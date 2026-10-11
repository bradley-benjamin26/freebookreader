# DOAB API (Directory of Open Access Books)

DOAB lists peer-reviewed open access books (and some chapters) from hundreds of academic publishers. Everything in it is free to read. It is a joint service of OAPEN, OpenEdition, CNRS and Aix-Marseille Université, provided by the DOAB Foundation (The Hague). Many DOAB books' PDFs are hosted in the OAPEN Library. DOAB runs on DSpace, like OAPEN.

Official docs: https://www.doabooks.org/en/librarians/doab-metadata. The page is behind a Cloudflare check (browsers only); this file follows a copy saved from a browser on 2026-10-10. The REST API's full guide is a PDF: https://doabooks.o172i.upcloudobjects.com/uploads/DOAB_REST_API_advanced_guide_710fe9a1da.pdf.

The ways in, as the docs list them, plus one they don't mention:

| Way in | Documented | Works for us | Used |
|---|---|---|---|
| **REST API** `https://directory.doabooks.org/rest/search?query=...` | Yes | **No**: rejects our IP | No |
| **OpenSearch** `https://directory.doabooks.org/open-search/discover?query=...` | No (standard DSpace) | Yes | **Yes**: finds the handles |
| **OAI-PMH** `https://directory.doabooks.org/oai/request` | Yes ("xoai provides the full set of metadata fields") | Yes | **Yes**: `GetRecord` fills in each hit |
| **Metadata feeds** (bulk, CC0) on `memo.doabooks.org` | Yes | Yes | No (see "A local index" below) |
| **RSS / Atom** `https://directory.doabooks.org/feed/{rss_1.0,rss_2.0,atom_1.0}/site` | Yes | Yes | No: newest items only, no search |
| **Selective Export** (pick titles in the website, export CSV; up to about 500) | Yes | Browser only | No |
| **PRISM API** `https://directory.doabooks.org/rest/peerReviews?doi=...` (peer-review info; exactly one of `doi`, `isbn`, `pId`, `title`; 400 for none or several, 404 for no match) | Yes | **No**: under `/rest`, rejects our IP | No |

## Access (tested 2026-10-10)

| Endpoint | Result |
|---|---|
| `/rest/...` (any path) | HTTP `403`, plain text `You address is not allowed to access this API.` (their spelling), with or without a browser `User-Agent`. An IP allow-list. |
| `/open-search/discover` | `200`, Atom. About 0.5 s. |
| `/oai/request` | `200`, XML. About 0.4 s per `GetRecord`. |
| Record pages (`/handle/...`), `/discover` | `403` "Making sure you're not a bot!" (Anubis) to HTTP clients; browsers pass. |
| PDF links on `library.oapen.org` | `403` Anubis bot check to HTTP clients; browsers pass. |
| PDF links on other hosts | Varies: IntechOpen serves the PDF directly; QScience returns an HTML page for a `.pdf` URL. |

## Endpoint: REST search (documented, blocked for us)

`GET https://directory.doabooks.org/rest/search?query=<URL-encoded query>`. From the docs:

* Full text: `query=water+AND+fire`.
* Exact title: `query=dc.title:%22the+deliverance+of+open+access+books%22`.
* One handle: `query=handle:%2220.500.12854/26303%22`.
* Response expansion (metadata, bitstreams), date queries, collections, funders, publishers and JSON or XML output are in the advanced guide (PDF, linked above).

```bash
curl "https://directory.doabooks.org/rest/search?query=water+AND+fire"
```

What we get back (HTTP `403`):

```
You address is not allowed to access this API.
```

## Endpoint: OpenSearch

`GET https://directory.doabooks.org/open-search/discover`

| Parameter | Value | Meaning |
|---|---|---|
| `query` | text | Keyword search over all fields. An ISBN works as a plain term. Field syntax (`title:...`, `author:...`, `dc.language:...`) finds **nothing**. |
| `rpp` | integer | Results per page. |
| `start` | integer | Offset of the first result (0-based): page 2 of 20 is `start=20`. |
| `format` | | Ignored: the answer is always Atom. |

