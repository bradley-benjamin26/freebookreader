# Sample API responses

Captured 2026-10-10 with curl. Real responses, unedited.

| File | Request |
|---|---|
| librivox-title-search.json | `audiobooks?title=pride and prejudice&format=json&extended=1&coverart=1&limit=3` |
| librivox-author-search.json | `audiobooks?author=^dickens&format=json&limit=3` |
| openlibrary-search.json | `search.json?q=pride+and+prejudice&limit=3` |
| openlibrary-search-title-author.json | `search.json?title=...&author=austen&limit=3&fields=...` (the `fields` filter was applied; the file is large because the response includes much more per doc than listed) |
| openlibrary-work.json | `works/OL66554W.json` |
| openlibrary-isbn.json | `isbn/9780140430721.json` (edition record) |
| openlibrary-search-borrowable.json | `search.json?q=dean koontz frankenstein ebook_access:[borrowable TO *]&limit=3&fields=...,editions,editions.key,editions.ebook_access` (2026-10-10) |
| openlibrary-availability-v2.json | `availability/v2?type=openlibrary_edition&ids=OL23273427M,OL25968798M,OL22173091M,OL50444320M,OL3311782M` (2026-10-10; live loan status) |
| openlibrary-availability.json | `api/volumes/brief/isbn/9780140430721.json` (large; `items` holds lending/access status) |
| gutendex-search.json | Self-hosted Gutendex: `books/?search=dickens great` |
| gutendex-book.json | `books/11/` |
| gutendex-french.json | `books/?languages=fr&search=hugo&mime_type=text/html` |
| gutendex-audio.json | `books/?mime_type=audio` (first page of 1,153) |
| doab-opensearch.xml | DOAB OpenSearch `open-search/discover?query=pride&rpp=10&start=0` (6 of the 10 entries are stale "Untitled" records) |
| doab-opensearch-empty.xml | DOAB OpenSearch `open-search/discover?query=zzzzqqqxx&rpp=10` (no results) |
| doab-xoai/`<n>`.xml | DOAB OAI-PMH `verb=GetRecord&metadataPrefix=xoai&identifier=oai:directory.doabooks.org:20.500.12854/<n>`, one file per hit in doab-opensearch.xml (the stale ones answer `idDoesNotExist`), plus 133576 (a German book from `query=kinder`) |

## Not captured
- **Gutendex** (gutendex.com): returned a Cloudflare bot challenge (HTTP 403) to curl. The `gutendex-*.json` files were captured from the self-hosted instance on 2026-10-10 and pretty-printed. They were captured again the same day, with the same requests, after our Gutendex gained `release_date`, `last_updated`, `credits` and `original_publication` (see api_gutendex.documentation.md); gutendex.com does not have these fields.
- **DOAB REST search** (directory.doabooks.org/rest/search): returned "You address is not allowed to access this API." (HTTP 403). It is restricted by IP address, like OAPEN's.
