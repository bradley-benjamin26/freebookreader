"""Open Library search and lending availability (see api_openlibrary.documentation.md).

Open Library books always open at openlibrary.org, so the app links out. Only books a user can
read or borrow now are returned: the search asks for free or borrowable works, each links to the
edition that can be read, and editions on loan or otherwise unavailable are then dropped.
"""
import httpx
from pydantic import BaseModel

from app.models import Access, Book, SearchQuery
from app.normalize import (
    normalize_author_name, normalize_isbn, normalize_oclc, to_language_code, to_marc_language,
)
from app.sources.base import SourceError, get, get_json

PAGE_SIZE = 20
FIELDS = ",".join([
    "key", "title", "author_name", "cover_i", "ebook_access", "isbn", "oclc", "language",
    "number_of_pages_median", "id_project_gutenberg", "id_librivox",
    "editions", "editions.key", "editions.ebook_access",
])
# ebook_access is ordered no_ebook < printdisabled < borrowable < public. In `q`, this filter also
# makes the `editions` sub-query return a free or borrowable edition of each work.
READABLE = "ebook_access:[borrowable TO *]"
_ACCESS: dict[str, Access] = {"public": "open", "borrowable": "borrow"}
# availability/v2 statuses meaning "can be read or borrowed now"; others include borrow_unavailable
# (every copy on loan), private and error (no scan).
_AVAILABLE = {"open", "borrow_available"}


class Availability(BaseModel):
    status: Access
    url: str


class OpenLibrarySource:
    name = "openlibrary"

    def __init__(self, client: httpx.Client, base_url: str):
        self.client = client
        self.base_url = base_url.rstrip("/")

    def search(self, query: SearchQuery) -> list[Book]:
        if query.format == "audio":
            return []
        params = self._params(query)
        if params is None:
            return []
        response = get(self.client, f"{self.base_url}/search.json", params, ok_statuses=(422,))
        if response.status_code == 422:   # e.g. a q shorter than 3 characters: nothing to find
            return []
        try:
            data = response.json()
        except ValueError as error:
            raise SourceError("openlibrary: response is not JSON") from error
        if not isinstance(data, dict) or not isinstance(data.get("docs"), list):
            raise SourceError("openlibrary: unexpected response")
        # A record that is not an object is skipped; the rest of the answer is still good.
        books = [self._book(d) for d in data["docs"] if isinstance(d, dict) and d.get("key") and d.get("title")]
        books = self._available([b for b in books if b.access in ("open", "borrow")])
        if query.language:   # the `language` filter guarantees an edition in that language
            for book in books:
                book.language = query.language
        return books

    def _available(self, books: list[Book]) -> list[Book]:
        """Drop editions that cannot be read or borrowed right now (e.g. every copy on loan).

        availability/v2 is undocumented (Open Library's own pages use it), so if it fails, the
        books are kept as the search returned them.
        """
        editions = [_edition_id(b) for b in books]
        wanted = [e for e in editions if e]
        if not wanted:
            return books
        try:
            data = get_json(self.client, f"{self.base_url}/availability/v2",
                            {"type": "openlibrary_edition", "ids": ",".join(wanted)})
        except SourceError:
            return books
        if not isinstance(data, dict):
            return books
        statuses = {e: r.get("status") for e, r in data.items() if isinstance(r, dict)}
        return [b for b, e in zip(books, editions) if e not in statuses or statuses[e] in _AVAILABLE]

    def availability(self, isbn: str) -> Availability | None:
        """How the edition with this ISBN can be read on Open Library, or None."""
        isbn13 = normalize_isbn(isbn)
        if isbn13 is None:
            return None
        data = get_json(self.client, f"{self.base_url}/api/volumes/brief/isbn/{isbn13}.json", None)
        items = data.get("items") if isinstance(data, dict) else None
        if not items:
            return None
        for status, wanted in (("open", {"full access"}), ("borrow", {"lendable", "checked out"})):
            item = next((i for i in items if i.get("status") in wanted and i.get("itemURL")), None)
            if item:
                return Availability(status=status, url=item["itemURL"])
        return None

    @staticmethod
    def _params(query: SearchQuery) -> dict | None:
        params = {"fields": FIELDS, "limit": str(PAGE_SIZE)}
        text = " ".join(t for t in (query.q, query.keyword) if t)
        if text:
            params["q"] = text
        if query.title:
            params["title"] = query.title
        if query.author:
            params["author"] = query.author
        if query.isbn:
            isbn = normalize_isbn(query.isbn)
            if isbn:
                params["isbn"] = isbn
        if not ({"q", "title", "author", "isbn"} & params.keys()):
            return None   # only an invalid ISBN was given
        params["q"] = f"{params['q']} {READABLE}" if "q" in params else READABLE
        if query.language:
            marc = to_marc_language(query.language)
            if marc:
                params["language"] = marc
            params["lang"] = query.language
        if query.page > 1:
            params["page"] = str(query.page)
        return params

    @staticmethod
    def _book(doc: dict) -> Book:
        work_id = doc["key"].rsplit("/", 1)[-1]
        languages = {to_language_code(code) for code in doc.get("language") or []}
        identifiers = {}
        isbns = _unique(normalize_isbn(i) for i in doc.get("isbn") or [])
        if isbns:
            identifiers["isbn"] = isbns
        oclcs = _unique(normalize_oclc(o) for o in doc.get("oclc") or [])
        if oclcs:
            identifiers["oclc"] = oclcs
        for field, name in (("id_project_gutenberg", "gutenberg"), ("id_librivox", "librivox")):
            values = _unique(str(v) for v in doc.get(field) or [])
            if values:
                identifiers[name] = values
        cover = doc.get("cover_i")
        edition = _edition(doc)
        access = (edition or {}).get("ebook_access") or doc.get("ebook_access")
        return Book(
            source="openlibrary",
            source_id=work_id,
            title=doc["title"],
            authors=_unique(normalize_author_name(a) for a in _strings(doc.get("author_name"))),
            # A work lists the languages of all its editions; only a single one is usable.
            language=next(iter(languages)) if len(languages) == 1 else None,
            format="text",
            pages=doc.get("number_of_pages_median"),
            identifiers=identifiers,
            # The work page can feature an edition with no ebook; link the one that can be read.
            url=(f"https://openlibrary.org/books/{edition['key'].rsplit('/', 1)[-1]}" if edition
                 else f"https://openlibrary.org/works/{work_id}"),
            cover_url=f"https://covers.openlibrary.org/b/id/{cover}-M.jpg" if cover else None,
            access=_ACCESS.get(access, "none"),
        )


def _edition(doc: dict) -> dict | None:
    """The edition the `editions` sub-query picked for this work, or None."""
    editions = doc.get("editions")
    docs = editions.get("docs") if isinstance(editions, dict) else None
    first = docs[0] if isinstance(docs, list) and docs else None
    if isinstance(first, dict) and isinstance(first.get("key"), str) and first["key"].startswith("/books/"):
        return first
    return None


def _edition_id(book: Book) -> str | None:
    prefix = "https://openlibrary.org/books/"
    return book.url.removeprefix(prefix) if book.url.startswith(prefix) else None


def _unique(values) -> list[str]:
    seen: list[str] = []
    for value in values:
        if value and value not in seen:
            seen.append(value)
    return seen


def _strings(values) -> list[str]:
    """The text values of a list from the API, leaving out nulls and anything else."""
    return [v for v in values if isinstance(v, str)] if isinstance(values, list) else []
