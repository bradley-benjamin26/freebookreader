"""The local index of HathiTrust volumes: a SQLite file with full-text search (decision_hathitrust.md).

HathiTrust has no search API, so the Hathifiles are loaded here (app/hathitrust_update.py) and searched
without calling HathiTrust. Only volumes anyone can read are in it (see app/hathifile.py).
"""
import os
import re
import sqlite3
from contextlib import closing
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from urllib.parse import quote

from app.hathifile import Volume
from app.normalize import normalize_isbn

BUSY_TIMEOUT_SECONDS = 10
BATCH_SIZE = 10_000
MAX_SEARCH_WORDS = 30
TITLE_WEIGHT, AUTHOR_WEIGHT = 4.0, 1.0       # a word in the title counts more than one in the author

_SCHEMA = """
CREATE TABLE volumes (
    id INTEGER PRIMARY KEY,
    htid TEXT NOT NULL UNIQUE,
    rights TEXT NOT NULL,
    bib_key TEXT NOT NULL,
    volume TEXT,
    source TEXT NOT NULL,
    oclcs TEXT NOT NULL,
    isbns TEXT NOT NULL,
    title TEXT NOT NULL,
    author TEXT,
    lang TEXT
);
CREATE TABLE isbns (isbn TEXT NOT NULL, volume_id INTEGER NOT NULL);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE VIRTUAL TABLE names USING fts5(
    title, author, content='volumes', content_rowid='id', tokenize='unicode61 remove_diacritics 2');
"""
_INDEXES = """
CREATE INDEX volumes_record ON volumes (bib_key, volume);
CREATE INDEX isbns_isbn ON isbns (isbn);
CREATE INDEX isbns_volume ON isbns (volume_id);
"""
# Keep the full-text table in step with `volumes` while volumes are added and removed.
_TRIGGERS = """
CREATE TRIGGER volumes_added AFTER INSERT ON volumes BEGIN
    INSERT INTO names (rowid, title, author) VALUES (new.id, new.title, new.author);
END;
CREATE TRIGGER volumes_removed AFTER DELETE ON volumes BEGIN
    INSERT INTO names (names, rowid, title, author) VALUES ('delete', old.id, old.title, old.author);
END;
"""
_COLUMNS = "htid, rights, bib_key, volume, source, oclcs, isbns, title, author, lang"
_WORD = re.compile(r"[^\W_]+")
# Words in nearly every title (English, plus the articles and "of"/"and" of the other big languages in the
# collection). Matching them reads millions of index entries (5-6 s for "the of and"), and they tell books
# apart less than any other word, so a search that has another word leaves them out.
_STOPWORDS = frozenset(
    "a an and are as at be by for from in is it of on or the to with "
    "de des du la le les et "                  # French (also Spanish, Italian and Latin "de", "la")
    "der die das und "                         # German
    "el los las del y "                        # Spanish
    "il di e".split())                         # Italian


@dataclass(frozen=True)
class IndexState:
    """Which Hathifiles the index was built from: the monthly full file, and the last daily update applied."""
    full_file: str            # e.g. "hathi_full_20261001.txt.gz"
    updated_through: str      # "YYYYMMDD"


