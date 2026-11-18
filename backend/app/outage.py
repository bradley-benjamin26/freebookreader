"""Source outage rule (spec.md): when a source fails 3 times in a row, stop using it for 24 hours."""
import threading
from datetime import datetime, timedelta, timezone
from typing import Callable


def _now() -> datetime:
    return datetime.now(timezone.utc)


class OutageTracker:
    def __init__(self, clock: Callable[[], datetime] = _now, cooldown: timedelta = timedelta(hours=24),
                 failures: int = 3):
        self.clock = clock
        self.cooldown = cooldown
        self.failures = failures        # in a row; one 5xx or dropped connection is not an outage
        self._failed_at: dict[str, datetime] = {}
        self._in_a_row: dict[str, int] = {}
        self._lock = threading.Lock()   # sources fail from worker threads

    def record_failure(self, source: str) -> None:
        with self._lock:
            count = self._in_a_row.get(source, 0) + 1
            if count >= self.failures:
                self._failed_at[source] = self.clock()
                count = 0
            self._in_a_row[source] = count

    def record_success(self, source: str) -> None:
        with self._lock:
            self._in_a_row.pop(source, None)

    def retry_at(self, source: str) -> datetime | None:
        """When the source may be used again, or None if it is available now."""
        with self._lock:
            failed_at = self._failed_at.get(source)
        if failed_at is None:
            return None
        until = failed_at + self.cooldown
        return until if self.clock() < until else None

    def is_available(self, source: str) -> bool:
        return self.retry_at(source) is None
