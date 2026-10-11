# LibriVox API

LibriVox publishes public-domain audiobooks read by volunteers. The audio files are hosted on archive.org. Official docs: https://librivox.org/api/info. Base URL: `https://librivox.org/api/feed/`.

The API serves **metadata and links to MP3 files**. Every recording is in the public domain, so everything is open access.

## General behavior

* **Auth:** none.
* **Rate limits:** none today. The docs say limits may be added later, and that clients making frequent requests would then get HTTP `429`. They ask for a delay between paged requests.
* **Output format:** XML by default. Always send `format=json`. Other values are `jsonp`, `serialized` and `php_array`.
* **Parameter syntax:** query string (`?title=x`) or path segments (`/title/x`). Both work. These examples use the query string.
* **Pagination:** `limit` (default 50, maximum 500) and `offset`. There is no total count in the response. A page past the end returns the not-found error below.
* **Order:** by project `id`, ascending (`sort_order=asc`, the default) or descending (`sort_order=desc`). There is no relevance ranking.
* **Not found:** HTTP `404` with `{"error": "Audiobooks could not be found"}`. Treat this as zero results, not as an outage.

## Endpoint: audiobooks (search)

`GET /api/feed/audiobooks`

| Parameter | Value | Meaning |
|---|---|---|
| `id` | project ID | A single audiobook. |
| `title` | string | **Exact** full-title match, case-insensitive. With a leading `^`, a prefix match (see below). |
| `author` | string | **Exact last-name match**, case-insensitive. A first name or full name finds nothing. |
| `genre` | string | Genre name, e.g. `^romance`. |
| `since` | UNIX timestamp | Projects cataloged after that time. |
| `extended` | `1` | Adds `url_iarchive`, `sections`, `genres`, `translators`. |
| `coverart` | `1` | Adds `coverart_jpg`, `coverart_pdf`, `coverart_thumbnail`. |
| `fields` | `{id,title,...}` | Only these fields. Groups (`authors`, `sections`, ...) can be selected, but not fields inside them. |
| `format` | `json` | Output format (default XML). |
| `limit`, `offset` | integers | Paging. `limit` > 500 returns HTTP `400`. |
| `sort_order` | `asc`, `desc` | By project ID. |

### How matching really works (tested 2026-10-10)

The docs say only that `^` anchors a search "to the beginning". The live behavior is more limited than that:

| Request | Result |
|---|---|
| `title=pride and prejudice` | 2 books with exactly that title. |
| `title=pride` | Not found. There is **no word or substring search**. |
| `title=^pride` | Prefix match: "Pride and Prejudice", "Pride and Prejudice (version 2)", ... |
| `title=^prejudice` | "Prejudices, First Series", ... (the prefix is the start of the title). |
| `author=dickens`, `author=Dickens` | 189 books (exact last name, case-insensitive). |
| `author=Charles Dickens` | Not found. |
| `author=^ickens` | Dickens **and** Pickens. With `author`, `^` behaves like an "ends with" match. |
| `title=...&author=...` | **HTTP 500, empty body.** Send one of the two, never both. |
| `language=French` | Ignored. There is no language filter. |

What this means for us: a free-text query cannot be sent to LibriVox as-is. The best available request is `title=^<query>`, a prefix match on the title. Language, and the second of title/author, have to be filtered after the response comes back.

### Example: search by title (extended, with cover art)

```bash
curl "https://librivox.org/api/feed/audiobooks?title=pride%20and%20prejudice&format=json&extended=1&coverart=1&limit=3"
```

Sample response (real, from `samples/librivox-title-search.json`, captured 2026-10-10). Abridged: one of two books shown, the description shortened, and 2 of 37 sections.

