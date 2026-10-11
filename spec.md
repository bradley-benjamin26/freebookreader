# Free Book Reader

The Free Book Reader is an application to find and read free books available through different sources: DOAB (the Directory of Open Access Books), Open Library, LibriVox, Project Gutenberg, and HathiTrust. When possible, the material can be read within the app with a viewer, but when impossible, a user is directed to the resource at the target.

## Statement on Accessibility
The application must be accessibility forward and is expected to meet at least WCAG 2.2 AA. A blind or low vision user must be able to navigate the interface, access audiobooks, and have access to screen-reader support for print materials.

## Data Sources
See externalSources.md. API documentation for each source is in api_*name*.documentation.md (e.g., api_gutendex.documentation.md).

HathiTrust (source id `hathitrust`) is built (decision and build 2026-10-11, see decision_hathitrust.md and api_hathitrust.documentation.md). It has no search API, so the backend searches a local index built from HathiTrust's Hathifiles (bulk files with one row per volume, public-domain and open-license volumes only). The Bibliographic API is used only for lookups by ID. A HathiTrust book opens in HathiTrust's own reader (`babel.hathitrust.org`) through a link; the app does not read these books itself. Showing that reader inside the app (a WebView, or an iframe on web) is a later step that depends on HathiTrust's framing headers and terms, which are not checked yet.

## Audience

The app is for a general audience. These include:
* students
* researchers
* readers of all types
* listeners
* life-long learners

Because this includes public-domain and open access publications, it serves both an academic and general audience as open access is largely driven by academia.

## Out of scope
* There is no need for DRM or anything
* Does not enable users to provide a review

## User stories
* Find and access an out-of-copyright book.
* Find a book in French.
* Find and listen to an audiobook.
* Find a copyrighted book I can borrow from Open Library or access through open access.
* Perform research on a topic of interest.

## Features
* Search experience
    * Search across all targets
    * Search across select targets or just 1
    * View the results of the search
    * When a user performs a known-item search using a title and/or author and/or an identifier (i.e., ISBN), the user sees results only for that specific title
    * Open Library results include only books that can be read or borrowed right now (not print-disabled-only books, books with no ebook, or books whose copies are all on loan). Each links to the edition that can be read or borrowed, not the work page.
        * A title is found with or without its subtitle ("Moby Dick" finds "Moby-Dick; or, The Whale"), and a volume of the work counts as the work ("Les Misérables" finds "Les misérables Tome I: Fantine"). Study guides, summaries, notes and other books about the book are not returned unless the user searches for their full title (user decision 2026-10-10).
    * Select format (text/audio)
    * Provide title, author, and keyword searching
    * HathiTrust results include only volumes that anyone can read (`access = allow` in the Hathifiles: public domain and open licenses), found in a local index and not through a live search. Volumes that are public domain only in the United States are shown with a note that they may open only there. A catalog record can have many volumes (copies and volumes of a set); each shows its volume label and holding library. Each links to HathiTrust's reader.
* Reading experience
    * Dark and Light mode
    * Font size can increase and font style can change to accommodate readers' needs. Spacing can be configured.
    * Can bookmark in a book to mark where they left off. Until accounts exist, bookmarks are stored on the device only.
    * If a user is reading a book where there is a LibriVox recording, they can listen while reading (synced). If this becomes too hard, they could have the viewer and the player both display.
    * The default view is page-turner view but a user can choose to just have a plain, scroll view.
    * Read aloud: text-to-speech reads the book in the viewer, with the text highlighted as it is read. It uses a voice that matches the book's language. Speed can be changed. (Goal confirmed 2026-10-10.)
    * Save a book to the device to read offline. Supported in principle; the milestone is not decided. Open Library books cannot be saved because they open at the source. See decision_reader.md for what to check before enabling it.

## Data

### Data model
Books are modeled into a simple hierarchy. There are "books" which are the individual items from the different sources which are united under a work.

* Work
    * title
    * author
    * source(s)
    * source Id(s)
    * identifiers - ISBN, OCLC Number, etc
    * URL(s)
    * cover image
    * language
