# Decision: HathiTrust

Status: **decided 2026-10-11** for search and for the first version of reading. **Not built.** There are no tests yet; per the test-first rule they come before the code. Facts come from curl tests on 2026-10-11 (see [api_hathitrust.documentation.md](api_hathitrust.documentation.md)).

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

## Open questions

* **US-only volumes.** `pdus` rows (public domain in the US only; 12,222 of 42,085 `allow` rows in the 2026-10-10 update file) may be search-only outside the US, and the `access` column does not say so. Options: show them with a note ("may be available only in the United States"), or leave them out. We cannot tell where a user is without collecting data. Recommendation: show them with the note.
* **Which volume is "the book".** A catalog record has many volumes (copies and volumes of a set). Proposal: one `book` per volume, grouped under the work, showing the volume label and holding library like the Gutenberg eBook cards. A work with 40 copies of one edition would be noisy; consider showing one copy per record and the rest on request.
* **Merging.** Hathifile rows carry ISBN and OCLC numbers, so they can merge by ID. Many ISBNs are fake (`9780000000002` appears on unrelated books). The ID pass must ignore it, as it already ignores bad check digits. Author strings are MARC style ("Austen, Jane, 1775-1817."); titles include "/ by …". Both need normalizing first.
* **Language filter.** The file gives MARC 3-letter codes; map them to ISO 639-1. This is the real language filter that DOAB lacks.
* **Index size and engine.** Not measured: we did not download the full file. Plan to count the `allow` rows first. Postgres (already used by Gutendex) or SQLite FTS5 are candidates. Decide after the count.
* **Removed volumes.** The file list has no deletion file; how removals appear in the update files is unknown. A monthly rebuild from the full file would clean them up.

## Effect on the tests and milestones

New tests are needed before any code (and in their READMEs): a Hathifile parser, the `allow` filter, the update/rebuild job, the language-code mapping, the source adapter in `/search`, the merge rules for fake ISBNs, and the app's link-out. These are listed as milestones in [spec.md](spec.md).
