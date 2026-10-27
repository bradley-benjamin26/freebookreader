"""Open Library search and lending availability."""
import httpx
import pytest

from app.models import SearchQuery
from app.sources.base import SourceError
from app.sources.openlibrary import OpenLibrarySource

BASE = "https://openlibrary.test"
READABLE = "ebook_access:[borrowable TO *]"


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
        assert rec.params()["q"] == f"pride and prejudice {READABLE}"

    def test_title_and_author_use_their_own_parameters(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("openlibrary-search-title-author.json"))
        source.search(SearchQuery(title="Pride and Prejudice", author="Austen"))
        params = rec.params()
        assert params["title"] == "Pride and Prejudice"
        assert params["author"] == "Austen"
        assert params["q"] == READABLE

    def test_keyword_is_a_general_query(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("openlibrary-search.json"))
        source.search(SearchQuery(keyword="whaling"))
        assert rec.params()["q"] == f"whaling {READABLE}"

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
        assert rec.params()["q"] == READABLE

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
                "id_librivox", "editions", "editions.key", "editions.ebook_access"} <= fields
        assert "limit" in rec.params()

    @pytest.mark.parametrize("query", [
        SearchQuery(q="frankenstein"), SearchQuery(title="Frankenstein"),
        SearchQuery(author="Koontz"), SearchQuery(isbn="0553587889"),
    ])
    def test_asks_only_for_free_or_borrowable_books(self, source_for, query):
        """Open Library orders ebook_access no_ebook < printdisabled < borrowable < public. The filter in `q`
        also makes the `editions` sub-query return a free or borrowable edition."""
        source, rec = source_for(json=payload())
        source.search(query)
        assert rec.params()["q"].endswith(READABLE)

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

    @pytest.mark.parametrize("ebook_access, expected", [("public", "open"), ("borrowable", "borrow")])
    def test_ebook_access_mapping(self, source_for, ebook_access, expected):
        source, _ = source_for(json=payload(doc(ebook_access=ebook_access)))
        assert source.search(SearchQuery(q="x"))[0].access == expected

    @pytest.mark.parametrize("ebook_access", ["printdisabled", "no_ebook", "something_new"])
    def test_books_that_cannot_be_read_or_borrowed_are_dropped(self, source_for, ebook_access):
        """In case Open Library ignores the filter: a user can do nothing with these."""
        source, _ = source_for(json=payload(doc(ebook_access=ebook_access), doc(key="/works/OL2W")))
        assert [b.source_id for b in source.search(SearchQuery(q="x"))] == ["OL2W"]

    def test_missing_access_field_is_dropped(self, source_for):
        d = doc()
        del d["ebook_access"]
        source, _ = source_for(json=payload(d))
        assert source.search(SearchQuery(q="x")) == []

    def test_links_to_the_edition_that_can_be_read_or_borrowed(self, source_for, sample_json):
        """The work page can feature an edition with no ebook (/works/OL497167W showed one)."""
        source, _ = source_for(json=sample_json("openlibrary-search-borrowable.json"))
        book = source.search(SearchQuery(q="dean koontz frankenstein"))[0]
        assert book.source_id == "OL497167W"
        assert book.url == "https://openlibrary.org/books/OL23273427M"
        assert book.access == "borrow"

    def test_access_comes_from_the_edition(self, source_for):
        source, _ = source_for(json=payload(doc(ebook_access="public", editions={"docs": [
            {"key": "/books/OL7M", "ebook_access": "borrowable"}]})))
        assert source.search(SearchQuery(q="x"))[0].access == "borrow"

    def test_an_edition_that_cannot_be_borrowed_is_dropped(self, source_for):
        source, _ = source_for(json=payload(doc(ebook_access="borrowable", editions={"docs": [
            {"key": "/books/OL7M", "ebook_access": "no_ebook"}]})))
        assert source.search(SearchQuery(q="x")) == []

    @pytest.mark.parametrize("editions", [None, {"docs": []}, {"docs": [{"title": "no key"}]}, "junk"])
    def test_without_an_edition_the_work_is_linked(self, source_for, editions):
        source, _ = source_for(json=payload(doc(editions=editions)))
        assert source.search(SearchQuery(q="x"))[0].url == "https://openlibrary.org/works/OL1W"

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


def edition_doc(work, edition, ebook_access="borrowable"):
    return doc(key=f"/works/{work}", ebook_access=ebook_access,
               editions={"docs": [{"key": f"/books/{edition}", "ebook_access": ebook_access}]})


