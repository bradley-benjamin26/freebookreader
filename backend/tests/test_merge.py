"""Data Merging rules from spec.md.

Pass 1: shared ID (ISBN or OCLC number).  Pass 2: exact title + author.
Pass 3: fuzzy title + author.
- Records in different languages are never merged.
- Narrators and other non-author contributors are not used for matching.
- An ambiguous fuzzy match is not merged: a duplicate beats a false merge.
"""
import random

import pytest

from app.merge import merge_books
from tests.factories import make_book


def book(source, source_id, title, authors=(), **kw):
    return make_book(source=source, source_id=source_id, title=title,
                     authors=list(authors), **kw)


def groups(works):
    """Work membership as a set of frozensets of (source, source_id)."""
    return {frozenset((b.source, b.source_id) for b in w.books) for w in works}


def merged(*pairs):
    return frozenset(pairs)


class TestBasics:
    def test_no_books_no_works(self):
        assert merge_books([]) == []

    def test_a_single_book_is_its_own_work(self):
        works = merge_books([book("gutenberg", "1", "Emma", ["Jane Austen"])])
        assert len(works) == 1
        assert works[0].books[0].source_id == "1"

    def test_unrelated_books_stay_separate(self):
        works = merge_books([
            book("gutenberg", "1", "Emma", ["Jane Austen"]),
            book("gutenberg", "2", "Hamlet", ["William Shakespeare"]),
        ])
        assert len(works) == 2

    def test_every_input_book_lands_in_exactly_one_work(self):
        books = [book("gutenberg", str(i), f"Title {i}", [f"Author {i % 3}"]) for i in range(12)]
        works = merge_books(books)
        members = [(b.source, b.source_id) for w in works for b in w.books]
        assert sorted(members) == sorted((b.source, b.source_id) for b in books)

    def test_input_order_does_not_change_the_result(self):
        books = [
            book("gutenberg", "1342", "Pride and Prejudice", ["Jane Austen"]),
            book("librivox", "253", "Pride and Prejudice", ["Jane Austen"], format="audio"),
            book("openlibrary", "OL1W", "Pride & Prejudice", ["Jane Austen"],
                 identifiers={"isbn": ["9780140430721"]}),
            book("doab", "9", "Pride and Prejudice", ["Jane Austen"],
                 identifiers={"isbn": ["9780140430721"]}),
            book("gutenberg", "11", "Alice's Adventures in Wonderland", ["Lewis Carroll"]),
        ]
        expected = groups(merge_books(books))
        ids = {frozenset(b.source_id for b in w.books): w.id for w in merge_books(books)}
        for seed in range(5):
            shuffled = books[:]
            random.Random(seed).shuffle(shuffled)
            again = merge_books(shuffled)
            assert groups(again) == expected
            assert {frozenset(b.source_id for b in w.books): w.id for w in again} == ids


