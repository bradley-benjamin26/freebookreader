"""The local index of HathiTrust volumes (SQLite with full-text search).

Search never calls HathiTrust: it reads this file (decision_hathitrust.md, decision 1).
"""
import sqlite3

import pytest

from app.hathifile import Volume, iter_changes
from app.hathitrust_index import HathiIndex, IndexState
from tests.conftest import SAMPLES
from tests.test_hathifile import SAMPLE_LINES

DICKENS = ["mdp.39015063531084", "mdp.39015063531373"]      # v.1, v.2
STATE = IndexState(full_file="hathi_full_20261001.txt.gz", updated_through="20261001")


def volume(htid="x.1", **fields) -> Volume:
    values = dict(htid=htid, rights="pd", bib_key=htid, volume=None, source="MIU", oclcs=[], isbns=[],
                  title="A title", author=None, language="eng")
    values.update(fields)
    return Volume(**values)


def kept(lines) -> list[Volume]:
    return [v for _, v in iter_changes(lines) if v is not None]


@pytest.fixture
def index(tmp_path) -> HathiIndex:
    index = HathiIndex(tmp_path / "hathi.sqlite")
    index.replace_all(kept(SAMPLE_LINES), STATE)
    return index


def htids(volumes) -> list[str]:
    return [v.htid for v in volumes]


class TestBuild:
    def test_a_missing_index_does_not_exist(self, tmp_path):
        index = HathiIndex(tmp_path / "nothing.sqlite")
        assert not index.exists()
        assert index.state() is None

    def test_a_built_index_exists_and_counts_its_volumes(self, index):
        assert index.exists()
        assert index.count() == 14

    def test_it_remembers_which_files_it_was_built_from(self, index):
        assert index.state() == STATE

    def test_an_empty_build_is_an_index_with_no_volumes(self, tmp_path):
        index = HathiIndex(tmp_path / "empty.sqlite")
        index.replace_all([], STATE)
        assert index.exists() and index.count() == 0
        assert index.search(text="anything") == []

    def test_replacing_throws_the_old_volumes_away(self, index):
        index.replace_all([volume("only.1", title="Only one")], IndexState("hathi_full_20261101.txt.gz", "20261101"))
        assert index.count() == 1
        assert htids(index.search(text="dickens")) == []
        assert index.state().full_file == "hathi_full_20261101.txt.gz"

    def test_a_failed_build_keeps_the_old_index(self, index):
        def volumes():
            yield volume("new.1")
            raise RuntimeError("download broke")
        with pytest.raises(RuntimeError):
            index.replace_all(volumes(), IndexState("hathi_full_20261101.txt.gz", "20261101"))
        assert index.count() == 14
        assert index.state() == STATE
        assert not [p for p in index.path.parent.iterdir() if p != index.path]    # no half-built file left

    def test_the_parent_folder_is_created(self, tmp_path):
        index = HathiIndex(tmp_path / "a" / "b" / "hathi.sqlite")
        index.replace_all([volume()], STATE)
        assert index.exists()


