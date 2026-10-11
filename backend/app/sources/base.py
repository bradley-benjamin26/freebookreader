"""What every source adapter has in common."""
from typing import Protocol

import httpx

from app.models import Book, SearchQuery


class SourceError(Exception):
    """The source could not be searched (down, slow, or answered something unusable)."""


class SourceTimeout(SourceError):
    """The source was too slow. Not an outage: it is asked again on the next search."""


class SourceRejected(SourceError):
    """The source answered 4xx: it turned down our request. Not an outage: the request, not the
    source, was at fault, so only this search goes without the source."""


class Source(Protocol):
    name: str

    def search(self, query: SearchQuery) -> list[Book]: ...


def get(client: httpx.Client, url: str, params, *, not_found_is_empty: bool = False,
        ok_statuses: tuple[int, ...] = ()) -> httpx.Response | None:
    """GET a URL, turning transport errors and error statuses into SourceError.

    Returns None for a 404 when not_found_is_empty (a page past the end, for example).
    Statuses in ok_statuses are returned for the caller to handle.
    """
    try:
        response = client.get(url, params=params)
    except httpx.TimeoutException as error:
        raise SourceTimeout(f"{url}: {error!r}") from error
    except httpx.HTTPError as error:
        raise SourceError(f"{url}: {error!r}") from error
    if response.status_code == 404 and not_found_is_empty:
        return None
    if response.status_code in ok_statuses:
        return response
    if 400 <= response.status_code < 500:
        raise SourceRejected(f"{url}: HTTP {response.status_code}")
    if response.status_code >= 500:
        raise SourceError(f"{url}: HTTP {response.status_code}")
    return response


def get_json(client: httpx.Client, url: str, params, *, not_found_is_empty: bool = False):
    response = get(client, url, params, not_found_is_empty=not_found_is_empty)
    if response is None:
        return None
    try:
        return response.json()
    except ValueError as error:
        raise SourceError(f"{url}: response is not JSON") from error
