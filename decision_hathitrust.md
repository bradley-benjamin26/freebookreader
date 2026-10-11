# Decision: HathiTrust

Status: **decided 2026-10-11** and **built 2026-10-11** for search and for the first version of reading (link out). The in-app reader (step 6) is not built. Tests came first (`test_hathifile.py`, `test_hathitrust_index.py`, `test_hathitrust_update.py`, `test_source_hathitrust.py`, plus additions to the merge, reader, config, info and app tests). Facts come from curl tests on 2026-10-11 (see [api_hathitrust.documentation.md](api_hathitrust.documentation.md)).

## Background

HathiTrust was left out of the first version because it has no search API ([spec.md](spec.md) said it would be a separate project). It has a large collection of out-of-copyright books, many in languages the other sources are thin in, so it is now added as a fifth source, `hathitrust`.

## Decision

1. **Search uses a local index built from the Hathifiles.** HathiTrust publishes one tab-separated row per volume (title, author, language, rights, ISBN, OCLC, year, volume label). The backend loads the rows with `access = allow` (public domain and open licenses) into a local database and searches that. It does not call HathiTrust at search time, so a search is fast and HathiTrust cannot slow it down or cause an outage.
2. **The index is refreshed from the daily update files**, and rebuilt from the monthly full file (1.2 GB compressed) when needed. The same kind of nightly job as `updatecatalog` for Gutendex.
3. **The Bibliographic API is optional.** The Hathifile already has the fields we need, and the reader link can be built from the volume ID. Use the API only when we want something the file lacks, such as the other volumes of a record. It is not used in a search.
4. **OAI-PMH is not used.** Measured: a full harvest of `hathitrust:pdus` is about 7,200 requests at 24 s each (about 2 days) and about 10 GB of XML. It is only worth considering if we need to know which volumes were removed.
5. **Reading, version 1: link out.** A HathiTrust book opens at `https://babel.hathitrust.org/cgi/pt?id=<htid>` in the user's browser (`url_launcher`, as for Open Library). HathiTrust's reader, sign-in and downloads all stay on HathiTrust's side. The app has no in-app reading, text-to-speech, bookmarks inside the book or offline copy for these books.
6. **Reading, later: HathiTrust's reader inside the app, only if the checks pass.**
    * Mobile and desktop: an in-app WebView (`webview_flutter`) loads the reader as a top-level page, so framing headers do not apply.
    * Web: an `<iframe>`, only if the real reader's `X-Frame-Options` and `Content-Security-Policy: frame-ancestors` allow our origin. Otherwise web links out. We do not proxy the reader through our backend (it would break their cookies and sign-in, and our IP is blocked).
    * It would be a third `ReaderEngine` (see [decision_reader.md](decision_reader.md)) that only shows the page. Bookmarks keep the volume and no position.

## Why not the other ways

* **Download everything through OAI-PMH:** about 5–10 times the storage and 100 times the fetch time of the Hathifile, for the same fields.
* **Look books up one by one through the Bibliographic API:** it cannot search, only look up by an ID we already have.
* **Read HathiTrust text or PDFs through our backend:** the `babel` host blocks our IP (Cloudflare challenge on the pages, "Blocked from HathiTrust" on the PDF, text and image downloads). We have not read HathiTrust's terms on automated access.

## Checks before step 6 (not done)

