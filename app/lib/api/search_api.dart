import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// The backend's `/search` and `/sources`.
abstract class SearchApi {
  Future<SearchResponse> search(SearchQuery query);
  Future<List<SourceInfo>> sources();
}

class SearchException implements Exception {
  const SearchException(this.message, {this.isTimeout = false});

  final String message;
  final bool isTimeout;

  @override
  String toString() => 'SearchException: $message';
}

class HttpSearchApi implements SearchApi {
  HttpSearchApi({required this.client, required this.baseUrl});

  final http.Client client;
  final Uri baseUrl;

  /// The backend answers within 15 seconds; this leaves room for the network.
  static const timeout = Duration(seconds: 20);

  Uri _endpoint(String name, [Map<String, String>? query]) {
    final prefix = baseUrl.path.endsWith('/') ? baseUrl.path : '${baseUrl.path}/';
    return baseUrl.replace(path: '$prefix$name', queryParameters: query);
  }

  Future<Object?> _getJson(Uri url) async {
    final http.Response response;
    try {
      response = await client.get(url).timeout(timeout);
    } on TimeoutException {
      throw const SearchException('The server took too long to answer.', isTimeout: true);
    } on http.ClientException catch (e) {
      throw SearchException('Could not reach the server: ${e.message}');
    }
    if (response.statusCode != 200) {
      throw SearchException('The server answered ${response.statusCode}.');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const SearchException('The server sent an answer that could not be read.');
    }
  }

  @override
  Future<SearchResponse> search(SearchQuery query) async {
    if (!query.isSearchable) throw const SearchException('Nothing to search for.');
    final json = await _getJson(_endpoint('search', query.toQueryParameters()));
    try {
      return SearchResponse.fromJson(json as Map<String, dynamic>);
    } on Object {
      throw const SearchException('The server sent an answer that could not be read.');
    }
  }

  @override
  Future<List<SourceInfo>> sources() async {
    final json = await _getJson(_endpoint('sources'));
    try {
      return (json as List).map((j) => SourceInfo.fromJson(j as Map<String, dynamic>)).toList();
    } on Object {
      throw const SearchException('The server sent an answer that could not be read.');
    }
  }
}
