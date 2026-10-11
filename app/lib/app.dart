import 'package:flutter/material.dart';

import 'api/search_api.dart';
import 'reader/reader_engine.dart';
import 'reader/reader_settings.dart';
import 'services/audio_engine.dart';
import 'services/url_opener.dart';
import 'storage/bookmark_store.dart';
import 'ui/home_page.dart';

typedef PdfViewBuilder = Widget Function(BuildContext context, Uri url);

/// Everything outside the app, injected so tests can fake it.
class Services extends InheritedWidget {
  const Services({
    super.key,
    required this.api,
    required this.bookmarks,
    required this.settingsStore,
    required this.readerEngine,
    required this.urlOpener,
    required this.audio,
    required this.pdfViewBuilder,
    required super.child,
  });

  final SearchApi api;
  final BookmarkStore bookmarks;
  final ReaderSettingsStore settingsStore;
  final ReaderEngineFactory readerEngine;
  final UrlOpener urlOpener;
  final AudioEngine audio;
  final PdfViewBuilder pdfViewBuilder;

  static Services of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!;

  @override
  bool updateShouldNotify(Services oldWidget) => false;
}

class FreeBookReaderApp extends StatelessWidget {
  const FreeBookReaderApp({
    super.key,
    required this.api,
    required this.bookmarks,
    required this.settingsStore,
    required this.readerEngine,
    required this.urlOpener,
    required this.audio,
    required this.pdfViewBuilder,
    this.themeMode = ThemeMode.system,
  });

  final SearchApi api;
  final BookmarkStore bookmarks;
  final ReaderSettingsStore settingsStore;
  final ReaderEngineFactory readerEngine;
  final UrlOpener urlOpener;
  final AudioEngine audio;
  final PdfViewBuilder pdfViewBuilder;
  final ThemeMode themeMode;

  static const seed = Color(0xFF3B5BA9);

  static ThemeData theme(Brightness brightness) => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      );

  @override
  Widget build(BuildContext context) {
    return Services(
      api: api,
      bookmarks: bookmarks,
      settingsStore: settingsStore,
      readerEngine: readerEngine,
      urlOpener: urlOpener,
      audio: audio,
      pdfViewBuilder: pdfViewBuilder,
      child: MaterialApp(
        title: 'Free Book Reader',
        locale: const Locale('en'),
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        themeMode: themeMode,
        home: const HomePage(),
      ),
    );
  }
}
