import '../models/models.dart';
import 'content.dart';
import 'reader_engine.dart';
import 'readium_engine.dart';
import 'text_engine.dart';

/// The engine that shows [book], or null when none can.
///
/// On web, flutter_readium opens the Readium manifest the backend serves for
/// the book (`reading.publication`). Elsewhere, and for books without one, our
/// own renderer shows HTML and plain text. PDFs go to the PDF viewer instead.
ReaderEngine? chooseReaderEngine(
  ReadingOptions book, {
  required bool web,
  required Uri backend,
  required ContentLoader loader,
}) {
  final publication = book.publication;
  if (web && publication != null) return ReadiumReaderEngine(backendUrl(backend, publication));
  if (book.kind == 'html' || book.kind == 'text') return TextReaderEngine(loader);
  return null;
}

/// [path] (like `/publications/...`) under [backend], keeping any path the
/// backend is mounted at.
Uri backendUrl(Uri backend, String path) {
  final prefix = backend.path.endsWith('/') ? backend.path.substring(0, backend.path.length - 1) : backend.path;
  return backend.replace(path: '$prefix${path.startsWith('/') ? path : '/$path'}');
}
