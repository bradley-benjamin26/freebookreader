# Backend tests (written before the code)

These tests define the backend. They were written before `backend/app/` existed; all of them pass as of
2026-10-10. A milestone is done when its tests pass.

```bash
cd backend
python3 -m venv venv && source venv/bin/activate
pip install -r requirements-dev.txt
python -m pytest                 # whole suite
python -m pytest tests/test_merge.py -q
python -m pytest -m "not slow"   # skip the tests that use real sleeps (about 3 s)

# Run the API (Gutendex must be running on port 8001)
uvicorn app.main:create_app --factory --port 8000
```

Settings come from `FBR_*` environment variables: `FBR_GUTENDEX_URL`, `FBR_LIBRIVOX_URL`, `FBR_OPENLIBRARY_URL`,
`FBR_DOAB_URL`, `FBR_HATHITRUST_INDEX` (default `backend/cache/hathitrust.sqlite`), `FBR_HATHITRUST_FILE_LIST_URL`, `FBR_SEARCH_TIMEOUT_SECONDS`, `FBR_MAX_CONCURRENT_SEARCHES`, `FBR_SEARCH_ADMISSION_SECONDS` (default 3), `FBR_OUTAGE_COOLDOWN_HOURS`, `FBR_CORS_ORIGINS` (comma-separated,
default `*`) and `FBR_CONTACT`. The EPUB cache for the web reader uses `FBR_GUTENBERG_URL` (default
`https://www.gutenberg.org`), `FBR_EPUB_CACHE_DIR` (default `backend/cache/epub`, ignored by git),
`FBR_MAX_DOWNLOAD_MB` (200) and `FBR_EPUB_CACHE_MB` (2000). The `User-Agent` is built from the project's top-level `.env` (JSON:
`projectName` and `email`; `name` is never sent), e.g. `FreeBookReader/0.1 (email)`. Open Library allows
3 requests/second instead of 1 when it names a contact. `FBR_CONTACT` overrides the email and `FBR_ENV_FILE`
points at another file.

Gutendex has its own regression tests (it is already built):
`cd gutendex && source venv/bin/activate && python manage.py test books --settings=gutendex.test_settings`
(uses in-memory SQLite, so it needs no Postgres privileges and cannot touch the catalog).

## Milestones to tests

| Milestone (spec.md) | Tests |
|---|---|
| Project Gutenberg search | `test_source_gutendex.py` (+ `gutendex/books/tests.py`) |
| LibriVox search | `test_source_librivox.py` |
| DOAB search (replaces OAPEN, 2026-10-10) | `test_source_doab.py` |
| Open Library search | `test_source_openlibrary.py` |
| HathiTrust: Hathifile rows -> volumes | `test_hathifile.py` |
| HathiTrust: the local index and its search | `test_hathitrust_index.py` |
| HathiTrust: nightly update from the Hathifiles | `test_hathitrust_update.py` |
| HathiTrust search (source adapter) | `test_source_hathitrust.py` (+ `test_merge.py`, `test_reader.py`, `test_sources_info.py`, `test_config.py`) |
| System that provides Project Gutenberg access is built and tested | `gutendex/books/tests.py`, `test_source_gutendex.py` |
| Records merged into works by the Data Merging rules | `test_merge.py`, `test_normalize.py` |
| Search across / select targets, filters, known-item search | `test_search_service.py` |
| Source outage: stop returning results for 24 h | `test_outage.py`, `TestOutages` in `test_search_service.py` |
| Search results within 15 s | `TestTimeout`, `test_default_timeout_leaves_room_inside_the_15_second_budget`, `test_sources_are_queried_in_parallel` |
| Viewer displays in-app sources, others link out | `test_reader.py` |
| Gutenberg EPUB served for the web reader (decision_reader.md, spike 9b/9c) | `test_publications.py`, `TestPublication` in `test_reader.py` |
| About pages content | `test_sources_info.py` |
| API the app talks to | `test_api.py`, `test_config.py` |
| Data model (Work -> book) | `test_models.py` |

## The contract the tests expect

