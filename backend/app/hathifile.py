"""HathiTrust Hathifiles: one tab-separated line per volume, no header (api_hathitrust.documentation.md).

Only volumes anyone can read (`access = allow`) and only books (`bib_fmt = BK`, not serials, maps or music)
are kept. Titles and authors come as catalog (MARC) strings and are cleaned here.
"""
import re
from dataclasses import dataclass
from typing import Iterable, Iterator
from urllib.parse import quote

from app.normalize import normalize_author_name, normalize_isbn, normalize_oclc

READER_URL = "https://babel.hathitrust.org/cgi/pt?id="

# Column positions (0-based) in a Hathifile line.
_HTID, _ACCESS, _RIGHTS, _BIB_KEY, _DESCRIPTION, _SOURCE, _OCLC, _ISBN, _TITLE, _LANG, _FORMAT, _AUTHOR = \
    0, 1, 2, 3, 4, 5, 7, 8, 11, 18, 19, 25
_COLUMNS = 26

# `lang` values that say nothing about the language: undetermined, multiple, no linguistic content.
_NO_LANGUAGE = {"", "und", "mul", "zxx"}


@dataclass(frozen=True)
class Volume:
    """One digitized volume that anyone can read."""
    htid: str                  # the volume ID, e.g. "mdp.39015063531373"
    rights: str                # "pd", "pdus" (public domain in the United States only), "cc-by-4.0", ...
    bib_key: str               # the catalog record; copies and volumes of one set share it
    volume: str | None         # volume label, e.g. "v.2"
    source: str                # holding library code, e.g. "MIU"
    oclcs: list[str]
    isbns: list[str]           # ISBN-13, valid ones only
    title: str
    author: str | None         # "Jane Austen"
    language: str | None       # MARC code ("eng", "ger"), None when unknown

    @property
    def us_only(self) -> bool:
        return self.rights == "pdus"


def reader_url(htid: str) -> str:
    """The volume in HathiTrust's reader. (We cannot read it from the backend: the host blocks our IP.)"""
    return READER_URL + quote(htid, safe=":/$")


def parse_line(line: str) -> tuple[str, Volume | None] | None:
    """(htid, volume) for a Hathifile line; the volume is None when it is not kept (search-only, or not a book),
    so that an update file can remove a volume that has stopped being open. None for a malformed line."""
    fields = line.rstrip("\r\n").split("\t")
    if len(fields) < _COLUMNS:
        return None
    htid = fields[_HTID].strip()
    if not htid:
        return None
    if fields[_ACCESS] != "allow" or fields[_FORMAT] != "BK":
        return htid, None
    title = clean_title(fields[_TITLE])
    if not title:
        return htid, None
    language = fields[_LANG].strip().lower()
    return htid, Volume(
        htid=htid,
        rights=fields[_RIGHTS].strip(),
        bib_key=fields[_BIB_KEY].strip(),
        volume=fields[_DESCRIPTION].strip() or None,
        source=fields[_SOURCE].strip(),
        oclcs=_unique(normalize_oclc(v) for v in fields[_OCLC].split(",")),
        isbns=_unique(normalize_isbn(v) for v in fields[_ISBN].split(",")),
        title=title,
        author=clean_author(fields[_AUTHOR]),
        language=None if language in _NO_LANGUAGE else language,
    )


def iter_changes(lines: Iterable[str]) -> Iterator[tuple[str, Volume | None]]:
    """parse_line over many lines, skipping the malformed ones."""
    for line in lines:
        parsed = parse_line(line)
        if parsed is not None:
            yield parsed


def _unique(values) -> list[str]:
    return list(dict.fromkeys(v for v in values if v))


# --- Titles and authors ------------------------------------------------------

# "Pride and prejudice / by Jane Austen": the statement of responsibility after " / " is not the title.
# Some records give it as "..., by Samuel P. Verner" or "...; by the Right Hon. ..." instead.
_RESPONSIBILITY = re.compile(r"(?:^|\s)/(?:\s|$)|[,;]\s+by\s")
_TRAILING_PUNCTUATION = " /:;,="


def clean_title(raw: str) -> str:
    text = " ".join((raw or "").split())
    head = _RESPONSIBILITY.split(text, maxsplit=1)[0].lstrip("[ ")
    if not head:                               # nothing but the statement: keep its words
        head = text.lstrip("/ [")
    head = head.rstrip(_TRAILING_PUNCTUATION)
    last = head.rsplit(" ", 1)[-1]
    if last.endswith(".") and sum(c.isalpha() for c in last) >= 3:    # "complètes." but not "Co." or "Jr."
        head = head[:-1].rstrip(_TRAILING_PUNCTUATION)
    return head


# Dates in a name: "1775-1817", "1900-", "fl. 1600", "b. 1900", "ca. 1500-ca. 1560", "1812?-1870".
_DATE = r"(?:(?:fl|b|d|ca)\.\s*)?\d{3,4}\??(?:\s*-\s*(?:ca\.\s*)?(?:\d{3,4}\??)?)?"
_TRAILING_DATE = re.compile(rf"[\s,]+{_DATE}\.?(?=\s*(?:,|$))", re.I)
_PARENTHETICAL = re.compile(r"\s*\([^)]*\)")


def clean_author(raw: str) -> str | None:
    """'Austen, Jane, 1775-1817.' -> 'Jane Austen'. None when there is no name."""
    text = _PARENTHETICAL.sub("", " ".join((raw or "").split()))
    text = _TRAILING_DATE.sub("", text)
    if not any(c.isalpha() for c in text):
        return None
    parts = [_without_full_stop(p.strip()) for p in text.split(",") if p.strip()]
    return normalize_author_name(", ".join(parts)) or None


def _without_full_stop(text: str) -> str:
    """'Samuel Phillips.' -> 'Samuel Phillips', but 'W. H.' and 'Jr.' keep theirs."""
    last = text.rsplit(" ", 1)[-1]
    return text[:-1] if last.endswith(".") and sum(c.isalpha() for c in last) >= 3 else text
