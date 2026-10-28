# Ruth — round-one review

**Date:** 27 October 2026 (local evening; browser logs use 28 October UTC).

## Perspective, assumptions and method

I am responding as the fictional Ruth in `docs/personas.txt`, not as a representative of everyone aged 50. I enjoy classic novels, occasionally compare translations, value comfortable text and resuming, and do not want to learn another complicated app. I read that persona, all eight questions in `docs/personaQuestionsRoundOne.txt`, and `AGENTS.md` before forming these responses. I did not consult other persona reports.

**My explicit assumptions:** I chose Jane Austen's *Pride and Prejudice* as a familiar favorite; the persona does not name one. I assumed English was suitable for this trial. I treated a laptop as an available comparison device, not as a documented preference. I did not assume poor eyesight, a disability, technical inability, or a particular phone.

I used my own browser page at `http://127.0.0.1:8080/`. I requested mobile **390 × 844** and desktop **1366 × 900** with `page.setViewportSize`; browser evaluation confirmed the latter dimensions. The initial mobile screenshot was legible, but subsequent desktop captures were cropped/inconsistent with the reported viewport. That prevents a reliable visual desktop comparison.

Flutter initially exposed only “Enable accessibility.” Ordinary activation timed out; I tried page-local placeholder styling, dispatched activation events and keyboard input. A semantics tree eventually appeared, but activating the title example did not produce an observable results transition. I treat this as an **automation/instrumentation limitation**, not proof that human users cannot search or that the app fails accessibility requirements.

I therefore used two distinct, source-limited API search scenarios below, with repeat retrievals to inspect selected records rather than further exploratory queries. These are **fallback checks**, not completed in-app journeys. I inspected only relevant UI/reader source and existing reader tests; I ran no builds or tests and changed no product behavior. The served web build may lag that source.

## 1. My initial impressions; mobile or desktop?

I immediately understand the name and search box. The familiar example titles reassure me that this collection includes the kinds of novels I want. The initial mobile view has a clear Search button and recognizable Title/Author choices, without asking me to register first.

The list of archive names tells me where the books come from, but I care first about finding a complete, comfortable edition. I would put that reassurance ahead of learning what DOAB or HathiTrust means.

My **provisional preference is mobile**, because that was the layout I could actually inspect cleanly and it felt approachable. I cannot honestly say it beats the desktop design: the attempted desktop comparison was compromised by capture behavior. I would want to compare actual reading pages, not just home screens, before choosing a device for a long novel.

## 2. My book search and access experience

I tried the home-screen **“Pride and Prejudice”** example. The automation focused its semantics node but did not visibly leave Home, even after activation attempts. I cannot count that as a successful app search.

My fallback was the exact request:

`GET http://127.0.0.1:8000/search?title=Pride%20and%20Prejudice&sources=gutenberg`

I found *Pride and Prejudice* by Jane Austen, English, with several Gutenberg editions grouped together. I selected **Gutenberg eBook #1342**. The API marked it open and supplied an in-app publication path; no source was skipped in this restricted search.

I fetched `/publications/gutenberg/1342/manifest.json`, which provided the title, reading order and chapter table of contents. I then opened its actual Chapter I resource in my browser:

`http://127.0.0.1:8000/publications/gutenberg/1342/OEBPS/1306980130634175271_1342-h-0.htm.xhtml#pgepubid00022`

The browser rendered book content rather than merely returning a link or status code. **That verifies readable publication content directly, not the Flutter reader, display adjustments, completeness of the whole novel, or reopening at my saved place.**

I appreciate having edition numbers, but I would still want a plain explanation of why I should pick one edition over another. For translated novels, translator and translation date would matter more to me than an archive's update date. I did not search a translated novel in this bounded trial.

## 3. My audiobook search and access experience

My exact audio request was:

`GET http://127.0.0.1:8000/search?title=Pride%20and%20Prejudice&format=audio&sources=librivox`

