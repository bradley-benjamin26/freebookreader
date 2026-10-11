"""Content for the Source About pages (spec.md > UX > Source About Pages). Plain text only."""
from pydantic import BaseModel

from app.models import Format


class SourceInfo(BaseModel):
    id: str
    name: str
    description: str        # what it is
    how_it_works: str       # how it works in this app
    how_to_access: str      # how to use it directly
    website_url: str
    donation_url: str
    formats: list[Format]
    in_app: bool            # whether its books open inside the app


SOURCES = [
    SourceInfo(
        id="gutenberg",
        name="Project Gutenberg",
        description=(
            "Project Gutenberg is a volunteer-run library of more than 75,000 free ebooks, founded in 1971. "
            "Almost all of its books are in the public domain in the United States, so anyone can read, "
            "copy and share them."),
        how_it_works=(
            "This app searches a copy of the Project Gutenberg catalog that is refreshed every night. "
            "Books open in the app's reader, and the text is loaded from gutenberg.org. Some books also "
            "have human-read audio, which plays in the app."),
        how_to_access=(
            "Visit gutenberg.org to search the catalog and read books online or download them as EPUB, "
            "Kindle or plain text files. No account is needed."),
        website_url="https://www.gutenberg.org/",
        donation_url="https://www.gutenberg.org/donate/",
        formats=["text"],
        in_app=True,
    ),
    SourceInfo(
        id="librivox",
        name="LibriVox",
        description=(
            "LibriVox is a library of free public-domain audiobooks read by volunteers from around the "
            "world. Its recordings are themselves in the public domain, and its audio files are kept "
            "at the Internet Archive."),
        how_it_works=(
            "This app searches LibriVox by title and by the author's last name. LibriVox cannot search "
            "by keyword, so a general search finds recordings whose title starts with your words. "
            "Recordings play chapter by chapter in the app."),
        how_to_access=(
            "Visit librivox.org to browse recordings by author, title, genre or language, listen online, "
            "or download MP3 files and podcast feeds. No account is needed."),
        website_url="https://librivox.org/",
        donation_url="https://librivox.org/pages/donate-to-librivox/",
        formats=["audio"],
        in_app=True,
    ),
    SourceInfo(
        id="doab",
        name="DOAB",
        description=(
            "DOAB, the Directory of Open Access Books, lists peer-reviewed open access books from hundreds "
            "of academic publishers. Every book in it is free to read and is usually shared under a "
            "Creative Commons license. It is a joint service of OAPEN, OpenEdition, CNRS and Aix-Marseille "
            "University, provided by the DOAB Foundation."),
        how_it_works=(
            "This app searches DOAB and lists books, not individual chapters. When a book's PDF is "
            "available, usually from the OAPEN Library, it opens in the app. Other books open on their "
            "DOAB page, which links to the publisher's website."),
        how_to_access=(
            "Visit directory.doabooks.org to search and browse by subject, publisher or language. Each "
            "book's page links to where it can be read or downloaded. No account is needed."),
        website_url="https://directory.doabooks.org/",
        # DOAB's own Donate button, "Support DOAB and the OAPEN Library" (permanent PayPal link).
        donation_url="https://www.paypal.com/donate/?hosted_button_id=VPW4DRBLBM9J8",
        formats=["text"],
        in_app=True,
    ),
    SourceInfo(
        id="openlibrary",
        name="Open Library",
        description=(
            "Open Library is a catalog of millions of books run by the Internet Archive, a non-profit "
            "library. Public-domain books can be read for free, and many newer books can be borrowed "
            "for a short time, like at a public library."),
        how_it_works=(
            "This app searches Open Library and shows whether each book can be read freely, borrowed, "
            "or is available only to people with a print disability. Reading and borrowing happen on "
            "the Open Library website, so these books open there instead of in the app."),
        how_to_access=(
            "Visit openlibrary.org to search for books. Reading public-domain books needs no account. "
            "Borrowing needs a free Internet Archive account, and print-disabled access needs a "
            "qualifying account."),
        website_url="https://openlibrary.org/",
        donation_url="https://archive.org/donate",
        formats=["text"],
        in_app=False,
    ),
]

_BY_ID = {source.id: source for source in SOURCES}


def get_source_info(source_id: str) -> SourceInfo:
    return _BY_ID[source_id]
