"""Gutenberg EPUBs served as Readium Web Publications, for the web reader (decision_reader.md, spike 9b/9c).

flutter_readium on web cannot open an .epub file: it wants a manifest.json (with the EPUB profile) and the
book's files next to it, all from one origin. The backend downloads the EPUB from gutenberg.org, caches it
on disk and serves both.
"""
import io
import threading
import time
import zipfile

import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import Settings, build_publication_store
from app.main import create_app
from app.publications import (EPUB_PROFILE, GutendexCatalog, PublicationNotFound, PublicationStore, PublicationTimeout,
                              PublicationUnavailable, build_manifest)
from tests.factories import make_epub
from tests.test_api import StubService

GUTENBERG = "https://www.gutenberg.org"
EPUB_URL = f"{GUTENBERG}/ebooks/1342.epub3.images"
CACHE_URL = f"{GUTENBERG}/cache/epub/1342/pg1342-images-3.epub"


def manifest_of(data: bytes) -> dict:
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        return build_manifest(archive)


class Gutenberg:
    """A fake gutenberg.org: /ebooks/<id>.epub3.images redirects to /cache/epub/..., like the real site."""

    def __init__(self, books=None, respond=None, delay=0.0):
        self.books = {1342: make_epub()} if books is None else books
        self.respond = respond
        self.delay = delay
        self.requests: list[httpx.Request] = []
        self.client = httpx.Client(transport=httpx.MockTransport(self._handle), follow_redirects=True)

    def _handle(self, request):
        self.requests.append(request)
        if self.delay:
            time.sleep(self.delay)
        if self.respond is not None:
            result = self.respond(request)
            if isinstance(result, Exception):
                raise result
            return result
        path = request.url.path
        if path.startswith("/ebooks/"):
            book_id = int(path.removeprefix("/ebooks/").split(".")[0])
            if book_id not in self.books:
                return httpx.Response(404, text="Not found")
            return httpx.Response(302, headers={"Location": f"/cache/epub/{book_id}/pg{book_id}-images-3.epub"})
        book_id = int(path.split("/")[3])
        return httpx.Response(200, content=self.books[book_id],
                              headers={"Content-Type": "application/epub+zip"})

    @property
    def downloads(self) -> int:
        return sum(1 for r in self.requests if r.url.path.startswith("/ebooks/"))


@pytest.fixture
def gutenberg():
    return Gutenberg()


@pytest.fixture
def store(gutenberg, tmp_path):
    return PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path / "epub")


@pytest.fixture
def api(store):
    return TestClient(create_app(search_service=StubService(), publication_store=store))


class TestManifest:
    def test_declares_the_epub_profile(self):
        # Without it flutter_readium uses its generic WebPub navigator, which ignores font size,
        # colours and page view (spike, 2026-10-10).
        manifest = manifest_of(make_epub())
        assert manifest["metadata"]["conformsTo"] == EPUB_PROFILE
        assert manifest["@context"] == "https://readium.org/webpub-manifest/context.jsonld"

    def test_metadata(self):
        metadata = manifest_of(make_epub())["metadata"]
        assert metadata["title"] == "Pride and Prejudice"
        assert metadata["author"] == ["Jane Austen"]
        assert metadata["language"] == ["en"]
        assert metadata["identifier"] == "http://www.gutenberg.org/1342"

    def test_reading_order_follows_the_spine_with_paths_from_the_zip_root(self):
        reading_order = manifest_of(make_epub())["readingOrder"]
        assert reading_order == [
            {"href": "OEBPS/text/ch1.xhtml", "type": "application/xhtml+xml"},
            {"href": "OEBPS/text/my%20chapter.xhtml", "type": "application/xhtml+xml"},
        ]

    def test_resources_are_the_other_manifest_items(self):
        resources = {r["href"]: r for r in manifest_of(make_epub())["resources"]}
        assert set(resources) == {"OEBPS/nav.xhtml", "OEBPS/toc.ncx", "OEBPS/css/style.css",
                                  "OEBPS/images/cover.jpg"}
        assert resources["OEBPS/css/style.css"]["type"] == "text/css"
        assert resources["OEBPS/images/cover.jpg"]["rel"] == "cover"
        assert resources["OEBPS/nav.xhtml"]["rel"] == "contents"

    def test_table_of_contents_from_the_epub3_nav_keeps_nesting_and_fragments(self):
        toc = manifest_of(make_epub())["toc"]
        assert toc == [{
            "href": "OEBPS/text/ch1.xhtml#c1", "title": "Chapter I.",
            "children": [{"href": "OEBPS/text/my%20chapter.xhtml", "title": "Part two"}],
        }]

    def test_table_of_contents_from_the_epub2_ncx(self):
        toc = manifest_of(make_epub(version=2))["toc"]
        assert toc == [
            {"href": "OEBPS/text/ch1.xhtml#c1", "title": "Chapter I."},
            {"href": "OEBPS/text/my%20chapter.xhtml", "title": "Part two"},
        ]

    def test_epub2_cover_comes_from_the_meta_element(self):
        data = make_epub(version=2)
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            opf = archive.read("OEBPS/content.opf").decode().replace(
                "<dc:language>en</dc:language>", '<dc:language>en</dc:language><meta name="cover" content="cover"/>')
        data = make_epub(version=2, extra={"OEBPS/content.opf": opf.encode()})
        resources = {r["href"]: r for r in manifest_of(data)["resources"]}
        assert resources["OEBPS/images/cover.jpg"]["rel"] == "cover"

    @pytest.mark.parametrize("broken", [
        {"META-INF/container.xml": b"not xml"},
        {"META-INF/container.xml": b"<container/>"},
        {"OEBPS/content.opf": b"<package/>"},
    ])
    def test_a_broken_epub_is_a_publication_error(self, broken):
        with pytest.raises(PublicationUnavailable):
            manifest_of(make_epub(extra=broken))


