// Homepage: a search box, maybe some example books, and links to the sources.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('shows example books that can be searched with one tap', (tester) async {
    final env = await TestEnv.create();
    await pumpApp(tester, env);
    final examples = find.descendant(
        of: find.byKey(const Key('example-books')), matching: find.byType(ActionChip));
    expect(examples, findsAtLeastNWidgets(3));
    await tester.tap(examples.first);
    await tester.pumpAndSettle();
    expect(env.api.queries, hasLength(1));
    expect(find.byKey(const Key('results-page')), findsOneWidget);
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
}
