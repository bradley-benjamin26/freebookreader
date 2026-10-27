"""DOAB, the Directory of Open Access Books.

A search is OpenSearch (Atom) for the handles, then one OAI-PMH GetRecord (xoai) per handle.
Everything here uses real captures from samples/ (see samples/README.md).
"""
from urllib.parse import parse_qs, urlparse

import httpx
import pytest

from app.models import SearchQuery
from app.sources.base import SourceError, SourceTimeout
from app.sources.doab import DoabSource
from tests.conftest import SAMPLES

BASE = "https://directory.doabooks.test"
RECORDS = SAMPLES / "doab-xoai"
GONE = (RECORDS / "1082.xml").read_text(encoding="utf-8")       # idDoesNotExist


def record(handle_suffix: str) -> str:
    return (RECORDS / f"{handle_suffix}.xml").read_text(encoding="utf-8")


def answer(search="doab-opensearch.xml", lookup_status=200, lookup_error=None):
    """Answer OpenSearch with a sample feed and GetRecord with the captured record for that handle."""
    def respond(request: httpx.Request):
        if request.url.path == "/open-search/discover":
            return httpx.Response(200, text=(SAMPLES / search).read_text(encoding="utf-8"))
        if request.url.path == "/oai/request":
            if lookup_error is not None:
                return lookup_error
            if lookup_status != 200:
                return httpx.Response(lookup_status, text="down")
            identifier = request.url.params["identifier"]
            path = RECORDS / f"{identifier.rsplit('/', 1)[-1]}.xml"
            return httpx.Response(200, text=path.read_text(encoding="utf-8") if path.exists() else GONE)
        return httpx.Response(404)
    return respond


@pytest.fixture
def source_for(recorder):
    def build(**kwargs):
        respond = kwargs.pop("respond", None) or answer(**kwargs)
        rec = recorder(respond=respond)
        return DoabSource(client=rec.client, base_url=BASE), rec
    return build


def searches(rec):
    return [r for r in rec.requests if r.url.path == "/open-search/discover"]


def lookups(rec):
    return [r for r in rec.requests if r.url.path == "/oai/request"]


def test_source_name():
    assert DoabSource.name == "doab"


class TestRequests:
    def test_free_text_goes_to_opensearch(self, source_for):
        source, rec = source_for()
        source.search(SearchQuery(q="pride"))
        params = dict(searches(rec)[0].url.params)
        assert params["query"] == "pride"
        assert params["start"] == "0"
        assert int(params["rpp"]) > 0

    def test_title_and_author_are_both_in_the_query(self, source_for):
        """OpenSearch has no working field syntax (title:, author: find nothing), so all terms are free text."""
        source, rec = source_for()
        source.search(SearchQuery(title="Pride in the Projects", author="Deutsch"))
        query = searches(rec)[0].url.params["query"]
        assert "Pride in the Projects" in query and "Deutsch" in query

    def test_isbn_is_normalized_in_the_query(self, source_for):
        source, rec = source_for()
        source.search(SearchQuery(isbn="978-0-8147-8521-8"))
        assert "9780814785218" in searches(rec)[0].url.params["query"]

    def test_page_becomes_start(self, source_for):
        source, rec = source_for()
        source.search(SearchQuery(q="x", page=3))
        params = dict(searches(rec)[0].url.params)
        assert params["start"] == str(2 * int(params["rpp"]))

    def test_each_hit_is_looked_up_in_xoai(self, source_for):
        source, rec = source_for()
        source.search(SearchQuery(q="pride"))
        identifiers = sorted(r.url.params["identifier"] for r in lookups(rec))
        assert identifiers == sorted(f"oai:doabooks.org:20.500.12854/{n}"
                                     for n in ("171014", "159907", "180381", "73393"))
        assert all(r.url.params["verb"] == "GetRecord" and r.url.params["metadataPrefix"] == "xoai"
                   for r in lookups(rec))

    def test_untitled_hits_are_not_looked_up(self, source_for):
        """The search index keeps "Untitled" entries for records that no longer exist."""
        source, rec = source_for()
        source.search(SearchQuery(q="pride"))
        assert not any(r.url.params["identifier"].endswith("/1082") for r in lookups(rec))

    def test_audio_search_makes_no_request(self, source_for):
        source, rec = source_for()
        assert source.search(SearchQuery(q="x", format="audio")) == []
        assert rec.requests == []

    def test_no_hits_means_no_lookups(self, source_for):
        source, rec = source_for(search="doab-opensearch-empty.xml")
        assert source.search(SearchQuery(q="zzzzqqqxx")) == []
        assert lookups(rec) == []

    def test_language_filter_is_applied_to_results(self, source_for):
        source, _ = source_for()
        assert source.search(SearchQuery(q="pride", language="de")) == []
        assert len(source.search(SearchQuery(q="pride", language="en"))) == 3


