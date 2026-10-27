"""Gutenberg EPUBs as Readium Web Publications, for the web reader.

flutter_readium on web cannot open an .epub file. It wants a manifest.json that declares the EPUB profile,
with the book's files served next to it from the same origin (decision_reader.md, spike 9b/9c). The store
downloads the EPUB from gutenberg.org once, keeps it on disk, and builds the manifest from its package
document. Only files listed in the package are served.
"""
import os
import posixpath
import tempfile
import threading
import time
import zipfile
from collections.abc import Callable
from pathlib import Path
from urllib.parse import quote, unquote, urljoin, urlsplit
from xml.etree import ElementTree as ET

import httpx

from app.sanitize import sanitize_markup

EPUB_PROFILE = "https://readium.org/webpub-manifest/profiles/epub"
CONTEXT = "https://readium.org/webpub-manifest/context.jsonld"

MAX_DOWNLOAD_BYTES = 200 * 1024 * 1024
MAX_CACHE_BYTES = 2000 * 1024 * 1024
MAX_ENTRY_BYTES = 100 * 1024 * 1024
# Package files (container, OPF, nav, NCX) are parsed whole in memory, so they get a smaller limit.
MAX_PACKAGE_BYTES = 5 * 1024 * 1024
MAX_REDIRECTS = 5
# Highest Gutenberg book number accepted (the catalog is near 80,000 in 2026).
MAX_GUTENBERG_ID = 99_999_999
_MEMORY_SLOTS = 64
# Locks that keep two requests from downloading one book. A fixed set (book id mod 64) instead of one per
# id, which grew with every id ever asked for. Books that share a lock only wait for each other's download.
_BOOK_LOCKS = 64
# Files a browser runs as a page: they lose their scripts before they are served (app/sanitize.py).
_PAGE_TYPES = {"application/xhtml+xml", "text/html", "image/svg+xml"}
# How long the local catalog may take to answer before the book is simply asked for at Gutenberg.
CATALOG_TIMEOUT_SECONDS = 3

_CONTAINER = "{urn:oasis:names:tc:opendocument:xmlns:container}"
_OPF = "{http://www.idpf.org/2007/opf}"
_DC = "{http://purl.org/dc/elements/1.1/}"
_XHTML = "{http://www.w3.org/1999/xhtml}"
_NCX = "{http://www.daisy.org/z3986/2005/ncx/}"
_EPUB_TYPE = "{http://www.idpf.org/2007/ops}type"


class PublicationError(Exception):
    pass


class PublicationNotFound(PublicationError):
    """No such book at Gutenberg, or no such file in its package."""


class PublicationUnavailable(PublicationError):
    """Gutenberg failed, or the file is not a usable EPUB."""


class PublicationTimeout(PublicationError):
    pass


def gutenberg_manifest_path(book_id: int) -> str:
    return f"/publications/gutenberg/{book_id}/manifest.json"


# --- manifest -------------------------------------------------------------------------------------------

def _read_entry(archive: zipfile.ZipFile, name: str, limit: int) -> bytes:
    """An entry's bytes. Refuses one larger than `limit`, by its listed size and while reading (zip bombs)."""
    info = archive.getinfo(name)
    if info.file_size > limit:
        raise PublicationUnavailable(f"{name} is larger than {limit} bytes")
    with archive.open(info) as file:
        data = file.read(limit + 1)
    if len(data) > limit:
        raise PublicationUnavailable(f"{name} is larger than {limit} bytes")
    return data


def build_manifest(archive: zipfile.ZipFile, max_entry_bytes: int = MAX_PACKAGE_BYTES) -> dict:
    """A Readium Web Publication Manifest for an EPUB. Every href is relative to the zip root.

    The package files it reads may not be larger than `max_entry_bytes`.
    """
    try:
        container = ET.fromstring(_read_entry(archive, "META-INF/container.xml", max_entry_bytes))
        rootfile = container.find(f".//{_CONTAINER}rootfile")
        if rootfile is None or not rootfile.get("full-path"):
            raise PublicationUnavailable("container.xml names no package document")
        opf_path = rootfile.get("full-path")
        package = ET.fromstring(_read_entry(archive, opf_path, max_entry_bytes))
        return _manifest(archive, package, posixpath.dirname(opf_path), max_entry_bytes)
    except (KeyError, ET.ParseError, zipfile.BadZipFile, UnicodeDecodeError) as error:
        raise PublicationUnavailable(f"not a usable EPUB: {error}") from error


