# Round-one UX review — Persona 1: Maya

**Date:** 2026-10-27 (local review date; browser logs crossed into October 28 UTC).

## Exact persona and scope

I am responding as **Persona 1: Maya**, the fictional person in `docs/personas.txt`, not as a real participant or a representative of teenagers:

> Maya is 16 and reads YA novels and graphic novels. She follows BookTok but
> mostly watches rather than posts. She reads on her phone between school and
> other activities, and usually finds her next book through friends, creators, or
> the library.
>
> She is unsure that a catalog focused on older and open-access books will have
> anything for her. A familiar title, an appealing cover, or a recommendation
> from a trusted person might persuade her to search. She expects search results
> to make it clear what a book is and whether she can actually read it. She may
> leave if the app feels like a school assignment or makes her work to understand
> the sources.

**Assumptions beyond that document:** I chose *Heartstopper* as a plausible YA/graphic-novel interest; the persona does not name it. I assumed I would give *Frankenstein*, a suggested familiar title, a chance and try its recording. I used English queries without assuming my nationality, reading ability, budget, disability, or access to a library account.

## Method and limitations

I read root `AGENTS.md` and the eight questions. I used my own browser page at `http://127.0.0.1:8080`, with Playwright viewports of **390 × 844** and **1366 × 900**. I inspected screenshots, Flutter's exposed semantics, browser responses from the existing backend, and a small amount of source. I did not rebuild, install anything, change product code, run suites, or operate the servers.

I distinguish **browser observations**, **API observations**, and **source-based inference** below. The served build may lag the source. Activating Flutter's accessibility placeholder required a programmatic click after an ordinary click could not reach it; some subsequent semantic clicks also timed out, so I used control bounding boxes for Play. These are automation limitations, not proof that human taps or assistive technology fail.

I initially encountered the known local Gutenberg outage. I then received the coordinator's update that PostgreSQL and Gutendex had recovered; my later search actually returned Gutenberg results and opened its reader. I do **not** conclude Gutenberg remains down. I did not test a real phone, native apps, screen readers, headphones/speakers, offline use, external borrowing, or a whole book. I could inspect playback state, but could not personally hear and assess narration.

## Reproducible search/access attempts

1. **Personal-interest search:** On mobile, enter `Heartstopper`, leave **Anything**, all sources, all formats, and any language selected, then Search. The captured request was `http://localhost:8000/search?q=Heartstopper&page=1`, HTTP 200. Its API response contained three works: *Zabójcze piękno* by Joy Fielding (Polish, Open Library), *Eat Fat, Be Healthy* by Matthew Bayan (Open Library), and *Translating Sexuality* (DOAB). Gutenberg was skipped with reason `error`. The browser displayed “3 results for "Heartstopper"” and the missing-Gutenberg warning. I did not find the intended graphic novel, and therefore could not access it. I did not open unrelated books merely to count a successful click.
2. **Familiar-book fallback, after recovery:** Replace the query with `Frankenstein`, retaining Anything/all formats. The captured request was `/search?q=Frankenstein&page=1`, HTTP 200; `skipped` was empty. The browser displayed **51 results**, including a combined Shelley work with Text and Audio. Choose **Read Frankenstein; Or, The Modern Prometheus by Mary Wollstonecraft Shelley**. It opened the in-app reader, not an external site. Next page changed progress from 0% to 3%; I saw the Gutenberg introductory/license material and edition information, including eBook #41445. Frame inspection also found loaded preface text. This verifies opening and initial navigation, not reading the entire novel.
3. **Audiobook refinement/access:** Return to those results and select **Audio**. This triggered another search/refinement; the browser displayed **seven results**, including Gutenberg and LibriVox editions in several languages. Choose **Listen to Frankenstein; Or, The Modern Prometheus by Mary Wollstonecraft Shelley**, the first result. I reached a dedicated player with Play, ±30-second controls, a position slider, and a Chapters heading. After Play, slider semantics progressed to “6 sec of 6 sec” and later “15 sec of 15 sec,” with Pause eventually exposed. This is stronger evidence than a link or HTTP 200, but **not verified audible listening**, complete playback, or correct narration. The selected player showed no chapter entries during this observation. I ended my browser visit by navigating my own page away, preventing continued playback.

I used two query strings and one audio refinement, rather than repeatedly searching every source.

## Q1 — Initial impressions; mobile or desktop?

I prefer **mobile** for how I normally read between activities. The home page gives me a clear search field and a visible Search button. Its dark background and pale controls feel calm. I do not have to create an account before searching.