```
backend/app/
  models.py        Book, Chapter, Work, SearchQuery (pydantic v2)
  normalize.py     normalize_author_name, author_key, title_key, normalize_isbn, normalize_oclc, to_language_code, to_marc_language
  sources/
    base.py        SourceError;  a Source has .name and .search(SearchQuery) -> list[Book]
    gutendex.py    GutendexSource(client: httpx.Client, base_url)          name "gutenberg"
    librivox.py    LibriVoxSource(client, base_url)                        name "librivox"
    openlibrary.py OpenLibrarySource(client, base_url); .availability(isbn) -> Availability|None   name "openlibrary"
    doab.py        DoabSource(client, base_url); .parse_opensearch(xml), .parse_xoai(xml) (static)  name "doab"
    hathitrust.py  HathiTrustSource(index: HathiIndex)   name "hathitrust"; HathiIndexMissing (not a SourceError)
  hathifile.py     Volume, parse_line(line) -> (htid, Volume|None)|None, iter_changes(lines), clean_title, clean_author, reader_url
  hathitrust_index.py   HathiIndex(path): exists, state, count, search(text,title,author,isbn,language,limit,offset), replace_all(volumes, state), apply(changes, state), writing() (lock; IndexBusy); IndexState
  hathitrust_update.py  plan_update(file_list, state) -> Plan(full, updates, missing); update_index(client, index, file_list_url) -> UpdateResult; iter_gzip_lines; main (python -m app.hathitrust_update)
  merge.py         merge_books(list[Book]) -> list[Work]
  outage.py        OutageTracker(clock, cooldown=24h): record_failure, is_available, unavailable, retry_at
  search.py        SearchService(sources, outage, timeout_seconds=12, max_in_flight=8, cache_seconds=0, cache_entries=500, now): search(SearchQuery) -> SearchResponse
  reader.py        reading_options(Book) -> ReadingOptions(mode, kind, url, publication)
  publications.py  build_manifest(ZipFile, max_entry_bytes) -> dict; PublicationStore(client, gutenberg_url, cache_dir, max_download_bytes,
                   max_cache_bytes, max_entry_bytes, catalog): GutendexCatalog(client, gutendex_url)(id) -> True/False/None; manifest(id), resource(id, href) -> (bytes, type);
                   PublicationNotFound (404), PublicationUnavailable (502), PublicationTimeout (504)
  sanitize.py      sanitize_markup(bytes) -> bytes (book pages without scripts)
  sources_info.py  SOURCES, get_source_info(id)
  config.py        Settings.from_env, build_search_service(settings, client)
  main.py          create_app(search_service, settings, publication_store) -> FastAPI:  GET /health, /search, /sources,
                   /publications/gutenberg/{id}/manifest.json, /publications/gutenberg/{id}/{href}
```

Sync `httpx.Client` is injected everywhere so tests can use `httpx.MockTransport`. Sources are
queried in parallel threads, on one executor shared by all searches.

## Decisions the tests encode (change them here and in the tests together)

- **Unknown language never merges by title/author.** A record with `language=None` (Open Library works
  usually span many languages) only merges through a shared ISBN/OCLC. This follows "a duplicate is
  better than a false merge", and it means Open Library records will often stay separate from
  Gutenberg ones.
- **Records with no author never merge on title alone.**
- **A fuzzy author match allows fuzziness only in the surname.** Both records need the same number of
  authors, each with the same number of name parts and identical given names; only the surnames may differ
  (rapidfuzz ratio ≥ 90). "Mary Shelley"/"Mary Shelly" and "Fyodor Dostoevsky"/"Fyodor Dostoyevsky" merge;
  "John Smith"/"Joan Smith", "Thomas Hardy"/"Thomas Harding" and "Mary Shelley"/"Mary W. Shelley" do not.
  A one-letter surname difference between two real people ("John Adams"/"John Addams") still merges.
- **Different languages never merge, even with the same ISBN.**
- **An ISBN/OCLC number held by two records of one source merges nothing** (`TestOmnibusAndSharedIdentifiers`,
  2026-10-11). Open Library lists the ISBNs of every edition of a work, so an omnibus shares them with the novel and
  the old rule merged them. The rule is about records, not volumes: copies of one HathiTrust record (same
  `identifiers.hathitrust`) count as one. When two records of one source hold the identifier, a third source's record
  does not merge on it either (it is unknown which one it belongs to); its other identifiers and the title passes
  still can.
- **Gutenberg cross-references merge** (`TestGutenbergReferences`, 2026-10-11). A LibriVox or Open Library record
  with `identifiers.gutenberg` joins the Gutenberg eBook of that number if it is in the results, still never across
  languages. A record naming one eBook is trusted; a record naming several (Open Library) is joined only to eBooks
  whose title is similar (ratio ≥ 90), so an omnibus that names the eBooks of several novels does not join them.