class TestSearchText:
    def test_q_finds_words_in_the_title(self, index):
        assert htids(index.search(text="writings dickens")) == DICKENS

    def test_q_finds_words_in_the_author_too(self, index):
        found = index.search(text="twain")
        assert htids(found) == ["coo1.ark:/13960/t7tm7sm8g"]

    def test_every_word_must_match(self, index):
        assert index.search(text="dickens zeppelin") == []

    def test_case_and_accents_are_ignored(self, index):
        assert htids(index.search(text="OEUVRES COMPLETES")) == htids(index.search(text="oeuvres complètes"))
        assert htids(index.search(text="goethes SÄMTLICHE werke")) != []
        assert htids(index.search(text="samtliche")) == htids(index.search(text="sämtliche")) != []

    def test_punctuation_is_ignored(self, index):
        assert htids(index.search(text="Dickens, Charles!")) == htids(index.search(text="charles dickens"))

    def test_search_syntax_is_just_text(self, index):
        """FTS5 operators must not leak: a user can type anything."""
        for text in ['"', "dickens OR", "dickens AND NOT", "title:dickens", "(", "dickens*", "NEAR(a b)",
                     "^dickens", "a - b", "'; DROP TABLE volumes; --", "\\", "{}", "col:"]:
            index.search(text=text)            # must not raise
        assert index.count() == 14

    def test_a_query_with_no_words_finds_nothing(self, index):
        assert index.search(text="!!! ???") == []

    def test_title_does_not_match_the_authors_other_names(self, index):
        """Goethe's volumes have "Johann Wolfgang von" only in the author field."""
        assert len(index.search(text="wolfgang")) == 2
        assert index.search(title="wolfgang") == []

    def test_author_only_matches_the_author(self, index):
        assert len(index.search(author="wolfgang")) == 2
        assert index.search(author="sämtliche") == []           # a word of the title
        assert htids(index.search(author="twain")) == ["coo1.ark:/13960/t7tm7sm8g"]

    def test_title_and_author_must_both_match(self, index):
        assert htids(index.search(title="writings", author="charles dickens")) == DICKENS
        assert index.search(title="writings", author="austen") == []

    def test_q_and_title_together_narrow_the_result(self, index):
        assert htids(index.search(text="dickens", title="writings")) == DICKENS
        assert index.search(text="austen", title="writings of charles") == []

    def test_the_dickens_query_returns_the_volumes_with_their_fields(self, index):
        found = index.search(title="writings", author="dickens")
        assert [v.volume for v in found] == ["v.1", "v.2"]
        first = found[0]
        assert first.title == "The writings of Charles Dickens"
        assert first.author == "Charles Dickens"
        assert first.oclcs == ["3388811"]
        assert first.language == "eng" and first.source == "MIU" and first.rights == "pd"

    def test_a_shorter_title_ranks_before_a_longer_one_with_the_same_words(self, tmp_path):
        index = HathiIndex(tmp_path / "rank.sqlite")
        index.replace_all([
            volume("a.1", bib_key="1", title="Pride and prejudice with a very long list of other things as well"),
            volume("a.2", bib_key="2", title="Pride and prejudice"),
        ], STATE)
        assert htids(index.search(title="pride and prejudice")) == ["a.2", "a.1"]


class TestStopwords:
    """Very common words are slow to match and say little, so a search with other words ignores them."""

    @pytest.fixture
    def words(self, tmp_path) -> HathiIndex:
        index = HathiIndex(tmp_path / "words.sqlite")
        index.replace_all([
            volume("a.1", bib_key="1", title="Time machine"),
            volume("a.2", bib_key="2", title="The time machine"),
            volume("a.3", bib_key="3", title="The of and"),
            volume("a.4", bib_key="4", title="Of mice and men", author="John Steinbeck"),
        ], STATE)
        return index

    def test_a_stopword_in_the_search_does_not_have_to_match(self, words):
        assert set(htids(words.search(title="the time machine"))) == {"a.1", "a.2"}

    def test_a_stopword_is_dropped_in_q_and_in_author_too(self, words):
        assert set(htids(words.search(text="the time machine"))) == {"a.1", "a.2"}
        assert htids(words.search(title="of mice and men", author="the steinbeck")) == ["a.4"]

    def test_stopwords_are_dropped_whatever_their_case(self, words):
        assert set(htids(words.search(title="THE Time Machine"))) == {"a.1", "a.2"}

    def test_a_search_of_only_stopwords_still_matches_them(self, words):
        assert htids(words.search(title="the of and")) == ["a.3"]
        assert htids(words.search(text="The Of")) == ["a.3"]

    def test_each_field_keeps_its_own_words(self, words):
        """The title is all stopwords, so it keeps them; the author's stopword is dropped."""
        assert htids(words.search(title="the of and", author="the steinbeck")) == []
        assert htids(words.search(title="of and", author="the steinbeck")) == ["a.4"]

    def test_a_search_with_a_stopword_does_not_find_books_without_the_other_words(self, words):
        assert words.search(title="the zeppelin") == []


