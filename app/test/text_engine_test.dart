// Our own renderer (TextReaderEngine), which shows books everywhere but web:
// paragraphs drawn by the app, page-turner and scroll view, and how display
// settings and positions work in it. Runs through the whole app, so the
// reader page's controls drive it as they would for a user.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/models/models.dart';
import 'package:free_book_reader/reader/content.dart';
import 'package:free_book_reader/reader/reader_settings.dart';

import 'helpers/fakes.dart';
import 'helpers/fixtures.dart';
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

/// The page as text. A page with several paragraphs is a Text.rich (the gap between them has its own size).
String pageText(WidgetTester tester) {
  final text = tester.widget<Text>(find.byKey(const Key('reader-page-text')));
  return text.data ?? text.textSpan!.toPlainText();
}

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

    testWidgets("the text is marked with the book's language", (tester) async {
      final json = loadJson('search_response.json');
      json['works'][0]['books'][0]['language'] = 'es';
      final env = await TestEnv.create(response: SearchResponse.fromJson(json), textEngine: true);
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(tester.widget<Text>(find.byKey(const Key('reader-page-text'))).locale, const Locale('es'));
    });

    testWidgets('a book with no language leaves the locale alone', (tester) async {
      final json = loadJson('search_response.json');
      json['works'][0]['books'][0]['language'] = null;
      final env = await TestEnv.create(response: SearchResponse.fromJson(json), textEngine: true);
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(tester.widget<Text>(find.byKey(const Key('reader-page-text'))).locale, isNull);
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

  // Review 2026-10-11-main #19: a Chinese paragraph was one page, taller than the screen.
  testWidgets('a long Chinese paragraph is split over pages', (tester) async {
    final env = await textEnv(tester);
    final text = List.generate(3000, (i) => '天下大勢分久必合合久必分'[i % 12]).join();
    env.loader.content = TextContent([text]);
    await openBook(tester, env, 'w-pride', gutenberg);
    expect(pageCount(tester), greaterThan(3));
    final first = pageText(tester);
    expect(first, isNot(contains(' ')));
    await nextPage(tester);
    expect(pageText(tester), isNot(first));
    expect(tester.takeException(), isNull);
  });

  // Review 2026-10-11-main #23: in the page-turner view the setting was only "gap or no gap".
  testWidgets('every paragraph spacing changes the pages', (tester) async {
    final counts = <int>[];
    for (final spacing in [1, 2, 3]) {
      final env = await textEnv(tester, prefs: {'reader_settings': '{"paragraphSpacing":$spacing}'});
      await openBook(tester, env, 'w-pride', gutenberg);
      counts.add(pageCount(tester));
      await tester.pumpWidget(const SizedBox());
    }
    expect(counts[1], greaterThan(counts[0]));
    expect(counts[2], greaterThan(counts[1]));
  });

  group('verse in the page-turner view', () {
    testWidgets('keeps the line breaks of a stanza', (tester) async {
      final env = await textEnv(tester);
      env.loader.content = const TextContent(['Line one,\nline two,\nline three']);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(pageText(tester), 'Line one,\nline two,\nline three');
    });
  });

  group('a long book', () {
    // Review 2026-10-11, #11: the whole book was paginated inside one build (1.3 s for 120,000 words).
    TextContent novel() => TextContent(List.generate(
        3000,
        (i) => 'Paragraph $i. It is a truth universally acknowledged, that a single man in possession of a '
            'good fortune, must be in want of a wife. ${'word ' * 25}'));

    /// Pumps frames until the page count is known; returns the slowest frame, in milliseconds.
    Future<int> pumpUntilPaginated(WidgetTester tester) async {
      var slowest = 0;
      for (var i = 0; i < 2000 && find.byKey(const Key('reader-page-text')).evaluate().isEmpty; i++) {
        final watch = Stopwatch()..start();
        await tester.pump(const Duration(milliseconds: 16));
        slowest = watch.elapsedMilliseconds > slowest ? watch.elapsedMilliseconds : slowest;
      }
      return slowest;
    }

    testWidgets('opens with text on screen at once, and no frame is held up by the pagination', (tester) async {
      final env = await textEnv(tester);
      env.loader.content = novel();
      await openDetails(tester, 'w-pride');
      await tester.ensureVisible(find.byKey(const Key('open-gutenberg:1342')));
      await tester.tap(find.byKey(const Key('open-gutenberg:1342')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const Key('reader-page-pending')), findsOneWidget);
      expect(find.textContaining('Paragraph 0.'), findsOneWidget);
      final slowest = await pumpUntilPaginated(tester);
      expect(slowest, lessThan(250), reason: 'a frame took $slowest ms');   // was over 1,000 ms
      expect(find.byKey(const Key('reader-page-pending')), findsNothing);
      expect(pageNumber(tester), 1);
      expect(pageCount(tester), greaterThan(1000));
    });

    testWidgets('a font size change keeps the text on screen while the pages are counted again', (tester) async {
      final env = await textEnv(tester);
      env.loader.content = novel();
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, 20);
      final opening = pageText(tester).split(RegExp(r'\s+')).take(4).join(' ');
      final before = pageCount(tester);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('font-increase')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const Key('reader-page-pending')), findsOneWidget);
      expect(find.textContaining(opening, findRichText: true), findsWidgets);
      await tester.pumpAndSettle();
      await closeSettings(tester);
      expect(find.byKey(const Key('reader-page-pending')), findsNothing);
      expect(pageCount(tester), greaterThan(before));
    });

    testWidgets('turning the page before the pages are counted does nothing', (tester) async {
      final env = await textEnv(tester);
      env.loader.content = novel();
      await openDetails(tester, 'w-pride');
      await tester.ensureVisible(find.byKey(const Key('open-gutenberg:1342')));
      await tester.tap(find.byKey(const Key('open-gutenberg:1342')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));   // the page slides in
      expect(find.byKey(const Key('reader-page-pending')), findsOneWidget);
      await tester.tap(find.byKey(const Key('next-page')));
      await pumpUntilPaginated(tester);
      expect(pageNumber(tester), 1);
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

    testWidgets('a line break inside a paragraph shows as a new line', (tester) async {
      final env = await textEnv(tester, prefs: {'reader_settings': '{"viewMode":"scroll"}'});
      env.loader.content = const TextContent(['Once upon a midnight dreary,\nwhile I pondered, weak and weary', 'Next']);
      await openBook(tester, env, 'w-pride', gutenberg);
      final lines = tester.getSize(find.byKey(const Key('reader-paragraph-0'))).height;
      final oneLine = tester.getSize(find.byKey(const Key('reader-paragraph-1'))).height;
      expect(lines, greaterThanOrEqualTo(oneLine * 2));
      expect(find.text('Once upon a midnight dreary,\nwhile I pondered, weak and weary'), findsOneWidget);
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

    // Review 2026-10-11-main #20 and #21: the place in the scroll view was the start of the paragraph at the top,
    // and a font change kept the pixel offset (another place in the book).
    group('in a long paragraph', () {
      final long = TextContent([List.generate(1500, (i) => 'w$i').join(' '), 'The end.']);

      Future<int> bookmarkedWord(WidgetTester tester, TestEnv env) async {
        await tester.tap(find.byKey(const Key('bookmark-button')));
        await tester.pumpAndSettle();
        final word = int.parse(env.bookmarks.load(gutenberg)!.locator!.replaceFirst('word:', ''));
        await tester.tap(find.byKey(const Key('bookmark-button'))); // remove it again
        await tester.pumpAndSettle();
        return word;
      }

      testWidgets('a bookmark keeps the line, and reopening shows that line', (tester) async {
        final env = await textEnv(tester, prefs: {'reader_settings': '{"viewMode":"scroll"}'});
        env.loader.content = long;
        await openBook(tester, env, 'w-pride', gutenberg);
        await tester.drag(find.byKey(const Key('reader-scroll')), const Offset(0, -1500));
        await tester.pumpAndSettle();
        final before = tester.getTopLeft(find.byKey(const Key('reader-paragraph-0'))).dy;
        await tester.tap(find.byKey(const Key('bookmark-button')));
        await tester.pumpAndSettle();
        expect(env.bookmarks.load(gutenberg)!.locator, isNot('word:0'));
        await tester.pageBack();
        await tester.pumpAndSettle();
        final open = find.byKey(const Key('open-$gutenberg'));
        await tester.ensureVisible(open);
        await tester.tap(open);
        await tester.pumpAndSettle();
        final after = tester.getTopLeft(find.byKey(const Key('reader-paragraph-0'))).dy;
        expect(after, closeTo(before, 30), reason: 'within a line of where it was');
      });

      testWidgets('a font size change keeps the line at the top', (tester) async {
        final env = await textEnv(tester, prefs: {'reader_settings': '{"viewMode":"scroll"}'});
        env.loader.content = long;
        await openBook(tester, env, 'w-pride', gutenberg);
        await tester.drag(find.byKey(const Key('reader-scroll')), const Offset(0, -2000));
        await tester.pumpAndSettle();
        final before = await bookmarkedWord(tester, env);
        expect(before, greaterThan(100));
        await openSettings(tester);
        for (var i = 0; i < 4; i++) {
          await tester.tap(find.byKey(const Key('font-increase')));
          await tester.pumpAndSettle();
        }
        await closeSettings(tester);
        final after = await bookmarkedWord(tester, env);
        expect(after, lessThanOrEqualTo(before));
        expect(before - after, lessThan(15), reason: 'the same line, or the start of it');
      });
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

    // Final review (persona round one): scroll view never sent a position, so the last place was never saved.
    testWidgets('scroll view saves the last place when scrolling stops', (tester) async {
      final env = await textEnv(tester, prefs: {'reader_settings': '{"viewMode":"scroll"}'});
      await openBook(tester, env, 'w-pride', gutenberg);
      await tester.drag(find.byKey(const Key('reader-scroll')), const Offset(0, -3000));
      await tester.pumpAndSettle();
      final place = env.bookmarks.loadLastPlace(gutenberg);
      expect(place, isNotNull);
      expect(place!.progress, greaterThan(0));
      expect(place.locator, startsWith('word:'));
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
