# Persona Round One Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the concrete defects the round-one persona reviews exposed: wrong or empty audiobook players, `&amp;` in LibriVox titles, no automatic resume, a possible reset of the search-field choice, filters that push phone results down, result cards that don't say why they matched, what they open or where, unclear offline expectations, and no way to preview text settings. Also record the review of `ANALYSIS.md` in that file.

**Architecture:** Small, separate fixes at the layer that owns each bug. The backend LibriVox adapter cleans titles. The app's `Work` model chooses a better recording. The audio widgets stop presenting elapsed time as the total length. `BookmarkStore` gains a "last place" next to the manual bookmark, and `ReaderPage` writes and reads it. No new packages.

**Tech Stack:** FastAPI/pytest (backend), Flutter/flutter_test (app), Python `html` stdlib.

**Spec:** `docs/persona-findings-round-one/ANALYSIS.md` (with the review addendum written in Task 1), `spec.md` (Reading experience, line 49; Data, line 176).

## Global Constraints

- Test-first: write the failing test, then the code (AGENTS.md).
- If a test changes, change its README in the same commit: `backend/tests/README.md`, `app/test/README.md`.
- Backend tests: `cd backend && source venv/bin/activate && python -m pytest`. App tests: `cd app && flutter test`.
- Bookmarks and places stay on the device only ("Until accounts exist, bookmarks are stored on the device only", spec.md:49).
- Show unknown facts as unknown; never guess them (ANALYSIS.md, recommendation 1).
- Branch: work on `audit-fixes` or a new branch off it; never commit to `main`.

## Review Focus

1. A work whose only recording is a Gutenberg audio eBook (no chapters, no `audio_seconds`): the player still plays, says the length is unknown, and shows no empty Chapters heading. Tested in Task 4.
2. A chaptered LibriVox book where one chapter has no `playtime`: that chapter's player says the length is unknown, while the others show their length. Tested in Task 4.
3. A stored last place that is not valid JSON: the book opens at the bookmark if there is one, else at the start, and does not crash. Tested in Task 5.
4. A title with a real `&` or `<`, already unescaped, comes through unchanged (unescaping runs once). Tested in Task 2.
5. Reading one book does not move the place of another book. Tested in Task 5.

---

### Task 1: Record the review of the analysis

**Files:**
- Modify: `docs/persona-findings-round-one/ANALYSIS.md` (append a section)
- Modify: `docs/persona-findings-round-one/README.md` (one line pointing to it)