class TestEndpoints:
    def test_manifest(self, api):
        response = api.get("/publications/gutenberg/1342/manifest.json")
        assert response.status_code == 200
        assert response.headers["content-type"].startswith("application/webpub+json")
        assert response.json()["metadata"]["conformsTo"] == EPUB_PROFILE

    def test_resource_is_served_with_its_type_from_the_package(self, api):
        response = api.get("/publications/gutenberg/1342/OEBPS/css/style.css")
        assert response.status_code == 200
        assert response.headers["content-type"].startswith("text/css")
        assert response.content == b"body { margin: 0 }"

    def test_resource_with_an_encoded_name(self, api):
        response = api.get("/publications/gutenberg/1342/OEBPS/text/my%20chapter.xhtml")
        assert response.status_code == 200
        assert b"Part two" in response.content

    def test_book_files_cannot_run_on_the_api_origin(self, api):
        # A book page opened directly must not run scripts on our origin. Readium builds its own blob
        # documents from the fetched text, so the header does not protect the reader; see the next test.
        response = api.get("/publications/gutenberg/1342/OEBPS/text/ch1.xhtml")
        assert response.headers["content-security-policy"] == "sandbox"
        assert response.headers["x-content-type-options"] == "nosniff"

    def test_book_pages_are_served_without_scripts(self, tmp_path):
        """Review 2026-10-11-main #15: Readium rebuilds pages on the app's origin, where the header above does not
        apply, so the pages themselves lose anything that runs code (app/sanitize.py, tests in test_sanitize.py)."""
        page = b"<html><body><h1 id='c1' onclick='x()'>Chapter I.</h1><script>parent.localStorage.clear()</script></body></html>"
        gutenberg = Gutenberg(books={1342: make_epub(extra={"OEBPS/text/ch1.xhtml": page})})
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path)
        data, _ = store.resource(1342, "OEBPS/text/ch1.xhtml")
        assert data == b"<html><body><h1 id='c1'>Chapter I.</h1></body></html>"

    def test_other_files_are_served_as_they_are(self, tmp_path):
        css = b"body { margin: 0 } /* <script>not a page</script> */"
        gutenberg = Gutenberg(books={1342: make_epub(extra={"OEBPS/css/style.css": css})})
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path)
        assert store.resource(1342, "OEBPS/css/style.css")[0] == css

    def test_responses_allow_any_origin_by_default(self, api):
        response = api.get("/publications/gutenberg/1342/manifest.json", headers={"Origin": "http://localhost:8080"})
        assert response.headers["access-control-allow-origin"] == "*"

    @pytest.mark.parametrize("path", [
        "META-INF/container.xml",          # in the zip but not a publication resource
        "OEBPS/content.opf",
        "mimetype",
        "OEBPS/missing.xhtml",
        "%2e%2e/%2e%2e/etc/passwd",
    ])
    def test_only_files_listed_in_the_package_are_served(self, api, path):
        assert api.get(f"/publications/gutenberg/1342/{path}").status_code == 404

    @pytest.mark.parametrize("book_id", ["abc", "0", "-1", "1342.5", "100000000"])
    def test_book_id_must_be_a_gutenberg_number(self, api, gutenberg, book_id):
        assert api.get(f"/publications/gutenberg/{book_id}/manifest.json").status_code in (404, 422)
        assert gutenberg.requests == []

    def test_unknown_book_is_404(self, api):
        assert api.get("/publications/gutenberg/99999/manifest.json").status_code == 404

    def test_other_sources_are_404(self, api):
        assert api.get("/publications/librivox/1342/manifest.json").status_code == 404