```json
{
  "books": [
    {
      "id": "253",
      "title": "Pride and Prejudice",
      "description": "<em>Pride and Prejudice</em> is the most famous of Jane Austen’s novels, ... (Summary from Wikipedia)",
      "url_text_source": "https://www.gutenberg.org/etext/1342",
      "language": "English",
      "copyright_year": "1813",
      "num_sections": "37",
      "url_rss": "https://librivox.org/rss/253",
      "url_zip_file": "https://archive.org/compress/pride_and_prejudice_librivox/formats=64KBPS MP3&file=/pride_and_prejudice_librivox.zip",
      "url_project": "https://en.wikipedia.org/wiki/Pride_and_Prejudice",
      "url_librivox": "https://librivox.org/pride-and-prejudice-by-jane-austen/",
      "url_other": "",
      "totaltime": "13:06:44",
      "totaltimesecs": 47204,
      "authors": [
        {"id": "155", "first_name": "Jane", "last_name": "Austen", "dob": "1775", "dod": "1817"}
      ],
      "coverart_jpg": "https://archive.org/download/pride_and_prejudice_librivox/Pride_Prejudice_1104.jpg",
      "coverart_pdf": "https://archive.org/download/pride_and_prejudice_librivox/Pride_Prejudice_1104.pdf",
      "coverart_thumbnail": "https://archive.org/download/pride_and_prejudice_librivox/Pride_Prejudice_1104_thumb.jpg",
      "url_iarchive": "https://www.archive.org/details/pride_and_prejudice_librivox",
      "sections": [
        {
          "id": "124135",
          "section_number": "1",
          "title": "Chapters 1-3",
          "listen_url": "https://www.archive.org/download/pride_and_prejudice_librivox/prideandprejudice_01-03_austen_64kb.mp3",
          "language": "English",
          "playtime": "1132",
          "file_name": null,
          "readers": [{"reader_id": "168", "display_name": "Chris Goringe"}]
        },
        {
          "id": "124136",
          "section_number": "2",
          "title": "Chapters 4-5",
          "listen_url": "https://www.archive.org/download/pride_and_prejudice_librivox/prideandprejudice_04-05_austen_64kb.mp3",
          "language": "English",
          "playtime": "865",
          "file_name": null,
          "readers": [{"reader_id": "19", "display_name": "Kara Shallenberg (1969-2023)"}]
        }
      ],
      "genres": [{"id": "27", "name": "Romance"}],
      "translators": []
    }
  ]
}
```

The second book in that response (`id` `22765`) has `"totaltimesecs": 0` and `"totaltime": ""`, even though it lists 61 sections. Treat `0` as "length unknown".

### Example: search by author

```bash
curl "https://librivox.org/api/feed/audiobooks?author=dickens&format=json&limit=2&fields=%7Bid,title%7D"
```

Real response (2026-10-10):

```json
{"books":[{"id":"53","title":"Bleak House"},{"id":"140","title":"Christmas Carol"}]}
```

### Other example calls

```bash
# Prefix match on the title
curl "https://librivox.org/api/feed/audiobooks?title=%5Egreat%20expect&format=json&limit=5"

# One project by ID
curl "https://librivox.org/api/feed/audiobooks?id=253&format=json&extended=1&coverart=1"

# Next page (results 51-100)
curl "https://librivox.org/api/feed/audiobooks?author=dickens&format=json&limit=50&offset=50"

# Newest projects first
curl "https://librivox.org/api/feed/audiobooks?sort_order=desc&format=json&limit=10"
```

### Errors

```bash
curl "https://librivox.org/api/feed/audiobooks?title=zzzzqqqxx&format=json"
```
HTTP `404`:
```json
{"error":"Audiobooks could not be found"}
```

```bash
curl "https://librivox.org/api/feed/audiobooks?format=json&limit=600"
```
HTTP `400`:
```json
{"error":"Too many records requested.  Please reduce your \"limit\" parameter.  See https:\/\/librivox.org\/api\/info for details."}
```

`title` and `author` together: HTTP `500` with an empty body.

## Endpoint: audiotracks

`GET /api/feed/audiotracks?project_id=<id>&format=json` returns the sections of one project. `id=<section id>` returns one section. These are the same objects as `sections` in an extended audiobook response, but without `readers`.

```bash
curl "https://librivox.org/api/feed/audiotracks?project_id=253&format=json"
```

Real response (2026-10-10), first 2 of 37 sections:

```json
{"sections":[
  {"id":"124135","section_number":"1","title":"Chapters 1-3","listen_url":"https://www.archive.org/download/pride_and_prejudice_librivox/prideandprejudice_01-03_austen_64kb.mp3","language":"English","playtime":"1132","file_name":null},
  {"id":"124136","section_number":"2","title":"Chapters 4-5","listen_url":"https://www.archive.org/download/pride_and_prejudice_librivox/prideandprejudice_04-05_austen_64kb.mp3","language":"English","playtime":"865","file_name":null}
]}
```

## Endpoint: authors

`GET /api/feed/authors?last_name=<name>&format=json` (exact last name) or `?id=<author id>`.

```bash
curl "https://librivox.org/api/feed/authors?last_name=Austen&format=json"
```

Real response (2026-10-10):

```json
{"authors":[{"id":"155","first_name":"Jane","last_name":"Austen","dob":"1775","dod":"1817"}]}
```

