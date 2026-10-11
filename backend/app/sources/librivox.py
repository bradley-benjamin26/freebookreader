"""LibriVox audiobooks (see api_librivox.documentation.md).

LibriVox has no keyword search and no language filter, matches `author` on the exact last name
only, and answers HTTP 500 when `title` and `author` are sent together. So every free-text or
title search is sent as `title=^<text>` (a title prefix match), and author and language are
filtered here after the response comes back.
"""
import re

import httpx

from app.models import Book, Chapter, SearchQuery
from app.normalize import NAME_SUFFIX, author_key, normalize_author_name, to_language_code
from app.sources.base import SourceError, get_json

PAGE_SIZE = 25   # extended responses list every section, so keep pages small
_GUTENBERG_ID = re.compile(r"gutenberg\.org/(?:etext|ebooks)/(\d+)")
# LibriVox catalogs titles without a leading article ("Time Machine", "Misérables - tome 1").
_LEADING_ARTICLE = re.compile(
    r"^(?:(?:the|a|an|le|la|les|un|une|der|die|das|ein|eine|el|los|las|il|lo|gli|de|het|een)\s+"
    r"|l['’]\s*)", re.I)


def _drop_leading_article(text: str) -> str:
    rest = _LEADING_ARTICLE.sub("", text.strip(), count=1)
    return rest if rest.strip() else text


class LibriVoxSource:
    name = "librivox"

    def __init__(self, client: httpx.Client, base_url: str):
        self.client = client
        self.base_url = base_url.rstrip("/")

    def search(self, query: SearchQuery) -> list[Book]:
        if query.format == "text":
            return []
        params = self._params(query)
        if params is None:
            return []
        data = get_json(self.client, f"{self.base_url}/api/feed/audiobooks", params,
                        not_found_is_empty=True)
        if data is None or _is_not_found(data):
            return []
        if not isinstance(data, dict) or not isinstance(data.get("books"), list):
            raise SourceError("librivox: unexpected response")
        books = [self._book(record) for record in data["books"]]
        if query.author and "title" in params:
            wanted = author_key(query.author).split()
            books = [b for b in books if _has_author(b, wanted)]
        if query.language:
            books = [b for b in books if b.language == query.language]
        return books

    @staticmethod
    def _params(query: SearchQuery) -> dict | None:
        params = {"format": "json", "extended": "1", "coverart": "1", "limit": str(PAGE_SIZE)}
        if query.page > 1:
            params["offset"] = str((query.page - 1) * PAGE_SIZE)
        text = query.title or query.q or query.keyword
        if text:
            params["title"] = f"^{_drop_leading_article(text)}"
        elif query.author:
            names = normalize_author_name(query.author).split()
            # "Charles Dickens Jr.": LibriVox matches the surname, so a trailing suffix would find nothing.
            while names and NAME_SUFFIX.match(names[-1]):
                names.pop()
            if not names:
                return None   # "(anon)", "(1812-1870)", "Jr.": no name left to search for
            params["author"] = names[-1]
        else:
            return None   # isbn only: LibriVox has no identifiers
        return params

    @staticmethod
    def _book(record: dict) -> Book:
        sections = record.get("sections") or []
        narrators: list[str] = []
        for section in sections:
            for reader in section.get("readers") or []:
                name = normalize_author_name(reader.get("display_name", ""))
                if name and name not in narrators:
                    narrators.append(name)
        identifiers = {}
        match = _GUTENBERG_ID.search(record.get("url_text_source") or "")
        if match:
            identifiers["gutenberg"] = [match.group(1)]
        return Book(
            source="librivox",
            source_id=str(record["id"]),
            title=record.get("title") or "Untitled",
            authors=_people(record.get("authors")),
            narrators=narrators,
            contributors=_people(record.get("translators")),
            language=to_language_code(record.get("language")),
            format="audio",
            audio_seconds=_seconds(record.get("totaltimesecs")),
            identifiers=identifiers,
            url=record.get("url_librivox") or f"https://librivox.org/?p={record['id']}",
            cover_url=record.get("coverart_jpg") or None,
            chapters=[Chapter(title=s.get("title") or f"Section {s.get('section_number', '')}".strip(),
                              url=s["listen_url"], duration_seconds=_seconds(s.get("playtime")))
                      for s in sections if s.get("listen_url")],
            access="open",
        )


def _is_not_found(data) -> bool:
    return isinstance(data, dict) and "could not be found" in str(data.get("error", ""))


def _people(people) -> list[str]:
    names = (normalize_author_name(f"{p.get('first_name', '')} {p.get('last_name', '')}")
             for p in people or [])
    return [n for n in names if n]


def _seconds(value) -> int | None:
    try:
        seconds = int(value)
    except (TypeError, ValueError):
        return None
    return seconds or None   # LibriVox uses 0 for "unknown"


def _has_author(book: Book, wanted: list[str]) -> bool:
    return any(set(wanted) <= set(author_key(a).split()) for a in book.authors)