def _manifest(archive: zipfile.ZipFile, package: ET.Element, base: str, limit: int) -> dict:
    metadata = package.find(f"{_OPF}metadata")
    items_parent = package.find(f"{_OPF}manifest")
    if metadata is None or items_parent is None:
        raise PublicationUnavailable("package document has no metadata or manifest")
    items = {item.get("id"): item for item in items_parent.findall(f"{_OPF}item") if item.get("href")}
    epub2_cover = next((m.get("content") for m in metadata.findall(f"{_OPF}meta") if m.get("name") == "cover"), None)

    def link(item_id: str, item: ET.Element) -> dict:
        result = {"href": quote(_resolve(base, item.get("href"))), "type": item.get("media-type")}
        properties = (item.get("properties") or "").split()
        if "cover-image" in properties or item_id == epub2_cover:
            result["rel"] = "cover"
        elif "nav" in properties:
            result["rel"] = "contents"
        return result

    spine = [ref.get("idref") for ref in package.findall(f"{_OPF}spine/{_OPF}itemref")]
    in_spine = set(spine)
    return {
        "@context": CONTEXT,
        "metadata": {
            "@type": "http://schema.org/Book",
            "conformsTo": EPUB_PROFILE,
            "title": _text(metadata.find(f"{_DC}title")),
            "author": [_text(c) for c in metadata.findall(f"{_DC}creator") if _text(c)],
            "language": [_text(lang) for lang in metadata.findall(f"{_DC}language") if _text(lang)],
            "identifier": _text(metadata.find(f"{_DC}identifier")),
        },
        "links": [],
        "readingOrder": [link(i, items[i]) for i in spine if i in items],
        "resources": [link(i, item) for i, item in items.items() if i not in in_spine],
        "toc": _toc(archive, base, items, limit),
    }


def _toc(archive: zipfile.ZipFile, base: str, items: dict, limit: int) -> list[dict]:
    nav = next((i for i in items.values() if "nav" in (i.get("properties") or "").split()), None)
    if nav is not None:
        path = _resolve(base, nav.get("href"))
        root = ET.fromstring(_read_entry(archive, path, limit))
        for element in root.iter(f"{_XHTML}nav"):
            if element.get(_EPUB_TYPE) == "toc":
                ol = element.find(f"{_XHTML}ol")
                return _nav_entries(ol, posixpath.dirname(path)) if ol is not None else []
        return []
    ncx = next((i for i in items.values() if i.get("media-type") == "application/x-dtbncx+xml"), None)
    if ncx is not None:
        path = _resolve(base, ncx.get("href"))
        nav_map = ET.fromstring(_read_entry(archive, path, limit)).find(f"{_NCX}navMap")
        return _ncx_entries(nav_map, posixpath.dirname(path)) if nav_map is not None else []
    return []


def _nav_entries(ol: ET.Element, base: str) -> list[dict]:
    entries = []
    for li in ol.findall(f"{_XHTML}li"):
        anchor = li.find(f"{_XHTML}a")
        if anchor is None or not anchor.get("href"):
            continue
        entry = {"href": _toc_href(base, anchor.get("href")), "title": _text(anchor)}
        nested = li.find(f"{_XHTML}ol")
        children = _nav_entries(nested, base) if nested is not None else []
        if children:
            entry["children"] = children
        entries.append(entry)
    return entries


def _ncx_entries(parent: ET.Element, base: str) -> list[dict]:
    entries = []
    for point in parent.findall(f"{_NCX}navPoint"):
        content = point.find(f"{_NCX}content")
        if content is None or not content.get("src"):
            continue
        entry = {"href": _toc_href(base, content.get("src")),
                 "title": _text(point.find(f"{_NCX}navLabel/{_NCX}text"))}
        children = _ncx_entries(point, base)
        if children:
            entry["children"] = children
        entries.append(entry)
    return entries


def _resolve(base: str, href: str) -> str:
    """A package-relative href as a path from the zip root (decoded)."""
    return posixpath.normpath(posixpath.join(base, unquote(href.split("#")[0])))