class TestMapping:
    @pytest.fixture
    def books(self, source_for):
        source, _ = source_for()
        return source.search(SearchQuery(q="pride"))

    def test_results_keep_search_order_and_skip_chapters(self, books):
        """171014 ("12: (Dis)placing Pride ...") is a chapter."""
        assert [b.source_id for b in books] == [
            "20.500.12854/159907", "20.500.12854/180381", "20.500.12854/73393"]

    def test_book_fields(self, books):
        book = books[0]
        assert book.source == "doab"
        assert book.title == "Pride Parades and LGBT Movements"
        assert book.authors == ["Abby Peterson", "Mattias Wahlström", "Magnus Wennerhag"]
        assert book.language == "en"
        assert book.format == "text"
        assert book.pages == 282
        assert book.url == "https://directory.doabooks.org/handle/20.500.12854/159907"
        assert book.access == "open"
        assert book.audio_seconds is None

    def test_identifiers(self, books):
        assert books[0].identifiers["isbn"][0] == "9781315474045"
        assert books[0].identifiers["doi"] == ["10.4324/9781315474052"]

    def test_oapen_pdf_link_becomes_content_and_opens_in_the_app(self, books):
        """DOAB records carry the OAPEN Library download link (oapenidentifierdownloadUrl)."""
        pdf = "https://library.oapen.org/bitstream/20.500.12657/102101/1/9781315474045.pdf"
        assert books[0].content == {"application/pdf": pdf}
        assert (books[0].reading.mode, books[0].reading.kind, books[0].reading.url) == ("in_app", "pdf", pdf)

    def test_a_non_pdf_link_is_not_content_and_the_book_links_out(self, books):
        """73393's link is a Frontiers web page: the DOAB record page is the way in."""
        book = books[2]
        assert book.content == {}
        assert book.reading.mode == "external"
        assert book.reading.url == "https://directory.doabooks.org/handle/20.500.12854/73393"

    def test_editors_are_contributors_not_authors(self, books):
        assert books[2].authors == []
        assert books[2].contributors == ["Robert A. Montgomery", "Matt W. Hayward", "Bernard Mombo Kissui"]

    def test_thumbnail_is_the_cover(self, books):
        assert books[0].cover_url == (
            "https://directory.doabooks.org/bitstream/20.500.12854/159907/1/9781315474045.pdf.jpg")

    def test_stale_hits_are_skipped(self, source_for):
        """A hit whose GetRecord answers idDoesNotExist is gone from DOAB."""
        feed = (SAMPLES / "doab-opensearch.xml").read_text(encoding="utf-8")
        def respond(request):
            if request.url.path == "/open-search/discover":
                return httpx.Response(200, text=feed)
            return httpx.Response(200, text=GONE)
        source, _ = source_for(respond=respond)
        assert source.search(SearchQuery(q="pride")) == []

    def test_a_failed_lookup_falls_back_to_the_search_hit(self, source_for):
        source, _ = source_for(lookup_status=503)
        books = source.search(SearchQuery(q="pride"))
        assert len(books) == 4                       # the chapter cannot be recognised without its record
        hit = next(b for b in books if b.source_id == "20.500.12854/159907")
        assert hit.title == "Pride Parades and LGBT Movements"
        assert hit.authors == ["Abby Peterson", "Mattias Wahlström", "Magnus Wennerhag"]
        assert hit.language is None and hit.content == {}
        assert hit.url == "https://directory.doabooks.org/handle/20.500.12854/159907"

    @pytest.mark.parametrize("reply", [
        "<html><body>Maintenance</body></html>",
        '<OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"><error code="badArgument">bad</error></OAI-PMH>',
        '<OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"><error code="cannotDisseminateFormat"/></OAI-PMH>',
    ])
    def test_a_lookup_that_is_well_formed_but_not_a_record_falls_back_too(self, source_for, reply):
        """Review 2026-10-11-main #30: these used to read as "deleted", so the hit was dropped."""
        feed = (SAMPLES / "doab-opensearch.xml").read_text(encoding="utf-8")
        def respond(request):
            if request.url.path == "/open-search/discover":
                return httpx.Response(200, text=feed)
            return httpx.Response(200, text=reply)
        source, _ = source_for(respond=respond)
        assert len(source.search(SearchQuery(q="pride"))) == 4

    def test_a_timed_out_lookup_also_falls_back(self, source_for):
        source, _ = source_for(lookup_error=httpx.ReadTimeout("slow"))
        assert len(source.search(SearchQuery(q="pride"))) == 4


