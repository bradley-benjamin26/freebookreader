# HathiTrust API

HathiTrust is a library partnership that holds digitized volumes from its member libraries (millions of them). Part of the collection is out of copyright (or openly licensed) and can be read by anyone. The rest is search-only. The decision on how we use it is in [decision_hathitrust.md](decision_hathitrust.md).

Official docs:
* Bibliographic API: https://www.hathitrust.org/member-libraries/resources-for-librarians/data-resources/bibliographic-api/
* Hathifiles: https://www.hathitrust.org/member-libraries/resources-for-librarians/data-resources/hathifiles/
* OAI-PMH: https://www.hathitrust.org/member-libraries/resources-for-librarians/data-resources/oai-pmh-feed/

The docs pages on www.hathitrust.org are behind a Cloudflare check for HTTP clients (HTTP 403 "Just a moment..."). The facts below were tested with curl on 2026-10-11, not copied from those pages. Re-read them in a browser before building.

## The ways in

| Way in | Search? | Works for us | Used |
|---|---|---|---|
| **Hathifiles** (bulk files of one tab-separated row per volume) `https://www.hathitrust.org/files/hathifiles/` | No: we build the index | **Yes** | **Yes**: the only source of search |
| **Bibliographic API** `https://catalog.hathitrust.org/api/volumes/...` | No: lookup by ID only | **Yes** | Yes, for volumes of one record |
| **OAI-PMH** `https://oai.hathitrust.org/` | No: harvest only | Yes | No: too slow and too large (see below) |
| **Reader** `https://babel.hathitrust.org/cgi/pt?id=<htid>` | n/a | **No**: blocked for our IP | Linked to, from the user's browser |
| **Data API** (page images, OCR, needs an application key) | n/a | Not tested: the `babel` host is blocked, and we have no key | No |

HathiTrust has no search API. A catalog search page exists (`catalog.hathitrust.org/Search`), but it is behind the same Cloudflare check.

## Access (tested 2026-10-11)

| Request | Result |
|---|---|
| `catalog.hathitrust.org/api/volumes/...` | `200` JSON, fast. |
| `oai.hathitrust.org/?verb=Identify` | `200` XML. |
| `www.hathitrust.org/files/hathifiles/hathi_file_list.json` and the `.txt.gz` files | `200`. |
| `www.hathitrust.org/` (pages), `catalog.hathitrust.org/Record/...`, `babel.hathitrust.org/cgi/pt` | `403` Cloudflare challenge (`cf-mitigated: challenge`) to curl, with or without a browser `User-Agent`. |
| `babel.hathitrust.org/cgi/imgsrv/download/pdf`, `.../plaintext`, `.../image`, `/cgi/htd/...` | `403`. The `imgsrv` paths return a page titled "Error - Blocked from HathiTrust": "Because of your IP address' reputation or location". |

So the machine this was tested on can fetch the metadata but cannot read any book. The block is probably tied to the IP address, like OAPEN's (see api_doab.documentation.md). Not tested from the final server. If we get the server's IP, ask support@hathitrust.org whether it can be allowed, and retest.

The `X-Frame-Options: SAMEORIGIN` header we saw on `babel.hathitrust.org` belongs to Cloudflare's challenge page, not the reader. Whether the real reader can be put in an iframe is **unverified** (see decision_hathitrust.md).

## Hathifiles

HathiTrust publishes the metadata of every volume as flat files.

* **Index:** `https://www.hathitrust.org/files/hathifiles/hathi_file_list.json`, a JSON array of `{filename, full, size, created, modified, url}`. On 2026-10-11 it listed 73 files: two full files (`hathi_full_20260901.txt.gz` and `hathi_full_20261001.txt.gz`, **1.22 GB** each) and about 70 daily update files.
* **Full file:** `hathi_full_YYYYMMDD.txt.gz`, made on the 1st of each month. It lists all volumes.
* **Update file:** `hathi_upd_YYYYMMDD.txt.gz`, made daily, 5–8 MB, with rows added or changed that day. The file list has no deletion file. We did not find out how removed volumes are signalled; check the docs in a browser before relying on updates.
* **Format:** gzip, UTF-8, tab-separated, **no header row**. The columns are listed in `https://www.hathitrust.org/files/hathifiles/hathi_field_list.txt`:

