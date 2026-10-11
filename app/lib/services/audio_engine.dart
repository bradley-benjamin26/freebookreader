import 'package:just_audio/just_audio.dart';

/// Plays one audio file at a time.
abstract class AudioEngine {
  Future<void> play(Uri url, {Duration? from});
  Future<void> pause();
  Future<void> seek(Duration position);
  Stream<Duration> get positionStream;
  Future<void> dispose();
}

class JustAudioEngine implements AudioEngine {
  final AudioPlayer _player = AudioPlayer();
  Uri? _current;

  @override
  Future<void> play(Uri url, {Duration? from}) async {
    if (url != _current) {
      _current = url;
      await _player.setUrl(url.toString(), initialPosition: from);
    } else if (from != null) {
      await _player.seek(from);
    }
    // just_audio's play() completes when playback stops, so don't wait for it.
    _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Future<void> dispose() => _player.dispose();
}
