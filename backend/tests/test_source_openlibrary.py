"""Open Library search and lending availability."""
import httpx
import pytest

from app.models import SearchQuery
from app.sources.base import SourceError
from app.sources.openlibrary import Availability, OpenLibrarySource

BASE = "https://openlibrary.test"


@pytest.fixture
def source_for(recorder):
    def build(**kwargs):
        rec = recorder(**kwargs)
        return OpenLibrarySource(client=rec.client, base_url=BASE), rec
    return build


def doc(**overrides):
    base = {"key": "/works/OL1W", "title": "A Book", "author_name": ["Some Author"],
            "language": ["eng"], "ebook_access": "public"}
    base.update(overrides)
    return base


def payload(*docs):
    return {"numFound": len(docs), "start": 0, "docs": list(docs)}


def test_source_name():
    assert OpenLibrarySource.name == "openlibrary"


class TestRequests:
    def test_free_text_uses_q_on_search_json(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("openlibrary-search.json"))
        source.search(SearchQuery(q="pride and prejudice"))
        assert rec.last.url.path == "/search.json"
        assert rec.params()["q"] == "pride and prejudice"

    def test_title_and_author_use_their_own_parameters(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("openlibrary-search-title-author.json"))
        source.search(SearchQuery(title="Pride and Prejudice", author="Austen"))
        params = rec.params()
        assert params["title"] == "Pride and Prejudice"
        assert params["author"] == "Austen"
        assert "q" not in params

    def test_keyword_is_a_general_query(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("openlibrary-search.json"))
        source.search(SearchQuery(keyword="whaling"))
        assert rec.params()["q"] == "whaling"

    @pytest.mark.parametrize("given", ["9780140430721", "0-14-043072-5"])
    def test_isbn_is_normalized_to_isbn13(self, source_for, sample_json, given):
        source, rec = source_for(json=sample_json("openlibrary-search.json"))
        source.search(SearchQuery(isbn=given))
        assert rec.params()["isbn"] == "9780140430721"

    def test_invalid_isbn_only_search_makes_no_request(self, source_for):
        source, rec = source_for(json=payload())
        assert source.search(SearchQuery(isbn="12345")) == []
        assert rec.requests == []

    @pytest.mark.parametrize("language, marc", [("es", "spa"), ("fr", "fre"), ("de", "ger"), ("en", "eng")])
    def test_language_filter_sends_a_marc_code(self, source_for, sample_json, language, marc):
        """`language=<MARC code>` filters works; `lang` only boosts editions in that language."""
        source, rec = source_for(json=sample_json("openlibrary-search.json"))
        source.search(SearchQuery(q="don quixote", language=language))
        assert rec.params()["language"] == marc
        assert rec.params()["lang"] == language

    def test_language_filter_works_with_title_and_author(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("openlibrary-search-title-author.json"))
        source.search(SearchQuery(title="Pride and Prejudice", author="Austen", language="fr"))
        assert rec.params()["language"] == "fre"
        assert "q" not in rec.params()

    def test_no_language_filter_when_none_requested(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("openlibrary-search.json"))
        source.search(SearchQuery(q="pride"))
        assert "language" not in rec.params()
        assert "lang" not in rec.params()

    def test_page_is_forwarded(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("openlibrary-search.json"))
        source.search(SearchQuery(q="x", page=2))
        assert rec.params()["page"] == "2"

    def test_asks_only_for_the_fields_it_maps(self, source_for, sample_json):
        """The full search response is huge (see samples/README.md)."""
        source, rec = source_for(json=sample_json("openlibrary-search.json"))
        source.search(SearchQuery(q="x"))
        fields = set(rec.params()["fields"].split(","))
        assert {"key", "title", "author_name", "cover_i", "ebook_access", "isbn",
                "language", "number_of_pages_median", "id_project_gutenberg",
                "id_librivox"} <= fields
        assert "limit" in rec.params()

    def test_audio_search_makes_no_request(self, source_for):
        source, rec = source_for(json=payload())
        assert source.search(SearchQuery(q="x", format="audio")) == []
        assert rec.requests == []


