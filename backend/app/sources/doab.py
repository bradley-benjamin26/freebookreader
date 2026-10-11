"""DOAB, the Directory of Open Access Books (see api_doab.documentation.md).

DOAB's REST API rejects our IP, so a search takes two steps that both work:
1. OpenSearch (`/open-search/discover`, Atom) finds the matching records' handles, in relevance order.
2. OAI-PMH `GetRecord` in the `xoai` format gives each record's metadata, cover and download link.
The download link usually points at the PDF in the OAPEN Library; a PDF opens in the app and any
other link (a publisher's page) is left to the DOAB record page. Chapters are not books.
"""
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlparse

import httpx

from app.models import Book, SearchQuery
from app.normalize import normalize_author_name, normalize_isbn, normalize_oclc, to_language_code
from app.sources.base import SourceError, get

PAGE_SIZE = 20
LOOKUP_THREADS = 10
# Links shown to users always point at the public site, whatever base_url the API is reached on.
PUBLIC_URL = "https://directory.doabooks.org"

_ATOM = "{http://www.w3.org/2005/Atom}"
_OAI = "{http://www.openarchives.org/OAI/2.0/}"
_XOAI = "{http://www.lyncode.com/xoai}"


class DoabSource:
    name = "doab"

    def __init__(self, client: httpx.Client, base_url: str):
        self.client = client
        self.base_url = base_url.rstrip("/")

    def search(self, query: SearchQuery) -> list[Book]:
        if query.format == "audio":
            return []
        isbn = normalize_isbn(query.isbn) if query.isbn else None
        terms = [t for t in (query.q, query.title, query.author, query.keyword, isbn) if t]
        if not terms:
            return []
        params = {"query": " ".join(terms), "rpp": str(PAGE_SIZE), "start": str((query.page - 1) * PAGE_SIZE)}
        response = get(self.client, f"{self.base_url}/open-search/discover", params)
        hits = self.parse_opensearch(response.text)
        if not hits:
            return []
        with ThreadPoolExecutor(max_workers=min(LOOKUP_THREADS, len(hits))) as pool:
            found = list(pool.map(self._lookup, hits))
        books = [book for book in found if book is not None]
        if query.language:
            books = [b for b in books if b.language == query.language]
        return books

    def _lookup(self, hit: Book) -> Book | None:
        """The full record for a search hit. None if DOAB no longer has it (stale search index)."""
        params = {"verb": "GetRecord", "metadataPrefix": "xoai",
                  "identifier": f"oai:doabooks.org:{hit.source_id}"}   # the documented form
        try:
            response = get(self.client, f"{self.base_url}/oai/request", params)
            if _oai_error(response.text) == "idDoesNotExist":
                return None
            books = self.parse_xoai(response.text)
        except SourceError:
            return hit   # the search worked; show what it said rather than nothing
        if not books:
            return None   # a chapter, or a deleted record
        return books[0]

    @staticmethod
    def parse_opensearch(xml: str) -> list[Book]:
        """Search hits (handle, title, authors) from an OpenSearch Atom feed, in result order."""
        root = _parse(xml)
        if root.tag != f"{_ATOM}feed":
            raise SourceError("doab: OpenSearch response is not an Atom feed")
        hits = []
        for entry in root.iter(f"{_ATOM}entry"):
            handle = (entry.findtext(f"{_ATOM}id") or "").split("/handle/", 1)[-1].strip()
            title = (entry.findtext(f"{_ATOM}title") or "").strip()
            if not handle or "/" not in handle or not title or title == "Untitled":
                continue
            authors = [n.text for n in entry.iter(f"{_ATOM}name") if n.text and n.text.strip()]
            hits.append(_book(handle=handle, title=title, authors=authors))
        return hits

    @staticmethod
    def parse_xoai(xml: str) -> list[Book]:
        """Books in an OAI-PMH GetRecord or ListRecords response in the xoai format.
        Deleted records and chapters are skipped."""
        root = _parse(xml)
        books = []
        for record in root.iter(f"{_OAI}record"):
            header = record.find(f"{_OAI}header")
            if header is None or header.get("status") == "deleted":
                continue
            fields = _xoai_fields(record)
            if "chapter" in [t.lower() for t in fields.get("dc.type", [])]:
                continue
            handle = (fields.get("others.handle") or [""])[0] or \
                (header.findtext(f"{_OAI}identifier") or "").rsplit(":", 1)[-1]
            titles = fields.get("dc.title", [])
            if not handle or not titles:
                continue
            pdf = next((u for u in fields.get("bundles.download", []) if _is_pdf(u)), None)
            books.append(_book(
                handle=handle, title=titles[0],
                authors=fields.get("dc.contributor.author", []),
                contributors=fields.get("dc.contributor.editor", []),
                language=(fields.get("dc.language") or [None])[0],
                isbns=fields.get("oapen.relation.isbn", []),
                dois=fields.get("oapen.identifier.doi", []),
                oclcs=[i.split(":", 1)[1] for i in fields.get("dc.identifier", []) if i.upper().startswith("OCN:")],
                pages=(fields.get("oapen.pages") or [None])[0],
                content={"application/pdf": pdf} if pdf else {},
                cover_url=(fields.get("bundles.thumbnail") or [None])[0],
            ))
        return books


