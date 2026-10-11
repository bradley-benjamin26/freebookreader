"""Project Gutenberg via the self-hosted Gutendex API (see api_gutendex.documentation.md)."""
from datetime import date

import httpx
import pytest

from app.models import SearchQuery
from app.sources.base import SourceError, SourceTimeout
from app.sources.gutendex import GutendexSource

BASE = "http://gutendex.test"


@pytest.fixture
def source_for(recorder):
    def build(**kwargs):
        rec = recorder(**kwargs)
        return GutendexSource(client=rec.client, base_url=BASE), rec
    return build


def test_source_name():
    assert GutendexSource.name == "gutenberg"


class TestRequests:
    def test_free_text_query_uses_search_on_the_books_endpoint(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("gutendex-search.json"))
        source.search(SearchQuery(q="dickens great"))
        assert len(rec.requests) == 1
        assert rec.last.method == "GET"
        assert rec.last.url.path == "/books/"          # trailing slash: no redirect
        assert rec.params()["search"] == "dickens great"

    def test_title_and_author_are_combined_into_search(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("gutendex-search.json"))
        source.search(SearchQuery(title="Great Expectations", author="Dickens"))
        words = rec.params()["search"].lower().split()
        assert {"great", "expectations", "dickens"} <= set(words)

    def test_keyword_uses_topic(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("gutendex-search.json"))
        source.search(SearchQuery(keyword="children"))
        assert rec.params()["topic"] == "children"
        assert "search" not in rec.params()

    def test_language_filter(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("gutendex-french.json"))
        source.search(SearchQuery(q="hugo", language="fr"))
        assert rec.params()["languages"] == "fr"

    def test_audio_format_asks_for_audio_mime_types(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("gutendex-audio.json"))
        source.search(SearchQuery(q="nights", format="audio"))
        assert rec.params()["mime_type"] == "audio"

    def test_page_is_forwarded(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("gutendex-search.json"))
        source.search(SearchQuery(q="dickens", page=3))
        assert rec.params()["page"] == "3"

    def test_isbn_only_search_is_answered_without_a_request(self, source_for):
        """Gutendex cannot search identifiers, so asking it would only return noise."""
        source, rec = source_for(json={"count": 0, "results": []})
        assert source.search(SearchQuery(isbn="9780140430721")) == []
        assert rec.requests == []

    def test_isbn_with_title_still_searches_by_title(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("gutendex-search.json"))
        source.search(SearchQuery(title="Great Expectations", isbn="9780141439563"))
        assert "great" in rec.params()["search"].lower()


