// Each source has a page saying what it is and how it works, how to use it
// normally, and a donation button. (Usability testing of these pages is manual.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

Future<void> openAbout(WidgetTester tester, String id) async {
  final link = find.byKey(Key('about-link-$id'));
  await tester.ensureVisible(link);
  await tester.tap(link);
  await tester.pumpAndSettle();
}

void main() {
  for (final entry in {
    'gutenberg': 'Project Gutenberg',
    'librivox': 'LibriVox',
    'doab': 'DOAB',
    'openlibrary': 'Open Library',
    'hathitrust': 'HathiTrust',
  }.entries) {
    testWidgets('${entry.value}: shows what it is, how it works and how to access it',
        (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openAbout(tester, entry.key);
      expect(find.byKey(const Key('about-page')), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('about-title'))),
          containsSemantics(isHeader: true, label: entry.value));
      expect(find.byKey(const Key('about-description')), findsOneWidget);
      expect(find.byKey(const Key('about-how-it-works')), findsOneWidget);
      expect(find.byKey(const Key('about-how-to-access')), findsOneWidget);
    });

    testWidgets('${entry.value}: has a donate button', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAbout(tester, entry.key);
      final donate = find.byKey(const Key('donate'));
      await tester.ensureVisible(donate);
      expect(tester.getSemantics(donate),
          containsSemantics(isButton: true, label: 'Donate to ${entry.value}'));
      await tester.tap(donate);
      await tester.pumpAndSettle();
      expect(env.urls.opened.single.scheme, 'https');
      expect(env.urls.opened.single.toString(),
          env.api.sourceInfos.firstWhere((s) => s.id == entry.key).donationUrl);
    });
  }

  testWidgets('has a link to the source website', (tester) async {
    final env = await TestEnv.create();
    await pumpApp(tester, env);
    await openAbout(tester, 'librivox');
    final visit = find.byKey(const Key('visit-website'));
    await tester.ensureVisible(visit);
    await tester.tap(visit);
    await tester.pumpAndSettle();
    expect(env.urls.opened.single.toString(), 'https://librivox.org');
  });

  testWidgets('says whether books open in the app or at the source', (tester) async {
    await pumpApp(tester, await TestEnv.create());
    String note() => tester.widget<Text>(find.byKey(const Key('about-reading-note'))).data!;
    await openAbout(tester, 'openlibrary');
    final external = note();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openAbout(tester, 'gutenberg');
    final inApp = note();
    expect(external, isNotEmpty);
    expect(inApp, isNotEmpty);
    expect(external, isNot(inApp));
  });

  testWidgets('shows an error with retry when the source details cannot load', (tester) async {
    final env = await TestEnv.create();
    final good = env.api.sourceInfos;
    env.api.sourceInfos = [];
    await pumpApp(tester, env);
    await openAbout(tester, 'gutenberg');
    expect(find.byKey(const Key('about-error')), findsOneWidget);
    env.api.sourceInfos = good;
    await tester.tap(find.byKey(const Key('retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('about-title')), findsOneWidget);
  });

  testWidgets('back returns to the previous page', (tester) async {
    await pumpApp(tester, await TestEnv.create());
    await openAbout(tester, 'doab');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-heading')), findsOneWidget);
  });
}
