"""Builders for Book objects so tests only spell out what they care about."""
from typing import Iterable, Iterator

from app.hathifile import Volume, parse_line
from app.models import Book


def make_book(**overrides) -> Book:
    source = overrides.get("source", "gutenberg")
    source_id = overrides.get("source_id", "1")
    defaults = dict(
        source=source,
        source_id=source_id,
        title="Untitled",
        authors=[],
        narrators=[],
        contributors=[],
        language="en",
        format="text",
        pages=None,
        audio_seconds=None,
        identifiers={},
        url=f"https://example.org/{source}/{source_id}",
        cover_url=None,
        content={},
        chapters=[],
        access="open",
    )
    defaults.update(overrides)
    return Book(**defaults)


CONTAINER_XML = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="{opf}" media-type="application/oebps-package+xml"/></rootfiles>
</container>"""

NAV_XHTML = """<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body>
  <nav epub:type="landmarks"><ol><li><a href="text/ch1.xhtml">Start</a></li></ol></nav>
  <nav epub:type="toc"><ol>
    <li><a href="text/ch1.xhtml#c1">Chapter <b>I</b>.</a>
      <ol><li><a href="text/my%20chapter.xhtml">Part two</a></li></ol></li>
  </ol></nav>
</body></html>"""

NCX = """<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="n1"><navLabel><text>Chapter I.</text></navLabel><content src="text/ch1.xhtml#c1"/></navPoint>
    <navPoint id="n2"><navLabel><text>Part two</text></navLabel><content src="text/my%20chapter.xhtml"/></navPoint>
  </navMap>
</ncx>"""

OPF = """<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="{version}" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">http://www.gutenberg.org/1342</dc:identifier>
    <dc:title>Pride and Prejudice</dc:title>
    <dc:creator>Jane Austen</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    {nav_item}
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/my%20chapter.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="css/style.css" media-type="text/css"/>
    <item id="cover" href="images/cover.jpg" media-type="image/jpeg" {cover_props}/>
  </manifest>
  <spine toc="ncx"><itemref idref="ch1"/><itemref idref="ch2"/></spine>
</package>"""


def make_epub(*, version: int = 3, extra: dict[str, bytes] | None = None) -> bytes:
    """A small EPUB in the layout Project Gutenberg uses (OPF in OEBPS/). EPUB 2 has an NCX and no nav."""
    import io
    import zipfile
    epub3 = version == 3
    files = {
        "mimetype": b"application/epub+zip",
        "META-INF/container.xml": CONTAINER_XML.format(opf="OEBPS/content.opf").encode(),
        "OEBPS/content.opf": OPF.format(
            version="3.0" if epub3 else "2.0",
            nav_item='<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
            if epub3 else "",
            cover_props='properties="cover-image"' if epub3 else "",
        ).encode(),
        "OEBPS/toc.ncx": NCX.encode(),
        "OEBPS/text/ch1.xhtml": b"<html><body><h1 id='c1'>Chapter I.</h1></body></html>",
        "OEBPS/text/my chapter.xhtml": b"<html><body><p>Part two</p></body></html>",
        "OEBPS/css/style.css": b"body { margin: 0 }",
        "OEBPS/images/cover.jpg": b"\xff\xd8\xff\xe0 not really a jpeg",
    }
    if epub3:
        files["OEBPS/nav.xhtml"] = NAV_XHTML.encode()
    files.update(extra or {})
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    return buffer.getvalue()


def iter_changes(lines: Iterable[str]) -> Iterator[tuple[str, Volume | None]]:
    """parse_line over many lines, skipping the malformed ones."""
    for line in lines:
        parsed = parse_line(line)
        if parsed is not None:
            yield parsed