There is no language, type or date filter; filter after the response comes back.

```bash
curl "https://directory.doabooks.org/open-search/discover?query=pride&rpp=10&start=0"
```

Real response, abridged (from [samples/doab-opensearch.xml](samples/doab-opensearch.xml), captured 2026-10-10): one of the ten entries, the summary shortened.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/" xmlns:dc="http://purl.org/dc/elements/1.1/">
<title>DOAB PROD Instance</title>
<opensearch:itemsPerPage>10</opensearch:itemsPerPage>
<opensearch:totalResults>117</opensearch:totalResults>
<opensearch:startIndex>1</opensearch:startIndex>
<opensearch:Query role="request" searchTerms="pride" startPage="1"/>
<entry>
<title>Pride in the Projects</title>
<link href="https://directory.doabooks.org/handle/20.500.12854/180381" rel="alternate"/>
<author>
<name>Deutsch, Nancy L.</name>
</author>
<id>https://directory.doabooks.org/handle/20.500.12854/180381</id>
<updated>2026-08-01T05:23:10Z</updated>
<published>2008-01-01T00:00:00Z</published>
<summary type="text">…</summary>
<dc:date>2008-01-01T00:00:00Z</dc:date>
</entry>
</feed>
```

* **Stale entries:** the search index keeps records that no longer exist. They come back titled `Untitled` with an empty `<name/>`, and `GetRecord` answers `idDoesNotExist` for them. In the "pride" sample, 6 of 10 entries are like this. Skip them.
* **Chapters** appear as hits too ("12: (Dis)placing Pride in Copenhagen"). Only the OAI record says so (`dc.type` = `chapter`).
* No result: an Atom feed with `totalResults` 0 and no entries ([samples/doab-opensearch-empty.xml](samples/doab-opensearch-empty.xml)).

## Endpoint: OAI-PMH GetRecord (xoai)

`GET https://directory.doabooks.org/oai/request?verb=GetRecord&metadataPrefix=xoai&identifier=oai:doabooks.org:<handle>`

The docs write the identifier as `oai:doabooks.org:<handle>`; the records' own headers say `oai:directory.doabooks.org:<handle>`. Both work; the backend sends the documented form. `ListRecords&metadataPrefix=xoai` harvests everything.

Other formats (`ListMetadataFormats`): `oai_dc`, `dim`, `qdc`, `mods`, `marc`, `mets`, `didl`, `ore`, `rdf`, `uketd_dc`, `etdms`. Only `xoai` includes the bitstreams (cover and download link); `oai_dc` and `dim` have the same descriptive metadata without them.

```bash
curl "https://directory.doabooks.org/oai/request?verb=GetRecord&metadataPrefix=xoai&identifier=oai:doabooks.org:20.500.12854/159907"
```

Real response, abridged (from [samples/doab-xoai/159907.xml](samples/doab-xoai/159907.xml)): descriptions, subjects, authority IDs, peer-review fields and three of the five bundles removed.

