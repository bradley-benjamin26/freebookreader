// Which engine reads a book, and how our settings become flutter_readium
// preferences. Readium itself only runs in a browser or on a phone; check it
// by hand with the spike checklist in decision_reader.md.
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
