# Security review - 2026-10-11

Reviewed baseline: `main`, commit `3e9d372`. No vulnerability fixes are included.

**Status (2026-10-11): fixed in the backend** (also #15 in `REVIEW-2026-10-11-main.md`). Readium fetches every chapter
from `/publications/...`, so the backend now serves XHTML, HTML and SVG files through `app/sanitize.py`: `<script>`,
`<iframe>`, `<object>`, `<embed>`, `<base>`, `<meta http-equiv>` and similar elements, `on*` attributes, `srcdoc`, and
`javascript:`/`vbscript:`/`data:` page links are removed; every other byte is unchanged (checked on 78 pages of 5 cached
Gutenberg books). The page is read as an XML parser reads it, so a script inside `<style>` is found too. Tests:
`backend/tests/test_sanitize.py`, `test_publications.py`. The Readium bundle is not patched and no DOMPurify was added.
Still to do: the browser check below (a scripted chapter in Chrome cannot reach the app's page or storage).

| # | Severity | File | Lines | Vulnerability | Confidence |
|---|----------|------|-------|---------------|------------|
| 1 | Medium | [readiumReader.js](app/web/readiumReader.js#L1) | 1 (bundled code) | Book scripts can access application-origin parent DOM/storage | 9/10 |

## Readium publication execution crosses the application-origin boundary

**Location:** bundled `fs.finalizeDOM`, `_s`, and `Vs` implementations in
[readiumReader.js](app/web/readiumReader.js#L1).

**Defect:** Readium preserves EPUB chapter scripts when rebuilding fetched markup into blob
documents. Its active EPUB iframe permits both `allow-scripts` and `allow-same-origin`; its
generated CSP permits inline scripts. The blob document inherits the application's origin.
The execution-prevention shim restricts storage APIs on the child window, but does not prevent
book scripts from reaching `parent.document` or `parent.localStorage`. The backend's sandbox
header protects directly served publication files, not these newly generated blob documents.

**Prerequisite:** an attacker must influence the upstream Gutenberg EPUB that a user opens.
No arbitrary user-upload endpoint was identified, and the review did not establish an ability
to alter Gutenberg's hosted files. This is an upstream-content trust-boundary finding.

**Evidence:** source tracing followed the active EPUB navigator to the blob builder, iframe
policy, CSP and execution-prevention shim. An in-memory scripted EPUB was accepted by the
production manifest builder. An isolated JavaScript probe confirmed that the shim restricted
child storage but allowed the equivalent access through the parent object.

**Limit:** no end-to-end browser exploit was performed. Confidence applies to the identified
execution boundary, not attacker access to upstream content or a demonstrated production attack.

## Recommended correction

Sanitize publication markup before injecting trusted Readium helpers, preferably through a
maintained dependency patch rather than manual edits to the minified bundle. An alternative is
to isolate publication execution on a separate origin with narrowly validated messaging.

Illustrative integration boundary, not a drop-in patch:

```javascript
const cleanMarkup = DOMPurify.sanitize(chapterMarkup, {
  WHOLE_DOCUMENT: true,
  FORBID_TAGS: ['script', 'iframe', 'object', 'embed', 'base', 'meta', 'form']
});
const chapterDocument =
  new DOMParser().parseFromString(cleanMarkup, 'text/html');
// Inject trusted Readium navigation helpers only after sanitization.
```

DOMPurify would be a new maintained dependency. Its configuration must also remove event
handlers and executable URLs while retaining required book markup.

Add browser integration tests with a chapter script, event handler and executable URL.
Verify they cannot mutate parent DOM/storage, while reading, navigation and TTS still work.

## Scope

The security pass examined backend HTTP/publication boundaries, source HTTP/XML handling,
Flutter text/Readium and URL opening, web integration, and Gutendex explorer DOM/templates.
The minified dependency was traced for the relevant execution surfaces, not exhaustively
audited. No additional exploitable security finding was verified in that scope.
Production deployment, real browser exploitability and upstream attacker control remain
unverified. Separate correctness/lifecycle/catalog findings are not security findings here.
