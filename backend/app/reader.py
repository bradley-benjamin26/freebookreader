"""Which books are read or heard inside the app, and which link out to the source."""
from app.models import Book, ReadingOptions
from app.publications import MAX_GUTENBERG_ID, gutenberg_manifest_path

__all__ = ["ReadingOptions", "reading_options"]

# Text formats in order of preference.
_TEXT_KINDS = [
    ("html", lambda mime: mime == "text/html" or mime.startswith("text/html;")),
    ("epub", lambda mime: mime == "application/epub+zip"),
    ("text", lambda mime: mime == "text/plain" or mime.startswith("text/plain;")),
    ("pdf", lambda mime: mime == "application/pdf"),
]
_AUDIO_PREFERENCE = ["audio/mpeg", "audio/mp4", "audio/ogg"]


def reading_options(book: Book) -> ReadingOptions:
    external = ReadingOptions(mode="external", kind=None, url=book.url)
    if book.source == "openlibrary":   # borrowing and reading happen on openlibrary.org
        return external
    if book.format == "audio":
        url = _audio_url(book)
        return ReadingOptions(mode="in_app", kind="audio", url=url) if url else external
    for kind, matches in _TEXT_KINDS:
        for mime, url in book.content.items():
            if matches(mime):
                return ReadingOptions(mode="in_app", kind=kind, url=url, publication=_publication(book))
    return external


def _publication(book: Book) -> str | None:
    """The web reader's manifest on this backend: Gutenberg books that have an EPUB."""
    if book.source != "gutenberg" or "application/epub+zip" not in book.content:
        return None
    if not book.source_id.isascii() or not book.source_id.isdigit():
        return None
    book_id = int(book.source_id)
    return gutenberg_manifest_path(book_id) if 1 <= book_id <= MAX_GUTENBERG_ID else None


def _audio_url(book: Book) -> str | None:
    if book.chapters:
        return book.chapters[0].url
    for mime in _AUDIO_PREFERENCE:
        if mime in book.content:
            return book.content[mime]
    return next((url for mime, url in book.content.items() if mime.startswith("audio/")), None)
