# Gutendex API (Project Gutenberg)

Project Gutenberg has no search API of its own. We self-host [Gutendex](https://github.com/garethbjohnson/gutendex) (code in [gutendex/](gutendex/)), a Django app that imports Gutenberg's nightly catalog and serves it as JSON. Upstream docs: https://github.com/garethbjohnson/gutendex. A public instance exists at https://gutendex.com.

Gutendex serves **metadata only**. It does not store or serve book text. The `formats` field links to files on gutenberg.org.

Because Gutenberg has no search API, the app cannot query it directly. A server must hold the catalog and answer queries, so Gutendex has to be hosted wherever the backend runs.

## Running it locally

```bash
cd gutendex
source venv/bin/activate
python manage.py updatecatalog     # download the catalog (~121 MB) and load it into Postgres (30+ min the first time)
python manage.py runserver 8001    # dev server; the examples below use http://localhost:8001
```

Settings come from `gutendex/gutendex/.env` (Postgres connection, `ALLOWED_HOSTS`, etc.). Re-run `updatecatalog` to refresh; Gutenberg publishes a new catalog nightly. Disk use: about 2.1 GB of unpacked RDF files plus a database of a few hundred MB.

## General behavior

* **Trailing slash:** the real paths are `/books/` and `/books/<id>/`. The upstream readme writes `/books`, but without the slash the server answers `301`. Use the slash (or `curl -L`).
* **Read-only:** `GET`, `HEAD` and `OPTIONS` only. `POST` returns `403`.
* **Auth and rate limits:** none. Responses send `Access-Control-Allow-Origin: *`.
* **Pagination:** up to 32 books per page, with `next` and `previous` URLs built from the request host. Use `?page=N`. A page past the end returns `404` with `{"detail": "Invalid page."}`.
* **Default order:** most downloaded first (`sort=popular`).
* **Combining parameters:** different parameters are ANDed. Comma-separated values inside one parameter are ORed.

## Endpoint: list / search books

`GET /books/`

| Parameter | Value | Meaning |
|---|---|---|
| `search` | words separated by a space | Case-insensitive match on **author name and title**. All words must match. |
| `topic` | phrase | Case-insensitive match on bookshelves **or** subjects (closest thing to keyword search). |
| `languages` | comma-separated 2-letter codes | Books in any of the languages (e.g. `fr,fi`). |
| `mime_type` | MIME type prefix | Books with a format starting with the value (`text/html`, `audio`, `application/epub`). |
| `ids` | comma-separated Gutenberg IDs | Only those books. |
| `author_year_start`, `author_year_end` | integers (negative = BCE) | Books with an author alive in the range. |
| `copyright` | `true`, `false`, `null`, comma-combinable | Copyright status (`false` = US public domain). |
| `sort` | `popular` (default), `ascending`, `descending` | Download count, or Gutenberg ID ascending or descending. |
| `page` | integer | Page number. |

**Not supported:** searching by ISBN or any other identifier. Gutenberg records have no ISBNs, and `search=9780141439518` returns `count: 0`. Matching to other sources has to use title and author.

### Example: search by title and author

```bash
curl "http://localhost:8001/books/?search=dickens%20great"
```

Sample response (abridged: the summary is shortened). Captured against the full catalog on 2026-10-10.

```json
{
  "count": 2,
  "next": null,
  "previous": null,
  "results": [
    {
      "id": 1400,
      "title": "Great Expectations",
      "authors": [
        {
          "name": "Dickens, Charles",
          "birth_year": 1812,
          "death_year": 1870
        }
      ],
      "summaries": [
        "\"Great Expectations\" by Charles Dickens is a novel first published serially from 1860 to 1861. The story follows Pip, a young orphan living with his sister and her blacksmith husband on England's coas..."
      ],
      "editors": [],
      "translators": [],
      "subjects": [
        "Benefactors -- Fiction",
        "Bildungsromans",
        "England -- Fiction",
        "Ex-convicts -- Fiction",
        "Man-woman relationships -- Fiction",
        "Orphans -- Fiction",
        "Revenge -- Fiction",
        "Young men -- Fiction"
      ],
      "bookshelves": [
        "Best Books Ever Listings",
        "Category: British Literature",
        "Category: Classics of Literature",
        "Category: Novels"
      ],
      "languages": [
        "en"
      ],
      "copyright": false,
      "media_type": "Text",
      "formats": {
        "text/html": "https://www.gutenberg.org/ebooks/1400.html.images",
        "application/epub+zip": "https://www.gutenberg.org/ebooks/1400.epub3.images",
        "application/x-mobipocket-ebook": "https://www.gutenberg.org/ebooks/1400.kf8.images",
        "text/plain; charset=utf-8": "https://www.gutenberg.org/ebooks/1400.txt.utf-8",
        "text/plain; charset=us-ascii": "https://www.gutenberg.org/files/1400/1400-0.txt",
        "application/rdf+xml": "https://www.gutenberg.org/ebooks/1400.rdf",
        "image/jpeg": "https://www.gutenberg.org/cache/epub/1400/pg1400.cover.medium.jpg",
        "application/octet-stream": "https://www.gutenberg.org/cache/epub/1400/pg1400-h.zip"
      },
      "download_count": 38268
    }
  ]
}
```

### Other example calls

```bash
# Books in French that have an HTML version
curl "http://localhost:8001/books/?languages=fr&mime_type=text%2Fhtml"

# Public-domain books by authors alive in the 19th century, oldest ID first
curl "http://localhost:8001/books/?author_year_start=1800&author_year_end=1899&copyright=false&sort=ascending"

# Children's literature
curl "http://localhost:8001/books/?topic=children"

# Specific IDs
curl "http://localhost:8001/books/?ids=11,12,13"

# Audio (media_type "Sound")
curl "http://localhost:8001/books/?mime_type=audio"
```

## Endpoint: single book

`GET /books/<id>/` where `<id>` is the Project Gutenberg ID.

```bash
curl "http://localhost:8001/books/11/"
```

Sample response (real, unabridged):

```json
{
  "id": 11,
  "title": "Alice's Adventures in Wonderland",
  "authors": [
    {
      "name": "Carroll, Lewis",
      "birth_year": 1832,
      "death_year": 1898
    }
  ],
  "summaries": [
    "\"Alice's Adventures in Wonderland\" by Lewis Carroll is a children's novel published in 1865. When a curious girl named Alice spots a White Rabbit with a pocket watch, she tumbles down a rabbit hole into an extraordinary fantasy world filled with peculiar anthropomorphic creatures. This pioneering work of literary nonsense plays with logic and language, creating a whimsical tale that delights both children and adults. Illustrated by John Tenniel, it helped transform children's literature from didactic instruction to pure entertainment. (This is an automatically generated summary.)"
  ],
  "editors": [],
  "translators": [],
  "subjects": [
    "Alice (Fictitious character from Carroll) -- Juvenile fiction",
    "Children's stories",
    "Fantasy fiction",
    "Imaginary places -- Juvenile fiction"
  ],
  "bookshelves": [
    "Category: British Literature",
    "Category: Children & Young Adult Reading",
    "Category: Classics of Literature",
    "Category: Novels",
    "Children's Literature"
  ],
  "languages": [
    "en"
  ],
  "copyright": false,
  "media_type": "Text",
  "formats": {
    "text/html": "https://www.gutenberg.org/ebooks/11.html.images",
    "application/epub+zip": "https://www.gutenberg.org/ebooks/11.epub3.images",
    "application/x-mobipocket-ebook": "https://www.gutenberg.org/ebooks/11.kf8.images",
    "text/plain; charset=utf-8": "https://www.gutenberg.org/ebooks/11.txt.utf-8",
    "text/plain; charset=us-ascii": "https://www.gutenberg.org/files/11/11-0.txt",
    "application/rdf+xml": "https://www.gutenberg.org/ebooks/11.rdf",
    "image/jpeg": "https://www.gutenberg.org/cache/epub/11/pg11.cover.medium.jpg",
    "application/octet-stream": "https://www.gutenberg.org/cache/epub/11/pg11-h.zip"
  },
  "download_count": 121623
}
```

### Errors

Both return HTTP `404`.

```bash
curl "http://localhost:8001/books/99999999/"
```
```json
{"detail": "No Book matches the given query."}
```

```bash
curl "http://localhost:8001/books/?search=x&page=999"
```
```json
{"detail": "Invalid page."}
```

## Book object

| Field | Type | Notes |
|---|---|---|
| `id` | number | Project Gutenberg ID. |
| `title` | string | |
| `authors`, `editors`, `translators` | array of Person | Person = `{name, birth_year, death_year}`. Names are "Last, First". Years may be `null`. |
| `summaries` | array of strings | Often auto-generated (the text says so). |
| `subjects`, `bookshelves` | array of strings | |
| `languages` | array of strings | 2-letter codes. |
| `copyright` | boolean or null | |
| `media_type` | string | `Text` or `Sound` seen so far. |
| `formats` | object | MIME type to URL on gutenberg.org. |
| `download_count` | number | Used for the default ordering. |

## Notes for the Free Book Reader

Mapping onto the data model in [spec.md](spec.md):

* **Work and book fields:** `title`, `authors[0].name`, `languages[0]`, `id` (source ID), and the Gutenberg page URL `https://www.gutenberg.org/ebooks/<id>`.
* **Titles carry MARC subfield markers** in some records: "Black Beauty : $b The autobiography of a horse", "Greasy luck : $b A whaling sketch book". The backend removes them ("Black Beauty: The autobiography of a horse").
* **Cover image:** the `image/jpeg` entry in `formats` (not checked for every book).
* **In-app reading:** the `text/html` and `application/epub+zip` URLs are the candidates for the viewer, with `text/plain` as the fallback. gutenberg.org sends **no CORS headers** (checked 2026-10-10), so a web app cannot fetch them directly. For the web reader the backend downloads the EPUB and serves it (see "Book files (EPUB)" below).
* **Number of pages and audio length:** not provided.
* **Filters:** language maps to `languages`. Format (text/audio) maps to `mime_type` or `media_type`.
* **Merging:** Gutenberg has no ISBN or OCLC number, so it only takes part in the exact and fuzzy title+author passes. Author names need normalizing from "Last, First".
* **Outage rule:** the backend, not the app, should call Gutendex and apply the 24-hour source-outage rule.

## Book files (EPUB)

Gutendex holds metadata only. The book files are on gutenberg.org. The backend's `/publications/gutenberg/<id>/...` endpoint (`backend/app/publications.py`) downloads the EPUB 3 with images and serves it to the web reader as a Readium Web Publication.

```bash
curl -sI https://www.gutenberg.org/ebooks/11.epub3.images
# HTTP/2 302
# location: https://www.gutenberg.org/cache/epub/11/pg11-images-3.epub
curl -sIL https://www.gutenberg.org/ebooks/11.epub3.images
# HTTP/2 200
# content-type: application/epub+zip
# content-length: 189249
# last-modified: Thu, 01 Oct 2026 07:31:59 GMT
# (no Access-Control-Allow-Origin header)
```

* `https://www.gutenberg.org/ebooks/<id>.epub3.images` redirects (302) to `https://www.gutenberg.org/cache/epub/<id>/pg<id>-images-3.epub` on the same host.
* Sizes vary a lot: book 11 (Alice) is 189 KB; book 1342 (Pride and Prejudice, illustrated) is 24.8 MB.
* Gutenberg's EPUBs keep the package document in `OEBPS/content.opf` with an EPUB 3 `nav.xhtml` and an EPUB 2 `toc.ncx`. File names are generated (`OEBPS/4040227324556390537_11-h-0.htm.xhtml`).
* `robots.txt` (2026-10-10) disallows only `/ebooks/search`. The backend downloads a book only when a reader opens it and then keeps it in its cache, so each book is fetched once. Project Gutenberg's robot policy asks automated tools to use a mirror; `FBR_GUTENBERG_URL` can point at one.

Our endpoint's answer for book 11 (lists shortened):

```bash
curl -s http://localhost:8000/publications/gutenberg/11/manifest.json
```

```json
{
  "@context": "https://readium.org/webpub-manifest/context.jsonld",
  "metadata": {
    "@type": "http://schema.org/Book",
    "conformsTo": "https://readium.org/webpub-manifest/profiles/epub",
    "title": "Alice's Adventures in Wonderland",
    "author": ["Lewis Carroll"],
    "language": ["en"],
    "identifier": "http://www.gutenberg.org/11"
  },
  "links": [],
  "readingOrder": [
    {"href": "OEBPS/wrap0000.xhtml", "type": "application/xhtml+xml"},
    {"href": "OEBPS/4040227324556390537_11-h-0.htm.xhtml", "type": "application/xhtml+xml"}
  ],
  "resources": [
    {"href": "OEBPS/7981341119032183217_cover.jpg", "type": "image/jpeg", "rel": "cover"},
    {"href": "OEBPS/pgepub.css", "type": "text/css"}
  ],
  "toc": [
    {"href": "OEBPS/4040227324556390537_11-h-0.htm.xhtml#pgepubid00000", "title": "Alice\u2019s Adventures in Wonderland"},
    {"href": "OEBPS/4040227324556390537_11-h-0.htm.xhtml#pgepubid00001", "title": "THE MILLENNIUM FULCRUM EDITION 3.0"}
  ]
}
```

`curl http://localhost:8000/publications/gutenberg/11/OEBPS/pgepub.css` then returns that file.

