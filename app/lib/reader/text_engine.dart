import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/models.dart';
import '../services/speech_engine.dart';
import '../util/format.dart';
import 'content.dart';
import 'pagination.dart';
import 'read_aloud.dart';
import 'reader_engine.dart';
import 'reader_settings.dart';

/// Our own renderer: paragraphs from the book's HTML or text, drawn by the app
/// and paginated with [TextPainter]. Used where flutter_readium is not set up
/// yet (everywhere but web). It has no EPUB or images. It reads aloud with the
/// [SpeechEngine] it is given (none: no read aloud), one chunk of a sentence or
/// more at a time, highlighting the word being spoken and turning the page.
///
/// Counting the pages of a novel takes about half a second, so it runs in slices of a few milliseconds
/// between frames. Until it is done, the text from the reader's place is shown without page numbers.
///
/// Its locator is the index of the first word on screen ("word:123"), which
/// survives a change of font, size or view.
class TextReaderEngine extends ChangeNotifier implements ReaderEngine {
  TextReaderEngine(this._loader, {SpeechEngine? speech}) {
    if (speech != null) _readAloud = _TextReadAloud(this, speech);
  }

  final ContentLoader _loader;
  _TextReadAloud? _readAloud;

  // The word being read aloud, highlighted.
  int? _spoken;
  final _positions = StreamController<ReaderPosition>.broadcast();

  BookText? _book;
  ReaderSettings _settings = const ReaderSettings();

  // Position: the first word on screen, so it survives layout changes.
  int _anchor = 0;
  double? _pendingProgress;

  // Last layout, for turning pages and converting positions.
  static const _sliceMilliseconds = 8;
  List<int> _pageStarts = const [0];
  bool _paginated = false; // whether _pageStarts is for the layout now on screen
  int _wordsPerPage = 300; // for the text shown while the pages are counted
  Object? _pagesFor;
  int _job = 0; // the pagination that is wanted; an older one stops
  bool _disposed = false;
  _ScrollLayout? _scroll;
  (int, int)? _emitted;

  @override
  Future<void> open(ReadingOptions book, {required ReaderSettings settings, ReaderPosition? at}) async {
    _settings = settings;
    final content = await _loader.load(book);
    _book = switch (content) {
      TextContent(:final paragraphs) => BookText(paragraphs),
      PdfContent() => throw const ReaderOpenException('Unexpected PDF'),
    };
    if (at != null) _goTo(at);
  }

  bool get _scrolling => _settings.viewMode == ViewMode.scroll;

  int get _page => pageOf(_pageStarts, _anchor);

  @override
  ReaderPosition get position {
    final book = _book;
    if (book == null) return ReaderPosition.start;
    if (_scrolling) {
      final anchor = _scroll?.anchor() ?? _anchor;
      return ReaderPosition(
        progress: book.length <= 1 ? 0 : anchor / (book.length - 1),
        locator: 'word:$anchor',
        atStart: anchor == 0,
      );
    }
    if (!_paginated) {
      return ReaderPosition(
        progress: book.length <= 1 ? 0 : _anchor / (book.length - 1),
        locator: 'word:$_anchor',
        atStart: _anchor == 0,
      );
    }
    final page = _page, pages = _pageStarts.length;
    return ReaderPosition(
      progress: pages <= 1 ? 0 : page / (pages - 1),
      locator: 'word:$_anchor',
      page: page + 1,
      pageCount: pages,
      atStart: page == 0,
      atEnd: page == pages - 1,
    );
  }

  @override
  Stream<ReaderPosition> get positions => _positions.stream;

  void _changed() {
    notifyListeners();
    _emit();
  }

  /// Tells listeners when the page or the page count changes.
  void _emit() {
    final now = (_page, _pageStarts.length);
    if (_scrolling || !_paginated || now == _emitted || _positions.isClosed) return;
    _emitted = now;
    _positions.add(position);
  }

  void _goToPage(int page) {
    if (!_paginated || page < 0 || page >= _pageStarts.length) return;
    _anchor = _pageStarts[page];
    _changed();
  }

  void _scrollBy(double screens) {
    final controller = _scroll?.controller;
    if (controller == null || !controller.hasClients) return;
    final p = controller.position;
    controller.jumpTo((p.pixels + screens * p.viewportDimension).clamp(0.0, p.maxScrollExtent));
  }

