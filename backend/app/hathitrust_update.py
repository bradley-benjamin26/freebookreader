"""Keep the HathiTrust index up to date from the Hathifiles (decision_hathitrust.md, decision 2).

    cd backend && source venv/bin/activate && python -m app.hathitrust_update

The first run downloads the newest monthly file (1.2 GB) and builds the index; later runs download only the daily
update files since the last run. A new monthly file means a rebuild, which is also how volumes that HathiTrust
removed leave the index (the update files do not say). Run it nightly, like `updatecatalog` for Gutendex.
"""
import re
import sys
import zlib
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Iterator

import httpx

from app.hathifile import Volume, parse_line
from app.hathitrust_index import HathiIndex, IndexBusy, IndexState

_NAME = re.compile(r"^hathi_(full|upd)_(\d{8})\.txt\.gz$")


class UpdateError(Exception):
    """The Hathifiles could not be read. The index is left as it was."""


@dataclass
class Plan:
    full: dict | None = None          # the monthly file to rebuild from, or None
    updates: list[dict] = field(default_factory=list)      # daily files to apply, oldest first
    missing: str | None = None        # "YYYYMMDD" of a daily file not published: the updates stop before it

    @property
    def is_empty(self) -> bool:
        return self.full is None and not self.updates


@dataclass
class UpdateResult:
    rebuilt: bool
    updates_applied: int
    volumes: int                      # in the index now
    through: str | None               # "YYYYMMDD" of the newest file applied


def plan_update(file_list: list[dict], state: IndexState | None) -> Plan:
    """Which files to download, given the published list and what the index was built from."""
    fulls, updates = [], []
    for entry in file_list:
        match = _NAME.match(str(entry.get("filename", "")))
        if not match or not entry.get("url") or not _is_date(match.group(2)):
            continue
        (fulls if match.group(1) == "full" else updates).append((match.group(2), entry))
    fulls.sort(key=lambda pair: pair[0])
    updates.sort(key=lambda pair: pair[0])

    newest_full = fulls[-1] if fulls else None
    rebuild = state is None
    if state is not None:
        built_from = _NAME.match(state.full_file)
        rebuild = bool(newest_full) and (built_from is None or newest_full[0] > built_from.group(2))
        # Only about 70 days of updates stay listed: if the oldest is later than the day after our last, some were missed.
        if updates and _next_day(state.updated_through) < updates[0][0]:
            rebuild = True
    if rebuild:
        if newest_full is None:
            raise UpdateError("the file list has no monthly (full) file to build the index from")
        applied, missing = _consecutive([(d, e) for d, e in updates if d >= newest_full[0]], newest_full[0])
        return Plan(full=newest_full[1], updates=applied, missing=missing)
    applied, missing = _consecutive([(d, e) for d, e in updates if d > state.updated_through],
                                    state.updated_through)
    return Plan(updates=applied, missing=missing)


def _consecutive(updates: list[tuple[str, dict]], since: str) -> tuple[list[dict], str | None]:
    """The updates up to the first day without one after `since` (that day's file may come late, and the
    later ones must not be applied before it), and that day."""
    applied, expected = [], _next_day(since)
    for date, entry in updates:
        if date < expected:            # the monthly file's own day
            applied.append(entry)
            continue
        if date != expected:
            return applied, expected
        applied.append(entry)
        expected = _next_day(date)
    return applied, None


def update_index(client: httpx.Client, index: HathiIndex, file_list_url: str, log=lambda message: None) -> UpdateResult:
    try:
        with index.writing():
            return _update(client, index, file_list_url, log)
    except IndexBusy as error:
        raise UpdateError(f"an update is already running: {error}") from error


