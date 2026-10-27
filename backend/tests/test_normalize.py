"""Pure helpers that make records from different sources comparable."""
import pytest

from app.normalize import (
    author_key, normalize_author_name, normalize_isbn, normalize_oclc,
    title_key, title_matches, to_language_code, to_marc_language, unique,
)


class TestAuthorDisplayName:
    @pytest.mark.parametrize("raw, expected", [
        ("Dickens, Charles", "Charles Dickens"),
        ("Carroll, Lewis", "Lewis Carroll"),
        ("Charles Dickens", "Charles Dickens"),
        ("Plato", "Plato"),
        ("  Austen,   Jane ", "Jane Austen"),
        ("vieri, marco", "Marco Vieri"),
        ("SARRI, Daniele", "Daniele Sarri"),
        ("Beethoven, Ludwig van", "Ludwig van Beethoven"),
        ("McDonald, Ronald", "Ronald McDonald"),
        ("Kara Shallenberg (1969-2023)", "Kara Shallenberg"),
        ("Dickens, Charles, 1812-1870", "Charles Dickens"),
        # A suffix after a comma is not a given name: "First Last, Jr." is already in display order.
        ("Charles Dickens, Jr.", "Charles Dickens Jr."),
        ("Dickens, Charles, Jr.", "Charles Dickens Jr."),
        ("Dickens, Charles Jr.", "Charles Dickens Jr."),
        ("King, Martin Luther, Jr., 1929-1968", "Martin Luther King Jr."),
        ("Henry Ford, II", "Henry Ford II"),
        ("henry ford ii", "Henry Ford II"),
        ("Nguyen Vi", "Nguyen Vi"),
        ("Vi Nguyen", "Vi Nguyen"),
        ("Smith, V.", "V. Smith"),                     # a single letter is an initial, not "V" the numeral
        ("Jr.", "Jr."),
        ("", ""),
    ])
    def test_normalize_author_name(self, raw, expected):
        assert normalize_author_name(raw) == expected


class TestAuthorKey:
    @pytest.mark.parametrize("a, b", [
        ("Dickens, Charles", "Charles Dickens"),
        ("CHARLES DICKENS", "charles dickens"),
        ("Charles  Dickens.", "Charles Dickens"),
        ("J. R. R. Tolkien", "J.R.R. Tolkien"),
        ("Tolkien, J. R. R.", "J.R.R. Tolkien"),
        ("Gabriel García Márquez", "Gabriel Garcia Marquez"),
        ("SARRI, Daniele", "Daniele Sarri"),
        ("Charles Dickens, Jr.", "Charles Dickens Jr."),
        ("Dickens, Charles, Jr.", "Charles Dickens Jr"),
    ])
    def test_same_person_same_key(self, a, b):
        assert author_key(a) == author_key(b)

    @pytest.mark.parametrize("a, b", [
        ("Charles Dickens", "Charles Darwin"),
        ("Jane Austen", "Jane Austin"),
        ("Charles Dickens", "Charles Dickens Jr"),
        ("Charles Dickens", "Charles Dickens, Jr."),
    ])
    def test_different_people_different_key(self, a, b):
        assert author_key(a) != author_key(b)


class TestTitleKey:
    @pytest.mark.parametrize("a, b", [
        ("Pride and Prejudice", "pride and prejudice"),
        ("Pride & Prejudice", "Pride and Prejudice"),
        ("The Adventures of Tom Sawyer", "Adventures of Tom Sawyer"),
        ("Alice's Adventures in Wonderland", "Alices Adventures in Wonderland"),
        ("Alice’s Adventures in Wonderland", "Alice's Adventures in Wonderland"),
        ("Great Expectations.", "Great  Expectations"),
        ("Les misérables", "Les miserables"),
        ("An Essay on Man", "Essay on Man"),
        # LibriVox numbers repeat recordings of a book; they are the same title.
        ("The Time Machine", "Time Machine (Version 4)"),
        ("Pride and Prejudice", "Pride and Prejudice (version 6, dramatic reading)"),
        ("Christmas Carol", "Christmas Carol (version 02)"),
    ])
    def test_equivalent_titles_share_a_key(self, a, b):
        assert title_key(a) == title_key(b)

    @pytest.mark.parametrize("a, b", [
        ("Hamlet", "Macbeth"),
        ("Pride and Prejudice", "Pride and Prejudice and Zombies"),
        ("Les misérables Tome I", "Les misérables Tome II"),
        ("Barnaby Rudge (NL)", "Barnaby Rudge"),          # only "(version N...)" is dropped
    ])
    def test_different_titles_have_different_keys(self, a, b):
        assert title_key(a) != title_key(b)