class TestSearchIsbn:
    def test_finds_by_isbn_13(self, index):
        assert htids(index.search(isbn="9780813730219")) == ["mdp.39015000388903"]

    def test_finds_by_isbn_10_and_with_hyphens(self, index):
        assert htids(index.search(isbn="0-8137-3021-X")) == ["mdp.39015000388903"]
        assert htids(index.search(isbn="081373021X")) == ["mdp.39015000388903"]

    def test_an_invalid_isbn_finds_nothing(self, index):
        assert index.search(isbn="9780813730218") == []        # bad check digit
        assert index.search(isbn="not an isbn") == []

    def test_the_fake_isbn_finds_nothing_even_when_a_row_carries_it(self, tmp_path):
        index = HathiIndex(tmp_path / "fake.sqlite")
        index.replace_all([volume("f.1", isbns=["9780000000002"])], STATE)
        assert index.search(isbn="9780000000002") == []
        assert index.search(isbn="0000000000") == []

    def test_isbn_and_text_must_both_match(self, index):
        assert htids(index.search(isbn="9780813730219", text="treatise")) == ["mdp.39015000388903"]
        assert index.search(isbn="9780813730219", text="dickens") == []


class TestFilters:
    def test_language_uses_the_marc_code(self, index):
        found = index.search(text="Tour du monde", language="fre")
        assert htids(found) == ["hvd.32044102775384"]
        assert index.search(text="Tour du monde", language="ger") == []

    def test_a_volume_with_no_language_never_passes_a_language_filter(self, index):
        assert htids(index.search(text="Bull Run")) == ["njp.32101041624584"]
        assert index.search(text="Bull Run", language="eng") == []

    def test_no_terms_at_all_finds_nothing(self, index):
        assert index.search() == []


class TestCopiesAndVolumes:
    def test_copies_of_one_record_with_the_same_volume_label_show_once(self, index):
        """Harvard and the New York Public Library each hold "Pioneering in Central Africa"."""
        found = index.search(text="pioneering central africa")
        assert len(found) == 1

    def test_the_copy_shown_is_stable(self, index):
        assert htids(index.search(text="pioneering")) == htids(index.search(text="pioneering"))
        assert htids(index.search(text="pioneering")) == ["hvd.hxdppf"]       # first htid in order

    def test_volumes_with_different_labels_all_show(self, index):
        found = index.search(text="goethes werke")
        assert sorted(v.volume for v in found) == ["v.2", "v.5"]

    def test_volumes_of_different_records_with_the_same_label_all_show(self, tmp_path):
        index = HathiIndex(tmp_path / "t.sqlite")
        index.replace_all([volume("a.1", bib_key="1", volume="v.1", title="Same title"),
                           volume("b.1", bib_key="2", volume="v.1", title="Same title")], STATE)
        assert len(index.search(text="same title")) == 2


class TestPaging:
    @pytest.fixture
    def many(self, tmp_path):
        index = HathiIndex(tmp_path / "many.sqlite")
        index.replace_all([volume(f"m.{n:03d}", bib_key=f"{n:03d}", title="Same words") for n in range(45)], STATE)
        return index

    def test_limit_and_offset(self, many):
        first = many.search(text="same words", limit=20, offset=0)
        second = many.search(text="same words", limit=20, offset=20)
        third = many.search(text="same words", limit=20, offset=40)
        assert (len(first), len(second), len(third)) == (20, 20, 5)

    def test_pages_do_not_overlap_and_the_order_is_stable(self, many):
        pages = [htids(many.search(text="same words", limit=20, offset=o)) for o in (0, 20, 40)]
        flat = [h for page in pages for h in page]
        assert len(flat) == len(set(flat)) == 45
        assert htids(many.search(text="same words", limit=20, offset=20)) == pages[1]

    def test_past_the_end_is_empty(self, many):
        assert many.search(text="same words", limit=20, offset=1000) == []