class TestLoanStatus:
    """Right after the search, one availability/v2 call drops editions that cannot be borrowed now."""

    @pytest.fixture
    def source_with(self, recorder):
        def build(search, statuses=None, status_reply=None):
            def respond(request):
                if request.url.path == "/search.json":
                    return httpx.Response(200, json=search)
                if status_reply is not None:
                    return status_reply
                return httpx.Response(200, json={k: {"status": v} for k, v in (statuses or {}).items()})
            rec = recorder(respond=respond)
            return OpenLibrarySource(client=rec.client, base_url=BASE), rec
        return build

    def test_asks_once_for_every_edition(self, source_with):
        source, rec = source_with(payload(edition_doc("OL1W", "OL1M"), edition_doc("OL2W", "OL2M")))
        source.search(SearchQuery(q="x"))
        assert len(rec.requests) == 2
        assert rec.last.url.path == "/availability/v2"
        assert rec.params() == {"type": "openlibrary_edition", "ids": "OL1M,OL2M"}

    def test_keeps_borrowable_and_open_drops_the_rest(self, source_with):
        source, _ = source_with(
            payload(edition_doc("OL1W", "OL1M"), edition_doc("OL2W", "OL2M"), edition_doc("OL3W", "OL3M"),
                    edition_doc("OL4W", "OL4M", "public"), edition_doc("OL5W", "OL5M"),
                    edition_doc("OL6W", "OL6M")),
            {"OL1M": "borrow_available", "OL2M": "borrow_unavailable", "OL3M": "error",
             "OL4M": "open", "OL5M": "private"})
        assert [b.source_id for b in source.search(SearchQuery(q="x"))] == ["OL1W", "OL4W", "OL6W"]

    def test_sample_answer(self, source_with, sample_json):
        """OL3311782M (a hardcover with no scan) answers status "error"."""
        statuses = sample_json("openlibrary-availability-v2.json")
        source, _ = source_with(payload(edition_doc("OL1W", "OL23273427M"), edition_doc("OL2W", "OL3311782M"),
                                        edition_doc("OL3W", "OL50444320M", "public")),
                                status_reply=httpx.Response(200, json=statuses))
        assert [b.source_id for b in source.search(SearchQuery(q="x"))] == ["OL1W", "OL3W"]

    def test_no_editions_means_no_second_request(self, source_with):
        source, rec = source_with(payload(doc()))
        assert len(source.search(SearchQuery(q="x"))) == 1
        assert len(rec.requests) == 1

    @pytest.mark.parametrize("reply", [
        httpx.Response(500, text="down"), httpx.Response(404, text="gone"),
        httpx.Response(200, text="<html>"), httpx.Response(200, json=["not", "a", "dict"]),
        httpx.Response(200, json={"OL1M": "not a record"}),
    ])
    def test_a_failed_check_keeps_what_the_search_found(self, source_with, reply):
        """The endpoint is undocumented, so it never takes Open Library out of a search."""
        source, _ = source_with(payload(edition_doc("OL1W", "OL1M")), status_reply=reply)
        assert [b.source_id for b in source.search(SearchQuery(q="x"))] == ["OL1W"]

    def test_a_timed_out_check_keeps_what_the_search_found(self, recorder):
        def respond(request):
            if request.url.path == "/search.json":
                return httpx.Response(200, json=payload(edition_doc("OL1W", "OL1M")))
            return httpx.ReadTimeout("slow")
        source = OpenLibrarySource(client=recorder(respond=respond).client, base_url=BASE)
        assert [b.source_id for b in source.search(SearchQuery(q="x"))] == ["OL1W"]


class TestMalformedRecords:
    """Review 2026-10-11-main #31: one bad record in an answer used to crash the adapter, and the source was
    left out of the search. Now the bad part is skipped and the rest is kept."""

    def test_a_record_that_is_not_an_object_is_skipped(self, source_for):
        source, _ = source_for(json=payload(None, doc(), "x", 3))
        assert [b.source_id for b in source.search(SearchQuery(q="a book"))] == ["OL1W"]

    def test_author_names_that_are_not_text_are_skipped(self, source_for):
        source, _ = source_for(json=payload(doc(author_name=[{"name": "x"}, "Jane Austen", None])))
        assert source.search(SearchQuery(q="a book"))[0].authors == ["Jane Austen"]

    def test_an_author_list_that_is_not_a_list_is_no_authors(self, source_for):
        source, _ = source_for(json=payload(doc(author_name={"name": "x"})))
        assert source.search(SearchQuery(q="a book"))[0].authors == []


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
