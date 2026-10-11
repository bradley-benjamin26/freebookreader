"""HathiTrust as a search source: reads the local index, never calls HathiTrust.

Rows are real ones from the daily update file of 2026-10-11 (samples/hathitrust-hathifile-sample.tsv).
"""
import pytest

from app.hathifile import iter_changes
from app.hathitrust_index import HathiIndex, IndexState
from app.models import SearchQuery
from app.reader import reading_options
from app.sources.hathitrust import HathiIndexMissing, HathiTrustSource
from tests.test_hathifile import SAMPLE_LINES, row

STATE = IndexState("hathi_full_20261001.txt.gz", "20261001")


@pytest.fixture
def index(tmp_path):
    index = HathiIndex(tmp_path / "hathi.sqlite")
    index.replace_all([v for _, v in iter_changes(SAMPLE_LINES) if v], STATE)
    return index


@pytest.fixture
def source(index):
    return HathiTrustSource(index)


def test_source_name():
    assert HathiTrustSource.name == "hathitrust"


def test_a_missing_index_is_our_problem_not_an_outage(tmp_path):
    """Not a SourceError: that would start a 24-hour outage for a source that is simply not set up yet."""
    from app.sources.base import SourceError
    source = HathiTrustSource(HathiIndex(tmp_path / "nothing.sqlite"))
    with pytest.raises(HathiIndexMissing) as raised:
        source.search(SearchQuery(q="dickens"))
    assert not isinstance(raised.value, SourceError)
    assert "update" in str(raised.value).lower()      # says how to build it


class TestBooks:
    def one(self, source, **query):
        (book,) = source.search(SearchQuery(**query))
        return book

    def test_a_volume_becomes_a_book(self, source):
        book = self.one(source, title="Tour du monde")
        assert book.source == "hathitrust"
        assert book.source_id == "hvd.32044102775384"
        assert book.title.startswith("Le tour du monde en quatre-vingts jours")
        assert book.authors == ["Jules Verne"]
        assert book.language == "fr"
        assert book.format == "text"
        assert book.access == "open"
        assert book.url == "https://babel.hathitrust.org/cgi/pt?id=hvd.32044102775384"
        assert book.cover_url is None and book.content == {}

    def test_it_opens_in_hathitrusts_reader_through_a_link(self, source):
        book = self.one(source, title="Tour du monde")
        reading = reading_options(book)
        assert reading.mode == "external"
        assert reading.url == "https://babel.hathitrust.org/cgi/pt?id=hvd.32044102775384"

    def test_the_volume_label_and_library_tell_volumes_apart(self, source):
        books = source.search(SearchQuery(title="writings", author="dickens"))
        assert [(b.volume, b.library) for b in books] == [("v.1", "University of Michigan"),
                                                          ("v.2", "University of Michigan")]

    def test_a_single_volume_book_has_no_label(self, source):
        assert self.one(source, q="pioneering central africa").volume is None

    def test_a_library_code_we_do_not_know_is_shown_as_it_is(self, tmp_path):
        index = HathiIndex(tmp_path / "x.sqlite")
        index.replace_all([v for _, v in iter_changes([row(source="ZZZ9", title="Odd one")]) if v], STATE)
        assert self.one(HathiTrustSource(index), q="odd").library == "ZZZ9"

    @pytest.mark.parametrize("code, name", [
        ("MIU", "University of Michigan"), ("NYP", "New York Public Library"), ("HVD", "Harvard University"),
        ("UC", "University of California"), ("COO", "Cornell University"), ("NJP", "Princeton University"),
        ("UIU", "University of Illinois at Urbana-Champaign"), ("LOC", "Library of Congress"),
    ])
    def test_known_library_names(self, tmp_path, code, name):
        index = HathiIndex(tmp_path / "x.sqlite")
        index.replace_all([v for _, v in iter_changes([row(source=code, title="Odd one")]) if v], STATE)
        assert self.one(HathiTrustSource(index), q="odd").library == name

    def test_us_only_volumes_are_marked(self, source):
        books = source.search(SearchQuery(q="goethes werke"))
        assert books and all(b.us_only for b in books)
        (verne,) = source.search(SearchQuery(title="Tour du monde"))
        assert verne.us_only is False

    def test_identifiers_carry_isbn_oclc_and_the_catalog_record(self, source):
        book = self.one(source, isbn="9780813730219")
        assert book.identifiers["isbn"] == ["9780813730219"]
        assert book.identifiers["oclc"] == ["2335529", "531991"]
        assert book.identifiers["hathitrust"] == ["003916076"]

    def test_no_identifier_kind_is_empty(self, source):
        book = self.one(source, title="Tour du monde")
        assert "isbn" not in book.identifiers or book.identifiers["isbn"]
        assert all(book.identifiers.values())

    def test_a_volume_with_no_author_has_an_empty_author_list(self, tmp_path):
        index = HathiIndex(tmp_path / "x.sqlite")
        index.replace_all([v for _, v in iter_changes([row(author="", title="Nobody wrote me")]) if v], STATE)
        assert self.one(HathiTrustSource(index), q="nobody").authors == []

    def test_an_unmapped_language_is_unknown(self, source):
        assert self.one(source, q="bull run").language is None


