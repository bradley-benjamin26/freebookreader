// Reading screen: the controls around the book, against a fake ReaderEngine.
// Opening and loading (with the one-minute limit), page-turner (default) and
// scroll view, display settings, dark and light mode, and bookmarks.
//
// How the book itself is drawn belongs to the engine: our own renderer is
// tested in text_engine_test.dart; flutter_readium (web) is checked by hand
// with the spike checklist in decision_reader.md.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/reader/reader_settings.dart';
import 'package:free_book_reader/storage/bookmark_store.dart';

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

/// Taps through to a book whose engine never finishes opening.
Future<void> startLoading(WidgetTester tester, TestEnv env) async {
  env.engines.never = true;
  await searchFor(tester, 'pride');
  await tester.tap(find.byKey(const Key('result-w-pride')));
  await tester.pumpAndSettle();
  final open = find.byKey(const Key('open-$gutenberg'));
  await tester.ensureVisible(open);
  await tester.tap(open);
  await tester.pump(); // a pushed route is offstage for its first frame
  await tester.pump(const Duration(seconds: 1));
}

/// A bookmark store whose writes wait for [release], like a slow disk.
class HeldBookmarkStore extends BookmarkStore {
  HeldBookmarkStore(super.prefs);

  final List<Completer<void>> _held = [];

  /// Lets the oldest waiting write go ahead.
  void release() {
    if (_held.isNotEmpty) _held.removeAt(0).complete();
  }

  Future<void> _hold() {
    final completer = Completer<void>();
    _held.add(completer);
    return completer.future;
  }

  @override
  Future<void> save(String bookKey, Bookmark bookmark) async {
    await _hold();
    await super.save(bookKey, bookmark);
  }

  @override
  Future<void> remove(String bookKey) async {
    await _hold();
    await super.remove(bookKey);
  }
}

Future<TestEnv> readerEnv(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  final env = await TestEnv.create(prefsValues: prefs);
  await pumpApp(tester, env);
  return env;
}

/// Reopens the book from the details page the reader was opened from.
Future<void> reopen(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  final open = find.byKey(const Key('open-$gutenberg'));
  await tester.ensureVisible(open);
  await tester.tap(open);
  await tester.pumpAndSettle();
}

