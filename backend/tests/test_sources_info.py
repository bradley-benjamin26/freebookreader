"""Content for the Source About pages (spec.md > UX > Source About Pages).

Each source has a page saying what it is, how it works, how to access it
normally, and a donation button. Whether the pages are *usable* is a manual
usability test; here we only check the content exists.
"""
import pytest

from app.sources_info import SOURCES, get_source_info

IDS = ["doab", "gutenberg", "librivox", "openlibrary"]


def test_there_is_one_entry_per_source():
    assert sorted(s.id for s in SOURCES) == IDS


@pytest.mark.parametrize("source_id, name", [
    ("gutenberg", "Project Gutenberg"), ("librivox", "LibriVox"),
    ("doab", "DOAB"), ("openlibrary", "Open Library"),
])
def test_display_names(source_id, name):
    assert get_source_info(source_id).name == name


@pytest.mark.parametrize("source_id", IDS)
def test_every_page_has_the_required_content(source_id):
    info = get_source_info(source_id)
    assert len(info.description) > 40           # what it is
    assert len(info.how_it_works) > 40          # how it works in this app
    assert len(info.how_to_access) > 40         # how to use it directly
    assert info.website_url.startswith("https://")
    assert info.donation_url.startswith("https://")


@pytest.mark.parametrize("source_id", IDS)
def test_descriptions_are_plain_text(source_id):
    info = get_source_info(source_id)
    for text in (info.description, info.how_it_works, info.how_to_access):
        assert "<" not in text and ">" not in text


def test_formats_offered_by_each_source():
    assert get_source_info("librivox").formats == ["audio"]
    assert get_source_info("gutenberg").formats == ["text"]
    assert get_source_info("doab").formats == ["text"]
    assert get_source_info("openlibrary").formats == ["text"]


def test_in_app_reading_flags_match_the_reader_rules():
    assert get_source_info("gutenberg").in_app is True
    assert get_source_info("doab").in_app is True        # its PDFs
    assert get_source_info("librivox").in_app is True
    assert get_source_info("openlibrary").in_app is False


def test_unknown_source_raises_key_error():
    with pytest.raises(KeyError):
        get_source_info("hathitrust")