def _toc_href(base: str, href: str) -> str:
    path, _, fragment = href.partition("#")
    result = quote(_resolve(base, path))
    return f"{result}#{fragment}" if fragment else result


def _text(element: ET.Element | None) -> str:
    return " ".join("".join(element.itertext()).split()) if element is not None else ""


# --- catalog --------------------------------------------------------------------------------------------

class GutendexCatalog:
    """Whether a Gutenberg id is a book with an EPUB, asked of our own Gutendex (no traffic to gutenberg.org).

    Called with a book id; returns True, False (not in the catalog, or no EPUB), or None when Gutendex
    cannot say (it is down or answers oddly): then the book is asked for at Gutenberg as before.
    """

    def __init__(self, client: httpx.Client, gutendex_url: str):
        self._client = client
        self._base_url = gutendex_url.rstrip("/")

    def __call__(self, book_id: int) -> bool | None:
        try:
            response = self._client.get(f"{self._base_url}/books/{book_id}/", timeout=CATALOG_TIMEOUT_SECONDS)
            if response.status_code == 404:
                return False
            if response.status_code != 200:
                return None
            formats = response.json()["formats"]
            if not isinstance(formats, dict):
                return None
            return "application/epub+zip" in formats
        except (httpx.HTTPError, ValueError, KeyError, TypeError):
            return None


# --- store ----------------------------------------------------------------------------------------------

class _Book:
    def __init__(self, path: Path, manifest: dict):
        self.path = path
        self.manifest = manifest
        self.types = {unquote(link["href"]): link["type"] or "application/octet-stream"
                      for link in manifest["readingOrder"] + manifest["resources"]}


