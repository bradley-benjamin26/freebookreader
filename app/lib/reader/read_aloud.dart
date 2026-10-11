import 'package:flutter/foundation.dart';

enum ReadAloudStatus { stopped, reading, paused }

/// What read-aloud is doing. [error] is set when it could not start or broke off, for example when the device
/// has no voice for the book's language.
class ReadAloudState {
  const ReadAloudState({this.status = ReadAloudStatus.stopped, this.rate = 1.0, this.error});

  final ReadAloudStatus status;

  /// Speed, 1.0 is normal.
  final double rate;
  final String? error;

  ReadAloudState copyWith({ReadAloudStatus? status, double? rate, String? error, bool clearError = false}) =>
      ReadAloudState(
        status: status ?? this.status,
        rate: rate ?? this.rate,
        error: clearError ? null : error ?? this.error,
      );

  @override
  bool operator ==(Object other) =>
      other is ReadAloudState && other.status == status && other.rate == rate && other.error == error;

  @override
  int get hashCode => Object.hash(status, rate, error);
}

/// The speeds a reader can choose, slowest first.
const readAloudRates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Text-to-speech for the book an engine shows. The engine highlights what is being read and turns the pages.
abstract class ReadAloud {
  ValueListenable<ReadAloudState> get state;

  /// Reads from where the reader is, in [language] (an ISO 639-1 code; null when the book's is unknown, which
  /// reads in English).
  Future<void> start({String? language});
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();

  /// Changes the speed; reading in progress carries on at the new speed.
  Future<void> setRate(double rate);
}