class TestMapping:
    def test_text_book_fields(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("gutendex-search.json"))
        book = source.search(SearchQuery(q="dickens great"))[0]
        assert book.source == "gutenberg"
        assert book.source_id == "1400"
        assert book.title == "Great Expectations"
        assert book.authors == ["Charles Dickens"]      # "Last, First" is flipped
        assert book.language == "en"
        assert book.format == "text"
        assert book.url == "https://www.gutenberg.org/ebooks/1400"
        assert book.cover_url == "https://www.gutenberg.org/cache/epub/1400/pg1400.cover.medium.jpg"
        assert book.access == "open"
        assert book.identifiers == {}                     # Gutenberg has no ISBN/OCLC
        assert book.pages is None and book.audio_seconds is None

    def test_readable_formats_are_kept_and_images_are_not(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("gutendex-search.json"))
        book = source.search(SearchQuery(q="dickens great"))[0]
        assert book.content["text/html"] == "https://www.gutenberg.org/ebooks/1400.html.images"
        assert book.content["application/epub+zip"] == "https://www.gutenberg.org/ebooks/1400.epub3.images"
        assert any(k.startswith("text/plain") for k in book.content)
        assert "image/jpeg" not in book.content
        assert "application/rdf+xml" not in book.content

    def test_sound_books_are_audio(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("gutendex-search.json"))
        books = source.search(SearchQuery(q="dickens great"))
        assert [b.format for b in books] == ["text", "audio"]
        assert books[1].source_id == "8608"

    def test_audio_files_are_kept_in_content(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("gutendex-audio.json"))
        book = source.search(SearchQuery(q="x", format="audio"))[0]
        assert book.format == "audio"
        assert any(k.startswith("audio/") for k in book.content)

    def test_text_format_drops_sound_books(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("gutendex-search.json"))
        books = source.search(SearchQuery(q="dickens great", format="text"))
        assert [b.source_id for b in books] == ["1400"]

    def test_french_book_language_and_unicode_title(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("gutendex-french.json"))
        book = source.search(SearchQuery(q="hugo", language="fr"))[0]
        assert book.language == "fr"
        assert book.title == "Les misérables Tome I: Fantine"
        assert book.authors == ["Victor Hugo"]

    def test_marc_subfield_markers_are_removed_from_titles(self, source_for, sample_json):
        """The catalog keeps MARC "$b" (subtitle) markers: "Black Beauty : $b The autobiography of a horse"."""
        source, _ = source_for(json=sample_json("gutendex-audio.json"))
        books = source.search(SearchQuery(q="x", format="audio"))
        black_beauty = next(b for b in books if b.source_id == "19637")
        assert black_beauty.title == "Black Beauty: The autobiography of a horse"
        assert not any("$" in b.title for b in books)

    def test_book_without_authors(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("gutendex-audio.json"))
        books = source.search(SearchQuery(q="x", format="audio"))
        assert books[0].authors == []                     # "Les mille et une nuits"

    def test_book_with_no_language_gets_none(self, source_for, sample_json):
        payload = sample_json("gutendex-search.json")
        payload["results"][0]["languages"] = []
        source, _ = source_for(json=payload)
        assert source.search(SearchQuery(q="x"))[0].language is None

    def test_book_in_several_languages_is_labelled_with_the_requested_one(self, source_for, sample_json):
        """12137 "La Légende des Siècles" has languages ["en", "fr"] (review 2026-10-10, #3)."""
        payload = sample_json("gutendex-search.json")
        payload["results"][0]["languages"] = ["en", "fr"]
        source, _ = source_for(json=payload)
        assert source.search(SearchQuery(q="x", language="fr"))[0].language == "fr"
        assert source.search(SearchQuery(q="x"))[0].language == "en"

    def test_translators_and_editors_are_contributors_not_authors(self, source_for, sample_json):
        payload = sample_json("gutendex-search.json")
        payload["results"][0]["translators"] = [
            {"name": "Wraxall, Lascelles", "birth_year": None, "death_year": None}]
        payload["results"][0]["editors"] = [
            {"name": "Smith, Ann", "birth_year": None, "death_year": None}]
        source, _ = source_for(json=payload)
        book = source.search(SearchQuery(q="x"))[0]
        assert book.authors == ["Charles Dickens"]
        assert book.contributors == ["Lascelles Wraxall", "Ann Smith"]

    def test_edition_details_tell_gutenberg_ebooks_apart(self, source_for, sample_json):
        """Gutenberg often has several eBooks of one work (1342 and 42671 are both
        Pride and Prejudice); release date, last update, credits and original
        publication tell them apart, as on gutenberg.org."""
        source, _ = source_for(json=sample_json("gutendex-search.json"))
        text, audio = source.search(SearchQuery(q="dickens great"))
        assert text.release_date == date(1998, 7, 1)
        assert text.last_updated == date(2024, 12, 17)
        assert text.credits == "An Anonymous Volunteer and David Widger"
        assert text.original_publication is None
        assert audio.release_date == date(2005, 8, 1)
        assert audio.credits is None

    def test_original_publication(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("gutendex-french.json"))
        books = source.search(SearchQuery(q="hugo", language="fr"))
        book = next(b for b in books if b.source_id == "70891")
        assert book.original_publication == "France: Hetzel-Quantin, 1880."

    def test_missing_or_unreadable_edition_details_are_none(self, source_for, sample_json):
        """An older Gutendex has none of these fields; a bad date must not cost the whole search."""
        payload = sample_json("gutendex-search.json")
        for field in ("release_date", "last_updated", "credits", "original_publication"):
            del payload["results"][0][field]
        payload["results"][1]["release_date"] = "1998-13-45"
        payload["results"][1]["last_updated"] = 19980701
        payload["results"][1]["credits"] = "   "
        source, _ = source_for(json=payload)
        for book in source.search(SearchQuery(q="x")):
            assert book.release_date is None
            assert book.last_updated is None
            assert book.credits is None
            assert book.original_publication is None

    def test_empty_result(self, source_for):
        source, _ = source_for(json={"count": 0, "next": None, "previous": None, "results": []})
        assert source.search(SearchQuery(q="zzzz")) == []


class TestErrors:
    def test_page_past_the_end_is_an_empty_list_not_an_error(self, source_for):
        source, _ = source_for(json={"detail": "Invalid page."}, status=404)
        assert source.search(SearchQuery(q="x", page=999)) == []

    @pytest.mark.parametrize("status", [500, 502, 503])
    def test_server_errors_raise_source_error(self, source_for, status):
        source, _ = source_for(json={"detail": "boom"}, status=status)
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))

    def test_connection_failure_raises_source_error(self, source_for):
        source, _ = source_for(error=httpx.ConnectError("refused"))
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))

    @pytest.mark.parametrize("error", [httpx.ReadTimeout("slow"), httpx.ConnectTimeout("slow")])
    def test_timeout_raises_source_timeout(self, source_for, error):
        """A SourceError subclass, so the search service can tell it apart from an outage."""
        source, _ = source_for(error=error)
        with pytest.raises(SourceTimeout):
            source.search(SearchQuery(q="x"))

    def test_non_json_body_raises_source_error(self, source_for):
        source, _ = source_for(text="<html>Cloudflare challenge</html>")
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))
