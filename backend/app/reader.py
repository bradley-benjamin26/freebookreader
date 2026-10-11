"""Which books are read or heard inside the app, and which link out to the source."""
from app.models import Book, ReadingOptions

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
                return ReadingOptions(mode="in_app", kind=kind, url=url)
    return external


def _audio_url(book: Book) -> str | None:
    if book.chapters:
        return book.chapters[0].url
    for mime in _AUDIO_PREFERENCE:
        if mime in book.content:
            return book.content[mime]
    return next((url for mime, url in book.content.items() if mime.startswith("audio/")), None)
