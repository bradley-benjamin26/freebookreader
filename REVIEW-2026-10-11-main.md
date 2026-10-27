# Main application review - 2026-10-11

Baseline: `main`, commit `3e9d372`. This is a source review, not a clean-diff review.
The existing `gptReport1011263pm.md` was read as historical context, not treated as evidence.
No application fixes are included in this report. Fix snippets are proposed changes.

## Scope and evidence

The review traces search input through HTTP validation, parallel source searches, normalization,
merging, JSON serialization, Flutter results/details, and reading/audio/bookmark state. It also
examines the independent catalog/index refresh pipelines and publication cache.

Backend core validation: 434 tests passed across `test_merge`, `test_search_service`, `test_api`,
`test_publications`, `test_normalize`, `test_models`, `test_reader`, and `test_outage`.
There was one existing Starlette/httpx test-client deprecation warning.
The IDE test runner had no connected client; validation used the existing virtual environment.

Gutendex validation: all 41 tests passed with SQLite test settings. A read-only parse of all
79,572 local RDF records completed without parsing failures or empty summaries.
Additional failures below were reproduced with isolated SQLite, mocked subprocess/filesystem
effects, local HTTP transports, threads, and network-free JavaScript DOM simulations.

Production PostgreSQL, live refresh jobs, real phone TTS, screen readers, and deployed browser
behavior are not certified by these tests. Scratch probes do not modify production databases
or the real HathiTrust index.

### Recovered domain reviews

The first Flutter and source/index background agents disappeared without returning final
reports. Their status did not establish success or failure. Both reviews were rerun
synchronously with incremental durable checkpoints and completed successfully.

- Flutter: all 29 production Dart files, web integration and relevant Android/iOS configuration;
  423 existing tests passed. Analyzer: zero errors, one existing warning and 53 informational
  diagnostics (nonzero analyzer exit, not a clean analysis result).
- Sources/index: all five adapters, configuration/metadata, Hathifile parser, SQLite search
  index, refresh planning and deploy examples; 539 selected existing tests passed.
- The 434 core and 539 source selections overlap; they must not be summed as distinct tests.
- Supplemental Flutter probes: nine valid recovered reproductions and four supplemental tests
  passed. One recovered Spanish fixture probe was invalid and excluded; the corrected probe
  reproduced missing language semantics. Source probes used tiny synthetic SQLite databases.
- All recovery scratch tests/data were removed. Tracked source/test/platform files are unchanged.

Detailed checkpoint evidence, correction notes and coverage remain in:
[Flutter recovery](../../../.copilot/session-state/a3fced19-d49b-4f17-8dcf-1d1aa2c3ef85/files/flutter-review-recovery.md)
and
[source/index recovery](../../../.copilot/session-state/a3fced19-d49b-4f17-8dcf-1d1aa2c3ef85/files/sources-review-recovery.md).
These are session-local supporting reports; the findings below are also consolidated here.

