"""Hostile and odd user input must never crash an adapter (review 2026-10-10, finding #1).

An adapter either returns a list or raises SourceError. Anything else is a bug in our code, and
the search service must not let it take the source offline for everyone.
"""
import httpx
import pytest

from app.models import MAX_PAGE, MAX_TEXT_LENGTH, SearchQuery
from app.sources.base import SourceError, SourceRejected
from app.sources.doab import DoabSource
from app.sources.gutendex import GutendexSource
from app.sources.librivox import LibriVoxSource
from app.sources.openlibrary import OpenLibrarySource

EMPTY_ATOM = '<feed xmlns="http://www.w3.org/2005/Atom"></feed>'

ADAPTERS = {
    "gutenberg": (GutendexSource, lambda: httpx.Response(200, json={"count": 0, "results": []})),
    "librivox": (LibriVoxSource, lambda: httpx.Response(200, json={"books": []})),
    "openlibrary": (OpenLibrarySource, lambda: httpx.Response(200, json={"numFound": 0, "docs": []})),
    "doab": (DoabSource, lambda: httpx.Response(200, text=EMPTY_ATOM)),
}

HOSTILE = [
    {"author": "(anon)"},
    {"author": "(1812-1870)"},
    {"author": "!!!"},
    {"title": "(anon)", "author": "(anon)"},
    {"q": "!?.,;:"},
    {"q": "x" * MAX_TEXT_LENGTH},
    {"keyword": "%%%"},
    {"isbn": "not-an-isbn"},
    {"q": "history", "page": MAX_PAGE},
]


def build(name, recorder, respond=None):
    cls, ok = ADAPTERS[name]
    rec = recorder(respond=lambda request: (respond or ok)())
    return cls(client=rec.client, base_url="https://source.test"), rec


@pytest.mark.parametrize("name", ADAPTERS)
@pytest.mark.parametrize("fields", HOSTILE, ids=lambda f: repr(f)[:40])
def test_hostile_input_returns_a_list(name, fields, recorder):
    source, _ = build(name, recorder)
    assert isinstance(source.search(SearchQuery(**fields)), list)


@pytest.mark.parametrize("name", ADAPTERS)
@pytest.mark.parametrize("status", [400, 403, 414])
def test_a_4xx_answer_is_a_rejection_not_an_outage(name, status, recorder):
    source, _ = build(name, recorder, respond=lambda: httpx.Response(status, text="no"))
    with pytest.raises(SourceRejected):
        source.search(SearchQuery(q="history"))


def test_a_rejection_is_still_a_source_error():
    assert issubclass(SourceRejected, SourceError)


@pytest.mark.parametrize("author", ["(anon)", "(1812-1870)"])
def test_librivox_makes_no_request_for_an_author_with_no_name_left(author, recorder):
    source, rec = build("librivox", recorder)
    assert source.search(SearchQuery(author=author)) == []
    assert rec.requests == []