  @override
  ReadAloud? get readAloud => _readAloud;

  /// The first word on screen: where reading aloud starts.
  int get _firstWord => _scrolling ? (_scroll?.anchor() ?? _anchor) : _anchor;

  /// The reader is reading word [word]: show it, and move to the page or paragraph it is on.
  void _follow(int word, {bool mark = true}) {
    if (mark) _spoken = word;
    final book = _book;
    if (book == null) return;
    if (_scrolling) {
      _scroll?.reveal(book.paragraphOfWord[word], book.wordOffsets[word]);
    } else if (_paginated) {
      final page = pageOf(_pageStarts, word);
      if (page != _page) _anchor = _pageStarts[page];
    } else if (word >= _anchor + _wordsPerPage) {
      _anchor = word;
    }
    _changed();
  }

  void _unmark() {
    if (_spoken == null) return;
    _spoken = null;
    _changed();
  }

  @override
  Future<void> next() async {
    if (_scrolling) return _scrollBy(0.9);
    _goToPage(_page + 1);
    await _readAloud?._moved();
  }

  @override
  Future<void> previous() async {
    if (_scrolling) return _scrollBy(-0.9);
    _goToPage(_page - 1);
    await _readAloud?._moved();
  }

  void _goTo(ReaderPosition position) {
    final word = int.tryParse(position.locator?.replaceFirst('word:', '') ?? '');
    if (word != null && word >= 0 && word < (_book?.length ?? 0)) {
      _anchor = word;
      _pendingProgress = null;
    } else {
      _pendingProgress = position.progress;
    }
    // The scroll view is rebuilt at the new place.
    _scroll?.controller.dispose();
    _scroll = null;
  }

  @override
  Future<void> goTo(ReaderPosition position) async {
    _goTo(position);
    _changed();
    await _readAloud?._moved();
  }

  @override
  Future<void> apply(ReaderSettings settings) async {
    if (_scrolling && settings.viewMode != ViewMode.scroll) {
      _anchor = _scroll?.anchor() ?? _anchor;
      _scroll?.controller.dispose();
      _scroll = null;
    }
    _settings = settings;
    _changed();
  }

  @override
  Widget buildView(BuildContext context, {Locale? locale}) {
    _locale = locale;
    return ListenableBuilder(listenable: this, builder: _build);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _job++;
    await _readAloud?._stopSpeech();
    _scroll?.controller.dispose();
    _scroll = null;
    await _positions.close();
    super.dispose();
  }

  Widget _build(BuildContext context, Widget? _) {
    final book = _book!;
    final settings = _settings;
    final style = settings.textStyle;
    final scaler = MediaQuery.textScalerOf(context);
    final gap = settings.paragraphSpacing * settings.fontSize;
    return LayoutBuilder(builder: (context, constraints) {
      const padding = 16.0;
      final width = constraints.maxWidth - 2 * padding;
      if (settings.viewMode == ViewMode.scroll) {
        final layout = _scroll = _ScrollLayout.update(_scroll, book, style, scaler, width, gap);
        if (_pendingProgress != null) {
          _anchor = (_pendingProgress! * (book.length - 1)).round();
          _pendingProgress = null;
        }
        layout.attach(_anchor);
        // A new layout is a new list: given a new controller, a list keeps its old pixel offset instead.
        return KeyedSubtree(
          key: ObjectKey(layout),
          child: ListView.builder(
            key: const Key('reader-scroll'),
            controller: layout.controller,
            padding: const EdgeInsets.all(padding),
            itemCount: book.paragraphs.length,
            itemBuilder: (context, i) => Padding(
              padding: EdgeInsets.only(bottom: layout.gap),
              child: _paragraph(book, i, style),
            ),
          ),
        );
      }
      final layout = (book, style, scaler, width, constraints.maxHeight - 2 * padding, gap);
      if (layout != _pagesFor) {
        _pagesFor = layout;
        _paginated = false;
        _emitted = null;
        unawaited(_paginate(++_job, book, style, scaler, width, constraints.maxHeight - 2 * padding, gap));
      }
      if (_pendingProgress != null) {
        _anchor = (_pendingProgress! * (book.length - 1)).round();
        _pendingProgress = null;
      }
      if (!_paginated) {
        // Not counted yet: the text from the reader's place, cut off where the screen ends.
        final end = (_anchor + _wordsPerPage).clamp(0, book.length);
        return ClipRect(
          child: Padding(
            padding: const EdgeInsets.all(padding),
            child: Align(
              alignment: Alignment.topLeft,
              child: _pageText(book, _anchor, end, gap, style, const Key('reader-page-pending')),
            ),
          ),
        );
      }
      // The page count is known only now; delivery is async, so listeners
      // update after this frame.
      _emit();
      final page = _page;
      final end = page + 1 < _pageStarts.length ? _pageStarts[page + 1] : book.length;
      return Padding(
        padding: const EdgeInsets.all(padding),
        child: Align(
          alignment: Alignment.topLeft,
          child: _pageText(book, _pageStarts[page], end, gap, style, const Key('reader-page-text')),
        ),
      );
    });
  }

