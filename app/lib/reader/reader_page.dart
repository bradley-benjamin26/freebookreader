import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../app.dart';
import '../models/models.dart';
import '../storage/bookmark_store.dart';
import '../ui/audio_player.dart';
import '../ui/common.dart';
import '../util/format.dart';
import 'read_aloud.dart';
import 'reader_engine.dart';
import 'reader_settings.dart';
import 'settings_sheet.dart';

/// Reads a book in the app: text through a [ReaderEngine] (page-turner or
/// scroll), or a PDF in the PDF viewer. Shows the player too when the work has
/// a recording in the same language.
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

  ReaderEngine? _engine;
  ReadAloud? _readAloud;
  StreamSubscription<ReaderPosition>? _positionSub;
  ReaderPosition _position = ReaderPosition.start;
  ReaderPosition? _startAt;
  bool _bookmarked = false;

  // On web the engine's view can be an iframe, which takes clicks meant for
  // Flutter widgets drawn over it; it is covered while the settings are open.
  bool _settingsOpen = false;

  // Loading.
  bool _opened = false;
  Object? _loadError;
  bool _timedOut = false;
  Timer? _limit;
  int _loadAttempt = 0;

  bool get _isPdf => widget.book.reading.kind == 'pdf';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = Services.of(context);
    if (_started) return;
    _started = true;
    _settings = ValueNotifier(_services.settingsStore.load())..addListener(_settingsChanged);
    final recording = widget.work.recordingsFor(widget.book).firstOrNull;
    if (recording != null && !_isPdf) _audio = AudioController(_services.audio, recording)..addListener(_audioChanged);
    final bookmark = _services.bookmarks.load(widget.book.key);
    _bookmarked = bookmark != null;
    if (bookmark != null) _startAt = ReaderPosition(progress: bookmark.progress, locator: bookmark.locator);
    if (_isPdf) return;
    _engine = _services.readerEngine(widget.book.reading);
    if (_engine == null) {
      _loadError = const ReaderOpenException('No reader for this book');
      return;
    }
    _readAloud = _engine!.readAloud;
    _positionSub = _engine!.positions.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _load();
  }

  @override
  void dispose() {
    _limit?.cancel();
    _audio?.removeListener(_audioChanged);
    _audio?.dispose();
    _positionSub?.cancel();
    _engine?.dispose();
    _settings.dispose();
    super.dispose();
  }

  void _load() {
    final engine = _engine!;
    final attempt = ++_loadAttempt;
    _loadError = null;
    _timedOut = false;
    if (attempt > 1) setState(() {});
    _limit?.cancel();
    _limit = Timer(loadLimit, () {
      if (mounted && !_opened) setState(() => _timedOut = true);
    });
    engine.open(widget.book.reading, settings: _settings.value, at: _startAt).then((_) {
      if (!mounted || attempt != _loadAttempt) return;
      _limit?.cancel();
      setState(() {
        _opened = true;
        _position = engine.position;
      });
    }, onError: (Object error) {
      if (!mounted || attempt != _loadAttempt) return;
      _limit?.cancel();
      setState(() => _loadError = error);
    });
  }

  /// The recording and read aloud do not play together: whichever starts second stops the first.
  void _audioChanged() {
    if (_audio!.playing && _readAloud?.state.value.status == ReadAloudStatus.reading) _readAloud!.pause();
  }

  Future<void> _toggleReadAloud() async {
    final readAloud = _readAloud!;
    switch (readAloud.state.value.status) {
      case ReadAloudStatus.reading:
        return readAloud.pause();
      case ReadAloudStatus.paused:
        if (_audio?.playing == true) await _audio!.togglePlay();
        return readAloud.resume();
      case ReadAloudStatus.stopped:
        if (_audio?.playing == true) await _audio!.togglePlay();
        return readAloud.start(language: widget.book.language);
    }
  }

  void _settingsChanged() {
    final next = _settings.value;
    _services.settingsStore.save(next);
    _engine?.apply(next);
    setState(() {});
  }

  Future<void> _toggleBookmark() async {
    final messenger = ScaffoldMessenger.of(context);
    final key = widget.book.key;
    final String message;
    if (_bookmarked) {
      await _services.bookmarks.remove(key);
      message = 'Bookmark removed';
    } else {
      final at = _engine!.position;
      await _services.bookmarks.save(key, Bookmark(progress: at.progress, locator: at.locator));
      message = 'Bookmark saved';
    }
    if (!mounted) return;
    setState(() => _bookmarked = !_bookmarked);
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSettings(BuildContext context) async {
    setState(() => _settingsOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReaderSettingsSheet(settings: _settings),
    );
    if (mounted) setState(() => _settingsOpen = false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_opened || _settings.value.viewMode != ViewMode.pageTurner) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (!_position.atEnd) _engine!.next();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (!_position.atStart) _engine!.previous();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings.value;
    final brightness = settings.theme == ReaderTheme.dark ? Brightness.dark : Brightness.light;
    final showText = !_isPdf && _opened;
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
                          child: showText
                              ? Stack(children: [
                                  Positioned.fill(
                                    child: Focus(
                                        autofocus: true, onKeyEvent: _onKey, child: _engine!.buildView(context)),
                                  ),
                                  if (_settingsOpen)
                                    Positioned.fill(
                                      child: PointerInterceptor(
                                          key: const Key('reader-click-shield'), child: const SizedBox.expand()),
                                    ),
                                ])
                              : _status(context),
                        ),
                      ),
                    ),
                    if (showText && settings.viewMode == ViewMode.pageTurner) _pageControls(context),
                    if (showText && _readAloud != null) ...[
                      const Divider(height: 1),
                      _ReadAloudBar(
                          key: const Key('read-aloud-bar'), readAloud: _readAloud!, onToggle: _toggleReadAloud),
                    ],
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
      return message(const Key('load-error'), 'The book could not be loaded.', retry: _engine != null);
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

  Widget _pageControls(BuildContext context) {
    final at = _position;
    final where = at.page != null && at.pageCount != null
        ? 'Page ${at.page} of ${at.pageCount}'
        : '${(at.progress * 100).round()}% read';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          OutlinedButton(
            key: const Key('previous-page'),
            onPressed: at.atStart ? null : _engine!.previous,
            child: const Icon(Icons.chevron_left, semanticLabel: 'Previous page'),
          ),
          Expanded(
            child: LiveRegion(
              child: Text(where,
                  key: const Key('page-indicator'), textAlign: TextAlign.center),
            ),
          ),
          OutlinedButton(
            key: const Key('next-page'),
            onPressed: at.atEnd ? null : _engine!.next,
            child: const Icon(Icons.chevron_right, semanticLabel: 'Next page'),
          ),
        ],
      ),
    );
  }
}


