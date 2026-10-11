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
`FBR_DOAB_URL`, `FBR_SEARCH_TIMEOUT_SECONDS`, `FBR_OUTAGE_COOLDOWN_HOURS`, `FBR_CORS_ORIGINS` (comma-separated,
default `*`) and `FBR_CONTACT`. The `User-Agent` is built from the project's top-level `.env` (JSON:
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
| System that provides Project Gutenberg access is built and tested | `gutendex/books/tests.py`, `test_source_gutendex.py` |
| Records merged into works by the Data Merging rules | `test_merge.py`, `test_normalize.py` |
| Search across / select targets, filters, known-item search | `test_search_service.py` |
| Source outage: stop returning results for 24 h | `test_outage.py`, `TestOutages` in `test_search_service.py` |
| Search results within 15 s | `TestTimeout`, `test_default_timeout_is_15_seconds`, `test_sources_are_queried_in_parallel` |
| Viewer displays in-app sources, others link out | `test_reader.py` |
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
  merge.py         merge_books(list[Book]) -> list[Work]
  outage.py        OutageTracker(clock, cooldown=24h): record_failure, is_available, unavailable, retry_at
  search.py        SearchService(sources, outage, timeout_seconds=15, max_in_flight=4): search(SearchQuery) -> SearchResponse
  reader.py        reading_options(Book) -> ReadingOptions(mode, kind, url)
  sources_info.py  SOURCES, get_source_info(id)
  config.py        Settings.from_env, build_search_service(settings, client)
  main.py          create_app(search_service) -> FastAPI:  GET /health, /search, /sources
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
- **Chapters are not books** (DOAB also lists chapters); deleted OAI records are skipped.
- **DOAB search is OpenSearch, then one OAI `GetRecord` (xoai) per hit**, because DOAB's REST API rejects our IP.
  Stale search entries (`Untitled`, or `idDoesNotExist`) are skipped. If a lookup fails, the hit is kept with what
  the search said. A download link ending in `.pdf` (usually in the OAPEN Library) is the book's PDF; any other
  link is left to the DOAB record page. DOAB's `open-access-no-cover.png` placeholder is not a cover.
- **Invalid ISBNs are dropped.** OAPEN/DOAB data contained one with a bad check digit.
- **Open Library always links out** (its `ebook_access` is recorded as `open`, `borrow`,
  `print_disabled` or `none` so the UI can say how to get the book).
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
- **A timeout is not an outage.** A source that misses the 15 s deadline, or whose HTTP request times out
  (`SourceTimeout`), is listed in `unavailable_sources` for that search only and is asked again next time.
  Errors (refused connections, `5xx`, unusable bodies) still start the 24-hour outage.
- **At most 4 searches per source run at once** (`MAX_IN_FLIGHT`, review 2026-10-10, #6). A timed-out search keeps
  its place until its thread finishes. A source with no free place is not asked: it is listed in
  `unavailable_sources` for that search only and is not marked down. So a stuck source holds at most 4 threads.
- **Only the source's fault is an outage** (review 2026-10-10, #1). A `4xx` answer raises `SourceRejected`
  (a `SourceError` subclass), and an exception that is not a `SourceError` is a bug in our adapter. Both leave
  the source out of that search only (listed in `unavailable_sources`) without `record_failure`.
  `test_hostile_inputs.py` sends odd input (`(anon)`, punctuation, maximum-length text, the last page) to every
  adapter: each must return a list or raise `SourceError`.
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
- **Open Library answering `422`** (for example a `q` shorter than 3 characters) means zero results, not an outage.
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
- The Gutenberg ID found in a LibriVox `url_text_source` is stored as `identifiers["gutenberg"]` and Open Library
  cross references are stored the same way. Nothing uses them yet.

## Not covered by these tests (and why)

- **DOAB's REST API is not used.** `directory.doabooks.org/rest/search` rejects our IP. The DOAB tests use real
  OpenSearch and OAI-PMH captures from `samples/`.
- **Whether a PDF link really serves a PDF.** OAPEN-hosted PDFs are behind a bot check, and some `.pdf` links return
  a web page; that is for the app's reader to handle.
- Live network calls. All HTTP is mocked; run the curl examples in `api_*.documentation.md` to check the real APIs.
- Gutendex nightly refresh scheduling (`updatecatalog`), deployment, and load.
