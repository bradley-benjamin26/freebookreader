import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A place in a book, as a fraction of the way through it, so it survives a
/// change of font size or view mode, plus the reader engine's own [locator]
/// for the exact place (null when the engine gave none).
class Bookmark {
  const Bookmark({required double progress, this.locator}) : _progress = progress;

  final double _progress;
  final String? locator;

  double get progress => _progress.clamp(0.0, 1.0);
}

/// Bookmarks, and the last place read in each book, are kept on the device only (no accounts yet).
class BookmarkStore {
  BookmarkStore(this._prefs);

  final SharedPreferences _prefs;
  static const _prefix = 'bookmark:';
  static const _lastPlacePrefix = 'lastplace:';

  Bookmark? load(String bookKey) => _load('$_prefix$bookKey');

  Future<void> save(String bookKey, Bookmark bookmark) => _save('$_prefix$bookKey', bookmark);

  /// Where the reader last was in the book, saved as they read; apart from the bookmark.
  Bookmark? loadLastPlace(String bookKey) => _load('$_lastPlacePrefix$bookKey');

  Future<void> saveLastPlace(String bookKey, Bookmark place) => _save('$_lastPlacePrefix$bookKey', place);

  Bookmark? _load(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return Bookmark(
          progress: (json['progress'] as num).toDouble(), locator: json['locator'] as String?);
    } on Object {
      return null;
    }
  }

  Future<void> _save(String key, Bookmark bookmark) =>
      _prefs.setString(key, jsonEncode({
        'progress': bookmark.progress,
        if (bookmark.locator != null) 'locator': bookmark.locator,
      }));

  Future<void> remove(String bookKey) => _prefs.remove('$_prefix$bookKey');

  List<String> savedBookKeys() => _prefs
      .getKeys()
      .where((k) => k.startsWith(_prefix))
      .map((k) => k.substring(_prefix.length))
      .toList();
}
