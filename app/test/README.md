# Flutter app tests (written before the code)

All 254 pass against `app/lib/` (2026-10-10).

```bash
cd app
flutter pub get
flutter test                       # everything
flutter test test/reader_test.dart
```

**Provisional:** `reader_test.dart` assumes the app draws the book text itself. The reader package has not been chosen (see [decision_reader.md](../../decision_reader.md)), and about 40 of those tests will move to a fake `ReaderEngine` once it is. TTS and offline-saving tests do not exist yet.

Change a test and this README together.

### Test changes made while building the app (2026-10-10)

- `bookmark_store_test`: the sorted key list is `['doab:9', 'gutenberg:1']` (the test sorted, then expected the unsorted order).
- `reader_test`: imports `helpers/fakes.dart` and `bookmark_store.dart` (it used `longText` and `Bookmark` without them). The PDF file name is `9783847408130.pdf`, as in the fixture (`9783847406334` is the print ISBN).
- `helpers/test_app.dart` `openDetails`: scrolls a result into view before tapping it. On a phone the third result is below the fold.
- `search_results_test` (progress indicator) and `reader_test` (`startLoading`): pump an extra frame after pushing a page. Flutter keeps a pushed route offstage for its first frame, and its semantics appear once the transition ends.

## Milestones to tests

| Milestone | Tests |
|---|---|
| Homepage built and passes accessibility testing | `home_page_test.dart`, `accessibility_test.dart` |
| Search page built and passes accessibility testing, also with results | `search_results_test.dart`, `accessibility_test.dart` |
| Results from each target display correctly | `search_results_test.dart`, `details_page_test.dart`, `models_test.dart` |
| About pages for the sources | `source_about_test.dart` (usability testing is manual) |
| Viewer shows in-app sources, others link to the source | `details_page_test.dart`, `reader_test.dart` |
| Reading screen passes accessibility testing | `reader_test.dart`, `accessibility_test.dart` |
| Bookmarks saved on the device and restored | `bookmark_store_test.dart`, `reader_test.dart` (bookmarks) |
| Listen while reading | `audio_player_test.dart` (**no text/audio syncing yet**; see that file) |
| Book displays in under a minute | `reader_test.dart` (one minute to display) |
| Search results within 15 s | `search_api_test.dart` (client gives up at 20 s; backend limit is 15 s) |
| Dark/light, font size and style, spacing, page-turner vs scroll | `reader_settings_test.dart`, `reader_test.dart` |

## The contract the tests expect

```
app/lib/
  app.dart                     FreeBookReaderApp({api, bookmarks, settingsStore, contentLoader,
                                 urlOpener, audio, themeMode, pdfViewBuilder})   MaterialApp(title: 'Free Book Reader')
  models/models.dart           Book, Chapter, Work, ReadingOptions, SourceInfo, SearchResponse, SearchQuery,
                                 enums BookFormat, Access, ReadingMode. const constructors on SearchResponse.
                                 ReadingOptions.publication: backend path of a Gutenberg book's Readium manifest
                                 for the web reader, or null (also null when the field is missing).
  api/search_api.dart          abstract SearchApi {search, sources}; HttpSearchApi(client, baseUrl); SearchException(isTimeout)
  storage/bookmark_store.dart  Bookmark(progress 0..1, const); BookmarkStore(SharedPreferences)
  reader/reader_settings.dart  ReaderSettings (const, clamped), ReaderSettingsStore, ReaderTheme, ReaderFont, ViewMode
  reader/content.dart          BookContent (TextContent(paragraphs) | PdfContent(url)), ContentLoader, ContentLoadException
  services/url_opener.dart     UrlOpener.open(Uri)
  services/audio_engine.dart   AudioEngine.play/pause/seek/positionStream/dispose
  util/format.dart             formatDuration, formatAuthors, languageName, sourceName, actionLabel
```

Also in `lib/` (not part of the test contract): `main.dart` (real services; backend address from
`--dart-define=BACKEND_URL=...`, default `http://localhost:8000`), `ui/` (pages), `reader/pagination.dart`
and `reader/settings_sheet.dart` (our own renderer), `ui/audio_player.dart` (player shared by the
audiobook page and the reader).

Everything outside the app (HTTP, shared preferences, audio, launching URLs, loading book text) is
injected so tests can fake it.

### Widget keys the tests look for

- **Home:** `home-heading`, `search-field` (semantic label "Search books"), `search-submit` ("Search"), `example-books` (ActionChips), `about-link-<sourceId>`
- **Results:** `results-page`, `results-heading`, `result-count` (live region), `filters`, `filter-source-<id>`, `filter-format-all|text|audio`, `filter-language`, `result-<workId>`, `cover`, `open-<workId>`, `searching`, `no-results`, `search-error`, `retry`, `unavailable-notice` (live region)
- **Details:** `details-page`, `details-title`, `details-cover`, `details-metadata`, `book-<source>:<id>`, `open-<source>:<id>`, `source-link-<source>:<id>`
- **About:** `about-page`, `about-title`, `about-description`, `about-how-it-works`, `about-how-to-access`, `about-reading-note`, `donate` ("Donate to <name>"), `visit-website`, `about-error`
- **Reader:** `reader-page`, `reader-title`, `reader-surface`, `reader-page-text` (a `Text` with `data`), `reader-scroll`, `reader-paragraph-<i>`, `page-indicator` ("Page 3 of 12", live region), `next-page`, `previous-page`, `bookmark-button`, `loading-book`, `load-timeout`, `load-error`, `open-external`, `pdf-viewer`
- **Reader settings:** `reader-settings-button`, `reader-settings`, `settings-close`, `theme-light|dark`, `font-increase|decrease` (step 2), `font-size-value`, `font-<serif|sansSerif|monospace|dyslexiaFriendly>`, `setting-line-height|letter-spacing|paragraph-spacing` (sliders named "Line spacing", "Letter spacing", "Paragraph spacing"), `view-page-turner|scroll`
- **Audio:** `audio-page`, `audio-title`, `audio-player`, `play-pause` ("Play"/"Pause"), `skip-back`/`skip-forward` (30 s), `position-slider` ("Playback position"), `chapter-<i>`

### Behavior notes

- A bookmark is a fraction (`progress`) of the way through the book, so it survives a change of font size or view mode.
- The results-page button for a work goes to the best way in: read in app, else listen, else open at the source.
- `Image` widgets in tests get no network; give them an `errorBuilder` and a `semanticLabel` (or `excludeFromSemantics` for decoration).
- Bookmark and settings changes are shown with a SnackBar ("Bookmark saved", "Bookmark removed").
