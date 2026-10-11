"""Project Gutenberg through the self-hosted Gutendex API (see api_gutendex.documentation.md)."""
import re

import httpx

from app.models import Book, SearchQuery
from app.normalize import normalize_author_name
from app.sources.base import SourceError, get_json

# Formats the app can use; covers (image/jpeg), RDF and zip files are dropped.
_KEEP = ("text/html", "application/epub+zip", "text/plain", "audio/")


class GutendexSource:
    name = "gutenberg"

    def __init__(self, client: httpx.Client, base_url: str):
        self.client = client
        self.base_url = base_url.rstrip("/")

    def search(self, query: SearchQuery) -> list[Book]:
        params = self._params(query)
        if params is None:
            return []
        data = get_json(self.client, f"{self.base_url}/books/", params, not_found_is_empty=True)
        if data is None:
            return []
        if not isinstance(data, dict) or not isinstance(data.get("results"), list):
            raise SourceError("gutendex: unexpected response")
        books = [self._book(record, query.language) for record in data["results"]]
        if query.format:
            books = [b for b in books if b.format == query.format]
        return books

    @staticmethod
    def _params(query: SearchQuery) -> dict | None:
        search = " ".join(t for t in (query.q, query.title, query.author) if t)
        if not search and not query.keyword:
            return None   # isbn only: Gutendex cannot search identifiers
        params = {}
        if search:
            params["search"] = search
        if query.keyword:
            params["topic"] = query.keyword
        if query.language:
            params["languages"] = query.language
        if query.format == "audio":
            params["mime_type"] = "audio"
        if query.page > 1:
            params["page"] = str(query.page)
        return params

    @staticmethod
    def _book(record: dict, wanted_language: str | None = None) -> Book:
        book_id = str(record["id"])
        formats = record.get("formats") or {}
        languages = record.get("languages") or []
        if wanted_language in languages:   # a book in ["en", "fr"] is a French book to a French search
            languages = [wanted_language]
        return Book(
            source="gutenberg",
            source_id=book_id,
            title=_clean_title(record.get("title") or "Untitled"),
            authors=_names(record.get("authors")),
            contributors=_names(record.get("translators")) + _names(record.get("editors")),
            language=languages[0] if languages else None,
            format="audio" if record.get("media_type") == "Sound" else "text",
            url=f"https://www.gutenberg.org/ebooks/{book_id}",
            cover_url=formats.get("image/jpeg"),
            content={mime: url for mime, url in formats.items() if mime.startswith(_KEEP)},
            access="open",
        )


def _clean_title(title: str) -> str:
    """Drop MARC subfield markers: "Black Beauty : $b The autobiography" -> "Black Beauty: The autobiography"."""
    title = re.sub(r"\s*([:;/=])\s*\$[a-z]\s*", r"\1 ", title)
    return " ".join(re.sub(r"\$[a-z]\s*", "", title).split())


def _names(people) -> list[str]:
    names = (normalize_author_name(p.get("name", "")) for p in people or [])
    return [n for n in names if n]
