import time


class FakeSource:
    """A stand-in for a source adapter that records calls."""

    def __init__(self, name, books=(), error=None, delay=0.0):
        self.name = name
        self._books = list(books)
        self._error = error
        self._delay = delay
        self.calls = []

    def search(self, query):
        self.calls.append(query)
        if self._delay:
            time.sleep(self._delay)
        if self._error is not None:
            raise self._error
        return list(self._books)
