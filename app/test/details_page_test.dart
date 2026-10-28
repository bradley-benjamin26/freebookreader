// Details page: the full metadata of a work, plus every way to get at it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:free_book_reader/models/models.dart';

import 'helpers/fixtures.dart';
import 'helpers/test_app.dart';

void main() {
  group('metadata', () {
    testWidgets('shows the title as the page heading', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      expect(find.byKey(const Key('details-page')), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('details-title'))),
          containsSemantics(isHeader: true, label: 'Pride and Prejudice'));
    });

    testWidgets('lists author, language and sources', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      final meta = find.byKey(const Key('details-metadata'));
      for (final text in ['Jane Austen', 'English', 'Project Gutenberg', 'LibriVox', 'Open Library']) {
        expect(find.descendant(of: meta, matching: find.textContaining(text)), findsWidgets,
            reason: text);
      }
    });

    group('identifiers', () {
      // The identifiers (ISBNs, OCLC numbers, ...) are many and mostly internal codes: they stay behind one
      // button, closed by default, so the page stays short (user decision 2026-10-11).
      Finder inMeta(String text) => find.descendant(
          of: find.byKey(const Key('details-metadata')), matching: find.textContaining(text));

      testWidgets('are hidden until asked for', (tester) async {
        await pumpApp(tester, await TestEnv.create());
        await openDetails(tester, 'w-pride');
        expect(find.descendant(of: find.byKey(const Key('identifiers-toggle')), matching: find.text('Show identifiers')),
            findsOneWidget);
        expect(inMeta('ISBN'), findsNothing);
        expect(inMeta('9780140430721'), findsNothing);
      });

      testWidgets('the button shows them, and hides them again', (tester) async {
        await pumpApp(tester, await TestEnv.create());
        await openDetails(tester, 'w-pride');
        final toggle = find.byKey(const Key('identifiers-toggle'));
        await tester.ensureVisible(toggle);
        expect(tester.getSemantics(toggle), containsSemantics(isButton: true, hasExpandedState: true, isExpanded: false));
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(inMeta('ISBN'), findsWidgets);
        expect(inMeta('9780140430721'), findsWidgets);
        expect(find.descendant(of: toggle, matching: find.text('Hide identifiers')), findsOneWidget);
        expect(tester.getSemantics(toggle), containsSemantics(isButton: true, hasExpandedState: true, isExpanded: true));
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(inMeta('ISBN'), findsNothing);
        expect(find.descendant(of: toggle, matching: find.text('Show identifiers')), findsOneWidget);
      });

      testWidgets('a work with none has no button', (tester) async {
        final env = await TestEnv.create();
        final pride = env.api.response.works.first;
        env.api.response = SearchResponse(works: [
          Work(id: pride.id, title: pride.title, authors: pride.authors, language: pride.language,
              sources: pride.sources, identifiers: const {'isbn': []}, books: pride.books),
        ], unavailableSources: const []);
        await pumpApp(tester, env);
        await openDetails(tester, 'w-pride');
        expect(find.byKey(const Key('identifiers-toggle')), findsNothing);
      });
    });

    testWidgets('shows a few identifiers, and all of them on request', (tester) async {
      // Review 2026-10-11, #15: one Open Library work had 3,714 ISBNs, printed as one 65,000-character line.
      final isbns = [for (var i = 0; i < 1000; i++) '97800000${i.toString().padLeft(5, '0')}'];
      final env = await TestEnv.create();
      final pride = env.api.response.works.first;
      env.api.response = SearchResponse(works: [
        Work(id: pride.id, title: pride.title, authors: pride.authors, language: pride.language,
            sources: pride.sources, identifiers: {'isbn': isbns, 'oclc': ['1', '2']}, books: pride.books),
      ], unavailableSources: const []);
      await pumpApp(tester, env);
      await openDetails(tester, 'w-pride');
      final toggle = find.byKey(const Key('identifiers-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final meta = find.byKey(const Key('details-metadata'));
      expect(find.descendant(of: meta, matching: find.textContaining(isbns[4])), findsOneWidget);
      expect(find.descendant(of: meta, matching: find.textContaining(isbns[5])), findsNothing);
      expect(find.descendant(of: meta, matching: find.textContaining('1, 2')), findsOneWidget);   // short lists unchanged
      final more = find.byKey(const Key('show-all-isbn'));
      expect(find.descendant(of: more, matching: find.text('Show all 1000 ISBNs')), findsOneWidget);
      expect(find.byKey(const Key('show-all-oclc')), findsNothing);
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.descendant(of: meta, matching: find.textContaining(isbns[999])), findsOneWidget);
      expect(find.byKey(const Key('show-all-isbn')), findsNothing);
    });

    testWidgets('shows a work with an unknown language without crashing', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-quijote');
      expect(find.descendant(
          of: find.byKey(const Key('details-metadata')), matching: find.textContaining('Spanish')),
          findsWidgets);
    });

    testWidgets('has a large cover with a text alternative', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      expect(tester.getSemantics(find.byKey(const Key('details-cover'))),
          containsSemantics(label: 'Cover of Pride and Prejudice'));
    });

    testWidgets('each book is listed with its source and format', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      for (final key in ['gutenberg:1342', 'librivox:253', 'openlibrary:OL66554W']) {
        await tester.ensureVisible(find.byKey(Key('book-$key')));
        expect(find.byKey(Key('book-$key')), findsOneWidget, reason: key);
      }
    });

    testWidgets('an audiobook shows its narrators and length', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      final book = find.byKey(const Key('book-librivox:253'));
      await tester.ensureVisible(book);
      expect(find.descendant(of: book, matching: find.textContaining('Chris Goringe')), findsOneWidget);
      expect(find.descendant(of: book, matching: find.textContaining('Kara Shallenberg')), findsOneWidget);
      expect(find.descendant(of: book, matching: find.textContaining('13 hr 6 min')), findsOneWidget);
    });

    testWidgets('a book with a page count shows it', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-quijote');
      expect(find.textContaining('863 pages'), findsOneWidget);
    });

    testWidgets('a Gutenberg book shows its release, last update and credits', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      final book = find.byKey(const Key('book-gutenberg:1342'));
      await tester.ensureVisible(book);
      Finder inBook(String text) => find.descendant(of: book, matching: find.textContaining(text));
      expect(inBook('eBook #1342 · Released June 1, 1998'), findsOneWidget);
      expect(inBook('Last updated September 29, 2026'), findsOneWidget);
      expect(inBook('Credits: Chuck Greif'), findsOneWidget);
      expect(inBook('Original publication'), findsNothing); // none in the catalog
    });

    testWidgets('books without edition details show none', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      final book = find.byKey(const Key('book-librivox:253'));
      await tester.ensureVisible(book);
      // Only Gutenberg numbers its books; other sources' ids mean nothing to readers.
      for (final text in ['eBook #', 'Released', 'Last updated', 'Credits', 'Original publication']) {
        expect(find.descendant(of: book, matching: find.textContaining(text)), findsNothing,
            reason: text);
      }
    });

    testWidgets('two Gutenberg editions of one work can be told apart', (tester) async {
      // Gutenberg has several eBooks of many works (1342 and 42671 are both
      // Pride and Prejudice); they merge into one work.
      final json = loadJson('search_response.json') as Map<String, dynamic>;
      final books = json['works'][0]['books'] as List;
      final edition = Map<String, dynamic>.from(books[0] as Map)
        ..['source_id'] = '42671'
        ..['url'] = 'https://www.gutenberg.org/ebooks/42671'
        ..['release_date'] = '2013-05-09'
        ..['last_updated'] = null
        ..['credits'] = 'E-text prepared by Greg Weeks and Jon Hurst'
        ..['original_publication'] = 'London: Chatto & Windus, 1894.';
      books.insert(1, edition);
      await pumpApp(tester, await TestEnv.create(response: SearchResponse.fromJson(json)));
      await openDetails(tester, 'w-pride');
      final book = find.byKey(const Key('book-gutenberg:42671'));
      await tester.ensureVisible(book);
      Finder inBook(String text) => find.descendant(of: book, matching: find.textContaining(text));
      expect(inBook('eBook #42671 · Released May 9, 2013'), findsOneWidget);
      expect(inBook('Last updated'), findsNothing);
      expect(inBook('Credits: E-text prepared by Greg Weeks'), findsOneWidget);
      expect(inBook('Original publication: London: Chatto & Windus, 1894.'), findsOneWidget);
    });

    group('HathiTrust volumes', () {
      Future<Finder> openHathiTrust(WidgetTester tester, Map<String, dynamic> extra) async {
        final json = loadJson('search_response.json') as Map<String, dynamic>;
        final books = json['works'][0]['books'] as List;
        books.add({
          'source': 'hathitrust',
          'source_id': 'hvd.hx66p3',
          'title': 'Pride and prejudice',
          'authors': ['Jane Austen'],
          'language': 'en',
          'format': 'text',
          'url': 'https://babel.hathitrust.org/cgi/pt?id=hvd.hx66p3',
          'access': 'open',
          'reading': {'mode': 'external', 'kind': null, 'url': 'https://babel.hathitrust.org/cgi/pt?id=hvd.hx66p3'},
          ...extra,
        });
        await pumpApp(tester, await TestEnv.create(response: SearchResponse.fromJson(json)));
        await openDetails(tester, 'w-pride');
        final book = find.byKey(const Key('book-hathitrust:hvd.hx66p3'));
        await tester.ensureVisible(book);
        return book;
      }

      testWidgets('show the volume label and the library that holds it', (tester) async {
        final book = await openHathiTrust(tester, {'volume': 'v.1', 'library': 'Harvard University'});
        expect(find.descendant(of: book, matching: find.textContaining('Volume v.1 · Harvard University')),
            findsOneWidget);
      });

      testWidgets('show just the library for a one-volume book', (tester) async {
        final book = await openHathiTrust(tester, {'library': 'Harvard University'});
        expect(find.descendant(of: book, matching: find.textContaining('Harvard University')), findsOneWidget);
        expect(find.descendant(of: book, matching: find.textContaining('Volume')), findsNothing);
      });

      testWidgets('say that the book opens in the HathiTrust reader in the browser', (tester) async {
        final book = await openHathiTrust(tester, {'library': 'Harvard University'});
        expect(find.descendant(of: book, matching: find.textContaining("HathiTrust's reader")), findsOneWidget);
        expect(find.descendant(of: book, matching: find.textContaining('web browser')), findsOneWidget);
      });

      testWidgets('mark a United States only volume', (tester) async {
        final book = await openHathiTrust(tester, {'us_only': true});
        expect(find.descendant(of: book, matching: find.textContaining('only in the United States')),
            findsOneWidget);
      });

      testWidgets('say nothing about the United States for other volumes', (tester) async {
        final book = await openHathiTrust(tester, {});
        expect(find.descendant(of: book, matching: find.textContaining('United States')), findsNothing);
      });

      group('many volumes', () {
        // One HathiTrust record can have dozens of volumes (the parts of a set, copies from several libraries).
        Future<void> openWithVolumes(WidgetTester tester, int count) async {
          final json = loadJson('search_response.json') as Map<String, dynamic>;
          final books = json['works'][0]['books'] as List;
          for (var i = 1; i <= count; i++) {
            books.add({
              'source': 'hathitrust',
              'source_id': 'hvd.v$i',
              'title': 'Pride and prejudice',
              'authors': ['Jane Austen'],
              'language': 'en',
              'format': 'text',
              'url': 'https://babel.hathitrust.org/cgi/pt?id=hvd.v$i',
              'access': 'open',
              'volume': 'v.$i',
              'library': 'Harvard University',
              'reading': {'mode': 'external', 'kind': null, 'url': 'https://babel.hathitrust.org/cgi/pt?id=hvd.v$i'},
            });
          }
          await pumpApp(tester, await TestEnv.create(response: SearchResponse.fromJson(json)));
          await openDetails(tester, 'w-pride');
        }

        final volumeCards = find.byWidgetPredicate(
            (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('book-hathitrust:'));

        testWidgets('show the first 3 and a button for the rest', (tester) async {
          await openWithVolumes(tester, 20);
          expect(volumeCards, findsNWidgets(3));
          expect(find.byKey(const Key('book-hathitrust:hvd.v1')), findsOneWidget);
          expect(find.byKey(const Key('book-hathitrust:hvd.v3')), findsOneWidget);
          expect(find.byKey(const Key('book-hathitrust:hvd.v4')), findsNothing);
          final button = find.byKey(const Key('show-all-hathitrust'));
          expect(button, findsOneWidget);
          expect(find.descendant(of: button, matching: find.text('Show all 20 HathiTrust volumes')),
              findsOneWidget);
        });

        testWidgets('the button shows every volume and goes away', (tester) async {
          await openWithVolumes(tester, 20);
          final button = find.byKey(const Key('show-all-hathitrust'));
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(volumeCards, findsNWidgets(20));
          expect(find.byKey(const Key('show-all-hathitrust')), findsNothing);
        });

        testWidgets('the button comes right after the last volume shown', (tester) async {
          await openWithVolumes(tester, 20);
          final third = tester.getTopLeft(find.byKey(const Key('book-hathitrust:hvd.v3'))).dy;
          final button = tester.getTopLeft(find.byKey(const Key('show-all-hathitrust'))).dy;
          expect(button, greaterThan(third));
        });

        testWidgets('3 volumes or fewer need no button', (tester) async {
          await openWithVolumes(tester, 3);
          expect(volumeCards, findsNWidgets(3));
          expect(find.byKey(const Key('show-all-hathitrust')), findsNothing);
        });

        testWidgets('other sources are never cut', (tester) async {
          await openWithVolumes(tester, 20);
          expect(find.byKey(const Key('book-librivox:253')), findsOneWidget);
          expect(find.byKey(const Key('book-gutenberg:1342')), findsOneWidget);
        });
      });

      testWidgets('open the reader through the book button', (tester) async {
        final env = await TestEnv.create();
        final json = loadJson('search_response.json') as Map<String, dynamic>;
        (json['works'][0]['books'] as List).add({
          'source': 'hathitrust', 'source_id': 'hvd.hx66p3', 'title': 'Pride and prejudice',
          'authors': ['Jane Austen'], 'language': 'en', 'format': 'text',
          'url': 'https://babel.hathitrust.org/cgi/pt?id=hvd.hx66p3', 'access': 'open',
          'reading': {'mode': 'external', 'kind': null, 'url': 'https://babel.hathitrust.org/cgi/pt?id=hvd.hx66p3'},
        });
        env.api.response = SearchResponse.fromJson(json);
        await pumpApp(tester, env);
        await openDetails(tester, 'w-pride');
        final button = find.byKey(const Key('open-hathitrust:hvd.hx66p3'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(env.urls.opened.last.toString(), 'https://babel.hathitrust.org/cgi/pt?id=hvd.hx66p3');
      });
    });

    testWidgets('explains how each book can be accessed', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-quijote');
      expect(find.textContaining('Borrow'), findsWidgets);
    });

    testWidgets('says once that reading needs a connection (persona round one)', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      expect(find.byKey(const Key('offline-note')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('offline-note'))).data,
          "You need an internet connection to read or listen. Books can't be saved for offline use yet.");
    });

    testWidgets('each book links to the source page', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openDetails(tester, 'w-pride');
      final link = find.byKey(const Key('source-link-gutenberg:1342'));
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(env.urls.opened.single.toString(), 'https://www.gutenberg.org/ebooks/1342');
    });
  });

  group('getting to the book', () {
    testWidgets('a text book that can be read in the app opens the reader', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      expect(find.byKey(const Key('reader-page')), findsOneWidget);
      expect(env.engines.last.opens.single.book.url, contains('gutenberg.org/ebooks/1342.html'));
    });

    testWidgets('an audiobook opens the player', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'librivox:253');
      expect(find.byKey(const Key('audio-page')), findsOneWidget);
    });

    testWidgets('a DOAB pdf opens the reader with the pdf viewer', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-kinder', 'doab:20.500.12854/95506');
      expect(find.byKey(const Key('pdf-viewer')), findsOneWidget);
    });

    testWidgets('a book that cannot be read in the app opens at its source', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-quijote', 'openlibrary:OL503666W');
      expect(env.urls.opened.single.toString(), 'https://openlibrary.org/works/OL503666W');
      expect(find.byKey(const Key('reader-page')), findsNothing);
      expect(find.byKey(const Key('details-page')), findsOneWidget);
    });

    testWidgets('the button name says where it goes', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      await openDetails(tester, 'w-pride');
      final button = find.byKey(const Key('open-openlibrary:OL66554W'));
      await tester.ensureVisible(button);
      expect(tester.getSemantics(button),
          containsSemantics(isButton: true, label: 'View Pride and Prejudice by Jane Austen at Open Library'));
    });
  });

  group('the results-page button goes straight to the best way in', () {
    testWidgets('prefers reading in the app', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await tester.tap(find.byKey(const Key('open-w-pride')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-page')), findsOneWidget);
    });

    testWidgets('falls back to the source when the app cannot show it', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await tester.ensureVisible(find.byKey(const Key('open-w-quijote')));
      await tester.tap(find.byKey(const Key('open-w-quijote')));
      await tester.pumpAndSettle();
      expect(env.urls.opened.single.toString(), 'https://openlibrary.org/works/OL503666W');
    });
  });

  group('navigation', () {
    testWidgets('going back returns to the results with the same query', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openDetails(tester, 'w-pride');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('results-page')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('search-field'))).controller!.text, 'pride');
    });
  });
}
