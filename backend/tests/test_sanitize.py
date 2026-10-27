"""Book pages lose anything that could run a script before the backend serves them.

Review 2026-10-11-main #15 (and SECURITY-REVIEW.md): Readium rebuilds each chapter into a document on the app's own
origin, with scripts allowed, so a script in a book could reach the app. The backend's `sandbox` header does not
follow the text into that document, so the text itself is cleaned here. Everything else stays as it was, byte for
byte, so the book looks the same.
"""
import pytest

from app.sanitize import sanitize_markup

PAGE = """<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en">
<head><meta charset="utf-8"/><title>Chapter 1</title>
<link rel="stylesheet" href="../css/style.css" type="text/css"/></head>
<body>
<!-- a comment -->
<h2 id="ch1">Chapter&#160;1</h2>
<p class="first">It is a truth universally acknowledged &amp; so on.</p>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><linearGradient id="g"/></svg>
<p><a href="ch2.xhtml#p3">Next</a> <img src="../images/a.jpg" alt="A picture"/></p>
</body>
</html>
"""


def clean(text: str) -> str:
    return sanitize_markup(text.encode("utf-8")).decode("utf-8")


def test_an_ordinary_page_is_unchanged_byte_for_byte():
    assert clean(PAGE) == PAGE


def test_a_page_in_another_encoding_keeps_its_bytes():
    data = PAGE.replace("utf-8", "iso-8859-1").replace("so on", "café").encode("iso-8859-1")
    assert sanitize_markup(data) == data


def test_script_elements_are_removed_with_their_code():
    page = PAGE.replace("<body>", '<body><script>parent.localStorage.clear()</script>'
                                  '<script type="text/javascript" src="x.js"></script><script src="y.js"/>')
    assert clean(page) == PAGE


def test_a_script_in_upper_case_is_removed():
    assert clean("<p>a</p><SCRIPT>alert(1)</SCRIPT><p>b</p>") == "<p>a</p><p>b</p>"


def test_a_script_that_is_never_closed_takes_the_rest_of_the_page_with_it():
    assert clean("<p>a</p><script>alert(1)<p>b</p>") == "<p>a</p>"


def test_a_script_hidden_in_a_style_element_is_removed():
    """Read as XML, a <script> inside <style> is an element and runs; as HTML it would be text."""
    assert clean("<style>p{}<script>alert(1)</script></style>") == "<style>p{}</style>"


@pytest.mark.parametrize("tag", ["iframe", "object", "applet", "frameset", "noembed"])
def test_elements_that_load_other_documents_are_removed(tag):
    assert clean(f'<p>a</p><{tag} src="x"><p>inside</p></{tag}><p>b</p>') == "<p>a</p><p>b</p>"


@pytest.mark.parametrize("tag", ['<embed src="x.swf"/>', '<base href="https://evil.example/"/>',
                                 '<base href="https://evil.example/">', '<frame src="x">',
                                 '<meta http-equiv="refresh" content="0; url=javascript:alert(1)"/>'])
def test_empty_elements_that_load_or_redirect_are_removed(tag):
    assert clean(f"<p>a</p>{tag}<p>b</p>") == "<p>a</p><p>b</p>"


def test_event_handlers_are_removed_and_the_rest_of_the_tag_is_kept_as_written():
    page = '<svg viewBox="0 0 1 1" onload="alert(1)" ONCLICK=\'x()\' id=s><rect onMouseOver=x width="1"/></svg>'
    assert clean(page) == '<svg viewBox="0 0 1 1" id=s><rect width="1"/></svg>'


@pytest.mark.parametrize("url", ["javascript:alert(1)", "  JavaScript:alert(1)", "java\tscript:alert(1)",
                                 "&#106;avascript:alert(1)", "vbscript:x", "data:text/html,<script>x</script>",
                                 "data:image/svg+xml,<svg onload=x>"])
def test_links_that_run_code_are_removed(url):
    assert clean(f'<a href="{url}" class="c">x</a>') == '<a class="c">x</a>'


def test_svg_links_and_animations_that_run_code_are_removed():
    page = ('<a xlink:href="javascript:x()">a</a>'
            '<animate attributeName="href" values="javascript:x()"/><set attributeName="href" to="javascript:x()"/>')
    assert clean(page) == '<a>a</a><animate attributeName="href"/><set attributeName="href"/>'


def test_srcdoc_and_form_actions_are_removed():
    assert clean('<form action="javascript:x()"><button formaction="javascript:y()">b</button></form>') == \
        "<form><button>b</button></form>"
    assert clean('<div srcdoc="&lt;script&gt;x&lt;/script&gt;">a</div>') == "<div>a</div>"


def test_ordinary_links_and_images_are_kept():
    page = '<a href="https://www.gutenberg.org/">G</a><img src="data:image/png;base64,iVBOR"/><a href="#n1">1</a>'
    assert clean(page) == page


def test_a_comment_or_cdata_section_is_left_alone():
    page = "<!-- <script>not run</script> --><p><![CDATA[ a < b ]]></p>"
    assert clean(page) == page
