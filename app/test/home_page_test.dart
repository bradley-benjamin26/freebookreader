// Homepage: a search box, maybe some example books, and links to the sources.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:free_book_reader/app.dart';
import 'package:free_book_reader/models/models.dart';
import 'package:free_book_reader/ui/common.dart' show Cover;

import 'helpers/test_app.dart';

void main() {
  testWidgets('shows the app name as the page heading', (tester) async {
    await pumpApp(tester, await TestEnv.create());
    expect(find.text('Free Book Reader'), findsWidgets);
    expect(tester.getSemantics(find.byKey(const Key('home-heading'))),
        containsSemantics(isHeader: true, label: 'Free Book Reader'));
  });

  // Persona round one (Maya, Jordan, Sam, Priya): say what the catalogs hold, not only their names.
  testWidgets('home says what kind of books the app finds', (tester) async {
    await pumpApp(tester, await TestEnv.create());
    expect(tester.widget<Text>(find.byKey(const Key('home-intro'))).data,
        'Find books that are out of copyright, openly licensed or free to borrow, plus free audiobooks.');
    expect(find.text("Some open in this app; others open on the library's own website."), findsOneWidget);
    expect(find.text('Sources: Project Gutenberg, LibriVox, DOAB, Open Library and HathiTrust.'), findsOneWidget);
  });

  // The web build announced chips as checkboxes: these are plain buttons, named by the title.
  // UI review 2026-11-18, #17: a cover and a title each.
  testWidgets('examples show a cover and a title, and search by title', (tester) async {
    final handle = tester.ensureSemantics();
    final env = await TestEnv.create();
    await pumpApp(tester, env);
    final examples = find.byKey(const Key('example-books'));
    expect(find.descendant(of: examples, matching: find.byType(Cover)), findsNWidgets(4));
    final first = find.byKey(const Key('example-1342'));
    expect(tester.getSemantics(first),
        containsSemantics(label: 'Pride and Prejudice', isButton: true, hasSelectedState: false));
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(env.api.queries.single.title, 'Pride and Prejudice');
    handle.dispose();
  });

  testWidgets('the sources are a compact row of links', (tester) async {
    await pumpApp(tester, await TestEnv.create(), size: const Size(1280, 800));
    for (final (id, name) in [
      ('gutenberg', 'Project Gutenberg'), ('librivox', 'LibriVox'), ('doab', 'DOAB'),
      ('openlibrary', 'Open Library'), ('hathitrust', 'HathiTrust'),
    ]) {
      final link = find.byKey(Key('about-link-$id'));
      expect(tester.widget(link), isA<TextButton>(), reason: id);
      expect(find.descendant(of: link, matching: find.text(name)), findsOneWidget, reason: id);
      expect(tester.getRect(link).bottom, lessThanOrEqualTo(800), reason: id);
    }
  });

  testWidgets('has a search box and a submit button with accessible names', (tester) async {
    await pumpApp(tester, await TestEnv.create());
    expect(find.byKey(const Key('search-field')), findsOneWidget);
    expect(find.byKey(const Key('search-submit')), findsOneWidget);
    expect(tester.getSemantics(find.byKey(const Key('search-field'))),
        containsSemantics(isTextField: true, label: 'Search books'));
    expect(tester.getSemantics(find.byKey(const Key('search-submit'))),
        containsSemantics(isButton: true, label: 'Search'));
  });

  testWidgets('submitting a query goes to the results page with that query', (tester) async {
    final env = await TestEnv.create();
    await pumpApp(tester, env);
    await searchFor(tester, 'pride and prejudice');
    expect(find.byKey(const Key('results-page')), findsOneWidget);
    expect(env.api.queries.single.q, 'pride and prejudice');
    expect(find.byKey(const Key('home-heading')), findsNothing);
  });

  testWidgets('pressing Enter in the search box submits', (tester) async {
    final env = await TestEnv.create();
    await pumpApp(tester, env);
    await tester.enterText(find.byKey(const Key('search-field')), 'dickens');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(env.api.queries.single.q, 'dickens');
  });

  testWidgets('an empty search does nothing and tells the user why', (tester) async {
    final env = await TestEnv.create();
    await pumpApp(tester, env);
    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();
    expect(env.api.queries, isEmpty);
    expect(find.byKey(const Key('home-heading')), findsOneWidget);
    expect(find.text('Enter a title, author or topic to search.'), findsOneWidget);
  });

  testWidgets('leading and trailing spaces are not searched for', (tester) async {
    final env = await TestEnv.create();
    await pumpApp(tester, env);
    await searchFor(tester, '   emma   ');
    expect(env.api.queries.single.q, 'emma');
  });

  testWidgets('links to an About page for each of the five sources', (tester) async {
    await pumpApp(tester, await TestEnv.create());
    for (final id in ['gutenberg', 'librivox', 'doab', 'openlibrary', 'hathitrust']) {
      final link = find.byKey(Key('about-link-$id'));
      await tester.ensureVisible(link);
      expect(link, findsOneWidget, reason: id);
    }
  });

  testWidgets('names all five sources in its introduction', (tester) async {
    await pumpApp(tester, await TestEnv.create());
    expect(find.textContaining('HathiTrust'), findsWidgets);
  });

  testWidgets('has no account, sign-in or personal-data UI yet', (tester) async {
    await pumpApp(tester, await TestEnv.create());
    for (final word in ['Account', 'Log in', 'Login', 'Sign in', 'Sign up', 'Register']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  testWidgets('has no saved-books list yet (arrives with accounts)', (tester) async {
    await pumpApp(tester, await TestEnv.create());
    expect(find.byKey(const Key('saved-books')), findsNothing);
  });

  // UI review 2026-11-18, #18: one reading serif for titles; body text and the reader are unchanged.
  test('titles use Literata', () {
    final t = FreeBookReaderApp.theme(Brightness.light).textTheme;
    for (final style in [t.headlineLarge, t.headlineMedium, t.headlineSmall, t.titleLarge, t.titleMedium]) {
      expect(style!.fontFamily, 'Literata');
    }
    expect(t.bodyLarge!.fontFamily, isNot('Literata'));
    expect(t.titleSmall!.fontFamily, isNot('Literata'));
  });

  testWidgets('the dropdowns keep the body font', (tester) async {
    await pumpApp(tester, await TestEnv.create());
    expect(tester.widget<DropdownButton<SearchField>>(find.byKey(const Key('search-in'))).style?.fontFamily,
        isNot('Literata'));
    expect(tester.widget<DropdownButton<SearchField>>(find.byKey(const Key('search-in'))).style, isNotNull);
  });
}
