// Search results: query box on top, filters (left on wide screens, under the
// search box on mobile), one row per work, and a notice when a source is down.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/models/models.dart';

import 'helpers/test_app.dart';

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

    testWidgets('each row has cover, author, title, source and a way to access the book',
        (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      final row = find.byKey(const Key('result-w-pride'));
      expect(find.descendant(of: row, matching: find.byKey(const Key('cover'))), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Pride and Prejudice')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Jane Austen')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('Project Gutenberg')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.byKey(const Key('open-w-pride'))), findsOneWidget);
    });

    testWidgets('a work available from several sources lists them all', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      final row = find.byKey(const Key('result-w-pride'));
      for (final name in ['Project Gutenberg', 'LibriVox', 'Open Library']) {
        expect(find.descendant(of: row, matching: find.textContaining(name)), findsWidgets, reason: name);
      }
    });

    testWidgets('shows that a work has both text and audio', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      final row = find.byKey(const Key('result-w-pride'));
      expect(find.descendant(of: row, matching: find.textContaining('Text')), findsWidgets);
      expect(find.descendant(of: row, matching: find.textContaining('Audio')), findsWidgets);
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

  group('filters', () {
    testWidgets('offer every source, both formats and a language', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await searchFor(tester, 'pride');
      for (final id in ['gutenberg', 'librivox', 'doab', 'openlibrary']) {
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
      for (final id in ['gutenberg', 'doab', 'openlibrary']) {
        await tester.tap(find.byKey(Key('filter-source-$id')));
        await tester.pumpAndSettle();
      }
      expect(env.api.queries.last.sources, ['librivox']);
    });

    testWidgets('searching selected sources', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await tester.tap(find.byKey(const Key('filter-source-librivox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-source-doab')));
      await tester.pumpAndSettle();
      expect(env.api.queries.last.sources, unorderedEquals(['gutenberg', 'openlibrary']));
    });

    testWidgets('at least one source always stays selected', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      for (final id in ['gutenberg', 'librivox', 'doab', 'openlibrary']) {
        await tester.tap(find.byKey(Key('filter-source-$id')));
        await tester.pumpAndSettle();
      }
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
      await tester.tap(find.byKey(const Key('filter-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('French').last);
      await tester.pumpAndSettle();
      expect(env.api.queries.last.language, 'fr');
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
      await tester.pump();
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