def _update(client: httpx.Client, index: HathiIndex, file_list_url: str, log) -> UpdateResult:
    plan = plan_update(_fetch_file_list(client, file_list_url), index.state() if index.exists() else None)
    through = None
    if plan.full is not None:
        name = plan.full["filename"]
        through = _date_of(name)
        log(f"building the index from {name}")
        changes = _checked(iter_gzip_lines(client, plan.full["url"]), name, full=True)
        index.replace_all((v for _, v in changes if v is not None), IndexState(name, through))
    full_file = index.state().full_file
    for entry in plan.updates:
        through = _date_of(entry["filename"])
        log(f"applying {entry['filename']}")
        changes = _checked(iter_gzip_lines(client, entry["url"]), entry["filename"], full=False)
        index.apply(changes, IndexState(full_file, through))
    if plan.missing is not None:
        raise UpdateError(f"the daily file for {plan.missing} is not published yet; the index is up to date "
                          f"through the day before, and the next run goes on from there")
    if plan.is_empty:
        log("the index is up to date")
    return UpdateResult(rebuilt=plan.full is not None, updates_applied=len(plan.updates),
                        volumes=index.count(), through=through)


def _checked(lines: Iterator[str], name: str, full: bool) -> Iterator[tuple[str, Volume | None]]:
    """The changes in a Hathifile, failing at the end (before the index commits) when it was not a Hathifile:
    an error page that came gzipped, say. A monthly file must also have at least one open book."""
    lines_seen = records = kept = 0
    for line in lines:
        if line.strip():
            lines_seen += 1
        parsed = parse_line(line)
        if parsed is None:
            continue
        records += 1
        kept += parsed[1] is not None
        yield parsed
    if lines_seen and not records:
        raise UpdateError(f"{name}: no line in it is a Hathifile record")
    if full and not kept:
        raise UpdateError(f"{name}: it has no volume anyone can read; the index was not replaced")


def _fetch_file_list(client: httpx.Client, url: str) -> list[dict]:
    try:
        response = client.get(url)
    except httpx.HTTPError as error:
        raise UpdateError(f"{url}: {error!r}") from error
    if response.status_code != 200:
        raise UpdateError(f"{url}: HTTP {response.status_code}")
    try:
        data = response.json()
    except ValueError as error:
        raise UpdateError(f"{url}: the file list is not JSON") from error
    if not isinstance(data, list):
        raise UpdateError(f"{url}: the file list is not a list")
    return [entry for entry in data if isinstance(entry, dict)]


def iter_gzip_lines(client: httpx.Client, url: str) -> Iterator[str]:
    """The lines of a .gz file, decompressed while it downloads (the monthly file does not fit in memory)."""
    decompressor = zlib.decompressobj(wbits=31)           # gzip
    pending = b""
    try:
        with client.stream("GET", url, headers={"Accept-Encoding": "identity"}) as response:
            if response.status_code != 200:
                raise UpdateError(f"{url}: HTTP {response.status_code}")
            for chunk in response.iter_raw():
                data = chunk
                while data:
                    pending += decompressor.decompress(data)
                    data = b""
                    if decompressor.eof and decompressor.unused_data:      # a second gzip member
                        data = decompressor.unused_data
                        decompressor = zlib.decompressobj(wbits=31)
                *lines, pending = pending.split(b"\n")
                for line in lines:
                    yield line.decode("utf-8", errors="replace")
    except httpx.HTTPError as error:
        raise UpdateError(f"{url}: {error!r}") from error
    except zlib.error as error:
        raise UpdateError(f"{url}: not a readable gzip file ({error})") from error
    if not decompressor.eof:
        raise UpdateError(f"{url}: the download ended early")
    if pending:
        yield pending.decode("utf-8", errors="replace")


def _is_date(text: str) -> bool:
    try:
        datetime.strptime(text, "%Y%m%d")
    except ValueError:
        return False
    return True


def _next_day(date: str) -> str:
    return (datetime.strptime(date, "%Y%m%d") + timedelta(days=1)).strftime("%Y%m%d")


def _date_of(filename: str) -> str:
    return _NAME.match(filename).group(2)


def main(argv: list[str] | None = None) -> int:
    from app.config import Settings, build_http_client
    settings = Settings.from_env()
    client = build_http_client(settings)
    client.timeout = httpx.Timeout(60.0)          # a monthly file is slow, but each read of it is not
    index = HathiIndex(settings.hathitrust_index)
    try:
        result = update_index(client, index, settings.hathitrust_file_list_url, log=lambda m: print(m, flush=True))
    except UpdateError as error:
        print(f"HathiTrust update failed: {error}", file=sys.stderr)
        return 1
    print(f"{result.volumes} volumes in {index.path}"
          + (f", through {result.through}" if result.through else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
