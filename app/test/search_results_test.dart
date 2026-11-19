// Search results: query box on top, filters (left on wide screens, under the
// search box on mobile), one row per work, and a notice when a source is down.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/api/search_api.dart';
import 'package:free_book_reader/models/models.dart';
import 'package:free_book_reader/ui/results_page.dart';
import 'package:free_book_reader/util/format.dart';

import 'helpers/fixtures.dart';
import 'helpers/test_app.dart';

SearchField? searchIn(WidgetTester tester) =>
    tester.widget<DropdownButton<SearchField>>(find.byKey(const Key('search-in'))).value;

void main() {
  group('the list', () {
    testWidgets('shows a row for each work, in a single column', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      final rows = ['w-pride', 'w-quijote', 'w-kinder'];
      for (final id in rows) {
        await tester.ensureVisible(find.byKey(Key('result-$id')));
        expect(find.byKey(Key('result-$id')), findsOneWidget);
      }
      final lefts = rows.map((id) => tester.getTopLeft(find.byKey(Key('result-$id'))).dx).toSet();
      expect(lefts, hasLength(1));
    });

    testWidgets('each row has cover, author, title and a way to access the book',
        (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      final row = find.byKey(const Key('result-w-pride'));
      expect(find.descendant(of: row, matching: find.byKey(const Key('cover'))), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Pride and Prejudice')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Jane Austen')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.byKey(const Key('open-w-pride'))), findsOneWidget);
    });

    testWidgets('shows that a work has both text and audio', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      final row = find.byKey(const Key('result-w-pride'));
      expect(find.descendant(of: row, matching: find.textContaining('Text and audio')), findsOneWidget);
    });

    testWidgets("the access button's name says what it does and for which book", (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      expect(tester.getSemantics(find.byKey(const Key('open-w-pride'))),
          containsSemantics(isButton: true, label: 'Read Pride and Prejudice by Jane Austen'));
      expect(tester.getSemantics(find.byKey(const Key('open-w-quijote'))),
          containsSemantics(
              isButton: true,
              label: 'Borrow Don Quijote de la Mancha by Miguel de Cervantes at Open Library'));
    });

    testWidgets('the cover has a text alternative', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      final cover = find.descendant(
          of: find.byKey(const Key('result-w-pride')), matching: find.byKey(const Key('cover')));
      expect(tester.getSemantics(cover), containsSemantics(label: 'Cover of Pride and Prejudice'));
    });

    testWidgets('covers can load from sites without CORS on web', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      final cover = find.descendant(
          of: find.byKey(const Key('result-w-pride')), matching: find.byKey(const Key('cover')));
      final image = tester.widget<Image>(find.descendant(of: cover, matching: find.byType(Image)));
      expect((image.image as NetworkImage).webHtmlElementStrategy, WebHtmlElementStrategy.fallback);
      expect(tester.getSize(cover).width, 64);
    });

    testWidgets('a work without a cover still shows a placeholder', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      expect(find.descendant(
          of: find.byKey(const Key('result-w-kinder')), matching: find.byKey(const Key('cover'))),
          findsOneWidget);
    });

    testWidgets('tapping a row opens the details page', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      await tester.ensureVisible(find.byKey(const Key('result-w-quijote')));
      await tester.tap(find.byKey(const Key('result-w-quijote')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('details-page')), findsOneWidget);
      expect(find.text('Don Quijote de la Mancha'), findsWidgets);
    });

    testWidgets('announces how many results were found', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      expect(find.text('3 results for "pride"'), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('result-count'))),
          containsSemantics(isLiveRegion: true));
    });
  });

  group('the search box', () {
    testWidgets('shows the query so it can be edited', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      final field = tester.widget<TextField>(find.byKey(const Key('search-field')));
      expect(field.controller!.text, 'pride');
    });

    testWidgets('editing and resubmitting runs a new search', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await searchFor(tester, 'emma');
      expect(env.api.queries.map((q) => q.q), ['pride', 'emma']);
    });
  });

  group('searching by title, author, subject or ISBN', () {
    // Review 2026-10-11, #9: the backend narrows a known-item search, but only if it gets title/author/isbn.
    for (final (key, read) in <(String, String? Function(SearchQuery))>[
      ('anything', (q) => q.q),
      ('title', (q) => q.title),
      ('author', (q) => q.author),
      ('subject', (q) => q.keyword),
      ('isbn', (q) => q.isbn),
    ]) {
      testWidgets('"$key" sends the text in that field only', (tester) async {
        final env = await TestEnv.create();
        await pumpApp(tester, env);
        await chooseSearchField(tester, key);
        await searchFor(tester, 'Pride and Prejudice');
        final query = env.api.queries.single;
        expect(read(query), 'Pride and Prejudice');
        expect(query.toQueryParameters().keys.where((k) => const ['q', 'title', 'author', 'keyword', 'isbn'].contains(k)),
            hasLength(1));
        expect(find.text('3 results for "Pride and Prejudice"'), findsOneWidget);
      });
    }

    testWidgets('the choices are labelled as a group and show which one is chosen', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      // The dropdown is a button named by the group and the current choice.
      expect(tester.getSemantics(find.byKey(const Key('search-in'))).label, startsWith('Search in'));
      expect(searchIn(tester), SearchField.anything);
      await chooseSearchField(tester, 'author');
      expect(searchIn(tester), SearchField.author);
    });

    testWidgets('a search from the home page keeps the choice on the results page', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await chooseSearchField(tester, 'title');
      await searchFor(tester, 'Emma');
      expect(searchIn(tester), SearchField.title);
      await searchFor(tester, 'Persuasion');
      expect(env.api.queries.map((q) => q.title), ['Emma', 'Persuasion']);
    });

    testWidgets('changing a filter keeps the title that was searched for', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await chooseSearchField(tester, 'title');
      await searchFor(tester, 'Emma');
      await tester.tap(find.byKey(const Key('filter-format-audio')));
      await tester.pumpAndSettle();
      expect(env.api.queries.last.title, 'Emma');
      expect(env.api.queries.last.q, isNull);
      expect(env.api.queries.last.format, BookFormat.audio);
    });

    // Persona round one (Jordan): the choice seemed to go back to Anything.
    testWidgets('the Title choice stays after Audio is chosen and after returning from a book', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'The Time Machine');
      await chooseSearchField(tester, 'title');
      await searchFor(tester, 'The Time Machine');
      await tester.tap(find.byKey(const Key('result-w-pride')));
      await tester.pumpAndSettle();
      final open = find.byKey(const Key('open-gutenberg:1342'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-format-audio')));
      await tester.pumpAndSettle();
      expect(searchIn(tester), SearchField.title);
      expect(env.api.queries.last.title, 'The Time Machine');
      expect(env.api.queries.last.format, BookFormat.audio);
    });

    testWidgets('anything that is an ISBN is searched as an ISBN', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, '978-0-14-043072-1');
      expect(env.api.queries.single.isbn, '978-0-14-043072-1');
      expect(env.api.queries.single.q, isNull);
    });
  });

  group('a search that is too long', () {
    // Review 2026-10-11, #14: the backend answers 422 above 300 characters.
    testWidgets('is not sent, and says why', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'a' * 301);
      expect(env.api.queries, isEmpty);
      final message = find.byKey(const Key('search-too-long'));
      expect(message, findsOneWidget);
      expect(find.descendant(of: message, matching: find.textContaining('300')), findsOneWidget);
      expect(tester.getSemantics(message), containsSemantics(isLiveRegion: true));
    });

    testWidgets('300 characters are sent', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'a' * 300);
      expect(env.api.queries.single.q, 'a' * 300);
      expect(find.byKey(const Key('search-too-long')), findsNothing);
    });

    testWidgets('the message goes away once the search is shortened', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'a' * 301);
      await searchFor(tester, 'emma');
      expect(find.byKey(const Key('search-too-long')), findsNothing);
      expect(env.api.queries.single.q, 'emma');
    });

    testWidgets('a 4xx from the server is not blamed on the connection', (tester) async {
      final env = await TestEnv.create();
      env.api.error = const SearchException('The server answered 422.', statusCode: 422);
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      final error = find.byKey(const Key('search-error'));
      expect(find.descendant(of: error, matching: find.textContaining('connection')), findsNothing);
      expect(find.descendant(of: error, matching: find.textContaining("can't be run")), findsOneWidget);
    });
  });

  group('why a result is here (persona round one)', () {
    testWidgets('a result shows its language, and a note when the title and author do not match', (tester) async {
      final json = loadJson('search_response.json') as Map<String, dynamic>;
      final works = json['works'] as List;
      (works[1] as Map<String, dynamic>)['language'] = 'pl';
      works.removeLast();
      await pumpApp(tester, await TestEnv.create(response: SearchResponse.fromJson(json)));
      await searchFor(tester, 'pride');
      expect(find.byKey(const Key('result-match-w-quijote')), findsOneWidget);
      expect(find.byKey(const Key('result-match-w-pride')), findsNothing);
      expect(find.text('Text · Polish'), findsOneWidget);
      expect(find.text('Text and audio · English'), findsOneWidget);
    });
  });

  // UI review 2026-11-18, #9 and #10.
  testWidgets('a result card shows title, author, one facts line, the button and where it opens', (tester) async {
    await pumpApp(tester, await TestEnv.create());
    await searchFor(tester, 'pride');
    final card = find.byKey(const Key('result-w-pride'));
    final work = tester.widget<ResultRow>(find.ancestor(of: card, matching: find.byType(ResultRow))).work;
    expect(find.descendant(of: card, matching: find.text(work.sources.map(sourceName).join(', '))), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('result-edition-w-pride'))).maxLines, 1);
    expect(find.descendant(of: card, matching: find.text('Text and audio · English')), findsOneWidget);
    final body = Theme.of(tester.element(card)).textTheme.bodyMedium!.fontSize!;
    for (final t in tester.widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))) {
      if (t.data == work.title) continue;
      final size = DefaultTextStyle.of(tester.element(find.byWidget(t))).style.merge(t.style).fontSize!;
      expect(size, greaterThanOrEqualTo(body), reason: '"${t.data}"');
    }
  });

  group('what a result opens (persona round one)', () {
    testWidgets('a result says which copy its button opens and where it opens', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      expect(tester.widget<Text>(find.byKey(const Key('result-edition-w-pride'))).data, contains('eBook #'));
      expect(tester.widget<Text>(find.byKey(const Key('result-access-w-pride'))).data, 'Read in this app.');
      expect(tester.widget<Text>(find.byKey(const Key('result-access-w-quijote'))).data, contains('Open Library'));
      expect(find.byKey(const Key('result-edition-w-quijote')), findsNothing);
    });
  });

  group('what the app holds (persona round one)', () {
    const collectionNote = "Nothing here matches by title or author. This app searches books that are out of "
        "copyright, openly licensed or free to borrow, so many recent books aren't included.";
    SearchResponse response(void Function(List works) change) {
      final json = loadJson('search_response.json') as Map<String, dynamic>;
      change(json['works'] as List);
      return SearchResponse.fromJson(json);
    }

    testWidgets('a search where nothing matches by title or author explains the collection', (tester) async {
      await pumpApp(tester, await TestEnv.create(response: response((works) => works.removeLast())));
      await searchFor(tester, 'Heartstopper');
      expect(tester.widget<Text>(find.byKey(const Key('collection-note'))).data, collectionNote);
    });

    testWidgets('no collection note when a result matches', (tester) async {
      await pumpApp(tester, await TestEnv.create(response: response((works) {
        works.removeLast();
        (works.first as Map<String, dynamic>)['title'] = 'Heartstopper';
      })));
      await searchFor(tester, 'Heartstopper');
      expect(find.byKey(const Key('collection-note')), findsNothing);
    });

    testWidgets('an empty search shows the collection note under no-results', (tester) async {
      await pumpApp(tester, await TestEnv.create(response: response((works) => works.clear())));
      await searchFor(tester, 'Heartstopper');
      expect(find.byKey(const Key('no-results')), findsOneWidget);
      expect(find.byKey(const Key('collection-note')), findsOneWidget);
      expect(tester.getRect(find.byKey(const Key('collection-note'))).top,
          greaterThanOrEqualTo(tester.getRect(find.byKey(const Key('no-results'))).bottom));
    });

    testWidgets('no collection note for a subject search', (tester) async {
      await pumpApp(tester, await TestEnv.create(response: response((works) => works.removeLast())));
      await chooseSearchField(tester, 'subject');
      await searchFor(tester, 'heartstopper');
      expect(find.byKey(const Key('collection-note')), findsNothing);
    });
  });

  group('minor fixes', () {
    SearchResponse response(void Function(Map<String, dynamic> json) change) {
      final json = loadJson('search_response.json') as Map<String, dynamic>;
      change(json);
      return SearchResponse.fromJson(json);
    }

    testWidgets('no collection note when a source was missing from the search', (tester) async {
      await pumpApp(tester, await TestEnv.create(response: response((json) {
        (json['works'] as List).clear();
        json['unavailable_sources'] = ['openlibrary'];
        json['skipped'] = [{'source': 'openlibrary', 'reason': 'timeout'}];
      })));
      await searchFor(tester, 'Heartstopper');
      expect(find.byKey(const Key('unavailable-notice')), findsOneWidget);
      expect(find.byKey(const Key('collection-note')), findsNothing);
    });

    testWidgets('no collection note for a search of only punctuation', (tester) async {
      await pumpApp(tester, await TestEnv.create(response: response((json) => (json['works'] as List).clear())));
      await searchFor(tester, '!!!');
      expect(find.byKey(const Key('no-results')), findsOneWidget);
      expect(find.byKey(const Key('collection-note')), findsNothing);
    });

    testWidgets('changes in the filters sheet search once, when it closes', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      final before = env.api.queries.length;
      await openFilters(tester);
      await tester.tap(find.byKey(const Key('filter-source-doab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-source-hathitrust')));
      await tester.pumpAndSettle();
      expect(env.api.queries.length, before);
      await closeFilters(tester);
      expect(env.api.queries.length, before + 1);
      expect(env.api.queries.last.sources, unorderedEquals(['gutenberg', 'librivox', 'openlibrary']));
    });

    testWidgets('closing the sheet without a change does not search', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      final before = env.api.queries.length;
      await openFilters(tester);
      await closeFilters(tester);
      expect(env.api.queries.length, before);
    });
  });

  group('filters', () {
    testWidgets('offer every source, both formats and a language', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      await openFilters(tester);
      for (final id in ['gutenberg', 'librivox', 'doab', 'openlibrary', 'hathitrust']) {
        expect(find.byKey(Key('filter-source-$id')), findsOneWidget, reason: id);
      }
      expect(find.byKey(const Key('filter-format-all')), findsOneWidget);
      expect(find.byKey(const Key('filter-format-text')), findsOneWidget);
      expect(find.byKey(const Key('filter-format-audio')), findsOneWidget);
      expect(find.byKey(const Key('filter-language')), findsOneWidget);
    });

    testWidgets('all sources are searched by default', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      expect(env.api.queries.single.sources, isNull);
      expect(env.api.queries.single.format, isNull);
    });

    testWidgets('searching a single source', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await openFilters(tester);
      for (final id in ['gutenberg', 'doab', 'openlibrary', 'hathitrust']) {
        await tester.tap(find.byKey(Key('filter-source-$id')));
        await tester.pumpAndSettle();
      }
      await closeFilters(tester);
      expect(env.api.queries.last.sources, ['librivox']);
    });

    testWidgets('searching selected sources', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await openFilters(tester);
      await tester.tap(find.byKey(const Key('filter-source-librivox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-source-doab')));
      await tester.pumpAndSettle();
      await closeFilters(tester);
      expect(env.api.queries.last.sources, unorderedEquals(['gutenberg', 'openlibrary', 'hathitrust']));
    });

    testWidgets('at least one source always stays selected', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await openFilters(tester);
      for (final id in ['gutenberg', 'librivox', 'doab', 'openlibrary', 'hathitrust']) {
        await tester.tap(find.byKey(Key('filter-source-$id')));
        await tester.pumpAndSettle();
      }
      await closeFilters(tester);
      expect(env.api.queries.last.sources, isNotEmpty);
    });

    testWidgets('choosing audio searches for audio', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await tester.tap(find.byKey(const Key('filter-format-audio')));
      await tester.pumpAndSettle();
      expect(env.api.queries.last.format, BookFormat.audio);
      expect(env.api.queries.last.q, 'pride');
    });

    testWidgets('choosing text searches for text, and "All" clears it', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await tester.tap(find.byKey(const Key('filter-format-text')));
      await tester.pumpAndSettle();
      expect(env.api.queries.last.format, BookFormat.text);
      await tester.tap(find.byKey(const Key('filter-format-all')));
      await tester.pumpAndSettle();
      expect(env.api.queries.last.format, isNull);
    });

    testWidgets('the selected format is exposed as selected to screen readers', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      await tester.tap(find.byKey(const Key('filter-format-audio')));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.byKey(const Key('filter-format-audio'))),
          containsSemantics(isSelected: true));
    });

    testWidgets('choosing a language searches in that language', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'les miserables');
      await openFilters(tester);
      await tester.tap(find.byKey(const Key('filter-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('French').last);
      await tester.pumpAndSettle();
      await closeFilters(tester);
      expect(env.api.queries.last.language, 'fr');
    });
  });

  group('filters on a phone (persona round one)', () {
    String buttonText(WidgetTester tester) => tester
        .widget<Text>(find.descendant(of: find.byKey(const Key('filters-button')), matching: find.byType(Text)))
        .data!;

    testWidgets('on a phone the sources and language are behind a Filters button', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      expect(find.byKey(const Key('filter-format-audio')), findsOneWidget);
      expect(find.byKey(const Key('filter-source-doab')), findsNothing);
      expect(find.byKey(const Key('filter-language')), findsNothing);
      expect(buttonText(tester), 'All sources · Any language');
    });

    testWidgets('the button shows what is chosen', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await openFilters(tester);
      await tester.tap(find.byKey(const Key('filter-source-doab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-source-hathitrust')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spanish').last);
      await tester.pumpAndSettle();
      await closeFilters(tester);
      expect(buttonText(tester), '3 of 5 sources · Spanish');
      expect(env.api.queries.last.sources, unorderedEquals(['gutenberg', 'librivox', 'openlibrary']));
      expect(env.api.queries.last.language, 'es');
    });

    testWidgets('a source turned off stays off when the sheet is opened again', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      await openFilters(tester);
      await tester.tap(find.byKey(const Key('filter-source-librivox')));
      await tester.pumpAndSettle();
      await closeFilters(tester);
      await openFilters(tester);
      expect(tester.widget<FilterChip>(find.byKey(const Key('filter-source-librivox'))).selected, isFalse);
    });

    testWidgets('the first result is higher on a phone', (tester) async {
      await pumpApp(tester, await TestEnv.create(), size: phone);
      await searchFor(tester, 'pride');
      final box = tester.getRect(find.byKey(const Key('search-field')));
      final first = tester.getRect(find.byKey(const Key('result-w-pride')));
      // 500 before the filters moved into a sheet, 308 after. The test font is wide ("All formats" is 209 px),
      // so the format chips take two lines here; on a real phone they take one.
      expect(first.top - box.bottom, lessThanOrEqualTo(320));
    });

    testWidgets('on a wide screen nothing moves into a sheet', (tester) async {
      await pumpApp(tester, await TestEnv.create(), size: desktop);
      await searchFor(tester, 'pride');
      expect(find.byKey(const Key('filters-button')), findsNothing);
      expect(find.byKey(const Key('filter-source-doab')), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('on a wide screen the filters are to the left of the results', (tester) async {
      await pumpApp(tester, await TestEnv.create(), size: desktop);
      await searchFor(tester, 'pride');
      final filters = tester.getRect(find.byKey(const Key('filters')));
      final results = tester.getRect(find.byKey(const Key('result-w-pride')));
      expect(filters.right, lessThanOrEqualTo(results.left));
    });

    // Review 2026-10-11-main, #22: the search box moved between the two layouts and started over.
    testWidgets('resizing between the layouts keeps what is in the search box', (tester) async {
      await pumpApp(tester, await TestEnv.create(), size: desktop);
      await chooseSearchField(tester, 'title');
      await searchFor(tester, 'Frankenstein');
      await tester.enterText(find.byKey(const Key('search-field')), 'Franken');
      tester.view.physicalSize = phone;
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('search-field'))).controller!.text, 'Franken');
      expect(searchIn(tester), SearchField.title);
    });

    testWidgets('on mobile the filters sit under the search box and above the results',
        (tester) async {
      await pumpApp(tester, await TestEnv.create(), size: phone);
      await searchFor(tester, 'pride');
      final box = tester.getRect(find.byKey(const Key('search-field')));
      final filters = tester.getRect(find.byKey(const Key('filters')));
      final firstResult = tester.getRect(find.byKey(const Key('result-w-pride')));
      expect(filters.top, greaterThanOrEqualTo(box.bottom));
      expect(filters.bottom, lessThanOrEqualTo(firstResult.top));
    });
  });

  group('states', () {
    testWidgets('shows a progress indicator with a name while searching', (tester) async {
      final env = await TestEnv.create();
      env.api.hold = Completer<SearchResponse>();
      await pumpApp(tester, env);
      await tester.enterText(find.byKey(const Key('search-field')), 'pride');
      await tester.tap(find.byKey(const Key('search-submit')));
      // A pushed route is offstage for its first frame (Flutter measures heroes
      // then), and its semantics appear once the page transition ends.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('searching')), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('searching'))),
          containsSemantics(label: 'Searching', isLiveRegion: true));
      env.api.hold!.complete(env.api.response);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('searching')), findsNothing);
    });

    testWidgets('says so when nothing matches', (tester) async {
      final env = await TestEnv.create(
          response: const SearchResponse(works: [], unavailableSources: []));
      await pumpApp(tester, env);
      await searchFor(tester, 'zzzz');
      expect(find.byKey(const Key('no-results')), findsOneWidget);
      expect(find.textContaining('No results'), findsOneWidget);
    });

    testWidgets('shows an error with a retry button when search fails', (tester) async {
      final env = await TestEnv.create();
      env.api.error = Exception('boom');
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      expect(find.byKey(const Key('search-error')), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('search-error'))),
          containsSemantics(isLiveRegion: true));
      env.api.error = null;
      await tester.tap(find.byKey(const Key('retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('result-w-pride')), findsOneWidget);
    });

    testWidgets('warns that results may be incomplete when a source is down', (tester) async {
      final env = await TestEnv.create();
      env.api.response = SearchResponse(
          works: env.api.response.works, unavailableSources: const ['doab', 'librivox']);
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      final notice = find.byKey(const Key('unavailable-notice'));
      expect(notice, findsOneWidget);
      expect(find.descendant(of: notice, matching: find.textContaining('DOAB')), findsOneWidget);
      expect(find.descendant(of: notice, matching: find.textContaining('LibriVox')), findsOneWidget);
      expect(find.descendant(of: notice, matching: find.textContaining('24 hours')), findsOneWidget);
      expect(tester.getSemantics(notice), containsSemantics(isLiveRegion: true));
    });

    testWidgets('a slow source is not said to be down for 24 hours', (tester) async {
      // Review 2026-10-11, #13: a timeout is asked again on the next search.
      final env = await TestEnv.create();
      env.api.response = SearchResponse(
          works: env.api.response.works,
          unavailableSources: const ['librivox', 'doab'],
          skipped: const [
            SkippedSource(source: 'doab', reason: SkipReason.timeout),
            SkippedSource(source: 'librivox', reason: SkipReason.busy),
          ]);
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      final notice = find.byKey(const Key('unavailable-notice'));
      expect(find.descendant(of: notice, matching: find.textContaining('24 hours')), findsNothing);
      expect(find.descendant(of: notice, matching: find.textContaining('too slow')), findsOneWidget);
      expect(find.descendant(of: notice, matching: find.textContaining('DOAB')), findsOneWidget);
      expect(find.descendant(of: notice, matching: find.textContaining('LibriVox')), findsOneWidget);
    });

    testWidgets('a source in an outage and a slow one get their own wording', (tester) async {
      final env = await TestEnv.create();
      env.api.response = SearchResponse(
          works: env.api.response.works,
          unavailableSources: const ['librivox', 'doab'],
          skipped: const [
            SkippedSource(source: 'doab', reason: SkipReason.timeout),
            SkippedSource(source: 'librivox', reason: SkipReason.outage),
          ]);
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      final notice = find.byKey(const Key('unavailable-notice'));
      expect(find.descendant(of: notice, matching: find.textContaining('24 hours')), findsOneWidget);
      expect(find.descendant(of: notice, matching: find.textContaining('too slow')), findsOneWidget);
    });

    testWidgets('a source that could not run the search is not said to be down', (tester) async {
      final env = await TestEnv.create();
      env.api.response = SearchResponse(
          works: env.api.response.works,
          unavailableSources: const ['doab'],
          skipped: const [SkippedSource(source: 'doab', reason: SkipReason.rejected)]);
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      final notice = find.byKey(const Key('unavailable-notice'));
      expect(find.descendant(of: notice, matching: find.textContaining('24 hours')), findsNothing);
      expect(find.descendant(of: notice, matching: find.textContaining('DOAB')), findsOneWidget);
    });

    testWidgets('shows no warning when every source answered', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      expect(find.byKey(const Key('unavailable-notice')), findsNothing);
    });

    testWidgets('results still show when a source is down', (tester) async {
      final env = await TestEnv.create();
      env.api.response = SearchResponse(
          works: env.api.response.works, unavailableSources: const ['doab']);
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      expect(find.byKey(const Key('result-w-pride')), findsOneWidget);
    });
  });
}
