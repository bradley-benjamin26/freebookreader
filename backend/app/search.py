"""Search across sources: fan out in parallel, filter, merge into works, and survive outages."""
import logging
import threading
from concurrent.futures import ThreadPoolExecutor, wait
from typing import Literal

from pydantic import BaseModel

from app.merge import merge_books
from app.models import Book, SearchQuery, Work
from app.normalize import author_key, normalize_isbn, title_matches
from app.outage import OutageTracker
from app.sources.base import Source, SourceError, SourceRejected, SourceTimeout

log = logging.getLogger(__name__)

# Searches one source may have running at once. A slow source is asked again on every search, and its
# threads outlive the response, so without a limit a stuck source would pile up threads under load.
MAX_IN_FLIGHT = 4


class SkippedSource(BaseModel):
    source: str
    # outage: down, not asked for up to 24 hours. timeout: too slow, asked again next time.
    # busy: it still has MAX_IN_FLIGHT searches running. rejected: it answered 4xx. error: our adapter crashed.
    reason: Literal["outage", "timeout", "busy", "rejected", "error"]


class SearchResponse(BaseModel):
    works: list[Work]
    unavailable_sources: list[str]   # every selected source missing from this response, whatever the reason
    skipped: list[SkippedSource] = []   # the same sources with the reason, in source-name order


class SearchService:
    def __init__(self, sources: list[Source], outage: OutageTracker, timeout_seconds: float = 12,
                 max_in_flight: int = MAX_IN_FLIGHT):
        self.sources = list(sources)
        self.outage = outage
        self.timeout_seconds = timeout_seconds
        self.max_in_flight = max_in_flight
        self._slots = {s.name: threading.BoundedSemaphore(max_in_flight) for s in self.sources}
        # Every running search holds one of its source's slots, so a task never waits for a worker.
        self._executor = ThreadPoolExecutor(max_workers=max(1, len(self.sources) * max_in_flight),
                                            thread_name_prefix="source-search")

    def search(self, query: SearchQuery) -> SearchResponse:
        selected = [s for s in self.sources if query.sources is None or s.name in query.sources]
        to_query = [s for s in selected if self.outage.is_available(s.name)]
        books, missing = self._fan_out(to_query, query)
        books = [b for b in books if _passes_filters(b, query)]
        works = merge_books(books)
        if query.is_known_item:
            works = [w for w in works if any(_is_the_item(b, query) for b in w.books)]
        reasons = {s.name: "outage" for s in selected if not self.outage.is_available(s.name)}
        reasons.update(missing)    # a source that failed just now is in an outage too, and says so
        skipped = [SkippedSource(source=name, reason=reasons[name]) for name in sorted(reasons)]
        return SearchResponse(works=works, unavailable_sources=sorted(reasons), skipped=skipped)

    def _fan_out(self, sources: list[Source], query: SearchQuery) -> tuple[list[Book], dict[str, str]]:
        """Books from every source that answered, and why each other source is missing.

        A slow source is left out of this response but is not marked down: it is asked again next time.
        So is a source that rejected our request (4xx) or whose adapter crashed: that is our fault,
        not the source's. Only a SourceError (connection failure, 5xx, unreadable answer) starts
        its outage period. A source that already has max_in_flight searches running (left behind by
        earlier timeouts) is not asked, and is left out of this search only.
        """
        missing: dict[str, str] = {}    # source name -> reason
        futures = {}
        for source in sources:
            slot = self._slots[source.name]
            if not slot.acquire(blocking=False):
                log.warning("source %s skipped: %s searches still running", source.name, self.max_in_flight)
                missing[source.name] = "busy"
                continue
            futures[self._executor.submit(_run, source, query, slot)] = source
        if not futures:
            return [], missing
        # Do not wait for slow sources; their searches finish in the background and then free their slot.
        done, not_done = wait(futures, timeout=self.timeout_seconds)
        books: list[Book] = []
        for future in futures:          # in source order, so results keep a stable order
            source = futures[future]
            if future in not_done:
                log.warning("source %s timed out after %ss", source.name, self.timeout_seconds)
                missing[source.name] = "timeout"
                continue
            error = future.exception()
            if isinstance(error, SourceTimeout):
                log.warning("source %s timed out: %s", source.name, error)
                missing[source.name] = "timeout"
            elif isinstance(error, SourceRejected):
                log.warning("source %s rejected the request: %s", source.name, error)
                missing[source.name] = "rejected"
            elif isinstance(error, SourceError):
                log.warning("source %s failed: %r", source.name, error)
                self.outage.record_failure(source.name)
                missing[source.name] = "outage"
            elif error is not None:
                log.error("source %s adapter crashed", source.name, exc_info=error)
                missing[source.name] = "error"
            else:
                books.extend(future.result())
        return books, missing


def _run(source: Source, query: SearchQuery, slot: threading.BoundedSemaphore) -> list[Book]:
    try:
        return source.search(query)
    finally:
        slot.release()


def _passes_filters(book: Book, query: SearchQuery) -> bool:
    if query.format and book.format != query.format:
        return False
    if query.language and book.language != query.language:   # SearchQuery normalized it
        return False
    return True


def _is_the_item(book: Book, query: SearchQuery) -> bool:
    """A known-item search keeps only works with a book matching every given title/author/ISBN."""
    if query.title and not title_matches(book.title, query.title):
        return False
    if query.author and not any(_same_author(a, query.author) for a in book.authors):
        return False
    if query.isbn:
        isbn = normalize_isbn(query.isbn)
        have = {normalize_isbn(i) for i in book.identifiers.get("isbn", [])}
        if isbn is None or isbn not in have:
            return False
    return True


def _same_author(book_author: str, wanted: str) -> bool:
    """Every word of the wanted name is in the book's author ("Mary Shelley" finds "Mary Wollstonecraft
    Shelley", "Charles Dickens" finds "Charles Dickens Jr."). A name with nothing left in it ("(anon)")
    is nobody."""
    wanted_words = set(author_key(wanted).split())
    have = set(author_key(book_author).split())
    return bool(wanted_words) and wanted_words <= have
