# Priya — round-one review

**Date:** 27 October 2026, approximately 20:28–20:34 EDT.  
**Perspective:** I am Priya, 33, balancing shifts and caring for a family member. I want free listening that fits interruptions, without account setup or troubleshooting.

## My method, assumptions and limits

I am a fictional persona walkthrough, not an interview with a real participant. I read `docs/personas.txt`, `docs/personaQuestionsRoundOne.txt` and `AGENTS.md`; I did not consult other reviewers' reports.

I assume, beyond my description, that I am comfortable trying English-language fiction and that *The Time Machine* and *Pride and Prejudice* might interest me. Those are exploration choices, not assumptions about my background, cultural interests, or reading ability. I assume I would normally use a phone while travelling, although my persona does not specify a device.

I used my own browser page at `http://127.0.0.1:8080`, requesting 390×844 mobile and 1366×900 desktop viewports. I inspected screenshots and browser semantics. Flutter's “Enable accessibility” placeholder could not be clicked normally; I activated it programmatically. Text entry also needed instrumentation: ordinary automation sometimes failed to update Flutter or inserted text in the middle. These are method limitations, not established human typing or accessibility defects.

My initial desktop home screenshot rendered a centered, wider layout; mobile used a narrow, stacked layout. Later resizing produced inconsistent snapshots/cropped screenshots and stale search-field content, so I cannot confidently judge desktop results or playback responsiveness. The existing web build may differ from current source.

I submitted three distinct query strings, including one accidental automation-corrupted query, then selected Audio on the successful audiobook query. That filter triggered another loading state. I made no separate API calls, ran no tests/builds, and changed no services or product files. I did not reproduce the earlier PostgreSQL outage: Gutenberg reading worked in my session.

I inspected `app/lib/ui/audio_page.dart`, `audio_player.dart`, and relevant portions/test names of `app/test/audio_player_test.dart` as a fallback. Source and fake-backed tests describe intended behavior; they do not prove this browser build or real streaming works.

## 1. My initial impressions and preferred view

I like having a search box immediately, with no account demand in the journey I tried. The dark home screen is restrained rather than busy. Suggested titles give me somewhere to begin, but the introduction mostly names catalogs. If I have ten minutes before leaving, “Find free audiobooks” would tell me more than knowing what DOAB is.

I prefer the **mobile home view for my likely use**, not because desktop looked bad: the search and suggested titles fit the narrow screen, and I would have my phone during chores or travel. Desktop's centered home layout was comfortable too. On mobile results, several rows of search/source/format controls came before the first book; I would rather reach a playable suggestion sooner.

## 2. My book search and reading experience

**Exact query:** `The Time Machine`, with Anything and all sources/formats initially selected.

I entered the query, pressed Search, and received **54 results**. I selected **“Read The Time Machine by H. G. Wells”**, whose result grouped Project Gutenberg, LibriVox and Open Library and identified Text and Audio.

The in-app reader opened. I used Next page several times: I saw Gutenberg front matter and subsequently visible story prose headed **“II. The Machine.”** This was actual rendered book content, not merely a working URL or successful HTTP response. I verified opening and viewing part of the text, not reading the whole edition or reliable long-session pagination.

I appreciated the recording strip under the reader. However, the first visible reading material was publication/legal information, not the story, and the compact strip initially said only “LibriVox recording.” In a short break, I want a clear route to the story and a clear sense of the listening commitment.

## 3. My audiobook search and access attempt

**Intended and successful query:** `Pride and Prejudice`.

While replacing my previous query, automation accidentally submitted **`The Time MachPride and Prejudiceine`**, which returned no results. I do not attribute that string to a normal user or count its failure against search relevance. After correcting the field with an input event, I submitted the exact intended query.

I selected **Audio**. The resulting list contained **two results**:

- *Pride and Prejudice* — Jane Austen, Project Gutenberg/LibriVox, Audio.
- *Pride and Prejudice: A Play* — Jane Austen and Mary Medbery Mackaye, LibriVox, Audio.

I chose **“Listen to Pride and Prejudice by Jane Austen.”** Ordinary automated clicks timed out waiting for the target to be stable; a programmatic click and an Enter attempt did not produce an observed audio page. Resizing further complicated automation. I stopped rather than keep generating searches or claim that playback was broken for people.

**Access outcome:** I found an explicitly audio-labelled result and attempted access, but did **not verify the audiobook page, streaming, advancing playback position, or audible sound**. I never successfully started playback. My final page check found no audio/video elements, and I navigated my own page to `about:blank` to end the session.

In source, I found an audio page intended to show narrators, total length, chapter lengths and a position slider; its controller implements play/pause, 30-second skips, retry messaging and chapter progression. These would help me, but I cannot present them as successfully exercised browser features. The fake-backed tests are not listening evidence.

## 4. My thoughts on “Free Book Reader”

I understand the price promise, but “Reader” makes audio sound secondary. I would keep the recognizable name initially and add **“Free books and audiobooks”** prominently. I would consider “Free Books & Listening” only after testing whether others understand it. A rename matters less to me than seeing that I can listen now, without an account.

## 5. My three favorite things

1. **I could start without registration.** My successful text journey did not ask me to set up an account.
2. **I could distinguish audio results.** The Audio filter and Listen action made the Austen results' format clear.
3. **I could see reading and a recording entry point together.** The Wells reader kept the recording strip alongside visible text, suggesting less navigation when I change activities.

## 6. My three least favorite things

1. **I have to get past catalog-oriented controls to reach books.** On mobile results, source and field choices occupy substantial space before the first title.
2. **I cannot judge time commitment from the audio result cards I saw.** They showed Audio/Listen, not total or first-chapter duration.
3. **I cannot yet trust the reading/listening handoff.** The visible recording strip did not explain position correspondence. The test file explicitly notes that text/audio position syncing is not covered; I should not assume the recording follows my reading place.

## 7. Features I would want and my priorities

**P1 — Help me choose quickly.** I want an audio-first home shortcut and result cards showing total duration, narrator, and a short first segment where available. Keep catalog filters available but less dominant. I want “Listen” to describe an action, not imply that this particular session has verified playability.

**P1 — Make interruptions safe.** I want a prominent Continue listening entry and a durable chapter/time bookmark after leaving and returning. The controller's in-session pause position is not proof of persistence across page closure. Validate real phone interruption, background and headset behavior before promising it.

**P2 — Explain the handoff.** I want “Read this book” beside the recording and an honest label if text and audio positions are independent. Shared placement is useful; automatic synchronization must not be implied without implementation and validation.

**P2 — Add practical listening tools.** I would value a sleep timer, recording speed control and intentional offline saving. I did not verify these features in the browser; this is a wish list, not a claim that every one is absent.

## 8. My overall assessment

I see a useful free starting point: I genuinely opened readable fiction, and the audio filter found a plausible listening choice without registration. For my limited uninterrupted time, the next improvement is a shorter path from “I have a few minutes” to a recording with a known length and a trustworthy return point.

I would try it again, but I would not yet rely on it for a commute based on this review. Native apps, actual phones, assistive technology, external-source/account journeys, poor connectivity, offline use, background playback and audible output remain untested. My automation difficulty opening Listen is an unresolved verification limit, not a confirmed playback or accessibility defect.
