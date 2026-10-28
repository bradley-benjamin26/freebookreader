# Round one — Daniel

**Date:** 2026-10-27 (local evening; browser logs use 2026-10-28 UTC).  
**Exact persona:** Persona 2: Daniel, from `docs/personas.txt`.

> Daniel is 22 and an English graduate student. He reads older literature for
> class, but also looks for open-access scholarship for his research. He is
> comfortable trying unfamiliar software and can work around a rough edge, but
> not when it wastes time or returns misleading results.
>
> He often knows the title, author, or ISBN he wants. He expects a precise search,
> useful distinctions between editions, and enough source information to judge a
> result. For broad research he wants to understand why a book appeared and
> whether it is scholarship, a primary text, or something else.
>
> Explore: How should known-item search differ from exploratory search? Which
> edition and source details are essential before he opens a result?

## Assumptions and method

I am a fictional perspective, not an actual participant or a representative of
all graduate students. I assume that *Frankenstein* interests me, that comparing
its 1818 and 1831 texts is useful, and that I want an English-language recording.
Those particular interests, my preference for desktop research, and my feature
priorities below are assumptions, not facts supplied by the persona.

I read the persona, all eight questions, and root `AGENTS.md`. I used my own
browser page at `http://127.0.0.1:8080`, with desktop **1366×900** and mobile-sized
**390×844** viewports. I inspected screenshots and Flutter's exposed semantics,
opened edition details and the web reader, and tried audio. I made two distinct
searches: Title = `Frankenstein`, then the same title with Audio selected. API
checks used `http://127.0.0.1:8000`; repeats of the title request checked recovery
and inspected its results rather than exploring more titles.

**Evidence boundaries:** “Browser” below describes the existing served build,
not necessarily current source. “API” describes live backend responses.
“Source” is a separate inference from `app/lib/ui/{home_page,search_bar,
results_page,details_page,audio_player}.dart` and
`app/lib/services/audio_engine.dart`; I did not rebuild or run tests.

My browser reported `document.visibilityState = hidden`, and initial ordinary
clicks and frames were unreliable. I enabled Flutter semantics, used DOM
activation where needed, and applied an own-page animation-frame-to-timer shim
after a reload. This is review instrumentation, not a product change. I therefore
do not treat those early interaction delays as demonstrated app defects or report
task timings. I did not test native apps, real phones, assistive technology,
offline use, borrowing accounts, or sustained reading. I did not complete a
separate subject/ISBN or scholarly-book access task.

## Q1 — Initial impressions; mobile or desktop?

I immediately understand that I can search rather than register. The home page
names five sources, offers Title, Author, Subject and ISBN alongside Anything,
and provides source-information links. The sample classics make the literature
side relevant to me. They do less to explain the scholarship side: I would not
infer from “DOAB” alone what research material I might find.

I prefer desktop for this task. In the observed results layout, source, format
and language filters sit beside the list, so I can compare results without first
scrolling past them. At 390×844 the chips wrap into several rows above the first
result; ISBN moves onto another row. The first card remains readable, but the
filter block consumes substantial vertical space and long titles wrap. Mobile
looks usable for a quick lookup; desktop better supports edition comparison.
This is viewport evidence, not a real-device endorsement.

## Q2 — A personally relevant book: finding and accessing it

I chose *Frankenstein* to see whether I could select a text rather than merely
recognize a title.

| Reproducible attempt | Observed outcome |
|---|---|
| API: `curl --get 'http://127.0.0.1:8000/search' --data-urlencode 'title=Frankenstein'` before recovery | I received results from other sources, with `gutenberg` skipped for reason `error`. |
| Repeat that title request after the recovery notification | I received Gutenberg results too; `skipped` was empty in that response. |
| Browser: home → **Frankenstein** example (Title search) | I saw **9 results**, including one combined work from Gutenberg, HathiTrust, LibriVox and Open Library. |
| Open the first result's card → select **Read** on Gutenberg **eBook #41445** | I reached the in-app publication reader. Its loaded content identified the 1818 publication; Next page exposed the Gutenberg front matter and transcriber's note identifying a photo-reprint of the 1818 edition. |

The initial failure was the supplied PostgreSQL/Gutendex environment problem.
The environment was repaired during my review; it did **not** remain down. I
did not repair infrastructure myself. Cache state could affect another attempt.

I found the edition details genuinely useful. The browser distinguished #41445,
with original publication in 1818, from #42324, with original publication in
1831, and also listed #84. Release/update dates were separately labelled. That
lets me avoid mistaking a recent digital update for the historical edition.
I verified loaded reading content, not just an HTTP success or a Read button;
I did not verify every chapter or textual accuracy.

The list still makes me investigate. “Mary Wollstonecraft Shelley and Mary
Shelley” appears as two author names on the combined work. Other rows include
*Frankenstein* by Ian Thorne and a DOAB result with “Unknown author.” I cannot
tell from those cards alone whether I am seeing my primary text, an adaptation,
or scholarship. I am not claiming those records are incorrectly matched; I want
the distinction explained before I open them. For scholarly research, “a title
matched” is not yet a relevance judgement.