I found and selected **Pride and Prejudice (version 3)**, **LibriVox #1480**, narrated by **Karen Savage**. The API reported **37,380 seconds (10 hours 23 minutes)** and chapter information, with no skipped source in that search.

I followed the first chapter's media URL directly:

`https://www.archive.org/download/pride_prejudice_krs_librivox/pride_and_prejudice_01_austen_64kb.mp3`

It redirected to an Internet Archive media host. The browser's native media element had a duration of about **284 seconds**, was playing, and advanced from approximately **2.47 to 4.96 seconds**. I then paused it and confirmed `paused: true`; I returned my page to Home, where no media element remained.

This is encouraging for listening during routine tasks, especially because the narrator and duration let me make a choice. **I verified advancing media time, not sound heard, the app's player, later chapters, background playback, or audio resume.** I would not describe this as a completed in-app listening test.

## 4. My thoughts on the name

I would keep **Free Book Reader**. It tells me the basic benefit without requiring me to learn a brand. I would add a short explanation such as “Classic books and audiobooks, with some books opening at their library.” That would acknowledge listening and avoid suggesting every result behaves identically.

## 5. My three favorite things

1. **Familiar classics right on Home.** The visible Austen example gives me an immediate starting point instead of an empty catalog.
2. **A choice of text and recorded audio for my chosen novel.** My API and direct-resource checks found both, including a named narrator and duration; I have not verified the combined app journey.
3. **Display controls designed around sustained reading.** In `app/lib/reader/settings_sheet.dart`, I found text size, font, light/dark colors, pages/scroll and line/letter/paragraph spacing. These suit my documented priorities, although I did not operate them in the served reader.

## 6. My three least favorite things

1. **I still have to interpret editions.** Several Gutenberg IDs were returned; numbers alone do not tell me which text is complete or why one is preferable. This is a concern raised by the API result and inspected details UI, not a fully observed comparison-screen test.
2. **Getting back to my place appears too deliberate.** `reader_page.dart` saves a position when I explicitly add a bookmark and loads that bookmark on entry. I did not see automatic position-saving there, and Home has no continue-reading entry in its source. That would be less effortless than my e-reader. I did not verify persistence live.
3. **Source names compete with my immediate purpose.** On the observed mobile Home, five “About” destinations take substantial space. Useful provenance is welcome, but I would rather first see a short path to reading or listening.

## 7. Features I would welcome; my priorities

**P1 — Effortless return:** I want a visible “Continue reading/listening,” automatic last-position saving, and an explanation of whether progress stays on this device. Existing bookmark/display tests are useful evidence of intended behavior, not proof of this broader journey.

**P1 — Confidence before opening:** I want a concise edition comparison: complete/abridged/unknown, language, translator where known, illustrations, and “reads here” versus “opens another site.” Unknown facts should remain explicitly unknown, not be guessed from a title or a successful download.

**P2 — Easy comfort check:** I want to preview a paragraph with larger text and looser spacing and immediately see the result. The source already supplies many controls; I recommend making their discovery and persistence easy to verify, not rebuilding them.

**P2 — Listening choices without homework:** I want narrator, total length and a short sample beside each recording. I would also value clearly remembered chapter/time and a sleep timer, subject to a real-device playback check.

## 8. My overall view

I see a promising route back to novels I already enjoy, with recorded listening as a useful companion rather than a separate hunt. The directly opened text and advancing audio make the catalog more than a list of promising links.

I would try it again, but my confidence would depend on three practical demonstrations: choose the right edition, make the text comfortable, and return tomorrow to the right place. I cannot yet claim those worked end to end.

My conclusions exclude native Android/iOS, e-reader transfer, real touch interaction, screen-reader/keyboard accessibility, audible quality, background/locked-screen audio, external account/borrowing flows, offline use and full-book completeness. I did not reproduce an outage; the two restricted backend searches succeeded, and I did not retest all sources. My highest-priority recommendations follow Ruth's stated reading habits, not assumptions about her age.
