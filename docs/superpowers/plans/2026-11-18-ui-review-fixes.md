# UI Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 18 findings of the 2026-11-18 UI review: the reader follows dark mode, covers load on web, the web reader starts at the book and shows its controls and contents, and the search, results, details, audio, About and Home pages get easier to scan.

**Architecture:** Almost everything is in the Flutter app (`app/lib`); one backend change de-duplicates author names when works merge (`backend/app/merge.py`), and one CSS override in `app/web/index.html` corrects Readium's view height. No new packages: the title font is bundled as an asset.

**Tech Stack:** Flutter 3.47.5 (web/CanvasKit, Material 3), flutter_readium 0.6.1, FastAPI backend (pytest).

**Spec:** `docs/ui-review-2026-11-18.md` (finding numbers below refer to it).

## Global Constraints

- Test first. If a test changes, change `app/test/README.md` (or `backend/tests/README.md`) in the same commit.
- Run the tests: `cd app && flutter test`; `cd backend && source venv/bin/activate && python -m pytest`. Both must pass before every commit.
- Keep existing widget keys unless a task says otherwise; tests and the Playwright walk depend on them.
- No new pub or pip dependencies. The font is an asset (`app/assets/fonts/`), with its OFL licence file next to it.
- WCAG 2.1 AA: every new control has an accessible name; at 200% text on `smallPhone` nothing overflows (`tester.takeException()` is null).
- UI copy is sentence case, no trailing arrows.
- `app/web/readiumReader.js` is a copy of the package's file and stays unedited; overrides go in `app/web/index.html`.

## Decisions taken in this plan (change before executing if you disagree)

- Result cards drop the source list line ("Project Gutenberg, HathiTrust, …"); the details page already shows "Available from". The which-copy line (`bookSummary`) and the access note from persona round one stay, now at `bodyMedium`, the which-copy line cut to one line.
- "Search in" becomes one dropdown on every width (one code path), not chips.
- The reader's colour choice gets a third option, "Auto" (the new default). A saved `light` stays light. The app isn't released, so no migration of stored settings.
- The details page gets no blurred cover backdrop: with covers drawn as HTML `<img>` elements on web (Task 3), Flutter can't filter them.

## Review Focus

- Someone who chose "Light" in dark mode keeps a light reader (Task 2 test `an explicit Light stays light in dark mode`).
- The system switches to dark while a book is open, and the reader follows (Task 2 test `the reader follows a brightness change while open`).
- A book whose manifest has no table of contents opens at the start and shows no Contents button (Task 4 tests).
- The new search row (dropdown + field + button) at 200% text on `smallPhone` doesn't overflow (Task 6 test).
- Co-authors with the same surname but different given names (Percy Bysshe Shelley, Mary Shelley) are both kept (Task 12 test).

---

### Task 1: The web reader fits the space Flutter gives it (findings 4, 5)

**Files:**
- Modify: `app/web/index.html`
- Create: `app/tool/check_reader_layout.mjs` (Playwright check, run by hand)

**Interfaces:** none.

