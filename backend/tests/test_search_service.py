"""Search across targets: fan out, filter, merge, and survive outages.

Non-functional requirements covered here: results within 15 seconds, and a
source that fails is dropped for 24 hours.
"""
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import httpx
import pytest

from app.models import SearchQuery
from app.outage import OutageTracker
from app.search import SearchService
from app.sources.base import SourceError, SourceRejected, SourceTimeout
from tests.factories import make_book
from tests.fakes import FakeSource


def austen_text():
    return make_book(source="gutenberg", source_id="1342", title="Pride and Prejudice",
                     authors=["Jane Austen"], identifiers={})


def austen_audio():
    return make_book(source="librivox", source_id="253", title="Pride and Prejudice",
                     authors=["Jane Austen"], format="audio")


def build(sources, clock, **kwargs):
    outage = OutageTracker(clock=clock)
    return SearchService(sources=sources, outage=outage, **kwargs), outage


class TestFanOut:
    def test_default_timeout_leaves_room_inside_the_15_second_budget(self, clock):
        """Review 2026-10-11, #20: merging, serializing, the network and drawing come after the wait, so the
        wait for sources may not use the whole 15 s the spec allows for results."""
        service, _ = build([], clock)
        assert service.timeout_seconds == 12

    def test_every_source_is_queried_once_with_the_query(self, clock):
        sources = [FakeSource(n) for n in ("gutenberg", "librivox", "doab", "openlibrary")]
        service, _ = build(sources, clock)
        query = SearchQuery(q="dickens")
        service.search(query)
        assert all(s.calls == [query] for s in sources)

    def test_search_a_single_target(self, clock):
        g, l = FakeSource("gutenberg"), FakeSource("librivox")
        service, _ = build([g, l], clock)
        service.search(SearchQuery(q="x", sources=["librivox"]))
        assert g.calls == [] and len(l.calls) == 1

    def test_search_selected_targets(self, clock):
        srcs = {n: FakeSource(n) for n in ("gutenberg", "librivox", "doab", "openlibrary")}
        service, _ = build(list(srcs.values()), clock)
        service.search(SearchQuery(q="x", sources=["gutenberg", "doab"]))
        assert [n for n, s in srcs.items() if s.calls] == ["gutenberg", "doab"]

    def test_sources_are_queried_in_parallel(self, clock):
        sources = [FakeSource(n, delay=0.3) for n in ("gutenberg", "librivox", "doab", "openlibrary")]
        service, _ = build(sources, clock)
        started = time.monotonic()
        service.search(SearchQuery(q="x"))
        assert time.monotonic() - started < 0.9       # serial would take 1.2s

    def test_results_from_sources_are_merged_into_works(self, clock):
        service, _ = build([FakeSource("gutenberg", [austen_text()]),
                            FakeSource("librivox", [austen_audio()])], clock)
        response = service.search(SearchQuery(q="pride"))
        assert len(response.works) == 1
        assert response.works[0].sources == ["gutenberg", "librivox"]

    def test_no_results(self, clock):
        service, _ = build([FakeSource("gutenberg")], clock)
        response = service.search(SearchQuery(q="zzzz"))
        assert response.works == [] and response.unavailable_sources == []


class TestFilters:
    def test_format_text_removes_audio_books(self, clock):
        service, _ = build([FakeSource("gutenberg", [austen_text()]),
                            FakeSource("librivox", [austen_audio()])], clock)
        work = service.search(SearchQuery(q="pride", format="text")).works[0]
        assert work.formats == ["text"]
        assert [b.source for b in work.books] == ["gutenberg"]

    def test_format_audio_drops_works_with_no_audio(self, clock):
        service, _ = build([FakeSource("gutenberg", [austen_text()])], clock)
        assert service.search(SearchQuery(q="pride", format="audio")).works == []

    def test_language_filter_drops_other_languages(self, clock):
        fr = make_book(source="gutenberg", source_id="2", title="Les Misérables",
                       authors=["Victor Hugo"], language="fr")
        en = make_book(source="gutenberg", source_id="3", title="Les Miserables",
                       authors=["Victor Hugo"], language="en")
        service, _ = build([FakeSource("gutenberg", [fr, en])], clock)
        works = service.search(SearchQuery(q="hugo", language="fr")).works
        assert [b.source_id for w in works for b in w.books] == ["2"]