  /// The word being read aloud, in the colours of the page swapped.
  TextStyle get _markStyle => TextStyle(color: _settings.backgroundColor, backgroundColor: _settings.textColor);

  Locale? _locale;

  Widget _marked(String text, int start, int end, TextStyle style, Key key) => Text.rich(
        TextSpan(children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(text: text.substring(start, end), style: _markStyle),
          TextSpan(text: text.substring(end)),
        ]),
        key: key,
        style: style,
        locale: _locale,
      );

  Widget _paragraph(BookText book, int i, TextStyle style) {
    final key = Key('reader-paragraph-$i');
    final word = _spoken;
    if (word == null || book.paragraphOfWord[word] != i) return Text(book.paragraphs[i], key: key, style: style, locale: _locale);
    final start = book.wordOffsets[word];
    return _marked(book.paragraphs[i], start, start + book.words[word].replaceFirst('\n', '').length, style, key);
  }

  Widget _pageText(BookText book, int start, int end, double gap, TextStyle style, Key key) {
    final span = pageSpan(book, start, end, paragraphGap: gap, mark: _spoken, markStyle: _markStyle);
    if (span.children == null) return Text(span.text!, key: key, style: style, locale: _locale);
    return Text.rich(span, key: key, style: style, locale: _locale);
  }

  /// Counts the pages in slices, one per frame, so the screen keeps drawing. Stops if the layout changes
  /// meanwhile.
  Future<void> _paginate(int job, BookText book, TextStyle style, TextScaler scaler, double width,
      double height, double gap) async {
    await SchedulerBinding.instance.endOfFrame; // not inside the build that asked for it
    if (job != _job) return;
    final paginator = Paginator(book,
        style: style, textScaler: scaler, width: width, height: height, paragraphGap: gap);
    final watch = Stopwatch()..start();
    while (paginator.step()) {
      if (watch.elapsedMilliseconds < _sliceMilliseconds) continue;
      await SchedulerBinding.instance.endOfFrame;
      if (job != _job) {
        paginator.cancel();
        return;
      }
      watch.reset();
    }
    _pageStarts = paginator.finish();
    _paginated = true;
    _wordsPerPage = max(50, (book.length / _pageStarts.length).ceil());
    final spoken = _spoken;
    if (spoken != null) _anchor = _pageStarts[pageOf(_pageStarts, spoken)]; // the layout changed under it
    if (!_disposed) _changed();
  }
}

/// Paragraph heights for the scroll view, to turn a word into a scroll offset
/// and back.
class _ScrollLayout {
  _ScrollLayout(this.book, this.style, this.scaler, this.width, this.gap);

  /// Reuses [old] when nothing that affects layout changed. Otherwise the new layout opens at the word that was
  /// at the top of the old one: the same pixel offset would be another place in the book.
  static _ScrollLayout update(_ScrollLayout? old, BookText book, TextStyle style, TextScaler scaler,
      double width, double gap) {
    if (old != null &&
        old.book == book &&
        old.style == style &&
        old.scaler == scaler &&
        old.width == width &&
        old.gap == gap) {
      return old;
    }
    final next = _ScrollLayout(book, style, scaler, width, gap);
    final oldController = old?._controller;
    if (oldController != null) {
      next.attach(old!.anchor());
      // The list lets go of the old controller in this frame.
      SchedulerBinding.instance.addPostFrameCallback((_) => oldController.dispose());
    }
    return next;
  }