## Q3 — Audiobook search and access

I kept the same title and selected **Audio**, rather than starting an unrelated
catalog search.

| Reproducible attempt | Observed outcome |
|---|---|
| API: `curl --get 'http://127.0.0.1:8000/search' --data-urlencode 'title=Frankenstein' --data-urlencode 'format=audio'` | I received **6 works**, with no skipped sources in that response. |
| Browser: Title = `Frankenstein` → **Audio** | I saw six results, including separately labelled 1818 and 1831 recordings. |
| **Listen** on *Frankenstein; or The Modern Prometheus (1818)* | I reached an audio page naming **Cori Samuel**, **7 hr 59 min**, and a chapter list beginning “01 - Dedication and Preface.” |
| Activate **Play**, inspect progress, then **Pause** | Play changed to Pause; the playback-position semantics advanced from **5 sec of 4 min** to **9 sec of 4 min**. Pause returned the control to Play. |

I verified player progress, which is stronger evidence than a recording URL or
an optimistic Pause icon alone. I could not independently hear or judge the
output, so I would describe this as **playback progress observed, audible
listening not verified**. A DOM query found no attached audio/video elements;
I did not infer failure from that. Source inspection also shows that the
controller sets its playing state before loading finishes, which is why the
icon alone would have been insufficient.

I like having narrator, total length and named chapters before committing to a
recording. For class work, the explicit 1818 label matters more than a generic
“version” number. I would still want assurance that the text and recording I
select correspond; I did not test synchronization or read-aloud.

## Q4 — The name Free Book Reader

I find it direct and unpretentious. I would keep it, but add a plain-language
description such as “Search classics, open-access books and free audiobooks.”
“Reader” alone understates the cross-catalog discovery function, while “free”
could make me expect every result to open immediately inside the app.

I saw distinct Read, Listen, Borrow and View actions. Source inspection shows
the details page can explain that Open Library borrowing needs a free account.
I would make those conditions apparent consistently in results rather than
rename the product to imply universal immediate access.

## Q5 — My three favorites

1. **Known-item controls without an account gate.** I can see Title, Author and
   ISBN choices immediately, rather than guess what one opaque search box does.
2. **Useful edition provenance.** The observed 1818/1831 original-publication
   information, eBook numbers and separate digital dates help me choose a text.
3. **Multiple access routes with real audio detail.** The combined work exposes
   several sources, while the recording page identifies narrator, duration and
   chapters; I observed progressing playback and could pause it.

## Q6 — My three least favorites

1. **Unexplained identity and relevance differences.** Duplicate author-name
   variants and similarly titled works leave me doing interpretation that the
   catalog could help with.
2. **Comparison requires opening and scanning long details.** The first result
   combines many editions and recordings. I appreciate the “Show all 12
   HathiTrust volumes” restraint, but I still want edition-level comparison
   before opening one, especially on mobile.
3. **Uneven discovery cues.** Several observed covers fell back to book icons;
   the console reported cross-origin cover failures. More importantly to me,
   result cards do not establish scholarly status or explain a match. I cannot
   conclude a DOAB title is relevant scholarship merely from its source badge.

## Q7 — Features I would want; prioritized suggestions

- **P1 — Separate known-item precision from exploration.** Let me combine title
  and author, identify the requested ISBN's edition, and see an explicit match
  explanation. The inspected search-bar source selects one term field at a
  time; I have not tested backend multi-field behavior here.
- **P1 — Make editions comparable.** Offer a compact comparison of original
  publication, edition/translation, editor, publisher, identifiers, language,
  source and access conditions where supplied. Preserve unknowns honestly.
  Keep digital release dates clearly separate from historical publication.
- **P1 — Explain result type and provenance.** Show available descriptions and
  subjects, plus evidence-backed distinctions such as primary text versus
  commentary. Do not invent a “scholarly” badge from a source name alone.
- **P2 — Support research reuse.** I would value stable edition links and
  citation export, with missing metadata exposed rather than fabricated.
- **P2 — Reduce mobile filter overhead.** Keep the query and active-filter
  summary visible, with optional expansion for all source chips.
- **P2 — Clarify recording/text relationships.** Show which historical edition
  each recording follows, when known, and avoid suggesting synchronization
  unless it actually exists.

## Q8 — Overall judgement

I would return for classic-literature lookup: I found a relevant text, could
distinguish 1818 from 1831, loaded reading content, and observed audiobook
progress. That is meaningful value, not just a collection of outbound links.

I would not yet make it my primary scholarly discovery tool. My bounded review
did not establish subject-search quality, citation completeness, ISBN precision
or successful external borrowing. The biggest improvement for me is not a
larger-looking result count: it is explaining which work and edition each
result represents, why it matched, and what access actually entails.
