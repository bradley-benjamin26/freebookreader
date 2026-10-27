// The just_audio adapter. Review 2026-10-11-main, #16: a pause while a file is
// still loading must cancel the play that was waiting for it.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/services/audio_engine.dart';
import 'package:just_audio/just_audio.dart';

/// An AudioPlayer whose loads wait until [finishLoad], and which records play/pause.
class HeldPlayer extends AudioPlayer {
  final List<String> calls = [];
  Completer<Duration?>? _load;

  void finishLoad() => _load!.complete(const Duration(minutes: 3));

  @override
  Future<Duration?> setUrl(String url,
      {Map<String, String>? headers, Duration? initialPosition, bool preload = true, dynamic tag}) {
    calls.add('load');
    _load = Completer();
    return _load!.future;
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final url = Uri.parse('https://archive.org/download/p/01.mp3');

  test('plays once the file has loaded', () async {
    final player = HeldPlayer();
    final engine = JustAudioEngine(player: player);
    final playing = engine.play(url);
    player.finishLoad();
    await playing;
    expect(player.calls, ['load', 'play']);
  });

  test('a pause while the file loads means it does not start', () async {
    final player = HeldPlayer();
    final engine = JustAudioEngine(player: player);
    final playing = engine.play(url);
    await engine.pause();
    player.finishLoad();
    await playing;
    expect(player.calls, ['load', 'pause']);
  });

  test('closing the engine while the file loads means it does not start', () async {
    final player = HeldPlayer();
    final engine = JustAudioEngine(player: player);
    final playing = engine.play(url);
    await engine.dispose();
    player.finishLoad();
    await playing;
    expect(player.calls, isNot(contains('play')));
  });
}