def _parse(xml: str) -> ET.Element:
    try:
        return ET.fromstring(xml)
    except ET.ParseError as error:
        raise SourceError(f"doab: malformed XML: {error}") from error


def _oai_error(xml: str) -> str | None:
    try:
        error = ET.fromstring(xml).find(f"{_OAI}error")
    except ET.ParseError:
        return None
    return error.get("code") if error is not None else None


def _xoai_fields(record: ET.Element) -> dict[str, list[str]]:
    """Flatten xoai's nested <element name=...> tree into {"dc.contributor.author": [...], ...}.

    Metadata values sit under a language element ("none", "en", ...), which is dropped from the key.
    Bitstreams are summarised as "bundles.thumbnail" (cover URLs) and "bundles.download" (full-text links).
    """
    fields: dict[str, list[str]] = {}
    metadata = record.find(f"{_OAI}metadata/{_XOAI}metadata")
    if metadata is None:
        return fields
    for top in metadata.findall(f"{_XOAI}element"):
        if top.get("name") == "bundles":
            _bundle_fields(top, fields)
        elif top.get("name") == "others":
            for field in top.findall(f"{_XOAI}field"):
                _add(fields, f"others.{field.get('name')}", field.text)
        else:
            _walk(top, [top.get("name")], fields)
    return fields


def _walk(element: ET.Element, path: list[str], fields: dict[str, list[str]]) -> None:
    for child in element.findall(f"{_XOAI}element"):
        name = child.get("name")
        values = [f.text for f in child.findall(f"{_XOAI}field") if f.get("name") == "value"]
        if values:   # a language element: its parent's path is the key
            for value in values:
                _add(fields, ".".join(path), value)
        _walk(child, path + [name], fields)


def _bundle_fields(bundles: ET.Element, fields: dict[str, list[str]]) -> None:
    for bundle in bundles.findall(f"{_XOAI}element"):
        bundle_name = bundle.findtext(f"{_XOAI}field[@name='name']")
        for stream in bundle.iter(f"{_XOAI}element"):
            if stream.get("name") != "bitstream":
                continue
            url = stream.findtext(f"{_XOAI}field[@name='url']") or ""
            # Books without a cover get DOAB's "open-access-no-cover.png" placeholder; that is no cover.
            if bundle_name == "THUMBNAIL" and "no-cover" not in url:
                _add(fields, "bundles.thumbnail", url)
            _add(fields, "bundles.download", stream.findtext(f"{_XOAI}field[@name='oapenidentifierdownloadUrl']"))


def _add(fields: dict[str, list[str]], key: str, value: str | None) -> None:
    value = (value or "").strip()
    if value and value not in fields.setdefault(key, []):
        fields[key].append(value)


def _is_pdf(url: str) -> bool:
    return urlparse(url).path.lower().endswith(".pdf")


def _book(*, handle, title, authors, contributors=(), language=None, isbns=(), dois=(), oclcs=(),
          pages=None, content=None, cover_url=None) -> Book:
    identifiers = {}
    for key, values in (("isbn", [normalize_isbn(i) for i in isbns]),
                        ("oclc", [normalize_oclc(o) for o in oclcs]),
                        ("doi", list(dois))):
        unique = list(dict.fromkeys(v for v in values if v))
        if unique:
            identifiers[key] = unique
    return Book(
        source="doab",
        source_id=handle,
        title=" ".join(title.split()),
        authors=[n for n in (normalize_author_name(a) for a in authors) if n],
        contributors=[n for n in (normalize_author_name(c) for c in contributors) if n],
        language=to_language_code(language),
        format="text",
        pages=int(pages) if pages and str(pages).isdigit() else None,
        identifiers=identifiers,
        url=f"{PUBLIC_URL}/handle/{handle}",
        cover_url=cover_url,
        content=content or {},
        access="open",   # everything in DOAB is open access
    )
