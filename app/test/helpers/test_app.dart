import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/app.dart';
import 'package:free_book_reader/models/models.dart';
import 'package:free_book_reader/reader/text_engine.dart';
import 'package:free_book_reader/reader/reader_settings.dart';
import 'package:free_book_reader/storage/bookmark_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'fixtures.dart';

/// Everything the app depends on, replaced by fakes.
class TestEnv {
  TestEnv._({
    required this.api,
    required this.prefs,
    required this.bookmarks,
    required this.settingsStore,
    required this.loader,
    required this.engines,
    required this.textEngine,
    required this.urls,
    required this.audio,
    required this.speech,
    required this.withSpeech,
  });

  final FakeSearchApi api;
  final SharedPreferences prefs;
  final BookmarkStore bookmarks;
  final ReaderSettingsStore settingsStore;
  final FakeContentLoader loader;
  final FakeReaderEngines engines;

  /// Whether books open in our own renderer ([TextReaderEngine], fed by
  /// [loader]) instead of a [FakeReaderEngine].
  final bool textEngine;
  final FakeUrlOpener urls;
  final FakeAudioEngine audio;

  /// The speech service of [textEngine]'s renderer, unless [withSpeech] is false.
  final FakeSpeechEngine speech;
  final bool withSpeech;

  static Future<TestEnv> create({
    SearchResponse? response,
    Map<String, Object> prefsValues = const {},
    bool textEngine = false,
    bool speech = true,
  }) async {
    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    return TestEnv._(
      api: FakeSearchApi(
        response: response ?? SearchResponse.fromJson(loadJson('search_response.json')),
        sourceInfos: (loadJson('sources.json') as List)
            .map((j) => SourceInfo.fromJson(j as Map<String, dynamic>))
            .toList(),
      ),
      prefs: prefs,
      bookmarks: BookmarkStore(prefs),
      settingsStore: ReaderSettingsStore(prefs),
      loader: FakeContentLoader(),
      engines: FakeReaderEngines(),
      textEngine: textEngine,
      urls: FakeUrlOpener(),
      audio: FakeAudioEngine(),
      speech: FakeSpeechEngine(),
      withSpeech: speech,
    );
  }

  Work get pride => api.response.works.firstWhere((w) => w.id == 'w-pride');
  Work get quijote => api.response.works.firstWhere((w) => w.id == 'w-quijote');
  Work get kinder => api.response.works.firstWhere((w) => w.id == 'w-kinder');
}

const phone = Size(400, 800);
const desktop = Size(1100, 800);
const smallPhone = Size(320, 640);

/// Pumps the whole app. [size] is in logical pixels.
Future<void> pumpApp(
  WidgetTester tester,
  TestEnv env, {
  Size size = phone,
  double textScale = 1.0,
  ThemeMode themeMode = ThemeMode.light,
  Widget Function(BuildContext, Uri)? pdfViewBuilder,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(FreeBookReaderApp(
    api: env.api,
    bookmarks: env.bookmarks,
    settingsStore: env.settingsStore,
    readerEngine: env.textEngine
        ? (_) => TextReaderEngine(env.loader, speech: env.withSpeech ? env.speech : null)
        : env.engines.call,
    urlOpener: env.urls,
    audio: env.audio,
    themeMode: themeMode,
    pdfViewBuilder: pdfViewBuilder ??
        (context, url) => Container(key: const Key('pdf-viewer'), child: Text('PDF $url')),
  ));
  await tester.pumpAndSettle();
}

/// Types into the search box and submits from the home or results page.
Future<void> searchFor(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('search-field')), text);
  await tester.tap(find.byKey(const Key('search-submit')));
  await tester.pumpAndSettle();
}

/// Picks what the search box searches in: anything, title, author, subject or isbn.
Future<void> chooseSearchField(WidgetTester tester, String field) async {
  await tester.tap(find.byKey(Key('search-in-$field')));
  await tester.pumpAndSettle();
}

/// Runs a search then opens a work's details page.
Future<void> openDetails(WidgetTester tester, String workId) async {
  await searchFor(tester, 'pride');
  await tester.ensureVisible(find.byKey(Key('result-$workId')));
  await tester.tap(find.byKey(Key('result-$workId')));
  await tester.pumpAndSettle();
}

/// Opens the reader for a book from the details page.
Future<void> openBook(WidgetTester tester, TestEnv env, String workId, String bookKey) async {
  await openDetails(tester, workId);
  final button = find.byKey(Key('open-$bookKey'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

int pageNumber(WidgetTester tester) {
  final text = tester.widget<Text>(find.byKey(const Key('page-indicator'))).data!;
  return int.parse(RegExp(r'Page (\d+) of').firstMatch(text)!.group(1)!);
}

int pageCount(WidgetTester tester) {
  final text = tester.widget<Text>(find.byKey(const Key('page-indicator'))).data!;
  return int.parse(RegExp(r'of (\d+)').firstMatch(text)!.group(1)!);
}

Future<void> nextPage(WidgetTester tester, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(const Key('next-page')));
    await tester.pumpAndSettle();
  }
}

/// The semantics node of a slider by its accessible name, for driving it the
/// way a screen reader's "increase value" gesture does.
FinderBase<SemanticsNode> sliderNamed(String label) => find.semantics.byPredicate((node) {
      final data = node.getSemanticsData();
      return data.label == label && data.hasAction(SemanticsAction.increase);
    });
