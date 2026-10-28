# Persona 7 — Sam: round-one review

**Date:** 27 October 2026, evening, America/New_York.

## Perspective, assumptions and method

I am responding as fictional Sam, 41, who uses a screen reader and enlarged phone text, sometimes uses text-to-speech, and reads for pleasure and reference. This is a persona exercise, not firsthand testimony about disability or a claim to represent other people with low vision.

**Assumptions beyond my description:** I am curious about H. G. Wells’s *The Time Machine*, want to compare reading with a human recording, and can use English editions. My phone operating system, preferred screen reader, magnification level and preferred contrast are unspecified; I have not invented them.

The reviewer read `docs/personas.txt`, `docs/personaQuestionsRoundOne.txt` and `AGENTS.md`, without reading other persona reports. They opened a separate browser page at `http://127.0.0.1:8080/`, requested 390×844 and 1366×900 viewports, inspected the home screen and exposed Flutter semantics, and attempted keyboard/pointer search. They made **two successful, source-restricted backend searches**, then checked a publication manifest/content resource and briefly probed one audiobook file.

**Important limits:** The ordinary “Enable accessibility” click timed out. DOM activation plus Tab/Enter exposed semantic nodes. Subsequent search automation changed the input but did not produce a verified results transition; some keyboard attempts duplicated text. This is an automation/instrumentation limitation, **not sufficient evidence that a human or screen-reader user cannot search**. Desktop DOM dimensions changed correctly, but screenshots remained clipped to the original narrow capture area, limiting visual comparison. No successful live enlarged-text/reflow test was completed.

Real VoiceOver, TalkBack, NVDA, magnification and screen-reader speech interaction were **not tested**. Neither were native apps, external source readers, borrowing, or a full long-reading session. Source and test inspection below supplies hypotheses, not proof about the served web build, which may lag source. No builds or tests were run; shared services and product/spec files were not changed.

## 1. My initial impressions; mobile or desktop?

I like the quiet home screen: a prominent search field, a Search button, familiar suggested titles and no account demand in the observed view. The dark presentation is an option I might appreciate, not something my low vision automatically makes preferable.

I would provisionally choose **mobile**, because that is where my established assistive tools are. At 390×844, the home layout wrapped the search categories and suggestions rather than squeezing everything into one row. I could see clear divisions between searching, suggestions and source information.

At 1366×900 the semantic layout measured a centered 640-pixel content group, rather than stretching text across the full width. That sounds helpful, but the clipped screenshot prevents a reliable full-desktop visual verdict. My mobile preference is about my routine, **not a demonstrated accessibility advantage**.

The exposed home semantics included a “Search books” textbox, a named Search button, headings and named source buttons. That is encouraging groundwork. It does not tell me whether focus, announcements and reading order work with my actual screen reader throughout a book.

## 2. My book search and access experience

I chose **“The Time Machine”** as my exact intended query, using the home “Anything” search. The reviewer tried entering it and activating Search through normal automation and then semantic/keyboard instrumentation. The home screen remained; I cannot report a completed browser search or opened reader.

For a bounded fallback, the reviewer requested:

`GET http://127.0.0.1:8000/search?title=The%20Time%20Machine&sources=gutenberg`

The response contained the work *The Time Machine* by H. G. Wells, with text and audio records and no skipped sources. I selected the **text edition, Gutenberg eBook #35**, from that response—not from a clicked result card.

Its reading metadata pointed to `/publications/gutenberg/35/manifest.json`. Fetching that manifest returned the correct title, author, English language and reading-order resources. The first resource, `OEBPS/wrap0000.xhtml`, returned cover XHTML with an image, not narrative text.

**Outcome:** I found a plausible readable edition through the API and verified a manifest and cover resource. I did **not** verify opening, navigating or reading its prose in the app, nor whether the cover has a useful spoken alternative in the rendered reader. A resource response is not a successful accessible reading session.

For me, the important next check is not simply “does the book open?” It is “can I find the first chapter, move by meaningful units, enlarge the text and get back to where I was?”

## 3. My audiobook search and access experience

