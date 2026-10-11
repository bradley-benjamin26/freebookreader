"""Hathifile rows -> volumes (decision_hathitrust.md).

Uses real rows from the daily update file of 2026-10-11 (samples/hathitrust-hathifile-sample.tsv).
The real files have no header row; the column order is in api_hathitrust.documentation.md.
"""
import pytest

from app.hathifile import Volume, clean_author, clean_title, iter_changes, parse_line, reader_url
from tests.conftest import SAMPLES

SAMPLE_LINES = (SAMPLES / "hathitrust-hathifile-sample.tsv").read_text(encoding="utf-8").splitlines()


def row(**fields) -> str:
    """A 26-column Hathifile line; spell out only the columns a test cares about."""
    columns = ["htid", "access", "rights", "ht_bib_key", "description", "source", "source_bib_num", "oclc_num",
               "isbn", "issn", "lccn", "title", "imprint", "rights_reason_code", "rights_timestamp",
               "us_gov_doc_flag", "rights_date_used", "pub_place", "lang", "bib_fmt", "collection_code",
               "content_provider_code", "responsible_entity_code", "digitization_agent_code",
               "access_profile_code", "author"]
    values = dict.fromkeys(columns, "")
    values.update(htid="mdp.39015000000001", access="allow", rights="pd", ht_bib_key="000000001", source="MIU",
                  title="A title", lang="eng", bib_fmt="BK")
    unknown = set(fields) - set(columns)
    assert not unknown, unknown
    values.update(fields)
    return "\t".join(values[c] for c in columns)


def sample(htid: str) -> str:
    return next(line for line in SAMPLE_LINES if line.startswith(htid + "\t"))


class TestParseLine:
    def test_a_public_domain_book_row(self):
        htid, volume = parse_line(sample("mdp.39015063531373"))
        assert htid == "mdp.39015063531373"
        assert volume == Volume(
            htid="mdp.39015063531373", rights="pd", bib_key="000122358", volume="v.2", source="MIU",
            oclcs=["3388811"], isbns=[],
            title="The writings of Charles Dickens", author="Charles Dickens", language="eng")

    def test_a_single_volume_book_has_no_volume_label(self):
        _, volume = parse_line(sample("hvd.hxdppf"))
        assert volume.volume is None

    def test_several_oclc_numbers(self):
        _, volume = parse_line(sample("hvd.hxj2gw"))
        assert volume.oclcs == ["218382373", "961680"]

    def test_isbns_become_isbn_13_and_duplicates_are_dropped(self):
        _, volume = parse_line(sample("mdp.39015000388903"))     # 9780813730219,081373021X
        assert volume.isbns == ["9780813730219"]

    def test_a_blank_language_is_unknown(self):
        _, volume = parse_line(sample("njp.32101041624584"))
        assert volume.language is None

    @pytest.mark.parametrize("code", ["und", "mul", "zxx", "   ", ""])
    def test_languages_that_say_nothing_are_unknown(self, code):
        _, volume = parse_line(row(lang=code))
        assert volume.language is None

    def test_the_language_is_the_marc_code_in_lower_case(self):
        _, volume = parse_line(row(lang="GER"))
        assert volume.language == "ger"

    def test_creative_commons_rows_are_kept(self):
        _, volume = parse_line(sample("mdp.39015000388903"))
        assert volume.rights == "cc-by-4.0"

    def test_us_only_volumes_are_marked(self):
        _, us_only = parse_line(sample("mdp.39015010564923"))
        _, everyone = parse_line(sample("mdp.39015063531373"))
        assert us_only.rights == "pdus" and us_only.us_only is True
        assert everyone.us_only is False

    def test_the_source_code_is_kept(self):
        _, volume = parse_line(sample("nyp.33433003836859"))
        assert volume.source == "NYP"

    def test_an_htid_with_slashes_and_colons_is_kept(self):
        htid, volume = parse_line(sample("coo1.ark:/13960/t7tm7sm8g"))
        assert htid == volume.htid == "coo1.ark:/13960/t7tm7sm8g"

    def test_a_row_without_an_author_has_none(self):
        _, volume = parse_line(row(author=""))
        assert volume.author is None


class TestWhatIsKept:
    def test_search_only_rows_are_not_kept_but_the_htid_is_reported(self):
        """The update files carry rights changes: a volume that is now `deny` must leave the index."""
        htid, volume = parse_line(sample("uc1.31822007598626"))
        assert htid == "uc1.31822007598626"
        assert volume is None

    def test_serials_are_not_books(self):
        htid, volume = parse_line(sample("uc1.b3731354"))        # bib_fmt SE
        assert htid == "uc1.b3731354" and volume is None

    @pytest.mark.parametrize("fmt", ["SE", "MU", "MP", "MX", "CF", "MV", ""])
    def test_only_books_are_kept(self, fmt):
        assert parse_line(row(bib_fmt=fmt))[1] is None

    def test_a_row_without_a_title_is_not_kept(self):
        assert parse_line(row(title="  "))[1] is None

    def test_a_title_that_is_only_a_statement_of_responsibility_is_not_lost(self):
        _, volume = parse_line(row(title="/ by Jane Austen"))
        assert volume is not None and volume.title

    @pytest.mark.parametrize("rights", ["pd", "pdus", "cc-by-4.0", "cc-zero", "cc-by-nc-nd-4.0"])
    def test_every_allow_row_is_kept_whatever_the_rights_code(self, rights):
        assert parse_line(row(rights=rights))[1] is not None

    @pytest.mark.parametrize("line", ["", "\n", "just one field", "a\tb\tc", "\t".join(["x"] * 25)])
    def test_malformed_lines_are_ignored(self, line):
        assert parse_line(line) is None

    def test_extra_columns_are_ignored(self):
        assert parse_line(row() + "\textra")[1] is not None

    def test_a_trailing_newline_is_ignored(self):
        assert parse_line(row(title="Hello") + "\n")[1].title == "Hello"

    def test_the_fake_isbn_is_not_an_identifier(self):
        _, volume = parse_line(row(isbn="9780000000002,0000000000,000000000061rub,9780140430721"))
        assert volume.isbns == ["9780140430721"]


