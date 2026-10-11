import 'package:flutter/painting.dart';

/// A book as a run of words, so a place in it (a word index) survives a
/// change of font, size or view.
///
/// Provisional: this belongs to our own renderer, which may be replaced by a
/// reader package (see decision_reader.md).
class BookText {
  BookText(this.paragraphs) {
    for (final (p, paragraph) in paragraphs.indexed) {
      paragraphStarts.add(words.length);
      for (final word in paragraph.split(' ')) {
        if (word.isEmpty) continue;
        words.add(word);
        paragraphOfWord.add(p);
      }
    }
  }

  final List<String> paragraphs;
  final List<String> words = [];
  final List<int> paragraphOfWord = [];

  /// The index of each paragraph's first word.
  final List<int> paragraphStarts = [];

  int get length => words.length;

  /// Words [start, end) as text, with [paragraphBreak] between paragraphs.
  String text(int start, int end, String paragraphBreak) {
    final out = StringBuffer();
    for (var i = start; i < end; i++) {
      if (i > start) {
        out.write(paragraphOfWord[i] != paragraphOfWord[i - 1] ? paragraphBreak : ' ');
      }
      out.write(words[i]);
    }
    return out.toString();
  }
}

/// Splits [book] into pages that fit [width] x [height] in [style]. Returns
/// the index of each page's first word.
List<int> paginate(
  BookText book, {
  required TextStyle style,
  required TextScaler textScaler,
  required double width,
  required double height,
  required String paragraphBreak,
}) {
  final painter = TextPainter(textDirection: TextDirection.ltr, textScaler: textScaler);
  bool fits(int start, int end) {
    painter.text = TextSpan(text: book.text(start, end, paragraphBreak), style: style);
    painter.layout(maxWidth: width);
    return painter.height <= height;
  }

  final starts = <int>[];
  var start = 0;
  var guess = 64;
  while (start < book.length) {
    starts.add(start);
    // Grow until a page overflows, then binary-search the last word that fits.
    var good = start + 1; // a page always holds at least one word
    var bad = -1;
    var probe = start + guess;
    while (bad < 0) {
      if (probe >= book.length) {
        if (fits(start, book.length)) {
          good = book.length;
          break;
        }
        bad = book.length;
      } else if (fits(start, probe)) {
        good = probe;
        probe = start + (probe - start) * 2;
      } else {
        bad = probe;
      }
    }
    if (bad > 0) {
      while (bad - good > 1) {
        final mid = (good + bad) ~/ 2;
        if (fits(start, mid)) {
          good = mid;
        } else {
          bad = mid;
        }
      }
    }
    guess = good - start;
    start = good;
  }
  painter.dispose();
  return starts.isEmpty ? [0] : starts;
}

/// The page that holds [word], given each page's first word.
int pageOf(List<int> pageStarts, int word) {
  var lo = 0, hi = pageStarts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (pageStarts[mid] <= word) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}