- [ ] **Step 1: Append `## Review of this analysis (2026-10-27)`** to ANALYSIS.md with two subsections:
  - **Disagreements:** (a) the audio failures follow one pattern: merged Gutenberg+LibriVox results open the Gutenberg audio eBook (`Work.bestBook`, `app/lib/models/models.dart:227`), which has no chapters or length, and `audio_player.dart:193` shows elapsed time as the total; (b) resuming is a real gap: `ReaderPage` restores only a manual bookmark, which never moves, so spec.md:49 "where they left off" is not met; (c) so "no spec change" is too strong (spec.md:49, plus spec.md:48's font promise against the unbundled dyslexia font); (d) "Heartstopper" (not in the catalog) and "time travel" (ranking) are different problems.
  - **Additions:** the `&amp;` chapter title; the empty Chapters heading; books opening on front matter (Maya, Elaine, Lucía, Priya, Jordan); a possible reset of Title→Anything (Jordan); asking for language before the search and allowing several languages (Lucía); justified, hyphenated text on mobile (Morgan); evidence counts (Ruth, Sam and Priya never finished an in-app journey); turning on semantics when the page loads for round two.
  - Each item gets a line pointing to the task in this plan that addresses it, or "Out of scope, needs a decision" (see the end of this plan).
- [ ] **Step 2: Add to README.md** under "Combined analysis": `ANALYSIS.md ends with a review of the analysis and links to the fix plan (docs/superpowers/plans/2026-10-27-persona-round-one-fixes.md).`
- [ ] **Step 3: Commit**

```bash
git add docs/persona-findings-round-one/ANALYSIS.md docs/persona-findings-round-one/README.md docs/superpowers/plans/2026-10-27-persona-round-one-fixes.md
git commit -m "docs: review the round-one persona analysis and plan the fixes"
```

### Task 2: Unescape HTML entities in LibriVox titles

**Files:**
- Modify: `backend/app/sources/librivox.py:95,105` (book title and chapter title)
- Test: `backend/tests/test_source_librivox.py` (new class `TestEntities`)

**Interfaces:** Produces nothing new; `Book.title` and `Chapter.title` arrive plain.

- [ ] **Step 1: Write the failing tests**

```python
class TestEntities:
    """Persona round one (Lucía): LibriVox sends "Tasa &amp; El Rey"."""

    def test_book_and_chapter_titles_are_unescaped(self, source_for, sample_json):
        data = sample_json("librivox-title-search.json")
        record = data["books"][0]
        record["title"] = "Pride &amp; Prejudice"
        record["sections"][0]["title"] = "Tasa &amp; El Rey"
        source, _ = source_for(json=data)
        book = source.search(SearchQuery(title="pride and prejudice"))[0]
        assert book.title == "Pride & Prejudice"
        assert book.chapters[0].title == "Tasa & El Rey"

    def test_plain_ampersand_is_unchanged(self, source_for, sample_json):
        data = sample_json("librivox-title-search.json")
        data["books"][0]["title"] = "Tom & Jerry <1>"
        source, _ = source_for(json=data)
        assert source.search(SearchQuery(title="pride and prejudice"))[0].title == "Tom & Jerry <1>"
```

- [ ] **Step 2: Run and see them fail.** `python -m pytest tests/test_source_librivox.py::TestEntities -v`. Expected: the first test fails (`'Pride &amp; Prejudice' != 'Pride & Prejudice'`).
- [ ] **Step 3: Implement.** Wrap both titles in `html.unescape(...)` (stdlib `import html`). The fallback `"Untitled"` and `"Section N"` strings need no unescaping.
- [ ] **Step 4: Run the whole backend suite.** `python -m pytest`. Expected: all pass. The LibriVox title filter compares titles after this point; if a title-matching test breaks, unescape before that comparison too.
- [ ] **Step 5: Add a line to `backend/tests/README.md`:** "LibriVox titles are HTML-unescaped (`TestEntities`)."
- [ ] **Step 6: Commit** `fix: unescape HTML entities in LibriVox titles (persona round one)`

### Task 3: Prefer recordings that have a length or chapters

**Files:**
- Modify: `app/lib/models/models.dart:216-230` (`Work.recordingsFor`, `Work.bestBook`; new getter on `Book`)
- Test: `app/test/models_test.dart` (new group `audio choice`)

**Interfaces:**
- Produces: `bool get hasAudioDetails` on `Book`, true when `chapters.isNotEmpty || audioSeconds != null`. `recordingsFor(book)` and `bestBook` list books with details first and otherwise keep their order (stable sort). `audioBooks` keeps its order, because the details page lists every book.

- [ ] **Step 1: Write the failing tests.** Build the books in code with `Book(source:, sourceId:, title:, format: BookFormat.audio, url:, access:, reading: ReadingOptions(mode: ReadingMode.inApp, kind: 'audio', url: ...), language: 'en', ...)`, with a Gutenberg audio book (no chapters, no seconds) listed before a LibriVox book (`audioSeconds: 12464`).

```dart
group('audio choice', () {
  test('a work with only audio opens the recording that has a length', () {
    final work = Work(id: 'w', title: 'The Time Machine', books: [gutenbergAudio, librivoxAudio]);
    expect(work.bestBook!.source, 'librivox');
  });
  test('the recording beside a text is the one with chapters or a length', () {
    final work = Work(id: 'w', title: 'T', books: [text, gutenbergAudio, librivoxAudio]);
    expect(work.recordingsFor(text).map((b) => b.source), ['librivox', 'gutenberg']);
  });
  test('a bare recording is still chosen when it is the only one', () {
    final work = Work(id: 'w', title: 'T', books: [gutenbergAudio]);
    expect(work.bestBook!.source, 'gutenberg');
  });
});
```

- [ ] **Step 2: Run them and see them fail.** `flutter test test/models_test.dart`. Expected: the first two fail (`gutenberg` is chosen).
- [ ] **Step 3: Implement** `hasAudioDetails`, plus one private helper on `Work` that moves books with details ahead of the rest, keeping their order. Use it in `recordingsFor` and in the audio branch of `bestBook`.
- [ ] **Step 4: Run all app tests.** `flutter test`. Expected: all pass, including the existing test `recordings only include audio in the same language as the text`.
- [ ] **Step 5: Add to `app/test/README.md`** under a new heading `### Persona round one fixes (2026-10-27)`: "`models_test` audio choice: a recording with chapters or a length is chosen before a bare one (Gutenberg audio eBooks have neither)."
- [ ] **Step 6: Commit** `fix: open the recording that has chapters or a length (persona round one)`

### Task 4: Say "length unknown" instead of a moving total; hide an empty chapter list

**Files:**
- Modify: `app/lib/ui/audio_player.dart:193-210` (the full panel's slider)
- Modify: `app/lib/ui/audio_page.dart:58-72` (the Chapters heading and list)
- Test: `app/test/audio_player_test.dart`

**Interfaces:**
- Consumes: `AudioController.chapterLength` (`Duration?`, null when unknown), `AudioController.position`.
- Produces: the key `position-elapsed`, a `Text` that is shown in place of `position-slider` when `chapterLength == null`.

- [ ] **Step 1: Write the failing tests** (use the file's existing helpers for pumping an audio page with `FakeAudioEngine`):
  - `'a recording with no length shows time played, not a total'`: book with no chapters and `audioSeconds: null`; play; `emitPosition` 12 s. Expect `find.byKey(Key('position-slider'))` to find nothing, and `position-elapsed` to have the text `'12 sec played · length unknown'`.
  - `'a chapter with no length shows time played'`: a book with two chapters, the first with `durationSeconds: null` and the second with 600. On chapter 0, expect `position-elapsed`. After `playChapter(1)`, expect `position-slider` with the semantics value `'0 sec of 10 min'`.
  - `'no Chapters heading when the recording has no chapters'`: expect `find.text('Chapters')` to find nothing on the audio page.
  - `'the Chapters heading shows when there are chapters'`: the existing chaptered fixture; expect `find.text('Chapters')` to find one widget.
- [ ] **Step 2: Run them and see them fail.** `flutter test test/audio_player_test.dart`.
- [ ] **Step 3: Implement.** In the panel, when `controller.chapterLength == null`, show `Text('${formatDuration(position.inSeconds) ?? '0 sec'} played · length unknown', key: Key('position-elapsed'))` instead of the slider. The skip buttons still work. Do not make it a live region, because it changes every second. In `audio_page.dart`, add `if (book.chapters.isNotEmpty)` in front of the heading and the list.
- [ ] **Step 4: Run all app tests.** `flutter test`. Any existing test that expected `position-slider` on a recording with no length must change. Record that in the README.
- [ ] **Step 5: Add to the README** (same heading as Task 3): the `position-elapsed` key in the key list (the "Audio" keys line), and both behaviors.
- [ ] **Step 6: Commit** `fix: audio player says length unknown and hides an empty chapter list (persona round one)`

### Task 5: Remember the last place in each book automatically

**Files:**
- Modify: `app/lib/storage/bookmark_store.dart` (two methods)
- Modify: `app/lib/reader/reader_page.dart:73-86` (open at the last place; save it on each position)
- Modify: `spec.md:49`, `spec.md:176`
- Test: `app/test/bookmark_store_test.dart`, `app/test/reader_test.dart` (new group `last place`)

**Interfaces:**
- Produces on `BookmarkStore`: `Bookmark? loadLastPlace(String bookKey)` and `Future<void> saveLastPlace(String bookKey, Bookmark place)`, stored under the prefix `'lastplace:'` with the same JSON as bookmarks. `savedBookKeys()` keeps returning manual bookmarks only.
- `ReaderPage` opens at the last place if there is one, else at the bookmark, else at the start. The bookmark button still shows only whether a manual bookmark exists.

- [ ] **Step 1: Write the failing store tests:**
  - `'keeps a last place apart from the bookmark'`: `saveLastPlace('gutenberg:1', Bookmark(progress: 0.5, locator: 'x'))`. Expect `loadLastPlace` to return progress 0.5 and locator `'x'`, `load('gutenberg:1')` to be null, and `savedBookKeys()` to be empty.
  - `'a damaged last place loads as none'`: set prefs `'lastplace:gutenberg:1': 'not json'`. Expect `loadLastPlace` to be null.
- [ ] **Step 2: Write the failing reader tests** (group `last place`, using `readerEnv`, `openBook`, `nextPage`, `reopen`, `pageNumber`):
  - `'reopens where the reader stopped, with no bookmark'`: `nextPage(tester, 3)`, then `reopen`. Expect `opens.single.at!.locator == 'fake:3'`, `pageNumber == 4`, and `env.bookmarks.load(gutenberg)` to be null.
  - `'the last place wins over an older bookmark'`: bookmark at page 2, `nextPage(tester, 3)`, then `reopen`. Expect `'fake:5'`, and the bookmark button semantics to be `'Remove bookmark'`.
  - `'a damaged last place falls back to the bookmark'`: prefs with a valid bookmark at `'fake:2'` and `'lastplace:<key>': '{'`. Expect it to open at `'fake:2'`.
  - `'reading one book does not move another'`: read the Pride book to page 3. Expect `loadLastPlace` for a second fixture book to be null.
- [ ] **Step 3: Run them and see them fail.** `flutter test test/bookmark_store_test.dart test/reader_test.dart`.
- [ ] **Step 4: Implement.** Store: two methods next to `load`/`save`. Page: `_startAt` comes from `loadLastPlace(key) ?? load(key)`. In the existing `positions.listen`, also call `saveLastPlace(key, Bookmark(progress: p.progress, locator: p.locator))` without awaiting it. One small write per event is fine on SharedPreferences and localStorage; add a debounce only if a test or a profile shows it is needed.
- [ ] **Step 5: Run all app tests.** `flutter test`. Existing tests that reopen a book and expect the start now open at the last place. Fix them by clearing prefs or by asserting the new behavior, and note each one in the README.
- [ ] **Step 6: Update the spec.** spec.md:49 becomes: "Reopens each book where the reader stopped (saved automatically), and can bookmark a place. Until accounts exist, both are stored on the device only." spec.md:176 becomes: "Bookmarks and the last place in each book are saved on the device and restored when a book is reopened."
- [ ] **Step 7: Update the README** (same heading): the new store methods in the file map (`storage/bookmark_store.dart` line), the `last place` group, and the requirement-table row "Bookmarks saved on the device and restored".
- [ ] **Step 8: Commit** `feat: reopen each book where the reader stopped (persona round one)`

### Task 6: The search-field choice survives a filter change and a trip to the reader

The code keeps the field in `BookSearchBar` state behind a `GlobalKey` (`results_page.dart:31,59`, `search_bar.dart:40`), so this may already work and Jordan's run may have used an older build. This task pins it with a test, and fixes it only if the test fails.

**Files:**
- Test: `app/test/search_results_test.dart`
- Modify (only if the test fails): `app/lib/ui/results_page.dart` and/or `app/lib/ui/search_bar.dart`

- [ ] **Step 1: Write the test** `'the Title choice stays after Audio is chosen and after returning from a book'`: start on results for "The Time Machine" with the field Anything. Tap `search-in-title`, then search. Open a result's reader and go back. Tap `filter-format-audio`. Expect the `search-in-title` ChoiceChip to be `selected: true`, and the last request the fake API received to carry `title=The Time Machine` and `format=audio`.
- [ ] **Step 2: Run it.** `flutter test test/search_results_test.dart`. If it passes, skip to Step 4.
- [ ] **Step 3: If it fails,** fix the root cause where the field is lost. Most likely the bar is rebuilt with `widget.initialField`; pass the field from `_query` instead. Run it again; expected PASS.
- [ ] **Step 4: Add the README line and commit** `test: the search field choice survives filters and the reader (persona round one)` (use `fix:` if Step 3 ran).

### Task 7: A compact filter bar on phones

Seven reviewers (Maya, Daniel, Elaine, Alex, Lucía, Priya, Jordan) said that on a phone the filters push the first result down. Design (ANALYSIS.md recommendation 4: keep every filter, show fewer at once):
- **Below 840 px (`ResultsPage.wideLayout`):** under the search box, one row holds the Format chips (`filter-format-all|text|audio`, unchanged, because Audio is the filter people used most) and a `filters-button`. The button's text is the summary, e.g. "All sources · Any language" or "2 of 5 sources · Spanish". Tapping it opens a modal bottom sheet (`filters-sheet`) with the Sources chips and the Language menu, both unchanged, plus a `filters-done` button. Changes apply at once, as they do now.
- **840 px and wider:** no change; the full filter column stays on the left.
- The "Search in" chips stay as they are: they are the known-item route Daniel valued. Revisit after round two.

**Files:**
- Modify: `app/lib/ui/results_page.dart` (the narrow branch of `build`; `_Filters`)
- Modify: `app/test/helpers/test_app.dart` (helper)
- Test: `app/test/search_results_test.dart` (group `filters`), `app/test/accessibility_test.dart`

**Interfaces:**
- Produces: `_Filters({..., bool format = true, bool sourcesAndLanguage = true})`, which draws only the parts asked for. Wide layout: both. Narrow row: `format: true, sourcesAndLanguage: false`, plus the button. Sheet: `format: false, sourcesAndLanguage: true`.
- Produces: `String filterSummary(SearchQuery query, Set<String> sources)`, a top-level function in `results_page.dart`. It returns `'All sources'` or `'N of 5 sources'`, then `' · '`, then `'Any language'` or the language's name from the map the Language menu already uses.
- Produces (test helper): `Future<void> openFilters(WidgetTester tester)`. It taps `filters-button` and settles if the button is on screen, and does nothing on a wide screen. `Future<void> closeFilters(WidgetTester tester)` taps `filters-done` if the sheet is open.
- The sheet rebuilds from the page's current `_query`/`_sources`: wrap its body in `StatefulBuilder` and call its setter after each change.

- [ ] **Step 1: Write the failing tests** (`size: phone` unless stated):
  - `'on a phone the sources and language are behind a Filters button'`: after a search, expect `filter-format-audio` to be found, `filter-source-doab` and `filter-language` to find nothing, and `filters-button` to have the text `'All sources · Any language'`.
  - `'the button shows what is chosen'`: `openFilters`, tap `filter-source-doab` and `filter-source-hathitrust`, choose Spanish, `closeFilters`. Expect the button text `'3 of 5 sources · Spanish'`, and the last request to carry `sources` without doab and hathitrust, and `language=es`.
  - `'a source turned off stays off when the sheet is opened again'`: turn off `librivox`, close, open again. Expect the `filter-source-librivox` chip to have `selected: false`.
  - `'the first result is higher on a phone'`: expect `result-w-pride`'s top to be at most 300 px below the bottom of `search-field` at `phone` size (400×800). Before this change it is much further down; record the measured value in the README.
  - `'on a wide screen nothing moves into a sheet'`: at `desktop` size, expect `filters-button` to find nothing and `filter-source-doab` to be found (the existing test "filters are to the left" still holds).
  - accessibility: `'the Filters button is a named button and works at 200% text on a small phone'` (`smallPhone`, the file's existing text-scale helper). Expect `isButton: true`, a label containing `'Filters'` and the summary, and no overflow errors. Also expect `filters-sheet` to be announced with the heading "Filters".
- [ ] **Step 2: Run them and see them fail.** `flutter test test/search_results_test.dart test/accessibility_test.dart`.
- [ ] **Step 3: Implement** the narrow branch, the two `_Filters` flags, `filterSummary`, and the sheet (`showModalBottomSheet`, `isScrollControlled: true`, `showDragHandle: true`, matching `ReaderPage._openSettings`). Keep the key `filters` on the narrow row, so the existing test "on mobile the filters sit under the search box and above the results" still holds.
- [ ] **Step 4: Add `openFilters`/`closeFilters`** to `test_app.dart`. The existing tests run at `phone` size by default, so call `openFilters` before they tap a `filter-source-*` chip or `filter-language` (search_results_test lines 238–311, accessibility_test line 109). Do not change what they assert.
- [ ] **Step 5: Run all app tests.** `flutter test`. Expected: all pass.
- [ ] **Step 6: Check by hand** in a browser at 390×844 and 1366×900 (`flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:8000`). On the phone size the first result card should be visible without scrolling, and the Filters sheet should open and close with the keyboard (Tab to the button, Enter, Tab to Done, Enter).
- [ ] **Step 7: Update the README** (Persona round one heading): the keys `filters-button`, `filters-sheet`, `filters-done`; the helpers; "on a phone, sources and language are in a sheet; format stays on the page"; and the change from the old layout test.
- [ ] **Step 8: Commit** `feat: compact filter bar on phones; sources and language in a sheet (persona round one)`

### Task 8: Say why a result appeared and what language it is in

Maya ("Heartstopper"), Jordan ("time travel"), Daniel, Elaine and Lucía could not tell why a result matched, or what language it was in. The app knows the query and each work's title and authors, so it can say when neither one contains the search words. It must not invent "scholarly" or "primary source" labels (ANALYSIS.md recommendation 1).

**Files:**
- Modify: `app/lib/util/format.dart` (new function)
- Modify: `app/lib/ui/results_page.dart:310-365` (`ResultRow`)
- Test: `app/test/format_test.dart`, `app/test/search_results_test.dart`

**Interfaces:**
- Produces: `String? matchNote(SearchQuery query, Work work)`. It returns `'Matched other catalog details, not the title or author'` when the searched words are not all found, and null otherwise. Rules:
  - The words are `query.searchedText`, lower-cased and split on anything that is not a letter or digit (`RegExp(r'[^\p{L}\p{N}]+', unicode: true)`), dropping empty strings.
  - `isbn` or `keyword` (subject) searches: always null. The title cannot show the match, and that is expected.
  - `title` search: null if every word is in the title words of the work or of any of its books.
  - `author` search: null if every word is in the author names.
  - `q` (Anything): null if every word is in the title words, or every word is in the author names.
  - shortcut: no accent folding ("Quixote" vs "Quijote" shows the note); upgrade if round two finds that misleading.
- `ResultRow` changes:
  - The formats line becomes `'<Text and Audio> · <languageName(work.language)>'`, so it reads "Unknown language" when the work's language is null.
  - When `matchNote` is not null, it is shown as `Text(key: Key('result-match-${work.id}'), style: bodySmall)` under the sources line.

- [ ] **Step 1: Write the failing `format_test` cases** (group `matchNote`):
  - `SearchQuery(q: 'Frankenstein')` with the title `'Frankenstein; Or, The Modern Prometheus'` gives null.
  - `SearchQuery(q: 'pride & prejudice')` with `'Pride and Prejudice'` gives null.
  - `SearchQuery(q: 'mary shelley')`, title `'Frankenstein'`, authors `['Shelley, Mary']`: null.
  - `SearchQuery(q: 'Heartstopper')`, title `'Eat Fat, Be Healthy'`: the note.
  - `SearchQuery(q: 'time travel')`, title `'A General History and Collection of Voyages and Travels'`: the note ("time" is missing).
  - `SearchQuery(title: 'Frankenstein')`, work title `'Frankenstein'`, but one book titled `'Frankenstein (1818)'`: null.
  - `SearchQuery(isbn: '9780141439471')`, any title: null. `SearchQuery(keyword: 'democracy')`, any title: null.
- [ ] **Step 2: Write the failing widget test** `'a result shows its language, and a note when the title and author do not match'`: give the fake API one work with matching words and one without, both with `language: 'pl'` on the second. Expect `result-match-<second>` to be found and `result-match-<first>` to find nothing. Expect the text `'Text · Polish'` to be found.
- [ ] **Step 3: Run them and see them fail.** `flutter test test/format_test.dart test/search_results_test.dart`.
- [ ] **Step 4: Implement** `matchNote` and the `ResultRow` lines.
- [ ] **Step 5: Run all app tests.** `flutter test`. Existing tests that look for the exact formats text (`'Text and Audio'`) now need the language suffix; change them and note it in the README.
- [ ] **Step 6: Update the README** (Persona round one heading): `result-match-<id>` and the rules. **Commit** `feat: results say their language and when the title and author do not match (persona round one)`

### Task 9: Show what opening a result will do, and which edition it is

The details page already explains access (`_accessNote`, `details_page.dart:163`) and editions (`_BookCard`, `details_page.dart:199-219`), but the result card shows neither, and its button goes straight in (Elaine, Daniel, Ruth, Sam, Morgan, Priya). This task moves those facts onto the card, for the book the button opens.

**Files:**
- Modify: `app/lib/util/format.dart` (moved and new functions)
- Modify: `app/lib/ui/details_page.dart` (use the moved function)
- Modify: `app/lib/ui/results_page.dart` (`ResultRow`)
- Test: `app/test/format_test.dart`, `app/test/search_results_test.dart`, `app/test/details_page_test.dart`

**Interfaces:**
- Produces: `String accessNote(Book book)`, moved unchanged from `details_page.dart` `_accessNote`. Task 10 changes its wording.
- Produces: `String? bookSummary(Book book)`, which says which copy the button opens, or null when there is nothing to say:
  - Audio: `'Read by <joinNames(narrators)>'` and `formatDuration(audioSeconds)`, joined by `' · '`, each part only when known.
  - Gutenberg text: `'eBook #<sourceId>'`, plus `'Original publication: <originalPublication>'` when known.
  - HathiTrust: `'Volume <volume>'` and `library`, when known.
  - Others: null.
- `ResultRow`, under the button: `Text(bookSummary(best), key: Key('result-edition-${work.id}'))` when it is not null, then `Text(accessNote(best), key: Key('result-access-${work.id}'))`, both `bodySmall`. These are plain text next to the button. The button's accessible label is unchanged, because it already names the book and the outside source.

- [ ] **Step 1: Write the failing `format_test` cases** (group `bookSummary`): a LibriVox book with narrators `['Cori Samuel']` and `audioSeconds: 28740` gives `'Read by Cori Samuel · 7 hr 59 min'`. Gutenberg `sourceId: '41445'`, `originalPublication: '1818'` gives `'eBook #41445 · Original publication: 1818'`. An Open Library book gives null. Use the exact output of `formatDuration` for the expected text.
- [ ] **Step 2: Write the failing widget test** `'a result says which copy its button opens and where it opens'`: a Gutenberg work shows `result-edition-<id>` with `'eBook #'` and `result-access-<id>` with `'Read in this app.'`. A borrowable Open Library work shows `result-access-<id>` containing `'Open Library'` and no `result-edition-<id>`.
- [ ] **Step 3: Run them and see them fail.**
- [ ] **Step 4: Implement.** Move `_accessNote` (the details page calls `accessNote`), add `bookSummary`, and add the two lines to `ResultRow`. Check `smallPhone` at 200% text in `accessibility_test` for overflow.
- [ ] **Step 5: Run all app tests.** `flutter test`. Expected: all pass, including the access-note tests in `details_page_test`.
- [ ] **Step 6: Update the README and commit** `feat: result cards say which copy opens and where (persona round one)`

### Task 10: Be honest about external sites and offline use

Morgan, Sam, Elaine, Ruth and Maya wanted to know before opening whether a book opens here or elsewhere, and whether it works without a connection. Nothing can be read offline yet (spec.md:53), so the app should say so rather than leave it unclear.

**Files:**
- Modify: `app/lib/util/format.dart` (`accessNote` wording)
- Modify: `app/lib/ui/details_page.dart` (offline note)
- Modify: `spec.md` (Reading experience)
- Test: `app/test/format_test.dart`, `app/test/details_page_test.dart`

The home page intro is Task 12.

**Exact copy:**
- `accessNote`:
  - In-app text and audio: unchanged (`'Read in this app.'` / `'Listen in this app.'`).
  - `Access.borrow`: `"Opens $source's website. You need a free account there to borrow it."`
  - `Access.open` for hathitrust: `"Opens HathiTrust's reader in your web browser."`
  - Other `Access.open`: `"Opens $source's website, where it is free to read."`
  - `printDisabled` and `none`: unchanged.
  - When `book.usOnly`: add `' It may open only in the United States.'`
- Details page, key `offline-note`, once, under the work's title: `"You need an internet connection to read or listen. Books can't be saved for offline use yet."`

- [ ] **Step 1: Write the failing tests:** `format_test` gets one case per `accessNote` line above, plus usOnly. `details_page_test`: `offline-note` is found once, with the exact text.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement** the copy.
- [ ] **Step 4: Run all app tests.** `flutter test`. Update the existing tests that assert the old access notes, and note them in the README.
- [ ] **Step 5: Update the spec.** Add to the Reading experience list in spec.md: "Before a book opens, the app says whether it opens here or on another website, what that site needs (such as a free account), and that an internet connection is needed. When offline saving is built, this note changes with it."
- [ ] **Step 6: Commit** `feat: say where books open and that offline reading is not available yet (persona round one)`

### Task 11: A comfort check in the display settings

Ruth and Morgan want to see how text will look before settling in. Morgan saw justified, hyphenated text on a phone. On web the settings sheet covers the book, so changes are made blind. Our own renderer already draws start-aligned text without hyphens; Readium is the one that justifies.

**Files:**
- Modify: `app/lib/reader/settings_sheet.dart` (preview and slider values)
- Modify: `app/lib/reader/readium_engine.dart:153-168` (`epubPreferences`)
- Test: `app/test/reader_test.dart` (settings group), `app/test/readium_engine_test.dart`

**Interfaces:**
- `epubPreferences(settings)` also sets `textAlign: TextAlign.start` and `hyphens: false` (fields of flutter_readium's `EPUBPreferences`), so both engines lay out text the same way.
- Settings sheet, at the top: `settings-preview`, a box in `settings.backgroundColor` showing two paragraphs in `settings.textStyle`, separated by `settings.paragraphSpacing * settings.fontSize`. It rebuilds on each change. Sample text (public domain, *Pride and Prejudice*, ch. 1): `'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.'` and `'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered as the rightful property of some one or other of their daughters.'` Put it under a `Heading('Preview')`.
- Each spacing slider shows its value next to its label: line spacing `'1.5×'` (one decimal), letter and paragraph spacing `'0.10 em'` (two decimals). Keys `setting-line-height-value`, `setting-letter-spacing-value`, `setting-paragraph-spacing-value`.

- [ ] **Step 1: Write the failing tests:**
  - `readium_engine_test`: `'text is start-aligned without hyphens'`: `epubPreferences(const ReaderSettings())` has `textAlign == TextAlign.start` and `hyphens == false`.
  - `reader_test`: `'the settings show a preview in the chosen style'`: open the settings and tap `font-increase`. Expect the first preview `Text`'s style to have `fontSize == 20`. Tap `theme-dark` and expect the preview box's colour to be `0xFF121212`.
  - `reader_test`: `'spacing sliders show their values'`: with the default settings, `setting-line-height-value` reads `'1.5×'` and `setting-paragraph-spacing-value` reads `'1.00 em'`.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.** Keep the sheet scrollable; at 200% text on `smallPhone` the preview must not overflow (`accessibility_test`).
- [ ] **Step 4: Run all app tests.** `flutter test`. Expected: all pass.
- [ ] **Step 5: Check by hand on web,** with a Gutenberg book in Chrome at 390×844: the text is left-aligned with no hyphens, and the preview follows each change.
- [ ] **Step 6: Update the README (settings keys line) and commit** `feat: settings preview and start-aligned text in every reader (persona round one)`

### Task 12: Say what kind of books the app finds

Maya searched for *Heartstopper* and got three unrelated books with no hint that a recent graphic novel was unlikely to be here. Jordan, Sam and Priya said the home page names catalogs but not what they hold. One plain sentence on Home sets the expectation. A note on results pages where nothing matched catches people who skipped it.

The wording must stay true: Open Library lends some in-copyright books, so the text says "many recent books", not "no recent books".

**Files:**
- Modify: `app/lib/ui/home_page.dart:39-42` (intro text)
- Modify: `app/lib/ui/results_page.dart:260-268` (`_ResultsBody`)
- Test: `app/test/home_page_test.dart`, `app/test/search_results_test.dart`

**Interfaces:**
- Consumes: `matchNote(SearchQuery, Work)` from Task 8.

**Exact copy:**
- Home intro (replaces the one sentence), as three `Text`s:
  1. `'Find books that are out of copyright, openly licensed or free to borrow, plus free audiobooks.'` (`bodyLarge`, key `home-intro`)
  2. `"Some open in this app; others open on the library's own website."` (`bodyMedium`)
  3. `'Sources: Project Gutenberg, LibriVox, DOAB, Open Library and HathiTrust.'` (`bodySmall`)
- Results note, key `collection-note`, shown above the result count when there are no results, or when every work on the page has a `matchNote`: `"Nothing here matches by title or author. This app searches books that are out of copyright, openly licensed or free to borrow, so many recent books aren't included."` It is not a live region, because the count and `no-results` already announce the search.
  - With no results, it goes under the existing `no-results` text, which is kept.
  - It is not shown for subject or ISBN searches, where `matchNote` is always null.

- [ ] **Step 1: Write the failing tests:**
  - `home_page_test`: `'home says what kind of books the app finds'` expects `home-intro` with the exact text 1, and texts 2 and 3 to be found.
  - `search_results_test`: `'a search where nothing matches by title or author explains the collection'`: the fake API returns two works whose titles and authors lack "heartstopper". Expect `collection-note` with the exact text.
  - `'no collection note when a result matches'`: one of the works is titled "Heartstopper". Expect `collection-note` to find nothing.
  - `'an empty search shows the collection note under no-results'`: zero works. Expect both `no-results` and `collection-note`.
  - `'no collection note for a subject search'`: `keyword: 'heartstopper'` with non-matching works. Expect nothing.
- [ ] **Step 2: Run them and see them fail.** `flutter test test/home_page_test.dart test/search_results_test.dart`.
- [ ] **Step 3: Implement** the copy, plus `bool _nothingMatches(SearchQuery query, List<Work> works)` in `results_page.dart`. It is true for an empty list, or when every work has a `matchNote`, and false for `keyword` and `isbn` searches.
- [ ] **Step 4: Run all app tests.** `flutter test`. Update any test that asserts the old home sentence, and note it in the README.
- [ ] **Step 5: Check by hand** at 390×844: the three intro lines don't push the example books below the fold.
- [ ] **Step 6: Update the README and commit** `feat: say what kind of books the app finds (persona round one)`

### Task 13: Make round two's browser runs reliable, and record the context

**Files:**
- Modify: `app/lib/main.dart:20-27`
- Modify: `docs/persona-findings-round-one/README.md` (shared review context)
- Modify: `AGENTS.md` (Context)

- [ ] **Step 1: In `main()`,** before `runApp`, add `if (const bool.fromEnvironment('FBR_SEMANTICS')) SemanticsBinding.instance.ensureSemantics();` with the comment: `// Browser test runs: turns on the semantics tree without the "Enable accessibility" placeholder.` Import `package:flutter/semantics.dart` if it is not already imported.
- [ ] **Step 2: Check it.** `cd app && flutter build web --dart-define=BACKEND_URL=http://localhost:8000 --dart-define=FBR_SEMANTICS=true`. Expected: the build succeeds. Serve it, load it once in headless Chromium, and confirm that `flt-semantics` nodes are present without any click.
- [ ] **Step 3: Add to the README's shared review context** for round two: "Rebuild the web app with `--dart-define=FBR_SEMANTICS=true`; seven round-one reviewers lost time to the accessibility placeholder."
- [ ] **Step 4: Add one AGENTS.md Context line:** "Persona round one (2026-10-27, `docs/persona-findings-round-one/`): fixed LibriVox `&amp;` titles, recording choice (details first), 'length unknown' audio, automatic last place (`lastplace:` prefs), phone filters (format inline; sources and language in a `filters-sheet` behind `filters-button`), result cards with language, `matchNote`, `bookSummary` and `accessNote`, a home intro and details `offline-note` that say where books open and that there is no offline reading, a settings preview, and start-aligned text without hyphens in Readium. Open: see the plan's out-of-scope list."
- [ ] **Step 5: Run the full suites** (backend `python -m pytest`, app `flutter test`). Expected: all pass. Commit with `chore: semantics flag for browser test runs; record persona round one`.

---

## Out of scope, needs a decision first

These came from the reviews but each needs a product decision or design before code:

- **"Start reading" past the front matter.** `ReaderEngine` has no table of contents, and finding the first chapter differs between Readium and our renderer. Needs a design.
- **Dyslexia-friendly font.** Bundle Atkinson Hyperlegible or OpenDyslexic (existing next step 2; on web the font must reach Readium's iframe), or relabel the choice until it is bundled. User's call.
- **Language before the search, and several languages at once** (Lucía). This changes `SearchQuery.language` to a list and changes the backend filter.
- **"time travel" ranking** (Jordan). Find out first whether HathiTrust FTS matches the words separately, or whether stopwords are dropped, before changing ranking.
- **Offline saving, citations, curated entry points, result descriptions** (no source gives us a description yet), **and "scholarly / primary source" labels** (no evidence-based way to set them yet). ANALYSIS.md recommendation 6. Match notes, access and edition lines, offline honesty, the comfort check and the collection explanation are Tasks 8–12.
- **A user setting for justified text.** Task 11 makes everything start-aligned; add a setting only if someone asks for justified text.
- **A smaller "Search in" control on phones** (a menu instead of five chips). Wait for round two's feedback on Task 7.
- **The compact player always says "LibriVox recording"** (`audio_player.dart:180`), even for Gutenberg audio. It rarely shows after Task 3; fix it if it is still seen.
