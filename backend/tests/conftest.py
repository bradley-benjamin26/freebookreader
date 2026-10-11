"""Shared fixtures. Sample payloads live in ../samples (real captured responses)."""
import json
from datetime import datetime, timezone
from pathlib import Path

import httpx
import pytest

SAMPLES = Path(__file__).resolve().parents[2] / "samples"


@pytest.fixture
def sample_text():
    def load(name: str) -> str:
        return (SAMPLES / name).read_text(encoding="utf-8")
    return load


@pytest.fixture
def sample_json():
    def load(name: str):
        return json.loads((SAMPLES / name).read_text(encoding="utf-8"))
    return load


class Recorder:
    """An httpx transport that records requests and answers from a function."""

    def __init__(self, respond):
        self.requests: list[httpx.Request] = []
        self._respond = respond
        self.client = httpx.Client(transport=httpx.MockTransport(self._handle))

    def _handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        result = self._respond(request)
        if isinstance(result, Exception):
            raise result
        return result

    @property
    def last(self) -> httpx.Request:
        return self.requests[-1]

    def params(self, index: int = -1) -> dict[str, str]:
        return dict(self.requests[index].url.params)


@pytest.fixture
def recorder():
    """recorder(json=..., text=..., status=200) -> Recorder answering every call the same."""
    def build(*, json=None, text=None, status=200, error=None, respond=None):
        def default(request):
            if error is not None:
                return error
            if json is not None:
                return httpx.Response(status, json=json)
            return httpx.Response(status, text=text or "")
        return Recorder(respond or default)
    return build


class FakeClock:
    def __init__(self, start=None):
        self.current = start or datetime(2026, 10, 10, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.current

    def advance(self, **kwargs):
        from datetime import timedelta
        self.current += timedelta(**kwargs)


@pytest.fixture
def clock():
    return FakeClock()
