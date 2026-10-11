import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/models.dart';
import '../storage/bookmark_store.dart';
import '../ui/audio_player.dart';
import '../ui/common.dart';
import '../util/format.dart';
import 'content.dart';
import 'pagination.dart';
import 'reader_settings.dart';
import 'settings_sheet.dart';

/// Reads a book in the app: text drawn by the app (page-turner or scroll), or
/// a PDF in the PDF viewer. Shows the player too when the work has a
/// recording in the same language.
///
/// Provisional: the text view is our own renderer; it may be replaced by a
/// reader package behind a ReaderEngine (see decision_reader.md).
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.work, required this.book});

  final Work work;
  final Book book;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static const loadLimit = Duration(minutes: 1);

  late Services _services;
  late final ValueNotifier<ReaderSettings> _settings;
  AudioController? _audio;
  bool _started = false;

  // Loading.
  BookText? _book;
  Object? _loadError;
  bool _timedOut = false;
  Timer? _limit;
  int _loadAttempt = 0;

  // Position: the first word on screen, so it survives layout changes.
  int _anchor = 0;
  double? _pendingProgress;
  bool _bookmarked = false;

  // Last layout, for turning pages and converting positions.
  List<int> _pageStarts = const [0];
  _ScrollLayout? _scroll;

  bool get _isPdf => widget.book.reading.kind == 'pdf';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = Services.of(context);
    if (_started) return;
    _started = true;
    _settings = ValueNotifier(_services.settingsStore.load())..addListener(_settingsChanged);
    _lastSettings = _settings.value;
    final recording = widget.work.recordingsFor(widget.book).firstOrNull;
    if (recording != null && !_isPdf) _audio = AudioController(_services.audio, recording);
    final bookmark = _services.bookmarks.load(widget.book.key);
    _bookmarked = bookmark != null;
    _pendingProgress = bookmark?.progress;
    if (!_isPdf) _load();
  }

  @override
  void dispose() {
    _limit?.cancel();
    _audio?.dispose();
    _scroll?.controller.dispose();
    _settings.dispose();
    super.dispose();
  }

  void _load() {
    final attempt = ++_loadAttempt;
    _loadError = null;
    _timedOut = false;
    if (attempt > 1) setState(() {});
    _limit?.cancel();
    _limit = Timer(loadLimit, () {
      if (mounted && _book == null) setState(() => _timedOut = true);
    });
    _services.contentLoader.load(widget.book.reading).then((content) {
      if (!mounted || attempt != _loadAttempt) return;
      _limit?.cancel();
      setState(() {
        _book = switch (content) {
          TextContent(:final paragraphs) => BookText(paragraphs),
          PdfContent() => null,
        };
        if (_book == null) _loadError = const ContentLoadException('Unexpected PDF');
      });
    }, onError: (Object error) {
      if (!mounted || attempt != _loadAttempt) return;
      _limit?.cancel();
      setState(() => _loadError = error);
    });
  }

  ReaderSettings _lastSettings = const ReaderSettings();

  void _settingsChanged() {
    final next = _settings.value;
    if (_lastSettings.viewMode == ViewMode.scroll && next.viewMode != ViewMode.scroll) {
      _anchor = _scroll?.anchor() ?? _anchor;
      _scroll?.controller.dispose();
      _scroll = null;
    }
    _lastSettings = next;
    _services.settingsStore.save(next);
    setState(() {});
  }

  // Pages.

  int get _page => pageOf(_pageStarts, _anchor);

  void _goToPage(int page) {
    if (page < 0 || page >= _pageStarts.length) return;
    setState(() => _anchor = _pageStarts[page]);
  }

  double get _progress {
    if (_settings.value.viewMode == ViewMode.scroll) {
      final book = _book!;
      final anchor = _scroll?.anchor() ?? _anchor;
      return book.length <= 1 ? 0 : anchor / (book.length - 1);
    }
    final pages = _pageStarts.length;
    return pages <= 1 ? 0 : _page / (pages - 1);
  }

  Future<void> _toggleBookmark() async {
    final messenger = ScaffoldMessenger.of(context);
    final key = widget.book.key;
    final String message;
    if (_bookmarked) {
      await _services.bookmarks.remove(key);
      message = 'Bookmark removed';
    } else {
      await _services.bookmarks.save(key, Bookmark(progress: _progress));
      message = 'Bookmark saved';
    }
    if (!mounted) return;
    setState(() => _bookmarked = !_bookmarked);
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReaderSettingsSheet(settings: _settings),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _book == null || _settings.value.viewMode != ViewMode.pageTurner) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goToPage(_page + 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goToPage(_page - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings.value;
    final brightness = settings.theme == ReaderTheme.dark ? Brightness.dark : Brightness.light;
    final showText = !_isPdf && _book != null;
    return Theme(
      data: FreeBookReaderApp.theme(brightness),
      child: Builder(builder: (context) {
        return Scaffold(
          key: const Key('reader-page'),
          backgroundColor: _isPdf ? null : settings.backgroundColor,
          appBar: AppBar(
            title: Heading(widget.book.title, key: const Key('reader-title'), maxLines: 1),
            actions: [
              if (showText) ...[
                IconButton(
                  key: const Key('bookmark-button'),
                  onPressed: _toggleBookmark,
                  icon: Icon(_bookmarked ? Icons.bookmark : Icons.bookmark_border,
                      semanticLabel: _bookmarked ? 'Remove bookmark' : 'Add bookmark'),
                ),
                IconButton(
                  key: const Key('reader-settings-button'),
                  onPressed: () => _openSettings(context),
                  icon: const Icon(Icons.text_format, semanticLabel: 'Display settings'),
                ),
              ],
            ],
          ),
          body: _isPdf
              ? _services.pdfViewBuilder(context, Uri.parse(widget.book.reading.url))
              : Column(
                  children: [
                    Expanded(
                      child: KeyedSubtree(
                        key: const Key('reader-surface'),
                        child: ColoredBox(
                          color: settings.backgroundColor,
                          child: showText ? _textView(context, settings) : _status(context),
                        ),
                      ),
                    ),
                    if (showText && settings.viewMode == ViewMode.pageTurner) _pageControls(context),
                    if (_audio != null) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: AudioPlayerPanel(
                            key: const Key('audio-player'), controller: _audio!, compact: true),
                      ),
                    ],
                  ],
                ),
        );
      }),
    );
  }

  Widget _status(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final source = sourceName(widget.book.source);
    Widget message(Key key, String what, {bool retry = false}) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LiveRegion(key: key, child: Text(what, textAlign: TextAlign.center, style: text.bodyLarge)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (retry)
                      FilledButton(key: const Key('retry'), onPressed: _load, child: const Text('Try again')),
                    OutlinedButton(
                      key: const Key('open-external'),
                      onPressed: () => _services.urlOpener.open(Uri.parse(widget.book.url)),
                      child: Text('Open at $source'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
    if (_loadError != null) {
      return message(const Key('load-error'), 'The book could not be loaded.', retry: true);
    }
    if (_timedOut) {
      return message(const Key('load-timeout'),
          'The book is taking more than a minute to load. You can keep waiting or open it at $source.');
    }
    return const Center(
      child: LiveRegion(
        key: Key('loading-book'),
        child: CircularProgressIndicator(semanticsLabel: 'Loading book'),
      ),
    );
  }

  Widget _textView(BuildContext context, ReaderSettings settings) {
    final book = _book!;
    final style = settings.textStyle;
    final scaler = MediaQuery.textScalerOf(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, constraints) {
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
        _pageStarts = _layoutPages(book, style, scaler, width, constraints.maxHeight - 2 * padding,
            settings.paragraphSpacing >= 0.5 ? '\n\n' : '\n');
        if (_pendingProgress != null) {
          _anchor = _pageStarts[(_pendingProgress! * (_pageStarts.length - 1)).round()];
          _pendingProgress = null;
        }
        final page = _page;
        final end = page + 1 < _pageStarts.length ? _pageStarts[page + 1] : book.length;
        // The page controls were built before this layout; rebuild them if
        // the page or the page count changed.
        if (_controlsShow != (page, _pageStarts.length)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
        return Padding(
          padding: const EdgeInsets.all(padding),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              book.text(_pageStarts[page], end, settings.paragraphSpacing >= 0.5 ? '\n\n' : '\n'),
              key: const Key('reader-page-text'),
              style: style,
            ),
          ),
        );
      }),
    );
  }

  // Pagination is costly; redo it only when the layout changes.
  Object? _pagesFor;

  List<int> _layoutPages(
      BookText book, TextStyle style, TextScaler scaler, double width, double height, String br) {
    final key = (book, style, scaler, width, height, br);
    if (key == _pagesFor) return _pageStarts;
    _pagesFor = key;
    return paginate(book,
        style: style, textScaler: scaler, width: width, height: height, paragraphBreak: br);
  }

  (int, int)? _controlsShow;

  Widget _pageControls(BuildContext context) {
    final page = _page;
    final pages = _pageStarts.length;
    _controlsShow = (page, pages);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          OutlinedButton(
            key: const Key('previous-page'),
            onPressed: page > 0 ? () => _goToPage(page - 1) : null,
            child: const Icon(Icons.chevron_left, semanticLabel: 'Previous page'),
          ),
          Expanded(
            child: LiveRegion(
              child: Text('Page ${page + 1} of $pages',
                  key: const Key('page-indicator'), textAlign: TextAlign.center),
            ),
          ),
          OutlinedButton(
            key: const Key('next-page'),
            onPressed: page + 1 < pages ? () => _goToPage(page + 1) : null,
            child: const Icon(Icons.chevron_right, semanticLabel: 'Next page'),
          ),
        ],
      ),
    );
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
