# Flutter app tests (written before the code)

All 445 pass against `app/lib/` (2026-10-11).

```bash
cd app
flutter pub get
flutter test                       # everything
flutter test test/reader_test.dart
```

The reader page talks to a `ReaderEngine` (see [decision_reader.md](../../decision_reader.md)). `reader_test.dart` tests the page's controls against `FakeReaderEngine` (`helpers/fakes.dart`). How the book is drawn is the engine's job: `text_engine_test.dart` covers our own renderer (`TextReaderEngine`, used everywhere but web), and `readium_engine_test.dart` covers which engine is chosen and how settings become Readium preferences. flutter_readium itself only runs in a browser or on a phone, so it is checked by hand with the spike checklist in decision_reader.md. `read_aloud_test.dart` covers read aloud; offline-saving tests do not exist yet.

Change a test and this README together.

### Test changes made while building the app (2026-10-10)

- `bookmark_store_test`: the sorted key list is `['doab:9', 'gutenberg:1']` (the test sorted, then expected the unsorted order).
- `reader_test`: imports `helpers/fakes.dart` and `bookmark_store.dart` (it used `longText` and `Bookmark` without them). The PDF file name is `9783847408130.pdf`, as in the fixture (`9783847406334` is the print ISBN).
- `helpers/test_app.dart` `openDetails`: scrolls a result into view before tapping it. On a phone the third result is below the fold.
- `search_results_test` (progress indicator) and `reader_test` (`startLoading`): pump an extra frame after pushing a page. Flutter keeps a pushed route offstage for its first frame, and its semantics appear once the transition ends.

### Code review fixes (2026-10-11, `REVIEW-2026-10-11.md`)

