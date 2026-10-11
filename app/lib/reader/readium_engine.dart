import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../models/models.dart';
import '../services/speech_engine.dart';
import '../util/format.dart';
import 'read_aloud.dart';
import 'reader_engine.dart';
import 'reader_settings.dart';

/// flutter_readium (Readium's ts-toolkit on web). Opens a Readium manifest
/// served by our backend (`reading.publication`), since the web reader cannot
/// open an .epub and gutenberg.org sends no CORS headers.
///
/// Only used on web for now: Android and iOS need native setup first (see
/// decision_reader.md). Not covered by widget tests; the spike checklist in
/// decision_reader.md is its test script.
class ReadiumReaderEngine implements ReaderEngine {
  ReadiumReaderEngine(this.manifest, {FlutterReadium? readium}) : _readium = readium ?? FlutterReadium() {
    _readAloud = _ReadiumReadAloud(_readium);
  }

  final Uri manifest;
  final FlutterReadium _readium;
  final _positions = StreamController<ReaderPosition>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];

  late final _ReadiumReadAloud _readAloud;
  Publication? _publication;
  Locator? _initial;
  double? _pendingProgress;
  ReaderPosition _position = ReaderPosition.start;

  @override
  Future<void> open(ReadingOptions book, {required ReaderSettings settings, ReaderPosition? at}) async {
    if (_subscriptions.isEmpty) {
      _subscriptions
        ..add(_readium.onTextLocatorChanged.listen(_onLocator))
        ..add(_readium.onReaderStatusChanged.listen(_onStatus));
    }
    // On web these become the view's initial preferences when it mounts.
    await apply(settings);
    try {
      _publication = await _readium.openPublication(manifest.toString());
    } on ReadiumException catch (e) {
      throw ReaderOpenException(e.message);
    }
    final locator = at?.locator == null ? null : Locator.fromJsonString(at!.locator!);
    _initial = locator;
    _pendingProgress = locator == null && at != null && at.progress > 0 ? at.progress : null;
  }

  void _onLocator(Locator locator) {
    final pending = _pendingProgress;
    if (pending != null) {
      // A bookmark saved without a locator: go there once the book is showing.
      _pendingProgress = null;
      _readium.goToProgression(pending);
      return;
    }
    final progress = locator.locations?.totalProgression ?? _position.progress;
    _emit(ReaderPosition(
      progress: progress,
      locator: jsonEncode(locator.toJson()),
      // Readium's position numbers fall back to one per chapter when the
      // manifest has no position list, so they are not shown as pages.
      atStart: progress <= 0,
      atEnd: progress >= 1,
    ));
  }

  void _onStatus(ReadiumReaderStatus status) {
    if (status != ReadiumReaderStatus.reachedEndOfPublication) return;
    final p = _position;
    _emit(ReaderPosition(progress: p.progress, locator: p.locator, atStart: p.atStart, atEnd: true));
  }

  void _emit(ReaderPosition position) {
    _position = position;
    if (!_positions.isClosed) _positions.add(position);
  }

  @override
  ReaderPosition get position => _position;

  @override
  Stream<ReaderPosition> get positions => _positions.stream;

  @override
  ReadAloud get readAloud => _readAloud;

  @override
  Future<void> next() => _readium.goForward();

  @override
  Future<void> previous() => _readium.goBackward();

  @override
  Future<void> goTo(ReaderPosition position) async {
    final locator = position.locator == null ? null : Locator.fromJsonString(position.locator!);
    if (locator != null) {
      await _readium.goToLocator(locator);
    } else {
      await _readium.goToProgression(position.progress);
    }
  }

  @override
  Future<void> apply(ReaderSettings settings) => _readium.setEPUBPreferences(epubPreferences(settings));

  @override
  Widget buildView(BuildContext context) => ReadiumReaderWidget(
        publication: _publication!,
        initialLocator: _initial,
        loadingWidget: const Center(child: CircularProgressIndicator(semanticsLabel: 'Loading book')),
        goBackwardSemanticLabel: 'Previous page',
        goForwardSemanticLabel: 'Next page',
      );

  @override
  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _readAloud.dispose();
    if (_publication != null) await _readium.closePublication();
    await _positions.close();
  }
}