- [ ] **Step 1: Write the check.** `app/tool/check_reader_layout.mjs`, run as `node app/tool/check_reader_layout.mjs` with the app served on `http://localhost:8080` (built with `--dart-define=BACKEND_URL=<backend>`). Playwright with any installed Chromium (`executablePath` from `PW_CHROMIUM` if set). It enables semantics (click `flt-semantics-placeholder`), taps the "Frankenstein" example (`getByRole('button', {name: 'Frankenstein', exact: true})`), waits for `/results? for/`, clicks 50px under the result count (opens details), clicks `getByRole('button', {name: /^Read /}).first()`, waits 8 s, then compares `document.querySelector('flt-platform-view iframe').getBoundingClientRect().bottom` with the top of `getByRole('button', {name: 'Next page'})`. Print `OK` and exit 0 when the iframe's bottom ≤ the button's top; else print both numbers and exit 1. Viewport 1280×800, or 390×844 with `--phone`. Add a comment at the top saying it needs Playwright (`npm i playwright` in a scratch folder, not in the repo).
- [ ] **Step 2: Run it and see it fail.** Expected: `FAIL iframe bottom 760 > Next page top …` at 1280×800.
- [ ] **Step 3: Override the height in `app/web/index.html`.** Add a `<style>` in `<head>`: `#wrapper#wrapper { height: 100% !important; }` (the doubled id beats Readium's single-id `!important` rule). If the check still fails, also give the platform view's own element full height: `flt-platform-view > * { height: 100%; }`. Comment: `/* Readium sizes its view to the window (100vh - 96px); Flutter decides its size. */`
- [ ] **Step 4: Rebuild and rerun the check.** `cd app && flutter build web --dart-define=BACKEND_URL=http://localhost:8012`, serve `build/web` on 8080, run the check. Expected: `OK`. Also run it at 390×844 (add `--phone`, which sets the viewport) and expect `OK`.
- [ ] **Step 5: Commit.** `git add app/web/index.html app/tool/check_reader_layout.mjs && git commit -m "fix: the web reader fits its space, so page controls and the player show"`

### Task 2: The reader follows the system's dark mode (finding 1)

**Files:**
- Modify: `app/lib/reader/reader_settings.dart`, `app/lib/reader/reader_page.dart`, `app/lib/reader/settings_sheet.dart`
- Test: `app/test/reader_settings_test.dart`, `app/test/reader_test.dart`

**Interfaces:**
- Produces: `enum ReaderTheme { system, light, dark }`; `ReaderSettings` default `theme: ReaderTheme.system`; `ReaderSettings resolve(Brightness platform)`: returns a copy with `light`/`dark` matching `platform` when `theme == system`, else `this`. The colour getters treat `system` as light (only resolved settings reach the engines and the screen).

- [ ] **Step 1: Write the failing tests.** In `reader_settings_test.dart`: replace `'start in light mode'` with `'start following the system'` (`expect(settings.theme, ReaderTheme.system)`); add `'resolve picks dark on a dark system and keeps a chosen theme'`: `const ReaderSettings().resolve(Brightness.dark).theme == ReaderTheme.dark`, `const ReaderSettings().resolve(Brightness.light).theme == ReaderTheme.light`, `const ReaderSettings(theme: ReaderTheme.light).resolve(Brightness.dark).theme == ReaderTheme.light`; the store test at line 140 now expects `ReaderTheme.system` for nothing stored. In `reader_test.dart` (set `tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark`, reset in `addTearDown`):
  - `'the reader is dark on a dark system'`: the fake engine's open received settings with `theme == ReaderTheme.dark`, and the `ColoredBox` under `reader-surface` has colour `0xFF121212`.
  - `'an explicit Light stays light in dark mode'`: stored settings `theme: light` → the open received `ReaderTheme.light`.
  - `'the reader follows a brightness change while open'`: open on light, switch the test value to dark, pump; the engine's last `apply` got `ReaderTheme.dark`.
  - `'the settings sheet offers Auto, Light and Dark'`: keys `theme-system`, `theme-light`, `theme-dark` exist; `theme-system` is selected by default.
- [ ] **Step 2: Run and see them fail.** `cd app && flutter test test/reader_settings_test.dart test/reader_test.dart` → the new tests fail (`ReaderTheme.system` undefined).
- [ ] **Step 3: Implement.** Add `system` and `resolve` as above. In `reader_page.dart` add `ReaderSettings get _shown => _settings.value.resolve(MediaQuery.platformBrightnessOf(context));` and use it for `engine.open`, `_engine?.apply` in `_settingsChanged`, the `Theme` brightness and both background colours. In `didChangeDependencies`, after the first run, call `_engine?.apply(_shown)` when the resolved theme differs from the last one applied (keep `ReaderTheme? _appliedTheme`). In `settings_sheet.dart`, add `(const Key('theme-system'), 'Auto', ReaderTheme.system)` before Light, and resolve the preview with `MediaQuery.platformBrightnessOf(context)`.
- [ ] **Step 4: Run the whole suite.** `flutter test` → all pass.
- [ ] **Step 5: Commit** with the test README note ("Reader colours: `ReaderTheme.system` (Auto) is the default; the page resolves it with the platform brightness").

### Task 3: Covers load on web, a bit larger on cards (findings 2, 18)

**Files:**
- Modify: `app/lib/ui/common.dart` (`Cover`), `app/lib/ui/results_page.dart` (`ResultRow` cover width)
- Test: `app/test/search_results_test.dart`

- [ ] **Step 1: Write the failing test** `'covers can load from sites without CORS on web'`: after a search, `tester.widget<Image>(find.descendant(of: find.byKey(const Key('cover')).first, matching: find.byType(Image)))` has `webHtmlElementStrategy == WebHtmlElementStrategy.fallback`, and the `SizedBox` under the first `cover` is 64 wide.
- [ ] **Step 2: Run and see it fail.**
- [ ] **Step 3: Implement.** Pass `webHtmlElementStrategy: WebHtmlElementStrategy.fallback` to `Image.network` in `Cover` (comment: `// gutenberg.org sends no CORS header; an <img> element does not need one.`). `ResultRow` passes `width: 64`.
- [ ] **Step 4: Run `flutter test`, then check in the browser.** Rebuild and serve; on the results page for "Frankenstein", covers show. If gutenberg.org answers 503 to this machine, note that in the commit message and check with another source's cover (Open Library).
- [ ] **Step 5: Commit.**

### Task 4: The web reader opens at the book and has a contents list (findings 3, 4)

**Files:**
- Modify: `app/lib/reader/reader_engine.dart`, `app/lib/reader/readium_engine.dart`, `app/lib/reader/text_engine.dart`, `app/lib/reader/reader_page.dart`
- Test: `app/test/readium_engine_test.dart`, `app/test/reader_test.dart`, `app/test/helpers/fakes.dart`

**Interfaces:**
- Produces: in `reader_engine.dart`, `class ReaderChapter { const ReaderChapter({required this.title, required this.locator}); final String title; final String locator; }` and on `ReaderEngine`: `List<ReaderChapter> get contents;` (empty until opened). `TextReaderEngine` returns `const []`. `ReadiumReaderEngine` adds `@visibleForTesting Locator? get startAt => _initial;` (the tests below read "the view's `initialLocator`" through it). `FakeReaderEngine` gets a settable `List<ReaderChapter> contents = const []` and records `goTo` calls (it already implements `goTo`).

- [ ] **Step 1: Write the failing tests.** In `readium_engine_test.dart`, let `FakeReadium.finishOpen` take an optional publication JSON with `readingOrder` `[{'href': 'a.xhtml', 'type': 'application/xhtml+xml'}, {'href': 'b.xhtml', 'type': 'application/xhtml+xml'}]` and `toc` `[{'href': 'b.xhtml#start', 'title': 'Chapter 1'}, {'href': 'b.xhtml#two', 'title': 'Chapter 2'}]`:
  - `'a new book starts at the first contents entry'`: open with `at: null`; the view's `initialLocator.href` is `'b.xhtml'` and its fragment list contains `'start'`.
  - `'a saved place wins over the contents'`: open with a locator; `initialLocator` is that locator.
  - `'a book without contents starts at the beginning and lists none'`: no `toc` → `initialLocator` null, `contents` empty.
  - `'contents lists every entry'`: `contents.map((c) => c.title)` is `['Chapter 1', 'Chapter 2']`.
  In `reader_test.dart`: `'Contents opens a list and goes to the chosen chapter'` (fake `contents` with two entries: `contents-button` exists with label `'Contents'`; tapping it shows `contents-sheet`; tapping `contents-1` calls `goTo` with that locator and closes the sheet) and `'no Contents button when the book has none'`.
- [ ] **Step 2: Run and see them fail.**
- [ ] **Step 3: Implement.** In `ReadiumReaderEngine.open`, after the publication opens: `contents` = `publication.tocFlattened` mapped through `publication.locatorFromLink(link)`, skipping nulls, title `link.title ?? ''`, locator `jsonEncode(locator.toJson())`; when `at == null`, `_initial` = the first of those locators. In `reader_page.dart` add an `IconButton` before the bookmark, key `contents-button`, `Icons.toc`, `semanticLabel: 'Contents'`, shown when `showText && _engine!.contents.isNotEmpty`. It opens a modal bottom sheet (`contents-sheet`, heading "Contents") with a `ListTile` per chapter keyed `contents-<index>`; tapping it calls `_engine!.goTo(ReaderPosition(progress: 0, locator: chapter.locator))` and pops. Raise the same click shield as the settings sheet while it is open (rename `_settingsOpen` to `_sheetOpen`).
- [ ] **Step 4: Run `flutter test`; rebuild and check in the browser** that "Frankenstein" opens at the title page, not the licence, and that Contents → "LETTER I." goes there. Run `app/tool/check_reader_layout.mjs` again → `OK`.
- [ ] **Step 5: Commit** with the test README note.

### Task 5: Shorter, more readable result cards (findings 9, 10)

**Files:**
- Modify: `app/lib/ui/results_page.dart` (`ResultRow`)
- Test: `app/test/search_results_test.dart`, `app/test/accessibility_test.dart`

- [ ] **Step 1: Write the failing tests.** `'a result card shows title, author, one facts line, the button and where it opens'`: the card for the Pride and Prejudice fixture work has no text equal to the joined source names; `result-edition-<id>` has `maxLines == 1`; the facts line reads `'Text and audio · English'` (lower-case "audio" after the first word); every `Text` in the card except the title uses at least `bodyMedium`'s font size. In `accessibility_test`: `'result cards fit at 200% text on a small phone'` (`tester.takeException()` is null after a search).
- [ ] **Step 2: Run and see them fail.**
- [ ] **Step 3: Implement.** In `ResultRow`, remove the source-list `Text`; build the facts line as `[formats sentence, language]` joined by `' · '` with formats `'Text'`, `'Audio'` or `'Text and audio'`; keep `matchNote`, the button, `bookSummary` (`maxLines: 1`, `overflow: TextOverflow.ellipsis`) and `accessNote`; switch `bodySmall` to `bodyMedium` and add `SizedBox(height: 4)` above the button. Update any existing test that looked for the source list on cards (grep for `sourceName` expectations in `search_results_test.dart`).
- [ ] **Step 4: Run `flutter test`.**
- [ ] **Step 5: Commit** with the README note (which lines a card has, and that sources moved to details).

### Task 6: "Search in" is one dropdown (findings 7, 11)

**Files:**
- Modify: `app/lib/ui/search_bar.dart`
- Test: `app/test/search_results_test.dart`, `app/test/helpers/test_app.dart` (line 124 helper), `app/test/accessibility_test.dart`

**Interfaces:**
- Produces: `DropdownButton<SearchField>` keyed `search-in`, menu items keyed `search-in-<field.name>`, semantics label `'Search in'`. The helper at `test_app.dart:124` becomes: tap `search-in`, `pumpAndSettle`, tap `find.byKey(Key('search-in-$field')).last`, `pumpAndSettle`.

- [ ] **Step 1: Change the tests first.** Replace the `ChoiceChip.selected` expectations (`search_results_test.dart` lines ~145–156, 192, 552) with `tester.widget<DropdownButton<SearchField>>(find.byKey(const Key('search-in'))).value == SearchField.<x>`. Add `'the search row fits at 200% text on a small phone'` in `accessibility_test` (no exception; `search-in`, `search-field` and `search-submit` all on screen).
- [ ] **Step 2: Run and see them fail.**
- [ ] **Step 3: Implement.** Replace the chip `Wrap` with a `DropdownButton<SearchField>` as the first child of the search `Row` (`underline: SizedBox.shrink()`, items from `_fieldNames`), wrapped in `Semantics(label: 'Search in')`. Below 360 logical px wide, put the dropdown on its own line above the row (use `LayoutBuilder`), so the 200% test passes.
- [ ] **Step 4: Run `flutter test`.**
- [ ] **Step 5: Commit** with the README note (the README's "Search by field" paragraph names the chips; reword it).

### Task 7: Format choices are radio buttons; filter groups have visible labels (findings 7, 12)

**Files:**
- Modify: `app/lib/ui/results_page.dart` (`_Filters`)
- Test: `app/test/accessibility_test.dart`, `app/test/search_results_test.dart`

- [ ] **Step 1: Write the failing tests.** `'format choices are one-of-a-group'`: `tester.getSemantics(find.byKey(const Key('filter-format-text')))` has `isInMutuallyExclusiveGroup: true` (`containsSemantics`). `'the wide filter rail labels its groups'`: at 1280×800 after a search, `find.text('Sources')`, `find.text('Format')` and `find.text('Language')` each find one widget inside `filters`. The phone's inline format chips show no "Format" text.
- [ ] **Step 2: Run and see them fail.**
- [ ] **Step 3: Implement.** Wrap each format `ChoiceChip` in `MergeSemantics(child: Semantics(inMutuallyExclusiveGroup: true, child: chip))`. In `group(...)`, when `sourcesAndLanguage` is true, put `Text(label, style: titleSmall)` and `SizedBox(height: 4)` above the `Wrap`, with `ExcludeSemantics` on the visible label (the group already has it), and the same above the language dropdown; `SizedBox(height: 16)` between groups.
- [ ] **Step 4: Run `flutter test`; in the browser, check** that `ariaSnapshot()` of the results page shows `radio "Text"` for the format chips.
- [ ] **Step 5: Commit.**

### Task 8: Heading levels (finding 8)

**Files:**
- Modify: `app/lib/ui/common.dart` (`Heading`), and the page-title headings: `home_page.dart` (`home-heading`), `results_page.dart` (`results-heading`), `details_page.dart` (`details-title`), `about_page.dart` (`about-title`), `audio_page.dart` (its title heading), `reader_page.dart` (`reader-title`)
- Test: `app/test/accessibility_test.dart`

**Interfaces:**
- Produces: `Heading(text, {..., int level = 2})` → `Semantics(header: true, headingLevel: level, ...)`.

- [ ] **Step 1: Write the failing test.** In the `headings` group loop, add `'${entry.key} title is heading level 1'`: `tester.getSemantics(find.byKey(Key(entry.value.heading))).getSemanticsData().headingLevel == 1`. Add one for a section heading ("Try one of these") at level 2.
- [ ] **Step 2: Run and see it fail.**
- [ ] **Step 3: Implement.** Add `level`; pass `level: 1` at each page-title heading listed above.
- [ ] **Step 4: Run `flutter test`.**
- [ ] **Step 5: Commit.**

### Task 9: Details page leads with the way in (findings 6, 13, 16)

**Files:**
- Modify: `app/lib/ui/details_page.dart`
- Test: `app/test/details_page_test.dart`

- [ ] **Step 1: Write the failing tests.**
  - `'the book the result button opens is listed first'`: for a work whose `books` put an audio book before the in-app text, the first `_BookCard` (first `find.byKey(Key('book-<key>'))` by vertical position) is `work.bestBook`.
  - `'the main button is under the title'`: a `details-primary` key holds a `BookActionButton` for `bestBook`, and its top is above `details-metadata`'s top.
  - `'the offline note comes last'`: `offline-note`'s top is below the last book card's bottom.
  - `'the page starts at the top on a wide screen'`: at 1280×800, `details-cover`'s top is ≤ 100.
- [ ] **Step 2: Run and see them fail.**
- [ ] **Step 3: Implement.** In `_bookCards`, iterate `[if (best != null) best, ...work.books.where((b) => b.key != best?.key)]` with `best = work.bestBook` (the HathiTrust cut logic is unchanged). Under the title, add `Padding(key: Key('details-primary'), child: BookActionButton(work: work, book: best))` when `best != null`, keyed so it doesn't collide with `open-<book.key>` (give this button `key: Key('open-primary')`). Move the `offline-note` `Text` to the end of the column with `SizedBox(height: 24)` above it. Replace the outer `Center` with `Align(alignment: Alignment.topCenter, ...)`. Existing tests that tap `open-<key>` on the first card still find it in the card.
- [ ] **Step 4: Run `flutter test`.**
- [ ] **Step 5: Commit.**

### Task 10: The audio player shows times and the playing chapter (finding 15)

**Files:**
- Modify: `app/lib/util/format.dart`, `app/lib/ui/audio_player.dart`, `app/lib/ui/audio_page.dart`
- Test: `app/test/format_test.dart`, `app/test/audio_player_test.dart`

**Interfaces:**
- Produces: `String formatClock(Duration d)` → `'0:05'`, `'12:05'`, `'1:02:03'` (hours only when ≥ 1 h; negatives clamp to `'0:00'`).

- [ ] **Step 1: Write the failing tests.** `format_test` group `formatClock`: `Duration(seconds: 5)` → `'0:05'`; `Duration(minutes: 12, seconds: 5)` → `'12:05'`; `Duration(hours: 1, minutes: 2, seconds: 3)` → `'1:02:03'`; `Duration(seconds: -3)` → `'0:00'`. `audio_player_test`: `'the full player shows time played and time left'`: with a 20-minute chapter at position 1:05, `position-time` reads `'1:05'` and `position-remaining` reads `'-18:55'`. Both are `ExcludeSemantics` (the slider already announces it). `'the playing chapter has an icon'`: the selected chapter row has an `Icon` with `semanticLabel: 'Current chapter'`; other rows have none.
- [ ] **Step 2: Run and see them fail.**
- [ ] **Step 3: Implement.** `formatClock` in `format.dart`. In `AudioPlayerPanel` (non-compact, length known), add a `Row(mainAxisAlignment: spaceBetween)` under the slider with the two texts (`bodySmall` is fine here: secondary and duplicated by the slider's semantics), padded 24 px horizontally to line up with the slider's track. In `audio_page.dart`, give the selected `ListTile` `leading: Icon(Icons.graphic_eq, semanticLabel: 'Current chapter')` and other tiles `leading: SizedBox(width: 24)` so titles stay aligned.
- [ ] **Step 4: Run `flutter test`.**
- [ ] **Step 5: Commit.**

### Task 11: Home and About start at the top; Home shows example covers (findings 16, 17)

**Files:**
- Modify: `app/lib/ui/home_page.dart`, `app/lib/ui/about_page.dart`
- Test: `app/test/home_page_test.dart`, `app/test/source_about_test.dart`

**Interfaces:**
- Produces: `exampleSearches` becomes `const exampleBooks = [(title: 'Pride and Prejudice', gutenberg: 1342), (title: 'Frankenstein', gutenberg: 84), (title: 'Moby Dick', gutenberg: 2701), (title: 'The Odyssey', gutenberg: 1727)];` cover URL `https://www.gutenberg.org/cache/epub/<n>/pg<n>.cover.medium.jpg`. Keep the `example-books` key on the row.

- [ ] **Step 1: Write the failing tests.** `home_page_test`: `'examples show a cover and a title, and search by title'`: each example has a `Cover` (`find.descendant(of: find.byKey(Key('example-books')), matching: find.byType(Cover))` finds 4) and is one button named by its title (semantics `isButton`, label `'Pride and Prejudice'`); tapping it runs a title search (as the current test does). `'the sources are a compact row of links'`: `about-link-<id>` are `TextButton`s labelled with the source name only ("LibriVox"), all five on one screen at 1280×800 (`tester.getRect` bottom ≤ 800). `source_about_test`: `'About starts at the top on a wide screen'`: `about-title` top ≤ 100 at 1280×800. Update the home test that expects `'About LibriVox'` text to `'LibriVox'`.
- [ ] **Step 2: Run and see them fail.**
- [ ] **Step 3: Implement.** Home: the examples are a horizontally scrolling `Row` of `InkWell`s, each a `Cover(width: 96)` with the title under it (`bodyMedium`, 2 lines max), wrapped in the same `Semantics(button: true, label: title, excludeSemantics: true, onTap: …)` pattern the chips use. The sources become a `Wrap` of `TextButton`s with the existing keys. Replace `Center` with `Align(alignment: Alignment.topCenter, …)` on Home and in `_AboutBody`. The intro and home heading are unchanged.
- [ ] **Step 4: Run `flutter test`.**
- [ ] **Step 5: Commit** with the README note.

### Task 12: One author, one name, when works merge (finding 14)

**Files:**
- Modify: `backend/app/merge.py` (`_work`)
- Test: `backend/tests/test_merge.py`

- [ ] **Step 1: Write the failing tests** (use the factories in `tests/factories.py`; join the two books through a `gutenberg` cross-reference, as existing merge tests do):
  - `test_a_shorter_spelling_of_the_same_author_is_dropped`: Gutenberg `'Shelley, Mary Wollstonecraft, 1797-1851'` + Open Library `'Mary Shelley'` → `work.authors == ['Mary Wollstonecraft Shelley']`.
  - `test_coauthors_with_one_surname_are_kept`: one book with authors `['Shelley, Percy Bysshe', 'Shelley, Mary Wollstonecraft']` → both kept.
  - `test_author_order_follows_the_text_record`: Open Library audio-less record `['Mary Shelley', 'Percy Bysshe Shelley']` merged with Gutenberg text `['Shelley, Mary Wollstonecraft']` → `['Mary Wollstonecraft Shelley', 'Percy Bysshe Shelley']`.
- [ ] **Step 2: Run and see them fail.** `cd backend && source venv/bin/activate && python -m pytest tests/test_merge.py -k author -v`
- [ ] **Step 3: Implement.** After building `authors` in `_work`, drop a key whose tokens are a strict subset of another key's tokens with the same first and last token (`k.split()`), but only between authors from *different* books (track which book each key came from), so co-authors in one record are never collapsed. Comment the why in one line.
- [ ] **Step 4: Run `python -m pytest`** → all pass.
- [ ] **Step 5: Commit** with a `backend/tests/README.md` note.

### Task 13: A reading serif for titles (finding 18)

**Files:**
- Create: `app/assets/fonts/Literata[opsz,wght].ttf`, `app/assets/fonts/OFL.txt`
- Modify: `app/pubspec.yaml`, `app/lib/app.dart` (`FreeBookReaderApp.theme`)
- Test: `app/test/accessibility_test.dart` (or a new small test in `home_page_test.dart`)

**Interfaces:**
- Produces: font family `'Literata'` used by `headlineLarge/Medium/Small`, `titleLarge` and `titleMedium` in the app theme; body, label and reader text are unchanged (the reader has its own font setting).

- [ ] **Step 1: Write the failing test** `'titles use Literata'`: `FreeBookReaderApp.theme(Brightness.light).textTheme.headlineMedium!.fontFamily == 'Literata'` and the same for `titleMedium`; `bodyLarge!.fontFamily != 'Literata'`.
- [ ] **Step 2: Run and see it fail.**
- [ ] **Step 3: Add the font.** Download the variable TTF and `OFL.txt` from github.com/googlefonts/literata (the `fonts/variable` folder of the latest release). Declare it under `flutter: fonts:` in `pubspec.yaml` (`family: Literata`). In `theme()`, build the `ThemeData` once, then `copyWith(textTheme: t.textTheme.copyWith(...))`, setting `fontFamily: 'Literata'` on the five styles above.
- [ ] **Step 4: Run `flutter test` and look at it.** Rebuild web; check Home, results and details at 1280 and 390 wide in light and dark. Titles must not overflow (Literata is wider than Roboto); `ResultRow` titles wrap, and the details app bar keeps `maxLines: 1`.
- [ ] **Step 5: Commit** (fonts, pubspec, theme, test).

### Task 14: Check the whole thing and record it

**Files:**
- Modify: `AGENTS.md` (Context), `app/test/README.md` (test count line), `docs/ui-review-2026-11-18.md` (a Status line per finding)

- [ ] **Step 1: Run all suites.** `cd app && flutter test`; `cd backend && python -m pytest`. Record the counts.
- [ ] **Step 2: Walk the app in a browser.** Build web against the running backend, serve on 8080, run `app/tool/check_reader_layout.mjs` at both sizes (`OK`), and take screenshots of Home, results, details, reader, settings and audio at 1280×800 and 390×844 with `colorScheme: 'dark'` and `'light'`. Confirm each finding visually: dark reader in dark mode, covers, title page first, "N% read" visible, contents list, details order, times on the player.
- [ ] **Step 3: Update the docs.** Add a `**Status:** fixed 2026-11-…` line under each finding in the review file. Add one AGENTS.md Context line: "UI review 2026-11-18 (`docs/ui-review-2026-11-18.md`): reader colour Auto (follows the system), covers as `<img>` on web, web reader starts at the first contents entry and has Contents, Readium height override in `web/index.html`, Search in is a dropdown, heading levels, shorter result cards, details lead with the main button, audio times, Literata titles, merged works drop a shorter spelling of an author." Update the test counts in AGENTS.md and `app/test/README.md`.
- [ ] **Step 4: Commit.** `git commit -m "docs: record the UI review fixes and test counts"`
