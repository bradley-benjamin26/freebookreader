import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

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
          for (final (j, (start, unit)) in _units(part).indexed) {
            words.add(i > 0 && j == 0 ? '\n$unit' : unit);
            wordOffsets.add(at + start);
            paragraphOfWord.add(p);
            spaceBefore.add(i == 0 && j == 0);
          }
          at += part.length + 1;
        }
        offset += piece.length + 1;
      }
    }
  }

  /// A run longer than this with no space in it is split between its letters (Thai, or a long web address),
  /// so that a page can end inside it.
  static const _longestRun = 40;

  /// The words of a piece of text with no spaces or line breaks, with where each starts in it. Chinese and
  /// Japanese are written without spaces, so each of their characters is a word, and a page can end after it.
  static List<(int, String)> _units(String part) {
    if (part.isEmpty) return const [];
    final split = part.length > _longestRun;
    if (!split && !part.runes.any(_isCjk)) return [(0, part)];
    final units = <(int, String)>[];
    var at = 0, runStart = -1;
    for (final letter in part.characters) {
      if (split || _isCjk(letter.runes.first)) {
        if (runStart >= 0) units.add((runStart, part.substring(runStart, at)));
        runStart = -1;
        units.add((at, letter));
      } else if (runStart < 0) {
        runStart = at;
      }
      at += letter.length;
    }
    if (runStart >= 0) units.add((runStart, part.substring(runStart)));
    return units;
  }

  static bool _isCjk(int rune) =>
      (rune >= 0x3000 && rune <= 0x30FF) || // CJK punctuation, hiragana, katakana
      (rune >= 0x3400 && rune <= 0x4DBF) || // CJK extension A
      (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK ideographs
      (rune >= 0xF900 && rune <= 0xFAFF) || // compatibility ideographs
      (rune >= 0xFF00 && rune <= 0xFFEF) || // full-width forms
      (rune >= 0x20000 && rune <= 0x2FA1F); // extensions B and later

  final List<String> paragraphs;
  final List<String> words = [];
  final List<int> paragraphOfWord = [];

  /// Where each word's own text starts in its paragraph (after the line break, if the word follows one).
  final List<int> wordOffsets = [];

  /// The index of each paragraph's first word.
  final List<int> paragraphStarts = [];

  /// Whether a space comes before each word in its paragraph (not between Chinese characters, say).
  final List<bool> spaceBefore = [];

  int get length => words.length;

  /// Words [start, end) as text, with [paragraphBreak] between paragraphs and a '\n' where a line breaks.
  /// [breaks], when given, gets where each paragraph break starts in the text.
  String text(int start, int end, String paragraphBreak, {List<int>? breaks}) {
    final out = StringBuffer();
    for (var i = start; i < end; i++) {
      final word = words[i];
      if (i > start) {
        if (paragraphOfWord[i] != paragraphOfWord[i - 1]) {
          breaks?.add(out.length);
          out.write(paragraphBreak);
        } else if (!word.startsWith('\n') && spaceBefore[i]) {
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
      } else if (!words[word].startsWith('\n') && spaceBefore[word]) {
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
  required double paragraphGap,
}) {
  final paginator = Paginator(book,
      style: style, textScaler: textScaler, width: width, height: height, paragraphGap: paragraphGap);
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
    required double paragraphGap,
  }) : _painter = TextPainter(textDirection: TextDirection.ltr, textScaler: textScaler) {
    // The gap is measured as pageSpan draws it: an empty line between the paragraphs.
    double heightOf(InlineSpan span) => (_painter
          ..text = TextSpan(style: style, children: [span])
          ..layout(maxWidth: width))
        .height;
    final two = BookText(const ['A', 'A']);
    _gap = heightOf(pageSpan(two, 0, 2, paragraphGap: paragraphGap)) - heightOf(pageSpan(two, 0, 2, paragraphGap: 0));
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

/// What goes between paragraphs in [BookText.text] for a gap of [paragraphGap] pixels: an empty line, or just a
/// new line when there is no gap.
String paragraphBreakFor(double paragraphGap) => paragraphGap > 0 ? '\n\n' : '\n';

/// Words [start, end) of [book] as the reader draws them: the empty line between paragraphs is [paragraphGap]
/// pixels tall (before text scaling), and the word [mark], if given, is drawn in [markStyle]. Draw it under the
/// page's own style (`Text.rich(span, style: ...)`).
TextSpan pageSpan(BookText book, int start, int end,
    {required double paragraphGap, int? mark, TextStyle? markStyle}) {
  final paragraphBreak = paragraphBreakFor(paragraphGap);
  final breaks = <int>[];
  final text = book.text(start, end, paragraphBreak, breaks: breaks);
  // (from, to, style) of each part that is not in the page's style, in order; none of them overlap.
  final styled = <(int, int, TextStyle)>[
    if (paragraphGap > 0)
      for (final at in breaks) (at + 1, at + 2, TextStyle(fontSize: paragraphGap, height: 1)),
  ];
  if (mark != null && markStyle != null && mark >= start && mark < end) {
    final (from, to) = book.wordRange(start, mark, paragraphBreak);
    styled.add((from, to, markStyle));
    styled.sort((a, b) => a.$1.compareTo(b.$1));
  }
  if (styled.isEmpty) return TextSpan(text: text);
  final children = <TextSpan>[];
  var at = 0;
  for (final (from, to, partStyle) in styled) {
    if (from > at) children.add(TextSpan(text: text.substring(at, from)));
    children.add(TextSpan(text: text.substring(from, to), style: partStyle));
    at = to;
  }
  if (at < text.length) children.add(TextSpan(text: text.substring(at)));
  return TextSpan(children: children);
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
