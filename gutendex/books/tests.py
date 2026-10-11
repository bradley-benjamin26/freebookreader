"""Regression tests for the self-hosted Gutendex API.

These document the behavior the Free Book Reader backend relies on
(see api_gutendex.documentation.md). They build their own small catalog, so
they never touch the real database; Django creates a throwaway test database.

Run: python manage.py test books
"""
from django.test import TestCase

from .models import Book, Bookshelf, Format, Language, Person, Subject, Summary


def make_book(gutenberg_id, title, *, authors=(), languages=('en',),
              downloads=100, media_type='Text', copyright=False,
              formats=None, subjects=(), bookshelves=(), summary=None,
              translators=()):
    book = Book.objects.create(
        gutenberg_id=gutenberg_id, title=title, download_count=downloads,
        media_type=media_type, copyright=copyright)
    for name, birth, death in authors:
        person, _ = Person.objects.get_or_create(
            name=name, birth_year=birth, death_year=death)
        book.authors.add(person)
    for name, birth, death in translators:
        person, _ = Person.objects.get_or_create(
            name=name, birth_year=birth, death_year=death)
        book.translators.add(person)
    for code in languages:
        language, _ = Language.objects.get_or_create(code=code)
        book.languages.add(language)
    for name in subjects:
        subject, _ = Subject.objects.get_or_create(name=name)
        book.subjects.add(subject)
    for name in bookshelves:
        shelf, _ = Bookshelf.objects.get_or_create(name=name)
        book.bookshelves.add(shelf)
    for mime_type, url in (formats or {
            'text/html': f'https://www.gutenberg.org/ebooks/{gutenberg_id}.html.images'}).items():
        Format.objects.create(book=book, mime_type=mime_type, url=url)
    if summary:
        Summary.objects.create(book=book, text=summary)
    return book


DICKENS = ('Dickens, Charles', 1812, 1870)
AUSTEN = ('Austen, Jane', 1775, 1817)
HUGO = ('Hugo, Victor', 1802, 1885)


class CatalogTestCase(TestCase):
    @classmethod
    def setUpTestData(cls):
        make_book(1342, 'Pride and Prejudice', authors=[AUSTEN], downloads=900,
                  subjects=['Courtship -- Fiction'],
                  bookshelves=['Category: Novels'],
                  summary='A novel of manners.',
                  formats={
                      'text/html': 'https://www.gutenberg.org/ebooks/1342.html.images',
                      'application/epub+zip': 'https://www.gutenberg.org/ebooks/1342.epub3.images',
                      'image/jpeg': 'https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg',
                  })
        make_book(1400, 'Great Expectations', authors=[DICKENS], downloads=500,
                  subjects=['Orphans -- Fiction'],
                  bookshelves=["Children's Literature"])
        make_book(8608, 'Great Expectations', authors=[DICKENS], downloads=50,
                  media_type='Sound',
                  formats={'audio/mpeg': 'https://www.gutenberg.org/files/8608/8608-1.mp3'})
        make_book(17489, 'Les misérables Tome I: Fantine', authors=[HUGO],
                  languages=('fr',), downloads=300,
                  translators=[('Wraxall, Lascelles', None, None)])
        make_book(5000, 'Bilingual Reader', languages=('en', 'fi'), downloads=10,
                  copyright=True)
        make_book(6000, 'Unknown Copyright Status', downloads=5, copyright=None)
        # Never listed: the view excludes books without a title or download count.
        make_book(7000, None, downloads=999)
        make_book(7001, 'No Download Count', downloads=None)


class ListBooksTests(CatalogTestCase):
    def get(self, query=''):
        return self.client.get('/books/' + query)

    def test_response_is_a_paginated_envelope(self):
        body = self.get().json()
        self.assertEqual(set(body), {'count', 'next', 'previous', 'results'})
        self.assertIsNone(body['next'])
        self.assertIsNone(body['previous'])

    def test_books_without_title_or_download_count_are_hidden(self):
        ids = [b['id'] for b in self.get().json()['results']]
        self.assertNotIn(7000, ids)
        self.assertNotIn(7001, ids)
        self.assertEqual(self.get().json()['count'], 6)

    def test_default_order_is_most_downloaded_first(self):
        ids = [b['id'] for b in self.get().json()['results']]
        self.assertEqual(ids, [1342, 1400, 17489, 8608, 5000, 6000])

    def test_sort_ascending_and_descending_follow_row_order(self):
        asc = [b['id'] for b in self.get('?sort=ascending').json()['results']]
        desc = [b['id'] for b in self.get('?sort=descending').json()['results']]
        self.assertEqual(asc, [1342, 1400, 8608, 17489, 5000, 6000])
        self.assertEqual(desc, list(reversed(asc)))

    def test_book_object_has_the_documented_fields(self):
        book = self.get('?ids=1342').json()['results'][0]
        self.assertEqual(set(book), {
            'id', 'title', 'authors', 'summaries', 'editors', 'translators',
            'subjects', 'bookshelves', 'languages', 'copyright', 'media_type',
            'formats', 'download_count'})
        self.assertEqual(book['id'], 1342)
        self.assertEqual(book['authors'], [
            {'name': 'Austen, Jane', 'birth_year': 1775, 'death_year': 1817}])
        self.assertEqual(book['languages'], ['en'])
        self.assertEqual(book['summaries'], ['A novel of manners.'])
        self.assertEqual(book['formats']['application/epub+zip'],
                         'https://www.gutenberg.org/ebooks/1342.epub3.images')
        self.assertIn('image/jpeg', book['formats'])

    def test_translators_are_separate_from_authors(self):
        book = self.get('?ids=17489').json()['results'][0]
        self.assertEqual([a['name'] for a in book['authors']], ['Hugo, Victor'])
        self.assertEqual([t['name'] for t in book['translators']],
                         ['Wraxall, Lascelles'])

    def test_page_size_is_32_and_next_link_is_built(self):
        for i in range(40):
            make_book(100000 + i, f'Filler {i}', downloads=1)
        body = self.get().json()
        self.assertEqual(len(body['results']), 32)
        self.assertEqual(body['count'], 46)
        self.assertIn('page=2', body['next'])
        second = self.get('?page=2').json()
        self.assertEqual(len(second['results']), 14)
        self.assertIsNone(second['next'])
        self.assertIsNotNone(second['previous'])

    def test_page_past_the_end_is_404(self):
        response = self.get('?search=x&page=999')
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json(), {'detail': 'Invalid page.'})