void main() {
  group('viewer', () {
    testWidgets("opens the book's reading options in the engine and shows it", (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.byKey(const Key('reader-page')), findsOneWidget);
      expect(find.byKey(const Key('fake-reader-view')), findsOneWidget);
      final open = env.engines.last.opens.single;
      expect(open.book.url, 'https://www.gutenberg.org/ebooks/1342.html.images');
      expect(open.book.publication, '/publications/gutenberg/1342/manifest.json');
      expect(tester.getSemantics(find.byKey(const Key('reader-title'))),
          containsSemantics(isHeader: true, label: 'Pride and Prejudice'));
    });

    testWidgets('shows a named progress indicator while loading', (tester) async {
      final env = await readerEnv(tester);
      await startLoading(tester, env);
      expect(tester.getSemantics(find.byKey(const Key('loading-book'))),
          containsSemantics(label: 'Loading book', isLiveRegion: true));
      expect(find.byKey(const Key('bookmark-button')), findsNothing);
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('the engine is disposed when the reader closes', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(env.engines.last.disposed, isTrue);
    });

    testWidgets('a book no engine can show offers the source, without retry', (tester) async {
      final env = await readerEnv(tester);
      env.engines.none = true;
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.byKey(const Key('load-error')), findsOneWidget);
      expect(find.byKey(const Key('retry')), findsNothing);
      await tester.tap(find.byKey(const Key('open-external')));
      await tester.pump();
      expect(env.urls.opened.single.toString(), 'https://www.gutenberg.org/ebooks/1342');
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
      env.engines.failNext = true;
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.byKey(const Key('load-error')), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('load-error'))),
          containsSemantics(isLiveRegion: true));
      expect(find.byKey(const Key('open-external')), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake-reader-view')), findsOneWidget);
      expect(env.engines.created, hasLength(1), reason: 'retry reuses the engine');
      expect(env.engines.last.opens, hasLength(2));
    });
  });

  group('page-turner view (default)', () {
    testWidgets('shows "Page 1 of N" from the engine', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(pageNumber(tester), 1);
      expect(pageCount(tester), env.engines.pageCount);
    });

    testWidgets('shows how far through the book when the engine has no page numbers',
        (tester) async {
      // Readium on web, for example: its positions are per chapter, not pages.
      final env = await readerEnv(tester);
      env.engines.pageNumbers = false;
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(tester.widget<Text>(find.byKey(const Key('page-indicator'))).data, '0% read');
      await nextPage(tester, 2);
      expect(tester.widget<Text>(find.byKey(const Key('page-indicator'))).data, '22% read');
    });

    testWidgets('the page number is announced when it changes', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(tester.getSemantics(find.byKey(const Key('page-indicator'))),
          containsSemantics(isLiveRegion: true));
    });

    testWidgets('next and previous buttons turn the page in the engine', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester);
      expect(env.engines.last.calls, ['next']);
      expect(pageNumber(tester), 2);
      expect(find.text('Text of page 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('previous-page')));
      await tester.pumpAndSettle();
      expect(env.engines.last.calls, ['next', 'previous']);
      expect(pageNumber(tester), 1);
    });

    testWidgets('previous is disabled on the first page', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('previous-page'))).onPressed, isNull);
    });

    testWidgets('next is disabled on the last page', (tester) async {
      final env = await readerEnv(tester);
      env.engines.pageCount = 3;
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, 2);
      expect(pageNumber(tester), 3);
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

    testWidgets('the left arrow does nothing on the first page', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(env.engines.last.calls, isEmpty);
    });
  });

  group('scroll view', () {
    testWidgets('can be chosen in the settings', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('view-scroll')));
      await tester.pumpAndSettle();
      await closeSettings(tester);
      expect(env.engines.last.settings!.viewMode, ViewMode.scroll);
      expect(find.byKey(const Key('next-page')), findsNothing);
      expect(find.byKey(const Key('page-indicator')), findsNothing);
      expect(find.byKey(const Key('fake-reader-view')), findsOneWidget);
    });

    testWidgets('the choice is remembered', (tester) async {
      final env = await readerEnv(tester, prefs: {
        'reader_settings': '{"viewMode":"scroll"}',
      });
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(env.engines.last.settings!.viewMode, ViewMode.scroll);
      expect(find.byKey(const Key('next-page')), findsNothing);
    });

    testWidgets('arrow keys are left to the engine in scroll view', (tester) async {
      final env = await readerEnv(tester, prefs: {'reader_settings': '{"viewMode":"scroll"}'});
      await openBook(tester, env, 'w-pride', gutenberg);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(env.engines.last.calls, isEmpty);
    });
  });

  group('display settings', () {
    testWidgets('the engine opens with the defaults', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(env.engines.last.settings, const ReaderSettings());
    });

    testWidgets('font size can be increased and decreased', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('font-increase')));
      await tester.pumpAndSettle();
      expect(env.engines.last.settings!.fontSize, 20);
      await tester.tap(find.byKey(const Key('font-decrease')));
      await tester.tap(find.byKey(const Key('font-decrease')));
      await tester.pumpAndSettle();
      expect(env.engines.last.settings!.fontSize, 16);
    });

    testWidgets('each change is sent to the engine at once', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('font-increase')));
      await tester.tap(find.byKey(const Key('theme-dark')));
      await tester.pumpAndSettle();
      expect(env.engines.last.applied.map((s) => (s.fontSize, s.theme)),
          [(20.0, ReaderTheme.light), (20.0, ReaderTheme.dark)]);
    });

    testWidgets('the book is covered while the settings are open, so its view cannot take their clicks',
        (tester) async {
      // On web the engine's view is an iframe, which otherwise gets every
      // click on the sheet drawn over it.
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.byKey(const Key('reader-click-shield')), findsNothing);
      await openSettings(tester);
      expect(find.byKey(const Key('reader-click-shield')), findsOneWidget);
      await closeSettings(tester);
      expect(find.byKey(const Key('reader-click-shield')), findsNothing);
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
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('font-sansSerif')));
      await tester.pumpAndSettle();
      expect(env.engines.last.settings!.fontFamily, ReaderFont.sansSerif);
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

    for (final (name, read) in [
      ('Line spacing', (ReaderSettings s) => s.lineHeight),
      ('Letter spacing', (ReaderSettings s) => s.letterSpacing),
      ('Paragraph spacing', (ReaderSettings s) => s.paragraphSpacing),
    ]) {
      testWidgets('increasing $name with assistive technology reaches the engine', (tester) async {
        final env = await readerEnv(tester);
        await openBook(tester, env, 'w-pride', gutenberg);
        final before = read(env.engines.last.settings!);
        await openSettings(tester);
        final handle = tester.ensureSemantics();
        tester.semantics.increase(sliderNamed(name));
        await tester.pumpAndSettle();
        expect(read(env.engines.last.settings!), greaterThan(before));
        handle.dispose();
      });
    }

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
      expect(env.engines.last.settings!.fontSize, 28);
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
      expect(env.engines.last.settings!.theme, ReaderTheme.light);
    });

    testWidgets('can switch to dark and back', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('theme-dark')));
      await tester.pumpAndSettle();
      expect(surface(tester), const ReaderSettings(theme: ReaderTheme.dark).backgroundColor);
      expect(env.engines.last.settings!.theme, ReaderTheme.dark);
      await tester.tap(find.byKey(const Key('theme-light')));
      await tester.pumpAndSettle();
      expect(surface(tester), const ReaderSettings().backgroundColor);
      expect(env.engines.last.settings!.theme, ReaderTheme.light);
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
      expect(env.engines.last.opens.single.at, isNull);
      expect(tester.getSemantics(find.byKey(const Key('bookmark-button'))),
          containsSemantics(isButton: true, label: 'Add bookmark'));
    });

    testWidgets("saves the engine's position on this device and confirms it", (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, 2);
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final bookmark = env.bookmarks.load(gutenberg);
      expect(bookmark, isNotNull);
      expect(bookmark!.progress, closeTo(2 / 9, 0.001));
      expect(bookmark.locator, 'fake:2');
      expect(find.text('Bookmark saved'), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('bookmark-button'))),
          containsSemantics(isButton: true, label: 'Remove bookmark'));
    });

    // Review 2026-10-11-main, #24: a second tap before the first is saved used to leave the button wrong.
    testWidgets('two quick taps leave the button saying what is stored', (tester) async {
      late HeldBookmarkStore store;
      final env = await TestEnv.create(bookmarks: (prefs) => store = HeldBookmarkStore(prefs));
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', gutenberg);
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.tap(find.byKey(const Key('bookmark-button'))); // before the first save is done
      store.release();
      await tester.pumpAndSettle();
      store.release();
      await tester.pumpAndSettle();
      final stored = env.bookmarks.load(gutenberg) != null;
      expect(tester.getSemantics(find.byKey(const Key('bookmark-button'))),
          containsSemantics(label: stored ? 'Remove bookmark' : 'Add bookmark'));
    });

    testWidgets('is restored when the book is reopened', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      await nextPage(tester, 2);
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pumpAndSettle();
      await reopen(tester);
      final at = env.engines.last.opens.single.at!;
      expect(at.locator, 'fake:2');
      expect(at.progress, closeTo(2 / 9, 0.001));
      expect(pageNumber(tester), 3);
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
      expect(restarted.engines.last.opens.single.at!.locator, 'fake:3');
      expect(pageNumber(tester), 4);
    });

    testWidgets('an old bookmark without a locator still opens at its progress', (tester) async {
      final env = await readerEnv(tester);
      await env.bookmarks.save(gutenberg, const Bookmark(progress: 0.5));
      await openBook(tester, env, 'w-pride', gutenberg);
      final at = env.engines.last.opens.single.at!;
      expect(at.locator, isNull);
      expect(at.progress, 0.5);
    });

    testWidgets('a book without a bookmark opens at the start', (tester) async {
      final env = await readerEnv(tester);
      await env.bookmarks.save('gutenberg:999', const Bookmark(progress: 0.5));
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(env.engines.last.opens.single.at, isNull);
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
      expect(env.bookmarks.load(gutenberg)!.locator, 'fake:3');
    });

    testWidgets('bookmarks never leave the device (no network request is made to save one)',
        (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-pride', gutenberg);
      final searches = env.api.queries.length;
      await tester.tap(find.byKey(const Key('bookmark-button')));
      await tester.pumpAndSettle();
      expect(env.api.queries.length, searches);
      expect(env.engines.last.opens, hasLength(1));
      expect(env.loader.requests, isEmpty);
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

    testWidgets('a pdf does not open a reader engine', (tester) async {
      final env = await readerEnv(tester);
      await openBook(tester, env, 'w-kinder', 'doab:20.500.12854/95506');
      expect(env.engines.asked, isEmpty);
    });
  });
}
