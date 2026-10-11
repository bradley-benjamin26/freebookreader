"""Non-functional requirement: when a source is down, stop returning results
from it (and stop querying it) for a 24 hour period."""
from datetime import timedelta

from app.outage import OutageTracker


def test_sources_are_available_by_default(clock):
    assert OutageTracker(clock=clock).is_available("gutenberg")


def test_default_cooldown_is_24_hours(clock):
    assert OutageTracker(clock=clock).cooldown == timedelta(hours=24)


def test_a_failure_marks_the_source_unavailable(clock):
    tracker = OutageTracker(clock=clock)
    tracker.record_failure("librivox")
    assert not tracker.is_available("librivox")


def test_other_sources_are_unaffected(clock):
    tracker = OutageTracker(clock=clock)
    tracker.record_failure("librivox")
    for name in ("gutenberg", "doab", "openlibrary"):
        assert tracker.is_available(name)


def test_still_unavailable_just_before_24_hours(clock):
    tracker = OutageTracker(clock=clock)
    tracker.record_failure("doab")
    clock.advance(hours=23, minutes=59, seconds=59)
    assert not tracker.is_available("doab")


def test_available_again_after_24_hours(clock):
    tracker = OutageTracker(clock=clock)
    tracker.record_failure("doab")
    clock.advance(hours=24)
    assert tracker.is_available("doab")


def test_cooldown_is_configurable(clock):
    tracker = OutageTracker(clock=clock, cooldown=timedelta(minutes=5))
    tracker.record_failure("doab")
    clock.advance(minutes=6)
    assert tracker.is_available("doab")


def test_a_second_failure_after_recovery_starts_a_new_period(clock):
    tracker = OutageTracker(clock=clock)
    tracker.record_failure("doab")
    clock.advance(hours=25)
    tracker.record_failure("doab")
    clock.advance(hours=23)
    assert not tracker.is_available("doab")


def test_unavailable_lists_sources_in_cooldown(clock):
    tracker = OutageTracker(clock=clock)
    tracker.record_failure("doab")
    tracker.record_failure("librivox")
    assert tracker.unavailable() == ["doab", "librivox"]
    clock.advance(hours=24)
    assert tracker.unavailable() == []


def test_retry_at_reports_when_the_source_returns(clock):
    tracker = OutageTracker(clock=clock)
    start = clock()
    tracker.record_failure("doab")
    assert tracker.retry_at("doab") == start + timedelta(hours=24)
    assert tracker.retry_at("gutenberg") is None