class SearchTests(CatalogTestCase):
    def ids(self, query):
        response = self.client.get('/books/' + query)
        self.assertEqual(response.status_code, 200)
        return [b['id'] for b in response.json()['results']]

    def test_search_matches_title(self):
        self.assertEqual(self.ids('?search=pride'), [1342])

    def test_search_matches_author_name(self):
        self.assertEqual(self.ids('?search=austen'), [1342])

    def test_search_is_case_insensitive(self):
        self.assertEqual(self.ids('?search=PRIDE'), [1342])

    def test_all_words_must_match_across_title_and_author(self):
        self.assertEqual(self.ids('?search=dickens%20great'), [1400, 8608])
        self.assertEqual(self.ids('?search=austen%20great'), [])

    def test_search_matches_accented_titles_by_substring(self):
        self.assertEqual(self.ids('?search=mis%C3%A9rables'), [17489])

    def test_isbn_search_is_not_supported(self):
        # Gutenberg records carry no ISBNs; this is why the merge step
        # can only use title and author for Gutenberg.
        self.assertEqual(self.ids('?search=9780141439518'), [])

    def test_topic_matches_subjects_and_bookshelves(self):
        self.assertEqual(self.ids('?topic=orphans'), [1400])
        self.assertEqual(self.ids('?topic=children'), [1400])
        self.assertEqual(self.ids('?topic=novels'), [1342])

    def test_languages_filter(self):
        self.assertEqual(self.ids('?languages=fr'), [17489])

    def test_multiple_languages_are_ored(self):
        self.assertEqual(self.ids('?languages=fr,fi'), [17489, 5000])

    def test_book_in_two_languages_is_listed_once(self):
        self.assertEqual(self.ids('?languages=en,fi').count(5000), 1)

    def test_mime_type_audio_returns_only_sound_books(self):
        self.assertEqual(self.ids('?mime_type=audio'), [8608])

    def test_mime_type_is_a_prefix_match(self):
        self.assertEqual(self.ids('?mime_type=application/epub'), [1342])

    def test_ids_filter(self):
        self.assertEqual(sorted(self.ids('?ids=1342,1400')), [1342, 1400])

    def test_copyright_filter(self):
        self.assertEqual(self.ids('?copyright=true'), [5000])
        self.assertEqual(self.ids('?copyright=null'), [6000])
        self.assertNotIn(5000, self.ids('?copyright=false'))

    def test_author_year_range(self):
        self.assertEqual(sorted(self.ids('?author_year_start=1800&author_year_end=1899&search=hugo')),
                         [17489])

    def test_different_parameters_are_anded(self):
        self.assertEqual(self.ids('?search=great&mime_type=audio'), [8608])
        self.assertEqual(self.ids('?search=great&languages=fr'), [])


class SingleBookTests(CatalogTestCase):
    def test_get_by_gutenberg_id(self):
        response = self.client.get('/books/1342/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['title'], 'Pride and Prejudice')

    def test_unknown_id_is_404(self):
        response = self.client.get('/books/99999999/')
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json(), {'detail': 'No Book matches the given query.'})


class HttpBehaviorTests(CatalogTestCase):
    def test_missing_trailing_slash_redirects(self):
        self.assertEqual(self.client.get('/books').status_code, 301)

    def test_api_is_read_only(self):
        self.assertEqual(self.client.post('/books/', {'title': 'x'}).status_code, 403)
        self.assertEqual(self.client.delete('/books/1342/').status_code, 403)
        self.assertEqual(self.client.put('/books/1342/', {'title': 'x'},
                                         content_type='application/json').status_code, 403)

    def test_head_and_options_are_allowed(self):
        self.assertEqual(self.client.head('/books/').status_code, 200)
        self.assertEqual(self.client.options('/books/').status_code, 200)

    def test_cors_allows_any_origin(self):
        response = self.client.get('/books/', HTTP_ORIGIN='https://example.org')
        self.assertEqual(response['Access-Control-Allow-Origin'], '*')
