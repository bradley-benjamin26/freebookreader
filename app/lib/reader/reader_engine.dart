import 'package:flutter/widgets.dart';

import '../models/models.dart';
import 'read_aloud.dart';
import 'reader_settings.dart';

/// A place in a book.
///
/// [progress] (0 to 1) survives any change of font, size or view, and works
/// with every engine. [locator] is the engine's own exact place (a Readium
/// locator as JSON, for example); only the engine that made it understands it.
class ReaderPosition {
  const ReaderPosition({
    required double progress,
    this.locator,
    this.page,
    this.pageCount,
    this.atStart = false,
    this.atEnd = false,
  }) : _progress = progress;

  static const start = ReaderPosition(progress: 0, atStart: true);

  final double _progress;
  final String? locator;

  /// 1-based page number and page count, when the engine knows them.
  final int? page;
  final int? pageCount;

  /// Whether there is no page before or after this one.
  final bool atStart;
  final bool atEnd;

  double get progress => _progress.clamp(0.0, 1.0);
}

/// Thrown by [ReaderEngine.open] when the book cannot be shown.
class ReaderOpenException implements Exception {
  const ReaderOpenException(this.message);

  final String message;

  @override
  String toString() => 'ReaderOpenException: $message';
}

/// Shows a book's text. The reader page talks only to this, so the package
/// behind it can change (see decision_reader.md). One engine reads one book.
abstract class ReaderEngine {
  /// Loads [book] with [settings], at [at] (the start when null). Completes
  /// when the first page can be shown; throws [ReaderOpenException] (or
  /// another error) when it cannot. May be called again after a failure.
  Future<void> open(ReadingOptions book, {required ReaderSettings settings, ReaderPosition? at});

  /// Where the reader is now.
  ReaderPosition get position;

  /// Emits [position] whenever it changes.
  Stream<ReaderPosition> get positions;

  /// The next or previous page (in scroll view, the next or previous screen).
  Future<void> next();
  Future<void> previous();

  Future<void> goTo(ReaderPosition position);

  /// Display settings: theme, font, size, spacing, page-turner or scroll.
  Future<void> apply(ReaderSettings settings);

  /// Text-to-speech for this engine's book, or null when it cannot read aloud.
  ReadAloud? get readAloud;

  /// The book itself, once [open] has completed.
  Widget buildView(BuildContext context);

  Future<void> dispose();
}

/// The engine for a book, or null when no engine can show it.
typedef ReaderEngineFactory = ReaderEngine? Function(ReadingOptions book);