class TestPass1Identifiers:
    def test_shared_isbn_merges_even_when_titles_differ(self):
        works = merge_books([
            book("openlibrary", "OL1W", "Pride and Prejudice", ["Jane Austen"],
                 identifiers={"isbn": ["9780140430721"]}),
            book("doab", "20.5/1", "Pride and Prejudice (Penguin Classics)", ["J. Austen"],
                 identifiers={"isbn": ["9780140430721", "9780000000002"]}),
        ])
        assert len(works) == 1

    def test_shared_oclc_merges(self):
        works = merge_books([
            book("openlibrary", "OL1W", "Title One", ["A One"], identifiers={"oclc": ["18103615"]}),
            book("doab", "20.5/1", "Totally Different", ["B Two"], identifiers={"oclc": ["18103615"]}),
        ])
        assert len(works) == 1

    def test_identifier_matches_chain(self):
        a = book("openlibrary", "A", "One", ["X"], identifiers={"isbn": ["9780140430721"]})
        b = book("doab", "B", "Two", ["Y"], identifiers={"isbn": ["9780140430721"], "oclc": ["1"]})
        c = book("openlibrary", "C", "Three", ["Z"], identifiers={"oclc": ["1"]})
        assert len(merge_books([a, b, c])) == 1

    def test_different_isbns_alone_do_not_merge(self):
        works = merge_books([
            book("openlibrary", "A", "Alpha", ["Ann One"], identifiers={"isbn": ["9780140430721"]}),
            book("doab", "B", "Omega", ["Bob Two"], identifiers={"isbn": ["9781134215645"]}),
        ])
        assert len(works) == 2

    def test_isbn_and_oclc_values_are_not_interchangeable(self):
        works = merge_books([
            book("openlibrary", "A", "Alpha", ["Ann One"], identifiers={"oclc": ["123456789"]}),
            book("doab", "B", "Omega", ["Bob Two"], identifiers={"isbn": ["123456789"]}),
        ])
        assert len(works) == 2

    def test_same_isbn_in_different_languages_is_not_merged(self):
        works = merge_books([
            book("openlibrary", "A", "Don Quijote", ["Miguel de Cervantes"], language="es",
                 identifiers={"isbn": ["9780140430721"]}),
            book("doab", "B", "Don Quixote", ["Miguel de Cervantes"], language="en",
                 identifiers={"isbn": ["9780140430721"]}),
        ])
        assert len(works) == 2

    def test_unknown_language_can_still_merge_on_identifier(self):
        works = merge_books([
            book("openlibrary", "A", "Pride and Prejudice", ["Jane Austen"], language=None,
                 identifiers={"isbn": ["9780140430721"]}),
            book("doab", "B", "Pride and Prejudice", ["Jane Austen"], language="en",
                 identifiers={"isbn": ["9780140430721"]}),
        ])
        assert len(works) == 1


class TestPass2ExactTitleAndAuthor:
    def test_text_and_audio_of_the_same_book_merge(self):
        works = merge_books([
            book("gutenberg", "1342", "Pride and Prejudice", ["Jane Austen"]),
            book("librivox", "253", "Pride and Prejudice", ["Jane Austen"], format="audio"),
        ])
        assert len(works) == 1
        assert {b.source for b in works[0].books} == {"gutenberg", "librivox"}

    @pytest.mark.parametrize("title_b, authors_b", [
        ("pride and prejudice", ["Jane Austen"]),
        ("Pride & Prejudice", ["Jane Austen"]),
        ("The Pride and Prejudice", ["Jane Austen"]),
        ("Pride and Prejudice.", ["Austen, Jane"]),
        ("Pride and Prejudice", ["JANE AUSTEN"]),
    ])
    def test_formatting_differences_still_match_exactly(self, title_b, authors_b):
        works = merge_books([
            book("gutenberg", "1", "Pride and Prejudice", ["Jane Austen"]),
            book("librivox", "2", title_b, authors_b, format="audio"),
        ])
        assert len(works) == 1

    def test_same_title_different_author_is_not_merged(self):
        works = merge_books([
            book("gutenberg", "1", "Hamlet", ["William Shakespeare"]),
            book("doab", "2", "Hamlet", ["Someone Else"]),
        ])
        assert len(works) == 2

    def test_same_author_different_title_is_not_merged(self):
        works = merge_books([
            book("gutenberg", "1", "Emma", ["Jane Austen"]),
            book("gutenberg", "2", "Persuasion", ["Jane Austen"]),
        ])
        assert len(works) == 2

    def test_multiple_authors_match_regardless_of_order(self):
        works = merge_books([
            book("gutenberg", "1", "Good Omens", ["Terry Pratchett", "Neil Gaiman"]),
            book("openlibrary", "2", "Good Omens", ["Neil Gaiman", "Terry Pratchett"]),
        ])
        assert len(works) == 1

    def test_different_languages_are_never_merged(self):
        works = merge_books([
            book("gutenberg", "1", "Les Misérables", ["Victor Hugo"], language="fr"),
            book("gutenberg", "2", "Les Misérables", ["Victor Hugo"], language="en"),
        ])
        assert len(works) == 2

    def test_unknown_language_is_not_merged_without_an_identifier(self):
        works = merge_books([
            book("gutenberg", "1", "Emma", ["Jane Austen"], language="en"),
            book("openlibrary", "2", "Emma", ["Jane Austen"], language=None),
        ])
        assert len(works) == 2


