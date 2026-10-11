import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/models.dart';

/// What the reader shows.
sealed class BookContent {
  const BookContent();
}

/// A book drawn by the app, one string per paragraph.
class TextContent extends BookContent {
  const TextContent(this.paragraphs);

  final List<String> paragraphs;
}

/// A PDF, shown by the PDF viewer.
class PdfContent extends BookContent {
  const PdfContent(this.url);

  final String url;
}

class ContentLoadException implements Exception {
  const ContentLoadException(this.message);

  final String message;

  @override
  String toString() => 'ContentLoadException: $message';
}

/// Fetches a book's text. PDFs do not come through here; they go straight to
/// the PDF viewer.
abstract class ContentLoader {
  Future<BookContent> load(ReadingOptions options);
}

/// Downloads HTML or plain text on the device and splits it into paragraphs.
///
/// Provisional: the reader package is not chosen yet (see decision_reader.md),
/// and this loader does not read EPUB.
class HttpContentLoader implements ContentLoader {
  HttpContentLoader(this.client);

  final http.Client client;

  @override
  Future<BookContent> load(ReadingOptions options) async {
    final kind = options.kind;
    if (kind != 'html' && kind != 'text') {
      throw ContentLoadException('This app cannot show $kind books yet.');
    }
    final http.Response response;
    try {
      response = await client.get(Uri.parse(options.url));
    } on Object catch (e) {
      throw ContentLoadException('Could not download the book: $e');
    }
    if (response.statusCode != 200) {
      throw ContentLoadException('The source answered ${response.statusCode}.');
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    final paragraphs = kind == 'html' ? htmlParagraphs(body) : textParagraphs(body);
    if (paragraphs.isEmpty) throw const ContentLoadException('The book has no text.');
    return TextContent(paragraphs);
  }
}

String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Headings and paragraphs from an HTML book, without Project Gutenberg's
/// license header and footer.
List<String> htmlParagraphs(String source) {
  final document = html_parser.parse(source);
  document
      .querySelectorAll('#pg-header, #pg-footer, .pg-boilerplate, script, style')
      .forEach((dom.Element e) => e.remove());
  return document
      .querySelectorAll('h1, h2, h3, h4, p')
      .map((e) => _clean(e.text))
      .where((t) => t.isNotEmpty)
      .toList();
}

/// Paragraphs of a plain-text book, separated by blank lines.
List<String> textParagraphs(String source) => source
    .split(RegExp(r'\r?\n\s*\r?\n'))
    .map(_clean)
    .where((t) => t.isNotEmpty)
    .toList();