/// Our settings as Readium preferences.
EPUBPreferences epubPreferences(ReaderSettings settings) => EPUBPreferences(
      // A ratio of the book's own size; our default size (18) is 100%.
      fontSize: settings.fontSize / const ReaderSettings().fontSize,
      fontFamily: cssFontStack(settings.fontFamily),
      lineHeight: settings.lineHeight,
      // Readium takes these in rem. Ours are in em, which is close enough for
      // body text. Readium puts paragraph spacing above and below each
      // paragraph, so half of it makes our gap.
      letterSpacing: settings.letterSpacing,
      paragraphSpacing: settings.paragraphSpacing / 2,
      backgroundColor: settings.backgroundColor,
      textColor: settings.textColor,
      scroll: settings.viewMode == ViewMode.scroll,
      // Otherwise the book's own CSS overrides spacing and line height.
      publisherStyles: false,
    );

const _genericFamilies = {'serif', 'sans-serif', 'monospace'};

/// A CSS font-family list for [font]: named fonts first, then a generic one.
String cssFontStack(ReaderFont font) {
  final generic = _genericFamilies.contains(font.family) ? font.family : 'sans-serif';
  final names = [if (!_genericFamilies.contains(font.family)) font.family, ...font.fallback];
  return [for (final n in names) '"$n"', generic].join(', ');
}

/// Readium's text-to-speech. It reads, highlights and turns the pages itself; this picks a voice that is on the
/// device for the book's language (the browser's default voice stalled in Chrome, see decision_reader.md) and
/// keeps [state] in step with what Readium reports. Not covered by widget tests.
class _ReadiumReadAloud implements ReadAloud {
  _ReadiumReadAloud(this._readium);

  final FlutterReadium _readium;
  @override
  final ValueNotifier<ReadAloudState> state = ValueNotifier(const ReadAloudState());
  StreamSubscription<ReadiumTimebasedState>? _subscription;
  String? _voice;

  ReadAloudState get _now => state.value;

  void _onState(ReadiumTimebasedState update) {
    switch (update.state) {
      case TimebasedState.playing || TimebasedState.loading:
        state.value = _now.copyWith(status: ReadAloudStatus.reading, clearError: true);
      case TimebasedState.paused:
        state.value = _now.copyWith(status: ReadAloudStatus.paused);
      case TimebasedState.ended:
        state.value = _now.copyWith(status: ReadAloudStatus.stopped);
      case TimebasedState.failure:
        state.value =
            _now.copyWith(status: ReadAloudStatus.stopped, error: 'Reading aloud stopped. Try again.');
      case TimebasedState.none:
        break; // also what Readium says before the first word
    }
  }

  @override
  Future<void> start({String? language}) async {
    final code = language ?? 'en';
    try {
      final voices = await _readium.ttsGetAvailableVoices();
      final matching = [
        for (final v in voices)
          if (matchVoiceLanguage(code, [v.language]) != null) v,
      ];
      if (matching.isEmpty) {
        state.value = _now.copyWith(
            status: ReadAloudStatus.stopped, error: 'This device has no voice for ${languageName(code)}.');
        return;
      }
      final voice = matching.firstWhere((v) => !v.networkRequired, orElse: () => matching.first);
      _voice = voice.identifier;
      _subscription ??= _readium.onTimebasedPlayerStateChanged.listen(_onState);
      await _readium.ttsEnable(TTSPreferences(speed: _now.rate, voiceIdentifier: _voice));
      await _readium.ttsSetVoice(voice.identifier, code);
      state.value = _now.copyWith(status: ReadAloudStatus.reading, clearError: true);
      await _readium.play(null);
    } on ReadiumException catch (e) {
      state.value = _now.copyWith(status: ReadAloudStatus.stopped, error: 'Reading aloud stopped: ${e.message}');
    }
  }

  @override
  Future<void> pause() => _readium.pause();

  @override
  Future<void> resume() => _readium.resume();

  @override
  Future<void> stop() async {
    state.value = _now.copyWith(status: ReadAloudStatus.stopped, clearError: true);
    try {
      await _readium.stop();
    } on ReadiumException {
      // Nothing was playing.
    }
  }

  @override
  Future<void> setRate(double rate) async {
    state.value = _now.copyWith(rate: rate);
    if (_now.status == ReadAloudStatus.stopped) return;
    await _readium.ttsSetPreferences(TTSPreferences(speed: rate, voiceIdentifier: _voice));
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    if (_now.status != ReadAloudStatus.stopped) await stop();
  }
}
