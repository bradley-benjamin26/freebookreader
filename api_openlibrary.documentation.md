# Open Library API

Open Library is the Internet Archive's book catalog. Some of its books can be read online for free (public domain), and others can be borrowed with a free archive.org account (controlled digital lending). Official docs: https://openlibrary.org/developers/api. Search: https://openlibrary.org/dev/docs/api/search. Read API: https://openlibrary.org/dev/docs/api/read. Covers: https://openlibrary.org/dev/docs/api/covers. Python client (not used by us): https://github.com/internetarchive/openlibrary-client.

Base URL: `https://openlibrary.org`.

We use five parts of it: **search** (`/search.json`), **live loan status** (`/availability/v2`), **work and edition records** (`/works/...`, `/isbn/...`), **lending availability** (`/api/volumes/brief/...`), and **covers** (`covers.openlibrary.org`).

## General behavior

* **Auth:** none for reading.
* **Rate limits:** 1 request/second without identification, 3 requests/second when the `User-Agent` names the app and a contact, e.g. `User-Agent: FreeBookReader (contact@example.org)`. The backend should always send one.
* **Usage policy:** the APIs are "not intended to serve as a data backend for third-party services". They ask for requests made on behalf of a person, for caching, for no bulk harvesting (there are monthly data dumps instead), and for `search.json` instead of many single-book calls. Breaking the policy can lead to blocking. Our use (live searches for one person at a time) fits the policy. Registering the use case is optional, through a form on the developers page.
* **CORS:** the record APIs send `Access-Control-Allow-Origin: *`. This does not matter for us, because the backend makes the calls.
* **Schema:** the search docs say the schema "is not guaranteed to be stable". `key`, `title` and the IA fields are described as safe to rely on.

## Endpoint: search

`GET /search.json`

Results are **works** (a work groups all its editions), not editions.

