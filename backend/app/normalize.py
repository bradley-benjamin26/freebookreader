"""Pure helpers that make records from different sources comparable."""
import re
import unicodedata
from typing import Iterable

def unique(values: Iterable[str | None]) -> list[str]:
    """The values without repeats and without empty ones, in the order first seen."""
    return list(dict.fromkeys(v for v in values if v))


# --- Authors -----------------------------------------------------------------

_PARENTHETICAL = re.compile(r"\s*\([^)]*\)")
_DATES = re.compile(r"^\s*(ca\.\s*)?-?\d{1,4}\??\s*-?\s*(\d{1,4}\??)?\s*$|^\s*(b|d|fl)\.\s*\d", re.I)
NAME_SUFFIX = re.compile(r"^(?:jr|sr|ii|iii|iv|v|vi)\.?$", re.I)


def _is_suffix(text: str) -> bool:
    """'Jr.', 'II': but not a lone 'V.', which after a comma is more likely an initial."""
    return bool(NAME_SUFFIX.match(text)) and sum(c.isalpha() for c in text) > 1


def normalize_author_name(raw: str) -> str:
    """'Dickens, Charles, 1812-1870' -> 'Charles Dickens' (display form)."""
    name = _PARENTHETICAL.sub("", raw or "")
    parts = [p.strip() for p in name.split(",")]
    parts = [p for p in parts if p and not _DATES.match(p)]
    if not parts:
        return ""
    # A suffix after a comma is not a given name: "Charles Dickens, Jr." is already "First Last".
    suffixes = [p for p in parts[1:] if _is_suffix(p)]
    parts = [parts[0], *(p for p in parts[1:] if not _is_suffix(p))]
    if len(parts) >= 2:
        given = parts[1].split()
        while len(given) > 1 and _is_suffix(given[-1]):   # "Dickens, Charles Jr."
            suffixes.insert(0, given.pop())
        parts = [" ".join(given), parts[0], *parts[2:]]  # "Last, First" -> "First Last"
    name = " ".join(" ".join(parts + suffixes).split())
    all_lower = name == name.lower()
    words = []
    for word in name.split(" "):
        letters = [c for c in word if c.isalpha()]
        roman = _is_suffix(word) and word.lower().strip(".") not in ("jr", "sr")
        if roman and words and word in (word.lower(), word.upper()):
            word = word.upper()                        # "II", not "Ii"; a mixed-case "Vi" is a name
        elif all_lower or (len(letters) > 1 and word.isupper()):
            word = word.capitalize()
        words.append(word)
    return " ".join(words)


def _fold(text: str) -> str:
    """Lowercase and strip accents."""
    text = unicodedata.normalize("NFKD", text)
    return "".join(c for c in text if not unicodedata.combining(c)).lower()


def author_key(raw: str) -> str:
    """A comparison key: the same person spelled differently gets the same key."""
    name = _fold(normalize_author_name(raw))
    tokens = re.sub(r"[^\w\s]|_", " ", name).split()
    merged: list[str] = []
    run = ""
    for token in tokens:                 # join initials: "j r r tolkien" -> "jrr tolkien"
        if len(token) == 1:
            run += token
            continue
        if run:
            merged.append(run)
            run = ""
        merged.append(token)
    if run:
        merged.append(run)
    return " ".join(merged)


# --- Titles ------------------------------------------------------------------

_LEADING_ARTICLES = {"the", "a", "an"}
# LibriVox: "Pride and Prejudice (version 6, dramatic reading)" is another recording, not another title.
_VERSION_NOTE = re.compile(r"\s*\(\s*version\s*\d+[^)]*\)\s*$", re.I)


def title_key(raw: str) -> str:
    text = _VERSION_NOTE.sub("", raw or "")
    text = _fold(text).replace("&", " and ")
    text = re.sub(r"['’‘`]", "", text)
    tokens = re.sub(r"[^\w\s]|_", " ", text).split()
    if len(tokens) > 1 and tokens[0] in _LEADING_ARTICLES:
        tokens = tokens[1:]
    return " ".join(tokens)


# Where a subtitle starts: "Moby-Dick; or, The Whale", "Black Beauty: The autobiography of a horse",
# "Emile, or On Education", "Misérables - tome 1", "Great Expectations (SparkNotes)".
# A bare " or " is not one ("To Be or Not to Be").
_SUBTITLE = re.compile(r"\s*(?:[:;(]|,\s*or\b|\s[-–—]\s)", re.I)
# A trailing volume marker: "Les misérables Tome I", "War and Peace, Volume 2".
_VOLUME = re.compile(r"\s+(?:tome|volume|vol|book|part|band|livre|teil)\s+(?:[ivxlc]+|\d+)$")
# Leading articles that title_key keeps (it only drops English ones, so merging stays strict).
_FOREIGN_ARTICLES = {"le", "la", "les", "un", "une", "der", "die", "das", "ein", "eine", "el", "los",
                     "las", "il", "lo", "gli", "het", "een"}
# Words in a subtitle that mark a book about the book, not the book itself.
_STUDY_AID_WORDS = {
    "guide", "guides", "study", "notes", "summary", "summaries", "analysis", "companion", "commentary",
    "commentaries", "criticism", "critical", "critique", "workbook", "questions", "sparknotes",
    "cliffsnotes", "cliffs", "handbook", "lesson", "lessons", "quiz", "synopsis", "casebook",
    "interpretation", "interpretations",
}


