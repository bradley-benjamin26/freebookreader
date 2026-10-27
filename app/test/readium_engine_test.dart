// Which engine reads a book, and how our settings become flutter_readium
// preferences. Readium itself only runs in a browser or on a phone; check it
// by hand with the spike checklist in decision_reader.md.
import 'dart:async';

import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/models/models.dart';
import 'package:free_book_reader/reader/engines.dart';
import 'package:free_book_reader/reader/readium_engine.dart';
import 'package:free_book_reader/reader/reader_settings.dart';
import 'package:free_book_reader/reader/text_engine.dart';

import 'helpers/fakes.dart';

const gutenberg = ReadingOptions(
  mode: ReadingMode.inApp,
  kind: 'html',
  url: 'https://www.gutenberg.org/ebooks/1342.html.images',
  publication: '/publications/gutenberg/1342/manifest.json',
);

/// The plugin's calls that matter when a book opens and closes. Opening waits for [finishOpen].
class FakeReadium implements FlutterReadium {
  final List<String> calls = [];
  final List<Completer<Publication>> _opens = [];

  void finishOpen() => _opens.removeAt(0)
      .complete(Publication.fromJson({'metadata': {'title': 'A book'}, 'links': [], 'readingOrder': []})!);

  @override
  Future<Publication> openPublication(String pubUrl) {
    calls.add('open $pubUrl');
    final completer = Completer<Publication>();
    _opens.add(completer);
    return completer.future;
  }

  @override
  Future<void> closePublication() async => calls.add('close');

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {}

  @override
  Stream<Locator> get onTextLocatorChanged => const Stream.empty();

  @override
  Stream<ReadiumReaderStatus> get onReaderStatusChanged => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final backend = Uri.parse('http://localhost:8000');
  final loader = FakeContentLoader();

  group('choosing the engine', () {
    test('web opens the backend manifest in Readium', () {
      final engine = chooseReaderEngine(gutenberg, web: true, backend: backend, loader: loader);
      expect(engine, isA<ReadiumReaderEngine>());
      expect((engine as ReadiumReaderEngine).manifest.toString(),
          'http://localhost:8000/publications/gutenberg/1342/manifest.json');
    });

    test('elsewhere our own renderer reads the HTML', () {
      expect(chooseReaderEngine(gutenberg, web: false, backend: backend, loader: loader),
          isA<TextReaderEngine>());
    });

    test('on web a book without a manifest falls back to our renderer', () {
      const text = ReadingOptions(mode: ReadingMode.inApp, kind: 'text', url: 'https://example.org/a.txt');
      expect(chooseReaderEngine(text, web: true, backend: backend, loader: loader),
          isA<TextReaderEngine>());
    });

    test('no engine for PDFs, audio or books read at the source', () {
      for (final kind in ['pdf', 'audio', null]) {
        final book = ReadingOptions(mode: ReadingMode.inApp, kind: kind, url: 'https://example.org/x');
        expect(chooseReaderEngine(book, web: false, backend: backend, loader: loader), isNull,
            reason: '$kind');
      }
    });

    test('the manifest path keeps the path the backend is mounted at', () {
      expect(backendUrl(Uri.parse('https://example.org/api/'), '/publications/x/manifest.json').toString(),
          'https://example.org/api/publications/x/manifest.json');
      expect(backendUrl(Uri.parse('https://example.org'), '/publications/x/manifest.json').toString(),
          'https://example.org/publications/x/manifest.json');
    });
  });

  // Review 2026-10-11-main, #26: Readium is one plugin for the whole app, so a book that finishes opening
  // after its reader closed must be closed, and must not close the next reader's book.
  group('opening and closing', () {
    final a = Uri.parse('http://localhost:8000/publications/gutenberg/1/manifest.json');
    final b = Uri.parse('http://localhost:8000/publications/gutenberg/2/manifest.json');

    test('a book that opens after its reader closed is closed', () async {
      final readium = FakeReadium();
      final engine = ReadiumReaderEngine(a, readium: readium);
      final opening = engine.open(gutenberg, settings: const ReaderSettings());
      await pumpEventQueue();
      await engine.dispose();
      readium.finishOpen();
      await opening.catchError((_) {});
      expect(readium.calls, ['open $a', 'close']);
    });

    test("the next reader's book opens only after the closed reader's book is closed", () async {
      final readium = FakeReadium();
      final first = ReadiumReaderEngine(a, readium: readium);
      final opening = first.open(gutenberg, settings: const ReaderSettings());
      await pumpEventQueue();
      await first.dispose();
      final second = ReadiumReaderEngine(b, readium: readium);
      final openingNext = second.open(gutenberg, settings: const ReaderSettings());
      await pumpEventQueue();
      readium.finishOpen();
      await opening.catchError((_) {});
      await pumpEventQueue();
      readium.finishOpen();
      await openingNext;
      expect(readium.calls, ['open $a', 'close', 'open $b']);
      await second.dispose();
      expect(readium.calls.last, 'close');
    });
  });

  group('settings as Readium preferences', () {
    test('defaults: 100% size, light colors, paginated, publisher styles off', () {
      final p = epubPreferences(const ReaderSettings());
      expect(p.fontSize, 1.0);
      expect(p.lineHeight, 1.5);
      expect(p.backgroundColor, const ReaderSettings().backgroundColor);
      expect(p.textColor, const ReaderSettings().textColor);
      expect(p.scroll, isFalse);
      expect(p.publisherStyles, isFalse);
    });

    test('font size is a ratio of our default size', () {
      expect(epubPreferences(const ReaderSettings(fontSize: 27)).fontSize, 1.5);
      expect(epubPreferences(const ReaderSettings(fontSize: 12)).fontSize, closeTo(0.667, 0.001));
    });

    test('dark mode, scroll view and spacing are passed on', () {
      final p = epubPreferences(const ReaderSettings(
          theme: ReaderTheme.dark, viewMode: ViewMode.scroll, letterSpacing: 0.1, paragraphSpacing: 2));
      expect(p.backgroundColor, const ReaderSettings(theme: ReaderTheme.dark).backgroundColor);
      expect(p.textColor, const ReaderSettings(theme: ReaderTheme.dark).textColor);
      expect(p.scroll, isTrue);
      expect(p.letterSpacing, 0.1);
      expect(p.paragraphSpacing, 1.0, reason: 'Readium adds it above and below each paragraph');
    });

    test('fonts become CSS font stacks ending in a generic family', () {
      expect(cssFontStack(ReaderFont.serif), '"Georgia", "Times New Roman", "Noto Serif", serif');
      expect(cssFontStack(ReaderFont.monospace), '"Menlo", "Courier New", "Roboto Mono", monospace');
      expect(cssFontStack(ReaderFont.dyslexiaFriendly),
          '"OpenDyslexic", "Atkinson Hyperlegible", "Verdana", sans-serif');
    });
  });
}
