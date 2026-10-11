"""Which books can be read or heard inside the app, and which link out to the source.

spec.md: "The viewer displays books from the sources that allow in-app reading,
and other books link to the source."
"""
import pytest

from app.models import Chapter
from app.reader import ReadingOptions, reading_options
from tests.factories import make_book

GUTEN = {
    "html": "https://www.gutenberg.org/ebooks/11.html.images",
    "epub": "https://www.gutenberg.org/ebooks/11.epub3.images",
    "txt": "https://www.gutenberg.org/ebooks/11.txt.utf-8",
}


def test_html_is_preferred_for_gutenberg_text():
    book = make_book(content={
        "text/plain; charset=utf-8": GUTEN["txt"],
        "application/epub+zip": GUTEN["epub"],
        "text/html": GUTEN["html"]})
    assert reading_options(book) == ReadingOptions(mode="in_app", kind="html", url=GUTEN["html"],
                                                   publication="/publications/gutenberg/1/manifest.json")


def test_epub_is_next_best():
    book = make_book(content={"text/plain; charset=utf-8": GUTEN["txt"],
                              "application/epub+zip": GUTEN["epub"]})
    assert reading_options(book).kind == "epub"
    assert reading_options(book).url == GUTEN["epub"]


@pytest.mark.parametrize("mime", ["text/plain; charset=utf-8", "text/plain; charset=us-ascii", "text/plain"])
def test_plain_text_is_the_fallback(mime):
    book = make_book(content={mime: GUTEN["txt"]})
    options = reading_options(book)
    assert (options.mode, options.kind, options.url) == ("in_app", "text", GUTEN["txt"])


def test_doab_pdf_opens_in_the_app():
    """DOAB records link to the PDF, usually in the OAPEN Library."""
    url = "https://library.oapen.org/bitstream/20.500.12657/1/1/book.pdf"
    book = make_book(source="doab", content={"application/pdf": url})
    assert reading_options(book) == ReadingOptions(mode="in_app", kind="pdf", url=url)


def test_doab_without_a_pdf_links_to_the_record_page():
    book = make_book(source="doab", url="https://directory.doabooks.org/handle/20.500.12854/1")
    assert reading_options(book) == ReadingOptions(
        mode="external", kind=None, url="https://directory.doabooks.org/handle/20.500.12854/1")


@pytest.mark.parametrize("access", ["open", "borrow", "print_disabled", "none"])
def test_open_library_always_links_out(access):
    book = make_book(source="openlibrary", access=access, url="https://openlibrary.org/works/OL1W")
    options = reading_options(book)
    assert options.mode == "external"
    assert options.url == "https://openlibrary.org/works/OL1W"


def test_audiobook_with_chapters_plays_in_the_app():
    book = make_book(source="librivox", format="audio", chapters=[
        Chapter(title="Chapters 1-3", url="https://archive.org/1.mp3", duration_seconds=1132)])
    options = reading_options(book)
    assert (options.mode, options.kind) == ("in_app", "audio")
    assert options.url == "https://archive.org/1.mp3"


def test_gutenberg_audio_file_plays_in_the_app():
    book = make_book(format="audio", content={
        "text/html": "https://www.gutenberg.org/files/1/1-index.html",
        "audio/mpeg": "https://www.gutenberg.org/files/1/mp3/1-01.mp3"})
    options = reading_options(book)
    assert (options.mode, options.kind, options.url) == (
        "in_app", "audio", "https://www.gutenberg.org/files/1/mp3/1-01.mp3")


def test_audiobook_without_files_links_out():
    book = make_book(source="librivox", format="audio", url="https://librivox.org/x/")
    assert reading_options(book) == ReadingOptions(mode="external", kind=None, url="https://librivox.org/x/")


def test_text_book_with_no_known_format_links_out():
    book = make_book(content={}, url="https://www.gutenberg.org/ebooks/5")
    assert reading_options(book).mode == "external"
    assert reading_options(book).url == "https://www.gutenberg.org/ebooks/5"


def test_unreadable_mime_types_are_ignored():
    book = make_book(content={"application/x-mobipocket-ebook": "https://x/k.kf8"},
                     url="https://x/page")
    assert reading_options(book).mode == "external"


def test_external_options_always_have_a_url():
    for source in ("gutenberg", "librivox", "doab", "openlibrary"):
        assert reading_options(make_book(source=source)).url


class TestPublication:
    """The web reader opens Gutenberg books through the backend's Readium manifest (test_publications.py).

    `publication` is a path on this backend, so the backend does not need to know its own public URL;
    the app joins it to BACKEND_URL. The other fields keep pointing at the source.
    """

    def test_gutenberg_book_with_an_epub_has_a_publication(self):
        book = make_book(source="gutenberg", source_id="11", content={
            "text/html": GUTEN["html"], "application/epub+zip": GUTEN["epub"]})
        options = reading_options(book)
        assert options.publication == "/publications/gutenberg/11/manifest.json"
        assert (options.kind, options.url) == ("html", GUTEN["html"])

    def test_gutenberg_book_without_an_epub_has_none(self):
        book = make_book(source="gutenberg", source_id="11", content={"text/html": GUTEN["html"]})
        assert reading_options(book).publication is None

    @pytest.mark.parametrize("source", ["librivox", "doab", "openlibrary"])
    def test_other_sources_have_none(self, source):
        book = make_book(source=source, source_id="11", content={"application/epub+zip": "https://x/b.epub"})
        assert reading_options(book).publication is None

    @pytest.mark.parametrize("source_id", ["abc", "0", "11/../12", "", "100000000"])
    def test_only_valid_gutenberg_numbers_get_one(self, source_id):
        book = make_book(source="gutenberg", source_id=source_id,
                         content={"application/epub+zip": GUTEN["epub"]})
        assert reading_options(book).publication is None