**Status (2026-10-11):** 26 fixed (#1–#7, #9, #15–#32), 6 left open on purpose (#8, #10–#14). Each
finding has a Status line. Test runs after the fixes: backend 969 passed, Flutter 445 passed, Gutendex 48 passed (after the 2026-10-27 fixes: backend 976, Flutter 447).

**Consolidated findings:** 32 actionable findings: 4 High, 22 Medium, 6 Low. No Critical
finding was verified. The Medium security finding has an explicit upstream-content-control
prerequisite and has not been reproduced end-to-end in a browser.

## Architecture conclusions

- Passing unit tests do not cover active cache eviction, admission-queue latency, interrupted
  catalog updates, overlapping updater ownership, or all reader lifecycle races.
- The backend's per-source search bound is distinct from its request-admission bound. Time
  waiting for admission is currently outside the source deadline.
- Catalog refresh has destructive filesystem/database operations without a reliable success
  boundary. This is more serious than parser style or missing `const` constructors.
- Third-party publication content crosses two boundaries: the backend's file response and
  Readium's newly generated browser document. Protecting the first does not protect the second.
- Vendored code remains part of the deployed application. Gutendex findings below are existing
  upstream-baseline defects, not regressions attributed to migration 0006.

## Backend orchestration and publications

### 1. Active EPUBs can be deleted while a request uses them

- **Severity:** High
- **Location:** [publications.py:259](backend/app/publications.py#L259),
  [publications.py:280](backend/app/publications.py#L280),
  [publications.py:346](backend/app/publications.py#L346),
  [publications.py:353](backend/app/publications.py#L353)
- **The Defect:** `_book()` protects a book with a striped lock, but `_evict()` ignores that
  lock and active readers. It can unlink an EPUB between `path.exists()` and `_touch()`, or
  between `_book()` and opening its ZIP. The first path raises uncaught `FileNotFoundError`
  and becomes HTTP 500; the second becomes a spurious 502. Reproduced by pausing a cached
  book's touch, downloading another book into a one-book cache, then resuming the first request.
- **The Fix:** Pin the book for the complete public operation and skip pinned books in
  eviction. Retain the existing striped download locks. The same ownership model is needed
  across processes if multiple workers share one cache.

  ```python
  from collections import Counter
  from contextlib import contextmanager

  # In PublicationStore.__init__:
  self._active: Counter[int] = Counter()

  @contextmanager
  def _pin(self, book_id: int):
      with self._lock:
          self._active[book_id] += 1
      try:
          yield
      finally:
          with self._lock:
              self._active[book_id] -= 1
              if not self._active[book_id]:
                  del self._active[book_id]

  def manifest(self, book_id: int) -> dict:
      with self._pin(book_id):
          return self._book(book_id).manifest

  # Wrap the complete existing resource() body in self._pin(book_id).
  # Inside _evict(), already under self._lock:
  if old == keep or self._active.get(int(old.stem), 0):
      continue
  ```

  Test simultaneous manifest/resource access and eviction; a sequential LRU test is insufficient.

- **Status:** fixed 2026-10-27, with the simpler fix rather than pinning: a book that is gone when `_book` touches it, or when `resource` opens its ZIP, is downloaded again (once). Tests: `TestEvictedWhileInUse` in `test_publications`.

### 2. Identifier merging loses compatible-language records

- **Severity:** Medium
- **Location:** [merge.py:110](backend/app/merge.py#L110)
- **The Defect:** `_union_all()` tries every record against only `indexes[0]`. If that first
  record is French and the next two are English, both English unions are refused and those
  two records are never compared with each other. Reproduced with three different sources,
  distinct titles, one shared OCLC number, and languages `fr/en/en`: three works were returned
  instead of a French work and a joined English work.
- **The Fix:** Consider compatible pairs instead of using an incompatible record as the sole
  anchor. The existing `union()` continues enforcing group-level language compatibility.

  ```python
  def _union_all(groups: _Groups, indexes: list[int]) -> None:
      for position, left in enumerate(indexes):
          for right in indexes[position + 1:]:
              groups.union(left, right)
  ```

  Add tests with multiple language partitions and unknown-language bridges. For large buckets,
  a language-partitioned implementation can avoid pairwise work without changing these rules.

- **Status:** fixed 2026-10-11. `_union_all` tries every pair. Test: `test_a_record_in_another_language_does_not_stop_the_others_merging`.

### 3. Request admission can exceed the 15-second search deadline

- **Severity:** Medium
- **Location:** [main.py:78](backend/app/main.py#L78),
  [search.py:82](backend/app/search.py#L82)
- **The Defect:** `to_thread.run_sync(..., limiter=...)` can wait indefinitely for admission;
  the 12-second source timer starts only afterward. Reproduced with the default 20-request
  limit: four eight-second searches per source occupied all 20 slots; the next request took
  **16.00 seconds**, although its own source search took only eight seconds. Initial concurrent
  probes without an occupancy barrier sometimes returned `busy` immediately; the verified
  reproduction waited until all 20 source calls had entered before submitting request 21.
- **The Fix:** Bound admission separately from execution, and explicitly reject a request
  that cannot enter within the remaining budget. Do not merely cancel a shielded worker call.
  Keep a dedicated thread limiter so searches do not consume the default file/health pool.

  ```python
  # Initialize these inside the running event loop, as the current limiter is.
  admission = anyio.CapacityLimiter(settings.max_concurrent_searches)
  workers = anyio.CapacityLimiter(settings.max_concurrent_searches)

  try:
      with anyio.fail_after(3):
          await admission.acquire()
  except TimeoutError as error:
      raise HTTPException(503, "Search capacity is busy; try again") from error
  try:
      return await to_thread.run_sync(search_service.search, query, limiter=workers)
  finally:
      admission.release()
  ```

  Wire these as shared per-app limiters, not fresh per-request objects. The API and Flutter
  error behavior must be updated together if 503 admission rejection is adopted.

- **Status:** fixed 2026-10-27, as suggested instead of a 503: after `FBR_SEARCH_ADMISSION_SECONDS` (3) without a free slot, `/search` answers with every selected source skipped as `busy`. Two limiters of one size (admission, worker threads). Tests: `TestSearchAdmission` in `test_api`.

### 4. Factory-owned HTTP connections and the search executor have no shutdown owner

- **Severity:** Medium
- **Location:** [main.py:32](backend/app/main.py#L32),
  [search.py:44](backend/app/search.py#L44)
- **The Defect:** `create_app()` builds an `httpx.Client` and usually a `SearchService` with
  a thread executor, but installs no lifespan cleanup. Exiting an isolated `TestClient`
  lifespan left the factory-created client's `is_closed` equal to `False`. Recreating app
  instances leaves their connections/resources alive; outstanding search tasks can also
  outlive application shutdown.
- **The Fix:** Give only factory-owned objects lifespan ownership, drain source tasks before
  closing their shared client, and do not close caller-injected dependencies.

  ```python
  from contextlib import asynccontextmanager

  # Add a public lifecycle method to SearchService:
  def close(self) -> None:
      self._executor.shutdown(wait=True, cancel_futures=True)

  owned_search = search_service is None
  # Keep the existing construction, then:
  @asynccontextmanager
  async def lifespan(app):
      try:
          yield
      finally:
          if owned_search:
              await to_thread.run_sync(search_service.close)
          if client is not None:
              client.close()

  app = FastAPI(title="Free Book Reader API", version="0.1.0", lifespan=lifespan)
  ```

  Add lifespan tests asserting client closure and worker termination. Draining still depends
  on genuinely bounded source operations; an executor shutdown is not a hard task timeout.

- **Status:** fixed 2026-10-27. A `lifespan` closes the HTTP client and, if the factory built it, the `SearchService` (`close()` waits for running source searches). Objects passed in are left to the caller. Tests: `TestShutdown` in `test_api`.

### 5. Malformed publication Content-Length becomes an internal server error

- **Severity:** Medium
- **Location:** [publications.py:333](backend/app/publications.py#L333)
- **The Defect:** `int(response.headers.get("content-length") or 0)` trusts the upstream
  header. A mock upstream returning `Content-Length: not-a-number` produced HTTP 500 from
  the real publication endpoint instead of its explicit upstream-unavailable response.
- **The Fix:** Validate the optional header, translate malformed upstream metadata to the
  repository's publication exception, and retain the streaming byte limit.

  ```python
  raw_length = response.headers.get("content-length")
  if raw_length is not None:
      if not raw_length.isascii() or not raw_length.isdecimal():
          raise PublicationUnavailable("invalid upstream Content-Length")
      try:
          length = int(raw_length)
      except ValueError as error:
          raise PublicationUnavailable("invalid upstream Content-Length") from error
      if length > self._max_download:
          raise PublicationUnavailable(f"{url} is larger than {self._max_download} bytes")
  ```

- **Status:** fixed 2026-10-11. A `Content-Length` that is not a number is `PublicationUnavailable` (502). Test in `test_publications`.

## Gutendex catalog and API

### 6. Failed extraction can delete valid catalog records

- **Severity:** High
- **Location:** [updatecatalog.py:325](gutendex/books/management/commands/updatecatalog.py#L325),
  [updatecatalog.py:334](gutendex/books/management/commands/updatecatalog.py#L334),
  [updatecatalog.py:353](gutendex/books/management/commands/updatecatalog.py#L353)
- **The Defect:** `tar` and `rsync` return codes are ignored. A failed extraction can leave
  a partial directory list that is treated as the complete catalog; absent books are then
  deleted. Reproduced with subprocess exit code 2 and only book 100 extracted: existing book
  202 was deleted from isolated SQLite and import still ran. `rsync` exit 23 also reached
  import and logged `Done!`.
- **The Fix:** Check subprocess success and validate the extracted catalog before computing
  removals; defer database deletions until copy and import have both succeeded.

  ```python
  from subprocess import check_call

  check_call(["tar", "fjvx", DOWNLOAD_PATH, "-C", TEMP_PATH],
             stdout=null, stderr=log_file)
  # Validate extraction and collect stale_ids; do not delete them here.
  check_call(rsync_args, stdout=null, stderr=log_file)
  put_catalog_in_db()
  Book.objects.filter(gutenberg_id__in=stale_ids).delete()
  ```

  Remove the pre-copy stale-directory deletion. Successful `rsync --delete-after` already
  handles disk removals. Import errors must propagate rather than reaching the success boundary.

- **Status:** fixed 2026-10-11. `tar` and `rsync` run with `check_call`; an archive with no books is an error; books that left the catalog are deleted only after the import succeeds; `rsync --delete-after` removes their files. Tests: `UpdateCatalogTests` in `gutendex/books/tests.py`.

### 7. A second updater removes the first updater's working directory

- **Severity:** High
- **Location:** [updatecatalog.py:311](gutendex/books/management/commands/updatecatalog.py#L311),
  [updatecatalog.py:372](gutendex/books/management/commands/updatecatalog.py#L372)
- **The Defect:** Detecting an existing temporary directory raises `CommandError`, but the
  outer exception handler unconditionally removes that directory. An overlapping run destroys
  the active run's download/extraction. A mocked existing directory caused `rmtree(TEMP_PATH)`
  even though this invocation never called download.
- **The Fix:** Acquire ownership atomically and clean up only resources owned by this run.

  ```python
  owns_temp = False
  try:
      os.makedirs(TEMP_PATH)
      owns_temp = True
      # Existing download/extract/copy/import sequence.
  finally:
      if owns_temp:
          shutil.rmtree(TEMP_PATH)
  ```

  Replace, rather than supplement, the existing unconditional cleanup paths. A process lock
  should also guard concurrent scheduled/manual refreshes.

- **Status:** fixed 2026-10-11. Creating the temporary directory (`os.makedirs`, which fails if it exists) is the claim to run, and only the run that created it removes it. No separate process lock. Test: `test_a_second_run_leaves_the_first_runs_files_alone`.

### 8. An interrupted book import commits mixed old/new metadata

- **Severity:** Medium
- **Location:** [updatecatalog.py:78](gutendex/books/management/commands/updatecatalog.py#L78),
  [updatecatalog.py:220](gutendex/books/management/commands/updatecatalog.py#L220),
  [utils.py:150](gutendex/books/utils.py#L150)
- **The Defect:** Scalars are saved before relations and summaries without a per-book
  transaction. A valid XML element `<pgterms:marc520/>` becomes `summaries=[None]`;
  summary creation raises `IntegrityError` after the title and authors have already changed.
  The isolated book ended with the new title, no authors, and its old summary.
  No empty summaries occurred in the scanned real catalog; this is a verified failure path.
- **The Fix:** Wrap the complete per-book update in one transaction and discard empty summary
  literals at the parser boundary.

  ```python
  from django.db import transaction

  # Inside put_catalog_in_db(), retain the existing per-book loop:
  book = utils.get_book(id, book_path)
  try:
      with transaction.atomic():
          # Move all existing mutations at lines 79-227 into this block:
          # book save/create, authors, editors, subjects, formats and summaries.
          ...
  except Exception as error:
      # Retain the existing failed-record logging outside the transaction.
      raise

  # In the RDF parser:
  result["summaries"] = [element.text for element in summaries if element.text]
  ```

  There is no existing per-book helper to decorate. Decorating `put_catalog_in_db()` would
  instead create a whole-catalog transaction. This fix rolls back one failed book, not the
  entire refresh. The import already re-raises per-book errors; preserve that behavior.

- **Status:** left open on purpose (2026-10-27): never seen in the real catalog.

### 9. Refresh failures report successful command exit

- **Severity:** Medium
- **Location:** [updatecatalog.py:372](gutendex/books/management/commands/updatecatalog.py#L372)
- **The Defect:** The outer exception handler logs but does not propagate failures.
  Injecting a download `OSError` caused `call_command("updatecatalog")` to return normally.
  Cron/systemd cannot distinguish failure from a successful refresh.
- **The Fix:** Preserve the failure exit status, together with ownership-safe cleanup from #7.

  ```python
  except Exception as error:
      log("Error:", str(error))
      raise CommandError(str(error)) from error
  ```

- **Status:** fixed 2026-10-11 (with #6). Any failure is logged, the log is mailed, and the command raises `CommandError`, so it exits non-zero.

### 10. Gutendex silently drops search terms after the fourth

- **Severity:** Medium
- **Location:** [views.py:89](gutendex/books/views.py#L89)
- **The Defect:** The documented all-words search is implemented with `search_terms[:4]`.
  A book named `one two three four actual` matched a request for
  `one two three four missing`. Backend known-item post-filtering can remove wrong returned
  records, but cannot retrieve correct records displaced from the source's limited page.
- **The Fix:** Enforce an explicit length limit, then apply every nonempty token.

  ```python
  if len(search_string) > 300:
      raise drf_exceptions.ValidationError({"search": "Maximum 300 characters."})
  for term in search_string.split():
      queryset = queryset.filter(
          Q(authors__name__icontains=term) | Q(title__icontains=term)
      )
  ```

- **Status:** left open on purpose (2026-10-27): vendored Gutendex; our backend sends only `search=`, so it does not reach the app.

### 11. Author-year bounds can be satisfied by different authors

- **Severity:** Medium
- **Location:** [views.py:35](gutendex/books/views.py#L35)
- **The Defect:** Separate many-to-many filters can match different authors for opposite
  bounds. A book with one author alive in 1000-1100 and another in 2000-2100 matched
  1800-1899, although neither author was alive then.
- **The Fix:** Apply both bounds to the same author queryset, then join it once.

  ```python
  people = Person.objects.all()
  if author_year_end is not None:
      people = people.filter(
          Q(birth_year__lte=author_year_end) | Q(death_year__lte=author_year_end))
  if author_year_start is not None:
      people = people.filter(
          Q(birth_year__gte=author_year_start) | Q(death_year__gte=author_year_start))
  if author_year_start is not None or author_year_end is not None:
      queryset = queryset.filter(authors__in=people)
  ```

  The current imports already supply `Q` and `Person`. An isolated interval test also
  confirmed that an author living 1700-2000 still matches 1800-1899; the fix preserves
  current partial-date semantics.

- **Status:** left open on purpose (2026-10-27): vendored Gutendex; does not reach the app.

### 12. ID sorting orders database rows rather than Gutenberg numbers

- **Severity:** Low
- **Location:** [views.py:23](gutendex/books/views.py#L23),
  [tests.py:111](gutendex/books/tests.py#L111)
- **The Defect:** Returned API IDs are `gutenberg_id`, but sort uses Django's internal
  primary key. Inserting Gutenberg 100 before Gutenberg 10 returned `[100, 10]` for
  ascending sort. The existing test explicitly expects row insertion order.
- **The Fix:** Sort and test the public identifier.

  ```python
  queryset = queryset.order_by("gutenberg_id")   # ascending branch
  queryset = queryset.order_by("-gutenberg_id")  # descending branch
  ```

- **Status:** left open on purpose (2026-10-27): vendored Gutendex; does not reach the app.

### 13. The explorer rejects supported Opera and Safari versions

- **Severity:** Low
- **Location:** [index.js:82](gutendex/static/scripts/index.js#L82),
  [index.js:99](gutendex/static/scripts/index.js#L99)
- **The Defect:** Opera's regex alternative does not capture the version; Safari's version
  extraction drops its decimal. Executing the actual loader against mocked browser UAs
  rejected Opera 112 and Safari 10.1, although the loader declares them supported.
- **The Fix:** Capture the numeric version for each alternative.

  ```javascript
  versionMatch = navigator.userAgent.match(/\b(OPR|Edge)\/(\d+(?:\.\d+)?)/);
  if (versionMatch) {
    return {
      name: versionMatch[1] === 'OPR' ? 'opera' : 'edge',
      version: parseFloat(versionMatch[2])
    };
  }
  specialVersionMatch =
    navigator.userAgent.match(/version\/(\d+(?:\.\d+)?)/i);
  ```

- **Status:** left open on purpose (2026-10-27): the explorer page is not used by the app.

### 14. Explorer responses can overwrite a newer query

- **Severity:** Low
- **Location:** [get-results.js:3](gutendex/static/scripts/api-explorer/get-results.js#L3)
- **The Defect:** Independent fetches race to update one result area. Submitting `first`,
  then `second`, and resolving the first last displayed the first response under the second
  query. Both success and failure paths need stale-request suppression.
- **The Fix:** Gate rendering by a request generation, retaining the existing error message.

  ```javascript
  let generation = 0;
  // Inside getResults():
  const current = ++generation;
  fetch(urlElement.value)
    .then(response => response.json())
    .then(object => {
      if (current === generation)
        resultArea.textContent = JSON.stringify(object, null, 2);
    })
    .catch(() => {
      if (current === generation) resultArea.textContent = ERROR_MESSAGE;
    });
  ```

- **Status:** left open on purpose (2026-10-27): the explorer page is not used by the app.

## Security boundary

### 15. Readium rebuilds book scripts into an application-origin frame

- **Severity:** Medium
- **Location:** [readiumReader.js:1](app/web/readiumReader.js#L1):
  bundled `fs.finalizeDOM`, `_s`, and `Vs` implementations.
- **The Defect:** The active EPUB navigator preserves chapter scripts and rebuilds chapter
  text into a blob document. Its iframe permits `allow-scripts` and `allow-same-origin`;
  its generated CSP permits inline scripts. The execution-prevention shim restricts storage
  on the child window, but a book script can reach `parent.document` and `parent.localStorage`.
  The backend's sandbox response header does not propagate to a new blob document.

  The prerequisite is attacker influence over the Gutenberg EPUB being opened. No arbitrary
  user-upload endpoint was found. The security reviewer traced the actual frame and shim,
  accepted an in-memory scripted EPUB through the manifest builder, and executed the shim
  in an isolated JavaScript context. This was **not** an end-to-end browser exploit and does
  not establish an ability to change Gutenberg's upstream files.
- **The Fix:** Sanitize book markup before injecting trusted Readium helpers, preferably in
  a maintained package patch rather than hand-editing the minified bundle. Alternatively,
  isolate publication execution on a separate origin with validated messaging. The following
  is the required sanitization boundary, not a drop-in patch to the bundled minified file:

  ```javascript
  const cleanMarkup = DOMPurify.sanitize(chapterMarkup, {
    WHOLE_DOCUMENT: true,
    FORBID_TAGS: ['script', 'iframe', 'object', 'embed', 'base', 'meta', 'form']
  });
  const chapterDocument =
    new DOMParser().parseFromString(cleanMarkup, 'text/html');
  // Only after sanitization: inject the trusted Readium navigation helpers.
  ```

  Add a real-browser integration test containing a chapter script, an event handler, and an
  executable URL; assert none can mutate parent DOM/storage while normal navigation and
  TTS still work. DOMPurify would be a new dependency and must be maintained/configured.

- **Status:** fixed 2026-10-11, in the backend rather than in Readium's bundle: `PublicationStore.resource()` serves XHTML, HTML and SVG through `app/sanitize.py`, which removes scripts, frames, `<base>`, `<meta http-equiv>`, `on*` attributes, `srcdoc` and code URLs, and leaves every other byte as it was. Tests: `test_sanitize.py`, `test_publications.py`. Still not checked end to end in a browser.

## Claims deliberately excluded

- Missing `const` alone is not a verified defect or a demonstrated performance regression.
- Pydantic list defaults are not Python function-default shared-state bugs.
- Marking ignored futures `unawaited(...)` does not fix teardown ordering or prove a leak.
- Use of stdlib XML parsing alone is not proof of an exploitable XML vulnerability; no
  fabricated CVE or unsupported parser/library-version claim is included.
- RDF parser faults on missing rights/nonnumeric fields were reproducible, but did not
  occur in the complete local catalog scan. The actionable failure containment is #8/#9.
- Gutendex serialization showed an N+1 pattern (34 queries for four books); no latency
  threshold breach was established, so it is not counted as a verified performance defect.
- Deferred PDF viewing, off-web EPUB support, font bundling, nightly job installation, and
  untested native reader setup are known scope gaps, not newly discovered regressions.
- No spec or API contract has been changed by this review.

## Flutter recovery findings

### 16. A pending audio load starts playback after Pause or route disposal

- **Severity:** Medium
- **Location:** [audio_player.dart:60](app/lib/ui/audio_player.dart#L60),
  [audio_engine.dart:50](app/lib/services/audio_engine.dart#L50)
- **The Defect:** The controller marks playback active before loading; Pause/disposal pauses
  the player but does not invalidate the pending load. After `setUrl`, the real adapter
  unconditionally plays. A held fake load reproduced playback after controller disposal.
- **The Fix:** Invalidate play requests in the adapter, not merely in the widget. Also guard
  late controller error notifications and invalidate before engine disposal.

  ```dart
  int _playEpoch = 0;
  // At play entry, before loading:
  final epoch = ++_playEpoch;
  // After every loading/seeking await, before starting:
  if (epoch != _playEpoch) return;
  unawaited(_player.play());

  Future<void> pause() {
    ++_playEpoch;
    return _player.pause();
  }
  ```

- **Status:** fixed 2026-10-11. `JustAudioEngine` counts play requests; `pause()` and `dispose()` cancel a play still loading. The controller does not notify after disposal. Tests: `audio_engine_test.dart` (the real adapter with a held `AudioPlayer`).

### 17. Replaying a completed recording does not reset its position

- **Severity:** Medium
- **Location:** [audio_player.dart:47](app/lib/ui/audio_player.dart#L47),
  [audio_player.dart:79](app/lib/ui/audio_player.dart#L79),
  [audio_engine.dart:54](app/lib/services/audio_engine.dart#L54)
- **The Defect:** Final completion leaves the last chapter selected. Replay supplies no
  seek position, and the adapter reuses the already-loaded URL at its completed position.
  The reproduction observed `from=null` for the completed URL. Selecting the already-loaded
  chapter likewise does not explicitly restart it.
- **The Fix:** Distinguish resume from explicit restart; reset on completion replay and chapter
  selection, but preserve ordinary paused resume.

  ```dart
  // For a completed replay or explicit chapter selection:
  await _engine.play(chapter.url, from: Duration.zero);
  // For ordinary resume, retain the existing current position.
  ```

  Wire the restart flag/state through the controller's existing `_start` path and clear the
  completed state when a new chapter starts. Do not seek every Play action to zero.

- **Status:** fixed 2026-10-11. Play after the last chapter ended, and choosing a chapter, start from 0:00; Play after Pause resumes. Tests in `audio_player_test`.

### 18. Voice lookup completes after Stop or renderer disposal and starts TTS

- **Severity:** Medium
- **Location:** [text_engine.dart:454](app/lib/reader/text_engine.dart#L454),
  [text_engine.dart:505](app/lib/reader/text_engine.dart#L505)
- **The Defect:** `hasVoice` is awaited before a speech generation is allocated. Stop only
  invalidates existing loops, so the delayed lookup starts a new one after Stop. A separate
  dispose probe raised "A TextReaderEngine was used after being disposed."
- **The Fix:** Allocate/check the generation around voice lookup; all stop/dispose paths must
  invalidate pending starts. Keep the existing no-voice error notification.

  ```dart
  final session = ++_session;
  final code = language ?? 'en';
  final available = await _speech.hasVoice(code);
  if (_engine._disposed || session != _session) return;
  _language = code;
  if (!available) {
    state.value = _now.copyWith(
      status: ReadAloudStatus.stopped,
      error: 'This device has no voice for ${languageName(code)}.',
    );
    return;
  }
  await _read(_engine._firstWord);
  ```

- **Status:** fixed 2026-10-11 as proposed. Tests in `read_aloud_test` (`FakeSpeechEngine.holdVoices`).

### 19. A CJK paragraph becomes one overflowing page

- **Severity:** Medium
- **Location:** [pagination.dart:13](app/lib/reader/pagination.dart#L13),
  [pagination.dart:159](app/lib/reader/pagination.dart#L159),
  [text_engine.dart:274](app/lib/reader/text_engine.dart#L274)
- **The Defect:** Whitespace-only tokenization makes a Chinese/Japanese paragraph one token.
  Page breaks cannot split that token. A 2,400-character Chinese paragraph produced one page
  with text height 3,618px inside a 560px viewport; most text cannot be reached by turning pages.
- **The Fix:** Use legal character/grapheme line boundaries for slicing and locators, retaining
  original text. Do not insert spaces into CJK text. This requires paginator, rendering and
  bookmark conversion to change together, not just tokenization.

  ```dart
  final boundary =
      painter.getLineBoundary(TextPosition(offset: cursor));
  pageCharacterStarts.add(boundary.start);
  final visible = paragraph.substring(pageStart, pageEnd);
  ```

  The snippet identifies the replacement boundary representation, not a drop-in local patch.
  Support legacy `word:` locators and test combining marks, mixed scripts and unbroken tokens.
  Until implemented, an explicit scroll fallback is preferable to inaccessible truncated pages.

- **Status:** fixed 2026-10-11. `BookText` makes each CJK character a word, and splits runs of more than 40 characters without a space into grapheme clusters; `spaceBefore` keeps the text without added spaces (also in what is spoken aloud). Bookmarks in CJK books made before this point to other words. Tests in `pagination_test`, `text_engine_test`.

### 20. Scroll bookmarks discard the location inside a paragraph

- **Severity:** Medium
- **Location:** [text_engine.dart:373](app/lib/reader/text_engine.dart#L373),
  [text_engine.dart:419](app/lib/reader/text_engine.dart#L419)
- **The Defect:** Anchor saving and restoration use only the paragraph's first word/top.
  A 1,000-word paragraph scrolled 1,000px still reported `word:0`. Bookmarks and TTS resume
  return multiple screens backward.
- **The Fix:** Map the viewport's caret to a character/word offset and restore that line,
  using the same TextPainter width, scale, style and padding as rendering.

  ```dart
  final caret = painter.getPositionForOffset(
    Offset(0, viewportOffset - paragraphTop),
  );
  final anchor = wordAtCharacter(paragraph, caret.offset);
  final y = painter.getOffsetForCaret(
    TextPosition(offset: book.wordOffsets[anchor]), Rect.zero,
  ).dy;
  final initialOffset = paragraphTop + y;
  ```

  `wordAtCharacter` is a new binary-search helper; account for the ListView's 16px top padding.
  Implement jointly with #19 if the locator representation changes.

- **Status:** fixed 2026-10-11. `_ScrollLayout.anchor()` gives the first word of the line at the top; `attach()` opens at that word's line. Tests in `text_engine_test` ("in a long paragraph").

### 21. Scroll reflow preserves pixels rather than the reading location

- **Severity:** Medium
- **Location:** [text_engine.dart:194](app/lib/reader/text_engine.dart#L194),
  [text_engine.dart:348](app/lib/reader/text_engine.dart#L348)
- **The Defect:** Font/spacing/viewport changes recompute paragraph geometry but reuse the
  old pixel offset. Font 18 to 36 changed the locator from `word:154` to `word:22` while the
  controller stayed at 2,000px.
- **The Fix:** Capture the logical anchor before invalidation, rebuild scroll geometry and
  reattach at its new offset. Apply to viewport/text-scale changes as well as preferences.

  ```dart
  if (_scrolling) {
    _anchor = _scroll?.anchor() ?? _anchor;
    _scroll?.controller.dispose();
    _scroll = null;
  }
  _settings = settings;
  _changed();
  ```

  This depends on the accurate anchor mapping in #20; reusing the old pixel controller is not
  equivalent to preserving a reading location.

- **Status:** fixed 2026-10-11. A new scroll layout opens at the old layout's anchor word. The list is keyed by its layout: a list given a new controller keeps the old pixel offset and ignores `initialScrollOffset`. Test in `text_engine_test`.

### 22. Responsive layout resets active search input to the original route query

- **Severity:** Low
- **Location:** [results_page.dart:55](app/lib/ui/results_page.dart#L55),
  [results_page.dart:86](app/lib/ui/results_page.dart#L86)
- **The Defect:** Crossing 840px reparents the stateful search bar and initializes it with
  the route's original query. After searching Title/Frankenstein, resizing to phone showed
  Anything/pride while the results still represented Frankenstein; drafts are lost too.
- **The Fix:** Preserve the bar's state across the mutually exclusive branches, or lift its
  controller/field into ResultsPage.

  ```dart
  // Allocate once in _ResultsPageState:
  final _searchBarKey = GlobalKey();
  // On the existing BookSearchBar, present exactly once per build:
  key: _searchBarKey,
  ```

- **Status:** fixed 2026-10-11 as proposed (`GlobalKey`). Test in `search_results_test`.

### 23. Paginated paragraph spacing ignores most values

- **Severity:** Medium
- **Location:** [text_engine.dart:223](app/lib/reader/text_engine.dart#L223),
  [pagination.dart:110](app/lib/reader/pagination.dart#L110)
- **The Defect:** The 0-3em preference is reduced to a binary newline separator. Values 1
  and 3 produced identical text/style and the same 78-page count. The accessibility control
  claims a spacing change that does not happen in the default page mode.
- **The Fix:** Pass numeric paragraph gaps through measurement, rendering and cache keys.
  Render paragraph slices with matching gaps instead of one threshold-separated Text.

  ```dart
  final gap = settings.paragraphSpacing * settings.fontSize;
  // New paginator input and layout-cache component:
  paragraphGap: gap,
  // Between rendered paragraph slices:
  SizedBox(height: gap),
  ```

  This is a coordinated paginator/rendering change; an unrelated SizedBox beside the existing
  monolithic Text does not solve it. Include text scaling consistently.

- **Status:** fixed 2026-10-11. Pages use `paragraphSpacing × fontSize` pixels, like the scroll view; `pageSpan` draws the empty line between paragraphs at that height, and the paginator measures the same line. Tests in `pagination_test`, `text_engine_test`.

### 24. Concurrent bookmark taps invert the UI relative to storage

- **Severity:** Low
- **Location:** [reader_page.dart:145](app/lib/reader/reader_page.dart#L145)
- **The Defect:** Two taps see the same pre-save boolean, both save, and both toggle it after
  awaiting. The reproduction left a saved bookmark while the button said "Add bookmark."
- **The Fix:** Serialize the operation, disable the button while busy, and assign the captured
  target instead of toggling after completion.

  ```dart
  if (_bookmarkBusy) return;
  _bookmarkBusy = true;
  final target = !_bookmarked;
  try {
    if (target) {
      final at = _engine!.position;
      await _services.bookmarks.save(
        key, Bookmark(progress: at.progress, locator: at.locator),
      );
    } else {
      await _services.bookmarks.remove(key);
    }
    if (mounted) setState(() => _bookmarked = target);
  } finally {
    _bookmarkBusy = false;
  }
  ```

  Add the busy field and preserve successful notifications. Surface persistence errors using
  the application's notification pattern; do not leave them as uncaught futures.

- **Status:** fixed 2026-10-11 as proposed. Test in `reader_test` (`HeldBookmarkStore`).

### 25. Non-English book content has no semantic language annotation

- **Severity:** Medium
- **Location:** [text_engine.dart:289](app/lib/reader/text_engine.dart#L289),
  [reader_page.dart:231](app/lib/reader/reader_page.dart#L231),
  [app.dart:83](app/lib/app.dart#L83)
- **The Defect:** A genuine in-app Spanish book inherited English UI locale, had null Text
  locale and no `Semantics.localeForSubtree` override. Book language drives TTS but is not
  communicated to screen-reader semantics. This verifies missing metadata, not actual
  VoiceOver/TalkBack pronunciation.
- **The Fix:** Scope the known language to book content without changing English controls.

  ```dart
  Semantics(
    localeForSubtree: widget.book.language == null
        ? null : Locale(widget.book.language!),
    child: _engine!.buildView(context),
  )
  ```

  Set appropriate Text locale/direction for glyph layout as well, and validate real
  screen-reader language switching on devices.

- **Status:** fixed 2026-10-27, differently: this Flutter has no `localeForSubtree` on `Semantics`, so the text engine gives its `Text` widgets the book's `locale` (`ReaderEngine.buildView(context, {locale})`), which Flutter puts in the semantics node. The Readium (web) view is an HTML page and is not changed here. Tests in `text_engine_test` ("marked with the book's language"). Real VoiceOver/TalkBack switching not checked.

### 26. Disposed Readium engines retain publications opened late

- **Severity:** Low
- **Location:** [readium_engine.dart:47](app/lib/reader/readium_engine.dart#L47),
  [readium_engine.dart:124](app/lib/reader/readium_engine.dart#L124)
- **The Defect:** Disposal closes a publication only if open has already assigned it.
  Releasing a held `openPublication` after disposal assigned the publication but called
  `closePublication` zero times. No live iframe appearance is asserted.
- **The Fix:** Check disposal immediately after opening and close abandoned publications.
  Because the plugin is a singleton, serialize open/close across engines or use an ownership
  lease; blindly closing a stale engine could otherwise close a newer reader's book.

  ```dart
  final publication =
      await _readium.openPublication(manifest.toString());
  if (_disposed) {
    await _readium.closePublication();
    return;
  }
  _publication = publication;
  ```

  Set `_disposed` before any disposal await. The excerpt requires the shared ownership boundary,
  not just a per-engine flag.

- **Status:** fixed 2026-10-11. `_disposed` is set first in `dispose`; opening and closing go through one queue shared by all Readium engines, so a book opened late is closed before the next reader opens its own. Tests in `readium_engine_test` (`FakeReadium`).

## Source adapter and HathiTrust refresh recovery findings

### 27. Unreadable Hathifile payloads replace the last-good catalog or advance its watermark

- **Severity:** High
- **Location:** [hathitrust_update.py:79](backend/app/hathitrust_update.py#L79),
  [hathifile.py:79](backend/app/hathifile.py#L79)
- **The Defect:** Valid gzip compression is mistaken for usable catalog data. Rows with
  fewer than 26 columns are silently ignored. A compressed HTML error replaced an existing
  index with zero volumes and recorded the new full-file state; a malformed daily payload
  advanced its watermark despite applying no recognizable records. Existing compressed
  truncation tests do not cover this semantic failure.
- **The Fix:** Validate the streamed import before its iterator exhausts successfully, so the
  existing build cleanup/daily transaction rollback preserves the old index and state.
  Reject unusable nonblank data, and reject full snapshots with no recognizable/retained books.

  ```python
  # In an update-layer validated generator, not generic HathiIndex.replace_all:
  if nonblank_rows and recognized_rows == 0:
      raise UpdateError("Hathifile payload contains no recognizable records")
  if is_full and retained_books == 0:
      raise UpdateError("Full Hathifile contains no searchable books")
  ```

  Add these counters while consuming rows; validate at generator completion *before* the
  caller commits/replaces. Distinguish legitimate deny/non-book rows from malformed rows.
  Define and test any tolerated malformed-row policy explicitly rather than silently ignoring it.

- **Status:** fixed 2026-10-11. `_checked` counts rows as they stream: lines but no Hathifile rows, or a monthly file with no open book, raise `UpdateError` before the commit. Tests in `test_hathitrust_update`.

### 28. Concurrent index writers can publish another writer's unfinished database

- **Severity:** Medium
- **Location:** [hathitrust_index.py:160](backend/app/hathitrust_index.py#L160),
  [hathitrust_index.py:178](backend/app/hathitrust_index.py#L178),
  [hathitrust_update.py:73](backend/app/hathitrust_update.py#L73)
- **The Defect:** All writers share `<index>.building`. Beta unlinks Alpha's staging pathname
  and creates its own file; Alpha then renames Beta's unfinished database into the live path.
  A deterministic two-thread schedule observed live count zero/state None while Beta was
  paused; Beta later raised FileNotFoundError. A daily transaction racing a full replacement
  separately raised "attempt to write a readonly database."
- **The Fix:** Serialize writers across processes before reading state/planning, and give each
  build its own staging file. Lock the entire state/plan/full/daily sequence; unique staging
  names alone do not fix stale plans or daily-vs-rebuild races.

  ```python
  import fcntl
  import tempfile

  # At the CLI/update entry, after ensuring the index parent exists:
  with open(lock_path, "a") as lock:
      fcntl.flock(lock, fcntl.LOCK_EX)
      # Read state, compute plan and perform the existing update here.

  # Inside replace_all, replace the shared staging filename:
  fd, name = tempfile.mkstemp(
      dir=self.path.parent, prefix=self.path.name + ".", suffix=".building",
  )
  os.close(fd)
  building = Path(name)
  ```

  Integrate writer-owned cleanup. The flock snippet applies to this macOS/Linux deployment;
  use a supported cross-platform locking implementation if Windows is required. All callers
  of mutation APIs need the same ownership contract; scheduler-only locks do not cover manual runs.

- **Status:** fixed 2026-10-11. `HathiIndex.writing()` holds a `flock` on `<index>.lock` for the whole update; a second run fails at once with "already running". The staging file name is unchanged (only the lock holder writes it).

### 29. Missing interior daily files are permanently skipped

- **Severity:** Medium
- **Location:** [hathitrust_update.py:62](backend/app/hathitrust_update.py#L62)
- **The Defect:** Gap detection checks the oldest listed daily file, not continuity through
  the proposed range. With state October 1 and listed days 1 and 3, it applied day 3 and
  advanced the watermark. A later day-2 deny row was never applied; the volume stayed open.
- **The Fix:** Require a contiguous series after the current/full baseline. Do not rebuild
  and leap the same uncovered gap; keep missing days retryable.

  ```python
  expected = next_day(baseline_through)
  for update in proposed_updates:
      if update_day(update) != expected:
          raise UpdateError(f"Missing daily Hathifile for {expected}")
      expected = next_day(expected)
  ```

  `update_day` represents the existing filename-date extraction, not a new parsing convention.
  Put validation before applying a later file or advancing state. Test late-arriving rights changes.

- **Status:** fixed 2026-10-11. `plan_update` applies the days up to the first missing one and sets `Plan.missing`; `update_index` then raises `UpdateError`, and the next run goes on from there. Checked against the live list (no gaps over 71 days).

### 30. Wrong-shape OAI XML silently erases valid DOAB hits

- **Severity:** Medium
- **Location:** [doab.py:60](backend/app/sources/doab.py#L60),
  [doab.py:90](backend/app/sources/doab.py#L90)
- **The Defect:** Well-formed XML with the wrong root or OAI `badArgument` yields an empty
  record list, interpreted as deletion. A good Atom search hit followed by valid XML HTML
  returned zero books, whereas syntactically malformed XML correctly preserved the fallback hit.
- **The Fix:** Validate protocol/envelope/metadata and classify unusable lookup replies as
  SourceError, letting the existing per-lookup fallback keep the Atom hit.

  ```python
  if root.tag != f"{{{OAI_NAMESPACE}}}OAI-PMH":
      raise SourceError("DOAB lookup returned an unexpected XML document")
  error = root.find(f"{{{OAI_NAMESPACE}}}error")
  if error is not None:
      if error.get("code") == "idDoesNotExist":
          return []
      raise SourceError(f"DOAB OAI lookup failed: {error.get('code')}")
  ```

  Use the existing namespace constant, or define the OAI-PMH namespace if absent. Also require
  usable GetRecord metadata; preserve positively identified deletion/chapter behavior. A failed
  lookup must not mark the entire source down when OpenSearch itself succeeded.

- **Status:** fixed 2026-10-11. A lookup answering another OAI error, or XML that is not OAI-PMH, keeps the search hit. Tests in `test_source_doab`.

### 31. Malformed nested upstream JSON bypasses the unreadable-answer outage rule

- **Severity:** Medium
- **Location:** [openlibrary.py:56](backend/app/sources/openlibrary.py#L56),
  [openlibrary.py:148](backend/app/sources/openlibrary.py#L148),
  [librivox.py:48](backend/app/sources/librivox.py#L48),
  [librivox.py:80](backend/app/sources/librivox.py#L80)
- **The Defect:** Only the outer dictionary/list is validated. `docs:[null]`,
  `books:[null]`, `sections:[null]` raised AttributeError; an object-valued Open Library
  author raised TypeError. Through SearchService these became `skipped:error` without outage,
  so the unusable answer is fetched repeatedly and valid records on the page are discarded.
- **The Fix:** Validate the upstream schema at each nested boundary and raise SourceError
  for known schema violations. Do not wrap genuine implementation bugs in a blanket catch.

  ```python
  for record in records:
      if not isinstance(record, dict):
          raise SourceError("Source returned a non-object book record")

  if authors is not None and (
      not isinstance(authors, list)
      or any(value is not None and not isinstance(value, str)
             for value in authors)
  ):
      raise SourceError("Source returned malformed author names")
  ```

  Apply source-specific required ID/key, section, string and numeric validation, while retaining
  documented optional nulls. Open Library null author entries were tolerated and are not a defect.

- **Status:** fixed 2026-10-11, differently: bad records are skipped and the rest of the answer is kept, rather than raising `SourceError` (which would start a 24-hour outage over one null). Tests: `TestMalformedRecords` in `test_source_openlibrary`, `test_source_librivox`.

### 32. Decomposed Unicode accents split HathiTrust search words

- **Severity:** Medium
- **Location:** [hathitrust_index.py:207](backend/app/hathitrust_index.py#L207)
- **The Defect:** The Python word regex treats a combining acute as a separator. Composed
  `misérables` found one book; visually identical decomposed `mise\u0301rables` found none.
  SQLite accent folding cannot repair the already-separated mandatory FTS terms.
- **The Fix:** Normalize canonical Unicode before token extraction.

  ```python
  import unicodedata

  def _search_words(text: str) -> list[str]:
      text = unicodedata.normalize("NFC", text)
      return [
          word for word in _WORD.findall(text)
          if word.lower() not in _STOPWORDS
      ][:MAX_SEARCH_WORDS]
  ```

  Test composed/decomposed title, author and free-text fields; preserve stopword-only behavior.

- **Status:** fixed 2026-10-11 as proposed (NFC before splitting). Text stored with separate accent marks was already found. Test in `test_hathitrust_index`.
