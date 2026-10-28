# Professor Elaine Brooks — round-one UX review

**Date:** 27 October 2026, approximately 20:18–20:22 EDT  
**Perspective:** I am responding as the fictional Professor Elaine Brooks, not claiming to represent all retired academics or people of my age.

## My scope, assumptions and method

I used Elaine's documented interest in political scholarship, academic-catalog experience, preference for laptop reading, calm presentation and trustworthy citations. **My additional assumptions** are that democracy is a topic I currently want to revisit, that Tocqueville is a useful historical primary source for that purpose, and that I am willing to sample its audiobook even though listening is not a stated preference. I have not assumed impaired vision, limited technical ability, or a particular political position.

I read `docs/personas.txt`, `docs/personaQuestionsRoundOne.txt` and `AGENTS.md`. I independently explored the running web app at `http://127.0.0.1:8080/` in my own browser page. I made two searches, opened a text reader and an audiobook player, and compared desktop **1366×900** with mobile-sized **390×844** viewports. These were browser viewport simulations, not physical devices.

My evidence below is browser observation, not a code audit or an inference from an API's HTTP status. The browser initially exposed only Flutter's accessibility-enablement placeholder and stalled rendering while reporting itself hidden. I enabled semantics and used browser focus emulation to continue. Some pointer interactions required retries or keyboard activation; I cannot confidently attribute those automation difficulties to ordinary-user behavior. I did not start or alter shared services.

I did not test native apps, actual mobile hardware, screen readers, enlarged system text, keyboard-only completion of the whole journey, external borrowing/download flows, offline access, or read-aloud voices. I cannot hear browser audio through these tools. This existing web build may lag repository source. I did not read other persona reports.

## 1. My initial impressions and preferred view

I appreciate a quiet opening screen with a prominent search box and recognizable choices: Anything, Title, Author, Subject and ISBN. I am not asked to register before trying a search. However, the example searches—Pride and Prejudice, Frankenstein, Moby Dick and The Odyssey—suggest a literary collection more strongly than a place for political scholarship. I would benefit from one nonfiction or open-access scholarship example.

I prefer **desktop**. The home content is contained rather than stretched across the screen, and I can inspect more results at once. In the reader I saw a two-column opening spread with identifying information and a contents list. At mobile width, search controls and source chips wrap into several rows before the first result; the reader's title is truncated and the text uses a narrow column. The mobile layout is usable for inspection, but it does not displace my preference for a laptop.

I found the dark search interface restrained. The transition to a bright white book page was noticeable; I would want to choose a reading background before a long session. This is my preference, not an age-based requirement.

## 2. My book search and access experience

**Exact query:** `democracy`  
**Search field:** Anything; all sources, all formats, any language.

I entered the query and activated Search. The interface returned **83 results**, including historical works, fiction, borrowable titles, DOAB entries and HathiTrust entries. I saw contemporary-looking titles such as *Reimagining Democracy* alongside older material. That breadth makes the service more relevant to me than the fiction-led home examples suggested.

I selected **Democracy in America — Volume 1, Alexis de Tocqueville**, using its **Read** action. Its result grouped Project Gutenberg and LibriVox and indicated Text and Audio. The action took me straight into the reader rather than first asking me to compare editions.

The initial reader view was blank apart from controls. After I selected **Next page**, readable opening material appeared: the book title, author, translator **Henry Reeve**, Gutenberg eBook **#815**, release/update information, an 1835 London title page and contents links. The progress indicator subsequently showed **2% read**. I inspected the opening at desktop and mobile widths.

**Access outcome:** I verified actual rendered front matter and navigation into it, not merely a working link. I did not verify chapter-by-chapter reading, completeness, annotation or a resumed session.

For my purposes, the query is a useful starting point, not yet a scholarly relevance judgment. A novel and political analysis both appear in the list. I want a concise explanation of why each item matches and whether it is a primary text, scholarly study or another kind of book. I would not treat a Gutenberg release date or digital-file update as the original publication date, nor assume a DOAB label alone establishes peer review.

