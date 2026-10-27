# Close Open Review Findings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the four open findings from `REVIEW-2026-10-11-main.md` that reach the app or the running server (#1, #3, #4, #25) and record why the other six (#8, #10–#14) stay open.

**Architecture:** Small local changes, each with a test written first. #1 and #3 use the simpler fixes already noted in the findings' Status lines, not the review's larger proposals.

**Tech Stack:** FastAPI + anyio + pytest (backend), Flutter + flutter_test (app).

**Spec:** `spec.md`; findings in `REVIEW-2026-10-11-main.md`.

## Global Constraints

- Test first. If a test changes, change `backend/tests/README.md` or `app/test/README.md` with it.
- Run: `cd backend && source venv/bin/activate && python -m pytest`; `cd app && flutter test`.
- Each finding's Status line is updated with the date and the test name when fixed.
- Keep the 300-character input cap, the outage rule and `skipped` reasons as they are. `busy` is an existing reason; add no new one.

## Review Focus

- Two requests for one uncached book at once, with a cache that holds one book: neither may become a 500.
- Searches arriving while all slots are taken: the answer comes within the search deadline, not after 16 s.
- A book whose language is null or not a valid code (`"xx-"`): the reader must not crash.
- Closing the app twice (two lifespans in tests): no error.

---

### Task 1: Reload a book evicted under a request (#1)

**Files:**
- Modify: `backend/app/publications.py` (`PublicationStore._book`, `resource`, `manifest`)
- Test: `backend/tests/test_publications.py`

**Interfaces:**
- Produces: `PublicationStore.manifest(book_id) -> dict` and `.resource(book_id, href) -> tuple[bytes, str]` unchanged; they no longer raise `FileNotFoundError`.

- [ ] **Step 1: Failing test** `test_a_book_evicted_between_the_check_and_the_read_is_loaded_again`: store with the one-book cache from the existing eviction tests; get `_book(1)`, download book 2 so 1 is evicted, then call `store.resource(1, <a listed href>)` after patching `_touch` to unlink the file once before delegating. Assert it returns bytes and does not raise.
- [ ] **Step 2:** Run `python -m pytest backend/tests/test_publications.py -k evicted -v`. Expected: FAIL (`FileNotFoundError` or `PublicationUnavailable`).
- [ ] **Step 3:** In `_book`, catch `FileNotFoundError` from `_touch` and from `_read_manifest` and go round once more (drop `self._books[book_id]`, fall through to the download branch). In `resource`, a `FileNotFoundError` from `zipfile.ZipFile(book.path)` drops the entry and retries `_book` once; a second failure is `PublicationUnavailable`.
- [ ] **Step 4:** Run the whole file. Expected: PASS.
- [ ] **Step 5:** Mark #1 fixed in the review; commit `fix: reload a book that was evicted while in use`.

### Task 2: Bounded wait for a search slot (#3)

**Files:**
- Modify: `backend/app/main.py:78-80` (the `/search` handler), `backend/app/config.py` (new `search_admission_seconds: float = 3`, env `FBR_SEARCH_ADMISSION_SECONDS`)
- Test: `backend/tests/test_api.py`, `backend/tests/test_config.py`

**Interfaces:**
- Consumes: `SearchResponse`, `SkippedSource` from `app/search.py`.
- Produces: when no slot frees within `search_admission_seconds`, `/search` answers 200 with `works=[]`, and every selected source (all sources when `sources` is unset) in `skipped` with reason `busy` and in `unavailable_sources`.

