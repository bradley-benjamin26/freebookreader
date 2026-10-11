import 'dart:async';

import 'package:free_book_reader/api/search_api.dart';
import 'package:free_book_reader/models/models.dart';
import 'package:free_book_reader/reader/content.dart';
import 'package:free_book_reader/services/audio_engine.dart';
import 'package:free_book_reader/services/url_opener.dart';

class FakeSearchApi implements SearchApi {
  FakeSearchApi({
    required this.response,
    this.sourceInfos = const [],
    this.error,
  });

  SearchResponse response;
  List<SourceInfo> sourceInfos;
  Object? error;
  Completer<SearchResponse>? hold;
  final List<SearchQuery> queries = [];

  @override
  Future<SearchResponse> search(SearchQuery query) {
    queries.add(query);
    if (hold != null) return hold!.future;
    if (error != null) return Future.error(error!);
    return Future.value(response);
  }

  @override
  Future<List<SourceInfo>> sources() async => sourceInfos;
}

class FakeUrlOpener implements UrlOpener {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }
}

class FakeContentLoader implements ContentLoader {
  FakeContentLoader({this.content, this.never = false});

  BookContent? content;

  /// When true, loading never finishes (to test the one-minute limit).
  bool never;

  /// When true, the next load fails once with a [ContentLoadException].
  bool failNext = false;
  final List<ReadingOptions> requests = [];

  @override
  Future<BookContent> load(ReadingOptions options) {
    requests.add(options);
    if (never) return Completer<BookContent>().future;
    if (failNext) {
      failNext = false;
      return Future.error(const ContentLoadException('could not load'));
    }
    return Future.value(content ?? longText());
  }
}

/// Enough paragraphs to fill several pages on a phone.
TextContent longText({int paragraphs = 60}) => TextContent(List.generate(
      paragraphs,
      (i) => 'Paragraph $i. ${'It is a truth universally acknowledged, that a single man '
          'in possession of a good fortune, must be in want of a wife. ' * 3}',
    ));

class FakeAudioEngine implements AudioEngine {
  final List<String> calls = [];
  final StreamController<Duration> _position = StreamController<Duration>.broadcast();
  bool playing = false;

  @override
  Future<void> play(Uri url, {Duration? from}) async {
    calls.add('play ${url.toString()}');
    playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> seek(Duration position) async => calls.add('seek ${position.inSeconds}');

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Future<void> dispose() async => _position.close();
}
