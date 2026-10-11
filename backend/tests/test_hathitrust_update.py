"""Keeping the HathiTrust index up to date from the Hathifiles (decision_hathitrust.md, decision 2).

The file list is the real hathi_file_list.json shape: {filename, full, size, created, modified, url}.
`python -m app.hathitrust_update` is the nightly job, like `updatecatalog` for Gutendex.
"""
import gzip
import json

import httpx
import pytest

from app.hathitrust_index import HathiIndex, IndexState
from app.hathitrust_update import (UpdateError, UpdateResult, iter_gzip_lines, plan_update, update_index)
from tests.test_hathifile import row

LIST_URL = "https://files.hathitrust.test/hathi_file_list.json"


def entry(name: str) -> dict:
    return {"filename": name, "full": "_full_" in name, "size": 1, "created": "x", "modified": "x",
            "url": f"https://files.hathitrust.test/{name}"}


def listing(*names: str) -> list[dict]:
    return [entry(n) for n in names]


FULLS = ["hathi_full_20260901.txt.gz", "hathi_full_20261001.txt.gz"]


def upd(*days: int) -> list[str]:
    return [f"hathi_upd_202610{d:02d}.txt.gz" for d in days]


class TestPlan:
    def test_no_index_yet_means_the_newest_full_file_and_the_updates_since_it(self):
        plan = plan_update(listing(*FULLS, *upd(1, 2, 3)), None)
        assert plan.full["filename"] == "hathi_full_20261001.txt.gz"
        assert [u["filename"] for u in plan.updates] == upd(1, 2, 3)

    def test_updates_older_than_the_full_file_are_not_applied_after_a_rebuild(self):
        names = ["hathi_upd_20250930.txt.gz", *FULLS, *upd(1, 2)]
        plan = plan_update(listing(*names), None)
        assert [u["filename"] for u in plan.updates] == upd(1, 2)

    def test_an_up_to_date_index_applies_only_newer_updates_in_date_order(self):
        state = IndexState("hathi_full_20261001.txt.gz", "20261002")
        plan = plan_update(listing(*FULLS, *upd(5, 3, 2, 1, 4)), state)
        assert plan.full is None
        assert [u["filename"] for u in plan.updates] == upd(3, 4, 5)

    def test_nothing_to_do_when_the_index_is_current(self):
        state = IndexState("hathi_full_20261001.txt.gz", "20261003")
        plan = plan_update(listing(*FULLS, *upd(1, 2, 3)), state)
        assert plan.full is None and plan.updates == [] and plan.is_empty

    def test_a_new_monthly_file_means_a_rebuild(self):
        """The updates have no deletions, so the monthly file is how removed volumes leave."""
        state = IndexState("hathi_full_20260901.txt.gz", "20261030")
        plan = plan_update(listing(*FULLS, *upd(1, 2)), state)
        assert plan.full["filename"] == "hathi_full_20261001.txt.gz"
        assert [u["filename"] for u in plan.updates] == upd(1, 2)

    def test_a_gap_in_the_updates_means_a_rebuild(self):
        """The list only keeps about 70 days of updates; if the oldest is later than the day after ours,
        we missed some."""
        state = IndexState("hathi_full_20261001.txt.gz", "20261001")
        plan = plan_update(listing(*FULLS, *upd(5, 6, 7)), state)
        assert plan.full["filename"] == "hathi_full_20261001.txt.gz"

    def test_no_gap_when_the_next_day_is_the_oldest_update(self):
        state = IndexState("hathi_full_20261001.txt.gz", "20261001")
        assert plan_update(listing(*FULLS, *upd(2, 3)), state).full is None

    def test_no_updates_listed_and_no_news_is_not_a_gap(self):
        state = IndexState("hathi_full_20261001.txt.gz", "20261001")
        assert plan_update(listing(*FULLS), state).is_empty

    def test_no_full_file_listed_and_no_index_is_an_error(self):
        with pytest.raises(UpdateError):
            plan_update(listing(*upd(1, 2)), None)

    def test_names_that_do_not_look_like_hathifiles_are_ignored(self):
        names = [*FULLS, "hathi_upd_20261002.txt.gz", "readme.txt", "hathi_upd_notadate.txt.gz", "hathi_upd_20261003.tsv"]
        plan = plan_update(listing(*names), IndexState("hathi_full_20261001.txt.gz", "20261001"))
        assert [u["filename"] for u in plan.updates] == ["hathi_upd_20261002.txt.gz"]

    def test_an_index_built_from_an_unknown_full_file_is_rebuilt(self):
        plan = plan_update(listing(*FULLS, *upd(1)), IndexState("something_else.gz", "20261001"))
        assert plan.full is not None


