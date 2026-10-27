"""Takes out of a book page (XHTML, HTML or SVG) everything that could run a script.

Readium does not open a book's pages as they are served: it rebuilds each one into a new document on the app's own
origin, with scripts allowed, so the `sandbox` header on our responses does not protect it. A script in a book could
then reach the app's page and storage (REVIEW-2026-10-11-main.md #15). Project Gutenberg's books have no scripts, so
cleaning them costs nothing a reader would see.

Only what is dangerous is cut out; every other byte stays as it was. The page is read the way an XML parser reads it
(markup inside <script>, <style> and <title> is markup), so a script hidden where an HTML parser sees only text is
found too.
"""
import re
from html import unescape
from html.parser import HTMLParser, attrfind_tolerant, tagfind_tolerant

# Elements removed with everything in them.
_REMOVE_WITH_CONTENT = {"script", "iframe", "object", "applet", "frameset", "noembed"}
# Empty elements that load something or send the page elsewhere.
_REMOVE = {"embed", "base", "frame"}
# A link to one of these runs code in the page (after removing whitespace and control characters, as browsers do).
_CODE_URL = re.compile(r"^(javascript|vbscript|data:(text/html|application/xhtml|image/svg))", re.IGNORECASE)
_IGNORED_IN_URLS = re.compile(r"[\x00-\x20]")


def sanitize_markup(data: bytes) -> bytes:
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return _clean(data.decode("utf-16")).encode("utf-16")
    # Latin-1 maps each byte to one character and back, so UTF-8 and other ASCII-based encodings come back
    # unchanged; the markup itself is ASCII.
    return _clean(data.decode("latin-1")).encode("latin-1")


def _clean(text: str) -> str:
    finder = _Finder(text)
    finder.feed(text)
    finder.close()
    if not finder.edits:
        return text
    out, at = [], 0
    for start, end, replacement in sorted(finder.edits):
        if start < at:              # inside a part already cut out
            continue
        out += [text[at:start], replacement]
        at = end
    out.append(text[at:])
    return "".join(out)


def _dangerous(name: str, value: str | None) -> bool:
    name = name.lower()
    if name.startswith("on") or name == "srcdoc":
        return True
    return value is not None and bool(_CODE_URL.match(_IGNORED_IN_URLS.sub("", value)))


class _Finder(HTMLParser):
    """Collects (start, end, replacement) for each part of the text to cut out or rewrite."""

    def __init__(self, text: str):
        super().__init__(convert_charrefs=False)
        self.text = text
        self.line_starts = [0] + [m.end() for m in re.finditer("\n", text)]
        self.edits: list[tuple[int, int, str]] = []
        self._skipping: list = []          # [tag, depth, start] of an element being cut out

    def set_cdata_mode(self, *args, **kwargs):
        pass        # read the inside of <script>, <style>, <title> as markup, like an XML parser

    def _here(self) -> int:
        line, column = self.getpos()
        return self.line_starts[line - 1] + column

    def handle_starttag(self, tag, attrs):
        self._start(tag, attrs, empty=False)

    def handle_startendtag(self, tag, attrs):
        self._start(tag, attrs, empty=True)

    def _start(self, tag, attrs, empty):
        raw = self.get_starttag_text()
        start = self._here()
        end = start + len(raw)
        if self._skipping:
            if tag == self._skipping[0] and not empty:
                self._skipping[1] += 1
            return
        if tag in _REMOVE_WITH_CONTENT:
            if empty:
                self.edits.append((start, end, ""))
            else:
                self._skipping = [tag, 1, start]
            return
        if tag in _REMOVE or (tag == "meta" and any(name == "http-equiv" for name, _ in attrs)):
            self.edits.append((start, end, ""))
            return
        if any(_dangerous(name, value) for name, value in attrs):
            self.edits.append((start, end, _without_dangerous_attributes(raw)))

    def handle_endtag(self, tag):
        if self._skipping and tag == self._skipping[0]:
            self._skipping[1] -= 1
            if self._skipping[1] == 0:
                close = self.text.find(">", self._here())
                self.edits.append((self._skipping[2], len(self.text) if close < 0 else close + 1, ""))
                self._skipping = []

    def close(self):
        super().close()
        if self._skipping:          # never closed: it runs to the end of the page
            self.edits.append((self._skipping[2], len(self.text), ""))
            self._skipping = []


def _without_dangerous_attributes(raw: str) -> str:
    """The start tag as written, without the dangerous attributes. The whole tag goes if that cannot be done."""
    match = tagfind_tolerant.match(raw, 1)
    if not match:
        return ""
    pieces, k = [raw[:match.end()]], match.end()
    while k < len(raw):
        m = attrfind_tolerant.match(raw, k)
        if not m or m.end() == k:
            break
        name, rest, value = m.group(1, 2, 3)
        if rest and value[:1] in "'\"" and value[:1] == value[-1:]:
            value = value[1:-1]
        if not _dangerous(name, unescape(value) if rest else None):
            pieces.append(raw[k:m.end()])
        k = m.end()
    pieces.append(raw[k:])
    rebuilt = re.sub(r"\s+(/?>)$", r"\1", "".join(pieces))   # the space left by an attribute at the end
    check = _Finder(rebuilt)
    check.feed(rebuilt)
    check.close()
    return "" if check.edits else rebuilt
