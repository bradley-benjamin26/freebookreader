import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import 'content.dart';
import 'pagination.dart';
import 'reader_engine.dart';
import 'reader_settings.dart';

/// Our own renderer: paragraphs from the book's HTML or text, drawn by the app
/// and paginated with [TextPainter]. Used where flutter_readium is not set up
/// yet (everywhere but web). It has no EPUB, images or TTS.
///
/// Its locator is the index of the first word on screen ("word:123"), which
/// survives a change of font, size or view.
class TextReaderEngine extends ChangeNotifier implements ReaderEngine {
  TextReaderEngine(this._loader);

  final ContentLoader _loader;
  final _positions = StreamController<ReaderPosition>.broadcast();

  BookText? _book;
  ReaderSettings _settings = const ReaderSettings();

  // Position: the first word on screen, so it survives layout changes.
  int _anchor = 0;
  double? _pendingProgress;

  // Last layout, for turning pages and converting positions.
  List<int> _pageStarts = const [0];
  Object? _pagesFor;
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
    if (_scrolling || now == _emitted || _positions.isClosed) return;
    _emitted = now;
    _positions.add(position);
  }

  void _goToPage(int page) {
    if (page < 0 || page >= _pageStarts.length) return;
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
  Future<void> next() async => _scrolling ? _scrollBy(0.9) : _goToPage(_page + 1);

  @override
  Future<void> previous() async => _scrolling ? _scrollBy(-0.9) : _goToPage(_page - 1);

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
  Widget buildView(BuildContext context) => ListenableBuilder(listenable: this, builder: _build);

  @override
  Future<void> dispose() async {
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
    final paragraphBreak = settings.paragraphSpacing >= 0.5 ? '\n\n' : '\n';
    return LayoutBuilder(builder: (context, constraints) {
      const padding = 16.0;
      final width = constraints.maxWidth - 2 * padding;
      if (settings.viewMode == ViewMode.scroll) {
        final layout = _scroll = _ScrollLayout.update(
            _scroll, book, style, scaler, width, settings.paragraphSpacing * settings.fontSize);
        if (_pendingProgress != null) {
          _anchor = (_pendingProgress! * (book.length - 1)).round();
          _pendingProgress = null;
        }
        layout.attach(_anchor);
        return ListView.builder(
          key: const Key('reader-scroll'),
          controller: layout.controller,
          padding: const EdgeInsets.all(padding),
          itemCount: book.paragraphs.length,
          itemBuilder: (context, i) => Padding(
            padding: EdgeInsets.only(bottom: layout.gap),
            child: Text(book.paragraphs[i], key: Key('reader-paragraph-$i'), style: style),
          ),
        );
      }
      _pageStarts = _layoutPages(
          book, style, scaler, width, constraints.maxHeight - 2 * padding, paragraphBreak);
      if (_pendingProgress != null) {
        _anchor = _pageStarts[(_pendingProgress! * (_pageStarts.length - 1)).round()];
        _pendingProgress = null;
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
          child: Text(
            book.text(_pageStarts[page], end, paragraphBreak),
            key: const Key('reader-page-text'),
            style: style,
          ),
        ),
      );
    });
  }

  // Pagination is costly; redo it only when the layout changes.
  List<int> _layoutPages(
      BookText book, TextStyle style, TextScaler scaler, double width, double height, String br) {
    final key = (book, style, scaler, width, height, br);
    if (key == _pagesFor) return _pageStarts;
    _pagesFor = key;
    return paginate(book,
        style: style, textScaler: scaler, width: width, height: height, paragraphBreak: br);
  }
}

/// Paragraph heights for the scroll view, to turn a word into a scroll offset
/// and back.
class _ScrollLayout {
  _ScrollLayout(this.book, this.style, this.scaler, this.width, this.gap);

  /// Reuses [old] when nothing that affects layout changed.
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
    if (old?._controller != null) next._controller = old!._controller;
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

  /// Creates the controller the first time, scrolled to [word].
  void attach(int word) {
    if (_controller != null) return;
    final paragraph = book.paragraphOfWord.isEmpty ? 0 : book.paragraphOfWord[word];
    _controller = ScrollController(initialScrollOffset: _top(paragraph));
  }

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

  /// The first word of the paragraph at the top of the view.
  int anchor() {
    final offset = _controller?.hasClients == true ? _controller!.offset : 0.0;
    var p = 0;
    while (p + 1 < book.paragraphs.length && _top(p + 1) <= offset) {
      p++;
    }
    return book.paragraphStarts[p];
  }
}
