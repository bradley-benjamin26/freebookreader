"""HTTP API the Flutter app talks to."""
from datetime import date

import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from app.models import SearchQuery
from app.search import SearchResponse
from tests.factories import make_book
from app.merge import merge_books


class StubService:
    def __init__(self, works=(), unavailable=()):
        self.works = list(works)
        self.unavailable = list(unavailable)
        self.queries: list[SearchQuery] = []

    def search(self, query):
        self.queries.append(query)
        return SearchResponse(works=self.works, unavailable_sources=self.unavailable)


@pytest.fixture
def works():
    return merge_books([
        make_book(source="gutenberg", source_id="1342", title="Pride and Prejudice",
                  authors=["Jane Austen"], content={"text/html": "https://g/1342.html"},
                  cover_url="https://g/cover.jpg", release_date=date(1998, 6, 1),
                  last_updated=date(2026, 9, 29), credits="Chuck Greif"),
        make_book(source="librivox", source_id="253", title="Pride and Prejudice",
                  authors=["Jane Austen"], format="audio", audio_seconds=47204),
    ])


@pytest.fixture
def stub(works):
    return StubService(works)


@pytest.fixture
def client(stub):
    return TestClient(create_app(search_service=stub))


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


class TestSearchEndpoint:
    def test_returns_works_and_unavailable_sources(self, stub, client):
        stub.unavailable = ["doab"]
        body = client.get("/search", params={"q": "pride"}).json()
        assert set(body) == {"works", "unavailable_sources"}
        assert body["unavailable_sources"] == ["doab"]
        assert len(body["works"]) == 1

    def test_work_json_shape(self, client):
        work = client.get("/search", params={"q": "pride"}).json()["works"][0]
        assert {"id", "title", "authors", "language", "sources", "source_ids", "identifiers",
                "urls", "cover_url", "formats", "books"} <= set(work)
        assert work["sources"] == ["gutenberg", "librivox"]
        assert work["formats"] == ["audio", "text"]

    def test_book_json_includes_how_to_read_it(self, client):
        books = client.get("/search", params={"q": "pride"}).json()["works"][0]["books"]
        text = next(b for b in books if b["format"] == "text")
        assert text["reading"] == {"mode": "in_app", "kind": "html", "url": "https://g/1342.html",
                                   "publication": None}
        audio = next(b for b in books if b["format"] == "audio")
        assert audio["reading"]["mode"] == "external"       # no chapters in this stub
        assert audio["audio_seconds"] == 47204

    def test_book_json_includes_edition_details(self, client):
        """ISO dates; null when the source does not say (only Gutenberg fills them)."""
        books = client.get("/search", params={"q": "pride"}).json()["works"][0]["books"]
        text = next(b for b in books if b["source"] == "gutenberg")
        assert text["release_date"] == "1998-06-01"
        assert text["last_updated"] == "2026-09-29"
        assert text["credits"] == "Chuck Greif"
        assert text["original_publication"] is None
        audio = next(b for b in books if b["source"] == "librivox")
        assert audio["release_date"] is None and audio["credits"] is None

    def test_query_parameters_reach_the_service(self, stub, client):
        client.get("/search", params={
            "title": "Hamlet", "author": "Shakespeare", "keyword": "tragedy", "isbn": "9780140430721",
            "language": "en", "format": "text", "sources": "gutenberg,doab", "page": 2})
        query = stub.queries[-1]
        assert (query.title, query.author, query.keyword) == ("Hamlet", "Shakespeare", "tragedy")
        assert query.isbn == "9780140430721"
        assert (query.language, query.format, query.page) == ("en", "text", 2)
        assert query.sources == ["gutenberg", "doab"]

    def test_q_only(self, stub, client):
        client.get("/search", params={"q": "dickens"})
        assert stub.queries[-1].q == "dickens"
        assert stub.queries[-1].sources is None

    def test_blank_sources_means_all_sources(self, stub, client):
        client.get("/search", params={"q": "dickens", "sources": ""})
        assert stub.queries[-1].sources is None

    def test_duplicate_sources_are_dropped(self, stub, client):
        client.get("/search", params={"q": "dickens", "sources": "doab,gutenberg,doab"})
        assert stub.queries[-1].sources == ["doab", "gutenberg"]

    @pytest.mark.parametrize("params", [
        {},                                   # nothing to search for
        {"q": "   "},
        {"q": "x", "format": "video"},
        {"q": "x", "sources": "hathitrust"},
        {"q": "x", "sources": ","},           # names no source at all
        {"q": "x", "sources": " , "},
        {"q": "x", "page": 0},
        {"q": "x", "page": "abc"},
        {"q": "x", "page": 10**9},
        {"q": "history " * 375},              # 3,000 characters
        {"title": "x" * 1000},
        {"author": "x" * 1000},
        {"keyword": "x" * 1000},
        {"isbn": "9" * 1000},
        {"q": "x", "language": "klingon"},
    ])
    def test_bad_requests_are_422(self, client, stub, params):
        assert client.get("/search", params=params).status_code == 422
        assert stub.queries == []

    def test_no_results_is_200_with_an_empty_list(self, stub, client):
        stub.works = []
        response = client.get("/search", params={"q": "zzzz"})
        assert response.status_code == 200
        assert response.json() == {"works": [], "unavailable_sources": []}

    def test_post_is_not_allowed(self, client):
        assert client.post("/search", json={"q": "x"}).status_code == 405


class TestSourcesEndpoint:
    def test_lists_the_four_sources_for_the_about_pages(self, client):
        body = client.get("/sources").json()
        assert sorted(s["id"] for s in body) == ["doab", "gutenberg", "librivox", "openlibrary"]
        for source in body:
            assert {"id", "name", "description", "how_it_works", "how_to_access",
                    "website_url", "donation_url", "formats", "in_app"} <= set(source)


def test_cors_allows_the_flutter_web_app(client):
    response = client.get("/health", headers={"Origin": "http://localhost:5000"})
    assert response.headers.get("access-control-allow-origin") in ("*", "http://localhost:5000")


def test_no_accounts_or_personal_data_endpoints_exist(client):
    """Privacy: the first version has no accounts and collects no personal data."""
    for path in ("/login", "/users", "/accounts", "/register", "/me"):
        assert client.get(path).status_code == 404


def test_gutenberg_epub_books_name_their_publication():
    works = merge_books([make_book(source="gutenberg", source_id="1342", title="Pride and Prejudice",
                                   authors=["Jane Austen"],
                                   content={"application/epub+zip": "https://g/1342.epub"})])
    client = TestClient(create_app(search_service=StubService(works)))
    book = client.get("/search", params={"q": "pride"}).json()["works"][0]["books"][0]
    assert book["reading"]["publication"] == "/publications/gutenberg/1342/manifest.json"
