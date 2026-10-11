// The app's models mirror the backend's JSON (see backend/tests/test_models.py).
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/models/models.dart';

import 'helpers/fixtures.dart';

void main() {
  late SearchResponse response;
  setUp(() => response = SearchResponse.fromJson(loadJson('search_response.json')));

  group('SearchResponse', () {
    test('parses works and the list of unavailable sources', () {
      expect(response.works.map((w) => w.id), ['w-pride', 'w-quijote', 'w-kinder']);
      expect(response.unavailableSources, isEmpty);
    });

    test('reads unavailable_sources', () {
      final json = loadJson('search_response.json') as Map<String, dynamic>;
      json['unavailable_sources'] = ['doab', 'librivox'];
      expect(SearchResponse.fromJson(json).unavailableSources, ['doab', 'librivox']);
    });
  });

  group('Work', () {
    test('has the fields from spec.md', () {
      final work = response.works.first;
      expect(work.title, 'Pride and Prejudice');
      expect(work.authors, ['Jane Austen']);
      expect(work.language, 'en');
      expect(work.sources, ['gutenberg', 'librivox', 'openlibrary']);
      expect(work.sourceIds['librivox'], ['253']);
      expect(work.identifiers['isbn'], ['9780140430721']);
      expect(work.urls, hasLength(3));
      expect(work.coverUrl, startsWith('https://'));
      expect(work.formats, ['audio', 'text']);
      expect(work.books, hasLength(3));
    });

    test('separates text books from audio books', () {
      final work = response.works.first;
      expect(work.textBooks.map((b) => b.source), ['gutenberg', 'openlibrary']);
      expect(work.audioBooks.map((b) => b.source), ['librivox']);
    });

    test('recordings only include audio in the same language as the text', () {
      final work = response.works.first;
      final gutenberg = work.books.first;
      expect(work.recordingsFor(gutenberg).map((b) => b.sourceId), ['253']);
      final spanish = response.works[1].books.first;
      expect(response.works[1].recordingsFor(spanish), isEmpty);
    });

    test('a book in a work with no audio has no recordings', () {
      final kinder = response.works[2];
      expect(kinder.recordingsFor(kinder.books.first), isEmpty);
    });

    test('has a null language when none of its books know it', () {
      final json = loadJson('search_response.json') as Map<String, dynamic>;
      final work = (json['works'] as List)[1] as Map<String, dynamic>;
      work['language'] = null;
      expect(Work.fromJson(work).language, isNull);
    });
  });

  group('Book', () {
    test('text book from Project Gutenberg', () {
      final book = response.works.first.books.first;
      expect(book.source, 'gutenberg');
      expect(book.sourceId, '1342');
      expect(book.key, 'gutenberg:1342');
      expect(book.format, BookFormat.text);
      expect(book.access, Access.open);
      expect(book.reading.mode, ReadingMode.inApp);
      expect(book.reading.kind, 'html');
      expect(book.content['text/html'], contains('gutenberg.org'));
    });

    test('Gutenberg book names its web-reader publication on the backend', () {
      // A path on the backend (a Readium manifest), joined to BACKEND_URL by the reader.
      final book = response.works.first.books.first;
      expect(book.reading.publication, '/publications/gutenberg/1342/manifest.json');
    });

    test('Gutenberg book has edition details', () {
      final book = response.works.first.books.first;
      expect(book.releaseDate, DateTime(1998, 6, 1));
      expect(book.lastUpdated, DateTime(2026, 9, 29));
      expect(book.credits, startsWith('Chuck Greif'));
      expect(book.originalPublication, isNull);
    });

    test('edition details are null when missing or unreadable', () {
      // LibriVox and older responses have no such fields.
      final audio = response.works.first.books[1];
      expect(audio.releaseDate, isNull);
      expect(audio.lastUpdated, isNull);
      expect(audio.credits, isNull);
      expect(audio.originalPublication, isNull);
      final json = Map<String, dynamic>.from(
          (loadJson('search_response.json')['works'][0]['books'][0]) as Map);
      json['release_date'] = 'June 1998';
      json['last_updated'] = 19980601;
      final book = Book.fromJson(json);
      expect(book.releaseDate, isNull);
      expect(book.lastUpdated, isNull);
    });

    test('books without a publication, or older responses without the field', () {
      expect(response.works.first.books[1].reading.publication, isNull);
      final reading = ReadingOptions.fromJson({'mode': 'external', 'kind': null, 'url': 'https://x'});
      expect(reading.publication, isNull);
    });

    test('audio book from LibriVox', () {
      final book = response.works.first.books[1];
      expect(book.format, BookFormat.audio);
      expect(book.audioSeconds, 47204);
      expect(book.narrators, ['Chris Goringe', 'Kara Shallenberg']);
      expect(book.chapters, hasLength(3));
      expect(book.chapters.first.title, 'Chapters 1-3');
      expect(book.chapters.first.durationSeconds, 1132);
      expect(book.reading.kind, 'audio');
    });

    test('Open Library book links out', () {
      final book = response.works.first.books[2];
      expect(book.language, isNull);
      expect(book.reading.mode, ReadingMode.external);
      expect(book.reading.url, 'https://openlibrary.org/works/OL66554W');
    });

    test('borrowable access', () {
      expect(response.works[1].books.first.access, Access.borrow);
      expect(response.works[1].books.first.pages, 863);
    });

    test('every access value parses', () {
      const expected = {
        'open': Access.open,
        'borrow': Access.borrow,
        'print_disabled': Access.printDisabled,
        'none': Access.none,
      };
      expected.forEach((value, access) {
        final json = Map<String, dynamic>.from(
            (loadJson('search_response.json')['works'][1]['books'][0]) as Map);
        json['access'] = value;
        expect(Book.fromJson(json).access, access);
      });
    });

    test('missing optional fields become null or empty', () {
      final book = Book.fromJson({
        'source': 'gutenberg',
        'source_id': '1',
        'title': 'T',
        'url': 'https://x',
        'format': 'text',
        'access': 'open',
        'reading': {'mode': 'external', 'kind': null, 'url': 'https://x'},
      });
      expect(book.authors, isEmpty);
      expect(book.narrators, isEmpty);
      expect(book.chapters, isEmpty);
      expect(book.identifiers, isEmpty);
      expect(book.content, isEmpty);
      expect(book.language, isNull);
      expect(book.coverUrl, isNull);
      expect(book.pages, isNull);
      expect(book.audioSeconds, isNull);
    });

    test('an unknown format or access value is rejected, not guessed', () {
      expect(
        () => Book.fromJson({
          'source': 'gutenberg', 'source_id': '1', 'title': 'T', 'url': 'u',
          'format': 'video', 'access': 'open',
          'reading': {'mode': 'external', 'kind': null, 'url': 'u'},
        }),
        throwsFormatException,
      );
    });
  });

  group('SourceInfo', () {
    test('parses the /sources payload', () {
      final sources = (loadJson('sources.json') as List)
          .map((j) => SourceInfo.fromJson(j as Map<String, dynamic>))
          .toList();
      expect(sources.map((s) => s.id), ['gutenberg', 'librivox', 'doab', 'openlibrary']);
      final librivox = sources[1];
      expect(librivox.name, 'LibriVox');
      expect(librivox.formats, ['audio']);
      expect(librivox.inApp, isTrue);
      expect(librivox.donationUrl, startsWith('https://'));
      expect(sources[3].inApp, isFalse);
    });
  });

  group('SearchQuery', () {
    test('only non-empty fields become query parameters', () {
      final query = SearchQuery(q: 'dickens', language: 'en', format: BookFormat.audio);
      expect(query.toQueryParameters(), {
        'q': 'dickens',
        'language': 'en',
        'format': 'audio',
        'page': '1',
      });
    });

    test('sources are joined with commas and fields are trimmed', () {
      final query = SearchQuery(
          title: ' Hamlet ', author: 'Shakespeare', sources: ['gutenberg', 'doab'], page: 2);
      expect(query.toQueryParameters(), {
        'title': 'Hamlet',
        'author': 'Shakespeare',
        'sources': 'gutenberg,doab',
        'page': '2',
      });
    });

    test('a blank query is not searchable', () {
      expect(SearchQuery().isSearchable, isFalse);
      expect(SearchQuery(q: '   ').isSearchable, isFalse);
      expect(SearchQuery(q: 'x').isSearchable, isTrue);
      expect(SearchQuery(isbn: '9780140430721').isSearchable, isTrue);
    });

    test('copyWith changes only what it is given', () {
      final query = SearchQuery(q: 'x', language: 'fr');
      final changed = query.copyWith(format: BookFormat.text);
      expect(changed.q, 'x');
      expect(changed.language, 'fr');
      expect(changed.format, BookFormat.text);
    });

    test('copyWith can clear a filter', () {
      final query = SearchQuery(q: 'x', language: 'fr', format: BookFormat.text);
      final cleared = query.copyWith(clearLanguage: true, clearFormat: true);
      expect(cleared.language, isNull);
      expect(cleared.format, isNull);
    });
  });
}