- **Search by field (#9, #14):** the search box has a "Search in" choice (`search-in` group; `search-in-anything|title|author|subject|isbn` ChoiceChips). `SearchQuery.withTerm(field, text)` sets one text field and keeps the filters; "anything" that is a valid ISBN (`util/isbn.dart`, `isbn_test`) is sent as `isbn`. The example books on Home are title searches. A search over 300 characters is not sent: `search-too-long` (live region). A 4xx from the server (`SearchException.statusCode`, `isRejected`) says "This search can't be run", not "Check your connection". The chips push the first results down on a phone, so tests that tap a result below the fold call `ensureVisible` first.
- **Why a source is missing (#13):** `SearchResponse.skipped` (`SkippedSource(source, reason)`, `SkipReason` outage|timeout|busy|rejected|error); without it, every source in `unavailable_sources` is taken as an outage. `unavailable-notice` mentions 24 hours only for outages.
- **Identifiers (#15):** the details page keeps all identifiers behind one button, `identifiers-toggle` ("Show identifiers" / "Hide identifiers", closed by default, no button when a work has none; user decision 2026-10-11). Once open it shows 5 identifiers of a kind, then `show-all-<kind>` ("Show all 1000 ISBNs").
- **Verse (#10):** `htmlParagraphs` keeps `<br>` as a line break (`\n` inside the paragraph) and takes text from every block element (`content_test`). `BookText` makes the word after a line break start with `\n`.
- **Pagination (#11):** `paginate` lays the book out once, a paragraph at a time (`Paginator`, `pagination_test`). `TextReaderEngine` runs it one slice (8 ms) per frame. Until the pages are counted it shows `reader-page-pending` (the text from the reader's place, clipped) and `page-indicator` says "N% read"; turning pages does nothing yet. The final page is `reader-page-text`. Tests that need to see the slices pump single frames: under `pumpAndSettle` it is over at once.
- **Audio (#12, #18):** `AudioEngine.play` throws `AudioException`; `positionStream` carries the file (`AudioPosition`) and `statusStream` says playing/completed (`AudioStatus`). The controller ignores positions of other files, moves to the next chapter when one ends, and shows `audio-error` (live region) with `audio-retry` when playback fails. `FakeAudioEngine` has `failNext`, `emitStatus`, `emitPosition`, and replays its last position to new listeners, as just_audio does.
- **Links (#22):** `LauncherUrlOpener` opens only `http`/`https` links with a host; others return false (`url_opener_test`). The pages do not yet tell the user.
- **Headings and labels (#23):** the two Home section titles are headings; the language filter is named "Language" (`accessibility_test`).

### Main review fixes (2026-10-11, `REVIEW-2026-10-11-main.md`)

- **Audio (#16, #17):** `audio_engine_test` tests the real `JustAudioEngine` with a subclassed `AudioPlayer` whose load waits (`JustAudioEngine(player: ...)`): a pause, or closing the engine, while a file loads means it does not start. `audio_player_test`: Play after the last chapter ended, and choosing the chapter already loaded, start from 0:00 (`from: Duration.zero`); Play after Pause goes on from where it stopped.
- **Read aloud (#18):** `FakeSpeechEngine.holdVoices` makes the voice lookup wait; a Stop or closing the book meanwhile means nothing is spoken (`read_aloud_test`).
- **Bookmarks (#24):** `TestEnv.create(bookmarks: ...)` takes a store; `HeldBookmarkStore` (in `reader_test`) holds its writes. A second tap while a write is pending is ignored, and the button says what is stored.
- **Search box (#22):** it keeps what is typed, and the field chosen, when the window crosses the 840 px layout width (`search_results_test`).
- **Readium (#26):** `FakeReadium` (in `readium_engine_test`) holds `openPublication`. A book that opens after its reader closed is closed, and the next reader's book opens only after that (Readium has one publication for the app, so opening and closing go through one queue).
- **Chinese and Japanese (#19):** `BookText` makes each CJK character a word and splits runs of more than 40 characters with no space (Thai, long links) between letters (grapheme clusters); `spaceBefore` says where the text had a space, so `text()` adds none between them (`pagination_test`, and `text_engine_test` "a long Chinese paragraph is split over pages").
- **Paragraph spacing (#23):** the page-turner view uses the setting's real size (`paragraphSpacing × fontSize` pixels, as the scroll view does), not "blank line or none". `paginate`/`Paginator` take `paragraphGap`; `pageSpan(book, start, end, paragraphGap:, mark:, markStyle:)` draws a page, with the empty line between paragraphs in its own size. So `reader-page-text` is a `Text.rich` when it holds more than one paragraph or a highlighted word, and `pageText` in `text_engine_test` reads `data ?? textSpan.toPlainText()`.
- **Scroll view (#20, #21):** the place is the first word of the line at the top, not of the paragraph; a font, size, spacing or width change reopens the list at that word (the list is keyed by its layout, since a list given a new controller keeps its pixel offset). In `read_aloud_test`, reading aloud in scroll view starts at that line ("speaks from the line at the top").

### HathiTrust (2026-10-11)

- `hathitrust` is the fifth source: `sourceIds`, `sourceName`, the Home sentence, the filter chips and its About page (fixture `sources.json`). Tests that listed the four sources, or tapped three chips to leave one selected, include it.
- `Book` has `volume`, `library` and `usOnly` (`models_test`). The details page (`details_page_test`, group "HathiTrust volumes") shows "Volume v.1 · Harvard University" on the edition line (no "eBook #": only Gutenberg numbers its books), says the book "opens in the HathiTrust reader in your web browser", marks a `usOnly` volume ("Public domain only in the United States: it may not open elsewhere."), and the book button opens the reader link through the URL opener. A work with more than 3 HathiTrust volumes shows the first 3 and a "Show all N HathiTrust volumes" button (`show-all-hathitrust`), which shows the rest (group "many volumes"); other sources are never cut. HathiTrust books are external, so the label is "View ... at HathiTrust" (`format_test`).

### ReaderEngine (2026-10-10)

- `reader_test` was rewritten against `FakeReaderEngine`: it checks what the page asks of the engine (open with the book's reading options, settings and bookmark position; next/previous; each settings change) instead of the drawn text. New: the engine is disposed on close, retry reuses the engine, a book no engine can show offers the source without retry, the indicator shows "N% read" when the engine has no page numbers, the left arrow does nothing on the first page, arrows are left to the engine in scroll view, and an old bookmark without a locator opens at its progress.
- The renderer-specific tests moved to `text_engine_test` (pagination, page count vs font size, scroll view and keeping the place across views, text styles, paragraph spacing, word locators). New there: a font size change keeps the first words on screen, a PDF from the loader is an error, and a scroll-view bookmark restores in page view.
- `TestEnv.create(textEngine: true)` opens books in the real `TextReaderEngine` fed by `FakeContentLoader`; otherwise books open in a `FakeReaderEngine` (`env.engines.last`). The reader contrast and text-scale tests in `accessibility_test` use the text engine so the book text is checked too.
- `audio_player_test` and `details_page_test` look for the engine's view (`fake-reader-view`, `reader-surface`) and the engine's open call instead of `reader-page-text` and the content loader.
- `bookmark_store_test`: a bookmark keeps the engine's locator; one saved without a locator still loads.
- `reader_test`: the book view is covered (`reader-click-shield`, a `PointerInterceptor`) while the settings sheet is open. On web Readium's iframe otherwise took every click on the sheet (found by hand in Chrome, 2026-10-10).

### Read aloud (2026-10-11)

- `read_aloud_test.dart`: `BookText.wordRange`, `matchVoiceLanguage` and `ttsRate`; the controls on the reader page against `FakeReaderEngine.readAloud` (`FakeReadAloud`): the bar (`read-aloud-bar`, `-toggle`, `-stop`, `-slower`, `-faster`, `-speed`, `-error`) exists only when the engine can read aloud and the book is open, its button is named "Read aloud", "Pause reading aloud" or "Resume reading aloud", the speeds go 0.5 to 2 and stop at the ends, errors are a live region, a recording and read aloud pause each other, and the tap target and label guidelines hold at 320 px and text scale 2. Then `TextReaderEngine` with `FakeSpeechEngine` (`TestEnv.create(textEngine: true)` has `env.speech`; `speech: false` leaves it out): speaks from the first word on screen in the book's language (English if unknown), says when there is no voice, highlights the word spoken (page colours swapped), goes on chunk by chunk without gaps or repeats, turns the page, restarts on the new page when the reader turns it, stops at the end of the book, pauses and resumes from the word, stops, changes speed from the word being spoken, reports a speech failure and can retry, stops when the book closes, keeps its place through a font size change, and in scroll view highlights in the paragraph and scrolls to it.
- `FakeReaderEngine` has `readAloud` (null unless a test sets it; `FakeReaderEngines.readAloud = true` sets it on every engine). `ReaderEngine.readAloud` is a new member of the interface.
- Not tested: Readium's TTS and the device's real voices (decision_reader.md checks 5 and 9, by hand), and the Android `TTS_SERVICE` entry in `AndroidManifest.xml` that Android 11+ needs.

### Persona round one fixes (2026-10-27)

- `models_test` audio choice: a recording with chapters or a length is chosen before a bare one (Gutenberg audio eBooks have neither), in `bestBook` and `recordingsFor`. `Book.hasAudioDetails` is new.
- `audio_player_test` unknown lengths: a recording or chapter with no length shows "<time> played · length unknown" (`position-elapsed`, not a live region) instead of a slider whose total grew with the time played; a recording with no chapters has no Chapters heading. No existing test changed.
- `reader_test` last place, `bookmark_store_test`: the reader saves the last place on every position (`lastplace:<book key>`, apart from the bookmark, not in `savedBookKeys`) and reopens there; else at the bookmark, else at the start. A damaged last place loads as none. The bookmark button still shows only the manual bookmark. No existing test changed: none read on and then reopened expecting the bookmark.
- `search_results_test` "the Title choice stays after Audio is chosen and after returning from a book": pins that the search field survives a filter change and a trip to the reader. It passed when written, so Jordan's reset was likely an older build; no code changed.

## Milestones to tests

| Milestone | Tests |
|---|---|
| Homepage built and passes accessibility testing | `home_page_test.dart`, `accessibility_test.dart` |
| Search page built and passes accessibility testing, also with results | `search_results_test.dart`, `accessibility_test.dart` |
| Results from each target display correctly | `search_results_test.dart`, `details_page_test.dart`, `models_test.dart` |
| About pages for the sources | `source_about_test.dart` (usability testing is manual) |
| Viewer shows in-app sources, others link to the source | `details_page_test.dart`, `reader_test.dart` |
| Reading screen passes accessibility testing | `reader_test.dart`, `accessibility_test.dart` |
| Bookmarks and the last place saved on the device and restored | `bookmark_store_test.dart`, `reader_test.dart` (bookmarks, last place) |
| Read aloud (TTS) | `read_aloud_test.dart` |
| Listen while reading | `audio_player_test.dart` (**no text/audio syncing yet**; see that file) |
| Book displays in under a minute | `reader_test.dart` (one minute to display) |
| Search results within 15 s | `search_api_test.dart` (client gives up at 20 s; backend limit is 15 s) |
| Dark/light, font size and style, spacing, page-turner vs scroll | `reader_settings_test.dart`, `reader_test.dart` |

## The contract the tests expect

```
app/lib/
  app.dart                     FreeBookReaderApp({api, bookmarks, settingsStore, readerEngine,
                                 urlOpener, audio, themeMode, pdfViewBuilder})   MaterialApp(title: 'Free Book Reader')
                               readerEngine: ReaderEngineFactory = ReaderEngine? Function(ReadingOptions)
  models/models.dart           Book, Chapter, Work, ReadingOptions, SourceInfo, SearchResponse(+ skipped), SkippedSource, SkipReason,
                                 SearchQuery(withTerm, searchedText), SearchField, enums BookFormat, Access, ReadingMode. const constructors on SearchResponse.
                                 ReadingOptions.publication: backend path of a Gutenberg book's Readium manifest
                                 for the web reader, or null (also null when the field is missing).
  api/search_api.dart          abstract SearchApi {search, sources}; HttpSearchApi(client, baseUrl); SearchException(isTimeout, statusCode?; isRejected for a 4xx)
  storage/bookmark_store.dart  Bookmark(progress 0..1, locator?, const); BookmarkStore(SharedPreferences): load/save/remove/savedBookKeys (`bookmark:`), loadLastPlace/saveLastPlace (`lastplace:`)
  reader/reader_settings.dart  ReaderSettings (const, clamped), ReaderSettingsStore, ReaderTheme, ReaderFont, ViewMode
  reader/reader_engine.dart    ReaderEngine {open(book, settings, at), position, positions, next, previous, goTo,
                                 apply, buildView(context, {locale}), dispose}; ReaderPosition(progress, locator?, page?, pageCount?,
                                 atStart, atEnd); ReaderOpenException; ReaderEngineFactory
  reader/text_engine.dart      TextReaderEngine(ContentLoader): our own renderer; locator "word:<index>"
  reader/engines.dart          chooseReaderEngine(book, web, backend, loader), backendUrl(backend, path)
  reader/readium_engine.dart   ReadiumReaderEngine(manifest Uri), epubPreferences(settings), cssFontStack(font)
  reader/content.dart          BookContent (TextContent(paragraphs) | PdfContent(url)), ContentLoader, ContentLoadException
  services/url_opener.dart     UrlOpener.open(Uri); LauncherUrlOpener opens http(s) only
  services/audio_engine.dart   AudioEngine.play/pause/seek/positionStream/statusStream/dispose; JustAudioEngine({player}); AudioException,
                                 AudioPosition(url, position), AudioStatus(url, playing, completed)
  util/isbn.dart               looksLikeIsbn(text)
  util/format.dart             formatDuration, formatAuthors, languageName, sourceName, actionLabel
```

Also in `lib/` (not part of the test contract): `main.dart` (real services; backend address from
`--dart-define=BACKEND_URL=...`, default `http://localhost:8000`), `ui/` (pages), `reader/pagination.dart`
(our own renderer), `reader/settings_sheet.dart`, `ui/audio_player.dart` (player shared by the
audiobook page and the reader).

Everything outside the app (HTTP, shared preferences, audio, launching URLs, loading book text) is
injected so tests can fake it.

### Widget keys the tests look for

- **Home:** `home-heading`, `search-field` (semantic label "Search books"), `search-submit` ("Search"), `search-in` (group "Search in"), `search-in-anything|title|author|subject|isbn`, `search-too-long` (live region), `example-books` (ActionChips), `about-link-<sourceId>`
- **Results:** `results-page`, `results-heading`, `result-count` (live region), `filters`, `filter-source-<id>`, `filter-format-all|text|audio`, `filter-language`, `result-<workId>`, `cover`, `open-<workId>`, `searching`, `no-results`, `search-error`, `retry`, `unavailable-notice` (live region)
- **Details:** `details-page`, `details-title`, `details-cover`, `details-metadata`, `identifiers-toggle`, `show-all-<identifierKind>`, `book-<source>:<id>`, `open-<source>:<id>`, `source-link-<source>:<id>`
- **About:** `about-page`, `about-title`, `about-description`, `about-how-it-works`, `about-how-to-access`, `about-reading-note`, `donate` ("Donate to <name>"; not shown for HathiTrust, whose `donation_url` is null), `visit-website`, `about-error`
- **Reader:** `reader-page`, `reader-title`, `reader-surface` (holds the engine's view), `reader-click-shield` (covers the view while the settings sheet is open), `page-indicator` ("Page 3 of 12", or "29% read" when the engine has no page numbers; live region), `next-page`, `previous-page`, `bookmark-button`, `loading-book`, `load-timeout`, `load-error`, `retry`, `open-external`, `pdf-viewer`
- **Our own renderer (TextReaderEngine):** `reader-page-text` (a `Text` with `data`, or a `Text.rich` with several paragraphs or a highlight), `reader-page-pending` (while pages are counted), `reader-scroll`, `reader-paragraph-<i>`. **FakeReaderEngine:** `fake-reader-view`
- **Reader settings:** `reader-settings-button`, `reader-settings`, `settings-close`, `theme-light|dark`, `font-increase|decrease` (step 2), `font-size-value`, `font-<serif|sansSerif|monospace|dyslexiaFriendly>`, `setting-line-height|letter-spacing|paragraph-spacing` (sliders named "Line spacing", "Letter spacing", "Paragraph spacing"), `view-page-turner|scroll`
- **Audio:** `audio-page`, `audio-title`, `audio-player`, `play-pause` ("Play"/"Pause"), `skip-back`/`skip-forward` (30 s), `position-slider` ("Playback position"), `position-elapsed` (shown instead of the slider when the length is unknown), `chapter-<i>`, `audio-error` (live region), `audio-retry`

### Behavior notes

- A bookmark is a fraction (`progress`) of the way through the book, so it survives a change of font size or view mode, plus the engine's `locator` for the exact place. The page opens the engine at the bookmark; an engine that cannot read the locator uses the progress.
- The results-page button for a work goes to the best way in: read in app, else listen, else open at the source.
- Each book's card on the details page shows its edition details when known (added 2026-10-10): "eBook #1342 · Released June 1, 1998 · Last updated September 29, 2026", "Original publication: …" and "Credits: …". Only Project Gutenberg gives them; they tell apart several Gutenberg eBooks of one work. Dates spell out the month (`formatDate`). Missing or unreadable values show nothing (`models_test`, `details_page_test`, `format_test`). The fixture's `gutenberg:1342` has them; the two-editions test adds a `gutenberg:42671` to its own copy of the response.
- `Image` widgets in tests get no network; give them an `errorBuilder` and a `semanticLabel` (or `excludeFromSemantics` for decoration).
- Bookmark and settings changes are shown with a SnackBar ("Bookmark saved", "Bookmark removed").