class TestDownload:
    def test_fetches_the_epub3_with_images_from_gutenberg(self, store, gutenberg):
        store.manifest(1342)
        assert str(gutenberg.requests[0].url) == EPUB_URL
        assert str(gutenberg.requests[-1].url) == CACHE_URL

    def test_downloads_once_and_serves_from_the_cache(self, store, gutenberg):
        store.manifest(1342)
        store.resource(1342, "OEBPS/css/style.css")
        store.resource(1342, "OEBPS/text/ch1.xhtml")
        assert gutenberg.downloads == 1

    def test_cache_survives_a_new_store(self, store, gutenberg, tmp_path):
        store.manifest(1342)
        again = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path / "epub")
        again.manifest(1342)
        assert gutenberg.downloads == 1

    def test_parallel_requests_for_one_book_download_it_once(self, tmp_path):
        gutenberg = Gutenberg(delay=0.2)
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path)
        threads = [threading.Thread(target=store.manifest, args=(1342,)) for _ in range(5)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        assert gutenberg.downloads == 1

    def test_missing_book(self, store):
        with pytest.raises(PublicationNotFound):
            store.manifest(5)

    @pytest.mark.parametrize("href", ["OEBPS/../OEBPS/css/style.css", "../OEBPS/css/style.css",
                                      "/OEBPS/css/style.css", "OEBPS/css/style.css/"])
    def test_only_exact_package_paths_are_served(self, store, href):
        # HTTP clients usually remove "..", so the store checks paths itself.
        with pytest.raises(PublicationNotFound):
            store.resource(1342, href)

    def test_missing_resource(self, store):
        with pytest.raises(PublicationNotFound):
            store.resource(1342, "OEBPS/nothing.css")

    @pytest.mark.parametrize("status", [500, 503, 403])
    def test_gutenberg_error_is_unavailable(self, tmp_path, status):
        gutenberg = Gutenberg(respond=lambda r: httpx.Response(status))
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path)
        with pytest.raises(PublicationUnavailable):
            store.manifest(1342)

    def test_a_content_length_that_is_not_a_number_is_unavailable(self, tmp_path):
        """Review 2026-10-11-main #5: int() of the header raised, which became a 500."""
        def respond(request):
            return httpx.Response(200, content=make_epub(), headers={"Content-Length": "not-a-number"})
        gutenberg = Gutenberg(respond=respond)
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path)
        with pytest.raises(PublicationUnavailable):
            store.manifest(1342)

    def test_connection_failure_is_unavailable(self, tmp_path):
        gutenberg = Gutenberg(respond=lambda r: httpx.ConnectError("refused"))
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path)
        with pytest.raises(PublicationUnavailable):
            store.manifest(1342)

    def test_timeout(self, tmp_path):
        gutenberg = Gutenberg(respond=lambda r: httpx.ReadTimeout("slow"))
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path)
        with pytest.raises(PublicationTimeout):
            store.manifest(1342)

    def test_not_a_zip_is_unavailable_and_not_cached(self, tmp_path):
        gutenberg = Gutenberg(books={1342: b"<html>Sorry</html>"})
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path)
        with pytest.raises(PublicationUnavailable):
            store.manifest(1342)
        gutenberg.books[1342] = make_epub()
        assert store.manifest(1342)["metadata"]["title"] == "Pride and Prejudice"

    def test_too_large_download_is_refused(self, tmp_path):
        gutenberg = Gutenberg()
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path,
                                 max_download_bytes=100)
        with pytest.raises(PublicationUnavailable):
            store.manifest(1342)
        assert list(tmp_path.glob("*.epub")) == []

    def test_redirect_away_from_gutenberg_is_refused(self, tmp_path):
        def respond(request):
            if request.url.host == "www.gutenberg.org":
                return httpx.Response(302, headers={"Location": "https://evil.example/book.epub"})
            return httpx.Response(200, content=make_epub())
        gutenberg = Gutenberg(respond=respond)
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path)
        with pytest.raises(PublicationUnavailable):
            store.manifest(1342)

    def test_entry_larger_than_the_limit_is_unavailable(self, tmp_path):
        # Zip bombs: a small download can hold a huge file. The size in the zip directory is checked
        # before reading, and reading stops at the limit whatever the directory says.
        big = b"a" * 5000
        gutenberg = Gutenberg(books={1342: make_epub(extra={"OEBPS/css/style.css": big})})
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path,
                                 max_entry_bytes=1000)
        store.manifest(1342)
        with pytest.raises(PublicationUnavailable):
            store.resource(1342, "OEBPS/css/style.css")

    @pytest.mark.parametrize("version, name", [
        (3, "META-INF/container.xml"), (3, "OEBPS/content.opf"), (3, "OEBPS/nav.xhtml"),
        (2, "OEBPS/toc.ncx"),
    ])
    def test_package_file_larger_than_the_limit_is_unavailable_and_not_cached(self, tmp_path, version, name):
        # The files the manifest is built from are read whole to be parsed, so they get the limit too.
        with zipfile.ZipFile(io.BytesIO(make_epub(version=version))) as archive:
            original = archive.read(name)
        padded = original + b"<!-- " + b"a" * 5000 + b" -->"
        gutenberg = Gutenberg(books={1342: make_epub(version=version, extra={name: padded})})
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path,
                                 max_entry_bytes=1000)
        with pytest.raises(PublicationUnavailable):
            store.manifest(1342)
        assert list(tmp_path.glob("*.epub")) == []

    def test_least_recently_used_books_leave_the_cache_when_it_is_full(self, tmp_path):
        epub = make_epub()
        gutenberg = Gutenberg(books={1: epub, 2: epub, 3: epub})
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path,
                                 max_cache_bytes=len(epub) * 2)
        store.manifest(1)
        store.manifest(2)
        store.resource(1, "OEBPS/css/style.css")   # 1 is now newer than 2
        store.manifest(3)
        assert sorted(p.name for p in tmp_path.glob("*.epub")) == ["1.epub", "3.epub"]


