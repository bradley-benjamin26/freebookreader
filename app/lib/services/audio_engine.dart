import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Playback could not start: the file is missing, the network is down, or the format is not supported.
class AudioException implements Exception {
  const AudioException(this.message);

  final String message;

  @override
  String toString() => 'AudioException: $message';
}

/// Where the player is in [url]. The engine is shared by every recording in the app, so a position says
/// which file it belongs to.
class AudioPosition {
  const AudioPosition(this.url, this.position);

  final Uri? url;
  final Duration position;
}

/// Whether [url] is playing, and whether it has played to the end.
class AudioStatus {
  const AudioStatus({required this.url, required this.playing, this.completed = false});

  final Uri? url;
  final bool playing;
  final bool completed;
}

/// Plays one audio file at a time.
abstract class AudioEngine {
  /// Starts [url] ([from] when given). Completes once playback has started; throws [AudioException] when it
  /// cannot.
  Future<void> play(Uri url, {Duration? from});
  Future<void> pause();
  Future<void> seek(Duration position);
  Stream<AudioPosition> get positionStream;
  Stream<AudioStatus> get statusStream;
  Future<void> dispose();
}

class JustAudioEngine implements AudioEngine {
  JustAudioEngine({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  Uri? _current;

  // A pause (or a newer play) while a file loads cancels the play that was waiting for it.
  int _request = 0;

  @override
  Future<void> play(Uri url, {Duration? from}) async {
    final request = ++_request;
    try {
      if (url != _current) {
        _current = url;
        await _player.setUrl(url.toString(), initialPosition: from);
      } else if (from != null) {
        await _player.seek(from);
      }
    } on Object catch (e) {
      _current = null; // load again next time
      if (request != _request) return;
      throw AudioException('$e');
    }
    if (request != _request) return;
    // just_audio's play() completes when playback stops, so don't wait for it.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() {
    _request++;
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Stream<AudioPosition> get positionStream =>
      _player.positionStream.map((position) => AudioPosition(_current, position));

  @override
  Stream<AudioStatus> get statusStream => _player.playerStateStream.map((state) {
        final completed = state.processingState == ProcessingState.completed;
        // just_audio keeps `playing` true at the end of a file.
        return AudioStatus(url: _current, playing: state.playing && !completed, completed: completed);
      });

  @override
  Future<void> dispose() {
    _request++;
    return _player.dispose();
  }
}
