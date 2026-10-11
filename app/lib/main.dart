import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api/search_api.dart';
import 'app.dart';
import 'reader/content.dart';
import 'reader/reader_settings.dart';
import 'services/audio_engine.dart';
import 'services/url_opener.dart';
import 'storage/bookmark_store.dart';
import 'ui/pdf_link_out.dart';

/// The backend's address, e.g. `flutter run --dart-define=BACKEND_URL=https://example.org`.
const backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8000');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final client = http.Client();
  runApp(FreeBookReaderApp(
    api: HttpSearchApi(client: client, baseUrl: Uri.parse(backendUrl)),
    bookmarks: BookmarkStore(prefs),
    settingsStore: ReaderSettingsStore(prefs),
    contentLoader: HttpContentLoader(client),
    urlOpener: const LauncherUrlOpener(),
    audio: JustAudioEngine(),
    // No PDF package yet (decision_reader.md): PDFs open outside the app.
    pdfViewBuilder: (context, url) => PdfLinkOut(url: url),
  ));
}