def title_matches(title: str, wanted: str) -> bool:
    """Is a book with this title the one a known-item title search asked for?

    The whole titles match, or their main titles do (before any subtitle; a volume of the work
    counts as the work). A main-title match does not count when the book's subtitle marks a study
    aid ("Great Expectations: A Study Guide"), unless the search named the whole title.
    """
    if _match_key(title) == _match_key(wanted):
        return True
    title = _VERSION_NOTE.sub("", title or "")
    main, subtitle = _split_subtitle(title)
    main_key = _match_key(main)
    wanted_key = _match_key(_split_subtitle(wanted)[0])
    if wanted_key not in {main_key, _VOLUME.sub("", main_key)}:
        return False
    return not (_STUDY_AID_WORDS & set(title_key(subtitle).split()))


def _match_key(title: str) -> str:
    """title_key without a leading article in any language: LibriVox catalogs "Misérables - tome 1"."""
    tokens = title_key(title).split()
    if len(tokens) > 1 and tokens[0] in _FOREIGN_ARTICLES:
        tokens = tokens[1:]
    return " ".join(tokens)


def _split_subtitle(title: str) -> tuple[str, str]:
    parts = _SUBTITLE.split(title or "", maxsplit=1)
    if len(parts) == 1 or not parts[0].strip():
        return title, ""
    return parts[0], parts[1]


# --- Identifiers -------------------------------------------------------------

def _isbn10_ok(isbn: str) -> bool:
    total = sum((10 - i) * (10 if c == "X" else int(c)) for i, c in enumerate(isbn))
    return total % 11 == 0


def _isbn13_check(first12: str) -> str:
    total = sum(int(c) * (1 if i % 2 == 0 else 3) for i, c in enumerate(first12))
    return str((10 - total % 10) % 10)


# HathiTrust puts this valid-looking number (and 0000000000, its ISBN-10 form) on thousands of unrelated books.
PLACEHOLDER_ISBN = "9780000000002"


def normalize_isbn(raw: str | None) -> str | None:
    """Any valid ISBN-10 or ISBN-13 -> ISBN-13. Invalid input (bad check digit too) and the
    placeholder ISBN -> None."""
    if not raw:
        return None
    text = re.sub(r"^\s*isbn[-:\s]*", "", raw, flags=re.I)
    text = re.sub(r"[\s-]", "", text).upper()
    if re.fullmatch(r"\d{9}[\dX]", text):
        if not _isbn10_ok(text):
            return None
        first12 = "978" + text[:9]
        isbn = first12 + _isbn13_check(first12)
    elif re.fullmatch(r"97[89]\d{10}", text):
        isbn = text if _isbn13_check(text[:12]) == text[12] else None
    else:
        return None
    return None if isbn == PLACEHOLDER_ISBN else isbn


def normalize_oclc(raw: str | None) -> str | None:
    if not raw:
        return None
    text = re.sub(r"^\(ocolc\)|^oc[mn]|^on", "", raw.strip(), flags=re.I).strip()
    if not text.isdigit():
        return None
    return text.lstrip("0") or None


# --- Languages ---------------------------------------------------------------

# ISO 639-1 code: (MARC / ISO 639-2/B code, ISO 639-2/T code if different, English name)
_LANGUAGES = {
    "ar": ("ara", None, "arabic"),
    "ca": ("cat", None, "catalan"),
    "cs": ("cze", "ces", "czech"),
    "cy": ("wel", "cym", "welsh"),
    "da": ("dan", None, "danish"),
    "de": ("ger", "deu", "german"),
    "el": ("gre", "ell", "greek"),
    "en": ("eng", None, "english"),
    "eo": ("epo", None, "esperanto"),
    "es": ("spa", None, "spanish"),
    "fa": ("per", "fas", "persian"),
    "fi": ("fin", None, "finnish"),
    "fr": ("fre", "fra", "french"),
    "ga": ("gle", None, "irish"),
    "he": ("heb", None, "hebrew"),
    "hi": ("hin", None, "hindi"),
    "hr": ("hrv", None, "croatian"),
    "hu": ("hun", None, "hungarian"),
    "is": ("ice", "isl", "icelandic"),
    "it": ("ita", None, "italian"),
    "ja": ("jpn", None, "japanese"),
    "ko": ("kor", None, "korean"),
    "la": ("lat", None, "latin"),
    "nl": ("dut", "nld", "dutch"),
    "no": ("nor", None, "norwegian"),
    "pl": ("pol", None, "polish"),
    "pt": ("por", None, "portuguese"),
    "ro": ("rum", "ron", "romanian"),
    "ru": ("rus", None, "russian"),
    "sk": ("slo", "slk", "slovak"),
    "sl": ("slv", None, "slovenian"),
    "sr": ("srp", None, "serbian"),
    "sv": ("swe", None, "swedish"),
    "tl": ("tgl", None, "tagalog"),
    "tr": ("tur", None, "turkish"),
    "uk": ("ukr", None, "ukrainian"),
    "zh": ("chi", "zho", "chinese"),
}
_TO_CODE = {}
for _code, (_marc, _terminology, _name) in _LANGUAGES.items():
    for _alias in (_code, _marc, _terminology, _name):
        if _alias:
            _TO_CODE[_alias] = _code


def to_language_code(raw: str | None) -> str | None:
    """'eng', 'fre', 'fra', 'French', 'FR' -> ISO 639-1 ('en', 'fr'). Unknown -> None."""
    if not raw:
        return None
    return _TO_CODE.get(raw.strip().lower())


def to_marc_language(raw: str | None) -> str | None:
    """ISO 639-1 (or anything to_language_code accepts) -> MARC code ('fr' -> 'fre')."""
    code = to_language_code(raw)
    return _LANGUAGES[code][0] if code else None