class TestUnknownBooks:
    """Review 2026-10-11, #19: any id up to 99,999,999 made us ask gutenberg.org, and every id left a lock behind."""

    def store_with(self, tmp_path, catalog, books=None):
        gutenberg = Gutenberg(books=books)
        store = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path,
                                 catalog=catalog)
        return store, gutenberg

    def test_a_book_the_catalog_does_not_know_is_not_asked_for_at_gutenberg(self, tmp_path):
        store, gutenberg = self.store_with(tmp_path, catalog=lambda book_id: False)
        for _ in range(3):
            with pytest.raises(PublicationNotFound):
                store.manifest(99999999)
        assert gutenberg.requests == []

    def test_a_book_the_catalog_knows_is_downloaded(self, tmp_path):
        store, gutenberg = self.store_with(tmp_path, catalog=lambda book_id: book_id == 1342)
        assert store.manifest(1342)["metadata"]["title"] == "Pride and Prejudice"
        assert gutenberg.downloads == 1

    def test_when_the_catalog_cannot_say_the_book_is_asked_for_as_before(self, tmp_path):
        """The local Gutendex may be down: that must not stop books from opening."""
        store, gutenberg = self.store_with(tmp_path, catalog=lambda book_id: None)
        assert store.manifest(1342)["metadata"]["title"] == "Pride and Prejudice"
        with pytest.raises(PublicationNotFound):
            store.manifest(5)
        assert gutenberg.downloads == 2

    def test_a_cached_book_is_not_looked_up_again(self, tmp_path):
        asked = []
        store, _ = self.store_with(tmp_path, catalog=lambda book_id: asked.append(book_id) or True)
        store.manifest(1342)
        store.resource(1342, "OEBPS/css/style.css")
        store.manifest(1342)
        assert asked == [1342]

    def test_a_book_cached_on_disk_opens_even_if_the_catalog_forgot_it(self, tmp_path):
        first, gutenberg = self.store_with(tmp_path, catalog=lambda book_id: True)
        first.manifest(1342)
        again = PublicationStore(client=gutenberg.client, gutenberg_url=GUTENBERG, cache_dir=tmp_path,
                                 catalog=lambda book_id: False)
        assert again.manifest(1342)["metadata"]["title"] == "Pride and Prejudice"

    def test_asking_for_many_unknown_books_does_not_grow_the_locks(self, tmp_path):
        store, _ = self.store_with(tmp_path, catalog=lambda book_id: False)
        locks = len(store._locks)
        for book_id in range(1, 2000):
            with pytest.raises(PublicationNotFound):
                store.manifest(book_id)
        assert len(store._locks) == locks == 64

    def test_books_that_share_a_lock_still_download(self, tmp_path):
        epub = make_epub()
        store, gutenberg = self.store_with(tmp_path, catalog=lambda book_id: True,
                                           books={1: epub, 65: epub, 129: epub})   # 1, 65 and 129 are 1 mod 64
        for book_id in (1, 65, 129):
            store.manifest(book_id)
        assert gutenberg.downloads == 3


