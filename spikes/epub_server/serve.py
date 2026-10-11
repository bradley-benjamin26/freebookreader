"""Spike: serve an EPUB as a Readium Web Publication (manifest.json + resources).

usage: python3 -I serve.py BOOK.epub [port]
Open http://localhost:PORT/manifest.json in the reader spike.
"""
import json, posixpath, sys, zipfile, mimetypes
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import quote, unquote, urlsplit
from xml.etree import ElementTree as ET

NS = {"c": "urn:oasis:names:tc:opendocument:xmlns:container",
      "o": "http://www.idpf.org/2007/opf", "dc": "http://purl.org/dc/elements/1.1/",
      "x": "http://www.w3.org/1999/xhtml", "e": "http://www.idpf.org/2007/ops"}
EPUB_PROFILE = "https://readium.org/webpub-manifest/profiles/epub"
EPUB_OPS = "{http://www.idpf.org/2007/ops}type"


def build_manifest(z: zipfile.ZipFile) -> dict:
    container = ET.fromstring(z.read("META-INF/container.xml"))
    opf_path = container.find(".//c:rootfile", NS).get("full-path")
    base = posixpath.dirname(opf_path)
    opf = ET.fromstring(z.read(opf_path))
    def href(p): return quote(posixpath.normpath(posixpath.join(base, unquote(p))))
    items = {i.get("id"): i for i in opf.findall(".//o:manifest/o:item", NS)}
    md = opf.find("o:metadata", NS)
    title = md.findtext("dc:title", "", NS)
    authors = [a.text for a in md.findall("dc:creator", NS) if a.text]
    langs = [l.text for l in md.findall("dc:language", NS) if l.text]
    spine_ids = [r.get("idref") for r in opf.findall(".//o:spine/o:itemref", NS)]
    def link(it):
        d = {"href": href(it.get("href")), "type": it.get("media-type")}
        props = (it.get("properties") or "").split()
        if "cover-image" in props: d["rel"] = "cover"
        if "nav" in props: d["rel"] = "contents"
        return d
    reading = [link(items[i]) for i in spine_ids if i in items]
    inspine = set(spine_ids)
    resources = [link(i) for k, i in items.items() if k not in inspine]
    toc = []
    nav = next((i for i in items.values() if "nav" in (i.get("properties") or "").split()), None)
    if nav is not None:
        npath = posixpath.normpath(posixpath.join(base, unquote(nav.get("href"))))
        ndir = posixpath.dirname(npath)
        root = ET.fromstring(z.read(npath))
        for n in root.iter("{%s}nav" % NS["x"]):
            if n.get(EPUB_OPS) == "toc":
                for a in n.iter("{%s}a" % NS["x"]):
                    h = a.get("href") or ""
                    toc.append({"href": quote(posixpath.normpath(posixpath.join(ndir, unquote(h.split("#")[0])))) + (("#" + h.split("#")[1]) if "#" in h else ""),
                                "title": "".join(a.itertext()).strip()})
    else:  # EPUB 2: NCX
        ncx = next((i for i in items.values() if i.get("media-type") == "application/x-dtbncx+xml"), None)
        if ncx is not None:
            npath = posixpath.normpath(posixpath.join(base, unquote(ncx.get("href"))))
            ndir = posixpath.dirname(npath)
            root = ET.fromstring(z.read(npath))
            N = "{http://www.daisy.org/z3986/2005/ncx/}"
            for p in root.iter(N + "navPoint"):
                c = p.find(N + "content"); t = p.find(N + "navLabel/" + N + "text")
                h = c.get("src")
                toc.append({"href": quote(posixpath.normpath(posixpath.join(ndir, unquote(h.split("#")[0])))) + (("#" + h.split("#")[1]) if "#" in h else ""),
                            "title": (t.text or "").strip()})
    return {"@context": "https://readium.org/webpub-manifest/context.jsonld",
            "metadata": {"@type": "http://schema.org/Book", "conformsTo": EPUB_PROFILE,
                         "title": title, "author": authors, "language": langs,
                         "identifier": md.findtext("dc:identifier", "", NS)},
            "links": [], "readingOrder": reading, "resources": resources, "toc": toc}


def make_handler(path):
    z = zipfile.ZipFile(path)
    manifest = json.dumps(build_manifest(z)).encode()
    names = set(z.namelist())
    types = {}
    for r in json.loads(manifest)["readingOrder"] + json.loads(manifest)["resources"]:
        types[unquote(r["href"])] = r["type"]
    class H(BaseHTTPRequestHandler):
        def _cors(self):
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Headers", "*")
        def do_OPTIONS(self):
            self.send_response(204); self._cors(); self.end_headers()
        def do_GET(self):
            p = unquote(urlsplit(self.path).path).lstrip("/")
            if p == "manifest.json":
                body, ct = manifest, "application/webpub+json"
            elif p in names and p in types:
                body, ct = z.read(p), types[p]
            else:
                self.send_response(404); self._cors(); self.end_headers(); return
            self.send_response(200); self._cors()
            self.send_header("Content-Type", ct); self.send_header("Content-Length", str(len(body)))
            self.end_headers(); self.wfile.write(body)
        def log_message(self, *a): pass
    return H

if __name__ == "__main__":
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8766
    HTTPServer(("127.0.0.1", port), make_handler(sys.argv[1])).serve_forever()
