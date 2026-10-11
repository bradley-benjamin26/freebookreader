import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/audio_engine.dart';
import '../util/format.dart';

/// Playback state for one recording, chapter by chapter.
class AudioController extends ChangeNotifier {
  AudioController(this._engine, this.book) {
    _positionSub = _engine.positionStream.listen((p) {
      position = p;
      notifyListeners();
    });
  }

  static const skip = Duration(seconds: 30);

  final AudioEngine _engine;
  final Book book;
  late final StreamSubscription<Duration> _positionSub;

  int chapter = 0;
  bool playing = false;
  Duration position = Duration.zero;

  List<Chapter> get chapters => book.chapters;

  Uri get _url => Uri.parse(chapters.isEmpty ? book.reading.url : chapters[chapter].url);

  Duration? get chapterLength {
    final seconds = chapters.isEmpty ? book.audioSeconds : chapters[chapter].durationSeconds;
    return seconds == null ? null : Duration(seconds: seconds);
  }

  Future<void> togglePlay() async {
    if (playing) {
      playing = false;
      notifyListeners();
      await _engine.pause();
    } else {
      playing = true;
      notifyListeners();
      await _engine.play(_url, from: position == Duration.zero ? null : position);
    }
  }

  Future<void> playChapter(int index) async {
    chapter = index;
    position = Duration.zero;
    playing = true;
    notifyListeners();
    await _engine.play(_url);
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
    _positionSub.cancel();
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
        if (compact) {
          final chapters = controller.chapters;
          return Row(
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
          );
        }
        final length = controller.chapterLength ?? controller.position;
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
          ],
        );
      },
    );
  }
}
