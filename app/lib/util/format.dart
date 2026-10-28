// Text shown (and spoken by screen readers) for durations, names and actions.
import '../models/models.dart';

/// "13 hr 6 min", "1 hr", "18 min", "45 sec"; null when unknown.
String? formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return null;
  if (seconds < 60) return '$seconds sec';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  return [if (hours > 0) '$hours hr', if (minutes > 0) '$minutes min'].join(' ');
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "May 9, 2013"; null when unknown.
String? formatDate(DateTime? date) =>
    date == null ? null : '${_months[date.month - 1]} ${date.day}, ${date.year}';

/// "A", "A and B", "A, B and C".
String formatAuthors(List<String> authors) => joinNames(authors) ?? 'Unknown author';

String? joinNames(List<String> names) => switch (names) {
      [] => null,
      [final one] => one,
      _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
    };

const languageNames = {
  'en': 'English',
  'fr': 'French',
  'de': 'German',
  'es': 'Spanish',
  'it': 'Italian',
  'pt': 'Portuguese',
  'nl': 'Dutch',
  'la': 'Latin',
  'fi': 'Finnish',
  'sv': 'Swedish',
  'da': 'Danish',
  'pl': 'Polish',
  'ru': 'Russian',
  'el': 'Greek',
  'zh': 'Chinese',
  'ja': 'Japanese',
};

String languageName(String? code) {
  if (code == null || code.isEmpty) return 'Unknown language';
  return languageNames[code] ?? code.toUpperCase();
}

const sourceIds = ['gutenberg', 'librivox', 'doab', 'openlibrary', 'hathitrust'];

const _sourceNames = {
  'gutenberg': 'Project Gutenberg',
  'librivox': 'LibriVox',
  'doab': 'DOAB',
  'openlibrary': 'Open Library',
  'hathitrust': 'HathiTrust',
};

String sourceName(String id) => _sourceNames[id] ?? id;

/// The verb on a book's button: "Read", "Listen", "Borrow" or "View".
String actionVerb(Book book) {
  if (book.inApp) return book.format == BookFormat.audio ? 'Listen' : 'Read';
  return book.access == Access.borrow ? 'Borrow' : 'View';
}

/// The accessible name of a book's button. It starts with the visible verb
/// and always names the book, so each button is unique to a screen reader.
String actionLabel(Book book) {
  final what = '${book.title} by ${formatAuthors(book.authors)}';
  return switch (actionVerb(book)) {
    'Read' => 'Read $what',
    'Listen' => 'Listen to $what',
    final verb => '$verb $what at ${sourceName(book.source)}',
  };
}

final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

Set<String> _words(String text) => text.toLowerCase().split(_nonWord).where((w) => w.isNotEmpty).toSet();

/// A note for a result whose title and author do not contain the searched words, so it matched on
/// something the card does not show; null when they do, and for ISBN and subject searches.
// shortcut: no accent folding ("Quixote" vs "Quijote" gets the note); add it if round two finds that misleading.
String? matchNote(SearchQuery query, Work work) {
  bool has(String? text) => text != null && text.trim().isNotEmpty;
  final words = _words(query.searchedText);
  if (words.isEmpty) return null;
  final titles = {for (final title in [work.title, ...work.books.map((b) => b.title)]) ..._words(title)};
  final authors = _words(work.authors.join(' '));
  final inTitle = words.every(titles.contains);
  final inAuthor = words.every(authors.contains);
  final matched = has(query.q)
      ? inTitle || inAuthor
      : has(query.title)
          ? inTitle
          : has(query.author)
              ? inAuthor
              : true; // subject or ISBN: the card cannot show the match, and that is expected
  return matched ? null : 'Matched other catalog details, not the title or author';
}

/// Where and how [book] opens, in a sentence.
String accessNote(Book book) {
  final source = sourceName(book.source);
  if (book.inApp) {
    return book.format == BookFormat.audio
        ? 'Listen in this app.'
        : 'Read in this app.';
  }
  return switch (book.access) {
    Access.borrow => 'Borrow it from $source. You need a free account there.',
    Access.printDisabled => 'Available at $source to people with a print disability.',
    Access.none => 'Listed at $source, which has no free copy to read.',
    Access.open when book.source == 'hathitrust' =>
      'Opens in the HathiTrust reader in your web browser.',
    Access.open => 'Read it free at $source.',
  };
}

/// Which copy [book] is, for telling it apart from others of the work; null when there is nothing to say.
String? bookSummary(Book book) {
  final parts = switch (book.source) {
    _ when book.format == BookFormat.audio => [
        if (joinNames(book.narrators) case final names?) 'Read by $names',
        ?formatDuration(book.audioSeconds),
      ],
    'gutenberg' => [
        'eBook #${book.sourceId}',
        if (book.originalPublication case final year?) 'Original publication: $year',
      ],
    'hathitrust' => [
        if (book.volume case final volume?) 'Volume $volume',
        ?book.library,
      ],
    _ => const <String>[],
  };
  return parts.isEmpty ? null : parts.join(' · ');
}