```xml
<OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/">
<GetRecord><record>
<header><identifier>oai:directory.doabooks.org:20.500.12854/159907</identifier><datestamp>2025-05-20T05:43:30Z</datestamp></header>
<metadata><metadata xmlns="http://www.lyncode.com/xoai">
<element name="dc">
  <element name="contributor"><element name="author"><element name="none">
    <field name="value">Peterson, Abby</field>
    <field name="value">Wahlström, Mattias</field>
    <field name="value">Wennerhag, Magnus</field>
  </element></element></element>
  <element name="language"><element name="none"><field name="value">eng</field></element></element>
  <element name="title"><element name="none"><field name="value">Pride Parades and LGBT Movements</field></element></element>
  <element name="type"><element name="none"><field name="value">book</field></element></element>
</element>
<element name="oapen">
  <element name="identifier"><element name="doi"><element name="none"><field name="value">10.4324/9781315474052</field></element></element></element>
  <element name="relation"><element name="isbn"><element name="none">
    <field name="value">9781315474045</field>
    <field name="value">9781138202399</field>
  </element></element></element>
  <element name="pages"><element name="none"><field name="value">282</field></element></element>
</element>
<element name="bundles">
  <element name="bundle">
    <field name="name">THUMBNAIL</field>
    <element name="bitstreams"><element name="bitstream">
      <field name="name">9781315474045.pdf.jpg</field>
      <field name="format">image/jpeg</field>
      <field name="url">https://directory.doabooks.org/bitstream/20.500.12854/159907/1/9781315474045.pdf.jpg</field>
      <field name="oapenidentifierdownloadUrl">https://library.oapen.org/bitstream/20.500.12657/102101/1/9781315474045.pdf</field>
    </element></element>
  </element>
</element>
<element name="others">
  <field name="handle">20.500.12854/159907</field>
</element>
</metadata></metadata>
</record></GetRecord>
</OAI-PMH>
```

A handle DOAB no longer has ([samples/doab-xoai/1082.xml](samples/doab-xoai/1082.xml)):

```xml
<OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"><request verb="GetRecord" ...>https://directory.doabooks.org/oai/request</request><error code="idDoesNotExist">The given id does not exist</error></OAI-PMH>
```

### xoai fields we use

The metadata is a tree of `<element name=...>`; values sit in `<field name="value">` under a language element (`none`, `en_US`, ...).

| Path | Meaning |
|---|---|
| `dc.title` | Title. |
| `dc.contributor.author`, `dc.contributor.editor` | "Last, First". Edited volumes have editors and no authors. |
| `dc.language` | MARC code (`eng`, `ger`). |
| `dc.type` | `book` or `chapter`. |
| `dc.identifier` | Includes `OCN: <OCLC number>` and the OAPEN Library handle URL when the book is in OAPEN. |
| `oapen.relation.isbn` | ISBNs (several per book: print, PDF, EPUB). |
| `oapen.identifier.doi` | DOI. |
| `oapen.pages` | Page count (not always present). |
| `bundles` → `THUMBNAIL` → `url` | Cover image. Books without one get DOAB's placeholder `open-access-no-cover.png`; ignore it. |
| `bundles` → bitstream `oapenidentifierdownloadUrl` | **The full-text link.** Usually a PDF in the OAPEN Library; otherwise a publisher's PDF or web page (Frontiers, OpenEdition, doi.org, ...). In a sample of 91 live records: 86 had one, 65 ending in `.pdf` (55 on library.oapen.org). |
| `others.handle` | The DOAB handle (source ID). |

## Metadata feeds (bulk downloads)

All CC0, from `https://memo.doabooks.org/file/oapen/`:

| File | Contents |
|---|---|
| `DOAB.json` | Every title as an OPDS 2.0 catalog. 324 MB, 107,232 publications (2026-10-10). |
| `DOAB.csv` | CSV. |
| `DOAB_MARCXML.xml` | MARC 21 XML. |
| `DOAB_ONIX.xml` | ONIX 3.0. |
| `DOAB_KBART.tsv`, `DOAB_KBART_books.tsv`, `DOAB_KBART_books_with_download_url.tsv` | KBART (tab-separated): everything, books only, and books with a download URL. |
| `DOAB_peerreview.csv` | Book metadata with PRISM peer-review fields, updated daily. |

```bash
curl -O "https://memo.doabooks.org/file/oapen/DOAB.json"
```

One publication from `DOAB.json` (real, 2026-10-10; description shortened):

