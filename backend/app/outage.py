"""Source outage rule (spec.md): when a source fails, stop using it for 24 hours."""
import threading
from datetime import datetime, timedelta, timezone
from typing import Callable


def _now() -> datetime:
    return datetime.now(timezone.utc)


class OutageTracker:
    def __init__(self, clock: Callable[[], datetime] = _now, cooldown: timedelta = timedelta(hours=24)):
        self.clock = clock
        self.cooldown = cooldown
        self._failed_at: dict[str, datetime] = {}
        self._lock = threading.Lock()   # sources fail from worker threads

    def record_failure(self, source: str) -> None:
        with self._lock:
            self._failed_at[source] = self.clock()

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

    def unavailable(self) -> list[str]:
        with self._lock:
            names = list(self._failed_at)
        return sorted(n for n in names if not self.is_available(n))
