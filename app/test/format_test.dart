import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/models/models.dart';
import 'package:free_book_reader/util/format.dart';

void main() {
  group('formatDuration (spoken as well as shown)', () {
    test('hours and minutes', () => expect(formatDuration(47204), '13 hr 6 min'));
    test('whole hours', () => expect(formatDuration(3600), '1 hr'));
    test('minutes only', () => expect(formatDuration(1132), '18 min'));
    test('seconds only', () => expect(formatDuration(45), '45 sec'));
    test('unknown', () {
      expect(formatDuration(null), isNull);
      expect(formatDuration(0), isNull);
    });
  });

  group('formatDate (month spelled out, so it reads the same everywhere)', () {
    test('a date', () => expect(formatDate(DateTime(2013, 5, 9)), 'May 9, 2013'));
    test('unknown', () => expect(formatDate(null), isNull));
  });

  group('authors', () {
    test('none', () => expect(formatAuthors([]), 'Unknown author'));
    test('one', () => expect(formatAuthors(['Jane Austen']), 'Jane Austen'));
    test('two', () => expect(formatAuthors(['A', 'B']), 'A and B'));
    test('many', () => expect(formatAuthors(['A', 'B', 'C']), 'A, B and C'));
  });

  group('language names', () {
    test('known codes', () {
      expect(languageName('en'), 'English');
      expect(languageName('fr'), 'French');
      expect(languageName('de'), 'German');
      expect(languageName('es'), 'Spanish');
    });
    test('unknown or missing', () {
      expect(languageName(null), 'Unknown language');
      expect(languageName('xx'), 'XX');
    });
  });

  group('source names', () {
    test('display names for the five sources', () {
      expect(sourceName('gutenberg'), 'Project Gutenberg');
      expect(sourceName('librivox'), 'LibriVox');
      expect(sourceName('doab'), 'DOAB');
      expect(sourceName('openlibrary'), 'Open Library');
      expect(sourceName('hathitrust'), 'HathiTrust');
    });
  });

  group('the action label for a book', () {
    Book book(String source, {BookFormat format = BookFormat.text, Access access = Access.open,
        ReadingMode mode = ReadingMode.inApp}) {
      return Book(
        source: source, sourceId: '1', title: 'Emma', authors: const ['Jane Austen'],
        format: format, access: access, url: 'https://x',
        reading: ReadingOptions(mode: mode, kind: mode == ReadingMode.inApp ? 'html' : null, url: 'https://x'),
      );
    }

    test('readable in the app', () => expect(actionLabel(book('gutenberg')), 'Read Emma by Jane Austen'));
    test('audio in the app', () {
      expect(actionLabel(book('librivox', format: BookFormat.audio)), 'Listen to Emma by Jane Austen');
    });
    test('open at the source', () {
      expect(actionLabel(book('openlibrary', mode: ReadingMode.external)),
          'View Emma by Jane Austen at Open Library');
    });
    test('a HathiTrust volume opens in HathiTrust\'s reader', () {
      expect(actionLabel(book('hathitrust', mode: ReadingMode.external)),
          'View Emma by Jane Austen at HathiTrust');
    });
    test('borrowable at the source', () {
      expect(actionLabel(book('openlibrary', access: Access.borrow, mode: ReadingMode.external)),
          'Borrow Emma by Jane Austen at Open Library');
    });
    test('labels always include the title so each one is unique to a screen reader', () {
      for (final source in ['gutenberg', 'doab', 'openlibrary', 'hathitrust']) {
        expect(actionLabel(book(source)), contains('Emma'));
      }
    });
  });

  group('matchNote (persona round one)', () {
    const note = 'Matched other catalog details, not the title or author';
    Work work(String title, {List<String> authors = const [], List<String> bookTitles = const []}) => Work(
          id: 'w',
          title: title,
          authors: authors,
          books: [
            for (final t in bookTitles)
              Book(
                source: 'gutenberg',
                sourceId: '1',
                title: t,
                format: BookFormat.text,
                url: 'https://example.org/1',
                access: Access.open,
                reading: const ReadingOptions(mode: ReadingMode.inApp, kind: 'html', url: 'https://example.org/1.html'),
              ),
          ],
        );

    test('every word in the title', () {
      expect(matchNote(SearchQuery(q: 'Frankenstein'), work('Frankenstein; Or, The Modern Prometheus')), isNull);
      expect(matchNote(SearchQuery(q: 'pride & prejudice'), work('Pride and Prejudice')), isNull);
    });
    test('every word in the authors', () {
      expect(matchNote(SearchQuery(q: 'mary shelley'), work('Frankenstein', authors: ['Shelley, Mary'])), isNull);
    });
    test('words missing from the title and author', () {
      expect(matchNote(SearchQuery(q: 'Heartstopper'), work('Eat Fat, Be Healthy')), note);
      expect(matchNote(SearchQuery(q: 'time travel'),
          work('A General History and Collection of Voyages and Travels')), note);
    });
    test("a title search matches a book's title too", () {
      expect(matchNote(SearchQuery(title: 'Frankenstein'),
          work('Frankenstein', bookTitles: ['Frankenstein (1818)'])), isNull);
    });
    test('ISBN and subject searches never get the note', () {
      expect(matchNote(SearchQuery(isbn: '9780141439471'), work('Anything')), isNull);
      expect(matchNote(SearchQuery(keyword: 'democracy'), work('Anything')), isNull);
    });
  });

  group('bookSummary (persona round one)', () {
    Book book(String source, BookFormat format,
            {String id = '1', List<String> narrators = const [], int? seconds, String? originalPublication}) =>
        Book(
          source: source,
          sourceId: id,
          title: 'T',
          format: format,
          url: 'https://example.org/1',
          access: Access.open,
          reading: const ReadingOptions(mode: ReadingMode.inApp, kind: 'html', url: 'https://example.org/1.html'),
          narrators: narrators,
          audioSeconds: seconds,
          originalPublication: originalPublication,
        );

    test('a recording names its readers and length', () {
      expect(bookSummary(book('librivox', BookFormat.audio, narrators: ['Cori Samuel'], seconds: 28740)),
          'Read by Cori Samuel · ${formatDuration(28740)}');
    });
    test('a Gutenberg eBook gives its number and first publication', () {
      expect(bookSummary(book('gutenberg', BookFormat.text, id: '41445', originalPublication: '1818')),
          'eBook #41445 · Original publication: 1818');
    });
    test('other sources have nothing to add', () {
      expect(bookSummary(book('openlibrary', BookFormat.text)), isNull);
    });
  });
}
