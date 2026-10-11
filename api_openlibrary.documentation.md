# Open Library API

Open Library is the Internet Archive's book catalog. Some of its books can be read online for free (public domain), and others can be borrowed with a free archive.org account (controlled digital lending). Official docs: https://openlibrary.org/developers/api. Search: https://openlibrary.org/dev/docs/api/search. Read API: https://openlibrary.org/dev/docs/api/read. Covers: https://openlibrary.org/dev/docs/api/covers. Python client (not used by us): https://github.com/internetarchive/openlibrary-client.

Base URL: `https://openlibrary.org`.

We use four parts of it: **search** (`/search.json`), **work and edition records** (`/works/...`, `/isbn/...`), **lending availability** (`/api/volumes/brief/...`), and **covers** (`covers.openlibrary.org`).

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
| `has_fulltext`, `public_scan_b`, `ia`, `lending_edition_s`, `edition_count`, `first_publish_year`, `author_key` | | Also available; we do not map them. |

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

* **Book fields:** work ID from `key` (source ID), `title`, `author_name`, format `text`, URL `https://openlibrary.org/works/<id>`, cover `https://covers.openlibrary.org/b/id/<cover_i>-M.jpg`, pages from `number_of_pages_median`. No audio length.
* **Access:** `ebook_access` maps to `public` → open, `borrowable` → borrow, `printdisabled` → print-disabled, anything else or missing → none. This covers the user story "a copyrighted book I can borrow from Open Library". Borrowing happens on openlibrary.org with the user's own account; the app links out.
* **Language:** a work lists every language of every edition, so a work with more than one language has an unknown language for merging. When the user picks a language, the backend sends `language=<MARC code>` (the filter) and `lang=<2-letter code>` (so the edition shown is in that language). The results can then be labeled with the requested language.
* **Identifiers:** `isbn` (convert to ISBN-13, drop duplicates and bad check digits) for the first merge pass. `id_project_gutenberg` and `id_librivox` link the work directly to Gutenberg and LibriVox records.
* **Search mapping:** free text and keyword use `q`; title and author use `title` and `author`; ISBN uses `isbn`. A `q` shorter than 3 characters must not be sent (HTTP `422`). Audio-only searches skip Open Library.
* **Availability:** the brief Read API gives the read or borrow link for a specific ISBN. `full access` wins over `lendable`.
* **Offline:** Open Library books open at the source and cannot be saved (spec).
* **Outage rule:** `5xx` and non-JSON bodies count as an outage. A timeout leaves Open Library out of that search only. `422` is our bug, not an outage. Send the `User-Agent` to get the higher rate limit.