class TestTitleMatches:
    """Known-item title search (review 2026-10-10, #5, option B chosen by the user): a title matches
    with or without its subtitle, but a subtitle that marks a study aid is a different book."""

    @pytest.mark.parametrize("wanted, title", [
        ("Moby Dick", "Moby-Dick; or, The Whale"),
        ("Frankenstein", "Frankenstein; Or, The Modern Prometheus"),
        ("Emile", "Emile, or On Education"),
        ("Black Beauty", "Black Beauty: The autobiography of a horse"),
        ("Black Beauty: The autobiography of a horse", "Black Beauty"),   # subtitle in the query
        ("Moby Dick; or, The Whale", "Moby Dick"),
        ("Great Expectations", "Great Expectations"),
        ("great expectations!", "Great Expectations"),
        ("Pride and Prejudice", "Pride and Prejudice (version 6, dramatic reading)"),
        # A volume of the work is the work.
        ("Les Misérables", "Les misérables Tome I: Fantine"),
        ("Les Misérables", "Misérables - tome 1"),
        ("War and Peace", "War and Peace, Volume 2"),
        ("Les misérables Tome I", "Les misérables Tome I: Fantine"),
        # Asking for the study guide by name still finds it.
        ("Great Expectations: A Study Guide", "Great Expectations: A Study Guide"),
    ])
    def test_matches(self, wanted, title):
        assert title_matches(title, wanted)

    @pytest.mark.parametrize("wanted, title", [
        ("Great Expectations", "Great Expectations: A Study Guide"),
        ("Great Expectations", "Great Expectations: Summary and Analysis"),
        ("Great Expectations", "Great Expectations (SparkNotes Literature Guide)"),
        ("Great Expectations", "Great Expectations - CliffsNotes"),
        ("Hamlet", "Hamlet: A Reader's Companion"),
        ("Hamlet", "Hamlet: Notes"),
        ("Hamlet", "Hamlet; Critical Essays and Commentary"),
        ("Pride and Prejudice", "Pride and Prejudice and Zombies"),
        ("Hamlet", "Macbeth"),
        ("Les misérables Tome I", "Les misérables Tome II: Cosette"),   # a named volume is that volume
        ("To Be", "To Be or Not to Be"),                                 # a bare " or " is not a subtitle
    ])
    def test_does_not_match(self, wanted, title):
        assert not title_matches(title, wanted)


class TestIsbn:
    @pytest.mark.parametrize("raw, expected", [
        ("9780140430721", "9780140430721"),
        ("978-0-14-043072-1", "9780140430721"),
        ("0140430725", "9780140430721"),          # ISBN-10 -> ISBN-13
        ("0-14-043072-5", "9780140430721"),
        ("ISBN 978 0 14 043072 1", "9780140430721"),
        ("080442957X", "9780804429573"),          # check digit X
        ("080442957x", "9780804429573"),
    ])
    def test_valid_isbns_become_isbn13(self, raw, expected):
        assert normalize_isbn(raw) == expected

    @pytest.mark.parametrize("raw", [
        "9783847406337",   # bad check digit (appeared in real OAPEN/DOAB data)
        "123", "", None, "not an isbn", "97801404307211",
    ])
    def test_invalid_isbns_are_none(self, raw):
        assert normalize_isbn(raw) is None

    @pytest.mark.parametrize("raw", [
        "9780000000002",        # on unrelated HathiTrust books; its check digit is valid
        "0000000000",           # the same number as an ISBN-10
        "000000000061rub",
        "0-00-000000-0",
    ])
    def test_the_placeholder_isbn_is_not_an_isbn(self, raw):
        assert normalize_isbn(raw) is None


class TestOclc:
    @pytest.mark.parametrize("raw, expected", [
        ("18103615", "18103615"),
        ("(OCoLC)18103615", "18103615"),
        ("ocm18103615", "18103615"),
        ("ocn018103615", "18103615"),
        (" 18103615 ", "18103615"),
    ])
    def test_oclc_numbers(self, raw, expected):
        assert normalize_oclc(raw) == expected

    @pytest.mark.parametrize("raw", ["", None, "abc"])
    def test_invalid_oclc_is_none(self, raw):
        assert normalize_oclc(raw) is None


class TestLanguageCode:
    @pytest.mark.parametrize("raw, expected", [
        ("en", "en"), ("EN", "en"), ("eng", "en"), ("fre", "fr"), ("fra", "fr"),
        ("ger", "de"), ("deu", "de"), ("ita", "it"), ("spa", "es"), ("dut", "nl"),
        ("English", "en"), ("french", "fr"), ("German", "de"), ("Italian", "it"),
    ])
    def test_known_languages(self, raw, expected):
        assert to_language_code(raw) == expected

    @pytest.mark.parametrize("raw", ["Multilingual", "und", "zzz", "", None, "Klingon"])
    def test_unknown_languages_are_none(self, raw):
        assert to_language_code(raw) is None


class TestMarcLanguageCode:
    """Open Library's `language` filter takes MARC (bibliographic) codes: fre, not fra."""

    @pytest.mark.parametrize("raw, expected", [
        ("en", "eng"), ("EN", "eng"), ("fr", "fre"), ("de", "ger"), ("es", "spa"),
        ("it", "ita"), ("nl", "dut"), ("zh", "chi"),
    ])
    def test_known_languages(self, raw, expected):
        assert to_marc_language(raw) == expected

    @pytest.mark.parametrize("raw", ["xx", "", None])
    def test_unknown_languages_are_none(self, raw):
        assert to_marc_language(raw) is None


def test_unique_keeps_first_seen_order_and_drops_empty_values():
    assert unique(["b", None, "a", "b", ""]) == ["b", "a"]