class TestQueries:
    def test_title_and_author_are_known_item_fields(self, source):
        books = source.search(SearchQuery(title="writings", author="charles dickens"))
        assert len(books) == 2

    def test_keyword_searches_the_same_text_as_q(self, source):
        assert [b.source_id for b in source.search(SearchQuery(keyword="twain"))] == \
               [b.source_id for b in source.search(SearchQuery(q="twain"))] != []

    def test_isbn_searches_by_isbn(self, source):
        assert [b.source_id for b in source.search(SearchQuery(isbn="081373021X"))] == ["mdp.39015000388903"]

    def test_an_invalid_isbn_finds_nothing(self, source):
        assert source.search(SearchQuery(isbn="9780813730218")) == []

    def test_language_filters_in_the_index(self, source):
        assert source.search(SearchQuery(q="tour du monde", language="de")) == []
        assert len(source.search(SearchQuery(q="tour du monde", language="fr"))) == 1

    def test_audio_has_no_hathitrust_books(self, source):
        assert source.search(SearchQuery(q="dickens", format="audio")) == []

    def test_no_match_is_an_empty_list(self, source):
        assert source.search(SearchQuery(q="zzzzqqqxx")) == []

    def test_a_text_filter_still_works(self, source):
        assert source.search(SearchQuery(q="dickens", format="text"))

    def test_a_title_that_is_only_punctuation_finds_nothing(self, source):
        assert source.search(SearchQuery(title="?!")) == []


class TestPaging:
    @pytest.fixture
    def many(self, tmp_path):
        index = HathiIndex(tmp_path / "many.sqlite")
        lines = [row(htid=f"m.{n:03d}", ht_bib_key=f"{n:03d}", title="Same words") for n in range(45)]
        index.replace_all([v for _, v in iter_changes(lines) if v], STATE)
        return HathiTrustSource(index)

    def test_twenty_books_a_page(self, many):
        sizes = [len(many.search(SearchQuery(q="same words", page=p))) for p in (1, 2, 3, 4)]
        assert sizes == [20, 20, 5, 0]

    def test_pages_follow_each_other(self, many):
        ids = [b.source_id for p in (1, 2, 3) for b in many.search(SearchQuery(q="same words", page=p))]
        assert len(ids) == len(set(ids)) == 45


class TestHostileInput:
    """Odd user input returns a list; it never crashes the adapter (review 2026-10-10, #1)."""

    @pytest.mark.parametrize("fields", __import__("tests.test_hostile_inputs", fromlist=["HOSTILE"]).HOSTILE,
                             ids=lambda f: repr(f)[:40])
    def test_hostile_input_returns_a_list(self, source, fields):
        assert isinstance(source.search(SearchQuery(**fields)), list)

    @pytest.mark.parametrize("text", ['"', "OR", "title:x", "a AND", "NEAR(", "*", "'; DROP TABLE volumes; --", "\x00"])
    def test_search_syntax_is_plain_text(self, source, text):
        assert isinstance(source.search(SearchQuery(q=text)), list)
        assert isinstance(source.search(SearchQuery(title=text, author=text)), list)


class TestInTheSearchService:
    def service(self, source):
        from datetime import timedelta
        from app.outage import OutageTracker
        from app.search import SearchService
        return SearchService([source], OutageTracker(cooldown=timedelta(hours=24)))

    def test_works_group_the_volumes_of_one_record(self, source):
        response = self.service(source).search(
            SearchQuery(title="The writings of Charles Dickens", author="charles dickens"))
        (work,) = response.works
        assert work.sources == ["hathitrust"] and [b.volume for b in work.books] == ["v.1", "v.2"]
        assert work.identifiers["hathitrust"] == ["000122358"]
        assert work.authors == ["Charles Dickens"]

    def test_a_title_search_finds_a_book_whose_title_carries_the_author(self, tmp_path):
        """"Pioneering in Central Africa, by Samuel P. Verner" is a real record title."""
        index = HathiIndex(tmp_path / "x.sqlite")
        index.replace_all([v for _, v in iter_changes(SAMPLE_LINES) if v], STATE)
        response = self.service(HathiTrustSource(index)).search(
            SearchQuery(title="Pioneering in Central Africa", author="Verner"))
        assert [w.title for w in response.works] == ["Pioneering in Central Africa"]

    def test_a_missing_index_skips_the_source_without_starting_an_outage(self, tmp_path):
        from datetime import timedelta
        from app.outage import OutageTracker
        outage = OutageTracker(cooldown=timedelta(hours=24))
        from app.search import SearchService
        service = SearchService([HathiTrustSource(HathiIndex(tmp_path / "nothing.sqlite"))], outage)
        response = service.search(SearchQuery(q="dickens"))
        assert response.works == [] and response.unavailable_sources == ["hathitrust"]
        assert [(s.source, s.reason) for s in response.skipped] == [("hathitrust", "error")]
        assert outage.is_available("hathitrust")          # asked again once the index is built