class TestKnownItemSearch:
    """A title/author/identifier search returns only that specific item."""

    @pytest.fixture
    def noisy(self):
        return [
            make_book(source="gutenberg", source_id="1400", title="Great Expectations",
                      authors=["Charles Dickens"]),
            make_book(source="librivox", source_id="9", title="Great Expectations",
                      authors=["Charles Dickens"], format="audio"),
            make_book(source="doab", source_id="a", title="Great Expectations: A Study Guide",
                      authors=["Someone Else"]),
            make_book(source="openlibrary", source_id="OL2W", title="Hard Times",
                      authors=["Charles Dickens"]),
            make_book(source="openlibrary", source_id="OL3W", title="Great Expectations",
                      authors=["A Different Writer"]),
        ]

    def run(self, clock, books, **query):
        by_source = {}
        for b in books:
            by_source.setdefault(b.source, []).append(b)
        service, _ = build([FakeSource(n, bs) for n, bs in by_source.items()], clock)
        return service.search(SearchQuery(**query)).works

    def test_title_only(self, clock, noisy):
        works = self.run(clock, noisy, title="Great Expectations")
        titles = {b.title for w in works for b in w.books}
        assert titles == {"Great Expectations"}

    def test_a_search_for_the_father_also_finds_the_son(self, clock):
        """Decided 2026-10-11 (review #21 suggested the opposite): "Charles Dickens" returns "Charles Dickens Jr."."""
        books = [
            make_book(source="gutenberg", source_id="1", title="Oliver Twist", authors=["Charles Dickens"]),
            make_book(source="gutenberg", source_id="2", title="Dickens Dictionary of London",
                      authors=["Charles Dickens Jr."]),
        ]
        works = self.run(clock, books, author="Charles Dickens")
        assert {b.source_id for w in works for b in w.books} == {"1", "2"}
        works = self.run(clock, books, author="CHarles Dickens, jr")
        assert {b.source_id for w in works for b in w.books} == {"2"}
        works = self.run(clock, books, author="Charles Dickens Jr.")
        assert {b.source_id for w in works for b in w.books} == {"2"}

    def test_a_middle_name_is_still_a_match(self, clock):
        books = [make_book(source="gutenberg", source_id="1", title="Frankenstein",
                           authors=["Mary Wollstonecraft Shelley"])]
        assert len(self.run(clock, books, author="Mary Shelley")) == 1

    def test_an_author_with_no_name_left_matches_nothing(self, clock):
        """"(anon)" is dropped as a parenthetical: an empty name is a subset of every author."""
        books = [make_book(source="gutenberg", source_id="1", title="Emma", authors=["Jane Austen"]),
                 make_book(source="gutenberg", source_id="2", title="Beowulf", authors=[])]
        assert self.run(clock, books, author="(anon)") == []
        assert self.run(clock, books, title="Emma", author="(anon)") == []

    def test_title_finds_books_with_a_subtitle_but_not_study_guides(self, clock):
        """Review 2026-10-10, #5 (option B): seen live for Moby Dick, Les Misérables, Black Beauty."""
        books = [
            make_book(source="gutenberg", source_id="2701", title="Moby-Dick; or, The Whale",
                      authors=["Herman Melville"]),
            make_book(source="librivox", source_id="7", title="Moby Dick",
                      authors=["Herman Melville"], format="audio"),
            make_book(source="doab", source_id="b", title="Moby Dick: A Study Guide",
                      authors=["Someone Else"]),
            make_book(source="openlibrary", source_id="OL9W", title="Moby Dick: Summary and Analysis",
                      authors=["Another Writer"]),
        ]
        works = self.run(clock, books, title="Moby Dick")
        assert {b.source_id for w in works for b in w.books} == {"2701", "7"}

    def test_title_finds_volumes_of_the_work(self, clock):
        books = [make_book(source="gutenberg", source_id="48731", language="fr",
                           title="Les misérables Tome I: Fantine", authors=["Victor Hugo"])]
        works = self.run(clock, books, title="Les Misérables")
        assert len(works) == 1

    def test_title_and_author_by_last_name(self, clock, noisy):
        works = self.run(clock, noisy, title="Great Expectations", author="Dickens")
        assert len(works) == 1
        assert {b.source for b in works[0].books} == {"gutenberg", "librivox"}

    def test_title_match_ignores_case_and_punctuation(self, clock, noisy):
        works = self.run(clock, noisy, title="great expectations!", author="Charles Dickens")
        assert len(works) == 1

    def test_author_only(self, clock, noisy):
        works = self.run(clock, noisy, author="Dickens")
        titles = sorted({w.title for w in works})
        assert titles == ["Great Expectations", "Hard Times"]
        assert all("Dickens" in " ".join(w.authors) for w in works)

    @pytest.mark.parametrize("isbn", ["9780140430721", "0140430725", "978-0-14-043072-1"])
    def test_isbn_returns_only_that_book(self, clock, isbn):
        wanted = make_book(source="openlibrary", source_id="OL1W", title="Pride and Prejudice",
                           authors=["Jane Austen"], identifiers={"isbn": ["9780140430721"]})
        other = make_book(source="openlibrary", source_id="OL2W", title="Emma",
                          authors=["Jane Austen"], identifiers={"isbn": ["9780141439587"]})
        works = self.run(clock, [wanted, other], isbn=isbn)
        assert [w.title for w in works] == ["Pride and Prejudice"]

    def test_exploratory_search_is_not_narrowed(self, clock, noisy):
        works = self.run(clock, noisy, q="great expectations")
        titles = {b.title for w in works for b in w.books}
        assert {"Great Expectations", "Hard Times", "Great Expectations: A Study Guide"} <= titles

    def test_keyword_search_is_not_narrowed(self, clock, noisy):
        works = self.run(clock, noisy, keyword="orphans")
        assert len(works) >= 3