class TestNonAuthorContributorsAreIgnored:
    def test_same_narrator_does_not_join_different_books(self):
        works = merge_books([
            book("librivox", "1", "Persuasion", ["Jane Austen"], format="audio",
                 narrators=["Karen Savage"]),
            book("librivox", "2", "Walden", ["Henry David Thoreau"], format="audio",
                 narrators=["Karen Savage"]),
        ])
        assert len(works) == 2

    def test_different_narrators_do_not_split_the_same_book(self):
        works = merge_books([
            book("librivox", "1", "Emma", ["Jane Austen"], format="audio", narrators=["Ann"]),
            book("librivox", "2", "Emma", ["Jane Austen"], format="audio", narrators=["Bob"]),
            book("gutenberg", "3", "Emma", ["Jane Austen"]),
        ])
        assert len(works) == 1

    def test_a_narrator_with_an_authors_name_is_not_an_author(self):
        works = merge_books([
            book("gutenberg", "1", "Sonnets", ["William Shakespeare"]),
            book("librivox", "2", "Sonnets", [], format="audio", narrators=["William Shakespeare"]),
        ])
        assert len(works) == 2

    def test_translators_and_editors_are_not_used(self):
        works = merge_books([
            book("gutenberg", "1", "Poems", ["Emily Dickinson"], contributors=["Mabel Todd"]),
            book("gutenberg", "2", "Letters", ["Mabel Todd"], contributors=["Emily Dickinson"]),
        ])
        assert len(works) == 2


class TestPass3Fuzzy:
    def test_typo_in_title_with_same_author_merges(self):
        works = merge_books([
            book("gutenberg", "1", "Great Expectations", ["Charles Dickens"]),
            book("doab", "2", "Great Expectation", ["Charles Dickens"]),
        ])
        assert len(works) == 1

    def test_transliterated_author_with_same_title_merges(self):
        works = merge_books([
            book("gutenberg", "1", "Crime and Punishment", ["Fyodor Dostoevsky"]),
            book("librivox", "2", "Crime and Punishment", ["Fyodor Dostoyevsky"], format="audio"),
        ])
        assert len(works) == 1

    def test_misspelled_surname_merges(self):
        works = merge_books([
            book("gutenberg", "1", "Poems", ["Mary Shelley"]),
            book("doab", "2", "Poems", ["Mary Shelly"]),
        ])
        assert len(works) == 1

    @pytest.mark.parametrize("first, second", [
        ("John Smith", "Joan Smith"),          # given names differ: different people
        ("Thomas Hardy", "Thomas Harding"),    # surnames too far apart
        ("Mary Shelley", "Mary W. Shelley"),   # different number of name parts
    ])
    def test_different_people_with_similar_names_do_not_merge(self, first, second):
        works = merge_books([
            book("gutenberg", "1", "Poems", [first]),
            book("doab", "2", "Poems", [second]),
        ])
        assert len(works) == 2

    def test_similar_author_but_unrelated_title_does_not_merge(self):
        works = merge_books([
            book("gutenberg", "1", "Pride and Prejudice", ["Jane Austen"]),
            book("gutenberg", "2", "Sense and Sensibility", ["Jane Austen"]),
        ])
        assert len(works) == 2

    def test_fuzzy_never_crosses_languages(self):
        works = merge_books([
            book("gutenberg", "1", "Great Expectations", ["Charles Dickens"], language="en"),
            book("gutenberg", "2", "Great Expectation", ["Charles Dickens"], language="fr"),
        ])
        assert len(works) == 2

    def test_numbered_volumes_are_not_fuzzy_merged(self):
        works = merge_books([
            book("gutenberg", "1", "Les misérables Tome I: Fantine", ["Victor Hugo"], language="fr"),
            book("gutenberg", "2", "Les misérables Tome V: Jean Valjean", ["Victor Hugo"], language="fr"),
        ])
        assert len(works) == 2

    def test_records_without_authors_never_merge_on_title_alone(self):
        """'Poems' or 'Letters' with no author is far too generic to trust."""
        works = merge_books([
            book("gutenberg", "1", "Letters", []),
            book("doab", "2", "Letters", []),
        ])
        assert len(works) == 2

    def test_ambiguous_match_is_left_unmerged(self):
        """The authorless 'Poems' fits two different authors' works equally well."""
        a = book("gutenberg", "1", "Poems", ["Emily Dickinson"])
        b = book("gutenberg", "2", "Poems", ["Walt Whitman"])
        x = book("doab", "3", "Poems", [])
        works = merge_books([a, b, x])
        assert groups(works) == {merged(("gutenberg", "1")), merged(("gutenberg", "2")),
                                 merged(("doab", "3"))}


