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
    test('display names for the four sources', () {
      expect(sourceName('gutenberg'), 'Project Gutenberg');
      expect(sourceName('librivox'), 'LibriVox');
      expect(sourceName('doab'), 'DOAB');
      expect(sourceName('openlibrary'), 'Open Library');
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
    test('borrowable at the source', () {
      expect(actionLabel(book('openlibrary', access: Access.borrow, mode: ReadingMode.external)),
          'Borrow Emma by Jane Austen at Open Library');
    });
    test('labels always include the title so each one is unique to a screen reader', () {
      for (final source in ['gutenberg', 'doab', 'openlibrary']) {
        expect(actionLabel(book(source)), contains('Emma'));
      }
    });
  });
}
