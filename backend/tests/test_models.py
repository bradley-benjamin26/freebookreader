"""Data model from spec.md: Work -> book. A Work unites books from different sources."""
import pytest
from pydantic import ValidationError

from app.models import MAX_PAGE, MAX_TEXT_LENGTH, Book, Chapter, SearchQuery, Work
from tests.factories import make_book


def test_book_has_the_fields_in_the_spec():
    book = make_book(
        title="Pride and Prejudice", authors=["Jane Austen"], language="en",
        format="audio", pages=None, audio_seconds=47204,
        identifiers={"isbn": ["9780140430721"]}, url="https://librivox.org/x",
        cover_url="https://example.org/c.jpg", source="librivox", source_id="253")
    for field in ("title", "authors", "language", "format", "pages", "audio_seconds",
                  "source", "source_id", "identifiers", "url", "cover_url"):
        assert hasattr(book, field), field


def test_book_requires_source_source_id_title_and_url():
    with pytest.raises(ValidationError):
        Book(source="gutenberg")


@pytest.mark.parametrize("bad", ["video", "", "TEXT"])
def test_book_format_is_text_or_audio(bad):
    with pytest.raises(ValidationError):
        make_book(format=bad)


@pytest.mark.parametrize("bad", ["", "mystery"])
def test_book_source_must_be_one_of_the_four_sources(bad):
    with pytest.raises(ValidationError):
        make_book(source=bad)


@pytest.mark.parametrize("source", ["gutenberg", "librivox", "doab", "openlibrary"])
def test_known_sources_are_accepted(source):
    assert make_book(source=source).source == source


def test_book_access_values():
    for value in ("open", "borrow", "print_disabled", "none"):
        assert make_book(access=value).access == value
    with pytest.raises(ValidationError):
        make_book(access="free")


def test_narrators_and_contributors_are_separate_from_authors():
    book = make_book(authors=["A"], narrators=["N"], contributors=["T"])
    assert (book.authors, book.narrators, book.contributors) == (["A"], ["N"], ["T"])


def test_book_defaults_are_independent_per_instance():
    a = make_book()
    b = make_book()
    a.authors.append("x")
    a.identifiers["isbn"] = ["1"]
    assert b.authors == [] and b.identifiers == {}


def test_chapter_for_audio_sections():
    chapter = Chapter(title="Chapters 1-3", url="https://x/1.mp3", duration_seconds=1132)
    assert chapter.duration_seconds == 1132
    assert Chapter(title="t", url="u", duration_seconds=None).duration_seconds is None


def test_book_serializes_a_reading_option():
    data = make_book(content={"text/html": "https://x/b.html"}).model_dump(mode="json")
    assert data["reading"] == {"mode": "in_app", "kind": "html", "url": "https://x/b.html", "publication": None}


def test_work_is_a_container_of_books_only():
    """Hierarchy is Work -> book, nothing deeper."""
    fields = set(Work.model_fields)
    assert {"id", "title", "authors", "language", "sources", "source_ids",
            "identifiers", "urls", "cover_url", "books", "formats"} <= fields


def test_search_query_defaults():
    query = SearchQuery(q="dickens")
    assert query.page == 1
    assert query.sources is None
    assert query.format is None
    assert query.language is None


@pytest.mark.parametrize("page", [0, -1])
def test_search_query_page_starts_at_one(page):
    with pytest.raises(ValidationError):
        SearchQuery(q="x", page=page)


def test_search_query_page_has_a_maximum():
    assert SearchQuery(q="x", page=MAX_PAGE).page == MAX_PAGE
    with pytest.raises(ValidationError):
        SearchQuery(q="x", page=MAX_PAGE + 1)


@pytest.mark.parametrize("field", ["q", "title", "author", "keyword", "isbn"])
def test_search_query_text_fields_have_a_maximum_length(field):
    assert SearchQuery(**{field: "x" * MAX_TEXT_LENGTH})
    with pytest.raises(ValidationError):
        SearchQuery(**{field: "x" * (MAX_TEXT_LENGTH + 1)})


@pytest.mark.parametrize("raw", ["fr", "FR", " fr ", "fre", "fra", "French", "FRENCH"])
def test_search_query_language_is_normalized_to_iso_639_1(raw):
    assert SearchQuery(q="x", language=raw).language == "fr"


@pytest.mark.parametrize("raw", ["klingon", "xx", "f"])
def test_search_query_rejects_an_unknown_language(raw):
    with pytest.raises(ValidationError):
        SearchQuery(q="x", language=raw)


def test_search_query_needs_at_least_one_search_term():
    with pytest.raises(ValidationError):
        SearchQuery()
    with pytest.raises(ValidationError):
        SearchQuery(q="   ")
    for field in ("q", "title", "author", "keyword", "isbn"):
        assert SearchQuery(**{field: "something"})


def test_search_query_flags_known_item_searches():
    """Title, author or identifier searches are known-item; q and keyword are exploratory."""
    assert SearchQuery(title="Hamlet").is_known_item
    assert SearchQuery(author="Austen").is_known_item
    assert SearchQuery(isbn="9780140430721").is_known_item
    assert SearchQuery(title="Hamlet", author="Shakespeare").is_known_item
    assert not SearchQuery(q="hamlet").is_known_item
    assert not SearchQuery(keyword="tragedy").is_known_item


def test_search_query_rejects_unknown_format_and_source():
    with pytest.raises(ValidationError):
        SearchQuery(q="x", format="video")
    with pytest.raises(ValidationError):
        SearchQuery(q="x", sources=["hathitrust"])


def test_search_query_rejects_an_empty_source_selection():
    """None means all sources; an empty list would search nothing."""
    with pytest.raises(ValidationError):
        SearchQuery(q="x", sources=[])


def test_search_query_drops_duplicate_sources_keeping_order():
    assert SearchQuery(q="x", sources=["doab", "gutenberg", "doab"]).sources == ["doab", "gutenberg"]