class TestApply:
    """Daily update files: rows added, changed, or no longer open to everyone."""

    def new_state(self):
        return IndexState("hathi_full_20261001.txt.gz", "20261002")

    def test_a_new_volume_is_added_and_found(self, index):
        index.apply([("n.1", volume("n.1", title="Brand new arrival"))], self.new_state())
        assert htids(index.search(text="brand new arrival")) == ["n.1"]
        assert index.count() == 15

    def test_a_changed_volume_is_replaced_not_duplicated(self, index):
        index.apply([("hvd.hxdppf", volume("hvd.hxdppf", bib_key="008642955", title="Pioneering renamed"))],
                    self.new_state())
        assert index.count() == 14
        assert htids(index.search(text="renamed")) == ["hvd.hxdppf"]
        assert htids(index.search(text="pioneering central africa")) == ["nyp.33433082463161"]     # the old text is gone

    def test_a_volume_that_is_no_longer_open_is_removed(self, index):
        index.apply([("mdp.39015063531084", None)], self.new_state())
        assert index.count() == 13
        assert "mdp.39015063531084" not in htids(index.search(text="writings dickens"))

    def test_removing_a_volume_also_removes_its_isbn(self, index):
        index.apply([("mdp.39015000388903", None)], self.new_state())
        assert index.search(isbn="9780813730219") == []

    def test_changing_a_volumes_isbn_updates_the_isbn_lookup(self, index):
        index.apply([("mdp.39015000388903", volume("mdp.39015000388903", bib_key="003916076", isbns=["9780140430721"],
                                                  title="Treatise on invertebrate paleontology"))], self.new_state())
        assert index.search(isbn="9780813730219") == []
        assert htids(index.search(isbn="9780140430721")) == ["mdp.39015000388903"]

    def test_removing_a_volume_that_is_not_there_is_fine(self, index):
        index.apply([("never.heard.of.it", None)], self.new_state())
        assert index.count() == 14

    def test_the_state_moves_forward_with_the_changes(self, index):
        index.apply([("n.1", volume("n.1"))], self.new_state())
        assert index.state() == self.new_state()

    def test_a_failed_apply_changes_nothing(self, index):
        def changes():
            yield "n.1", volume("n.1", title="Half applied")
            raise RuntimeError("download broke")
        with pytest.raises(RuntimeError):
            index.apply(changes(), self.new_state())
        assert index.count() == 14
        assert index.search(text="half applied") == []
        assert index.state() == STATE

    def test_apply_on_a_missing_index_is_an_error(self, tmp_path):
        with pytest.raises(FileNotFoundError):
            HathiIndex(tmp_path / "nothing.sqlite").apply([], self.new_state())


class TestSafety:
    def test_searching_opens_the_file_read_only(self, index):
        with sqlite3.connect(f"file:{index.path}?mode=ro", uri=True) as db:
            with pytest.raises(sqlite3.OperationalError):
                db.execute("DELETE FROM volumes")

    def test_searching_does_not_create_a_missing_file(self, tmp_path):
        index = HathiIndex(tmp_path / "nothing.sqlite")
        assert not index.exists()
        with pytest.raises(FileNotFoundError):
            index.search(text="x")
        assert not index.path.exists()

    def test_a_search_can_run_while_the_index_is_replaced(self, index):
        found_during = []
        original = index.search

        def volumes():
            found_during.append(htids(original(text="dickens")))       # the old index still answers
            yield volume("new.1", title="Replacement")
        index.replace_all(volumes(), IndexState("hathi_full_20261101.txt.gz", "20261101"))
        assert found_during == [DICKENS]
        assert htids(index.search(text="replacement")) == ["new.1"]

    def test_a_corrupt_file_is_reported_as_an_error(self, tmp_path):
        path = tmp_path / "bad.sqlite"
        path.write_bytes(b"this is not a database" * 100)
        with pytest.raises(sqlite3.DatabaseError):
            HathiIndex(path).search(text="x")


def test_the_sample_directory_has_the_rows_used_here():
    assert (SAMPLES / "hathitrust-hathifile-sample.tsv").exists()