class TestMapping:
    @pytest.fixture
    def books(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("openlibrary-search.json"))
        return source.search(SearchQuery(q="pride and prejudice"))

    def test_sample_yields_three_works(self, books):
        assert [b.source_id for b in books] == ["OL66554W", "OL15165350W", "OL15093171W"]

    def test_book_fields(self, books):
        book = books[0]
        assert book.source == "openlibrary"
        assert book.title == "Pride and Prejudice"
        assert book.authors == ["Jane Austen"]
        assert book.format == "text"
        assert book.url == "https://openlibrary.org/works/OL66554W"
        assert book.cover_url == "https://covers.openlibrary.org/b/id/14348537-M.jpg"
        assert book.audio_seconds is None

    def test_language_is_unknown_when_a_work_has_many(self, books):
        assert books[0].language is None       # 27 languages across editions

    def test_language_is_the_filter_when_one_was_requested(self, source_for, sample_json):
        """Safe because the `language` parameter makes Open Library return only works with an edition in it."""
        source, _ = source_for(json=sample_json("openlibrary-search.json"))
        books = source.search(SearchQuery(q="pride", language="en"))
        assert {b.language for b in books} == {"en"}

    def test_single_language_work_uses_it(self, source_for):
        source, _ = source_for(json=payload(doc(language=["fre"])))
        assert source.search(SearchQuery(q="x"))[0].language == "fr"

    def test_public_and_borrowable_access(self, books):
        assert books[0].access == "open"          # ebook_access: public
        assert books[2].access == "borrow"        # ebook_access: borrowable

    @pytest.mark.parametrize("ebook_access, expected", [
        ("public", "open"),
        ("borrowable", "borrow"),
        ("printdisabled", "print_disabled"),
        ("no_ebook", "none"),
        ("something_new", "none"),
    ])
    def test_ebook_access_mapping(self, source_for, ebook_access, expected):
        source, _ = source_for(json=payload(doc(ebook_access=ebook_access)))
        assert source.search(SearchQuery(q="x"))[0].access == expected

    def test_missing_access_field_means_none(self, source_for):
        d = doc()
        del d["ebook_access"]
        source, _ = source_for(json=payload(d))
        assert source.search(SearchQuery(q="x"))[0].access == "none"

    def test_cross_references_to_other_sources_become_identifiers(self, books):
        assert books[0].identifiers["gutenberg"] == ["1342", "42671", "45186"]
        assert "253" in books[0].identifiers["librivox"]

    def test_isbns_are_normalized_deduplicated_and_validated(self, source_for):
        source, _ = source_for(json=payload(doc(
            isbn=["0140430725", "9780140430721", "9780140430721", "12345", "9783847406337"])))
        assert source.search(SearchQuery(q="x"))[0].identifiers["isbn"] == ["9780140430721"]

    def test_page_count(self, source_for):
        source, _ = source_for(json=payload(doc(number_of_pages_median=464)))
        assert source.search(SearchQuery(q="x"))[0].pages == 464

    def test_no_cover(self, source_for):
        source, _ = source_for(json=payload(doc()))
        assert source.search(SearchQuery(q="x"))[0].cover_url is None

    def test_doc_without_author(self, source_for):
        d = doc()
        del d["author_name"]
        source, _ = source_for(json=payload(d))
        assert source.search(SearchQuery(q="x"))[0].authors == []

    def test_docs_without_a_title_or_key_are_skipped(self, source_for):
        source, _ = source_for(json=payload(
            {"key": "/works/OL9W"}, {"title": "No key"}, doc(key="/works/OL5W")))
        assert [b.source_id for b in source.search(SearchQuery(q="x"))] == ["OL5W"]

    def test_title_author_sample_maps_cleanly(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("openlibrary-search-title-author.json"))
        books = source.search(SearchQuery(title="Pride and Prejudice", author="Austen"))
        assert books
        assert all(b.source_id.startswith("OL") and b.source_id.endswith("W") for b in books)
        assert all(b.title for b in books)

    def test_no_results(self, source_for):
        source, _ = source_for(json=payload())
        assert source.search(SearchQuery(q="zzzz")) == []


class TestAvailability:
    """Lending status for an ISBN (api/volumes/brief/isbn/<isbn>.json)."""

    def test_requests_the_brief_volumes_endpoint_with_isbn13(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("openlibrary-availability.json"))
        source.availability("0140430725")
        assert rec.last.url.path == "/api/volumes/brief/isbn/9780140430721.json"

    def test_full_access_wins_over_lendable(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("openlibrary-availability.json"))
        result = source.availability("9780140430721")
        assert isinstance(result, Availability)
        assert result.status == "open"
        assert result.url.startswith("http")

    def test_lendable_only_means_borrow(self, source_for, sample_json):
        data = sample_json("openlibrary-availability.json")
        data["items"] = [i for i in data["items"] if i["status"] == "lendable"]
        source, _ = source_for(json=data)
        assert source.availability("9780140430721").status == "borrow"

    def test_no_items_means_none(self, source_for):
        source, _ = source_for(json={"records": {}, "items": []})
        assert source.availability("9780140430721") is None

    def test_invalid_isbn_makes_no_request(self, source_for):
        source, rec = source_for(json={"records": {}, "items": []})
        assert source.availability("123") is None
        assert rec.requests == []


class TestErrors:
    @pytest.mark.parametrize("status", [500, 503])
    def test_server_errors_raise_source_error(self, source_for, status):
        source, _ = source_for(text="down", status=status)
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))

    def test_connection_failure_raises_source_error(self, source_for):
        source, _ = source_for(error=httpx.ConnectError("refused"))
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))

    def test_garbage_body_raises_source_error(self, source_for):
        source, _ = source_for(text="<html>oops</html>")
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))

    def test_availability_errors_raise_source_error(self, source_for):
        source, _ = source_for(text="down", status=500)
        with pytest.raises(SourceError):
            source.availability("9780140430721")
