// Details page: the full metadata of a work, plus every way to get at it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

void main() {
  group('metadata', () {
    testWidgets('shows the title as the page heading', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      expect(find.byKey(const Key('details-page')), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('details-title'))),
          containsSemantics(isHeader: true, label: 'Pride and Prejudice'));
    });

    testWidgets('lists author, language, sources and identifiers', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      final meta = find.byKey(const Key('details-metadata'));
      for (final text in ['Jane Austen', 'English', 'Project Gutenberg', 'LibriVox', 'Open Library',
        '9780140430721']) {
        expect(find.descendant(of: meta, matching: find.textContaining(text)), findsWidgets,
            reason: text);
      }
      expect(find.descendant(of: meta, matching: find.textContaining('ISBN')), findsWidgets);
    });

    testWidgets('shows a work with an unknown language without crashing', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-quijote');
      expect(find.descendant(
          of: find.byKey(const Key('details-metadata')), matching: find.textContaining('Spanish')),
          findsWidgets);
    });

    testWidgets('has a large cover with a text alternative', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      expect(tester.getSemantics(find.byKey(const Key('details-cover'))),
          containsSemantics(label: 'Cover of Pride and Prejudice'));
    });

    testWidgets('each book is listed with its source and format', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      for (final key in ['gutenberg:1342', 'librivox:253', 'openlibrary:OL66554W']) {
        await tester.ensureVisible(find.byKey(Key('book-$key')));
        expect(find.byKey(Key('book-$key')), findsOneWidget, reason: key);
      }
    });

    testWidgets('an audiobook shows its narrators and length', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      final book = find.byKey(const Key('book-librivox:253'));
      await tester.ensureVisible(book);
      expect(find.descendant(of: book, matching: find.textContaining('Chris Goringe')), findsOneWidget);
      expect(find.descendant(of: book, matching: find.textContaining('Kara Shallenberg')), findsOneWidget);
      expect(find.descendant(of: book, matching: find.textContaining('13 hr 6 min')), findsOneWidget);
    });

    testWidgets('a book with a page count shows it', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-quijote');
      expect(find.textContaining('863 pages'), findsOneWidget);
    });

    testWidgets('explains how each book can be accessed', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-quijote');
      expect(find.textContaining('Borrow'), findsWidgets);
    });

    testWidgets('each book links to the source page', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openDetails(tester, 'w-pride');
      final link = find.byKey(const Key('source-link-gutenberg:1342'));
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(env.urls.opened.single.toString(), 'https://www.gutenberg.org/ebooks/1342');
    });
  });

  group('getting to the book', () {
    testWidgets('a text book that can be read in the app opens the reader', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      expect(find.byKey(const Key('reader-page')), findsOneWidget);
      expect(env.loader.requests.single.url, contains('gutenberg.org/ebooks/1342.html'));
    });

    testWidgets('an audiobook opens the player', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'librivox:253');
      expect(find.byKey(const Key('audio-page')), findsOneWidget);
    });

    testWidgets('a DOAB pdf opens the reader with the pdf viewer', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-kinder', 'doab:20.500.12854/95506');
      expect(find.byKey(const Key('pdf-viewer')), findsOneWidget);
    });

    testWidgets('a book that cannot be read in the app opens at its source', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-quijote', 'openlibrary:OL503666W');
      expect(env.urls.opened.single.toString(), 'https://openlibrary.org/works/OL503666W');
      expect(find.byKey(const Key('reader-page')), findsNothing);
      expect(find.byKey(const Key('details-page')), findsOneWidget);
    });

    testWidgets('the button name says where it goes', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      final button = find.byKey(const Key('open-openlibrary:OL66554W'));
      await tester.ensureVisible(button);
      expect(tester.getSemantics(button),
          containsSemantics(isButton: true, label: 'View Pride and Prejudice by Jane Austen at Open Library'));
    });
  });

  group('the results-page button goes straight to the best way in', () {
    testWidgets('prefers reading in the app', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await tester.tap(find.byKey(const Key('open-w-pride')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-page')), findsOneWidget);
    });

    testWidgets('falls back to the source when the app cannot show it', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await tester.tap(find.byKey(const Key('open-w-quijote')));
      await tester.pumpAndSettle();
      expect(env.urls.opened.single.toString(), 'https://openlibrary.org/works/OL503666W');
    });
  });

  group('navigation', () {
    testWidgets('going back returns to the results with the same query', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openDetails(tester, 'w-pride');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('results-page')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('search-field'))).controller!.text, 'pride');
    });
  });
}
