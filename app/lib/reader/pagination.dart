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
      var offset = 0; // where the current piece starts in the paragraph
      for (final piece in paragraph.split(' ')) {
        // A line break inside a paragraph (verse) starts the word after it: "a\nb" is "a" and "\nb".
        var at = offset;
        for (final (i, part) in piece.split('\n').indexed) {
          if (part.isNotEmpty) {
            words.add(i == 0 ? part : '\n$part');
            wordOffsets.add(at);
            paragraphOfWord.add(p);
          }
          at += part.length + 1;
        }
        offset += piece.length + 1;
      }
    }
  }

  final List<String> paragraphs;
  final List<String> words = [];
  final List<int> paragraphOfWord = [];

  /// Where each word's own text starts in its paragraph (after the line break, if the word follows one).
  final List<int> wordOffsets = [];

  /// The index of each paragraph's first word.
  final List<int> paragraphStarts = [];

  int get length => words.length;

  /// Words [start, end) as text, with [paragraphBreak] between paragraphs and a '\n' where a line breaks.
  String text(int start, int end, String paragraphBreak) {
    final out = StringBuffer();
    for (var i = start; i < end; i++) {
      final word = words[i];
      if (i > start) {
        if (paragraphOfWord[i] != paragraphOfWord[i - 1]) {
          out.write(paragraphBreak);
        } else if (!word.startsWith('\n')) {
          out.write(' ');
        }
      }
      out.write(i == start && word.startsWith('\n') ? word.substring(1) : word);
    }
    return out.toString();
  }

  /// Where [word] is in `text(first, ...)`: its start and end offsets, without the line break before it.
  (int, int) wordRange(int first, int word, String paragraphBreak) {
    var start = 0;
    if (word > first) {
      start = text(first, word, paragraphBreak).length;
      if (paragraphOfWord[word] != paragraphOfWord[word - 1]) {
        start += paragraphBreak.length;
      } else if (!words[word].startsWith('\n')) {
        start += 1;
      }
    }
    final piece = words[word];
    if (piece.startsWith('\n')) {
      // The line break is part of the text before the word (but not before the first word shown).
      if (word > first) start += 1;
      return (start, start + piece.length - 1);
    }
    return (start, start + piece.length);
  }
}

/// Splits [book] into pages that fit [width] x [height] in [style]. Returns
/// the index of each page's first word.
///
/// A page break falls between lines. The book is laid out once, a paragraph at a time, and the lines
/// are counted onto pages, instead of laying out a page's text again for every guess at where it ends
/// (which took over a second for a novel).
List<int> paginate(
  BookText book, {
  required TextStyle style,
  required TextScaler textScaler,
  required double width,
  required double height,
  required String paragraphBreak,
}) {
  final paginator = Paginator(book,
      style: style, textScaler: textScaler, width: width, height: height, paragraphBreak: paragraphBreak);
  while (paginator.step()) {}
  return paginator.finish();
}

/// [paginate] in steps of one paragraph, so a caller can give the screen time to draw in between.
class Paginator {
  Paginator(
    this.book, {
    required this.style,
    required this.textScaler,
    required this.width,
    required this.height,
    required String paragraphBreak,
  }) : _painter = TextPainter(textDirection: TextDirection.ltr, textScaler: textScaler) {
    // The blank line between paragraphs is as tall as a line of text.
    _gap = paragraphBreak == '\n\n'
        ? (_painter
              ..text = TextSpan(text: 'A', style: style)
              ..layout(maxWidth: width))
            .preferredLineHeight
        : 0;
  }

  final BookText book;
  final TextStyle style;
  final TextScaler textScaler;
  final double width;
  final double height;
  final TextPainter _painter;
  late final double _gap;

  /// The first word of each page found so far.
  final List<int> starts = [0];

  int _paragraph = 0;
  double _y = 0; // height used on the current page
  bool _pageEmpty = true;

  /// Whether every paragraph has been placed.
  bool get done => _paragraph >= book.paragraphs.length;

  /// Places the next paragraph. Returns false when there is none left.
  bool step() {
    if (done) return false;
    final p = _paragraph++;
    final first = book.paragraphStarts[p];
    final end = p + 1 < book.paragraphs.length ? book.paragraphStarts[p + 1] : book.length;
    if (first == end) return !done; // no words
    _painter
      ..text = TextSpan(text: book.paragraphs[p], style: style)
      ..layout(maxWidth: width);
    // The first character of each line. (computeLineMetrics gives heights but not offsets, and costs as
    // much as the layout itself, so every line is taken to be as tall as the paragraph's average.)
    final text = book.paragraphs[p];
    final lineStarts = <int>[];
    var at = 0;
    while (at < text.length) {
      final line = _painter.getLineBoundary(TextPosition(offset: at));
      if (line.start >= (lineStarts.lastOrNull ?? -1) + 1) lineStarts.add(line.start);
      at = line.end > at ? line.end : at + 1;
    }
    final lineHeight = _painter.height / lineStarts.length;
    var word = first;
    var gap = _pageEmpty ? 0.0 : _gap;
    for (final lineStart in lineStarts) {
      // The first word on this line: the first word that starts at or after the line's first character.
      word = _firstWordFrom(word, end, lineStart);
      // A line that starts inside a word (a word wider than the page) cannot start a page.
      final canBreak = word < end && word > starts.last;
      if (!_pageEmpty && _y + gap + lineHeight > height && canBreak) {
        starts.add(word); // the line does not fit: it starts the next page
        _y = 0;
        gap = 0;
      }
      _y += gap + lineHeight;
      _pageEmpty = false;
      gap = 0;
    }
    return !done;
  }

  int _firstWordFrom(int from, int end, int offset) {
    var lo = from, hi = end; // `end` when no word starts at or after the offset
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (book.wordOffsets[mid] >= offset) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// The page starts. Call once, when [done]; frees the text painter.
  List<int> finish() {
    _painter.dispose();
    return starts;
  }

  /// Gives up the text painter of a pagination that is not wanted any more.
  void cancel() => _painter.dispose();
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