On desktop, the same narrow, centered home content leaves a lot of empty space; it does not offer extra discovery value. On mobile, however, the source and format controls dominate the results page. In my *Heartstopper* screenshot, the first card starts well below the filters, and only two cards fit before the bottom edge.

The four opening suggestions—*Pride and Prejudice*, *Frankenstein*, *Moby Dick*, and *The Odyssey*—make the collection understandable but also reinforce my worry that this will feel like school reading. I would like an invitation into those stories, not a promise of current YA that the collection cannot keep.

## Q2 — Did I find and access an interesting book?

I did **not** find the *Heartstopper* I meant. Getting unrelated-looking books under a confident result count makes me wonder whether I searched incorrectly. Nothing on those cards explained why they matched. The Polish title also lacked an obvious language label on the visible result card.

I could switch to *Frankenstein* and open an actual in-app book after Gutenberg recovered. That was a worthwhile fallback, but not a substitute for finding my first choice. The reading view initially showed a cover and then lengthy introductory/license material. I would appreciate a clearly labeled route to the contents or story while preserving the original front matter.

I treat the initial source failure as an environment limitation. Separately, clearer matching and collection expectations would still help me when all services work.

## Q3 — Audiobook experience

I found audio without needing to understand what LibriVox is first: **Audio** and **Listen** are useful words. Having a recording option alongside the reader also looks convenient.

The dedicated player was less reassuring. I saw a Chapters heading without chapter choices for my selected edition. I could observe playback position increasing, but the changing “6 sec of 6 sec” / “15 sec of 15 sec” semantics did not communicate a reliable total length. I cannot honestly say I listened successfully just because the control changed to Pause.

As a source-based explanation, `app/lib/ui/audio_player.dart` uses current position when chapter length is unknown, which could explain that moving endpoint; I have not established that this exact source version produced the served build. I would want “duration unavailable” rather than something resembling an entire book lasting fifteen seconds.

## Q4 — The name

I understand **Free Book Reader** immediately, which is useful. But “Reader” makes me expect books to open here, whereas some observed results say **Borrow** and identify Open Library. The name also does not tell me audio is included.

I would keep it for now and add a plain-language description such as “Discover free books and audiobooks—some open here, some on library sites.” A new name would not fix unclear availability or irrelevant results.

## Q5 — My three favorites

1. **A low-commitment start:** I could search and open a Gutenberg book without an app account.
2. **Action words and formats:** Read, Listen, Borrow, Text, and Audio help me see what I can try.
3. **Reading and recording together:** The opened reader included bookmark/display controls and a recording strip. I value that possibility, although I did not validate every control or audible playback.

## Q6 — My three least favorites

1. **Unexplained relevance:** My graphic-novel query returned a different novel, nutrition nonfiction, and scholarship without explaining the connection.
2. **Catalog machinery before stories:** Source names and many chips take prominent mobile space, while the initial suggestions give me little sense of plot, mood, or why I might enjoy them.
3. **Uncertain audio readiness:** An empty Chapters section and a moving apparent total leave me unsure whether I have a complete, usable recording.

## Q7 — Features and prioritized suggestions

**P1 — Help me trust each result.** I want a short description, clear language, format, and “Read here,” “Listen here,” or “Borrow on another site” before opening. If an Anything match is not a title match, explain that or offer a prominent title-only retry. Do not silently present scholarship mentioning a title as that novel.

**P1 — Make audio state honest.** I want a known duration or explicit unknown-duration label, loading/error feedback, and chapters when provided. Hide an empty Chapters section or explain it. Verify audible playback separately from optimistic Play/Pause state.

**P2 — Give the collection a relevant front door.** I would try small, honestly curated collections such as suspenseful classics or short reads, with covers and one-sentence reasons to try them. I would welcome a recommendation from a trusted library or person, but do not assume everyone who watches BookTok wants a social feed.

**P2 — Put mobile results sooner.** Keep search and format accessible, but collapse advanced source controls behind Filters and show active choices compactly. Preserve the source warning.

**P3 — Help me return and share.** I would like a simple saved-to-try list and shareable book links for recommendations from friends. These are requests, not claims that I exhaustively checked their absence.

## Q8 — Overall

I see a useful way to try older stories and recordings without committing to another service first. The recovered Gutenberg reader gave me a real success after an unconvincing first search. I would return for a specific classic or a compelling recommendation, but I would not yet treat this as my usual YA/graphic-novel discovery app. Honest collection framing, trustworthy result explanations, and clearer audio readiness would persuade me more than pretending the catalog contains everything.
