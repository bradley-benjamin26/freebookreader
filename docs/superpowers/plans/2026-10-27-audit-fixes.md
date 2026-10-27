# Audit Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the eight findings of the 2026-10-27 ponytail audit: sources dropping out under load, Gutenberg lost for 24 h by a Gutendex restart, unbounded EPUB downloads, unpinned dependencies, a blind `/health`, and dead code.

**Architecture:** Everything is backend-only and small. A per-source result cache and a higher in-flight cap live in `SearchService`; the outage rule skips our own Gutendex; `PublicationStore` gets a download semaphore and `.part` cleanup; `/health` reports the HathiTrust index; cleanup deletes dead code.

**Tech Stack:** Python 3.14, FastAPI, httpx, pytest (`cd backend && source venv/bin/activate && python -m pytest`).

**Spec:** `spec.md` (outage rule, non-functional requirements), the audit report in the 2026-10-27 session (findings numbered 1–8 below as F1–F8), `AGENTS.md`, `backend/tests/README.md`.

## Global Constraints

- Development is test-first; if an existing test must change, change it together with `backend/tests/README.md`.
- Spec outage rule: "only the source's own errors (connection failure, 5xx, unreadable answer) take it out for 24 hours" applies to outside sources. Timeouts, 4xx and adapter crashes never start an outage.
- Search must answer inside 15 s: `search_timeout_seconds` stays 12, `search_admission_seconds` stays 3.
- Settings come from `FBR_*` environment variables read in `Settings.from_env` (`backend/app/config.py`).
- No new dependencies.
- Update `spec.md` and the Context section of `AGENTS.md` for anything that changes behaviour.
- Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

- Two searches that differ only in `sources` (all vs one) must share cached source results and never return another source's books.
- Mutating the list a cached search returned must not change what the next search gets.
- The cache must stay bounded (a crawler sending 10,000 different queries must not grow memory).
- A download that raises must release its slot (with a limit of 1, the next download still runs).
- `/health` with no index file must say so (`hathitrust_index` false) and still answer 200.

## File Structure

- Modify `backend/app/search.py`: cache, in-flight default, own-source rule.
- Modify `backend/app/sources/gutendex.py`: `own = True`.
- Modify `backend/app/config.py`: `search_cache_seconds`, pass to `SearchService`.
- Modify `backend/app/publications.py`: download semaphore, `.part` cleanup.
- Modify `backend/app/main.py`: `/health` body.
- Modify `backend/app/normalize.py`, `sources/openlibrary.py`, `hathifile.py`: one `unique` helper, dead code out.
- Create `backend/requirements.lock`.
- Tests: `test_search_service.py`, `test_source_gutendex.py`, `test_config.py`, `test_publications.py`, `test_api.py`, `test_source_openlibrary.py`, `test_normalize.py`.

---

### Task 1: Gutendex failures do not start an outage (F2)

**Files:**
- Modify: `backend/app/sources/gutendex.py` (class `GutendexSource`), `backend/app/search.py:100-103`
- Test: `backend/tests/test_search_service.py`, `backend/tests/test_source_gutendex.py`

**Interfaces:**
- Produces: sources may have class attribute `own: bool` (absent means False). A `SourceError` from an own source leaves it out of that search with reason `"error"`, is logged, and never calls `OutageTracker.record_failure`.

- [ ] **Step 1: Write failing tests** in `TestOutage`-style class of `test_search_service.py`:
  - `test_a_failure_of_our_own_source_is_not_an_outage`: `FakeSource("gutenberg", error=SourceError("refused"))` with `own = True` set on the instance; search twice; assert both searches called it (`len(calls) == 2`), `response.skipped == [SkippedSource(source="gutenberg", reason="error")]`, `outage.is_available("gutenberg")`.
  - `test_a_failure_of_an_outside_source_is_still_an_outage` (guard): same with `own` unset, second search makes no call, reason `"outage"`.
  - In `test_source_gutendex.py`: `test_gutendex_is_our_own_service`: `assert GutendexSource.own is True`.
