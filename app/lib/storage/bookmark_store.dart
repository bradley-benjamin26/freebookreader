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

/// Bookmarks are kept on the device only (no accounts yet).
class BookmarkStore {
  BookmarkStore(this._prefs);

  final SharedPreferences _prefs;
  static const _prefix = 'bookmark:';

  Bookmark? load(String bookKey) {
    final raw = _prefs.getString('$_prefix$bookKey');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return Bookmark(
          progress: (json['progress'] as num).toDouble(), locator: json['locator'] as String?);
    } on Object {
      return null;
    }
  }

  Future<void> save(String bookKey, Bookmark bookmark) =>
      _prefs.setString('$_prefix$bookKey', jsonEncode({
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
