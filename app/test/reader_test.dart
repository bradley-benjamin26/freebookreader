// Reading experience: viewer, page-turner (default) and scroll view, display
// settings, bookmarks, and the one-minute load limit.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/reader/reader_settings.dart';
import 'package:free_book_reader/storage/bookmark_store.dart';

import 'helpers/fakes.dart';
import 'helpers/test_app.dart';

const gutenberg = 'gutenberg:1342';

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('reader-settings-button')));
  await tester.pumpAndSettle();
}

TextStyle pageStyle(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('reader-page-text'))).style!;

/// Taps through to a book whose content never finishes loading.
Future<void> startLoading(WidgetTester tester, TestEnv env) async {
  env.loader.never = true;
  await searchFor(tester, 'pride');
  await tester.tap(find.byKey(const Key('result-w-pride')));
  await tester.pumpAndSettle();
  final open = find.byKey(const Key('open-$gutenberg'));
  await tester.ensureVisible(open);
  await tester.tap(open);
  await tester.pump(); // a pushed route is offstage for its first frame
  await tester.pump(const Duration(seconds: 1));
}

Future<TestEnv> readerEnv(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  final env = await TestEnv.create(prefsValues: prefs);
  await pumpApp(tester, env);
  return env;
}

void main() {
  group('viewer', () {
    testWidgets('loads the book and shows its text', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.byKey(const Key('reader-page')), findsOneWidget);
      expect(find.textContaining('Paragraph 0.'), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('reader-title'))),
          containsSemantics(isHeader: true, label: 'Pride and Prejudice'));
    });

    testWidgets('the text is available to screen readers', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      final handle = tester.ensureSemantics();
      expect(tester.getSemantics(find.byKey(const Key('reader-page-text'))).label,
          contains('Paragraph 0.'));
      handle.dispose();
    });

    testWidgets('shows a named progress indicator while loading', (tester) async {
      final env = await readerEnv(tester);
      await startLoading(tester, env);
      expect(tester.getSemantics(find.byKey(const Key('loading-book'))),
          containsSemantics(label: 'Loading book', isLiveRegion: true));
      await tester.pump(const Duration(seconds: 61));
    });
  });

  group('one minute to display', () {
    testWidgets('keeps waiting for the first minute', (tester) async {
      final env = await readerEnv(tester);
      await startLoading(tester, env);
      await tester.pump(const Duration(seconds: 55));
      expect(find.byKey(const Key('loading-book')), findsOneWidget);
      expect(find.byKey(const Key('load-timeout')), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('after a minute offers to open the book at its source', (tester) async {
      final env = await readerEnv(tester);
      await startLoading(tester, env);
      await tester.pump(const Duration(seconds: 61));
      expect(find.byKey(const Key('load-timeout')), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('load-timeout'))),
          containsSemantics(isLiveRegion: true));
      await tester.tap(find.byKey(const Key('open-external')));
      await tester.pump();
      expect(env.urls.opened.single.toString(), 'https://www.gutenberg.org/ebooks/1342');
    });

    testWidgets('a loading error offers retry and the source', (tester) async {
      final env = await readerEnv(tester);
      env.loader.failNext = true;
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.byKey(const Key('load-error')), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('load-error'))),
          containsSemantics(isLiveRegion: true));
      expect(find.byKey(const Key('open-external')), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-page-text')), findsOneWidget);
    });
  });

  group('page-turner view (default)', () {
    testWidgets('shows one page at a time with "Page 1 of N"', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.byKey(const Key('reader-scroll')), findsNothing);
      expect(pageNumber(tester), 1);
      expect(pageCount(tester), greaterThan(3));
    });

    testWidgets('the page number is announced when it changes', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(tester.getSemantics(find.byKey(const Key('page-indicator'))),
          containsSemantics(isLiveRegion: true));
    });

    testWidgets('next and previous buttons turn the page', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      String pageText() => tester.widget<Text>(find.byKey(const Key('reader-page-text'))).data!;
      final first = pageText();
      await nextPage(tester);
      expect(pageNumber(tester), 2);
      expect(pageText(), isNot(first));
      await tester.tap(find.byKey(const Key('previous-page')));
      await tester.pumpAndSettle();
      expect(pageNumber(tester), 1);
    });

    testWidgets('previous is disabled on the first page', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('previous-page'))).onPressed, isNull);
    });

    testWidgets('next is disabled on the last page', (tester) async {
      final env = await readerEnv(tester);
      env.loader.content = longText(paragraphs: 6);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, pageCount(tester) - 1);
      expect(pageNumber(tester), pageCount(tester));
      expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('next-page'))).onPressed, isNull);
    });

    testWidgets('buttons have accessible names', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(tester.getSemantics(find.byKey(const Key('next-page'))),
          containsSemantics(isButton: true, label: 'Next page'));
      expect(tester.getSemantics(find.byKey(const Key('previous-page'))),
          containsSemantics(isButton: true, label: 'Previous page'));
    });

    testWidgets('arrow keys turn pages (keyboard access)', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(pageNumber(tester), 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(pageNumber(tester), 1);
    });

    testWidgets('page count changes with font size', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      final before = pageCount(tester);
      await openSettings(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('font-increase')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('settings-close')));
      await tester.pumpAndSettle();
      expect(pageCount(tester), greaterThan(before));
    });
  });

  group('scroll view', () {
    testWidgets('can be chosen in the settings', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('view-scroll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-scroll')), findsOneWidget);
      expect(find.byKey(const Key('next-page')), findsNothing);
      expect(find.byKey(const Key('reader-paragraph-0')), findsOneWidget);
    });

    testWidgets('the choice is remembered', (tester) async {
      final env = await readerEnv(tester, prefs: {
        'reader_settings': '{"viewMode":"scroll"}',
      });
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.byKey(const Key('reader-scroll')), findsOneWidget);
    });

    testWidgets('switching views keeps your place', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, 4);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('view-scroll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-paragraph-0')), findsNothing);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('view-page-turner')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-close')));
      await tester.pumpAndSettle();
      expect(pageNumber(tester), closeTo(5, 1));
    });
  });

  group('display settings', () {
    testWidgets('start from the defaults', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(pageStyle(tester).fontSize, 18);
      expect(pageStyle(tester).height, 1.5);
    });

    testWidgets('font size can be increased and decreased', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('font-increase')));
      await tester.pumpAndSettle();
      expect(pageStyle(tester).fontSize, 20);
      await tester.tap(find.byKey(const Key('font-decrease')));
      await tester.tap(find.byKey(const Key('font-decrease')));
      await tester.pumpAndSettle();
      expect(pageStyle(tester).fontSize, 16);
    });

    testWidgets('font size shows its current value as text', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      expect(find.descendant(of: find.byKey(const Key('font-size-value')), matching: find.text('18')),
          findsOneWidget);
    });

    testWidgets('font size stops at the limits', (tester) async {
      final env = await readerEnv(tester, prefs: {'reader_settings': '{"fontSize":40}'});
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('font-increase'))).onPressed, isNull);
    });

    testWidgets('font style can be changed', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      final before = pageStyle(tester).fontFamily;
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('font-sansSerif')));
      await tester.pumpAndSettle();
      expect(pageStyle(tester).fontFamily, isNot(before));
    });

    testWidgets('a dyslexia-friendly font is offered', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      expect(find.byKey(const Key('font-dyslexiaFriendly')), findsOneWidget);
    });

    testWidgets('line spacing, letter spacing and paragraph spacing have sliders with names',
        (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      expect(tester.getSemantics(find.byKey(const Key('setting-line-height'))),
          containsSemantics(isSlider: true, label: 'Line spacing'));
      expect(tester.getSemantics(find.byKey(const Key('setting-letter-spacing'))),
          containsSemantics(isSlider: true, label: 'Letter spacing'));
      expect(tester.getSemantics(find.byKey(const Key('setting-paragraph-spacing'))),
          containsSemantics(isSlider: true, label: 'Paragraph spacing'));
    });

    testWidgets('increasing line spacing with assistive technology changes the text', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      final handle = tester.ensureSemantics();
      tester.semantics.increase(sliderNamed('Line spacing'));
      await tester.pumpAndSettle();
      expect(pageStyle(tester).height, greaterThan(1.5));
      handle.dispose();
    });

    testWidgets('increasing letter spacing changes the text', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      final handle = tester.ensureSemantics();
      tester.semantics.increase(sliderNamed('Letter spacing'));
      await tester.pumpAndSettle();
      expect(pageStyle(tester).letterSpacing, greaterThan(0));
      handle.dispose();
    });

    testWidgets('paragraph spacing applies in scroll view', (tester) async {
      final env = await readerEnv(tester, prefs: {'reader_settings': '{"viewMode":"scroll"}'});
      await openBook(tester, env, 'w-pride', gutenberg);
      final gapBefore = tester.getTopLeft(find.byKey(const Key('reader-paragraph-1'))).dy -
          tester.getBottomLeft(find.byKey(const Key('reader-paragraph-0'))).dy;
      await openSettings(tester);
      final handle = tester.ensureSemantics();
      tester.semantics.increase(sliderNamed('Paragraph spacing'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-close')));
      await tester.pumpAndSettle();
      final gapAfter = tester.getTopLeft(find.byKey(const Key('reader-paragraph-1'))).dy -
          tester.getBottomLeft(find.byKey(const Key('reader-paragraph-0'))).dy;
      expect(gapAfter, greaterThan(gapBefore));
      handle.dispose();
    });

    testWidgets('settings are remembered on the device', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('font-increase')));
      await tester.tap(find.byKey(const Key('theme-dark')));
      await tester.pumpAndSettle();
      final saved = env.settingsStore.load();
      expect(saved.fontSize, 20);
      expect(saved.theme, ReaderTheme.dark);
    });

    testWidgets('settings apply the next time a book is opened', (tester) async {
      final env = await readerEnv(tester, prefs: {'reader_settings': '{"fontSize":28}'});
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(pageStyle(tester).fontSize, 28);
    });
  });

  group('dark and light mode', () {
    Color surface(WidgetTester tester) {
      final box = tester.widget<ColoredBox>(find.descendant(
          of: find.byKey(const Key('reader-surface')), matching: find.byType(ColoredBox)).first);
      return box.color;
    }

    testWidgets('light is the default', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(surface(tester), const ReaderSettings().backgroundColor);
      expect(pageStyle(tester).color, const ReaderSettings().textColor);
    });

    testWidgets('can switch to dark and back', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('theme-dark')));
      await tester.pumpAndSettle();
      const dark = ReaderSettings(theme: ReaderTheme.dark);
      expect(surface(tester), dark.backgroundColor);
      expect(pageStyle(tester).color, dark.textColor);
      await tester.tap(find.byKey(const Key('theme-light')));
      await tester.pumpAndSettle();
      expect(surface(tester), const ReaderSettings().backgroundColor);
    });

    testWidgets('the selected mode is exposed as selected', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('theme-dark')));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.byKey(const Key('theme-dark'))), containsSemantics(isSelected: true));
      expect(tester.getSemantics(find.byKey(const Key('theme-light'))),
          isNot(containsSemantics(isSelected: true)));
    });
  });

  group('bookmarks', () {
    testWidgets('start with none, and the button says so', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(env.bookmarks.load(gutenberg), isNull);
      expect(tester.getSemantics(find.byKey(const Key('bookmark-button'))),
          containsSemantics(isButton: true, label: 'Add bookmark'));
    });

    testWidgets('saves the place on this device and confirms it', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, 2);
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final bookmark = env.bookmarks.load(gutenberg);
      expect(bookmark, isNotNull);
      expect(bookmark!.progress, closeTo(2 / (pageCount(tester) - 1), 0.001));
      expect(find.text('Bookmark saved'), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('bookmark-button'))),
          containsSemantics(isButton: true, label: 'Remove bookmark'));
    });

    testWidgets('is restored when the book is reopened', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, 2);
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pumpAndSettle();
      final total = pageCount(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final open = find.byKey(const Key('open-gutenberg:1342'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(pageNumber(tester), 3);
      expect(pageCount(tester), total);
    });

    testWidgets('is restored after the app restarts', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, 3);
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pumpAndSettle();

      final restarted = await TestEnv.create(prefsValues: {
        for (final key in env.prefs.getKeys()) key: env.prefs.get(key)!,
      });
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, restarted);
      await openBook(tester, restarted, 'w-pride', gutenberg);
      expect(pageNumber(tester), 4);
    });

    testWidgets('a book without a bookmark opens on the first page', (tester) async {
      final env = await readerEnv(tester);
      await env.bookmarks.save('gutenberg:999', const Bookmark(progress: 0.5));
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(pageNumber(tester), 1);
    });

    testWidgets('each book keeps its own bookmark', (tester) async {
      final env = await readerEnv(tester);
      await env.bookmarks.save('doab:other', const Bookmark(progress: 0.9));
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(pageNumber(tester), 1);
      expect(env.bookmarks.load('doab:other')!.progress, closeTo(0.9, 1e-9));
    });

    testWidgets('can be removed', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester);
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(env.bookmarks.load(gutenberg), isNull);
      expect(find.text('Bookmark removed'), findsOneWidget);
    });

    testWidgets('saving again moves the bookmark', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bookmark-button')));   // remove
      await tester.pumpAndSettle();
      await nextPage(tester, 3);
      await tester.tap(find.byKey(const Key('bookmark-button')));   // add at page 4
      await tester.pumpAndSettle();
      expect(env.bookmarks.load(gutenberg)!.progress, closeTo(3 / (pageCount(tester) - 1), 0.001));
    });

    testWidgets('bookmarks never leave the device (no network request is made to save one)',
        (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      final searches = env.api.queries.length;
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pumpAndSettle();
      expect(env.api.queries.length, searches);
      expect(env.loader.requests, hasLength(1));
    });
  });

  group('other kinds of content', () {
    testWidgets('a pdf is shown in the pdf viewer without text settings', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-kinder', 'doab:20.500.12854/95506');
      expect(find.byKey(const Key('pdf-viewer')), findsOneWidget);
      expect(find.byKey(const Key('reader-settings-button')), findsNothing);
      expect(find.byKey(const Key('next-page')), findsNothing);
    });

    testWidgets('a pdf receives the book url', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-kinder', 'doab:20.500.12854/95506');
      expect(find.textContaining('9783847408130.pdf'), findsOneWidget);
    });

    testWidgets('a pdf does not go through the text loader', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-kinder', 'doab:20.500.12854/95506');
      expect(env.loader.requests, isEmpty);
    });
  });
}