## Audiobook object

| Field | Type | Notes |
|---|---|---|
| `id` | string | Project ID (a number, sent as a string). |
| `title` | string | Later recordings of the same book are titled "... (version 2)" etc. |
| `description` | string | HTML. |
| `url_text_source` | string | Where the reader got the text. Often a Gutenberg URL (`/etext/<id>` or `/ebooks/<id>`). May be empty. |
| `language` | string | **Full English name** ("English", "French", "Multilingual"), not a code. |
| `copyright_year` | string | Year of the original work. |
| `num_sections` | string | |
| `totaltime` | string | `HH:MM:SS`. Empty when unknown. |
| `totaltimesecs` | number | Seconds. `0` means unknown. |
| `authors`, `translators` | array of Person | Person = `{id, first_name, last_name, dob, dod}`. All strings, years may be empty. |
| `url_librivox` | string | The project page. |
| `url_rss` | string | Podcast feed for the book. |
| `url_zip_file` | string | Whole book as a 64 kbps MP3 zip. |
| `url_iarchive` | string | archive.org item (extended only). |
| `url_project`, `url_other` | string | Usually Wikipedia; may be empty. |
| `sections` | array of Section | Extended only. Section = `{id, section_number, title, listen_url, language, playtime, file_name, readers}`. `playtime` is seconds, as a string. `readers` = `[{reader_id, display_name}]`. `display_name` can carry life years, e.g. "Kara Shallenberg (1969-2023)". |
| `genres` | array of `{id, name}` | Extended only. |
| `coverart_jpg`, `coverart_thumbnail`, `coverart_pdf` | string | With `coverart=1`. |

## Notes for the Free Book Reader

Mapping onto the data model in [spec.md](spec.md):

* **Book fields:** `id` (source ID), `title`, authors as "first_name last_name", `language` (convert the English name to a 2-letter code; "Multilingual" and unknown names become unknown), format `audio`, `totaltimesecs` (length of audio; `0` = unknown), `url_librivox` (URL), `coverart_jpg` (cover image). No page count.
* **Readers are narrators, not authors.** Collect them from `sections[].readers`, strip the "(years)" suffix, and remove duplicates. They are never used for matching (spec merge rules).
* **Chapters for the player:** `sections` gives `title`, `listen_url` (MP3) and `playtime` per chapter. Playing them uses just_audio.
* **Listen while reading:** when `url_text_source` is a Gutenberg URL, its number is the Gutenberg ID of the text that was read. Record it as a `gutenberg` identifier to pair the recording with the Gutendex book.
* **Search mapping:** author search sends the last name only ("Charles Dickens" and "Dickens, Charles" both become `Dickens`). Title and free-text search send `title=^<text>`, a prefix match. This also finds later recordings such as "... (version 2)". When both title and author are given, only `title` is sent and the results are filtered by author last name. Text-only and ISBN-only searches skip LibriVox (it has no ISBNs). Apply the language filter to the results.
* **Leading articles (tested 2026-10-10):** LibriVox catalogs titles without a leading article: "Time Machine", "Christmas Carol", "Misérables - tome 1". So `title=^the time machine`, `^a christmas`, `^les mis` and `^die ` all find nothing. The backend drops a leading article (English, French, German, Spanish, Italian, Dutch) before sending the title. **Exceptions (tested 2026-10-11):** Italian "Il" and Latin "De" are kept: `^Il Principe` finds "Il Principe" but `^Principe` finds nothing; `^De Profundis`, `^De Rerum` and `^De Bello` find their books but `^Profundis` finds nothing. Dutch "De" and German "Die" are dropped (`^Kleine Johannes` and `^Leiden des` work). The backend never strips "Il" or "De", so a Dutch title that starts with "De" is not found.
* **Repeat recordings:** titles end in "(version 2)", "(Version 4)", "(version 6, dramatic reading)". `title_key` ignores that suffix, so all recordings of a book merge into one work.
* **Unfinished projects:** some projects (e.g. `id` `22765`) list sections whose `listen_url` is `null` and `playtime` is `"0"`. They have no playable chapters, so the app links to the LibriVox page.
* **Free-text limitation:** LibriVox has no keyword search. A free-text query only finds books whose title starts with it ("pride" finds "Pride and Prejudice"; "prejudice" does not). See "How matching really works" above.
* **Outage rule:** `404` with the "could not be found" message means no results. `5xx` (except the title+author `500`, which we avoid) and non-JSON bodies count as an outage. A timeout leaves LibriVox out of that search only.
