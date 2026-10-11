"""Data model from spec.md: a Work unites books from different sources (Work -> book)."""
from datetime import date
from typing import Annotated, Literal, Optional

from pydantic import BaseModel, Field, computed_field, field_serializer, field_validator, model_validator

from app.normalize import to_language_code

SourceName = Literal["gutenberg", "librivox", "doab", "openlibrary"]
Format = Literal["text", "audio"]
# How a book can be had: freely, by borrowing, for print-disabled readers only, or not at all.
Access = Literal["open", "borrow", "print_disabled", "none"]


# Most identifiers of one kind in a response. Open Library works carry every edition's ISBN (3,714 for
# Pride and Prejudice), which made a details page print 65,000 characters. Merging and known-item
# filtering see the full lists; only the serialized response is cut.
MAX_SERIALIZED_IDENTIFIERS = 20


def _cut(identifiers: dict[str, list[str]]) -> dict[str, list[str]]:
    return {kind: values[:MAX_SERIALIZED_IDENTIFIERS] for kind, values in identifiers.items()}


class Chapter(BaseModel):
    """One section of an audiobook (LibriVox lists them)."""
    title: str
    url: str
    duration_seconds: Optional[int] = None


class ReadingOptions(BaseModel):
    """How the app opens a book: in its own viewer/player, or by linking to the source."""
    mode: Literal["in_app", "external"]
    kind: Optional[Literal["html", "epub", "text", "pdf", "audio"]] = None
    url: str
    # Path on this backend of a Readium manifest for the book (web reader), or None.
    publication: Optional[str] = None


class Book(BaseModel):
    """One record from one source."""
    source: SourceName
    source_id: str
    title: str
    authors: list[str] = Field(default_factory=list)
    narrators: list[str] = Field(default_factory=list)
    contributors: list[str] = Field(default_factory=list)   # translators, editors, ...
    language: Optional[str] = None                          # ISO 639-1, None when unknown
    format: Format = "text"
    pages: Optional[int] = None
    audio_seconds: Optional[int] = None
    identifiers: dict[str, list[str]] = Field(default_factory=dict)   # isbn, oclc, gutenberg, ...
    url: str                                                # the record's page at the source
    cover_url: Optional[str] = None
    content: dict[str, str] = Field(default_factory=dict)   # MIME type -> file URL
    chapters: list[Chapter] = Field(default_factory=list)
    access: Access = "open"
    # Edition details that tell apart several records of one work (only Gutenberg fills them).
    release_date: Optional[date] = None
    last_updated: Optional[date] = None                     # None when not changed since release
    credits: Optional[str] = None                           # who produced it; one credit per line
    original_publication: Optional[str] = None              # e.g. "Budapest: Athenaeum, 1926."

    @field_serializer("identifiers")
    def _serialize_identifiers(self, identifiers):
        return _cut(identifiers)

    @computed_field
    @property
    def reading(self) -> ReadingOptions:
        from app.reader import reading_options
        return reading_options(self)


class Work(BaseModel):
    """Books from one or more sources that are the same work."""
    id: str
    title: str
    authors: list[str]
    language: Optional[str]
    sources: list[SourceName]
    source_ids: dict[str, list[str]]
    identifiers: dict[str, list[str]]
    urls: list[str]
    cover_url: Optional[str]
    formats: list[Format]
    books: list[Book]

    @field_serializer("identifiers")
    def _serialize_identifiers(self, identifiers):
        return _cut(identifiers)


# Input limits: longer queries or deeper pages make sources answer 5xx (Open Library did for a
# 3,000-character q and for page 10**9), which would count as an outage. No real search needs more.
MAX_TEXT_LENGTH = 300
MAX_PAGE = 1000
_Text = Optional[Annotated[str, Field(max_length=MAX_TEXT_LENGTH)]]


class SearchQuery(BaseModel):
    q: _Text = None                   # free text (exploratory)
    title: _Text = None               # known-item
    author: _Text = None              # known-item
    keyword: _Text = None             # subject/topic (exploratory)
    isbn: _Text = None                # known-item
    language: Optional[str] = None    # normalized to ISO 639-1 ('FR', 'fre', 'French' -> 'fr')
    format: Optional[Format] = None
    sources: Optional[Annotated[list[SourceName], Field(min_length=1)]] = None   # None = all sources
    page: int = Field(default=1, ge=1, le=MAX_PAGE)

    @field_validator("sources")
    @classmethod
    def _no_duplicate_sources(cls, value):
        return None if value is None else list(dict.fromkeys(value))

    @field_validator("q", "title", "author", "keyword", "isbn", "language")
    @classmethod
    def _blank_is_none(cls, value):
        if value is None:
            return None
        value = value.strip()
        return value or None

    @field_validator("language")
    @classmethod
    def _known_language(cls, value):
        if value is None:
            return None
        code = to_language_code(value)
        if code is None:
            raise ValueError(f"unknown language {value!r}; use an ISO 639-1 code such as 'fr'")
        return code

    @model_validator(mode="after")
    def _needs_a_search_term(self):
        if not any((self.q, self.title, self.author, self.keyword, self.isbn)):
            raise ValueError("give at least one of q, title, author, keyword or isbn")
        return self

    @property
    def is_known_item(self) -> bool:
        return bool(self.title or self.author or self.isbn)