| # | Column | Notes |
|---|---|---|
| 1 | `htid` | The volume ID, e.g. `mdp.39015001657579`. Used in the reader link and the Bib API. |
| 2 | `access` | `allow` or `deny`. |
| 3 | `rights` | Rights code (below). |
| 4 | `ht_bib_key` | The catalog record number. Several volumes (copies, volumes of a set) share one. |
| 5 | `description` | Volume label, e.g. `v.2`; empty for single-volume books. (`enumcron` in the Bib API.) |
| 6 | `source` | Library code, e.g. `MIU`. |
| 7 | `source_bib_num` | The library's own record number. |
| 8 | `oclc_num` | Comma-separated OCLC numbers. |
| 9 | `isbn` | Comma-separated ISBNs. |
| 10 | `issn` | |
| 11 | `lccn` | |
| 12 | `title` | |
| 13 | `imprint` | Publisher and date as a string. |
| 14 | `rights_reason_code` | |
| 15 | `rights_timestamp` | When the rights were set. |
| 16 | `us_gov_doc_flag` | `0` or `1`. |
| 17 | `rights_date_used` | Year used for the rights decision (the publication year). |
| 18 | `pub_place` | MARC place code. |
| 19 | `lang` | MARC language code (`eng`, `fre`, `ger`, ...). Three-letter MARC codes, not the ISO 639-1 codes we use; map them. |
| 20 | `bib_fmt` | `BK` book, `SE` serial, ... |
| 21–25 | `collection_code`, `content_provider_code`, `responsible_entity_code`, `digitization_agent_code`, `access_profile_code` | Provenance. |
| 26 | `author` | |

Rights codes seen in the update file of 2026-10-10 (116,392 rows): `ic` (in copyright, 62,383), `pd` (public domain, 28,932), `pdus` (public domain in the US only, 12,222), `und` (undetermined, 10,792), `pd-pvt` (935), `cc-*` (creative commons: `cc-by-nc-nd-4.0` 327, `cc-by-4.0` 177, `cc-zero` 131, ...), `icus`, `ic-world`, `op`, `nobody`. In that file, **every `pd`, `pdus` and `cc-*` row has `access=allow`, and every other row has `deny`**. 42,085 of the rows (36%) were `allow`; of those, 27,759 were English, 7,579 German and 3,443 French. A daily file is not typical of the whole collection, so these shares are only a hint. We did not download the full file; it has not been counted.

`allow` is therefore the public-domain and open-license filter. `pdus` volumes are only viewable by everyone in the US; outside the US HathiTrust may treat them as search-only. The `access` column does not tell the two apart.

Sample rows (3 `pd`/`allow` rows from 2026-10-10): [samples/hathitrust-hathifile-rows.tsv](samples/hathitrust-hathifile-rows.tsv).

```
uc1.b3731354	allow	pd	1566424		UC	b3731354	...	Deutsche Monatsschrift für Zahnheilkunde.	Verlag von Julius Springer.	...	1883	...	ger	SE	...
```

```bash
curl -s https://www.hathitrust.org/files/hathifiles/hathi_file_list.json | head -c 400
curl -sO https://www.hathitrust.org/files/hathifiles/hathi_upd_20261010.txt.gz
gzip -dc hathi_upd_20261010.txt.gz | awk -F'\t' '$2=="allow"' | head -3
```

## Endpoint: Bibliographic API

`GET https://catalog.hathitrust.org/api/volumes/{brief|full}/{type}/{value}.json`

* `brief` gives the catalog record and its volumes. `full` adds the MARC record (`marc-xml`) for each record.
* `type`: `oclc`, `isbn` and `htid` were tested. `issn`, `lccn` and `recordnumber` are listed in HathiTrust's documentation (from memory; not tested here). Any other type gives HTTP `400` with `{"message":"query 'foo:1' is invalid"}`.
* **Several IDs in one call:** `GET .../api/volumes/brief/json/oclc:424023|oclc:2686466` (the `|` encoded as `%7C`). The result is an object keyed by the query (`"oclc:424023": {records, items}`). Tested: works.
* **No match** is `200` with `{"records": {}, "items": []}`, not a 404.
* **Auth:** none. **Rate limit:** none documented; we send our User-Agent and ask rarely.
* **Response:** `records` is keyed by catalog record number (`recordURL`, `titles`, `isbns`, `issns`, `oclcs`, `lccns`, `publishDates`). `items` has one entry per volume:

