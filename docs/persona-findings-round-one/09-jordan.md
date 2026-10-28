# Jordan — round-one UX findings

**Date:** 2026-10-27 (local evening; browser logs use 2026-10-28 UTC).  
**Perspective:** I am Jordan, 27, working in food service. I seldom finish books and usually choose podcasts, video essays, or games. I am exploring a curiosity, not trying to become a “proper reader.”

## Assumptions and method

I assumed a video essay had made me curious about time travel and that I recognized *The Time Machine* as a possible next step. Neither that particular interest nor familiarity with that title is specified in my persona. I assumed English was suitable for this exercise. My preference between screen sizes below is a reaction to these screens, not an assumption about what devices someone in my job owns.

I read `docs/personas.txt`, `docs/personaQuestionsRoundOne.txt`, and `AGENTS.md` before forming this report, without reading other persona reports. I used my own new browser page at `http://127.0.0.1:8080`, with 390×844 mobile and 1366×900 desktop viewports. These were resized browser views, not physical devices. I inspected screenshots and browser semantics, and made three bounded search configurations: a topic, a title, and that title filtered to audio.

Flutter's “Enable accessibility” placeholder was outside the actionable viewport. I activated it through a DOM click to expose semantics. The audio Play/Pause controls also required DOM activation after a pointer-interception timeout. These are automation limitations, not proof that a person cannot tap the controls. I did not run a screen reader or an accessibility audit.

My observations concern the served web build, which may lag repository source. I checked only `app/lib/ui/audio_player.dart` and `app/lib/services/audio_engine.dart` to interpret the audio behavior. I did not change product code, inspect other reports, run builds/tests, or control the shared servers. Native devices, external borrowing/reading sites, network resilience, and sustained reading/listening remain untested. I cannot hear browser sound through these tools.

## 1. My initial impressions and preferred view

I like that I can start without an account or a setup questionnaire. The page is calm, the search box is obvious, and “Try one of these” gives me something to do if I draw a blank.

However, the first explanation introduces five catalog names, including DOAB and HathiTrust. Those names do not tell me what experience I will get. “Anything,” “Subject,” and “ISBN” make this feel more like a catalog than an invitation to follow a curiosity. The suggested classics are usable entry points, but there is no short explanation of what might hook me.

For this visit, I prefer desktop results. Filters sit beside the books rather than above them. On the mobile results screen, the search controls, five source choices, format, and language filled roughly the first half of the screen before results appeared. I would rather see a promising book quickly. The mobile home page itself wraps its buttons cleanly; my preference is about getting to something worthwhile, not a claim that mobile is unusable.

## 2. My book search and access experience

**First query:** `time travel`, using **Anything**, all sources, all formats.

I typed the topic on mobile and pressed Search. I saw a loading indicator, then 54 results and a notice that Open Library was too slow and some results might be missing. The first visible desktop results were volumes of Robert Kerr's *A General History and Collection of Voyages and Travels*, beginning with Volume 10.

That was discouraging: I wanted the idea of travelling through time, not historical travel collections. I cannot tell from the UI why these results matched. I did not open those volumes, and I am not claiming every result was irrelevant; the first screen did not make my intended topic feel understood.

**Second query:** `The Time Machine`, with **Title** selected, all sources/formats.

I changed the query and search field on desktop. This returned nine results. I selected **Read The Time Machine by H. G. Wells**, whose result combined Project Gutenberg, LibriVox, and Open Library and said “Text and Audio.”

The in-app reader opened. I initially encountered cover/front matter; after Next page, I saw publication information and a contents table. I followed **Introduction** and saw actual narrative paragraphs, with progress changing to **5% read**. This verifies readable story content in the web reader—not merely a working link or an HTTP response. I did not finish a chapter, test resuming later, or compare the full edition.

That successful second attempt matters: I could try a story without committing to finishing it. But I needed a known title to recover from my topic search. Someone arriving with only a loose reference might leave before that.

## 3. My audiobook search and access experience

**Third configuration:** I returned from the reader and selected **Audio** for the same exact query, `The Time Machine`. The returned screen showed **Anything** selected, rather than the previous Title selection.

I got one result, **The time machine — H. G. Wells**, labeled Project Gutenberg, LibriVox, Audio. I chose **Listen to The time machine by H. G. Wells**. The player opened inside the app with Play and 30-second skips. No account or external-site journey was required in the steps I tested.

After activating Play, the control changed to Pause. The slider's accessible text advanced from **“9 sec of 9 sec”** to **“12 sec of 12 sec.”** I therefore observed playback-position advancement, but **did not verify audible narration or sound quality**. The visible Chapters heading had no entries in this session, and the screen did not give me a useful total listening duration.

The source provides a possible explanation, not a verified diagnosis of this build: `AudioPlayerPanel` falls back to the current position when chapter length is unknown, which can produce that changing “of” value. `AudioController` also supports a recording without chapter entries. I would not interpret “12 sec of 12 sec” as this audiobook really lasting twelve seconds.

I paused playback; the control returned to **Play** with the position at twelve seconds. Audio was left paused on my own page.

## 4. My thoughts on the name

“Free Book Reader” tells me the price and the basic purpose clearly. I would keep that clarity rather than rename it just to sound fashionable. But “Reader” does not tell me I can listen, and it sounds aimed at people who already choose books.

I would try a subtitle such as **“Read or listen. Follow your curiosity.”** That better matches why I would visit, without promising a modern podcast or new-release catalog.

## 5. My three favorite things

1. **I can try something without signing up.** My curiosity can remain a small experiment.
2. **I actually reached the story in-app.** The title search led to readable narrative rather than just another catalog page.
3. **Audio is a real route through the interface.** The Audio filter and Listen action are easy to understand once I find them, and playback position advanced.

## 6. My three least favorite things

1. **My topic search did not feel relevant at the top.** Long travel-history volume titles made a simple curiosity feel like research work.
2. **Catalog decisions come before the payoff.** Source names and many filters take prominent mobile space before I see a book.
3. **I cannot judge the listening commitment.** The tested player had an empty Chapters section and no trustworthy total duration, despite its playback state changing.

## 7. Features that would interest me, in priority order

- **P1 — Help my topic find an approachable starting point.** Explain why a result matches; distinguish a phrase such as “time travel” from scattered matching words. Offer clearly labeled title suggestions when appropriate, without pretending every topic has a perfect match.
- **P1 — Let me sample before committing.** Put a short, factual, spoiler-light description beside a “Try the opening” or “Start listening” action. Show known audio duration, or plainly say it is unavailable. Do not frame sampling as a challenge to finish.
- **P2 — Simplify the first mobile results screen.** Keep Text/Audio readily available, but tuck detailed source choices behind an understandable filter control. Retain the useful missing-results notice.
- **P2 — Make audio state understandable.** Show elapsed time separately from an unknown total; hide an empty chapter section or explain that this recording has no chapter list.
- **P3 — Offer optional, low-pressure return paths.** I would be interested in “Save for later” and resuming a sample, without streaks or guilt. I did not test existing bookmark/resume behavior, so these are desired experiences, not claims that all saving is absent.

## 8. My overall thoughts

I found a worthwhile first visit only after turning my topic into a specific title. I could see the opening of a story and initiate an audio experience without a membership funnel. That is a good foundation.

I would not yet return just to browse unfamiliar archive results. My biggest need is a bridge from “that idea sounded interesting” to “here is something I can try now.” Better first-result relevance and an honest, inviting sample would matter more to me than adding more catalog controls or encouraging me to read more.