```json
{
  "metadata": {
    "title": "Legislating for the Future",
    "subtitle": "The Pan-African Model Law for Sustainable Soil Management",
    "author": null,
    "editor": ["Ginzky, Harald", "Ruppel, Oliver C."],
    "language": ["ger"],
    "modified": "2026-05-07 00:34:08",
    "description": "This publication is based on a project funded by the German Federal Ministry …",
    "publisher": "Nomos Verlagsgesellschaft mbH & Co. KG",
    "imprint": null,
    "published": 2026,
    "docType": "book",
    "subject": null,
    "classification": null,
    "belongsTo": {"series": "Recht und Verfassung in Afrika - Law and Constitution in Africa", "seriesNumber": "50"},
    "numberOfPages": null,
    "identifier": "https://directory.doabooks.org/handle/20.500.12854/176147",
    "doi": "10.5771/9783748966609",
    "isbn": ["978-3-7560-3274-7", "9783748966609"],
    "licence": null,
    "accessibility": {"accessMode": ["textual", "visual"], "hazard": "unknown"}
  },
  "links": {"href": "https://doi.org/10.5771/9783748966609", "rel": "http://opds-spec.org/acquisition/open-access", "type": "application/pdf"},
  "images": {"href": "https://directory.doabooks.org/bitstream/20.500.12854/176147/1/10.5771_9783748966609_big.png", "type": "image/jpeg"}
}
```

Note that `links` can be a single object or a list, and a link typed `application/pdf` can be a doi.org page rather than a PDF.

### A local index (not decided)

The backend could load `DOAB.json` nightly into its own index and search that, as it does for Gutenberg with Gutendex. Compared with OpenSearch plus a lookup per hit, that would mean one local query instead of 21 requests, a real language filter, no stale "Untitled" entries, and the accessibility metadata (`accessMode`, `hazard`) for the reader. The cost is a 324 MB nightly download, a database table, and results that are up to a day old.

## Notes for the Free Book Reader

Mapping onto the data model in [spec.md](spec.md):

* **Search:** free text, title, author, keyword and ISBN (normalized to ISBN-13) all go into OpenSearch's `query`. Paging uses `start` = (page − 1) × `rpp`, with `rpp` 20. Audio-only searches skip DOAB. Then one `GetRecord` (xoai) per hit, 10 at a time in parallel. A search takes about 1.5 s.
* **Book fields:** handle (source ID), `dc.title`, authors (reorder "Last, First" to "First Last"), editors as contributors, language (3-letter → 2-letter code), format `text`, pages, URL `https://directory.doabooks.org/handle/<handle>`, cover from the `THUMBNAIL` bundle, and access `open`.
* **Identifiers:** ISBNs (validate the check digit; drop bad ones), OCLC number from `OCN:`, DOI. ISBN and OCLC are used for the first merge pass.
* **Reading:** a download link whose path ends in `.pdf` becomes the book's PDF and opens in the app. Any other link is left to the DOAB record page, which links to it. OAPEN-hosted PDFs are behind a bot check, so the device has to fetch them (WebView on mobile, iframe or new tab on web); see "Getting OAPEN PDFs" in [decision_reader.md](decision_reader.md). Some `.pdf` links return a web page, so the reader must fall back to the record page when a file is not a PDF.
* **Skipped:** chapters (`dc.type` = `chapter`), deleted records, and stale search entries (`Untitled`, or `idDoesNotExist`).
* **Lookup failures:** if a `GetRecord` fails, the hit is kept with what the search said (title, authors, record page) and no language, so it is dropped by a language filter.
* **Language filter:** DOAB cannot filter by language, so the filter is applied to the 20 results of the requested page. A search in a language other than English may find few DOAB books on page 1.
* **Outage rule:** the "not allowed" message, `403`, `5xx`, an HTML page instead of Atom, and malformed XML count as an outage. A timeout leaves DOAB out of that search only. An empty feed is zero results.
* **If DOAB allows our IP:** the REST API (`/rest/search?query=...&expand=metadata,bitstreams`) would return the metadata and files in one request. Ask info@oapen.org once the server's IP is known.