- [ ] **Step 2: Run** `python -m pytest tests/test_search_service.py tests/test_source_gutendex.py -q`. Expected: the new own-source tests FAIL.
- [ ] **Step 3: Implement.** Add `own = True` (with a one-line comment: our service, restarts must not hide it for 24 h) to `GutendexSource`. In `_fan_out`'s `SourceError` branch: if `getattr(source, "own", False)`, log and set `missing[name] = "error"`; else existing behaviour. Update the `SkippedSource` reason comment.
- [ ] **Step 4: Run** the same command. Expected: PASS. Then full suite: all pass.
- [ ] **Step 5: Docs.** Add one line to `spec.md`'s outage rule and `AGENTS.md` Context: our own Gutendex is exempt (restarts, `updatecatalog`). Update `backend/tests/README.md`.
- [ ] **Step 6: Commit** `fix: a Gutendex failure no longer starts a 24-hour outage (audit F2)`.

---

### Task 2: Per-source result cache and higher in-flight cap (F1)

**Files:**
- Modify: `backend/app/search.py` (`SearchService.__init__`, `_run`, `MAX_IN_FLIGHT`), `backend/app/config.py` (`Settings`, `from_env`, `build_search_service`)
- Test: `backend/tests/test_search_service.py`, `backend/tests/test_config.py`

**Interfaces:**
- Produces: `SearchService(sources, outage, timeout_seconds=12, max_in_flight=MAX_IN_FLIGHT, cache_seconds: float = 0, cache_entries: int = 500, now: Callable[[], float] = time.monotonic)`. `cache_seconds=0` means no cache (existing tests unchanged). `Settings.search_cache_seconds: float = 300`, env `FBR_SEARCH_CACHE_SECONDS`. `MAX_IN_FLIGHT = 8`.
- Cache key: `(source.name, query.model_dump_json(exclude={"sources"}))`. Only successful book lists are stored; errors, timeouts and rejections never are.

- [ ] **Step 1: Write failing tests** (class `TestCache`; use a fake clock list for `now`):
  - `test_the_same_search_asks_each_source_once`: two identical `search(SearchQuery(q="dickens"))` → `source.calls` has length 1, both responses equal.
  - `test_searches_for_other_sources_share_cached_results`: search all, then `sources=["gutenberg"]` → still one call, response has only gutenberg works.
  - `test_a_different_page_is_a_different_search`.
  - `test_results_expire`: advance `now` past `cache_seconds` → second call made.
  - `test_failures_are_not_cached`: a source raising `SourceError` once then succeeding is asked again (use a flaky fake or `outage` cooldown 0; assert the success is returned on the next search).
  - `test_the_cache_is_bounded`: `cache_entries=3`, 10 distinct queries → internal cache size `<= 3` (assert through behaviour: re-running the first query calls the source again).
  - `test_changing_a_returned_book_does_not_change_the_cache`: mutate `response.works[0].books[0].title`, search again, original title returned.
  - `test_no_cache_by_default`: `SearchService(...)` without `cache_seconds` asks twice.
  - In `test_config.py`: `test_search_cache_setting` (default 300, `FBR_SEARCH_CACHE_SECONDS=0` → 0, passed to the service built by `build_search_service`).
- [ ] **Step 2: Run** the two files. Expected: new tests FAIL.
- [ ] **Step 3: Implement.** Cache is a `dict` guarded by a `threading.Lock`, insertion-ordered; on insert past `cache_entries` drop the oldest. `_run` returns books to the caller as `[b.model_copy(deep=True) for b in books]` both when storing and when reading (the cache holds its own copies). Check cache before taking a slot in `_fan_out` so a hit uses no thread. Raise `MAX_IN_FLIGHT` to 8 and fix its comment.
- [ ] **Step 4: Run** full suite. Expected: all PASS (update any test that asserted the default of 4 together with README).
- [ ] **Step 5: Docs.** `backend/tests/README.md` (new parameters), `AGENTS.md` Context (cache 5 min, why: Open Library 3 req/s, DOAB 21 requests per search), `spec.md` if it lists freshness.
- [ ] **Step 6: Commit** `feat: cache source results for 5 minutes and allow 8 searches per source (audit F1)`.

