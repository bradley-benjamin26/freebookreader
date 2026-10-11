"""LibriVox audiobooks (api/feed/audiobooks)."""
import httpx
import pytest

from app.models import SearchQuery
from app.sources.base import SourceError
from app.sources.librivox import LibriVoxSource

BASE = "https://librivox.test"


@pytest.fixture
def source_for(recorder):
    def build(**kwargs):
        rec = recorder(**kwargs)
        return LibriVoxSource(client=rec.client, base_url=BASE), rec
    return build


def test_source_name():
    assert LibriVoxSource.name == "librivox"


class TestRequests:
    def test_requests_extended_json_with_cover_art(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("librivox-title-search.json"))
        source.search(SearchQuery(title="pride and prejudice"))
        assert rec.last.url.path == "/api/feed/audiobooks"
        params = rec.params()
        assert params["format"] == "json"
        assert params["extended"] == "1"
        assert params["coverart"] == "1"
        assert params["title"] == "^pride and prejudice"

    def test_title_is_a_prefix_match(self, source_for, sample_json):
        """Without "^" LibriVox matches the exact full title only, which misses
        "Pride and Prejudice (version 2)" and other recordings of the same book."""
        source, rec = source_for(json=sample_json("librivox-title-search.json"))
        source.search(SearchQuery(title="Great Expectations"))
        assert rec.params()["title"] == "^Great Expectations"

    @pytest.mark.parametrize("text, sent", [
        ("The Time Machine", "^Time Machine"),
        ("A Christmas Carol", "^Christmas Carol"),
        ("Les Misérables", "^Misérables"),
        ("L'homme qui rit", "^homme qui rit"),
        ("Die Leiden des jungen Werther", "^Leiden des jungen Werther"),
        ("The", "^The"),                      # nothing left after the article: send as is
        # Kept in LibriVox's catalog (checked live 2026-10-11): "^Principe" and "^Profundis" find nothing.
        ("Il Principe", "^Il Principe"),
        ("De Profundis", "^De Profundis"),
        ("De Bello Gallico", "^De Bello Gallico"),
    ])
    def test_leading_articles_are_dropped(self, source_for, sample_json, text, sent):
        """LibriVox catalogs "Time Machine", "Misérables - tome 1": "^the time machine" finds nothing."""
        source, rec = source_for(json=sample_json("librivox-title-search.json"))
        source.search(SearchQuery(title=text))
        assert rec.params()["title"] == sent

    def test_author_search_uses_the_last_name_only(self, source_for, sample_json):
        """LibriVox answers 'Audiobooks could not be found' for a full name."""
        source, rec = source_for(json=sample_json("librivox-author-search.json"))
        source.search(SearchQuery(author="Charles Dickens"))
        assert rec.params()["author"] == "Dickens"

    def test_author_in_last_comma_first_form(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("librivox-author-search.json"))
        source.search(SearchQuery(author="Dickens, Charles"))
        assert rec.params()["author"] == "Dickens"

    @pytest.mark.parametrize("author", [
        "Charles Dickens Jr.", "Charles Dickens jr", "Dickens, Charles, Jr.", "Charles Dickens Sr.",
        "Charles Dickens II", "Charles Dickens III", "Charles Dickens IV", "Charles Dickens, Jr.",
    ])
    def test_name_suffixes_are_not_sent_as_the_last_name(self, source_for, sample_json, author):
        source, rec = source_for(json=sample_json("librivox-author-search.json"))
        source.search(SearchQuery(author=author))
        assert rec.params()["author"] == "Dickens"

    def test_a_suffix_alone_makes_no_request(self, source_for):
        source, rec = source_for(json={"books": []})
        assert source.search(SearchQuery(author="Jr.")) == []
        assert rec.requests == []

    @pytest.mark.parametrize("field", ["q", "keyword"])
    def test_free_text_searches_title_prefixes(self, source_for, sample_json, field):
        """LibriVox has no keyword search; "title=pride" finds nothing, "^pride" finds titles starting with it."""
        source, rec = source_for(json=sample_json("librivox-title-search.json"))
        source.search(SearchQuery(**{field: "pride"}))
        assert rec.params()["title"] == "^pride"

    def test_title_and_author_are_never_sent_together(self, source_for, sample_json):
        """LibriVox answers HTTP 500 with an empty body when both are sent."""
        source, rec = source_for(json=sample_json("librivox-title-search.json"))
        source.search(SearchQuery(title="Pride and Prejudice", author="Jane Austen"))
        assert len(rec.requests) == 1
        assert rec.params()["title"] == "^Pride and Prejudice"
        assert "author" not in rec.params()

    def test_author_filters_a_title_search(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("librivox-title-search.json"))
        assert len(source.search(SearchQuery(title="Pride and Prejudice", author="Austen, Jane"))) == 2
        assert source.search(SearchQuery(title="Pride and Prejudice", author="Charles Dickens")) == []

    def test_page_becomes_an_offset(self, source_for, sample_json):
        source, rec = source_for(json=sample_json("librivox-title-search.json"))
        source.search(SearchQuery(q="pride", page=1))
        assert rec.params().get("offset", "0") == "0"
        source.search(SearchQuery(q="pride", page=3))
        limit = int(rec.params()["limit"])
        assert rec.params()["offset"] == str(2 * limit)

    def test_text_only_search_makes_no_request(self, source_for):
        source, rec = source_for(json={"books": []})
        assert source.search(SearchQuery(q="pride", format="text")) == []
        assert rec.requests == []

    def test_isbn_only_search_makes_no_request(self, source_for):
        source, rec = source_for(json={"books": []})
        assert source.search(SearchQuery(isbn="9780140430721")) == []
        assert rec.requests == []

    def test_language_filter_is_applied_to_results(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("librivox-title-search.json"))
        assert source.search(SearchQuery(q="pride", language="fr")) == []
        assert len(source.search(SearchQuery(q="pride", language="en"))) == 2


