"""Builders for Book objects so tests only spell out what they care about."""
from app.models import Book


def make_book(**overrides) -> Book:
    source = overrides.get("source", "gutenberg")
    source_id = overrides.get("source_id", "1")
    defaults = dict(
        source=source,
        source_id=source_id,
        title="Untitled",
        authors=[],
        narrators=[],
        contributors=[],
        language="en",
        format="text",
        pages=None,
        audio_seconds=None,
        identifiers={},
        url=f"https://example.org/{source}/{source_id}",
        cover_url=None,
        content={},
        chapters=[],
        access="open",
    )
    defaults.update(overrides)
    return Book(**defaults)