/// Play/pause, stop and speed for reading aloud.
class _ReadAloudBar extends StatelessWidget {
  const _ReadAloudBar({super.key, required this.readAloud, required this.onToggle});

  final ReadAloud readAloud;
  final VoidCallback onToggle;

  static String speedLabel(double rate) => 'Speed ${rate == rate.roundToDouble() ? rate.round() : rate}×';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReadAloudState>(
      valueListenable: readAloud.state,
      builder: (context, state, _) {
        final reading = state.status == ReadAloudStatus.reading;
        final index = readAloudRates.indexOf(state.rate);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton.filled(
                    key: const Key('read-aloud-toggle'),
                    onPressed: onToggle,
                    icon: Icon(reading ? Icons.pause : Icons.record_voice_over,
                        semanticLabel: switch (state.status) {
                          ReadAloudStatus.reading => 'Pause reading aloud',
                          ReadAloudStatus.paused => 'Resume reading aloud',
                          ReadAloudStatus.stopped => 'Read aloud',
                        }),
                  ),
                  if (state.status != ReadAloudStatus.stopped)
                    IconButton(
                      key: const Key('read-aloud-stop'),
                      onPressed: readAloud.stop,
                      icon: const Icon(Icons.stop, semanticLabel: 'Stop reading aloud'),
                    ),
                  IconButton(
                    key: const Key('read-aloud-slower'),
                    onPressed: index > 0 ? () => readAloud.setRate(readAloudRates[index - 1]) : null,
                    icon: const Icon(Icons.remove, semanticLabel: 'Read slower'),
                  ),
                  Text(speedLabel(state.rate), key: const Key('read-aloud-speed')),
                  IconButton(
                    key: const Key('read-aloud-faster'),
                    onPressed: index < readAloudRates.length - 1
                        ? () => readAloud.setRate(readAloudRates[index + 1])
                        : null,
                    icon: const Icon(Icons.add, semanticLabel: 'Read faster'),
                  ),
                ],
              ),
              if (state.error != null)
                LiveRegion(
                  key: const Key('read-aloud-error'),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(state.error!, textAlign: TextAlign.center),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
