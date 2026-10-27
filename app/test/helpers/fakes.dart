import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:free_book_reader/api/search_api.dart';
import 'package:free_book_reader/models/models.dart';
import 'package:free_book_reader/reader/content.dart';
import 'package:free_book_reader/reader/read_aloud.dart';
import 'package:free_book_reader/reader/reader_engine.dart';
import 'package:free_book_reader/reader/reader_settings.dart';
import 'package:free_book_reader/services/audio_engine.dart';
import 'package:free_book_reader/services/speech_engine.dart';
import 'package:free_book_reader/services/url_opener.dart';

class FakeSearchApi implements SearchApi {
  FakeSearchApi({
    required this.response,
    this.sourceInfos = const [],
    this.error,
  });

  SearchResponse response;
  List<SourceInfo> sourceInfos;
  Object? error;
  Completer<SearchResponse>? hold;
  final List<SearchQuery> queries = [];

  @override
  Future<SearchResponse> search(SearchQuery query) {
    queries.add(query);
    if (hold != null) return hold!.future;
    if (error != null) return Future.error(error!);
    return Future.value(response);
  }

  @override
  Future<List<SourceInfo>> sources() async => sourceInfos;
}

class FakeUrlOpener implements UrlOpener {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }
}

class FakeContentLoader implements ContentLoader {
  FakeContentLoader({this.content, this.never = false});

  BookContent? content;

  /// When true, loading never finishes (to test the one-minute limit).
  bool never;

  /// When true, the next load fails once with a [ContentLoadException].
  bool failNext = false;
  final List<ReadingOptions> requests = [];

  @override
  Future<BookContent> load(ReadingOptions options) {
    requests.add(options);
    if (never) return Completer<BookContent>().future;
    if (failNext) {
      failNext = false;
      return Future.error(const ContentLoadException('could not load'));
    }
    return Future.value(content ?? longText());
  }
}

/// Enough paragraphs to fill several pages on a phone.
TextContent longText({int paragraphs = 60}) => TextContent(List.generate(
      paragraphs,
      (i) => 'Paragraph $i. ${'It is a truth universally acknowledged, that a single man '
          'in possession of a good fortune, must be in want of a wife. ' * 3}',
    ));

/// A reader engine with [pageCount] pages that records what the reader page
/// asks of it. Its view is one line of text in the settings' colors.
class FakeReaderEngine implements ReaderEngine {
  FakeReaderEngine(
      {this.pageCount = 10, this.pageNumbers = true, this.never = false, this.failNext = false});

  final int pageCount;

  /// When false, positions carry no page numbers (like Readium on web).
  final bool pageNumbers;

  /// When true, opening never finishes (to test the one-minute limit).
  bool never;

  /// When true, the next open fails once with a [ReaderOpenException].
  bool failNext;

  /// 0-based.
  int page = 0;
  ReaderSettings? settings;
  bool disposed = false;
  final List<({ReadingOptions book, ReaderPosition? at})> opens = [];
  final List<ReaderSettings> applied = [];
  final List<String> calls = [];
  final _positions = StreamController<ReaderPosition>.broadcast();

  /// Null, like an engine that cannot read aloud, unless a test sets it.
  @override
  FakeReadAloud? readAloud;

  @override
  Future<void> open(ReadingOptions book, {required ReaderSettings settings, ReaderPosition? at}) {
    opens.add((book: book, at: at));
    this.settings = settings;
    if (never) return Completer<void>().future;
    if (failNext) {
      failNext = false;
      return Future.error(const ReaderOpenException('could not open'));
    }
    if (at != null) _goTo(at);
    return Future.value();
  }

  @override
  ReaderPosition get position => ReaderPosition(
        progress: pageCount <= 1 ? 0 : page / (pageCount - 1),
        locator: 'fake:$page',
        page: pageNumbers ? page + 1 : null,
        pageCount: pageNumbers ? pageCount : null,
        atStart: page == 0,
        atEnd: page == pageCount - 1,
      );

  @override
  Stream<ReaderPosition> get positions => _positions.stream;

  void _turn(int to) {
    page = to.clamp(0, pageCount - 1);
    _positions.add(position);
  }

  @override
  Future<void> next() async {
    calls.add('next');
    _turn(page + 1);
  }

  @override
  Future<void> previous() async {
    calls.add('previous');
    _turn(page - 1);
  }

  void _goTo(ReaderPosition at) {
    final exact = int.tryParse(at.locator?.replaceFirst('fake:', '') ?? '');
    page = (exact ?? (at.progress * (pageCount - 1)).round()).clamp(0, pageCount - 1);
  }

  @override
  Future<void> goTo(ReaderPosition position) async {
    calls.add('goTo');
    _goTo(position);
    _positions.add(this.position);
  }

  @override
  Future<void> apply(ReaderSettings settings) async {
    applied.add(settings);
    this.settings = settings;
  }

  @override
  Widget buildView(BuildContext context, {Locale? locale}) => Text('Text of page ${page + 1}',
      key: const Key('fake-reader-view'), style: TextStyle(color: settings!.textColor, fontSize: 18));

  @override
  Future<void> dispose() async {
    disposed = true;
    await _positions.close();
  }
}

/// Makes a [FakeReaderEngine] per opened book, or none when [none] is set.
class FakeReaderEngines {
  int pageCount = 10;
  bool pageNumbers = true;
  bool never = false;
  bool failNext = false;
  bool none = false;

