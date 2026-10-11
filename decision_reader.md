# Decision: how the app reads books

Status: **provisional**. Decided 2026-10-10 to run a spike on `flutter_readium` before committing. Nothing here has been run yet; the facts about both packages come from their READMEs and pub.dev pages, not from testing.

## What the reader has to do

From [spec.md](spec.md):

* Show EPUB-style text (Project Gutenberg), PDF (DOAB, mostly hosted in the OAPEN Library), and play audiobooks (LibriVox). Open Library books link out.
* Be usable by a blind or low-vision person with a screen reader, and meet WCAG 2.2 AA.
* Dark and light mode, font size and style, spacing, page-turner view (default) and scroll view.
* Bookmarks stored on the device.
* Listen while reading when a LibriVox recording exists.
* **Read aloud with text-to-speech (TTS).** This is a goal (confirmed 2026-10-10).
* **Save a book to the device for offline use.** Supported in principle, not scheduled (see "Offline downloads").
* Web is supported but has no priority over mobile.

## Options considered

| Option | What it is | For | Against |
|---|---|---|---|
| **flutter_readium** | Flutter plugin over the Readium toolkits (swift-toolkit on iOS, kotlin-toolkit on Android, ts-toolkit on web). From Notalib. | EPUB 2/3, PDF (mobile only), audiobooks, TTS, media overlays, reader preferences, paginated and scrolled, saved reading position. Readium is the standard toolkit for accessible reading apps. BSD-3-Clause. | Pre-1.0 (0.x), 37 stars, 13 open issues. Native setup on Android, iOS and web. No LCP (we don't need it), no native macOS. On web: no PDF, no search, no background audio, TTS depends on the browser. Its README does not discuss accessibility. |
| **flutter_epub_viewer** | epub.js in a WebView (an iframe on web). | Simple. EPUB, themes via CSS, font size, paginated or scrolled, search, highlights, CFI position. Android, iOS, macOS, web. | EPUB only: no PDF, no audio, **no TTS**. Version 2.0.0, about 1.8k downloads, "OPF format is not fully supported yet". On web the iframe sits above the Flutter layer, so our settings sheet and player may not receive taps. Web needs permissive CORS from gutenberg.org (unverified). Its README does not discuss accessibility. |
| **Our own renderer** | Parse the book into paragraphs and draw them with Flutter widgets. | Full control of semantics, and the current widget tests in [app/test/reader_test.dart](app/test/reader_test.dart) assume it. | We build pagination, images, footnotes and CSS handling ourselves. Plain paragraphs lose book formatting. We would also have to build TTS. |

## Decision

1. **Run a spike on `flutter_readium` first** (plan below). It is the only option that covers EPUB, PDF, TTS and preferences in one native stack, and TTS is a goal.
2. **Fallback if the spike fails:** `flutter_epub_viewer` for EPUB with a separate TTS plugin, or our own renderer.
3. **Put the engine behind a `ReaderEngine` interface** in the app so the choice can change without rewriting screens.
4. **Audiobooks use `just_audio` plus `audio_service`, not Readium.** LibriVox already gives a list of MP3 URLs per chapter. Readium audiobooks need a Readium manifest, which we would have to generate for no gain. `just_audio` handles chapters, background playback and lock-screen controls.
5. **PDF (DOAB):** use Readium's PDF on mobile. For web, evaluate `pdfrx`, or link out. OAPEN PDFs may be untagged, so screen-reader quality is uncertain. Check a sample. Most of the files are in the OAPEN Library, behind a bot check (see "Getting OAPEN PDFs" below), so the PDF has to be fetched by the user's device through a WebView, not by the backend.
6. **Listen while reading: show the viewer and the player together.** Real text/audio syncing needs alignment data inside the publication, which Gutenberg text and a LibriVox recording do not have. Syncing them would be a separate research project (forced alignment). Readium's media overlays do not solve this. **TTS gives a synced read-along for any book**, with no recording needed.

## The `ReaderEngine` interface (sketch)

The app talks only to this. The real implementation wraps the chosen package; tests use a fake.

```
open(ReadingOptions)                      // EPUB or PDF source: URL now, local file later
Stream<ReaderPosition> positions          // where the reader is now
goTo(ReaderPosition)
apply(ReaderSettings)                     // theme, font, size, spacing, page-turner/scroll
tts: start, pause, resume, stop, setRate, setVoice; Stream<TtsState>
dispose()
```

`ReaderPosition` holds the engine's own locator (a Readium locator or an epub CFI) plus a progress fraction from 0 to 1. Bookmarks keep both. The fraction is what we store today (see [app/test/bookmark_store_test.dart](app/test/bookmark_store_test.dart)), and it keeps working across font and view changes. The locator restores the exact place.

## Spike plan

Time-box: a few days. Throwaway app in `spikes/reader/`, not `app/`.

Test material:
* Gutenberg EPUB for book 1342: `https://www.gutenberg.org/ebooks/1342.epub3.images` (it redirects; check that the loader follows it).
* A DOAB book whose PDF is in the OAPEN Library, for example DOAB `20.500.12854/95506` (OAPEN `20.500.12657/60336`), and one from another publisher (IntechOpen serves its PDFs directly).
* A local EPUB file, to prove offline opening.

Devices: a real iPhone and a real Android phone, plus Chrome for web. Simulators are not enough for screen-reader checks.

**Must pass** (otherwise the package is out):

| # | Check | Pass when |
|---|---|---|
| 1 | VoiceOver (iOS) and TalkBack (Android) | Someone can open the book, read it, change pages and reach the controls without looking at the screen |
| 2 | Preferences | Font size, font family (including a dyslexia-friendly one), line, letter and paragraph spacing, and dark/light all change the text; body text meets 4.5:1 contrast in both modes |
| 3 | Page-turner and scroll | Both work and can be switched without losing the place |
| 4 | Position | The locator restores the same place, including after a font size change |
| 5 | TTS | Start, pause, resume, change speed and voice, text highlights as it reads, continues across page turns, keeps going with the screen locked |
| 6 | Loading | The first page shows in well under a minute on a normal connection ("Book should display in viewer in under a minute") |

**Should pass** (note failures, they may be acceptable):

| # | Check |
|---|---|
| 7 | Our own Flutter widgets (settings sheet, player) receive taps over the viewer on mobile and on web |
| 8 | PDF opens on mobile, and screen-reader quality of an OAPEN PDF is acceptable |
| 9 | EPUB loads on web (CORS) and TTS works in Chrome and Safari |
| 10 | Opening from a local file (offline) works |
| 11 | Build setup effort and app size are acceptable |
| 12 | OAPEN PDF through a WebView on mobile: the book page passes OAPEN's bot check in `flutter_inappwebview`, the PDF can be caught (`onDownloadStartRequest`) or fetched with the WebView's cookie and User-Agent, saved to a file, and opened in the reader. Note how long the check takes and what a screen reader announces on the check page |
| 13 | OAPEN on web: the book page and the PDF load inside an iframe (no `X-Frame-Options` or `frame-ancestors` blocking it) in Chrome and Safari, including with third-party cookies blocked |

Record the results in this file under "Spike results". Then fill in the decision above.

## Getting OAPEN PDFs

OAPEN's book pages and PDFs are behind Anubis, a bot check that makes the browser solve a JavaScript puzzle and then sets a cookie (`techaro.lol-anubis-auth`). Plain HTTP clients get `403`. See [api_doab.documentation.md](api_doab.documentation.md).

* **Mobile (preferred):** open the OAPEN book page in an in-app WebView. It passes the check like any browser. Then catch the PDF download, or copy the cookie and fetch the PDF with the same User-Agent (Anubis ties the cookie to the client). Save it to a file and open it in the reader. The user sees the check page for a moment.
* **Web:** the page or PDF can be shown in an iframe with the browser's own PDF viewer, but our code cannot read the file across origins, so there is no TTS, our settings or bookmarks. Browsers that block third-party cookies may break the check inside the frame. Fallback: open in a new tab.
* **Not allowed:** the backend must not solve the check or replay the cookies. That is the scraping the check is there to stop.
* **Also do:** ask DOAB and OAPEN (info@oapen.org, the contact in DOAB's records; OAPEN runs the OAPEN Library and co-runs DOAB) to allow the backend's IP for DOAB's REST API and OAPEN's PDF downloads. A yes removes the WebView step.
* **Not every `.pdf` link is a PDF.** Some publishers answer a `.pdf` URL with a web page. If the file is not a PDF, open the book's DOAB page instead.

Spike checks 12 and 13 test this.

## Offline downloads

2026-10-10: the spec used to say "Does not download books", meaning no offline use. That is dropped. Offline saving is supported in principle. Both viewers fetch the whole EPUB file to open it anyway, so saving a copy is a small step.

* Not scheduled. Decide the milestone later.
* It is user-initiated and stored on the device only (there are no accounts).
* Gutenberg and LibriVox content is public domain. Before enabling it, check: Project Gutenberg's policy on automated and repeated downloads from gutenberg.org, and the licence of each DOAB book (the OAI record has the licence, for example CC BY 4.0), since some licences require attribution or forbid changes.
* Open Library books cannot be saved. They link out.
* The `ReaderEngine.open` input must accept a local file path as well as a URL, so offline needs no redesign.

## Impact on the tests

* [app/test/reader_test.dart](app/test/reader_test.dart): the page-turner, scroll and display-setting tests assume our own renderer (`reader-page-text`, `reader-paragraph-N`, page counts). If a package is adopted, these move to the engine: the screens test our controls and bookmark logic against a fake `ReaderEngine`, and rendering and screen-reader behavior are checked on real devices (the spike checklist above becomes the manual test script). About 40 tests need rewriting, not deleting, once the spike picks an engine.
* [app/test/audio_player_test.dart](app/test/audio_player_test.dart): still valid, since the audio side uses `just_audio` either way.
* [app/test/bookmark_store_test.dart](app/test/bookmark_store_test.dart): add the locator alongside `progress`.
* **New tests needed** for TTS controls (start, pause, rate, voice, announced state) and for offline saving, once those are scheduled.

## Risks

* `flutter_readium` is pre-1.0 and the API may change between versions. Pin the version.
* Neither package's README discusses accessibility, so screen-reader quality is unproven until the spike.
* Native setup (Android desugaring and `FlutterFragmentActivity`, iOS Readium pods, web JS bundle) adds build complexity.
* Web TTS quality depends on the browser's voices.

## Open questions

* Which TTS voices and languages do we need? Books are in several languages and the voice must match the book's language.
* Should a TTS read-along and a LibriVox recording be allowed at the same time? Probably not. One should stop the other.
* Offline downloads: which milestone, and whether audiobooks are included (they are large).

## Sources

* flutter_readium: https://github.com/Notalib/flutter_readium , https://pub.dev/documentation/flutter_readium/0.2.0/
* flutter_epub_viewer: https://pub.dev/packages/flutter_epub_viewer
* Readium toolkits: https://readium.org/
* just_audio: https://pub.dev/packages/just_audio , audio_service: https://pub.dev/packages/audio_service

## Spike results

**2026-10-10, partial. Nothing below has been seen running; only the build and the HTTP checks were done.**

Spike app: `spikes/reader/` (`flutter_readium` 0.6.1, which needs Flutter 3.44.8+; we have 3.47.5). It opens an EPUB URL and has buttons for next/prev, font size, scroll/page view, dark/light, save/restore position, TTS start/stop/pause/resume, and a voice list. It logs the time to open and to first page.

This machine can only run web. No Android SDK, Xcode is incomplete and CocoaPods is missing, and native macOS is unsupported by the plugin. So checks 1, 5 (native TTS), 7, 8, 10 and 12 need a Mac with Xcode (or Android Studio) and real phones.

| # | Result |
|---|---|
| 11 | Web build works: `flutter build web` succeeds after `dart run flutter_readium:copy_js_file web` and two script tags in `web/index.html`. Android and iOS setup (desugaring, `FlutterFragmentActivity`, Podfile) not done yet. |
| 9 | **gutenberg.org sends no CORS headers** (checked on `/ebooks/1342.epub3.images` and the redirect target `/cache/epub/1342/pg1342-images-3.epub`). The browser cannot fetch Gutenberg EPUBs directly, so web needs our backend (or another proxy) to serve them. The file is 24.8 MB for book 1342 with images. The redirect is a plain 302. |
| 9b | **On web the plugin cannot open an `.epub` file.** Run in Chrome, `openPublication('http://localhost:8765/pg1342.epub')` made the ts-toolkit fetch `http://localhost:8765/manifest.json` (404). Web wants a Readium Web Publication Manifest with the book's files served as resources next to it, so the EPUB has to be unpacked and served by a Readium-style streamer. Our backend would need to do this for web (or web needs another reader). Mobile opens EPUB files directly. I tried building Readium's `rwp serve` (go-toolkit) in Docker to test it: `go-toolkit` `main` and tag `v0.16.1` no longer contain `cmd/rwp`, so that did not work and is not tried further. |
| 2, 3 (web) | **Pass with an EPUB-profile manifest; fail with a generic WebPub one.** The user's run on `https://alice.dita.digital/manifest.json` showed that page forward/back, save and restore position work, but font size, dark/light and page view did nothing. Cause (confirmed by driving headless Chromium with Playwright and reading the iframe styles): that manifest has no `conformsTo`, so the plugin uses its generic *WebPubNavigator*, which only supports a zoom variable. With `metadata.conformsTo` = `https://readium.org/webpub-manifest/profiles/epub` the *EpubNavigator* is used and every preference applied: `--USER__fontSize: 120%`, dark background and text colours, line height 1.6, and `readium-paged-on` vs `readium-scroll-on` (two columns in paged mode). So **our backend's manifest for an EPUB must declare the EPUB profile.** |
| 11b | **Readium web sets a Content-Security-Policy that limits styles, images and scripts to the manifest's own origin** (blocked `https://alice.dita.digital/css/core.css` when the manifest came from `localhost:8765`). On web the manifest and all book resources must come from one origin, so our backend has to serve both. |
| 5 (web) | **TTS is unreliable in Chrome.** The user's console log: 199 voices found; the first Start spoke; after Stop and Start again (each Start calls `ttsEnable` then `play`) the third try logged `speechSynthesis stall detected — attempting recovery` (voice `(default)`, `speaking: true`, waited 8000 ms) and then `stall persisted after recovery`, with no audio. So the browser's speech queue wedges after a stop/start cycle. Readium detects the stall and its recovery does not work. Not tried: Safari, Firefox, a reload between runs, choosing an explicit voice instead of the default. Second run (2026-10-10, Gutenberg 1342 from our backend, fresh page): it stalled on the **first** Start too (`voice: "(default)"`, `localService: null`, 199 voices), so it is not only a stop/start problem. Next thing to try, in the app's TTS work: pick a local voice for the book's language with `ttsSetVoice` instead of the browser default. Web TTS is a "Limited" feature in the package's own table, so mobile (native TTS) decides check 5. |
| 11c | Console noise to ignore: the book iframes are in Quirks Mode (no DOCTYPE in the blob documents Readium builds), a sandbox warning (`allow-scripts` + `allow-same-origin`), and a "No positions from manifest, falling back to readingOrder" warning (our manifest should include positions or accept the fallback, which gives coarser progress). |
| 4 | Save/restore position works on web (user report). Restoring after a font-size change not separately confirmed. |
| 9c | **Web with a real Gutenberg EPUB works** (2026-10-10, headless Chromium + screenshot). `spikes/epub_server/serve.py` (about 100 lines, standard library) reads the EPUB zip, builds a Readium manifest (EPUB profile, title, author, language, reading order, resources, table of contents from `nav.xhtml` or the EPUB 2 NCX) and serves the manifest and the files from one origin with CORS. Book 1342 gave 9 reading-order items, 170 resources and 63 TOC entries. The cover and images load, no CSP errors, and font size, dark mode and page/scroll view applied. This is the shape of the backend endpoint web needs. Still to decide for the real endpoint: fetch and cache the EPUB from gutenberg.org, limit the host to gutenberg.org and the size of the zip, and reject paths outside the zip. |
| 9d | **Backend endpoint built** (2026-10-10): `GET /publications/gutenberg/<id>/manifest.json` and `/<file>` in `backend/app/publications.py`, tests in `backend/tests/test_publications.py`. Live: book 1342 (24.8 MB) answered in 1.6 s on first download, book 11 in 0.2 s. Opened in the spike in headless Chromium: pages turn (progress 0.117 after 4 pages), dark mode and images work, and the `Content-Security-Policy: sandbox` header on book files does not break Readium. |
| 2b | **Dark mode hides black line art.** Gutenberg's illustrated editions (1342) have black-on-transparent drawings that nearly vanish on a dark background. Try Readium's image preferences (`imageFilter`, darken/invert) before calling check 2 passed. |
| 6 | Not run. |
| — | To run the spike on web: `cd spikes/reader && flutter run -d web-server --web-port 8080`, then give it a manifest URL such as `http://localhost:8765/alice/manifest.json` (a local copy of the Alice sample with the EPUB profile set; resources still load from alice.dita.digital, so its CSS is blocked by the CSP above). |

Web test source that works without a streamer: a sample Web Publication, `https://alice.dita.digital/manifest.json` (CORS open, checked). Tried 2026-10-10 in Chrome: it opens and shows the book (reported by the user; no timings or other checks recorded yet).

Next: run the app in Chrome and note checks 2, 3, 4, 6; then repeat on an iPhone and an Android phone for 1, 5, 7, 8, 10, 12.