class TestXoaiParsing:
    def test_german_record(self):
        (book,) = DoabSource.parse_xoai(record("133576"))
        assert book.title == "Potenziale der Kinder- und Jugendarbeit"
        assert book.authors == ["Erich Sass", "Julia Hallmann"]
        assert book.language == "de"
        assert book.pages == 296
        assert book.identifiers["oclc"] == ["1348638022"]       # from "OCN: 1348638022"

    def test_placeholder_cover_is_skipped_for_a_real_one(self):
        """133576 lists DOAB's "open-access-no-cover.png" placeholder before its real thumbnail."""
        (book,) = DoabSource.parse_xoai(record("133576"))
        assert book.cover_url == "https://directory.doabooks.org/bitstream/20.500.12854/133576/6/9783779969457.pdf.jpg"

    def test_only_a_placeholder_means_no_cover(self):
        text = record("133576").replace("9783779969457.pdf.jpg", "open-access-no-cover.png")
        (book,) = DoabSource.parse_xoai(text)
        assert book.cover_url is None

    def test_chapter_is_not_a_book(self):
        assert DoabSource.parse_xoai(record("171014")) == []

    def test_id_does_not_exist_is_empty(self):
        assert DoabSource.parse_xoai(GONE) == []

    def test_invalid_isbns_are_dropped(self):
        text = record("180381").replace("9780814785218", "9780814785219")   # bad check digit
        (book,) = DoabSource.parse_xoai(text)
        assert "isbn" not in book.identifiers

    def test_malformed_xml_raises_source_error(self):
        with pytest.raises(SourceError):
            DoabSource.parse_xoai("<not-xml")


class TestOpenSearchParsing:
    def test_hits_have_handle_title_and_authors(self):
        hits = DoabSource.parse_opensearch((SAMPLES / "doab-opensearch.xml").read_text(encoding="utf-8"))
        assert [h.source_id for h in hits] == [
            "20.500.12854/171014", "20.500.12854/159907", "20.500.12854/180381", "20.500.12854/73393"]
        assert hits[2].title == "Pride in the Projects"
        assert hits[2].authors == ["Nancy L. Deutsch"]

    def test_empty_feed(self):
        assert DoabSource.parse_opensearch(
            (SAMPLES / "doab-opensearch-empty.xml").read_text(encoding="utf-8")) == []


class TestErrors:
    def test_not_allowed_message_raises_source_error(self, source_for):
        """What DOAB's REST API answers today; an HTML bot-check page is just as unusable."""
        source, _ = source_for(respond=lambda r: httpx.Response(
            200, text="You address is not allowed to access this API."))
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))

    def test_bot_check_page_raises_source_error(self, source_for):
        source, _ = source_for(respond=lambda r: httpx.Response(
            200, text="<!doctype html><html><head><title>Making sure you're not a bot!</title></head></html>"))
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))

    @pytest.mark.parametrize("status", [403, 500, 503])
    def test_http_errors_raise_source_error(self, source_for, status):
        source, _ = source_for(respond=lambda r: httpx.Response(status, text="no"))
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))

    def test_connection_failure_raises_source_error(self, source_for):
        source, _ = source_for(respond=lambda r: httpx.ConnectError("refused"))
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))

    def test_search_timeout_raises_source_timeout(self, source_for):
        source, _ = source_for(respond=lambda r: httpx.ReadTimeout("slow"))
        with pytest.raises(SourceTimeout):
            source.search(SearchQuery(q="x"))
