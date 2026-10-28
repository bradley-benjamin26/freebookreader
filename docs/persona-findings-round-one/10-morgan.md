# Morgan — round-one review

**Date:** 2026-10-27, approximately 20:33–20:37 EDT.

## Perspective, method and limits

I am responding as fictional Morgan, 38: I enjoy nonfiction and mysteries in print, find dense digital pages tiring, and have unreliable home broadband. This is a persona-based evaluation, **not testing with a real dyslexic reader**.

I read `docs/personas.txt`, `docs/personaQuestionsRoundOne.txt` and `AGENTS.md` before exploring. I did not read other reviewers' reports. I used my own browser page at `http://127.0.0.1:8080`, comparing 390×844 mobile and 1366×900 desktop viewports. I explored two distinct mystery queries, an in-app chapter, display settings and an audiobook player. Reapplying an Audio filter reused a query; I did not systematically search all sources. I made no product changes or service changes and ran no builds or test suites.

**My explicit assumptions:** I chose Sherlock Holmes as a plausible mystery interest; the persona does not name a favorite author. I assumed I would welcome audio as an alternative when a digital page becomes tiring, not that dyslexia necessarily implies an audiobook preference. I have no evidence about Morgan's particular device, preferred font, colors or assistive technology.

Flutter initially exposed only “Enable accessibility.” I activated its semantics using a dispatched click because the ordinary automation click was outside the viewport. Some subsequent semantic clicks were intercepted; I used dispatched clicks and direct input filling, sometimes retrying after values reset. These are automation limitations, not sufficient evidence that a person cannot operate the controls. I distinguish screenshots and browser state from my limited source inspection below. The existing web build may lag the source.

I did not test a real phone, native apps, screen readers, external-site reading, degraded connectivity, offline use, long-session comfort, or TTS. I cannot hear browser audio through these tools. A running playback position is not proof of audible sound.

## 1. My first impression and preferred view

I like having a single obvious search box, a short explanation and no account barrier in the journey I tried. The dark home screen feels relatively uncluttered. I can choose title, author or subject without learning a special search syntax.

I prefer **desktop for reading in this session**, rather than declaring it inherently better for me. Its centered home content feels contained, and the reader has more room. On mobile the home choices wrap sensibly, but the chapter at my selected size looks dense: justified lines spread words unevenly and split several words across lines. That is precisely the kind of page I would want to adjust before settling in. Desktop also showed a two-column publication layout, so more space alone does not solve every reading preference.

I would still want mobile for convenience; a viewport simulation cannot tell me how comfortable either is over an evening.

## 2. My book search and reading access

I searched **`The Adventures of Sherlock Holmes`**, using Anything with all sources selected. After “Searching,” I saw **24 results**, including the exact Arthur Conan Doyle title, other Holmes books, adaptations and scholarly titles. I selected **“Read The Adventures of Sherlock Holmes by Arthur Conan Doyle.”**

That opened an in-app publication, initially a cover rather than story text. I opened Display settings, changed **Text size 18 → 20** and selected **Sans serif**; both selected states changed. I advanced to the Gutenberg front matter and contents, then activated **“A Scandal in Bohemia.”** A screenshot showed the chapter heading and opening prose on mobile. That is verified delivery of actual reading content, not merely a working link or an HTTP success. I did not finish the chapter or test returning tomorrow.

I found Pages/Scroll, Light/Dark, four font choices and line, letter and paragraph spacing controls. I selected Scroll and saw that choice checked and page controls disappear afterward. My attempted keyboard adjustment of line spacing did not establish a changed value, so I cannot claim I verified spacing changes visually or found my ideal setup.

The mobile chapter still appeared tightly packed and justified after the size/font change. I would want a quick way to shorten the line, turn off justification and hyphenation, and preview spacing without repeatedly closing settings.

I also noticed results explicitly saying “View … at Open Library,” “Borrow … at Open Library,” and “View … at HathiTrust,” unlike the in-app Read action. That distinction helps. I did not follow those external routes, so I cannot judge their reading experience or account requirements.

## 3. My audiobook search and access

I searched **`The Hound of the Baskervilles`**, then selected **Audio**. The final browser state showed **two results for that exact query**. I selected **“Hound of the Baskervilles (Version 6)” by Sir Arthur Conan Doyle**, from LibriVox.

Its in-app audio page identified **Richard Reiman** as reader, gave **6 hr 52 min** total length, and listed named chapters with durations. I started playback with the Play action after an ordinary automated click was intercepted. The button became Pause, and the playback slider's accessible text advanced from **“4 sec of 17 min” to “6 sec of 17 min”** for the opening chapter, “Mr. Sherlock Holmes.”

I therefore reached a player and observed advancing playback state. **I did not verify sound or recording quality**, uninterrupted streaming or recovery after a broadband drop. I paused it before finishing and verified Play was present, Pause absent, and the position still six seconds on a subsequent check.

For me, named chapters and durations are useful ways to judge the commitment. I would also want explicit download status and expected data size before relying on this away from a good connection.

## 4. My reaction to “Free Book Reader”

I understand the name immediately and would keep it. My concern is its promise, not its style: “Reader” might make me assume every result opens here, and “free” does not explain borrowing or connectivity. I would add a plain-language description such as **“Find free books and audiobooks—some open on other libraries' sites.”** I would not rename it to imply offline reading until that is genuinely supported.

## 5. My three favorite things

1. **I reached a real mystery chapter in-app**, without an account prompt in the tested path.
2. **Display controls are close to the book**, including ordinary font choices, text size, spacing and Pages/Scroll—not a single supposed universal dyslexia solution.
3. **The audiobook page explains the listening commitment**, with narrator, total length and named chapters.

## 6. My three least favorite things

1. **The mobile prose still looks demanding to me**, with dense justified lines and conspicuous word breaks at the tested setting.
2. **I cannot confidently plan for a bad-connection evening.** I found no clear offline-readiness or download status in the screens I visited; loading a chapter today is not evidence that it is saved.
3. **“Dyslexia friendly” suggests a stronger font guarantee than I can establish.** As source evidence—not a runtime font measurement—`app/lib/reader/reader_settings.dart` has a TODO to bundle that font and says the choice currently falls back to a platform font. I would prefer an honest font name and availability explanation over a reassuring label alone.

## 7. Features I would want and my priorities

**P0 — Set trustworthy access expectations.** I want each result to say “Read here,” “Listen here,” “Opens another site,” or “Borrow at Open Library,” plus a clear online/offline statement before opening it. Existing external action wording is a useful start; I would make the connectivity promise equally explicit.

**P1 — Let me make a genuinely less tiring page.** I want alignment and hyphenation controls, a comfortable adjustable text width, numeric spacing values and a live sample. I would like to save my own preset, rather than being told one font works for everyone. Bundle and identify the advertised font, or disclose its fallback. I would prioritize real dyslexic participants trying sustained reading over treating this fictional review as validation.

**P2 — Build verifiable preparation for poor connectivity.** I want an explicit save/download flow with size, progress, failure/retry and a “ready offline” state only after the required content is available. If offline reading is not available, tell me so now. Audio chapter downloads would interest me too. I have not verified that either capability currently exists or works reliably.

## 8. My overall view

I see a promising route from a familiar mystery to text or a clearly described recording. I would experiment with it, especially because I can change the display without leaving the reader. I am not yet ready to depend on it as my bad-broadband reading plan. My deciding factors would be whether I can make the actual prose comfortable—not merely see setting labels—and whether I can tell, before losing connectivity, exactly what I will still be able to open.
