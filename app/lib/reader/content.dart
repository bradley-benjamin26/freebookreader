import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  HttpContentLoader(this.client, {this.timeout = const Duration(seconds: 30)});

  final http.Client client;

  /// A download that takes longer is a load error, so the reader can offer Try again.
  final Duration timeout;

  @override
  Future<BookContent> load(ReadingOptions options) async {
    final kind = options.kind;
    if (kind != 'html' && kind != 'text') {
      throw ContentLoadException('This app cannot show $kind books yet.');
    }
    final http.Response response;
    try {
      response = await client.get(Uri.parse(options.url)).timeout(timeout);
    } on TimeoutException {
      throw const ContentLoadException('The download took too long.');
    } on Object catch (e) {
      throw ContentLoadException('Could not download the book: $e');
    }
    if (response.statusCode != 200) {
      throw ContentLoadException('The source answered ${response.statusCode}.');
    }
    final body = decodeBody(response);
    // In a background isolate: a big book takes long enough to freeze the screen.
    final paragraphs = await compute(kind == 'html' ? htmlParagraphs : textParagraphs, body);
    if (paragraphs.isEmpty) throw const ContentLoadException('The book has no text.');
    return TextContent(paragraphs);
  }
}

/// The response's text in the charset its `content-type` names; UTF-8 when it names none or one Dart does not
/// know (the `http` package would use Latin-1).
String decodeBody(http.Response response) {
  final charset = RegExp(r'charset=([\w.:-]+)', caseSensitive: false)
      .firstMatch(response.headers['content-type'] ?? '')
      ?.group(1);
  final encoding = charset == null ? null : Encoding.getByName(charset);
  if (encoding != null && encoding != utf8) {
    try {
      return encoding.decode(response.bodyBytes);
    } on FormatException {
      // e.g. us-ascii with bytes above 127: fall through to UTF-8
    }
  }
  return utf8.decode(response.bodyBytes, allowMalformed: true);
}

/// Stands for a line break (<br>, or a newline in <pre>) until [_clean] turns it into a '\n'.
const _lineBreak = '\u0001';

/// Folds whitespace into single spaces, keeps each line break as one '\n' with no spaces around it, and
/// trims the ends.
String _clean(String text) => text
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp('[ $_lineBreak]*$_lineBreak[ $_lineBreak]*'), '\n')
    .trim();

/// Elements that start a new paragraph. Anything else (span, em, a, ...) continues the one it is in.
const _blocks = {
  'address', 'article', 'aside', 'blockquote', 'body', 'caption', 'dd', 'details', 'div', 'dl', 'dt',
  'fieldset', 'figcaption', 'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr',
  'html', 'li', 'main', 'nav', 'ol', 'p', 'pre', 'section', 'table', 'tbody', 'td', 'tfoot', 'th', 'thead',
  'tr', 'ul',
};

/// Headings, paragraphs, verse, list items and table cells from an HTML book, in order, without Project
/// Gutenberg's license header and footer. A <br> is a line break inside its paragraph ('\n'), which is how
/// verse keeps its lines. Text between blocks (a bare div of text) is a paragraph of its own.
List<String> htmlParagraphs(String source) {
  final document = html_parser.parse(source);
  document
      .querySelectorAll('#pg-header, #pg-footer, .pg-boilerplate, script, style')
      .forEach((dom.Element e) => e.remove());
  final paragraphs = <String>[];
  final text = StringBuffer();

  void flush() {
    final paragraph = _clean(text.toString());
    text.clear();
    if (paragraph.isNotEmpty) paragraphs.add(paragraph);
  }

  void walk(dom.Node node, {required bool preformatted}) {
    if (node is dom.Text) {
      text.write(preformatted ? node.text.replaceAll(RegExp(r'\r?\n'), _lineBreak) : node.text);
    } else if (node is dom.Element) {
      final name = node.localName;
      if (name == 'br') {
        text.write(_lineBreak);
        return;
      }
      final block = _blocks.contains(name);
      if (block) flush();
      for (final child in node.nodes) {
        walk(child, preformatted: preformatted || name == 'pre');
      }
      if (block) flush();
    }
  }

  walk(document.documentElement ?? document, preformatted: false);
  flush();
  return paragraphs;
}

/// Paragraphs of a plain-text book, separated by blank lines.
List<String> textParagraphs(String source) => source
    .split(RegExp(r'\r?\n\s*\r?\n'))
    .map(_clean)
    .where((t) => t.isNotEmpty)
    .toList();
