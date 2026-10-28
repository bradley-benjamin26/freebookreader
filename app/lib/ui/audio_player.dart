import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/audio_engine.dart';
import '../util/format.dart';
import 'common.dart';

/// Playback state for one recording, chapter by chapter.
class AudioController extends ChangeNotifier {
  AudioController(this._engine, this.book) {
    _positionSub = _engine.positionStream.listen((p) {
      // The engine is shared: ignore the position of any other file (the last one played, for one).
      if (p.url != _url) return;
      position = p.position;
      notifyListeners();
    });
    _statusSub = _engine.statusStream.listen(_onStatus);
  }

  static const skip = Duration(seconds: 30);

  final AudioEngine _engine;
  final Book book;
  late final StreamSubscription<AudioPosition> _positionSub;
  late final StreamSubscription<AudioStatus> _statusSub;

  int chapter = 0;
  bool playing = false;
  Duration position = Duration.zero;

  /// What went wrong when the recording could not be played; null otherwise.
  String? error;

  bool _disposed = false;

  // The last chapter played to the end: Play starts it again from the beginning.
  bool _finished = false;

  List<Chapter> get chapters => book.chapters;

  Uri get _url => Uri.parse(chapters.isEmpty ? book.reading.url : chapters[chapter].url);

  Duration? get chapterLength {
    final seconds = chapters.isEmpty ? book.audioSeconds : chapters[chapter].durationSeconds;
    return seconds == null ? null : Duration(seconds: seconds);
  }

  void _onStatus(AudioStatus status) {
    if (status.url != _url) return; // another recording's
    if (status.completed) {
      if (chapter + 1 < chapters.length) {
        unawaited(playChapter(chapter + 1));
        return;
      }
      playing = false;
      position = Duration.zero;
      _finished = true;
    } else {
      playing = status.playing;
    }
    notifyListeners();
  }

  Future<void> _start(Uri url, {Duration? from}) async {
    error = null;
    playing = true;
    _finished = false;
    notifyListeners();
    try {
      await _engine.play(url, from: from);
    } on Object {
      if (_disposed) return;
      playing = false;
      error = 'The recording could not be played. Check your connection and try again.';
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    if (playing) {
      playing = false;
      notifyListeners();
      await _engine.pause();
    } else {
      await _start(_url, from: _finished ? Duration.zero : (position == Duration.zero ? null : position));
    }
  }

  Future<void> playChapter(int index) async {
    chapter = index;
    position = Duration.zero;
    await _start(_url, from: Duration.zero); // from the beginning, even if it is the chapter already loaded
  }

  Future<void> seek(Duration to) async {
    final length = chapterLength;
    var target = to < Duration.zero ? Duration.zero : to;
    if (length != null && target > length) target = length;
    position = target;
    notifyListeners();
    await _engine.seek(target);
  }

  Future<void> skipForward() => seek(position + skip);
  Future<void> skipBack() => seek(position - skip);

  /// Stops playback when the page closes; the engine itself is shared.
  @override
  void dispose() {
    _disposed = true;
    _positionSub.cancel();
    _statusSub.cancel();
    if (playing) _engine.pause();
    super.dispose();
  }
}

/// Play/pause and 30-second skips. [compact] leaves out the position slider,
/// for the player under the reader.
class AudioPlayerPanel extends StatelessWidget {
  const AudioPlayerPanel({super.key, required this.controller, this.compact = false});

  final AudioController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final buttons = [
          IconButton(
            key: const Key('skip-back'),
            onPressed: controller.skipBack,
            icon: const Icon(Icons.replay_30, semanticLabel: 'Skip back 30 seconds'),
          ),
          IconButton.filled(
            key: const Key('play-pause'),
            iconSize: 32,
            onPressed: controller.togglePlay,
            icon: Icon(controller.playing ? Icons.pause : Icons.play_arrow,
                semanticLabel: controller.playing ? 'Pause' : 'Play'),
          ),
          IconButton(
            key: const Key('skip-forward'),
            onPressed: controller.skipForward,
            icon: const Icon(Icons.forward_30, semanticLabel: 'Skip forward 30 seconds'),
          ),
        ];
        final error = controller.error == null
            ? null
            : Row(
                children: [
                  Expanded(
                    child: LiveRegion(
                      key: const Key('audio-error'),
                      child: Text(controller.error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  ),
                  TextButton(
                    key: const Key('audio-retry'),
                    onPressed: controller.togglePlay,
                    child: const Text('Try again'),
                  ),
                ],
              );
        if (compact) {
          final chapters = controller.chapters;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chapters.isEmpty
                          ? 'LibriVox recording'
                          : 'LibriVox: ${chapters[controller.chapter].title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ...buttons,
                ],
              ),
              ?error,
            ],
          );
        }
        final length = controller.chapterLength;
        if (length == null) {
          // Not a live region: it changes every second.
          return Column(
            children: [
              Text('${formatDuration(controller.position.inSeconds) ?? '0 sec'} played · length unknown',
                  key: const Key('position-elapsed')),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: buttons),
              ?error,
            ],
          );
        }
        final max = length.inSeconds <= 0 ? 1.0 : length.inSeconds.toDouble();
        final value = controller.position.inSeconds.clamp(0, max).toDouble();
        return Column(
          children: [
            MergeSemantics(
              key: const Key('position-slider'),
              child: Semantics(
                label: 'Playback position',
                child: Slider(
                  value: value,
                  max: max,
                  semanticFormatterCallback: (v) =>
                      '${formatDuration(v.round()) ?? '0 sec'} of ${formatDuration(max.round()) ?? 'unknown'}',
                  onChanged: (v) => controller.seek(Duration(seconds: v.round())),
                ),
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: buttons),
            ?error,
          ],
        );
      },
    );
  }
}