class TestMapping:
    @pytest.fixture
    def books(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("librivox-title-search.json"))
        return source.search(SearchQuery(title="pride and prejudice"))

    def test_book_fields(self, books):
        book = books[0]
        assert book.source == "librivox"
        assert book.source_id == "253"
        assert book.title == "Pride and Prejudice"
        assert book.authors == ["Jane Austen"]
        assert book.language == "en"
        assert book.format == "audio"
        assert book.audio_seconds == 47204
        assert book.url == "https://librivox.org/pride-and-prejudice-by-jane-austen/"
        assert book.cover_url == "https://archive.org/download/pride_and_prejudice_librivox/Pride_Prejudice_1104.jpg"
        assert book.pages is None
        assert book.access == "open"

    def test_zero_length_means_unknown(self, books):
        assert books[1].source_id == "22765"
        assert books[1].audio_seconds is None

    def test_readers_are_narrators_not_authors(self, books):
        assert "Chris Goringe" in books[0].narrators
        assert "Kara Shallenberg" in books[0].narrators      # "(1969-2023)" is stripped
        assert not set(books[0].narrators) & set(books[0].authors)
        assert len(books[0].narrators) == len(set(books[0].narrators))

    def test_chapters_come_from_sections(self, books, sample_json):
        sections = sample_json("librivox-title-search.json")["books"][0]["sections"]
        chapters = books[0].chapters
        assert len(chapters) == len(sections) == 37
        assert chapters[0].title == "Chapters 1-3"
        assert chapters[0].url == sections[0]["listen_url"]
        assert chapters[0].duration_seconds == 1132

    def test_gutenberg_text_source_is_recorded_as_an_identifier(self, books):
        """Used to pair a recording with the text for listen-while-reading."""
        assert books[0].identifiers == {"gutenberg": ["1342"]}      # url ".../etext/1342"
        assert books[1].identifiers == {"gutenberg": ["1342"]}      # url ".../ebooks/1342"

    def test_non_gutenberg_text_source_adds_no_identifier(self, source_for, sample_json):
        payload = sample_json("librivox-title-search.json")
        payload["books"][0]["url_text_source"] = "https://example.org/some-text"
        source, _ = source_for(json=payload)
        assert source.search(SearchQuery(q="x"))[0].identifiers == {}

    def test_translators_are_contributors(self, source_for, sample_json):
        payload = sample_json("librivox-title-search.json")
        payload["books"][0]["translators"] = [
            {"id": "1", "first_name": "Constance", "last_name": "Garnett", "dob": "", "dod": ""}]
        source, _ = source_for(json=payload)
        assert source.search(SearchQuery(q="x"))[0].contributors == ["Constance Garnett"]

    def test_author_search_response(self, source_for, sample_json):
        source, _ = source_for(json=sample_json("librivox-author-search.json"))
        books = source.search(SearchQuery(author="Dickens"))
        assert books and all(b.authors == ["Charles Dickens"] for b in books)

    def test_unknown_language_name_gives_none(self, source_for, sample_json):
        payload = sample_json("librivox-title-search.json")
        payload["books"][0]["language"] = "Multilingual"
        source, _ = source_for(json=payload)
        assert source.search(SearchQuery(q="x"))[0].language is None


class TestErrors:
    def test_not_found_message_means_no_results(self, source_for):
        source, _ = source_for(json={"error": "Audiobooks could not be found"})
        assert source.search(SearchQuery(title="zzzzqqqxx")) == []

    @pytest.mark.parametrize("status", [500, 503])
    def test_server_errors_raise_source_error(self, source_for, status):
        source, _ = source_for(text="down", status=status)
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))

    def test_connection_failure_raises_source_error(self, source_for):
        source, _ = source_for(error=httpx.ConnectTimeout("slow"))
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))

    def test_garbage_body_raises_source_error(self, source_for):
        source, _ = source_for(text="<html>maintenance</html>")
        with pytest.raises(SourceError):
            source.search(SearchQuery(q="x"))
