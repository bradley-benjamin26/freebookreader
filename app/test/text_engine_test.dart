// Our own renderer (TextReaderEngine), which shows books everywhere but web:
// paragraphs drawn by the app, page-turner and scroll view, and how display
// settings and positions work in it. Runs through the whole app, so the
// reader page's controls drive it as they would for a user.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/reader/content.dart';
import 'package:free_book_reader/reader/reader_settings.dart';

import 'helpers/fakes.dart';
import 'helpers/test_app.dart';

const gutenberg = 'gutenberg:1342';

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('reader-settings-button')));
  await tester.pumpAndSettle();
}

Future<void> closeSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('settings-close')));
  await tester.pumpAndSettle();
}

Future<void> chooseView(WidgetTester tester, String view) async {
  await openSettings(tester);
  await tester.tap(find.byKey(Key('view-$view')));
  await tester.pumpAndSettle();
  await closeSettings(tester);
}

TextStyle pageStyle(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('reader-page-text'))).style!;

String pageText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('reader-page-text'))).data!;

Future<TestEnv> textEnv(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  final env = await TestEnv.create(prefsValues: prefs, textEngine: true);
  await pumpApp(tester, env);
  return env;
}

void main() {
  group('loading', () {
    testWidgets("downloads the book's text once and shows it", (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.textContaining('Paragraph 0.'), findsOneWidget);
      expect(env.loader.requests.single.url, 'https://www.gutenberg.org/ebooks/1342.html.images');
    });

    testWidgets('a download error offers retry, which loads the book', (tester) async {
      final env = await textEnv(tester);
      env.loader.failNext = true;
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.byKey(const Key('load-error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-page-text')), findsOneWidget);
    });

    testWidgets('a pdf from the loader is an error, not a crash', (tester) async {
      final env = await textEnv(tester);
      env.loader.content = const PdfContent('https://example.org/a.pdf');
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.byKey(const Key('load-error')), findsOneWidget);
    });

    testWidgets('the text is available to screen readers', (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      final handle = tester.ensureSemantics();
      expect(tester.getSemantics(find.byKey(const Key('reader-page-text'))).label,
          contains('Paragraph 0.'));
      handle.dispose();
    });
  });

  group('page-turner view', () {
    testWidgets('splits the book into pages that fit the screen', (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.byKey(const Key('reader-scroll')), findsNothing);
      expect(pageNumber(tester), 1);
      expect(pageCount(tester), greaterThan(3));
    });

    testWidgets('turning the page shows the next text', (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      final first = pageText(tester);
      await nextPage(tester);
      expect(pageNumber(tester), 2);
      expect(pageText(tester), isNot(first));
      await tester.tap(find.byKey(const Key('previous-page')));
      await tester.pumpAndSettle();
      expect(pageText(tester), first);
    });

    testWidgets('next is disabled on the last page', (tester) async {
      final env = await textEnv(tester);
      env.loader.content = longText(paragraphs: 6);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, pageCount(tester) - 1);
      expect(pageNumber(tester), pageCount(tester));
      expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('next-page'))).onPressed, isNull);
    });

    testWidgets('page count changes with font size', (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      final before = pageCount(tester);
      await openSettings(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('font-increase')));
        await tester.pumpAndSettle();
      }
      await closeSettings(tester);
      expect(pageCount(tester), greaterThan(before));
    });

    testWidgets('a font size change keeps the first word on screen', (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, 3);
      String words(String text) => text.split(RegExp(r'\s+')).join(' ');
      final opening = words(pageText(tester)).split(' ').take(5).join(' ');
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('font-increase')));
      await tester.pumpAndSettle();
      await closeSettings(tester);
      expect(words(pageText(tester)), contains(opening));
    });
  });

  group('scroll view', () {
    testWidgets('shows every paragraph in one list', (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await chooseView(tester, 'scroll');
      expect(find.byKey(const Key('reader-scroll')), findsOneWidget);
      expect(find.byKey(const Key('reader-paragraph-0')), findsOneWidget);
    });

    testWidgets('switching views keeps your place', (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, 4);
      await chooseView(tester, 'scroll');
      expect(find.byKey(const Key('reader-paragraph-0')), findsNothing);
      await chooseView(tester, 'page-turner');
      expect(pageNumber(tester), closeTo(5, 1));
    });

    testWidgets('paragraph spacing applies', (tester) async {
      final env = await textEnv(tester, prefs: {'reader_settings': '{"viewMode":"scroll"}'});
      await openBook(tester, env, 'w-pride', gutenberg);
      double gap() =>
          tester.getTopLeft(find.byKey(const Key('reader-paragraph-1'))).dy -
          tester.getBottomLeft(find.byKey(const Key('reader-paragraph-0'))).dy;
      final before = gap();
      await openSettings(tester);
      final handle = tester.ensureSemantics();
      tester.semantics.increase(sliderNamed('Paragraph spacing'));
      await tester.pumpAndSettle();
      await closeSettings(tester);
      expect(gap(), greaterThan(before));
      handle.dispose();
    });
  });

  group('display settings', () {
    testWidgets('start from the defaults', (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(pageStyle(tester).fontSize, 18);
      expect(pageStyle(tester).height, 1.5);
      expect(pageStyle(tester).color, const ReaderSettings().textColor);
    });

    testWidgets('font size, font, line and letter spacing change the text', (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      final family = pageStyle(tester).fontFamily;
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('font-increase')));
      await tester.tap(find.byKey(const Key('font-sansSerif')));
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();
      tester.semantics.increase(sliderNamed('Line spacing'));
      tester.semantics.increase(sliderNamed('Letter spacing'));
      await tester.pumpAndSettle();
      handle.dispose();
      expect(pageStyle(tester).fontSize, 20);
      expect(pageStyle(tester).fontFamily, isNot(family));
      expect(pageStyle(tester).height, greaterThan(1.5));
      expect(pageStyle(tester).letterSpacing, greaterThan(0));
    });

    testWidgets('dark mode changes the text color', (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('theme-dark')));
      await tester.pumpAndSettle();
      expect(pageStyle(tester).color, const ReaderSettings(theme: ReaderTheme.dark).textColor);
    });

    testWidgets('saved settings apply when the book opens', (tester) async {
      final env = await textEnv(tester, prefs: {'reader_settings': '{"fontSize":28}'});
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(pageStyle(tester).fontSize, 28);
    });
  });

  group('positions and bookmarks', () {
    testWidgets('a bookmark holds the page as progress and the first word as locator', (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, 2);
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pumpAndSettle();
      final bookmark = env.bookmarks.load(gutenberg)!;
      expect(bookmark.progress, closeTo(2 / (pageCount(tester) - 1), 0.001));
      expect(bookmark.locator, matches(RegExp(r'^word:[1-9]\d*$')));
    });

    testWidgets('is restored when the book is reopened', (tester) async {
      final env = await textEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, 2);
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pumpAndSettle();
      final total = pageCount(tester);
      final text = pageText(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final open = find.byKey(const Key('open-$gutenberg'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(pageNumber(tester), 3);
      expect(pageCount(tester), total);
      expect(pageText(tester), text);
    });

    testWidgets('an old bookmark without a locator opens at its progress', (tester) async {
      final env = await textEnv(tester, prefs: {'bookmark:$gutenberg': '{"progress":1.0}'});
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(pageNumber(tester), pageCount(tester));
    });

    testWidgets('a bookmark made in scroll view is restored in page view', (tester) async {
      final env = await textEnv(tester, prefs: {'reader_settings': '{"viewMode":"scroll"}'});
      await openBook(tester, env, 'w-pride', gutenberg);
      await tester.drag(find.byKey(const Key('reader-scroll')), const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pumpAndSettle();
      expect(env.bookmarks.load(gutenberg)!.progress, greaterThan(0));
      await chooseView(tester, 'page-turner');
      expect(pageNumber(tester), greaterThan(1));
    });
  });
}