| Field | Meaning |
|---|---|
| `htid` | Volume ID. |
| `fromRecord` | Key into `records`. |
| `itemURL` | `https://babel.hathitrust.org/cgi/pt?id=<htid>`: the reader page. Equals the link built from the htid, so we don't need the API for it. |
| `orig` | Holding library name. |
| `rightsCode` | Same codes as the Hathifile. |
| `usRightsString` | `Full view` or `Limited (search-only)`. |
| `enumcron` | `false` or the volume label (`"no.6"`). |
| `lastUpdate` | `YYYYMMDD`. |

The API gives **no text, no PDF and no page images**, only catalog data and links to the reader.

Sample responses: [samples/hathitrust-bib-brief.json](samples/hathitrust-bib-brief.json) (a viewable volume) and [samples/hathitrust-bib-brief-not-viewable.json](samples/hathitrust-bib-brief-not-viewable.json) (two search-only volumes).

```bash
curl -s "https://catalog.hathitrust.org/api/volumes/brief/oclc/2686466.json" | python3 -m json.tool
```
```json
{
    "records": {
        "008586797": {
            "recordURL": "https://catalog.hathitrust.org/Record/008586797",
            "titles": ["History of the United States, from their first settlement as colonies, to the close of Mr. Tyler's administration, in 1845 : to which are added questions, adapted to the use of schools"],
            "isbns": [],
            "issns": [],
            "oclcs": ["2686466"],
            "lccns": [],
            "publishDates": ["1849"]
        }
    },
    "items": [
        {
            "orig": "New York Public Library",
            "fromRecord": "008586797",
            "htid": "nyp.33433012110726",
            "itemURL": "https://babel.hathitrust.org/cgi/pt?id=nyp.33433012110726",
            "rightsCode": "pd",
            "lastUpdate": "20260330",
            "enumcron": false,
            "usRightsString": "Full view"
        }
    ]
}
```

**Placeholder ISBNs.** A lookup by `isbn/0000000000` returned 10 unrelated records, all carrying the fake ISBN `9780000000002` (and strings like `000000000061rub`, which are not ISBNs). The Data Merging rules must ignore `9780000000002` and any identifier that is not a valid ISBN with a good check digit. The Hathifile `isbn` column has the same values. The same may hold for OCLC numbers; no sample showed it.

## OAI-PMH (not used)

`https://oai.hathitrust.org/?verb=ListRecords&metadataPrefix=marc21&set=hathitrust:pdus`. Sets: `hathitrust`, `hathitrust:pd`, `hathitrust:pdus`. `Identify` says the earliest datestamp is 2013-08-01, deleted records are `transient`, and granularity is a date (`YYYY-MM-DD`).

Measured 2026-10-11 on `hathitrust:pdus`: 3,616,684 records, 500 per page, **24 s and 1.4 MB per page**. A full harvest is about 7,200 requests: roughly 48 hours one after another and about 10 GB of MARC XML. The Hathifile is 1.2 GB, flat, and is made monthly with daily updates, so we use it instead. OAI-PMH does give deleted records, which the Hathifile may not (see above); if that matters, harvest only `from=<last date>`.

Sample: [samples/hathitrust-oai-identify.xml](samples/hathitrust-oai-identify.xml).

## Reading a book (babel)

The reader for volume `<htid>` is `https://babel.hathitrust.org/cgi/pt?id=<htid>` (add `&seq=<page>` for a page). It is the only place HathiTrust offers reading, search inside the book, and downloads. According to the project owner, some books can be downloaded only by a signed-in user. We have not verified this; the host is blocked from our IP.

## Limitations and notes

* **A book is a volume.** One catalog record (`ht_bib_key`) can have many volumes: copies from different libraries, and volumes of a set (`description` / `enumcron`). A work in our app will have several HathiTrust books; show the volume label and holding library so they can be told apart.
* **Title and author strings are MARC.** Titles include the statement of responsibility ("Pride and prejudice / by Jane Austen"), authors are "Austen, Jane, 1775-1817." Normalization is needed before matching (the same applies to Open Library).
* **Language codes** are 3-letter MARC codes. Convert to ISO 639-1 (`ger` → `de`, `fre` → `fr`); the bibliographic and terminology codes differ for some languages (`ger`/`deu`).
* **Rights are decided per volume and can change.** Update files carry the changes; a volume can move from `deny` to `allow` when its rights are reviewed.
* **`und` (undetermined)** and `pd-pvt` are not `allow`; we do not offer them.