class PublicationStore:
    """Downloads Gutenberg EPUBs on first use and keeps them in `cache_dir` (least recently used leave first)."""

    def __init__(self, client: httpx.Client, gutenberg_url: str, cache_dir: Path | str,
                 max_download_bytes: int = MAX_DOWNLOAD_BYTES, max_cache_bytes: int = MAX_CACHE_BYTES,
                 max_entry_bytes: int = MAX_ENTRY_BYTES,
                 catalog: Callable[[int], bool | None] | None = None):
        self._client = client
        self._catalog = catalog
        self._base_url = gutenberg_url.rstrip("/")
        self._host = urlsplit(self._base_url).hostname
        self._cache_dir = Path(cache_dir)
        self._max_download = max_download_bytes
        self._max_cache = max_cache_bytes
        self._max_entry = max_entry_bytes
        self._package_limit = min(max_entry_bytes, MAX_PACKAGE_BYTES)
        self._lock = threading.Lock()
        self._locks = [threading.Lock() for _ in range(_BOOK_LOCKS)]
        self._books: dict[int, _Book] = {}
        self._last_touch = 0

    def manifest(self, book_id: int) -> dict:
        return self._book(book_id).manifest

    def resource(self, book_id: int, href: str) -> tuple[bytes, str]:
        """The bytes and media type of a file listed in the package. `href` is decoded."""
        try:
            return self._resource(book_id, href)
        except FileNotFoundError:
            # Evicted by another request after the lookup: _book finds the file gone and downloads it again.
            with self._lock:
                self._books.pop(book_id, None)
            try:
                return self._resource(book_id, href)
            except FileNotFoundError as error:
                raise PublicationUnavailable(str(error)) from error

    def _resource(self, book_id: int, href: str) -> tuple[bytes, str]:
        book = self._book(book_id)
        media_type = book.types.get(href)
        if media_type is None:
            raise PublicationNotFound(href)
        try:
            with zipfile.ZipFile(book.path) as archive:
                info = archive.getinfo(href)
                if info.file_size > self._max_entry:
                    raise PublicationUnavailable(f"{href} is larger than {self._max_entry} bytes")
                with archive.open(info) as file:
                    data = file.read(self._max_entry + 1)
        except KeyError as error:
            raise PublicationNotFound(href) from error
        except FileNotFoundError:
            raise
        except (zipfile.BadZipFile, OSError) as error:
            raise PublicationUnavailable(str(error)) from error
        if len(data) > self._max_entry:
            raise PublicationUnavailable(f"{href} is larger than {self._max_entry} bytes")
        if media_type in _PAGE_TYPES:
            data = sanitize_markup(data)
        return data, media_type

    def _book(self, book_id: int) -> _Book:
        path = self._cache_dir / f"{book_id}.epub"
        # Before any lock or download: an id that is not a book is refused without asking Gutenberg. A book
        # on disk or in memory is not looked up (the catalog may have been rebuilt without it).
        if self._catalog is not None and book_id not in self._books and not path.exists():
            if self._catalog(book_id) is False:
                raise PublicationNotFound(f"{book_id} is not a book with an EPUB")
        with self._locks[book_id % _BOOK_LOCKS]:
            book = self._books.get(book_id)
            try:
                if book is not None and path.exists():
                    self._touch(path)
                    return book
                if path.exists():
                    self._touch(path)
                    book = _Book(path, _read_manifest(path, self._package_limit))
                else:
                    book = self._download(book_id, path)
            except FileNotFoundError:
                # Evicted by another request since the check above.
                book = self._download(book_id, path)
            with self._lock:
                if len(self._books) >= _MEMORY_SLOTS:
                    self._books.pop(next(iter(self._books)))
                self._books[book_id] = book
            return book

    def _download(self, book_id: int, path: Path) -> _Book:
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        fd, temp_name = tempfile.mkstemp(dir=self._cache_dir, suffix=".part")
        temp = Path(temp_name)
        try:
            with os.fdopen(fd, "wb") as file:
                self._fetch(f"{self._base_url}/ebooks/{book_id}.epub3.images", file)
            book = _Book(path, _read_manifest(temp, self._package_limit))
            os.replace(temp, path)
            self._touch(path)
        finally:
            temp.unlink(missing_ok=True)
        self._evict(keep=path)
        return book

    def _fetch(self, url: str, file) -> None:
        try:
            for _ in range(MAX_REDIRECTS + 1):
                if urlsplit(url).hostname != self._host:
                    raise PublicationUnavailable(f"refusing to download from {url}")
                with self._client.stream("GET", url, follow_redirects=False) as response:
                    if response.is_redirect:
                        url = urljoin(url, response.headers["location"])
                        continue
                    if response.status_code == 404:
                        raise PublicationNotFound(url)
                    if response.status_code != 200:
                        raise PublicationUnavailable(f"{url} answered {response.status_code}")
                    try:
                        length = int(response.headers.get("content-length") or 0)
                    except ValueError as error:
                        raise PublicationUnavailable(f"{url} sent a bad Content-Length") from error
                    if length > self._max_download:
                        raise PublicationUnavailable(f"{url} is larger than {self._max_download} bytes")
                    size = 0
                    for chunk in response.iter_bytes():
                        size += len(chunk)
                        if size > self._max_download:
                            raise PublicationUnavailable(f"{url} is larger than {self._max_download} bytes")
                        file.write(chunk)
                    return
            raise PublicationUnavailable(f"too many redirects from {url}")
        except httpx.TimeoutException as error:
            raise PublicationTimeout(str(error)) from error
        except httpx.HTTPError as error:
            raise PublicationUnavailable(str(error)) from error

    def _touch(self, path: Path) -> None:
        # Strictly increasing times, so the eviction order is right even within one clock tick.
        with self._lock:
            self._last_touch = max(time.time_ns(), self._last_touch + 1)
            now = self._last_touch
        os.utime(path, ns=(now, now))

    def _evict(self, keep: Path) -> None:
        with self._lock:
            files = sorted(self._cache_dir.glob("*.epub"), key=lambda p: p.stat().st_mtime_ns)
            total = sum(p.stat().st_size for p in files)
            for old in files:
                if total <= self._max_cache:
                    break
                if old == keep:
                    continue
                total -= old.stat().st_size
                old.unlink(missing_ok=True)
                self._books.pop(int(old.stem), None)


def _read_manifest(path: Path, max_entry_bytes: int = MAX_PACKAGE_BYTES) -> dict:
    try:
        with zipfile.ZipFile(path) as archive:
            return build_manifest(archive, max_entry_bytes)
    except zipfile.BadZipFile as error:
        raise PublicationUnavailable(f"not an EPUB: {error}") from error