I used the same exact title, **“The Time Machine”**, restricted to LibriVox through:

`GET http://127.0.0.1:8000/search?title=The%20Time%20Machine&sources=librivox`

The response had no skipped sources. I selected **“Time Machine (Version 6)”**, LibriVox ID **13949**. It supplied a total duration of **12,464 seconds** (about 3 hours 28 minutes), chapter entries and an in-app audio URL. Chapter 1 was listed as 608 seconds.

Because the browser search journey was not completed, the reviewer used a clearly separate **injected HTML audio probe on their own page**, not the app player, for:

`https://www.archive.org/download/time_machine_v6_2008_librivox/timemachine_01_wells_64kb.mp3`

The browser accepted playback. A later check showed approximately **4.94 seconds elapsed**, `paused=false`, ready state 4 and no media error. The reviewer then paused it, cleared its source and removed the probe. A final check found no audio/video elements and no speech synthesis speaking.

**Outcome:** The selected recording’s first file could start and its browser playback position advanced. Nobody verified sound by listening. This does not establish app-player accessibility, chapter transitions, resume behavior or successful listening through assistive technology. The request-aborted event after clearing the source accompanied intentional cleanup, not a demonstrated playback failure.

I would welcome a clearly identified human recording alongside text-to-speech; they are different choices, and I want to know which one I am starting.

## 4. My thoughts on the name

I like **Free Book Reader** because I understand it immediately. I would keep it, with a short explanation such as “Find free books and audiobooks; some open on other sites.” “Reader” alone should not promise that every result uses the same accessible reading environment.

## 5. My three favorite things

1. **The direct, uncluttered starting point.** The observed home screen lets me begin with a named search field rather than registration.
2. **The prospect of text and recorded audio for one title.** Both searches found relevant options; I would value choosing according to the task and my energy.
3. **Accessibility has explicit implementation attention.** Source inspection found adjustable reading settings and named playback controls; accessibility test definitions cover headings, labels, keyboard behavior and enlarged layouts. I appreciate that intention without treating it as verified real-world support.

## 6. My three least favorite things

1. **The home explanation is mostly catalog names.** It does not immediately explain which journey stays here and which takes me elsewhere.
2. **Listening is under-signposted at the start.** The observed home copy says “books” without explicitly advertising audiobooks or distinguishing recordings from read-aloud.
3. **A consistent accessible end-to-end experience remains unproven.** The documented mix of in-app and external reading raises a concern for me, not an observed external-site defect. Reader controls alone cannot guarantee accessible book content or handoffs.

## 7. Features I would want; priorities

**P0 — Validate the complete journey with real assistive technology.** Test search, changing results, edition selection, chapter navigation, reader exit and focus restoration with screen-reader users on supported platforms. Include large system text and magnification. This is a validation priority, not a finding of certified failure.

**P1 — Make access expectations explicit before opening.** I want “Read here,” “Listen here” and “Opens another website,” with clear source/format labels and any account or regional requirements.

**P1 — Make reading controls and speech coexist predictably.** I want easily reached size/spacing settings, meaningful document navigation, a reliable stop control, and a way to avoid app speech talking over my screen reader. Voice choice would interest me. These need live verification, not just controls in source.

**P2 — Preserve my place and preferences across interruptions.** An accessible “Continue reading/listening” entry and confirmation of what will resume would help both pleasure reading and looking something up. I would first verify what already works rather than add duplicate features.

Source context: `app/lib/reader/reader_settings.dart` defines 12–40 font sizes and spacing/preferences; `app/lib/ui/audio_player.dart` names Play/Pause, skips and the position slider. `app/test/accessibility_test.dart` defines semantic, keyboard and 200%-text/320-pixel checks. These were inspected, **not executed**, and do not certify the web reader or external books.

## 8. My overall thoughts

I see a useful, approachable starting point and relevant material, but I cannot yet trust the entire reading journey on the strength of a home screen, API responses and test definitions. I would keep exploring if the app clearly told me where each book opens and demonstrated dependable navigation with my tools. For me, enlargement, speech and screen-reader support are complementary—not substitutes for one another.