class TestWorkFields:
    @pytest.fixture
    def work(self):
        works = merge_books([
            book("gutenberg", "1342", "Pride and Prejudice", ["Jane Austen"],
                 cover_url="https://g/cover.jpg", url="https://www.gutenberg.org/ebooks/1342"),
            book("librivox", "253", "Pride and Prejudice", ["Jane Austen"], format="audio",
                 audio_seconds=47204, cover_url="https://l/cover.jpg",
                 url="https://librivox.org/pride/", identifiers={"gutenberg": ["1342"]}),
            book("openlibrary", "OL66554W", "Pride and Prejudice", ["Jane Austen"],
                 identifiers={"isbn": ["9780140430721"], "oclc": ["18103615"]},
                 url="https://openlibrary.org/works/OL66554W"),
        ])
        assert len(works) == 1
        return works[0]

    def test_id_is_a_stable_non_empty_string(self, work):
        assert isinstance(work.id, str) and work.id

    def test_title_authors_language(self, work):
        assert work.title == "Pride and Prejudice"
        assert work.authors == ["Jane Austen"]
        assert work.language == "en"

    def test_sources_and_source_ids(self, work):
        assert work.sources == ["gutenberg", "librivox", "openlibrary"]
        assert work.source_ids == {"gutenberg": ["1342"], "librivox": ["253"],
                                   "openlibrary": ["OL66554W"]}

    def test_identifiers_are_the_union(self, work):
        assert work.identifiers["isbn"] == ["9780140430721"]
        assert work.identifiers["oclc"] == ["18103615"]
        assert work.identifiers["gutenberg"] == ["1342"]

    def test_urls_and_cover(self, work):
        assert set(work.urls) == {"https://www.gutenberg.org/ebooks/1342",
                                  "https://librivox.org/pride/",
                                  "https://openlibrary.org/works/OL66554W"}
        assert work.cover_url in {"https://g/cover.jpg", "https://l/cover.jpg"}

    def test_formats_summarize_the_books(self, work):
        assert work.formats == ["audio", "text"]

    def test_books_are_kept_under_the_work(self, work):
        assert len(work.books) == 3

    def test_work_without_a_cover_has_none(self):
        works = merge_books([book("gutenberg", "1", "Emma", ["Jane Austen"])])
        assert works[0].cover_url is None

    def test_authors_are_unique_when_spelled_differently(self):
        works = merge_books([
            book("gutenberg", "1", "Emma", ["Jane Austen"]),
            book("librivox", "2", "Emma", ["Austen, Jane"], format="audio"),
        ])
        assert len(works[0].authors) == 1