---

### Task 3: Bound EPUB downloads (F3)

**Files:**
- Modify: `backend/app/publications.py` (`PublicationStore.__init__`, `_download`, `_evict`), `backend/app/config.py` (`build_publication_store` unchanged unless a setting is added; no setting needed)
- Test: `backend/tests/test_publications.py` (use the `Gutenberg` fake's `delay`/`respond`)

**Interfaces:**
- Produces: `PublicationStore(..., max_parallel_downloads: int = 4)`; constant `STALE_PART_SECONDS = 3600`.

- [ ] **Step 1: Write failing tests** in `TestDownload`:
  - `test_at_most_four_books_download_at_once`: 12 threads, 12 different ids, fake that records its peak concurrency while sleeping 0.05 s; assert peak `<= 4` and all 12 stored.
  - `test_a_failed_download_gives_its_slot_back`: `max_parallel_downloads=1`, first id answers 500 (raises `PublicationUnavailable`), second id downloads fine.
  - `test_old_part_files_are_removed`: create `cache/epub/stale.part` with mtime two hours old and `fresh.part` with mtime now; after one successful download, `stale.part` gone, `fresh.part` kept.
- [ ] **Step 2: Run** `python -m pytest tests/test_publications.py -q`. Expected: new tests FAIL.
- [ ] **Step 3: Implement.** A `threading.BoundedSemaphore` acquired in `_download` around the fetch (released in `finally`). In `_evict`, unlink `*.part` files whose mtime is older than `STALE_PART_SECONDS`.
- [ ] **Step 4: Run** full suite. Expected: PASS.
- [ ] **Step 5: Docs + commit** `fix: limit parallel EPUB downloads and clean stale .part files (audit F3)`. Note in `AGENTS.md` Web reader line.

---

### Task 4: `/health` reports the HathiTrust index (F5)

**Files:**
- Modify: `backend/app/main.py:62-64`
- Test: `backend/tests/test_api.py:50-53`

**Interfaces:**
- Produces: `GET /health` → `{"status": "ok", "hathitrust_index": bool}`; always HTTP 200; the bool is `settings.hathitrust_index.is_file()`.

- [ ] **Step 1: Write failing tests**: replace `test_health` assertion with two tests that build the app with `Settings(hathitrust_index=tmp_path/"x.sqlite")`: `test_health_says_when_the_hathitrust_index_is_missing` (False, status 200) and `test_health_says_when_the_hathitrust_index_exists` (touch file → True). Keep `status == "ok"` in both.
- [ ] **Step 2: Run** `python -m pytest tests/test_api.py -q -k health`. Expected: FAIL.
- [ ] **Step 3: Implement** in `health()`; return type `dict`.
- [ ] **Step 4: Run** full suite. PASS.
- [ ] **Step 5: Docs + commit** `feat: /health reports whether the HathiTrust index exists (audit F5)`. Mention in `backend/tests/README.md` and the deploy examples' header comment (alert on `hathitrust_index: false`).

---

### Task 5: Pin the backend's dependencies (F4)

**Files:**
- Create: `backend/requirements.lock`
- Modify: `AGENTS.md` (Context: install from the lock file)

- [ ] **Step 1:** In the tested venv: `cd backend && source venv/bin/activate && pip freeze --exclude-editable | grep -v '^pytest\|^pip' > requirements.lock` (runtime packages only; check that fastapi, httpx, pydantic, uvicorn, rapidfuzz and their dependencies are listed with `==`).
- [ ] **Step 2: Verify from scratch:** `python -m venv /tmp/fbr-lock && /tmp/fbr-lock/bin/pip install -r requirements.lock -r requirements-dev.txt && /tmp/fbr-lock/bin/python -m pytest -q`. Expected: all pass. (Use the scratchpad directory, not `/tmp`, if the harness provides one.)
- [ ] **Step 3: Commit** `build: lock backend dependencies (audit F4)`.

---

### Task 6: Remove dead and duplicated code (F6, F7)

**Files:**
- Modify: `backend/app/sources/openlibrary.py:31-34,86-99,178-183`, `backend/app/hathifile.py:77-86`, `backend/app/normalize.py`, `backend/tests/README.md`
- Test: `backend/tests/test_normalize.py`, `backend/tests/test_source_hathitrust.py`, `backend/tests/test_hathitrust_index.py`

**Interfaces:**
- Produces: `app.normalize.unique(values: Iterable[str | None]) -> list[str]` (first-seen order, drops falsy values). Test helper `iter_changes` moves to `backend/tests/factories.py` with the same signature `(lines) -> Iterator[tuple[str, Volume | None]]`.

- [ ] **Step 1:** Re-grep that nothing else uses `availability(`, `Availability`, `iter_changes`, `_unique` (`grep -rnE ... backend app`); if a caller appears, stop and ask.
- [ ] **Step 2: Write failing test** `test_unique_keeps_first_seen_order_and_drops_empty_values` in `test_normalize.py`: `unique(["b", None, "a", "b", ""]) == ["b", "a"]`.
- [ ] **Step 3: Implement** `unique` in `normalize.py` (`list(dict.fromkeys(v for v in values if v))`); import it in `openlibrary.py` and `hathifile.py`, delete both `_unique`. Delete `Availability`, `OpenLibrarySource.availability` and the unused `get_json` import if it becomes unused. Move `iter_changes` into `tests/factories.py` and update the two importing tests.
- [ ] **Step 4: Run** full suite. Expected: all PASS.
- [ ] **Step 5: Docs.** Remove the `.availability(...)` and `iter_changes` mentions from `backend/tests/README.md`; check `api_openlibrary.documentation.md` for a mention of the brief-ISBN lookup and mark it not used by the app.
- [ ] **Step 6: Commit** `refactor: delete unused Open Library availability lookup, share one unique helper (audit F6, F7)`.

---

### Task 7: Delete `spikes/` (F8) — only after the user confirms

**Files:**
- Delete: `spikes/`
- Modify: `AGENTS.md` (Context mentions `spikes/reader/` and `spikes/epub_server/serve.py`), `decision_reader.md` (point at git history)

- [ ] **Step 1: Ask the user** whether they still run the spike app by hand. If yes, skip this task.
- [ ] **Step 2:** `git rm -r spikes`; replace the AGENTS.md sentences with "the spike was removed on 2026-10-27; see commit <hash of the last commit that has it>"; same in `decision_reader.md`.
- [ ] **Step 3: Run** `cd app && flutter test` and the backend suite. Expected: all pass (nothing imports `spikes/`; check with `grep -rn spikes app backend`).
- [ ] **Step 4: Commit** `chore: remove the reader spikes (audit F8)`.

---

## Self-Review

- **Coverage:** F1 → Task 2; F2 → Task 1; F3 → Task 3; F4 → Task 5; F5 → Task 4; F6, F7 → Task 6; F8 → Task 7. The three small findings the audit left out are not planned.
- **Types:** `own`, `cache_seconds`, `cache_entries`, `now`, `max_parallel_downloads`, `unique`, `iter_changes` are named the same in every task that uses them.
- **Order:** Tasks 1–6 are independent of each other; do 1 and 2 first (they change `search.py` and its tests together, so not in parallel). Task 7 waits for the user.
- **Clear the context window** after each task (project rule).