- [ ] **Step 1: Failing tests** in `test_api.py`: `test_a_search_that_cannot_get_a_slot_answers_busy_for_every_source` (settings `max_concurrent_searches=1`, `search_admission_seconds=0.1`, a fake service whose `search` blocks on an event; start one request in a thread, send a second; assert 200, `skipped` lists each selected source as `busy`, and the call took under 1 s; then release the event). `test_busy_answer_respects_the_sources_filter` (only the named source is listed). In `test_config.py`: the env var is read.
- [ ] **Step 2:** Run them. Expected: FAIL (second request waits).
- [ ] **Step 3:** In the handler, `with anyio.move_on_after(settings.search_admission_seconds)` around `await limiter.acquire()`; if it timed out, build the busy `SearchResponse` from the selected source names (`query.sources` or all `search_service.sources`); otherwise run `to_thread.run_sync(..., limiter=<a second limiter of the same size>)` and release the admission limiter in `finally`. Both limiters are created lazily with the existing `search_limiter` list pattern.
- [ ] **Step 4:** Run `python -m pytest backend/tests -q`. Expected: all pass.
- [ ] **Step 5:** Update `backend/tests/README.md`, `api_*` docs if they list `busy`, the review's #3 Status, and `spec.md` if it describes admission; commit `fix: answer busy instead of waiting past the search deadline`.

### Task 3: Close what the factory opened (#4)

**Files:**
- Modify: `backend/app/search.py` (`SearchService.close`), `backend/app/main.py` (`lifespan`)
- Test: `backend/tests/test_api.py`, `backend/tests/test_search_service.py`

**Interfaces:**
- Produces: `SearchService.close() -> None` (shuts the executor down, `wait=True, cancel_futures=True`); `create_app` closes the `httpx.Client` and the service only when it built them.

- [ ] **Step 1: Failing tests:** `test_the_factory_closes_its_client_on_shutdown` (`with TestClient(create_app(...)):` then assert `client.is_closed`; get the client through whatever `create_app` already exposes or a patched `build_http_client`). `test_a_client_passed_in_is_left_open`. `test_close_stops_the_executor` (a search after `close()` raises `RuntimeError`).
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement as the review's snippet (`@asynccontextmanager lifespan`, `owned_search = search_service is None`), passing `lifespan=lifespan` to `FastAPI(...)`.
- [ ] **Step 4:** Run all backend tests. Expected: pass; closing twice does not raise.
- [ ] **Step 5:** Mark #4 fixed; commit `fix: close the HTTP client and search executor on shutdown`.

### Task 4: Tag book content with its language (#25)

**Files:**
- Modify: `app/lib/reader/reader_page.dart:231` (wrap `_engine!.buildView(context)`)
- Test: `app/test/reader_test.dart`

**Interfaces:**
- Consumes: `widget.book.language` (`String?`, ISO 639-1).

- [ ] **Step 1: Failing test** `semantics tag a Spanish book's text as Spanish` using the existing reader test setup with a book whose `language` is `'es'`: find the `Semantics` above the `reader-surface` content and assert `properties.localeForSubtree == const Locale('es')`; and `a book with no language has no locale`: it is null.
- [ ] **Step 2:** Run `flutter test test/reader_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Wrap the engine view in `Semantics(localeForSubtree: ..., child: ...)` in both places `buildView` is used (text and Readium branches share it). Use `Locale(language)` only when non-empty; do not set the controls' locale.
- [ ] **Step 4:** Run `flutter test`. Expected: 445+ pass.
- [ ] **Step 5:** Mark #25 fixed, noting that real VoiceOver/TalkBack switching is not checked; commit `fix: give book content its language for screen readers`.

### Task 5: Record the six findings left open

**Files:**
- Modify: `REVIEW-2026-10-11-main.md` (Status of #8, #10–#14, and the summary at line 50), `AGENTS.md` context line

- [ ] **Step 1:** Rewrite each Status as "left open on purpose (2026-10-27): <reason>": #8 never seen in the real catalog; #10–#12 in vendored Gutendex and unreachable from our backend (`search=` only); #13–#14 explorer page unused by the app.
- [ ] **Step 2:** Update the counts in the summary and AGENTS.md ("open: …").
- [ ] **Step 3:** Commit `docs: record why six review findings stay open`.