class TestIterChanges:
    def test_yields_every_well_formed_line_and_skips_the_rest(self):
        lines = [row(htid="a.1"), "", "garbage", row(htid="a.2", access="deny"), row(htid="a.3")]
        changes = list(iter_changes(lines))
        assert [(htid, v is not None) for htid, v in changes] == [("a.1", True), ("a.2", False), ("a.3", True)]

    def test_the_real_sample(self):
        changes = list(iter_changes(SAMPLE_LINES))
        assert len(changes) == 16
        assert sum(1 for _, v in changes if v is not None) == 14      # minus the `deny` row and the serial


class TestCleanTitle:
    @pytest.mark.parametrize("raw, expected", [
        ("Pride and prejudice / by Jane Austen", "Pride and prejudice"),
        ("Investigation of Simon & Coles manganese deposit Bedford county, Pa. / by W.H. Kerns.",
         "Investigation of Simon & Coles manganese deposit Bedford county, Pa."),
        ("Oeuvres complètes.", "Oeuvres complètes"),
        ("Pioneering in Central Africa, by Samuel P. Verner.", "Pioneering in Central Africa"),
        ("Notes from a diary, 1896 to January 23, 1901; by the Right Hon. Sir Mountstuart E. Grant Duff.",
         "Notes from a diary, 1896 to January 23, 1901"),
        ("Letters by a modern mystic", "Letters by a modern mystic"),
        ("Hamlet, Prince of Denmark", "Hamlet, Prince of Denmark"),
        ("The story of my life,", "The story of my life"),
        ("Biographie universelle, ancienne et moderne;", "Biographie universelle, ancienne et moderne"),
        ("Phosphate rock : 2. Processing / by William H Waggaman", "Phosphate rock : 2. Processing"),
        ("[Works.", "Works"),
        ("Smith and Co.", "Smith and Co."),
        ("Mrs. Dalloway", "Mrs. Dalloway"),
        ("  Spaced   out   title  ", "Spaced out title"),
        ("British diplomatic instructions, 1689-1789 / edited for the Royal Historical Society",
         "British diplomatic instructions, 1689-1789"),
    ])
    def test_cleaning(self, raw, expected):
        assert clean_title(raw) == expected

    def test_a_title_made_only_of_the_responsibility_statement_keeps_its_words(self):
        assert clean_title("/ by Jane Austen") == "by Jane Austen"

    def test_empty(self):
        assert clean_title("") == "" and clean_title("   ") == ""


class TestCleanAuthor:
    @pytest.mark.parametrize("raw, expected", [
        ("Austen, Jane, 1775-1817.", "Jane Austen"),
        ("Twain, Mark, 1835-1910.", "Mark Twain"),
        ("Dickens, Charles, 1812-1870.", "Charles Dickens"),
        ("Hare, Augustus J. C. 1834-1903.", "Augustus J. C. Hare"),
        ("Kerns, W. H.", "W. H. Kerns"),
        ("Verner, Samuel Phillips.", "Samuel Phillips Verner"),
        ("Voltaire, 1694-1778.", "Voltaire"),
        ("Verne, Jules, 1828-1905", "Jules Verne"),
        ("Halliwell-Phillipps, J. O. 1820-1889.", "J. O. Halliwell-Phillipps"),
        ("Goethe, Johann Wolfgang von, 1749-1832.", "Johann Wolfgang von Goethe"),
        ("Dickens, Charles, 1812-1870, Jr.", "Charles Dickens Jr."),
        ("Smith, John, fl. 1600.", "John Smith"),
        ("Smith, John, b. 1900.", "John Smith"),
        ("Smith, John, ca. 1500-ca. 1560.", "John Smith"),
        ("Smith, John, 1900-", "John Smith"),
        ("United States. Congress. Senate. Committee on Appropriations.",
         "United States. Congress. Senate. Committee on Appropriations"),
    ])
    def test_cleaning(self, raw, expected):
        assert clean_author(raw) == expected

    @pytest.mark.parametrize("raw", ["", "   ", ",", "1812-1870"])
    def test_nobody(self, raw):
        assert clean_author(raw) is None


class TestReaderUrl:
    def test_plain_htid(self):
        assert reader_url("mdp.39015063531373") == "https://babel.hathitrust.org/cgi/pt?id=mdp.39015063531373"

    def test_htids_with_ark_ids_keep_their_slashes_and_colons(self):
        assert reader_url("coo1.ark:/13960/t7tm7sm8g") == \
            "https://babel.hathitrust.org/cgi/pt?id=coo1.ark:/13960/t7tm7sm8g"

    def test_nothing_that_could_end_the_query_string_gets_through(self):
        url = reader_url("x.1&seq=9#frag y")
        assert "&" not in url.split("?id=", 1)[1] and "#" not in url and " " not in url