## 3. My audiobook search and access experience

**Exact query:** `Democracy in America`  
**Search field:** Title; initially all formats.

I replaced the query, selected Title and searched. I received **6 results**, including merged text/audio volumes. I then selected the **Audio** format filter. The display changed to **2 results**, both LibriVox volumes, with explicit **Listen** actions.

I selected **Democracy in America Vol. I, Alexis de Tocqueville**. The player displayed narrator names, **17 hr 43 min** total length, chapter titles and chapter durations. I activated **Play** with keyboard focus after an automated pointer click was intercepted. The button became **Pause**, and the playback-position label advanced from **6 sec of 33 min** to **12 sec of 33 min** over a six-second interval for “Introduction & Special Introduction.” I then paused playback; Play reappeared.

**Access outcome:** I verified the player opened and its reported playback position advanced. I did **not** hear sound, judge the recording quality, or verify continuous listening through a chapter. Those remain untested.

I like being able to choose a political primary source rather than being steered toward fiction. The duration and chapter list help me decide whether to sample it. I would also want the audio's edition and translation clearly identified before treating it as interchangeable with the text.

## 4. My reaction to “Free Book Reader”

I find the name plain and understandable. I would keep it, but add an honest explanation: **“Find public-domain, open-access and borrowable books, plus free audiobooks.”** “Free” should not leave me guessing whether a result opens immediately, requires a library account or borrowing step, or takes me elsewhere.

I do not need a more academic-sounding brand. I need precise promises underneath it.

## 5. My three favorite things

1. **I can begin without an account.** A clear search box lets me test usefulness immediately.
2. **I can find both historical political texts and scholarship-oriented titles together.** My democracy results showed substantially more breadth than the home examples implied.
3. **I can switch purposefully to audio.** The Audio filter, Listen labels, total duration and chapter list make the alternative format concrete.

## 6. My three least favorite things

1. **I must do too much relevance classification myself.** The broad list mixed fiction, primary texts and analysis without a clear distinction in the cards I inspected.
2. **I do not get enough edition context before the direct Read action.** I found valuable translator and publication information only after opening the text; I want that context available before choosing it.
3. **I must interpret source and access vocabulary.** Source names and Read/View/Borrow are helpful starts, but I want immediate explanations of where I will go and what access conditions apply, without researching each service.

## 7. Features I would want and my priorities

**Priority 1 — Make relevance and access explicit at selection time.** I want a short description, original publication year, language, and a carefully sourced type label where known: “primary source,” “scholarly study,” or “fiction.” Unknown is better than an invented classification. I want labels such as “Read here now,” “Listen here,” “Read on another website,” or “Borrow on Open Library—account may be required.” I did not test those external requirements myself.

**Priority 2 — Give me a citation/edition panel.** I want author/editor, translator, original publication information, the particular edition's publisher/year when known, stable source link and identifier, plus a copyable citation. Digital release/update dates should be distinctly labeled. For merged records I want to know which edition each Read or Listen action opens, with provenance rather than a blended citation.

**Priority 3 — Support occasional research without adding clutter.** I would use publication-year and subject refinements, a saved reading list, and a choice to open details before reading. I would welcome a nonfiction example on the home screen and an optional reading theme. I would keep these secondary to trustworthy result descriptions and access labels.

## 8. My overall assessment

I would return to look up a political classic or discover a potentially useful open title. My actual trial reached readable front matter and an audio player with advancing position; that is encouraging practical evidence, not proof that every source or edition works.

I would not yet substitute this interface for a research catalog when selecting scholarship. My next decision needs to be “Is this the right work and edition, and can I use it now?” rather than “What does this source acronym imply?” If the app answers those questions plainly while retaining its calm layout, I can see it becoming a useful companion to my existing research habits.