1. In a browser, open a public-domain volume and look at the response headers of the `pt?id=…` request for `X-Frame-Options` and `frame-ancestors`.
2. Read HathiTrust's terms of use on embedding their reader.
3. In a WebView on a phone, check that the reader works, that a user can sign in, and that screen readers (VoiceOver, TalkBack) can use it. This matters most because the spec requires WCAG 2.2 AA, and we cannot change their reader. If it fails, keep linking out and say so on the About page.
4. From the final server, retest whether the `babel` host is still blocked; if so, ask support@hathitrust.org to allow the IP. (Our app does not need this if the user's device loads the reader.)

## Built (2026-10-11)

* `backend/app/hathifile.py` reads a line; `hathitrust_index.py` is the SQLite file with full-text search; `hathitrust_update.py` is the nightly job (`python -m app.hathitrust_update`); `sources/hathitrust.py` is the source in `/search`. Settings: `FBR_HATHITRUST_INDEX` (default `backend/cache/hathitrust.sqlite`, ignored by git) and `FBR_HATHITRUST_FILE_LIST_URL`.
* The index keeps `access = allow` **and** `bib_fmt = BK` (books). A daily file has 485,566 rows: 328,389 are `allow`, but 291,489 of those are serials (`SE`, journals and government series), so only 36,833 are books.
* The Flutter app lists HathiTrust as a fifth source: filter chip, About page, and on the details page the volume label, library and the United States note. The book button opens the reader in the browser.

## Measured (2026-10-11, the real files)

Run of `python -m app.hathitrust_update` from nothing: the full file of 2026-10-01 (1.2 GB) and the 11 daily files since, **4 min 10 s** on a laptop, mostly the full file (about 3.5 min). A second run found nothing to do.

| | |
|---|---|
| Volumes in the index | **5,353,556** (3,336,110 catalog records; 4,419,561 distinct record and volume-label pairs) |
| Index file | **1.65 GB** |
| Rights | `pd` 3,850,934 (72%), `pdus` 1,445,815 (27%), the rest (`cc-*`, `und-world`, ...) about 1% |
| Languages | English 60%, German 11%, French 9%, Spanish 3.5%, Italian 2.5%, Latin 2.3%, no language 1.8%, Japanese 1.5%, Chinese 1.5%, Russian 1.3% |
| No author | 770,594 (14%) |
| Rows with an ISBN | 163,320 (3%): searching HathiTrust by ISBN finds few books |
| Search time | 18–150 ms for a title and author; "history of the united states" 1 s; **a search made only of the most common words ("the of and") 5–6 s** |

## Resolved questions

* **US-only volumes:** shown, with the note "Public domain only in the United States: it may not open elsewhere." (`us_only`, from rights `pdus`). 27% of the volumes are `pdus`, so leaving them out would have dropped a quarter of the collection.
* **Which volume is "the book":** one book per volume, but a catalog record with several copies that have the same volume label (for example Harvard and the New York Public Library both holding one book) is shown once, the copy with the first htid. Volumes with different labels all show. 5.35 M volumes become 4.42 M listed books.
* **Merging:** volumes of one catalog record merge into one work through the new identifier `hathitrust` (= `ht_bib_key`), then through shared OCLC numbers and ISBNs like the other sources. `normalize_isbn` returns None for the fake ISBN `9780000000002` (and its ISBN-10 form `0000000000`), so it neither merges nor can be searched for. Titles lose the part after ` / `, `, by ...` or `; by ...`; authors lose dates ("Austen, Jane, 1775-1817." becomes "Jane Austen").
* **Language filter:** MARC code in the index (`fre`), mapped to ISO 639-1 in the book. A language outside `normalize.py`'s table of 38 has no ISO code, so the book's language shows as unknown and the language filter cannot select it (the filter only accepts languages in the table). This is the real language filter that DOAB lacks.
* **Index size and engine:** SQLite with FTS5, 1.65 GB; no server needed. Postgres was not needed.
* **Removed volumes:** the daily files do not say. A new monthly file triggers a full rebuild (built beside the old file and swapped in), so removed volumes leave within a month. A volume whose row turns `deny` is removed the same day.

## Open questions

* **One work, many books.** A search for "Great Expectations" by Dickens returns one work with 20 HathiTrust books on page 1 (different libraries' editions of the novel); HathiTrust holds far more. It is correct but long. Options: show the first few and "show more", or one book per library, or rank volumes with a label last. Not decided.
* **Common-word searches.** A query made only of very common words takes 5–6 s (under the 12 s limit, but it uses a thread for that long). Done 2026-10-11: `HathiIndex.search` drops stopwords (`_STOPWORDS` in `hathitrust_index.py`: English articles and prepositions, plus the French, German, Spanish and Italian articles) from a field when it has any other word, so "the time machine" searches "time machine". A field made only of stopwords ("the of and") keeps them and is still slow, since there is nothing else to search. Tested on the sample index only; the 1.65 GB index is not built on this machine, so the new timing is unmeasured.
* **Titles of multi-volume sets.** Volume labels are shown ("v.2"), but the title of a set's volume is the set's title ("The writings of Charles Dickens"); the individual novel in a volume is not searchable.
* **Donation link.** HathiTrust is funded by its member libraries and has no public donation page that we could find (2026-10-11); the About page's donation link is its home page. Ask the project owner.
* **Mojibake.** A few titles in the file are already mis-encoded (Japanese text shown as `ã\x82\x84...`). We show them as given.
* **Jobs.** Nothing runs `hathitrust_update` yet. It needs a nightly schedule on the server (cron or similar) and about 2 GB of disk.
* **Python needs FTS5.** The `sqlite3` module of the Python used must be built with FTS5 (macOS and Debian builds are; if a server's is not, the index cannot be built).

## Tests

The tests that came first are listed in [backend/tests/README.md](backend/tests/README.md) (HathiTrust rows in the milestone table) and [app/test/README.md](app/test/README.md). Real rows for them are in [samples/hathitrust-hathifile-sample.tsv](samples/hathitrust-hathifile-sample.tsv). The in-app reader (step 6) has no tests yet.