  /// Whether the engines can read aloud.
  bool readAloud = false;
  final List<FakeReaderEngine> created = [];
  final List<ReadingOptions> asked = [];

  /// The engine of the book opened last.
  FakeReaderEngine get last => created.last;

  ReaderEngine? call(ReadingOptions book) {
    asked.add(book);
    if (none) return null;
    final engine = FakeReaderEngine(
        pageCount: pageCount, pageNumbers: pageNumbers, never: never, failNext: failNext);
    if (readAloud) engine.readAloud = FakeReadAloud();
    failNext = false;
    created.add(engine);
    return engine;
  }
}

class FakeAudioEngine implements AudioEngine {
  final List<String> calls = [];
  final List<Duration?> playedFrom = [];
  final StreamController<AudioPosition> _position = StreamController<AudioPosition>.broadcast();
  final StreamController<AudioStatus> _status = StreamController<AudioStatus>.broadcast();
  bool playing = false;
  Uri? current;
  AudioPosition? _last;

  /// When true, the next [play] fails (the file is missing, or there is no network).
  bool failNext = false;

  @override
  Future<void> play(Uri url, {Duration? from}) async {
    calls.add('play ${url.toString()}');
    playedFrom.add(from);
    if (failNext) {
      failNext = false;
      throw const AudioException('could not load');
    }
    if (url != current) {
      current = url;
      emitPosition(url, from ?? Duration.zero);
    }
    playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> seek(Duration position) async => calls.add('seek ${position.inSeconds}');

  /// Like just_audio, a new listener gets the last position at once, whichever file it belongs to.
  @override
  Stream<AudioPosition> get positionStream {
    late final StreamController<AudioPosition> controller;
    StreamSubscription<AudioPosition>? subscription;
    controller = StreamController<AudioPosition>(
      onListen: () {
        if (_last != null) controller.add(_last!);
        subscription = _position.stream.listen(controller.add);
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Stream<AudioStatus> get statusStream => _status.stream;

  void emitPosition(Uri url, Duration position) {
    _last = AudioPosition(url, position);
    _position.add(_last!);
  }

  /// The player stopped by itself (or was stopped from outside, e.g. a headset button).
  void emitStatus({required bool playing, bool completed = false}) {
    this.playing = playing;
    _status.add(AudioStatus(url: current, playing: playing, completed: completed));
  }

  @override
  Future<void> dispose() async {
    await _position.close();
    await _status.close();
  }
}


/// A read-aloud that records what the reader page asks of it.
class FakeReadAloud implements ReadAloud {
  final _state = ValueNotifier(const ReadAloudState());
  final List<String> calls = [];
  String? language;

  /// When set, the next [start] fails with this message.
  String? failNext;

  @override
  ValueListenable<ReadAloudState> get state => _state;

  /// Changes the state from outside, like speech that ends by itself.
  void emit(ReadAloudState state) => _state.value = state;

  @override
  Future<void> start({String? language}) async {
    calls.add('start');
    this.language = language;
    final error = failNext;
    failNext = null;
    _state.value = error != null
        ? _state.value.copyWith(status: ReadAloudStatus.stopped, error: error)
        : _state.value.copyWith(status: ReadAloudStatus.reading, clearError: true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _state.value = _state.value.copyWith(status: ReadAloudStatus.paused);
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    _state.value = _state.value.copyWith(status: ReadAloudStatus.reading);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _state.value = _state.value.copyWith(status: ReadAloudStatus.stopped);
  }

  @override
  Future<void> setRate(double rate) async {
    calls.add('rate $rate');
    _state.value = _state.value.copyWith(rate: rate);
  }
}

/// Speech that waits for the test: [say] speaks a word of the current text, [finish] ends it.
class FakeSpeechEngine implements SpeechEngine {
  /// Languages with a voice.
  Set<String> languages = {'en', 'es'};

  /// Everything handed to [speak], oldest first.
  final List<({String text, String language, double rate})> spoken = [];
  int stops = 0;
  bool disposed = false;

  /// When set, the next [speak] throws this.
  SpeechException? failNext;

  Completer<void>? _pending;
  void Function(int, int)? _onWord;

  bool get speaking => _pending != null && !_pending!.isCompleted;
  String get text => spoken.last.text;

  /// When set, [hasVoice] answers only once this completes (a browser loading its voices).
  Completer<void>? holdVoices;

  @override
  Future<bool> hasVoice(String language) async {
    await holdVoices?.future;
    return languages.contains(language);
  }

  @override
  Future<void> speak(String text,
      {required String language, required double rate, required void Function(int, int) onWord}) {
    spoken.add((text: text, language: language, rate: rate));
    if (failNext != null) {
      final e = failNext!;
      failNext = null;
      return Future.error(e);
    }
    _pending?.complete();
    _onWord = onWord;
    return (_pending = Completer<void>()).future;
  }

  /// The engine speaks the [index]th word (0-based, split on spaces and line breaks) of the current text.
  void say(int index) {
    var at = 0, i = 0;
    for (final m in RegExp(r'\S+').allMatches(text)) {
      if (i++ == index) {
        at = m.start;
        _onWord!(at, m.end);
        return;
      }
    }
    throw StateError('The text has no word $index');
  }

  /// The engine has read everything it was given.
  void finish() {
    final pending = _pending;
    _pending = null;
    pending?.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    finish();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    finish();
  }
}