def body(data: bytes) -> httpx.Response:
    """A download that is streamed, as over a real connection."""
    return httpx.Response(200, content=iter([data]))


def gz(*lines: str) -> bytes:
    return gzip.compress(("\n".join(lines) + "\n").encode("utf-8"))


def served(files: dict[str, bytes], names: list[str] | None = None, calls: list | None = None):
    """A transport answering the file list and the files."""
    names = names if names is not None else list(files)

    def respond(request: httpx.Request) -> httpx.Response:
        if calls is not None:
            calls.append(str(request.url))
        if str(request.url) == LIST_URL:
            return httpx.Response(200, json=listing(*names))
        name = request.url.path.rsplit("/", 1)[-1]
        if name in files:
            return body(files[name])
        return httpx.Response(404)
    return httpx.Client(transport=httpx.MockTransport(respond))


class TestIterGzipLines:
    def lines(self, data: bytes, **kwargs):
        client = httpx.Client(transport=httpx.MockTransport(lambda r: body(data)))
        return list(iter_gzip_lines(client, "https://files.hathitrust.test/x.gz", **kwargs))

    def test_decompresses_and_splits_lines(self):
        assert self.lines(gz("a\tb", "c\td")) == ["a\tb", "c\td"]

    def test_non_ascii_text_survives(self):
        assert self.lines(gz("Oeuvres complètes", "日本語")) == ["Oeuvres complètes", "日本語"]

    def test_a_last_line_without_a_newline_is_kept(self):
        assert self.lines(gzip.compress(b"a\nb")) == ["a", "b"]

    def test_lines_are_split_correctly_across_tiny_chunks(self):
        data = gz(*[f"line {n} with ü" for n in range(200)])
        client = httpx.Client(transport=httpx.MockTransport(
            lambda r: httpx.Response(200, content=iter([data[i:i + 7] for i in range(0, len(data), 7)]))))
        lines = list(iter_gzip_lines(client, "https://files.hathitrust.test/x.gz"))
        assert lines == [f"line {n} with ü" for n in range(200)]

    def test_an_http_error_is_an_update_error(self):
        client = httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(503)))
        with pytest.raises(UpdateError):
            list(iter_gzip_lines(client, "https://files.hathitrust.test/x.gz"))

    def test_a_connection_error_is_an_update_error(self):
        def refuse(request):
            raise httpx.ConnectError("no route")
        client = httpx.Client(transport=httpx.MockTransport(refuse))
        with pytest.raises(UpdateError):
            list(iter_gzip_lines(client, "https://files.hathitrust.test/x.gz"))

    def test_a_file_that_is_not_gzip_is_an_update_error(self):
        with pytest.raises(UpdateError):
            self.lines(b"<html>Just a moment...</html>")

    def test_a_cut_off_download_is_an_update_error(self):
        data = gz(*[f"line {n}" for n in range(500)])
        with pytest.raises(UpdateError):
            self.lines(data[: len(data) // 2])


@pytest.fixture
def index(tmp_path):
    return HathiIndex(tmp_path / "hathi.sqlite")


def book(htid, title, **fields):
    return row(htid=htid, ht_bib_key=htid.replace(".", ""), title=title, **fields)


class TestUpdateIndex:
    def test_a_first_run_builds_from_the_full_file_then_applies_updates(self, index):
        files = {
            "hathi_full_20261001.txt.gz": gz(book("a.1", "Alpha book"), book("a.2", "Beta book"),
                                              book("a.3", "Closed book", access="deny")),
            "hathi_upd_20261001.txt.gz": gz(book("a.1", "Alpha book")),
            "hathi_upd_20261002.txt.gz": gz(book("a.4", "Delta book"), book("a.2", "Beta book", access="deny")),
        }
        result = update_index(served(files), index, LIST_URL)
        assert isinstance(result, UpdateResult)
        assert result.rebuilt is True and result.updates_applied == 2
        assert sorted(v.htid for v in index.search(text="book")) == ["a.1", "a.4"]
        assert index.state() == IndexState("hathi_full_20261001.txt.gz", "20261002")

    def test_a_later_run_downloads_only_new_updates(self, index):
        files = {
            "hathi_full_20261001.txt.gz": gz(book("a.1", "Alpha book")),
            "hathi_upd_20261002.txt.gz": gz(book("a.2", "Beta book")),
        }
        update_index(served(files), index, LIST_URL)
        files["hathi_upd_20261003.txt.gz"] = gz(book("a.3", "Gamma book"))
        calls: list[str] = []
        result = update_index(served(files, calls=calls), index, LIST_URL)
        assert result.rebuilt is False and result.updates_applied == 1
        assert calls == [LIST_URL, "https://files.hathitrust.test/hathi_upd_20261003.txt.gz"]
        assert sorted(v.htid for v in index.search(text="book")) == ["a.1", "a.2", "a.3"]

    def test_nothing_new_downloads_nothing_but_the_list(self, index):
        files = {"hathi_full_20261001.txt.gz": gz(book("a.1", "Alpha book"))}
        update_index(served(files), index, LIST_URL)
        calls: list[str] = []
        result = update_index(served(files, calls=calls), index, LIST_URL)
        assert calls == [LIST_URL]
        assert result.rebuilt is False and result.updates_applied == 0

    def test_a_new_month_rebuilds_and_drops_volumes_that_left(self, index):
        old = {"hathi_full_20261001.txt.gz": gz(book("a.1", "Alpha book"), book("a.2", "Beta book"))}
        update_index(served(old), index, LIST_URL)
        new = {"hathi_full_20261101.txt.gz": gz(book("a.1", "Alpha book"))}
        result = update_index(served(new), index, LIST_URL)
        assert result.rebuilt is True
        assert [v.htid for v in index.search(text="book")] == ["a.1"]
        assert index.state() == IndexState("hathi_full_20261101.txt.gz", "20261101")

    def test_a_failed_update_file_leaves_the_index_at_the_last_good_day(self, index):
        files = {
            "hathi_full_20261001.txt.gz": gz(book("a.1", "Alpha book")),
            "hathi_upd_20261002.txt.gz": gz(book("a.2", "Beta book")),
        }
        update_index(served(files), index, LIST_URL)
        files["hathi_upd_20261003.txt.gz"] = gz(book("a.3", "Gamma book"))[:40]        # cut off
        files["hathi_upd_20261004.txt.gz"] = gz(book("a.4", "Delta book"))
        with pytest.raises(UpdateError):
            update_index(served(files), index, LIST_URL)
        assert index.state().updated_through == "20261002"
        assert sorted(v.htid for v in index.search(text="book")) == ["a.1", "a.2"]

    def test_a_failed_rebuild_keeps_the_old_index_working(self, index):
        update_index(served({"hathi_full_20261001.txt.gz": gz(book("a.1", "Alpha book"))}), index, LIST_URL)
        broken = {"hathi_full_20261101.txt.gz": gz(book("b.1", "Other book"))[:30]}
        with pytest.raises(UpdateError):
            update_index(served(broken), index, LIST_URL)
        assert [v.htid for v in index.search(text="book")] == ["a.1"]
        assert index.state().full_file == "hathi_full_20261001.txt.gz"

    def test_an_unreadable_file_list_is_an_update_error(self, index):
        client = httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, text="<html>challenge")))
        with pytest.raises(UpdateError):
            update_index(client, index, LIST_URL)

    def test_a_file_list_that_is_not_a_list_is_an_update_error(self, index):
        client = httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"files": []})))
        with pytest.raises(UpdateError):
            update_index(client, index, LIST_URL)

    def test_a_file_list_error_status_is_an_update_error(self, index):
        client = httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(403)))
        with pytest.raises(UpdateError):
            update_index(client, index, LIST_URL)

    def test_the_result_counts_what_was_loaded(self, index):
        files = {"hathi_full_20261001.txt.gz": gz(book("a.1", "Alpha book"), book("a.2", "Closed", access="deny"))}
        result = update_index(served(files), index, LIST_URL)
        assert result.volumes == 1


def test_the_file_list_the_job_reads_is_json():
    assert json.loads(json.dumps(listing(*FULLS)))[0]["full"] is True