def reasons(response) -> dict[str, str]:
    """Why each source is missing from a response: outage, timeout, busy, rejected or error."""
    return {s.source: s.reason for s in response.skipped}


class TestOutages:
    def test_failing_source_is_dropped_and_reported(self, clock):
        good = FakeSource("gutenberg", [austen_text()])
        bad = FakeSource("librivox", error=SourceError("500"))
        service, _ = build([good, bad], clock)
        response = service.search(SearchQuery(q="pride"))
        assert [w.sources for w in response.works] == [["gutenberg"]]
        assert response.unavailable_sources == ["librivox"]
        assert reasons(response) == {"librivox": "outage"}

    @pytest.mark.parametrize("error", [SourceError("down"), SourceError("HTTP 503")])
    def test_a_source_error_counts_as_an_outage(self, clock, error):
        service, outage = build([FakeSource("doab", error=error)], clock)
        service.search(SearchQuery(q="x"))
        assert not outage.is_available("doab")

    @pytest.mark.parametrize("error", [
        RuntimeError("bug in adapter"), IndexError("list index out of range"),
        httpx.ConnectError("refused"),   # adapters wrap these in SourceError; a bare one is our bug
        SourceRejected("HTTP 400"),      # the source turned down our request
    ])
    def test_our_own_failures_are_not_an_outage(self, clock, error):
        """Only the source's fault may affect other users: a bug in our code or a request the
        source rejects fails this search for that source only."""
        bad = FakeSource("doab", error=error)
        service, outage = build([bad, FakeSource("gutenberg", [austen_text()])], clock)
        response = service.search(SearchQuery(q="x"))
        assert response.unavailable_sources == ["doab"]
        assert reasons(response) == {"doab": "rejected" if isinstance(error, SourceRejected) else "error"}
        assert [w.sources for w in response.works] == [["gutenberg"]]
        assert outage.is_available("doab")
        service.search(SearchQuery(q="y"))
        assert len(bad.calls) == 2

    def test_failed_source_is_not_called_again_for_24_hours(self, clock):
        bad = FakeSource("librivox", error=SourceError("500"))
        service, _ = build([bad, FakeSource("gutenberg")], clock)
        service.search(SearchQuery(q="x"))
        clock.advance(hours=23)
        response = service.search(SearchQuery(q="y"))
        assert len(bad.calls) == 1
        assert response.unavailable_sources == ["librivox"]

    def test_source_is_tried_again_after_24_hours(self, clock):
        flaky = FakeSource("librivox", [austen_audio()], error=SourceError("500"))
        service, _ = build([flaky], clock)
        service.search(SearchQuery(q="x"))
        flaky._error = None
        clock.advance(hours=24)
        response = service.search(SearchQuery(q="x"))
        assert len(flaky.calls) == 2
        assert response.unavailable_sources == []
        assert len(response.works) == 1

    def test_all_sources_down_returns_empty_not_an_exception(self, clock):
        srcs = [FakeSource(n, error=SourceError("x")) for n in ("gutenberg", "librivox")]
        service, _ = build(srcs, clock)
        response = service.search(SearchQuery(q="x"))
        assert response.works == []
        assert response.unavailable_sources == ["gutenberg", "librivox"]
        assert reasons(response) == {"gutenberg": "outage", "librivox": "outage"}

    def test_outage_of_an_unselected_source_is_not_reported(self, clock):
        service, outage = build([FakeSource("gutenberg"), FakeSource("librivox")], clock)
        outage.record_failure("librivox")
        response = service.search(SearchQuery(q="x", sources=["gutenberg"]))
        assert response.unavailable_sources == []

    def test_outage_of_a_selected_source_is_reported(self, clock):
        service, outage = build([FakeSource("gutenberg"), FakeSource("librivox")], clock)
        outage.record_failure("librivox")
        response = service.search(SearchQuery(q="x", sources=["librivox"]))
        assert response.unavailable_sources == ["librivox"]
        assert reasons(response) == {"librivox": "outage"}


