"""Data Merging rules (spec.md): unite books from different sources into works.

Pass 1: a shared ISBN or OCLC number.  Pass 2: exact title and author.  Pass 3: fuzzy title and author.
- Different languages never merge. A book with an unknown language merges only through pass 1.
- Only authors count; narrators, translators and editors are ignored.
- A book with no author never merges on title alone.
- A fuzzy match merges only when it is unambiguous: a duplicate is better than a false merge.
"""
import re
from dataclasses import dataclass, field

from rapidfuzz import fuzz

from app.models import Book, Work
from app.normalize import author_key, normalize_author_name, normalize_isbn, normalize_oclc, title_key

TITLE_SIMILARITY = 90    # rapidfuzz ratio, 0-100
SURNAME_SIMILARITY = 90  # Shelley/Shelly 92, Dostoevsky/Dostoyevsky 95, Hardy/Harding 83
_NUMBER = re.compile(r"^(\d+|[ivxlc]+)$")   # volume numbers: "Tome I" is not "Tome V"


@dataclass
class _Entry:
    book: Book
    order: int                     # position in the input, used to keep result order
    title: str = ""
    authors: frozenset = frozenset()
    ids: set = field(default_factory=set)
    numbers: frozenset = frozenset()


class _Groups:
    """Union-find that refuses to put two different languages in one group."""

    def __init__(self, entries: list[_Entry]):
        self.parent = list(range(len(entries)))
        self.languages = [{e.book.language} - {None} for e in entries]

    def find(self, i: int) -> int:
        while self.parent[i] != i:
            self.parent[i] = self.parent[self.parent[i]]
            i = self.parent[i]
        return i

    def compatible(self, i: int, j: int) -> bool:
        return len(self.languages[self.find(i)] | self.languages[self.find(j)]) <= 1

    def union(self, i: int, j: int) -> None:
        a, b = self.find(i), self.find(j)
        if a == b or not self.compatible(a, b):
            return
        a, b = min(a, b), max(a, b)
        self.parent[b] = a
        self.languages[a] |= self.languages[b]


def merge_books(books: list[Book]) -> list[Work]:
    # Sorting first makes the grouping independent of the order the sources answered in.
    ordered = sorted(enumerate(books), key=lambda pair: (pair[1].source, pair[1].source_id, pair[0]))
    entries = [_entry(book, order) for order, book in ordered]
    groups = _Groups(entries)
    _merge_on_identifiers(entries, groups)
    _merge_exact(entries, groups)
    _merge_fuzzy(entries, groups)

    members: dict[int, list[_Entry]] = {}
    for i, entry in enumerate(entries):
        members.setdefault(groups.find(i), []).append(entry)
    clusters = sorted(members.values(), key=lambda group: min(e.order for e in group))
    return [_work([e.book for e in group]) for group in clusters]


def _entry(book: Book, order: int) -> _Entry:
    ids = {("isbn", v) for v in map(normalize_isbn, book.identifiers.get("isbn", [])) if v}
    ids |= {("oclc", v) for v in map(normalize_oclc, book.identifiers.get("oclc", [])) if v}
    title = title_key(book.title)
    return _Entry(
        book=book, order=order, title=title,
        authors=frozenset(k for k in map(author_key, book.authors) if k),
        ids=ids,
        numbers=frozenset(t for t in title.split() if _NUMBER.match(t)),
    )


def _merge_on_identifiers(entries: list[_Entry], groups: _Groups) -> None:
    first_with: dict[tuple, int] = {}
    for i, entry in enumerate(entries):
        for identifier in sorted(entry.ids):
            if identifier in first_with:
                groups.union(first_with[identifier], i)
            else:
                first_with[identifier] = i


def _title_author_eligible(entry: _Entry) -> bool:
    return entry.book.language is not None and bool(entry.authors) and bool(entry.title)


def _merge_exact(entries: list[_Entry], groups: _Groups) -> None:
    first_with: dict[tuple, int] = {}
    for i, entry in enumerate(entries):
        if not _title_author_eligible(entry):
            continue
        key = (entry.book.language, entry.title, entry.authors)
        if key in first_with:
            groups.union(first_with[key], i)
        else:
            first_with[key] = i


def _fuzzy_match(a: _Entry, b: _Entry) -> bool:
    if a.book.language != b.book.language or a.numbers != b.numbers:
        return False
    if fuzz.ratio(a.title, b.title) < TITLE_SIMILARITY:
        return False
    return _same_authors(a.authors, b.authors)


def _same_authors(a: frozenset, b: frozenset) -> bool:
    """Each author pairs with one whose given names are identical and whose surname is close.

    "John Smith" and "Joan Smith" are different people; "Mary Shelley" and "Mary Shelly" are a misspelling.
    """
    if len(a) != len(b):
        return False
    by_surname = lambda key: (key.split()[-1], key)
    return all(_same_author(x, y) for x, y in zip(sorted(a, key=by_surname), sorted(b, key=by_surname)))


def _same_author(a: str, b: str) -> bool:
    *given_a, surname_a = a.split()
    *given_b, surname_b = b.split()
    return given_a == given_b and fuzz.ratio(surname_a, surname_b) >= SURNAME_SIMILARITY


def _merge_fuzzy(entries: list[_Entry], groups: _Groups) -> None:
    """Merge two groups only when each is the other's one and only fuzzy match."""
    eligible = [i for i, e in enumerate(entries) if _title_author_eligible(e)]
    candidates: dict[int, set[int]] = {}
    for x, i in enumerate(eligible):
        for j in eligible[x + 1:]:
            gi, gj = groups.find(i), groups.find(j)
            if gi == gj or not groups.compatible(gi, gj):
                continue
            if _fuzzy_match(entries[i], entries[j]):
                candidates.setdefault(gi, set()).add(gj)
                candidates.setdefault(gj, set()).add(gi)
    for g, matches in sorted(candidates.items()):
        if len(matches) == 1:
            (h,) = matches
            if candidates.get(h) == {g}:
                groups.union(g, h)


def _work(books: list[Book]) -> Work:
    # LibriVox drops leading articles ("Time Machine (Version 4)"), so prefer a text record's title.
    preferred = sorted(books, key=lambda b: (b.format != "text", b.source, b.source_id))
    authors: dict[str, str] = {}
    for book in preferred:
        for name in book.authors:
            authors.setdefault(author_key(name), normalize_author_name(name) or name)
    identifiers: dict[str, list[str]] = {}
    source_ids: dict[str, list[str]] = {}
    for book in books:
        for kind, values in book.identifiers.items():
            bucket = identifiers.setdefault(kind, [])
            bucket.extend(v for v in values if v not in bucket)
        source_ids.setdefault(book.source, []).append(book.source_id)
    first = books[0]
    return Work(
        id=f"{first.source}:{first.source_id}",
        title=preferred[0].title,
        authors=list(authors.values()),
        language=next((b.language for b in preferred if b.language), None),
        sources=sorted(source_ids),
        source_ids=source_ids,
        identifiers=identifiers,
        urls=list(dict.fromkeys(b.url for b in books)),
        cover_url=next((b.cover_url for b in preferred if b.cover_url), None),
        formats=sorted({b.format for b in books}),
        books=books,
    )