  final BookText book;
  final TextStyle style;
  final TextScaler scaler;
  final double width;
  final double gap;
  ScrollController? _controller;
  final List<double> _tops = [0]; // top of each paragraph, measured lazily

  ScrollController get controller => _controller!;

  /// Creates the controller the first time, scrolled so that the line holding [word] is at the top.
  void attach(int word) {
    if (_controller != null) return;
    if (book.length == 0) {
      _controller = ScrollController();
      return;
    }
    final paragraph = book.paragraphOfWord[word];
    final painter = _layout(paragraph);
    final line = painter.getOffsetForCaret(TextPosition(offset: book.wordOffsets[word]), Rect.zero).dy;
    painter.dispose();
    _controller = ScrollController(initialScrollOffset: _top(paragraph) + line);
  }

  TextPainter _layout(int paragraph) => TextPainter(
      text: TextSpan(text: book.paragraphs[paragraph], style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler)
    ..layout(maxWidth: width);

  double _top(int paragraph) {
    if (paragraph < _tops.length) return _tops[paragraph];
    final painter = TextPainter(textDirection: TextDirection.ltr, textScaler: scaler);
    while (_tops.length <= paragraph) {
      final i = _tops.length - 1;
      painter.text = TextSpan(text: book.paragraphs[i], style: style);
      painter.layout(maxWidth: width);
      _tops.add(_tops.last + painter.height + gap);
    }
    painter.dispose();
    return _tops[paragraph];
  }

  /// Scrolls so that the word at [offset] in [paragraph] is on screen: the whole paragraph when it fits, else
  /// the word, a fifth of the way down.
  void reveal(int paragraph, int offset) {
    final c = _controller;
    if (c == null || !c.hasClients) return;
    final p = c.position;
    final top = _top(paragraph), bottom = _top(paragraph + 1) - gap;
    final double target;
    if (bottom - top <= p.viewportDimension) {
      if (top >= p.pixels && bottom <= p.pixels + p.viewportDimension) return;
      target = top;
    } else {
      final painter = _layout(paragraph);
      final y = top + painter.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dy;
      painter.dispose();
      if (y >= p.pixels && y <= p.pixels + p.viewportDimension * 0.75) return;
      target = y - p.viewportDimension * 0.2;
    }
    c.animateTo(target.clamp(0.0, p.maxScrollExtent),
        duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
  }

  /// The first word of the line at the top of the view (review 2026-10-11-main #20: it was the paragraph's
  /// first word, which could be screens back in a long paragraph).
  int anchor() {
    if (book.length == 0) return 0;
    final offset = _controller?.hasClients == true ? _controller!.offset : 0.0;
    var p = 0;
    while (p + 1 < book.paragraphs.length && _top(p + 1) <= offset) {
      p++;
    }
    final first = book.paragraphStarts[p];
    final end = p + 1 < book.paragraphs.length ? book.paragraphStarts[p + 1] : book.length;
    final within = offset - _top(p);
    if (within <= 0 || first == end) return first;
    final painter = _layout(p);
    final height = painter.height;
    final line = painter.getLineBoundary(painter.getPositionForOffset(Offset(0, within)));
    painter.dispose();
    if (within >= height) return end < book.length ? end : first; // in the gap below the paragraph
    // The first word that starts on that line; a line that starts inside a word belongs to that word.
    var lo = first, hi = end;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (book.wordOffsets[mid] >= line.start) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    if (lo == end || (lo > first && book.wordOffsets[lo] > line.start)) {
      return lo == first ? first : lo - 1;
    }
    return lo;
  }
}


/// Reading a book aloud with a [SpeechEngine]: a chunk (a sentence or more, inside one paragraph) at a time, so the
/// word being spoken can be highlighted and the page turned. Pausing stops the speech and remembers the word,
/// since not every platform can pause in the middle of a chunk.
class _TextReadAloud implements ReadAloud {
  _TextReadAloud(this._engine, this._speech);

  /// A chunk ends at a sentence end once it has this many characters, and at the latest at [_maxChunk].
  static const _minChunk = 100;
  static const _maxChunk = 800;
  static final _sentenceEnd = RegExp(r'[.!?\u2026]["\x27\u201d\u2019)\]]*$');

  final TextReaderEngine _engine;
  final SpeechEngine _speech;
  @override
  final ValueNotifier<ReadAloudState> state = ValueNotifier(const ReadAloudState());

  String _language = 'en';
  int _session = 0; // a newer session ends the loop of an older one
  int _current = 0; // the word being spoken, or the next to speak

  ReadAloudState get _now => state.value;

  @override
  Future<void> start({String? language}) async {
    // A Stop, or the book closing, while the voices are looked up wins over this start.
    final session = ++_session;
    _language = language ?? 'en';
    final available = await _speech.hasVoice(_language);
    if (_engine._disposed || session != _session) return;
    if (!available) {
      state.value = _now.copyWith(
          status: ReadAloudStatus.stopped, error: 'This device has no voice for ${languageName(_language)}.');
      return;
    }
    await _read(_engine._firstWord);
  }

  @override
  Future<void> pause() async {
    if (_now.status != ReadAloudStatus.reading) return;
    _session++;
    state.value = _now.copyWith(status: ReadAloudStatus.paused);
    await _speech.stop();
  }

  @override
  Future<void> resume() async {
    if (_now.status != ReadAloudStatus.paused) return;
    await _read(_current);
  }

  @override
  Future<void> stop() async {
    _session++;
    state.value = _now.copyWith(status: ReadAloudStatus.stopped, clearError: true);
    _engine._unmark();
    await _speech.stop();
  }

  @override
  Future<void> setRate(double rate) async {
    state.value = _now.copyWith(rate: rate);
    if (_now.status == ReadAloudStatus.reading) await _read(_current);
  }

  /// The reader turned the page or went to a place: go on from there.
  Future<void> _moved() async {
    switch (_now.status) {
      case ReadAloudStatus.reading:
        await _read(_engine._firstWord);
      case ReadAloudStatus.paused:
        _current = _engine._firstWord;
        _engine._unmark();
      case ReadAloudStatus.stopped:
        break;
    }
  }

  /// Ends the speech when the book closes.
  Future<void> _stopSpeech() async {
    _session++;
    state.value = const ReadAloudState();
    await _speech.stop();
  }

  int _chunkEnd(BookText book, int from) {
    final paragraph = book.paragraphOfWord[from];
    var i = from, chars = 0;
    while (i < book.length && book.paragraphOfWord[i] == paragraph) {
      chars += book.words[i].length + 1;
      i++;
      if (chars >= _maxChunk || (chars >= _minChunk && _sentenceEnd.hasMatch(book.words[i - 1]))) break;
    }
    return i;
  }

  /// Starts reading at word [from]. Completes once the speech has started; the reading goes on by itself.
  Future<void> _read(int from) async {
    if (_engine._book == null) return;
    final session = ++_session;
    state.value = _now.copyWith(status: ReadAloudStatus.reading, clearError: true);
    await _speech.stop(); // a speech service may queue what it is given instead of replacing what it says
    if (session == _session) unawaited(_run(session, from));
  }

  /// Speaks chunk after chunk until the book ends or a newer session takes over.
  Future<void> _run(int session, int from) async {
    final book = _engine._book!;
    var word = from;
    while (session == _session && word < book.length) {
      final end = _chunkEnd(book, word);
      final text = StringBuffer();
      final starts = <int>[];
      for (var i = word; i < end; i++) {
        if (i > word && (book.words[i].startsWith('\n') || book.spaceBefore[i])) {
          text.write(book.words[i].startsWith('\n') ? '\n' : ' ');
        }
        starts.add(text.length);
        text.write(book.words[i].replaceFirst('\n', ''));
      }
      _current = word;
      final first = word;
      _engine._follow(first, mark: false);
      try {
        await _speech.speak(text.toString(), language: _language, rate: _now.rate, onWord: (start, _) {
          if (session != _session) return;
          var k = 0;
          while (k + 1 < starts.length && starts[k + 1] <= start) {
            k++;
          }
          _current = first + k;
          _engine._follow(_current);
        });
      } on Object catch (e) {
        if (session == _session) {
          _session++;
          state.value = _now.copyWith(
              status: ReadAloudStatus.stopped,
              error: 'Reading aloud stopped: ${e is SpeechException ? e.message : e}');
          _engine._unmark();
        }
        return;
      }
      word = end;
    }
    if (session == _session) {
      _session++;
      state.value = _now.copyWith(status: ReadAloudStatus.stopped);
      _engine._unmark();
    }
  }
}
