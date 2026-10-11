import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/api/search_api.dart';
import 'package:free_book_reader/models/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers/fixtures.dart';

HttpSearchApi apiWith(MockClient client) =>
    HttpSearchApi(client: client, baseUrl: Uri.parse('http://backend.test'));

void main() {
  group('search', () {
    test('GETs /search with the query parameters', () async {
      late http.Request seen;
      final api = apiWith(MockClient((request) async {
        seen = request;
        return http.Response(loadFixtureText('search_response.json'), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }));
      final response = await api.search(
          SearchQuery(title: 'Pride and Prejudice', author: 'Austen', sources: ['gutenberg']));
      expect(seen.method, 'GET');
      expect(seen.url.path, '/search');
      expect(seen.url.queryParameters['title'], 'Pride and Prejudice');
      expect(seen.url.queryParameters['author'], 'Austen');
      expect(seen.url.queryParameters['sources'], 'gutenberg');
      expect(response.works, hasLength(3));
    });

    test('decodes UTF-8 titles correctly', () async {
      final api = apiWith(MockClient((_) async => http.Response.bytes(
          utf8.encode(loadFixtureText('search_response.json')), 200,
          headers: {'content-type': 'application/json; charset=utf-8'})));
      final response = await api.search(SearchQuery(q: 'kinder'));
      expect(response.works.last.title, 'Kinder in Jugendverbänden');
    });

    test('keeps a base URL path prefix', () async {
      late Uri seen;
      final api = HttpSearchApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response('{"works": [], "unavailable_sources": []}', 200);
        }),
        baseUrl: Uri.parse('http://backend.test/api/v1'),
      );
      await api.search(SearchQuery(q: 'x'));
      expect(seen.path, '/api/v1/search');
    });

    test('an empty result is not an error', () async {
      final api = apiWith(MockClient((_) async =>
          http.Response('{"works": [], "unavailable_sources": ["doab"]}', 200)));
      final response = await api.search(SearchQuery(q: 'zzzz'));
      expect(response.works, isEmpty);
      expect(response.unavailableSources, ['doab']);
    });

    test('refuses to send a blank query', () async {
      var called = false;
      final api = apiWith(MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }));
      await expectLater(api.search(SearchQuery()), throwsA(isA<SearchException>()));
      expect(called, isFalse);
    });

    test('a 422 becomes a SearchException', () async {
      final api = apiWith(MockClient((_) async => http.Response('{"detail": []}', 422)));
      await expectLater(api.search(SearchQuery(q: 'x')), throwsA(isA<SearchException>()));
    });

    test('the exception carries the status, so a 4xx can be told from a failing server', () async {
      final api = apiWith(MockClient((_) async => http.Response('{"detail": []}', 422)));
      await expectLater(api.search(SearchQuery(q: 'x')),
          throwsA(isA<SearchException>().having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.isRejected, 'isRejected', isTrue)));
      final failing = apiWith(MockClient((_) async => http.Response('oops', 500)));
      await expectLater(failing.search(SearchQuery(q: 'x')),
          throwsA(isA<SearchException>().having((e) => e.isRejected, 'isRejected', isFalse)));
    });

    test('a 500 becomes a SearchException', () async {
      final api = apiWith(MockClient((_) async => http.Response('oops', 500)));
      await expectLater(api.search(SearchQuery(q: 'x')),
          throwsA(isA<SearchException>().having((e) => e.isTimeout, 'isTimeout', isFalse)));
    });

    test('a network failure becomes a SearchException', () async {
      final api = apiWith(MockClient((_) async => throw http.ClientException('offline')));
      await expectLater(api.search(SearchQuery(q: 'x')), throwsA(isA<SearchException>()));
    });

    test('a malformed body becomes a SearchException', () async {
      final api = apiWith(MockClient((_) async => http.Response('<html>', 200)));
      await expectLater(api.search(SearchQuery(q: 'x')), throwsA(isA<SearchException>()));
    });

    testWidgets('gives up after 20 seconds (backend allows 15)', (tester) async {
      final api = apiWith(MockClient((_) => Completer<http.Response>().future));
      Object? error;
      unawaited(api.search(SearchQuery(q: 'x')).then((_) {}, onError: (Object e) => error = e));
      await tester.pump(const Duration(seconds: 19));
      expect(error, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(error, isA<SearchException>().having((e) => e.isTimeout, 'isTimeout', isTrue));
    });
  });

  group('sources', () {
    test('GETs /sources', () async {
      late Uri seen;
      final api = apiWith(MockClient((request) async {
        seen = request.url;
        return http.Response(loadFixtureText('sources.json'), 200);
      }));
      final sources = await api.sources();
      expect(seen.path, '/sources');
      expect(sources.map((s) => s.name),
          ['Project Gutenberg', 'LibriVox', 'DOAB', 'Open Library']);
    });

    test('a failure becomes a SearchException', () async {
      final api = apiWith(MockClient((_) async => http.Response('', 503)));
      await expectLater(api.sources(), throwsA(isA<SearchException>()));
    });
  });
}
