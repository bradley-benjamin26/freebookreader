import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speech could not start: there is no voice for the language, or the device's speech service failed.
class SpeechException implements Exception {
  const SpeechException(this.message);

  final String message;

  @override
  String toString() => 'SpeechException: $message';
}

/// Reads text aloud, one piece at a time, with the device's own voices.
abstract class SpeechEngine {
  /// Whether the device has a voice for [language] (an ISO 639-1 code such as "en").
  Future<bool> hasVoice(String language);

  /// Reads [text] in [language] at [rate] (1.0 is normal speed) and completes when it has been read, or when
  /// [stop] was called. [onWord] gets the start and end offsets of each word in [text] as it is spoken.
  /// Throws [SpeechException] when it cannot speak.
  Future<void> speak(
    String text, {
    required String language,
    required double rate,
    required void Function(int start, int end) onWord,
  });

  /// Stops speaking. Completes the pending [speak].
  Future<void> stop();

  Future<void> dispose();
}

/// The first of [available] (like "en-US" or "fr_FR") that is [language], or starts with it. Null if none.
String? matchVoiceLanguage(String language, Iterable<String> available) {
  final wanted = language.toLowerCase();
  for (final tag in available) {
    final normal = tag.toLowerCase().replaceAll('_', '-');
    if (normal == wanted || normal.startsWith('$wanted-')) return tag;
  }
  return null;
}

/// flutter_tts's rate for [rate], our speed (1.0 is normal): phones take 0 to 1 with 0.5 as normal, and the
/// browser takes the speed itself.
double ttsRate(double rate, {required bool web}) => web ? rate : (rate * 0.5).clamp(0.0, 1.0);

/// The device's speech service (Android TextToSpeech, iOS AVSpeechSynthesizer, the browser's
/// speechSynthesis) through flutter_tts.
class FlutterSpeechEngine implements SpeechEngine {
  FlutterSpeechEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  void Function(int start, int end)? _onWord;
  String? _error;
  bool _ready = false;

  Future<void> _setUp() async {
    if (_ready) return;
    _ready = true;
    // `speak` then completes when the speech has ended or has been stopped.
    await _tts.awaitSpeakCompletion(true);
    _tts.setErrorHandler((message) => _error = '$message');
    _tts.setProgressHandler((text, start, end, word) => _onWord?.call(start, end));
  }

  Future<List<String>> _languages() async {
    final languages = await _tts.getLanguages;
    return [for (final l in languages as List<dynamic>) '$l'];
  }

  @override
  Future<bool> hasVoice(String language) async {
    try {
      return matchVoiceLanguage(language, await _languages()) != null;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> speak(
    String text, {
    required String language,
    required double rate,
    required void Function(int start, int end) onWord,
  }) async {
    try {
      await _setUp();
      final tag = matchVoiceLanguage(language, await _languages());
      if (tag == null) throw SpeechException('No voice for $language');
      _error = null;
      _onWord = onWord;
      await _tts.setLanguage(tag);
      await _tts.setSpeechRate(ttsRate(rate, web: kIsWeb));
      await _tts.speak(text);
    } on SpeechException {
      rethrow;
    } on Object catch (e) {
      throw SpeechException('$e');
    }
    final error = _error;
    if (error != null) throw SpeechException(error);
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // Nothing was speaking.
    }
  }

  @override
  Future<void> dispose() => stop();
}