class TestGutendexCatalog:
    def catalog(self, respond):
        seen = []

        def handle(request):
            seen.append(request.url.path)
            result = respond(request)
            if isinstance(result, Exception):
                raise result
            return result

        client = httpx.Client(transport=httpx.MockTransport(handle))
        return GutendexCatalog(client, "http://localhost:8001/"), seen

    def test_a_book_with_an_epub_exists(self):
        catalog, seen = self.catalog(lambda r: httpx.Response(
            200, json={"id": 1342, "formats": {"application/epub+zip": "https://g/1342.epub3.images"}}))
        assert catalog(1342) is True
        assert seen == ["/books/1342/"]

    def test_a_book_without_an_epub_does_not(self):
        catalog, _ = self.catalog(lambda r: httpx.Response(200, json={"id": 7, "formats": {"text/html": "x"}}))
        assert catalog(7) is False

    def test_an_unknown_id_does_not(self):
        catalog, _ = self.catalog(lambda r: httpx.Response(404, json={"detail": "Not found."}))
        assert catalog(99999999) is False

    @pytest.mark.parametrize("respond", [
        lambda r: httpx.Response(500),
        lambda r: httpx.Response(503),
        lambda r: httpx.ConnectError("refused"),
        lambda r: httpx.ReadTimeout("slow"),
        lambda r: httpx.Response(200, text="<html>not json</html>"),
        lambda r: httpx.Response(200, json=["not", "a", "book"]),
        lambda r: httpx.Response(200, json={"formats": "oops"}),
    ])
    def test_when_gutendex_cannot_say_the_answer_is_unknown(self, respond):
        catalog, _ = self.catalog(respond)
        assert catalog(1342) is None


def test_the_configured_store_checks_the_local_gutendex(tmp_path):
    settings = Settings.from_env({"FBR_GUTENDEX_URL": "http://gutendex.invalid", "FBR_EPUB_CACHE_DIR": str(tmp_path)})
    store = build_publication_store(settings, httpx.Client())
    assert isinstance(store._catalog, GutendexCatalog)


@pytest.mark.parametrize("error, status", [
    (PublicationNotFound("x"), 404),
    (PublicationUnavailable("x"), 502),
    (PublicationTimeout("x"), 504),
])
def test_errors_map_to_http_statuses(error, status):
    class FailingStore:
        def manifest(self, book_id):
            raise error

        def resource(self, book_id, href):
            raise error

    api = TestClient(create_app(search_service=StubService(), publication_store=FailingStore()))
    assert api.get("/publications/gutenberg/1342/manifest.json").status_code == status
    assert api.get("/publications/gutenberg/1342/OEBPS/a.css").status_code == status
