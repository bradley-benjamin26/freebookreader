// Splitting a book into pages for our own renderer. Review 2026-10-11, #11: this took over a second
// for a novel, in the middle of a build.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/reader/pagination.dart';

const style = TextStyle(fontSize: 18, height: 1.5, fontFamily: 'Roboto');
const scaler = TextScaler.noScaling;

List<String> novel(int paragraphs, {String extra = ''}) => List.generate(
    paragraphs,
    (i) => 'Paragraph $i. It is a truth universally acknowledged, that a single man in possession of a '
        'good fortune, must be in want of a wife.${i.isEven ? ' However little known the feelings or views '
            'of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the '
            'minds of the surrounding families.' : ''}$extra');

double heightOf(String text, double width) {
  final painter = TextPainter(
      text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler)
    ..layout(maxWidth: width);
  final height = painter.height;
  painter.dispose();
  return height;
}

List<int> pages(BookText book, {double width = 340, double height = 560, String br = '\n\n'}) => paginate(book,
    style: style, textScaler: scaler, width: width, height: height, paragraphBreak: br);

void main() {
  group('BookText', () {
    test('knows where each word starts in its paragraph', () {
      final book = BookText(['Once upon,\nwhile I', 'Next  one']);
      expect(book.words, ['Once', 'upon,', '\nwhile', 'I', 'Next', 'one']);
      expect(book.wordOffsets, [0, 5, 11, 17, 0, 6]);
    });
  });

  group('paginate', () {
    final book = BookText(novel(120));

    for (final br in ['\n\n', '\n']) {
      test('every page fits, and is nearly full (paragraph break ${br.length == 2 ? 'blank line' : 'none'})', () {
        const width = 340.0, height = 560.0;
        final starts = pages(book, br: br);
        expect(starts.first, 0);
        expect(starts.length, greaterThan(5));
        final line = heightOf('A', width);
        for (var i = 0; i < starts.length; i++) {
          final end = i + 1 < starts.length ? starts[i + 1] : book.length;
          final used = heightOf(book.text(starts[i], end, br), width);
          expect(used, lessThanOrEqualTo(height + 1), reason: 'page $i overflows');
          if (i + 1 < starts.length) {
            expect(used, greaterThan(height - 3 * line), reason: 'page $i is not full');
          }
        }
      });
    }

    test('pages are in order and never empty', () {
      final starts = pages(book);
      for (var i = 1; i < starts.length; i++) {
        expect(starts[i], greaterThan(starts[i - 1]));
      }
      expect(starts.last, lessThan(book.length));
    });

    test('a bigger font or a narrower page makes more pages', () {
      final base = pages(book).length;
      expect(pages(book, width: 220).length, greaterThan(base));
      expect(pages(book, height: 300).length, greaterThan(base));
    });

    test('a short book is one page, and an empty one has a page too', () {
      expect(pages(BookText(['Short.'])), [0]);
      expect(pages(BookText([])), [0]);
    });

    test('verse keeps its lines: a page break never falls inside the text of a word', () {
      final verse = BookText(List.generate(40, (i) => 'Line one of stanza $i,\nline two of it,\nline three, the last'));
      final starts = pages(verse, height: 200);
      for (var i = 0; i < starts.length; i++) {
        final end = i + 1 < starts.length ? starts[i + 1] : verse.length;
        expect(heightOf(verse.text(starts[i], end, '\n\n'), 340), lessThanOrEqualTo(201));
      }
    });

    test('a word wider than the page does not break pagination', () {
      final wide = BookText(['W' * 200, 'then some words after it', 'W' * 200]);
      final starts = pages(wide, width: 100, height: 60);
      for (var i = 1; i < starts.length; i++) {
        expect(starts[i], greaterThan(starts[i - 1]));
      }
    });

    test('a novel of 120,000 words is paginated in seconds at most', () {
      final long = BookText(novel(3000, extra: ' ${'word ' * 25}'));
      expect(long.length, greaterThan(100000));
      final watch = Stopwatch()..start();
      final starts = pages(long, width: 360, height: 600);
      watch.stop();
      expect(starts.length, greaterThan(1000));
      // Was 1,285 ms before the book was laid out once (about 500 ms alone, over 1,700 ms with the whole
      // suite running). Only a sanity check; the engine runs it in slices so the screen keeps drawing.
      expect(watch.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('Paginator', () {
    test('gives the same pages when run step by step', () {
      final book = BookText(novel(80));
      final paginator = Paginator(book,
          style: style, textScaler: scaler, width: 340, height: 560, paragraphBreak: '\n\n');
      var steps = 0;
      while (paginator.step()) {
        steps++;
      }
      expect(steps, 79);
      expect(paginator.done, isTrue);
      expect(paginator.finish(), pages(book));
    });
  });

  test('pageOf finds the page that holds a word', () {
    expect(pageOf([0, 10, 20], 0), 0);
    expect(pageOf([0, 10, 20], 9), 0);
    expect(pageOf([0, 10, 20], 10), 1);
    expect(pageOf([0, 10, 20], 99), 2);
  });
}