* book
    * title
    * author
    * language
    * format
    * number of pages
    * length of audio
    * source
    * identifiers
    * URL
    * cover image
    * release date, last update, credits, original publication (when the source gives them; today only Project Gutenberg does)
    * volume label (HathiTrust's `description`, e.g. "v.2") and holding library (HathiTrust only)

### Data Merging
Records are merged to create a work. First pass for matching is on ID (ISBN or OCLC Number). Next pass is exact title and author match. Final pass is fuzzy title and author match.

Rules:
- Records in different languages are never merged.
- Narrators and other non-author contributors are not used for matching.
- If a fuzzy match is ambiguous, do not merge. A duplicate is better than a false merge.
- A record with an unknown language only merges through a shared ISBN or OCLC number, never on title and author alone.
- A record with no author is never merged on title alone.
- ISBN-10s are converted to ISBN-13. Identifiers with a bad check digit are ignored.
- Chapters (DOAB lists them) are not books.
- HathiTrust data contains placeholder ISBNs (`9780000000002` and strings like `000000000061rub` appear on unrelated books). The ID pass ignores any ISBN that is not valid, and `9780000000002` explicitly.
- HathiTrust titles and authors are MARC strings ("Pride and prejudice / by Jane Austen", "Austen, Jane, 1775-1817.") and its languages are 3-letter MARC codes. They are normalized before matching (planned).

### Hierarchy
Work
 |
book

## Architecture

Mobile first and then web based, Dart/Flutter . I don't know what to use as a backend stack... I guess some kind of Python?

Will need a backend that calls the various APIs and manages the data to serve to the user. Will also need a system to provide Project Gutenberg access because it does not have a normal API but there is a client with a GitHub repo.

### Backend (decision)
A Python backend built with FastAPI, in `backend/`. It calls the five sources (Gutenberg through the self-hosted Gutendex; HathiTrust through a local index), merges the records into works, applies the 24-hour source-outage rule, and serves JSON to the Flutter app in `app/`. Endpoints: `GET /search`, `GET /sources` (content for the About pages), `GET /health`, and `GET /publications/gutenberg/<id>/manifest.json` with `GET /publications/gutenberg/<id>/<file>` (a Gutenberg EPUB as a Readium Web Publication, for the web reader). In `/search`, a Gutenberg book's `reading.publication` gives that manifest's path. There are no accounts and no endpoints that take personal data. The backend, not the app, talks to the sources. The contract is defined by the tests in `backend/tests/` (see its README).

### Testing (decision)
Tests are written before the code and fail until the feature exists. See `backend/tests/README.md`, `app/test/README.md` and `gutendex/books/tests.py` for the map from milestones to tests. Backend tests use `pytest` with mocked HTTP; app tests use `flutter test`, including Flutter's accessibility guidelines (contrast, tap target size, labels), 200% text size, 320px width and keyboard checks. These catch regressions but do not replace testing with a real screen reader. Usability testing of the About pages is manual.

### Reader (decision, provisional)
The reader is chosen by a spike, not yet by a decision. Plan: try `flutter_readium` (EPUB, PDF on mobile, TTS, reader preferences, on the Readium toolkits) first. If it fails the accessibility checks, fall back to `flutter_epub_viewer` plus a separate TTS plugin, or our own renderer. Audiobooks use `just_audio` and `audio_service`. The app talks to the reader through a `ReaderEngine` interface so the package can change. Built 2026-10-10: on web, Gutenberg books open in `flutter_readium` from the backend's manifest; elsewhere the app's own text renderer is used until Readium's native setup is done. Listen while reading shows the viewer and the player together; syncing text to a LibriVox recording needs alignment data we do not have. See decision_reader.md for the options, the spike checklist and the effect on the tests.

### Project Gutenberg access (decision)
Project Gutenberg is served by a self-hosted copy of [Gutendex](https://github.com/garethbjohnson/gutendex) (in `gutendex/`), a Django + Postgres app. It downloads Project Gutenberg's nightly catalog (metadata only, about 3 GB on disk) and exposes it as a JSON search API. Gutendex does not store book text; books are read from gutenberg.org through the links in each record. For the web reader, the backend downloads a book's EPUB from gutenberg.org the first time someone opens it, keeps it in a disk cache (2 GB by default; least recently used books are removed first) and serves it with a Readium manifest. Web needs this because gutenberg.org sends no CORS headers and the web reader cannot open an .epub file. The catalog must be refreshed on a schedule (nightly) with `manage.py updatecatalog`. Gutendex has no ISBN or other identifier search, so Gutenberg records can only be merged on title and author. See api_gutendex.documentation.md.

### HathiTrust access (decision and build 2026-10-11)
HathiTrust has no search API, so it is searched through a local index of its Hathifiles: one row per volume, loaded only when `access = allow` and the record is a book (not a serial), refreshed from the daily update files and rebuilt from the monthly full file (1.2 GB compressed). The Bibliographic API (`catalog.hathitrust.org/api/volumes/...`, works from our IP) is used only for lookups by ID; OAI-PMH is not used (a full harvest takes about 2 days and 10 GB). HathiTrust's reader and downloads (`babel.hathitrust.org`) are blocked for our IP, so books open in the user's browser at `https://babel.hathitrust.org/cgi/pt?id=<htid>`. Later, a WebView (mobile, desktop) or iframe (web, only if HathiTrust's headers allow it) could show that reader inside the app, as a third `ReaderEngine`; this waits for the checks listed in decision_hathitrust.md. Open: how to show volumes of one record, `pdus` (US-only) volumes, index size. See decision_hathitrust.md and api_hathitrust.documentation.md.

## UX

### Homepage

A homepage features a search box and maybe some example books. After accounts are added, saved books may display here.

After accounts are added, there is a link to an account view.

Typing a query and hitting submit directs the user to the search results page. Next to the box, a choice says what is searched: anything, title, author, subject or ISBN. A title, author or ISBN search shows results only for that item (known-item search). Free text that is a valid ISBN is searched as an ISBN. A search over 300 characters is not sent; the app says so.

### Search Results
The top of the page displays a search box with the user's query, enabling the user to edit their search.

The left side of the screen has some filter options. On mobile they display under the search box but before the listing of results.
The results are displayed in rows in a single column. Each listing has an image of the cover, author, title, source, and a way to access that book. Clicking on a record brings the user to a details page.

When a source is left out of a search, a notice above the results says so. The notice must match the reason. A source in an outage is skipped for up to 24 hours. A source that was only too slow is asked again on the next search, so its notice must not mention the 24 hours. The backend says why a source is missing (`skipped`: outage, timeout, busy, rejected, error), and the app words each case (fixed 2026-10-11).

### Details
The details page includes a full list of the book's metadata. Maybe this could include other information such as other books by the author or the following book in a series or something.

Project Gutenberg often has several eBooks of one work (Pride and Prejudice has two text editions and three audiobooks), and they merge into one work. So that the user can tell them apart, each book's card shows its eBook number, release date, last update, credits and original publication when they are known, as gutenberg.org does. See api_gutendex.documentation.md.

### Source About Pages
Each source has a page detailing what it is and how it works. Information about how to access it normally.

Includes a donation button for each source.

## Privacy
The goal is to limit data on the user. The first version has no accounts and collects no personal data. In a later update, a user can create an account with a username and password. This enables a user to access their account on their phone or on a computer/by browser. An email is optional.

## Milestones
- Unit tests are created for each feature. They fail by default. A milestone is not completed until it passes its associated unit tests.
- The application can run a search using the API for each target. Each is a milestone:
    - Project Gutenberg
    - LibriVox
    - DOAB
    - Open Library
- The homepage is constructed and passes accessibility testing
- The search page is constructed and passes accessibility testing
- Results from each target display correctly in the search results
- Search page passes accessibility test with search results displaying
- The about pages for the different services are created and pass usability testing
- The system that provides Project Gutenberg access is built and tested
- HathiTrust (built 2026-10-11, tests pass): the Hathifile index is built from `access = allow` book rows and kept up to date with the daily files; HathiTrust is searched like the other sources; its books link to the HathiTrust reader; its records are merged into works (with placeholder ISBNs ignored). Not scheduled yet: running the update nightly on the server.
- HathiTrust in-app reader (later, not scheduled): done only after the checks in decision_hathitrust.md pass
- Records from the different targets are merged into works following the Data Merging rules
- The viewer displays books from the sources that allow in-app reading, and other books link to the source
- The screen to read the book passes accessibility testing
- Bookmarks are saved on the device and restored when a book is reopened
- Listen while reading feature is constructed and passes accessibility testing
- The reader spike is done and the reader package is chosen (decision_reader.md)
- Read-aloud (TTS) is constructed and passes accessibility testing

## Non-functional requirements
- Source outage - do not return results and stop returning results for a 24 hour period. A timeout is not an outage: a source that is too slow is left out of that search only and is asked again on the next one. A source that is still working on several earlier searches (4 at most) is not asked again until one finishes; it is left out of that search only. Only the source's own failures start an outage (it cannot be reached, it answers with a server error, or its answer cannot be read). When the source turns down our request (a 4xx answer) or our own code fails, the source is left out of that search only. Search input is limited (300 characters per field, page 1000 at most) so that no request can make a source fail.

- There are no rate limits because use is expected to be very low.

- Search results should appear within 15 seconds. The backend waits at most 12 seconds for the sources, so merging, the network and drawing fit in the rest.

- Book should display in viewer in under a minute.

## Risks
- The reader package (flutter_readium) is pre-1.0 and its screen-reader behavior is unproven until the spike.
- The backend's EPUB cache downloads books from gutenberg.org. Project Gutenberg asks automated tools to use a mirror; if traffic grows, point `FBR_GUTENBERG_URL` at a mirror.
- A source changes or removes its API, or its terms of use change.
- Project Gutenberg has no standard API, so its access system depends on a third-party client.
- Fuzzy matching can wrongly merge or fail to merge records.
- A source being down limits results for 24 hours, so search may look incomplete.
- DOAB's REST search rejects our IP address, so DOAB is searched through OpenSearch plus one OAI-PMH lookup per result (about 1.5 s). DOAB cannot filter by language, so a search in another language may find few DOAB books. See api_doab.documentation.md.
- HathiTrust: its book reader, page text and PDFs (`babel.hathitrust.org`) return a Cloudflare challenge or "Blocked from HathiTrust" to our IP, so the backend cannot read HathiTrust books; users open them in HathiTrust's reader. Whether that reader can be shown in an iframe or WebView, and whether HathiTrust's terms allow it, is unverified. Its accessibility with a screen reader is outside our control. Some books can be downloaded only by a signed-in user (per the project owner; not verified). See api_hathitrust.documentation.md and decision_hathitrust.md.
- HathiTrust's local index is a copy of its data: the full file is 1.2 GB compressed; the index has 5.35 million volumes and is 1.65 GB (measured 2026-10-11). It is only as fresh as our last import, and the daily files do not say which volumes were removed, so a new monthly file rebuilds it.
- HathiTrust `pdus` volumes (public domain in the US only) may open only for users in the US; we cannot tell where a user is.
- HathiTrust: a title search can return one work with 20 books (different libraries' editions) on a page, and HathiTrust holds more; how to shorten that is not decided (decision_hathitrust.md).
- HathiTrust: stopwords ("the", "of", "and", "de", "der", ...) are left out of a title, author or `q` that has other words; a search made only of them ("the of and") still takes 5–6 s. Ordinary searches take under 150 ms.
- HathiTrust: the index is refreshed by `python -m app.hathitrust_update`, which nothing runs on a schedule yet; until it has run once, HathiTrust is skipped in every search.
- HathiTrust has no public donation page that we could find, so its About page's donation button links to its home page.
- HathiTrust's catalog has few ISBNs (3% of volumes) and no subjects, so ISBN searches rarely find a HathiTrust book and a keyword search only matches titles and authors.
- Open Library's work records span many languages, so they often cannot be merged with other sources' records.
- Most DOAB books' PDFs are in the OAPEN Library, whose book pages and PDF files are behind a bot check that browsers pass but HTTP clients do not. The planned workaround is for the user's device to fetch the PDF through an in-app WebView. This is unverified until the reader spike. On web, these books open in an iframe or a new tab. Some publisher links that end in `.pdf` return a web page, so the reader must fall back to the DOAB page. See api_doab.documentation.md and decision_reader.md.
- LibriVox has no keyword search. Free text is sent as a title-prefix search, so it finds only recordings whose title starts with the query. See api_librivox.documentation.md.
- LibriVox's server can be slower than our search limit (15 s then, 12 s since 2026-10-11). On 2026-10-10 every API request took 14–16 s to answer (even `limit=1` without `extended`), and the librivox.org home page did not load within 40 s. Gutenberg and archive.org answered in under 0.4 s. LibriVox was therefore left out of most searches, and every search took the full 15 s. Not decided:
    - wait and recheck, since this may be temporary on LibriVox's side;
    - a separate timeout per source;
    - return the sources that are ready and add slower ones' results when they arrive (changes the API and the app);
    - archive.org's `librivoxaudio` collection as a fallback (a new source, to be documented like the others).
- Open Library's language filter (`language=<MARC code>`) is not in its documentation and could change.
- Open Library's live loan status (`/availability/v2`) is not in its documentation either. If it fails, Open Library results are shown without the loan check, so a book whose copies are all on loan can appear.
- An Open Library ISBN search finds a book only if that ISBN's edition can be read or borrowed. If another edition of the same work can be borrowed, it is not found by that ISBN.

## Saving this for future use. Do not develop. Don't even bother reading, Claude

 HathiTrust api
Note: HathiTrust is used only for full-text, out-of-copyright content where the whole book can be provided
Api documentation: https://www.hathitrust.org/member-libraries/resources-for-librarians/data-resources/bibliographic-api/
The following is incomplete to do later.
Data model
* User
    * Username
    * Password
    * name
    * email
    * hasFavoriteBooks
    * hasFavoritePassages


* Account experience
    * User can update their name, email, or change their password
    * Can view saved books
    * Can view passages they've highlighted (with metadata such as book's title, author, and page number when available)
    * Features a button to copy the passage along with (*Book Title*, *Author*, and *Page Number*) for the user.
        * User can highlight passages that are saved to their account

- The user account feature is constructed and passes accessibility testing
    - Account creation
    - Authentication
    - Saved books list display

    ## Features to add in an update
* Account
* Favoriting Books