| Parameter | Value | Meaning |
|---|---|---|
| `q` | Solr query | General search. **At least 3 characters**, or HTTP `422`. Accepts field syntax such as `language:spa`. |
| `title` | string | Title search (works; shown in the docs' examples but not in the parameter list). |
| `author` | string | Author search (same). |
| `isbn` | ISBN-10 or ISBN-13 | Works with an edition that has this ISBN (works; not in the docs' parameter list). |
| `lang` | 2-letter ISO 639-1 code | **Boosts** editions in that language. It does **not** remove other works. |
| `language` | 3-letter MARC code (`spa`, `fre`, `ger`) | **Filters** to works with an edition in that language. Not in the docs; tested 2026-10-10 (with `title=don quixote`: 155 results, all with `spa`, versus 4 of the first 50 without it). Works with `q` or with `title`/`author`. |
| `fields` | comma-separated | Fields to return. Always set it: the default response is very large (see [samples/README.md](samples/README.md)). `*` returns all. Adding `availability` adds archive.org availability for the first `ia` item. |
| `sort` | `new`, `old`, `random`, `key`, ... | Default is relevance. |
| `page` + `limit` | integers | Page-based paging (`page` starts at 1). |
| `offset` + `limit` | integers | Offset-based paging. |

| `q=... ebook_access:[borrowable TO *]` | Solr range | **Only free or borrowable works.** `ebook_access` is ordered `no_ebook` < `printdisabled` < `borrowable` < `public`. Works alone as `q` next to `title`/`author`/`isbn`, and with `language`. It also filters the `editions` sub-query (below). Tested 2026-10-10. |
| `fields=editions,editions.key,editions.ebook_access` | | Adds `editions.docs`: the **one edition** of the work that best matches the query, including its filters (an `ebook_access` filter, `language`, `isbn`). Other edition fields work the same way (`editions.title`, `editions.language`, `editions.ia`). |

Tested on 2026-10-10: `title` + `author` together are ANDed (`q` is then `""` in the response); `isbn=0140430725` and `isbn=9780140430721` both return `/works/OL66554W`; a search with no matches returns `200` with `"docs": []`.

### Example: title and author search, only the fields we map

```bash
curl -A "FreeBookReader (contact@example.org)" \
  "https://openlibrary.org/search.json?title=pride+and+prejudice&author=austen&limit=1&fields=key,title,author_name,cover_i,ebook_access,isbn,language,number_of_pages_median,id_project_gutenberg,id_librivox"
```

Real response, captured 2026-10-10. Abridged: `isbn` (6,117 values) and `language` (27 values) are cut short.

```json
{
  "numFound": 276,
  "start": 0,
  "numFoundExact": true,
  "num_found": 276,
  "documentation_url": "https://openlibrary.org/dev/docs/api/search",
  "q": "",
  "offset": null,
  "docs": [
    {
      "author_name": ["Jane Austen"],
      "cover_i": 14348537,
      "ebook_access": "public",
      "isbn": ["3849552691", "1484110986", "1296850145", "..."],
      "key": "/works/OL66554W",
      "language": ["por", "cze", "kor", "fre", "..."],
      "number_of_pages_median": 351,
      "title": "Pride and Prejudice",
      "id_project_gutenberg": ["1342", "42671", "45186"],
      "id_librivox": ["253", "orgullo-y-prejuicio-vol-2-by-jane-austen", "5349", "969", "4023", "254", "1480"]
    }
  ]
}
```

Unabridged captures: [samples/openlibrary-search.json](samples/openlibrary-search.json) (`q=pride+and+prejudice&limit=3`, no `fields`) and [samples/openlibrary-search-title-author.json](samples/openlibrary-search-title-author.json).

### Example: only books that can be read or borrowed, with the edition to link

Without the filter, `/works/OL497167W` ("Dean Koontz's Frankenstein") is `borrowable` and its `lending_edition_s` is `OL32667096M`, a Polish translation. Its `editions` sub-query returns `OL3311782M`, a hardcover with no ebook, and the work page on openlibrary.org also features an edition that cannot be borrowed. With the filter, the sub-query returns `OL23273427M` ("Book One"), which can be borrowed.

```bash
curl -G -A "FreeBookReader (contact@example.org)" "https://openlibrary.org/search.json" \
  --data-urlencode "q=dean koontz frankenstein ebook_access:[borrowable TO *]" \
  --data-urlencode "fields=key,title,author_name,ebook_access,editions,editions.key,editions.ebook_access" \
  --data-urlencode "limit=3"
```

Real response, captured 2026-10-10 (first doc only; full capture with all our fields: [samples/openlibrary-search-borrowable.json](samples/openlibrary-search-borrowable.json)):

```json
{
  "numFound": 6,
  "start": 0,
  "docs": [
    {
      "key": "/works/OL497167W",
      "title": "Dean Koontz's Frankenstein",
      "author_name": [
        "Dean Koontz",
        "Kevin J. Anderson"
      ],
      "ebook_access": "borrowable",
      "editions": {
        "numFound": 2,
        "start": 0,
        "numFoundExact": true,
        "docs": [
          {
            "ebook_access": "borrowable",
            "key": "/books/OL23273427M"
          }
        ]
      }
    }
  ]
}
```

Without the filter the same query finds 19 works, including print-disabled-only ones such as `/works/OL15443537W`. With the filter it finds 6.

### Other example calls

```bash
# Free text
curl "https://openlibrary.org/search.json?q=whaling&limit=20&fields=key,title,author_name"

# By ISBN
curl "https://openlibrary.org/search.json?isbn=9780140430721&fields=key,title"

# Only works with a Spanish edition (a filter, unlike lang=es)
curl "https://openlibrary.org/search.json?title=don+quixote&language=spa&lang=es&fields=key,title"

# The same filter inside q
curl "https://openlibrary.org/search.json?q=don+quixote+language:spa&fields=key,title"

# Second page of 20
curl "https://openlibrary.org/search.json?q=whaling&limit=20&page=2&fields=key,title"
```

### Errors

```bash
curl "https://openlibrary.org/search.json?q=x"
```
HTTP `422`:
```json
{"detail":[{"type":"value_error","loc":["query","q"],"msg":"Value error, Query too short, must be at least 3 characters","input":"x","ctx":{"error":{}}}]}
```

### Search doc fields we use

| Field | Type | Notes |
|---|---|---|
| `key` | string | `/works/OL…W`. The work ID is the last part. |
| `title` | string | |
| `author_name` | array of strings | "First Last". May be missing. |
| `language` | array of strings | **3-letter MARC codes** (`eng`, `fre`, `ger`), one per language that any edition is in. Popular works list dozens. |
| `ebook_access` | string | `public` (free to read), `borrowable` (loan with an account), `printdisabled` (only for people with a print disability), `no_ebook`. May be missing. |
| `isbn` | array of strings | ISBN-10s and ISBN-13s of every edition, with duplicates and some invalid values. |
| `cover_i` | number | Cover ID for the Covers API. May be missing. |
| `number_of_pages_median` | number | Median across editions. |
| `id_project_gutenberg` | array of strings | Gutenberg IDs. |
| `id_librivox` | array of strings | LibriVox project IDs, mixed with some LibriVox URL slugs. |
| `editions` | object | With `editions.key` and `editions.ebook_access` in `fields`: `{"numFound", "start", "numFoundExact", "docs": [one edition]}`. The edition we link. |
| `has_fulltext`, `public_scan_b`, `ia`, `lending_edition_s`, `edition_count`, `first_publish_year`, `author_key` | | Also available; we do not map them. |

## Endpoint: live loan status

`GET /availability/v2?type=<type>&ids=<id>,<id>,...`

**Not in the developer docs.** openlibrary.org's own pages use it (the source is `core.models.lending.get_availability`). `type` is `openlibrary_edition` (`OL…M`), `openlibrary_work` (`OL…W`, answers for one edition the server picks, which can be a translation) or `identifier` (archive.org item ID). Several IDs go in one call. The answer is an object keyed by the IDs asked for; with no IDs it is `[]`. archive.org's own `/services/availability` answers "Current user does not have access to scope" to us.

```bash
curl -A "FreeBookReader (contact@example.org)" \
  "https://openlibrary.org/availability/v2?type=openlibrary_edition&ids=OL23273427M,OL25968798M,OL22173091M,OL50444320M,OL3311782M"
```

Real response, captured 2026-10-10. Abridged: 2 of 5 records are shown. Full capture: [samples/openlibrary-availability-v2.json](samples/openlibrary-availability-v2.json).

```json
{
  "OL23273427M": {
    "status": "borrow_available",
    "available_to_browse": true,
    "available_to_borrow": true,
    "available_to_waitlist": false,
    "is_printdisabled": true,
    "is_readable": false,
    "is_lendable": true,
    "is_previewable": true,
    "is_restricted": true,
    "is_browseable": true,
    "identifier": "deankoontzsfrank0000koon_k0s4",
    "isbn": "0553587889",
    "oclc": null,
    "openlibrary_work": "OL497167W",
    "openlibrary_edition": "OL23273427M",
    "last_loan_date": null,
    "num_waitlist": null,
    "last_waitlist_date": null,
    "__src__": "core.models.lending.get_availability"
  },
  "OL3311782M": {
    "status": "error",
    "available_to_browse": null,
    "available_to_borrow": null,
    "available_to_waitlist": null,
    "is_printdisabled": null,
    "is_readable": null,
    "is_lendable": null,
    "is_previewable": false,
    "is_restricted": true,
    "is_browseable": false,
    "identifier": null,
    "isbn": null,
    "oclc": null,
    "openlibrary_work": null,
    "openlibrary_edition": null,
    "last_loan_date": null,
    "num_waitlist": null,
    "last_waitlist_date": null,
    "error_message": "not found",
    "__src__": "core.models.lending.get_availability"
  }
}
```

* `status`: `open` (free to read), `borrow_available` (can be borrowed now), `borrow_unavailable` (every copy is on loan; join the waitlist), `private`, or `error` (with `error_message`, e.g. `"not found"` for an edition with no scan). In OL's code these are the only values. No `borrow_unavailable` turned up in about 60 borrowable editions of popular books checked on 2026-10-10.
* `available_to_borrow: false` with `available_to_browse: true` and status `borrow_available` is normal. It means the book can be borrowed for 1 hour (browse) but not for the 14-day loan. It is still borrowable.
* We send the editions from one page of search results (20 at most) in one call.

## Endpoint: work record

`GET /works/<OLID>.json`

```bash
curl "https://openlibrary.org/works/OL66554W.json"
```

Real response: [samples/openlibrary-work.json](samples/openlibrary-work.json). Top-level keys: `authors`, `covers`, `created`, `description`, `excerpts`, `first_publish_date`, `genres`, `key`, `last_modified`, `latest_revision`, `links`, `revision`, `subject_people`, `subject_places`, `subject_times`, `subjects`, `title`, `type`, `works`. Authors are references (`{"author": {"key": "/authors/OL21594A"}}`), not names. `description` is either a string or `{"type": "/type/text", "value": "..."}`.

Not found, HTTP `404`:
```json
{"error": "notfound", "key": "/works/OL0W"}
```

## Endpoint: edition by ISBN

`GET /isbn/<isbn>.json` answers `302` with a redirect to `/books/<edition OLID>.json`, so use `curl -L`.

```bash
curl -L "https://openlibrary.org/isbn/9780140430721.json"
```

Real response (from [samples/openlibrary-isbn.json](samples/openlibrary-isbn.json)), abridged: the description, `source_records` and timestamps are removed.

```json
{
  "title": "Pride and Prejudice",
  "publish_date": "1998",
  "publishers": ["Penguin Books"],
  "type": {"key": "/type/edition"},
  "ocaid": "prideprejudice1972aust",
  "isbn_13": ["9780140430721"],
  "isbn_10": ["0140430725"],
  "edition_name": "Penguin Classics Reprint",
  "physical_format": "Paperback",
  "languages": [{"key": "/languages/eng"}],
  "series": ["Penguin Classics"],
  "key": "/books/OL37006384M",
  "number_of_pages": 399,
  "works": [{"key": "/works/OL66554W"}],
  "covers": [13057878],
  "oclc_numbers": ["18103615", "2656503"],
  "lccn": ["72186963"],
  "identifiers": {"goodreads": ["175254"]}
}
```

## Endpoint: lending availability (Read API)

`GET /api/volumes/brief/<id-type>/<id>.json`, where `<id-type>` is `isbn`, `oclc`, `lccn` or `olid`. Several lookups in one call: `/api/volumes/brief/json/isbn:...|oclc:...` (`|` separates requests, `;` separates IDs within one request).

The docs now call this the "Legacy Partner API (formerly the Read API)". It is still live.

```bash
curl "https://openlibrary.org/api/volumes/brief/isbn/9780140430721.json"
```

Real response (from [samples/openlibrary-availability.json](samples/openlibrary-availability.json)), abridged: the record's `data` and `details` are removed, and 2 of 198 items are shown (38 `full access`, 160 `lendable`).

```json
{
  "records": {
    "/books/OL37006384M": {
      "isbns": ["0140430725", "9780140430721"],
      "issns": [],
      "lccns": ["72186963"],
      "oclcs": ["18103615", "2656503"],
      "olids": ["OL37006384M"],
      "publishDates": ["1998"],
      "recordURL": "http://openlibrary.org/books/OL37006384M/Pride_and_Prejudice",
      "data": "…",
      "details": "…"
    }
  },
  "items": [
    {
      "enumcron": false,
      "match": "similar",
      "status": "full access",
      "fromRecord": "/books/OL37006384M",
      "ol-edition-id": "OL39221195M",
      "ol-work-id": "OL66554W",
      "publishDate": "1813",
      "contributor": "",
      "itemURL": "http://www.archive.org/stream/prideprejudice0000jane_h2f2",
      "cover": {
        "small": "https://covers.openlibrary.org/b/id/12856344-S.jpg",
        "medium": "https://covers.openlibrary.org/b/id/12856344-M.jpg",
        "large": "https://covers.openlibrary.org/b/id/12856344-L.jpg"
      }
    },
    {
      "enumcron": false,
      "match": "similar",
      "status": "lendable",
      "fromRecord": "/books/OL37006384M",
      "ol-edition-id": "OL48120788M",
      "ol-work-id": "OL66554W",
      "publishDate": "",
      "contributor": "",
      "itemURL": "http://openlibrary.org/books/OL48120788M/Pride_and_Prejudice/borrow",
      "cover": {
        "small": "https://covers.openlibrary.org/b/id/14617363-S.jpg",
        "medium": "https://covers.openlibrary.org/b/id/14617363-M.jpg",
        "large": "https://covers.openlibrary.org/b/id/14617363-L.jpg"
      }
    }
  ]
}
```

* `items` holds the readable or borrowable scans, sorted best first. It is empty when nothing can be read.
* `match`: `exact` = a scan of this edition; `similar` = another edition of the same work.
* `status`: `full access`, `lendable`, `checked out` or `restricted`. The docs list these without defining them. The plain reading: free to read, can be borrowed now, all copies on loan, print-disabled access only.
* An ISBN Open Library knows but cannot lend returns `200` with a record and `"items": []`. So does a made-up ISBN that happens to be in the catalog (`9780000000002` is). Results can vary by caller IP: libraries in the lending program see more borrowable items.

## Covers

`https://covers.openlibrary.org/b/<key>/<value>-<size>.jpg`, where `<key>` is `id` (the `cover_i` value), `olid`, `isbn`, `oclc` or `lccn`, and `<size>` is `S`, `M` or `L`.

```bash
curl -I "https://covers.openlibrary.org/b/id/14348537-M.jpg"   # 302 to the image on archive.org
```

* A missing cover returns a blank image. Add `?default=false` to get a `404` instead.
* Lookups by `isbn`, `oclc` or `lccn` are limited to 100 per IP per 5 minutes (`403` after that). Lookups by `id` and `olid` are not. Use `cover_i`.
* The app loads cover images directly from this URL; no JSON is involved.

## Notes for the Free Book Reader

Mapping onto the data model in [spec.md](spec.md):

* **Only books a user can read or borrow now** (user request 2026-10-10). Every search adds `ebook_access:[borrowable TO *]` to `q` (alone, when the search uses only `title`/`author`/`isbn`). Results whose edition is not `public` or `borrowable` are dropped. The edition IDs then go to `/availability/v2` in one call, and editions whose status is not `open` or `borrow_available` are dropped. That endpoint is undocumented, so if it fails (any error, including a timeout or 4xx) the results are kept as the search returned them, and the failure does not count as an outage. Trade-off: an ISBN search finds the work only if that ISBN's edition can be read or borrowed.
* **Book fields:** work ID from `key` (source ID), `title`, `author_name`, format `text`, URL `https://openlibrary.org/books/<edition id>` from `editions.docs[0].key` (`https://openlibrary.org/works/<id>` when there is none), cover `https://covers.openlibrary.org/b/id/<cover_i>-M.jpg`, pages from `number_of_pages_median`. No audio length.
* **Access:** the edition's `ebook_access` (the work's when the edition has none) maps to `public` → open, `borrowable` → borrow. Anything else is dropped (the app still knows print-disabled and none, which no longer occur). This covers the user story "a copyrighted book I can borrow from Open Library". Borrowing happens on openlibrary.org with the user's own account; the app links out.
* **Language:** a work lists every language of every edition, so a work with more than one language has an unknown language for merging. When the user picks a language, the backend sends `language=<MARC code>` (the filter) and `lang=<2-letter code>` (so the edition shown is in that language). The results can then be labeled with the requested language.
* **Identifiers:** `isbn` (convert to ISBN-13, drop duplicates and bad check digits) for the first merge pass. `id_project_gutenberg` and `id_librivox` link the work directly to Gutenberg and LibriVox records.
* **Search mapping:** free text and keyword use `q`; title and author use `title` and `author`; ISBN uses `isbn`. A `q` shorter than 3 characters answers HTTP `422`; with the access filter appended, `q` is never that short. Audio-only searches skip Open Library.
* **Availability:** the brief Read API gives the read or borrow link for a specific ISBN. `full access` wins over `lendable`.
* **Offline:** Open Library books open at the source and cannot be saved (spec).
* **Outage rule:** `5xx` and non-JSON bodies count as an outage. A timeout leaves Open Library out of that search only. `422` is our bug, not an outage. Send the `User-Agent` to get the higher rate limit.