class TestTimeout:
    @pytest.mark.slow
    def test_a_slow_source_does_not_hold_up_the_rest(self, clock):
        fast = FakeSource("gutenberg", [austen_text()])
        slow = FakeSource("doab", [], delay=2.0)
        service, _ = build([fast, slow], clock, timeout_seconds=0.3)
        started = time.monotonic()
        response = service.search(SearchQuery(q="pride"))
        assert time.monotonic() - started < 1.2
        assert len(response.works) == 1
        assert response.unavailable_sources == ["doab"]      # no results from it this time
        assert reasons(response) == {"doab": "timeout"}

    @pytest.mark.slow
    def test_a_slow_source_is_not_marked_down(self, clock):
        """A timeout is not an outage: the source is asked again on the next search."""
        slow = FakeSource("doab", [], delay=0.6)
        service, outage = build([slow], clock, timeout_seconds=0.2)
        service.search(SearchQuery(q="pride"))
        assert outage.is_available("doab")
        response = service.search(SearchQuery(q="pride"))
        assert len(slow.calls) == 2
        assert response.unavailable_sources == ["doab"]

    def test_an_http_timeout_inside_a_source_is_not_an_outage(self, clock):
        flaky = FakeSource("librivox", error=SourceTimeout("read timeout"))
        service, outage = build([flaky], clock)
        response = service.search(SearchQuery(q="x"))
        assert response.unavailable_sources == ["librivox"]
        assert reasons(response) == {"librivox": "timeout"}
        assert outage.is_available("librivox")


class TestSearchesInFlight:
    """Review 2026-10-10, #6: a slow source must not pile up threads, since it is asked again every time."""

    def test_default_limit_is_4_searches_per_source(self, clock):
        service, _ = build([], clock)
        assert service.max_in_flight == 4

    @pytest.mark.slow
    def test_a_slow_source_holds_at_most_its_limit_of_threads(self, clock):
        slow = FakeSource("doab", [], delay=1.0)
        service, _ = build([slow], clock, timeout_seconds=0.02, max_in_flight=3)
        before = threading.active_count()
        for _ in range(20):
            service.search(SearchQuery(q="pride"))
        assert len(slow.calls) == 3
        assert threading.active_count() - before <= 3

    @pytest.mark.slow
    def test_a_source_at_its_limit_is_reported_but_not_marked_down(self, clock):
        fast = FakeSource("gutenberg", [austen_text()])
        slow = FakeSource("doab", [], delay=1.0)
        service, outage = build([fast, slow], clock, timeout_seconds=0.02, max_in_flight=1)
        service.search(SearchQuery(q="pride"))
        response = service.search(SearchQuery(q="pride"))     # the first doab search is still running
        assert len(slow.calls) == 1
        assert response.unavailable_sources == ["doab"]
        assert reasons(response) == {"doab": "busy"}
        assert len(response.works) == 1
        assert outage.is_available("doab")

    @pytest.mark.slow
    def test_a_source_is_asked_again_once_its_slow_search_finishes(self, clock):
        slow = FakeSource("doab", [], delay=0.3)
        service, _ = build([slow], clock, timeout_seconds=0.02, max_in_flight=1)
        service.search(SearchQuery(q="pride"))
        time.sleep(0.5)
        service.search(SearchQuery(q="pride"))
        assert len(slow.calls) == 2

    def test_finished_searches_free_their_place(self, clock):
        """Back-to-back searches of a fast source are never skipped, even with a limit of 1."""
        fast = FakeSource("gutenberg", [austen_text()])
        service, _ = build([fast], clock, max_in_flight=1)
        for _ in range(10):
            assert service.search(SearchQuery(q="pride")).unavailable_sources == []
        assert len(fast.calls) == 10

    def test_concurrent_searches_within_the_limit_all_reach_the_source(self, clock):
        fast = FakeSource("gutenberg", [austen_text()], delay=0.1)
        service, _ = build([fast], clock, max_in_flight=4)
        with ThreadPoolExecutor(max_workers=4) as users:
            responses = list(users.map(service.search, [SearchQuery(q="pride")] * 4))
        assert all(r.unavailable_sources == [] for r in responses)
        assert len(fast.calls) == 4
