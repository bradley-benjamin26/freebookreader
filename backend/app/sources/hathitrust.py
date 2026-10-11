"""HathiTrust, searched in a local index of its Hathifiles (see decision_hathitrust.md).

HathiTrust has no search API, so nothing here calls HathiTrust. A book is one volume that anyone can read.
Its reader (babel.hathitrust.org) blocks our IP, so each book links to the reader instead of opening in the app.
"""
from app.hathifile import Volume, reader_url
from app.hathitrust_index import HathiIndex
from app.models import Book, SearchQuery
from app.normalize import to_language_code, to_marc_language

PAGE_SIZE = 20

# Holding libraries by the code in the Hathifiles. These are the ones with the most open volumes
# (names from the Bibliographic API's `orig` field, 2026-10-11); any other code is shown as it is.
LIBRARIES = {
    "UC": "University of California", "NYP": "New York Public Library", "MIU": "University of Michigan",
    "HVD": "Harvard University", "UIU": "University of Illinois at Urbana-Champaign",
    "COU": "University of Colorado Boulder", "OU": "The Ohio State University",
    "WU": "University of Wisconsin - Madison", "COO": "Cornell University", "UMN": "University of Minnesota",
    "UVA": "University of Virginia", "NJP": "Princeton University", "PST": "Pennsylvania State University",
    "CHI": "University of Chicago", "NNC": "Columbia University", "IEN": "Northwestern University",
    "PUR": "Purdue University Main Campus Libraries", "GU": "University of Georgia", "IAU": "University of Iowa",
    "MIEM": "Michigan State University", "INU": "Indiana University", "NJR": "Rutgers University",
    "YALE": "Yale University", "LOC": "Library of Congress", "UKOXU": "University of Oxford",
    "FU": "State University System of Florida", "NJPT": "Princeton Theological Seminary",
    "TXU": "University of Texas at Austin", "CMALG": "Getty Research Institute",
    "UCM": "Universidad Complutense de Madrid", "CTU": "University of Connecticut", "DUL": "Duke University",
    "UNC": "University of North Carolina at Chapel Hill", "PU": "University of Pennsylvania",
    "MCHB": "Boston College", "QMM": "McGill University", "NCSU": "North Carolina State University",
    "MMET": "Tufts University", "MWICA": "Sterling and Francine Clark Art Institute",
    "MU": "University of Massachusetts Amherst",
}


class HathiIndexMissing(RuntimeError):
    """The index has not been built. Our setup is incomplete, not HathiTrust down, so this is not a SourceError
    (which would start a 24-hour outage): the search service reports the source as skipped and goes on."""


class HathiTrustSource:
    name = "hathitrust"

    def __init__(self, index: HathiIndex):
        self.index = index

    def search(self, query: SearchQuery) -> list[Book]:
        if query.format == "audio":
            return []
        if not self.index.exists():
            raise HathiIndexMissing(
                f"the HathiTrust index {self.index.path} has not been built; "
                "run `python -m app.hathitrust_update` in backend/")
        volumes = self.index.search(
            text=" ".join(t for t in (query.q, query.keyword) if t) or None,
            title=query.title, author=query.author, isbn=query.isbn,
            language=to_marc_language(query.language) if query.language else None,
            limit=PAGE_SIZE, offset=(query.page - 1) * PAGE_SIZE)
        return [_book(v) for v in volumes]


def _book(volume: Volume) -> Book:
    identifiers = {"isbn": volume.isbns, "oclc": volume.oclcs, "hathitrust": [volume.bib_key]}
    return Book(
        source="hathitrust",
        source_id=volume.htid,
        title=volume.title,
        authors=[volume.author] if volume.author else [],
        language=to_language_code(volume.language),
        identifiers={kind: values for kind, values in identifiers.items() if values},
        url=reader_url(volume.htid),
        volume=volume.volume,
        library=LIBRARIES.get(volume.source, volume.source),
        us_only=volume.us_only,
    )