- **HathiTrust is searched in a local index, never live** (decision_hathitrust.md). `HathiIndex` is a SQLite file with
  an FTS5 table over title and author (accents and case ignored, every word must match, words are quoted so search
  syntax is plain text, a title word weighs 4 times an author word, stopwords like "the" and "of" are left out, and a field made only of them is ignored, so a search with nothing else finds nothing: `TestStopwords`). It holds only rows with `access = allow` and
  `bib_fmt = BK` (not serials, maps or music), so a daily file's 485,566 rows give 36,833 volumes. Search returns one
  copy per catalog record and volume label (Harvard and the New York Public Library each holding the same book show
  once; `v.1` and `v.2` both show), 20 a page, language by MARC code (`fre`). A missing index raises `HathiIndexMissing`
  (not a `SourceError`, so no 24-hour outage; the response lists the source as skipped with reason `error`).
- **The index is updated by `python -m app.hathitrust_update`** (`plan_update`). The first run builds from the newest
  monthly file (1.2 GB, streamed and decompressed on the fly, built beside the old file and swapped in, so searches
  keep working); later runs apply only the daily files after the last one, each in one transaction, so a failed
  download leaves the index at the last good day. A volume whose row is now `deny` (or not a book) is removed. A new
  monthly file or a gap in the daily files (the list keeps about 70 days) means a rebuild, which is also how volumes
  HathiTrust removed leave: the daily files do not say. A missing day between daily files (review 2026-10-11-main
  #29) stops the run after the day before it, with an error; the next run goes on from there (`Plan.missing`).
  A file that has lines but no Hathifile rows (a gzipped error page), or a monthly file with no open book, is an
  error before anything is committed, so the old index and its date stay (#27). One update runs at a time: a lock
  file beside the index (`HathiIndex.writing`), and a second run fails at once with "already running" (#28).
- **HathiTrust books link out.** Each book is one volume with `url` `https://babel.hathitrust.org/cgi/pt?id=<htid>`,
  `volume` ("v.2"), `library` (name for the 40 most common library codes, else the code) and `us_only` (rights `pdus`).
  Copies and volumes of one catalog record merge into one work through `identifiers.hathitrust` (= `ht_bib_key`), a new
  pass-1 identifier next to ISBN and OCLC. Titles lose the part after ` / `; authors lose dates.
- **The placeholder ISBN is not an ISBN**: `normalize_isbn` returns None for `9780000000002` (and `0000000000`, its
  ISBN-10 form), which HathiTrust puts on unrelated books, so it never merges books and an ISBN search for it finds
  nothing.
- **Chapters are not books** (DOAB also lists chapters); deleted OAI records are skipped.
- **DOAB search is OpenSearch, then one OAI `GetRecord` (xoai) per hit**, because DOAB's REST API rejects our IP.
  Stale search entries (`Untitled`, or `idDoesNotExist`) are skipped. If a lookup fails, the hit is kept with what
  the search said; so is a lookup that answers with another OAI error or with XML that is not OAI-PMH (#30). A download link ending in `.pdf` (usually in the OAPEN Library) is the book's PDF; any other
  link is left to the DOAB record page. DOAB's `open-access-no-cover.png` placeholder is not a cover.
- **Invalid ISBNs are dropped.** OAPEN/DOAB data contained one with a bad check digit.
- **A malformed record is skipped, not the source** (review 2026-10-11-main #31, `TestMalformedRecords`). A null or
  non-object Open Library doc or LibriVox book, chapter or reader, and author names that are not text, are left
  out; the rest of the answer is used. It is not an outage either: the source answered.
- **Identifier merging tries every pair** (#2): when the first record holding an identifier is in another language,
  the others still merge with each other.
- **Open Library always links out**, and only to books a user can read or borrow now (user request 2026-10-10).
  `q` always ends with `ebook_access:[borrowable TO *]` (with `title`/`author`/`isbn` alone, `q` is just that
  filter), which also makes the `editions` sub-query return a free or borrowable edition. The link is that edition
  (`/books/OL…M`), because the work page can feature one with no ebook (`/works/OL497167W` did). Access comes from
  the edition (`open` or `borrow`); anything else is dropped. Then one `/availability/v2?type=openlibrary_edition`
  call drops editions whose status is not `open` or `borrow_available` (`borrow_unavailable` = all copies on loan,
  `error` = no scan); an edition missing from the answer is kept. That endpoint is undocumented, so if it fails
  in any way (including a timeout or a 4xx) the search's results are kept and it is not an outage.
- **A known-item search** (title, author or ISBN) returns only works with a matching title/author/ISBN.
  `q` and `keyword` are exploratory and are not narrowed.
- **A title matches with or without its subtitle** (`title_matches`; user chose option B for review #5, 2026-10-10).
  A subtitle starts at `:`, `;`, `(`, `, or` or a spaced dash; a bare ` or ` does not start one ("To Be or Not to Be").
  A trailing volume marker (`Tome I`, `Volume 2`) is dropped from the book's title, but a volume named in the search
  must match. A subtitle with a study-aid word (`guide`, `study`, `notes`, `summary`, `analysis`, `companion`,
  `commentary`, `criticism`, `SparkNotes`, ... see `_STUDY_AID_WORDS`) is a different book unless the search gives the
  whole title. Leading articles in other languages (`Les`, `Die`, ...) are ignored when matching, because LibriVox
  catalogs "Misérables"; merging still uses the stricter `title_key`.
- **Gutenberg isbn-only searches, LibriVox/Open Library audio or text mismatches** make no request.
- **LibriVox author search uses the last name only** (the full name returns "could not be found"). A trailing
  suffix (`Jr.`, `Sr.`, `II`–`VI`) is skipped, so "Charles Dickens Jr." sends `author=Dickens` (review 2026-10-10,
  #8); a name that is only a suffix makes no request. The service's known-item filter still tells the son from
  the father.
- **A suffix after a comma is not a given name** (`normalize_author_name`): "Charles Dickens, Jr." and
  "Dickens, Charles, Jr." both give "Charles Dickens Jr.", a different `author_key` from "Charles Dickens". A lone
  letter ("Smith, V.") is an initial, not a numeral. Roman numerals stay uppercase ("Henry Ford II"), but a
  mixed-case "Vi" is left alone, since it is also a name.
- **LibriVox title and free-text searches send `title=^<text>`.** Without `^`, LibriVox matches the exact
  full title only (`title=pride` finds nothing, and other recordings such as "... (version 2)" are missed).
  It has no keyword search, so free text is a title-prefix search.
- **A timeout is not an outage.** A source that misses the 12 s deadline (`FBR_SEARCH_TIMEOUT_SECONDS`, review 2026-10-11, #20: the spec's 15 s for results includes the merging and the network after it), or whose HTTP request times out
  (`SourceTimeout`), is listed in `unavailable_sources` for that search only and is asked again next time.
  Errors (refused connections, `5xx`, unusable bodies) still start the 24-hour outage, except for a source with `own = True` (Gutendex, our own service): its errors leave it out of that search only, reason `error` (audit 2026-10-27, F2).
- **`skipped` says why a source is missing** (review 2026-10-11, #13). `unavailable_sources` lists every selected
  source missing from the response; `skipped` is the same list as `{source, reason}`, reason one of `outage`
  (down, not asked for up to 24 hours), `timeout` (too slow, asked again next time), `busy` (4 searches already
  running), `rejected` (it answered 4xx) or `error` (our adapter crashed). The app words each case.
- **Responses are gzipped** (2026-10-11, `TestCompression` in `test_api.py`): `GZipMiddleware`, only for clients sending
  `Accept-Encoding: gzip`, only above 1,000 bytes; images and other compressed files are skipped. A search for
  "pride and prejudice" went from 111 KB to 12 KB (about half of the 111 KB is LibriVox chapter lists; chapters are
  still in the response because the player uses them).
- **Long identifier lists are cut in the response** (review 2026-10-11, #15). A `Book` or `Work` serializes at most
  20 identifiers of each kind (`MAX_SERIALIZED_IDENTIFIERS`); merging and the known-item ISBN check see them all.
- **LibriVox keeps "Il" and "De"** (review 2026-10-11, #16): "Il Principe" and "De Profundis" are searched as
  titled. Dutch "De Kleine Johannes" is the price (LibriVox drops that one).
- **At most 8 searches per source run at once** (`MAX_IN_FLIGHT`, review 2026-10-10, #6). A timed-out search keeps
  its place until its thread finishes. A source with no free place is not asked: it is listed in
  `unavailable_sources` for that search only and is not marked down. So a stuck source holds at most 8 threads.
- **Only the source's fault is an outage** (review 2026-10-10, #1). A `4xx` answer raises `SourceRejected`
  (a `SourceError` subclass), and an exception that is not a `SourceError` is a bug in our adapter. Both leave
  the source out of that search only (listed in `unavailable_sources`) without `record_failure`.
  `test_hostile_inputs.py` sends odd input (`(anon)`, punctuation, maximum-length text, the last page) to every
  adapter: each must return a list or raise `SourceError`.
- **Unknown book ids are refused locally** (review 2026-10-11, #19). Before downloading an EPUB that is not cached, the store asks the local Gutendex (`GET /books/<id>/`, 3 s) through `GutendexCatalog`: no such book, or no EPUB format, is a 404 without any request to gutenberg.org. If Gutendex is down or answers oddly the answer is unknown and the book is asked for at Gutenberg as before. A book already on disk is never looked up. Per-book download locks are a fixed set of 64 (`id % 64`) instead of one per id. A book newer than the last `updatecatalog` is a 404 until the catalog is updated.
- **Searches have their own thread limit** (review 2026-10-11, #24). `/search` is `async` and runs the search with `anyio.to_thread.run_sync` on a `CapacityLimiter` of `FBR_MAX_CONCURRENT_SEARCHES` (default 20). A search over the limit waits as a coroutine, without a thread, so `/health` and book files still answer when slow searches pile up (`TestSlowSearchesDoNotStarveTheRest`). A search that gets no slot within `FBR_SEARCH_ADMISSION_SECONDS` (default 3) answers 200 with no works and its sources skipped as `busy` (main review #3; `TestSearchAdmission`).
- **Source ids are case-sensitive on purpose** (user decision 2026-10-11): `sources=DOAB` is a 422 that lists the valid ids. Only the app's source chips set `sources`, and they send the lowercase ids. (`language`, by contrast, is normalized.)
- **A known-item author matches when every word of the wanted name is in the book's author** ("Mary Shelley" finds
  "Mary Wollstonecraft Shelley"; "Charles Dickens" finds "Charles Dickens Jr." on purpose, user decision 2026-10-11,
  so a search for the father also returns the son; "Charles Dickens Jr." does not find the father). A name with
  nothing left after cleaning ("(anon)") matches no book (review 2026-10-11, #21).
- **Search input is limited:** `q`, `title`, `author`, `keyword` and `isbn` at most 300 characters (`MAX_TEXT_LENGTH`),
  `page` at most 1000 (`MAX_PAGE`); beyond that the API answers 422. Open Library answered `500` to a 3,000-character
  `q` and to `page=10**9`.
- **`language` is normalized in `SearchQuery`:** `FR`, `fre`, `fra` and `French` become `fr`; an unknown language is a
  validation error (422). Adapters always see a 2-letter lowercase code.
- **`sources` must name at least one source** (review 2026-10-10, #7). A missing or blank `sources` means all sources;
  `sources=,` names none and is a validation error (422). Duplicates are dropped, keeping the first order
  (`doab,gutenberg,doab` → `["doab", "gutenberg"]`).
- **A Gutenberg book in several languages** (`["en", "fr"]`) is labelled with the requested language when it is one of
  them, otherwise with its first language.
- **A LibriVox author with no name left after normalization** (`(anon)`, `(1812-1870)`) makes no request.
- **Open Library answering `422`** means zero results, not an outage. (A short `q` no longer causes one, because
  the access filter is appended to it.)
- **Gutenberg books carry edition details** (added 2026-10-10): `release_date`, `last_updated` (ISO dates),
  `credits` (one credit per line) and `original_publication`, so several Gutenberg eBooks of one work can be told
  apart. Other sources leave them `null`. A missing or unreadable value is `null`, never an error. Gutendex computes
  them (see `gutendex/books/utils.py` and api_gutendex.documentation.md).
- **Gutenberg titles lose MARC subfield markers** (`"Black Beauty : $b The autobiography of a horse"` becomes
  `"Black Beauty: The autobiography of a horse"`), seen in live results 2026-10-10.
- **LibriVox titles are sent without a leading article** (`The`, `A`, `Les`, `L'`, `Die`, ...). LibriVox catalogs
  "Time Machine" and "Misérables - tome 1", so `title=^the time machine` finds nothing (checked live 2026-10-10).
- **A LibriVox "(version N ...)" suffix is not part of the title** (`title_key`), so repeat recordings merge
  with each other and with the text, and a known-item title search keeps them.
- **LibriVox never gets `title` and `author` together** (it answers HTTP 500). The title is sent and the
  results are filtered by author last name.
- **Open Library language filter:** `language=<MARC code>` (`fre`, not `fra`) filters works; `lang=<2-letter>`
  is sent too but only boosts editions. Because of the filter, results are labeled with the requested language.
- **Reading order for text:** html, then epub, then plain text. PDF for DOAB.
- **The web reader gets Gutenberg books from `/publications/gutenberg/<id>/`** (added 2026-10-10). The manifest
  declares the EPUB profile (`https://readium.org/webpub-manifest/profiles/epub`): without it flutter_readium on web
  uses its generic navigator, which ignores font size, colours and page view. Every `href` is relative to the zip
  root, so the files are served under the same prefix. The table of contents comes from the EPUB 3 `nav` (nested
  entries keep `children`), or from the NCX for EPUB 2; an EPUB 2 cover comes from `<meta name="cover">`.
- **Only files listed in the package's manifest are served**, by exact decoded path (`container.xml`, the OPF,
  `mimetype` and `..` paths are 404). Book files carry `Content-Security-Policy: sandbox` and `nosniff` so a book page
  opened directly cannot run scripts on the API's origin; Readium builds its own documents, so the reader is unaffected
  (checked in Chromium 2026-10-10). Because Readium's documents are on the app's origin, where that header does not
  reach, XHTML, HTML and SVG files are also served without anything that runs code (review 2026-10-11-main #15,
  `test_sanitize.py`): `<script>`, `<iframe>`, `<object>`, `<embed>`, `<base>`, `<meta http-equiv>` and the like,
  `on*` attributes, `srcdoc`, and `javascript:`/`vbscript:`/`data:` page links. Everything else is unchanged byte for
  byte (all 78 pages of 5 cached Gutenberg books came back unchanged).
- **Downloading:** `<gutenberg_url>/ebooks/<id>.epub3.images`, following at most 5 redirects, only on the same host.
  404 there is 404; any other failure is 502 (also a `Content-Length` that is not a number, #5), a timeout 504. Downloads over 200 MB, files that are not a usable EPUB
  and zip entries over 100 MB (package files, i.e. container, OPF, nav and NCX, over 5 MB) are refused with 502, checked before and while reading (against zip bombs). A book is
  downloaded once even when several requests arrive together, and a failed download is not cached. The cache is a
  directory of `<id>.epub` files; when it is over its limit, the least recently used books are deleted. Book ids are
  1 to 99,999,999 (422 otherwise). This endpoint does not use the outage rule; it only serves books already found.
- **`reading.publication` names that manifest** for a Gutenberg book with an `application/epub+zip` file and a
  numeric id: `/publications/gutenberg/<id>/manifest.json`, a path on this backend (the app joins it to its
  `BACKEND_URL`, so the backend need not know its public address). Every other book has `null`. `kind` and `url`
  are unchanged, so the current in-app reader keeps working.
- The Gutenberg ID found in a LibriVox `url_text_source` is stored as `identifiers["gutenberg"]` and Open Library
  cross references are stored the same way. Merging uses them (see "Gutenberg cross-references merge" above).

## Not covered by these tests (and why)

- **DOAB's REST API is not used.** `directory.doabooks.org/rest/search` rejects our IP. The DOAB tests use real
  OpenSearch and OAI-PMH captures from `samples/`.
- **Whether a PDF link really serves a PDF.** OAPEN-hosted PDFs are behind a bot check, and some `.pdf` links return
  a web page; that is for the app's reader to handle.
- Live network calls. All HTTP is mocked; run the curl examples in `api_*.documentation.md` to check the real APIs.
- Gutendex nightly refresh scheduling (`updatecatalog`), deployment, and load. (`updatecatalog`'s failure handling is
  tested in Gutendex: `UpdateCatalogTests` in `gutendex/books/tests.py`.)

- **Source answers are cached** (audit 2026-10-27, F1): `TestCache` in `test_search_service.py`. `cache_seconds` (`FBR_SEARCH_CACHE_SECONDS`, default 300 in `Settings`, 0 in the bare `SearchService`) keeps each source's good answer to a query; the key leaves out `sources`, errors are never kept, at most `cache_entries` are held, and callers get copies.
- **EPUB downloads are bounded** (audit 2026-10-27, F3): `TestDownloadLimits` in `test_publications.py`. `PublicationStore(max_parallel_downloads=4)` (a slot is given back when a download fails); `.part` files older than `STALE_PART_SECONDS` (1 h) are removed when a download finishes.
- **`/health` reports the index** (audit 2026-10-27, F5): `{"status": "ok", "hathitrust_index": bool}`, always 200 (`test_health_says_when_the_hathitrust_index_*` in `test_api.py`).