class HathiIndex:
    def __init__(self, path: Path | str):
        self.path = Path(path)

    def exists(self) -> bool:
        return self.path.is_file()

    # --- Reading ---------------------------------------------------------------

    def _reader(self) -> sqlite3.Connection:
        if not self.exists():
            raise FileNotFoundError(f"the HathiTrust index {self.path} has not been built")
        uri = f"file:{quote(str(self.path))}?mode=ro"
        return sqlite3.connect(uri, uri=True, timeout=BUSY_TIMEOUT_SECONDS)

    def state(self) -> IndexState | None:
        if not self.exists():
            return None
        with closing(self._reader()) as db:
            meta = dict(db.execute("SELECT key, value FROM meta"))
        if "full_file" not in meta or "updated_through" not in meta:
            return None
        return IndexState(meta["full_file"], meta["updated_through"])

    def count(self) -> int:
        with closing(self._reader()) as db:
            return db.execute("SELECT count(*) FROM volumes").fetchone()[0]

    def search(self, *, text: str | None = None, title: str | None = None, author: str | None = None,
               isbn: str | None = None, language: str | None = None,
               limit: int = 20, offset: int = 0) -> list[Volume]:
        """Volumes matching every given term, best first. `text` matches title or author; `title` and
        `author` only their own field; `isbn` is exact; `language` is a MARC code ("fre").

        Every word must match (case, accents and punctuation do not count). Words are never read as search
        syntax. A volume with several copies of the same record and volume label is listed once.
        """
        conditions, params = [], []
        for field, value in ((None, text), ("title", title), ("author", author)):
            if value is None:
                continue
            words = _search_words(value)
            if not words:               # only stopwords (or no letters): slow to match, says nothing
                continue
            phrase = " ".join(f'"{w}"' for w in words)
            conditions.append(f"{field} : ({phrase})" if field else f"({phrase})")
        match = " AND ".join(conditions)
        wanted_isbn = None
        if isbn is not None:
            wanted_isbn = normalize_isbn(isbn)
            if wanted_isbn is None:
                return []
        if not match and wanted_isbn is None:
            return []

        where, where_params = [], []
        if language:
            where.append("v.lang = ?")
            where_params.append(language)
        if wanted_isbn:
            where.append("v.id IN (SELECT volume_id FROM isbns WHERE isbn = ?)")
            where_params.append(wanted_isbn)
        columns = ", ".join(f"v.{c.strip()}" for c in _COLUMNS.split(","))
        if match:
            inner = (f"SELECT {columns}, bm25(names, {TITLE_WEIGHT}, {AUTHOR_WEIGHT}) AS rank "
                     "FROM names JOIN volumes v ON v.id = names.rowid WHERE names MATCH ?")
            params.append(match)
        else:
            inner = f"SELECT {columns}, 0.0 AS rank FROM volumes v WHERE 1"
        inner += "".join(f" AND {w}" for w in where)
        params += where_params
        sql = (f"SELECT {_COLUMNS} FROM ("
               f"  SELECT *, row_number() OVER (PARTITION BY bib_key, volume ORDER BY htid) AS copy FROM ({inner})"
               f") WHERE copy = 1 ORDER BY rank, bib_key, volume, htid LIMIT ? OFFSET ?")
        with closing(self._reader()) as db:
            rows = db.execute(sql, [*params, limit, offset]).fetchall()
        return [_volume(row) for row in rows]

    # --- Writing ---------------------------------------------------------------

    def replace_all(self, volumes: Iterable[Volume], state: IndexState) -> None:
        """Build a new index from these volumes and put it in place of the old one. The old index keeps
        answering searches until the new one is complete; if building fails, it is left untouched."""
        self.path.parent.mkdir(parents=True, exist_ok=True)
        building = self.path.with_name(self.path.name + ".building")
        building.unlink(missing_ok=True)
        try:
            with closing(sqlite3.connect(building)) as db:
                db.execute("PRAGMA journal_mode = OFF")
                db.execute("PRAGMA synchronous = OFF")
                db.executescript(_SCHEMA)
                batch: list[Volume] = []
                for volume in volumes:
                    batch.append(volume)
                    if len(batch) >= BATCH_SIZE:
                        _insert(db, batch)
                        batch = []
                _insert(db, batch)
                db.execute("INSERT INTO names (names) VALUES ('rebuild')")     # index every title at once
                db.executescript(_INDEXES + _TRIGGERS)
                _set_state(db, state)
                db.commit()
            os.replace(building, self.path)
        except BaseException:
            building.unlink(missing_ok=True)
            raise

    def apply(self, changes: Iterable[tuple[str, Volume | None]], state: IndexState) -> None:
        """Add, replace or (when the volume is None) remove volumes, all or nothing, then record the state."""
        if not self.exists():
            raise FileNotFoundError(f"the HathiTrust index {self.path} has not been built")
        with closing(sqlite3.connect(self.path, timeout=BUSY_TIMEOUT_SECONDS)) as db:
            db.isolation_level = None             # explicit transaction below
            db.execute("BEGIN IMMEDIATE")
            try:
                for htid, volume in changes:
                    row = db.execute("SELECT id FROM volumes WHERE htid = ?", (htid,)).fetchone()
                    if row:
                        db.execute("DELETE FROM isbns WHERE volume_id = ?", (row[0],))
                        db.execute("DELETE FROM volumes WHERE id = ?", (row[0],))
                    if volume is not None:
                        _insert(db, [volume])
                _set_state(db, state)
                db.execute("COMMIT")
            except BaseException:
                db.execute("ROLLBACK")
                raise


def _search_words(text: str) -> list[str]:
    """The words to match, without stopwords. Empty when the text is only stopwords ("the of and")."""
    return [w for w in _WORD.findall(text) if w.lower() not in _STOPWORDS][:MAX_SEARCH_WORDS]


def _insert(db: sqlite3.Connection, volumes: list[Volume]) -> None:
    for v in volumes:
        cursor = db.execute(
            f"INSERT OR IGNORE INTO volumes ({_COLUMNS}) VALUES (?,?,?,?,?,?,?,?,?,?)",
            (v.htid, v.rights, v.bib_key, v.volume, v.source, ",".join(v.oclcs), ",".join(v.isbns),
             v.title, v.author, v.language))
        if cursor.rowcount == 1:                  # 0: a repeated htid, the first line wins
            db.executemany("INSERT INTO isbns (isbn, volume_id) VALUES (?, ?)",
                           [(isbn, cursor.lastrowid) for isbn in v.isbns])


def _set_state(db: sqlite3.Connection, state: IndexState) -> None:
    db.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('full_file', ?)", (state.full_file,))
    db.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('updated_through', ?)", (state.updated_through,))


def _volume(row) -> Volume:
    htid, rights, bib_key, volume, source, oclcs, isbns, title, author, lang = row
    return Volume(htid=htid, rights=rights, bib_key=bib_key, volume=volume, source=source,
                  oclcs=oclcs.split(",") if oclcs else [], isbns=isbns.split(",") if isbns else [],
                  title=title, author=author, language=lang)
