# Round-one persona review: combined analysis

**Review date:** 2026-10-27  
**Scope:** Synthesis of the ten independent reports listed in this folder.  
**Status:** Research analysis, not a usability study with recruited participants or a set of product decisions.

## Executive summary

Across the ten walkthroughs, the product's clearest value is a low-friction way
to discover a book and, in several observed journeys, reach actual text or an
audio player without first creating an account. The most consistent unmet need
is confidence at the point of choice: people need to understand what a result
is, why it matched, which edition or format an action opens, and whether access
is in-app, external, or conditional.

The reviews also reveal an important difference between a control being present
and a task being verified. Some reviewers saw real book prose and advancing
audio position; others reached only a player, API result, manifest, or cover.
Several observed audio players had missing chapter information or a changing
elapsed-time value presented as though it were a total. None of the reviews
verified audible quality. Accessibility requirements are explicit in the
product spec, but this exercise did not test with real assistive technology and
cannot establish WCAG conformance.

The reports support prioritizing clearer result and access information,
reliable audio state, and direct accessibility validation. They do **not**
support a single preferred device layout, an immediate rebrand, or adding every
suggested feature. Several requests—citations, offline downloads, saved lists,
recommendations, and reading presets—need product validation and trade-off
decisions before they become requirements.

## How to read this synthesis

The ten reports are simulated persona walkthroughs, not interviews. Each
reviewer documented assumptions and limitations; the source README also records
that the existing web build was not rebuilt, browser viewport sizes were not
native-device tests, and live services could be unavailable. Some reports used
the app UI, some used backend/API or source inspection as a fallback, and some
used injected browser instrumentation. Those evidence types are not
interchangeable.

Search counts below are specific to different queries, filters, source
availability, and cache states. They should not be compared as measures of
search quality. A failed automated click or incomplete player observation is
not treated as proof of a human-facing defect. Conversely, an API response,
HTTP success, visible Play/Pause state, or test definition alone is not proof
that a person completed the intended task.

## Cross-report themes

| Theme | Appears in | Combined finding |
|---|---|---|
| Explain relevance and result identity | Maya, Daniel, Elaine, Alex, Lucía, Jordan | Exploratory searches can feel like catalog work when results do not explain whether a match is an exact title, a related work, a topic hit, an adaptation, scholarship, or another kind of book. Several reviewers saw potentially confusing or loosely related results. This is a trust and orientation concern; the reports do not establish a single backend cause. |
| Make access and provenance legible before opening | Maya, Daniel, Elaine, Ruth, Sam, Morgan; also relevant to Alex, Lucía, Priya | Source names alone do not tell people whether they can read or listen here, will go to another site, may need to borrow, or are choosing a particular edition. Action labels such as Read, Listen, Borrow, and View are a useful foundation, but reviewers want consistent plain-language expectations and source/format attribution. |
| Preserve edition and language distinctions | Daniel, Elaine, Ruth, Lucía, Maya | Original publication date, translator, language, edition identity, and the source that supplies each action matter to choosing the right item. Keep known metadata distinct from digital release/update dates; present unknowns as unknown rather than infer them. Research-oriented citation requests are valuable but are not yet a shared requirement for all audiences. |
| Audio details and state are inconsistent | Alex, Maya, Jordan, Lucía, Priya; metadata requests also from Elaine, Daniel, Ruth, Sam | Some sessions exposed narrator, chapter list, and duration; others showed an empty chapter section or a changing “N sec of N sec” value. Lucía saw duration and chapters but did not observe a moving slider; Priya and Sam did not complete app playback. This suggests a data-dependent presentation/verification problem, not that every recording is broken. No report verified audible quality. |
| Mobile results put controls ahead of content | Maya, Daniel, Elaine, Alex, Lucía, Priya, Jordan | Several reviewers found the stacked search, source, format, and language controls pushed the first result down. Others still preferred mobile for their own context. Consider progressive disclosure, but do not remove useful filters or treat mobile as universally preferred. |
| Reading comfort and continuity are consequential | Ruth, Morgan, Sam; also Daniel and Elaine | Adjustable reader controls are appreciated, but their presence is not proof that the resulting page is comfortable or accessible. Reviewers want an easy comfort check, clear entry into the story, and a dependable way to resume. These require real task validation, especially for sustained reading. |
| Set honest expectations for offline and external journeys | Morgan, Sam, Elaine, Ruth, Maya | People need to know whether a work is available in-app, externally, or offline before relying on it. HathiTrust and some Open Library journeys differ from Gutenberg's in-app reader. Offline capability is not established by these reviews and should not be implied. |
| Low-friction discovery is a strength | Maya, Daniel, Elaine, Alex, Ruth, Priya, Sam, Jordan and others | Multiple reviewers valued being able to search or open content without an account prompt. Keep the first-use path light. Recommendations and curated entry points may help Maya and Jordan, but should not imply a current YA/graphic-novel collection the catalog does not provide. |

### Device preference is contextual, not a design verdict

Preferences split: Maya, Alex, Lucía, and Priya leaned mobile; Daniel, Elaine,
Jordan, and Morgan preferred desktop for their reviewed tasks. Ruth's desktop
comparison was inconclusive, and Sam's mobile preference reflected their
routine and assistive tools rather than a demonstrated accessibility
advantage. The stronger common signal is narrower: on small screens, filters
often delayed the first result. Keep both layouts useful and test specific
tasks on real devices.

### The name does not need an immediate replacement

Most reviewers found **Free Book Reader** understandable and favored retaining
it, often with a short explanation that includes audiobooks and clarifies that
some items open elsewhere or require borrowing. The name's limits are best
addressed first through an accurate subtitle and access labels, not a rename.

## Persona-by-persona synthesis

| Persona | Most important signal | Strongest evidence in the report | Main limitation |
|---|---|---|---|
| Maya | Relevance and an inviting, honest path for a teen curious about YA/graphic novels | `Heartstopper` produced three apparently unrelated results; after Gutenberg recovered, she opened *Frankenstein* in-app and reached the player for an audio result. | The initial Gutenberg outage was repaired during review. Audio position advanced, but sound was not heard; not a real teen test. |
| Daniel | Known-item precision, edition distinction, and research provenance | The title search returned *Frankenstein* editions distinguished by original publication year; reading content and player progress were observed. | No separate subject/ISBN or scholarly access task was completed; audio was not audibly verified. |
| Professor Elaine Brooks | Relevance and citation-quality context for political scholarship | `democracy` returned a broad mix; audio filtering narrowed a title search, and the report records rendered text plus advancing player position. | No real screen-reader, borrowing, or full scholarly-citation workflow test; browser automation needed workarounds. |
| Alex | Make the aggregation explain itself and improve audio certainty | Title search led to actual *The Time Machine* prose; the audio page lacked visible chapter/narrator/duration details and showed a moving apparent total. | The attempted second title replacement did not take, so the report correctly excludes it as a valid search test; sound was not verified. |
| Ruth | Make choosing an edition, adjusting comfort, and returning effortless | UI automation did not complete search, but a restricted API check and direct browser navigation verified publication content; a direct media probe advanced and paused. | Neither the app's reader nor its player was verified end-to-end; desktop comparison and real-device comfort were inconclusive. |
| Lucía | Put language choice earlier and label result language/match clearly | `Don Quijote` produced multilingual results; Spanish filtering narrowed the list, Spanish text rendered, and the player showed narrator/duration/chapters. | No older Android or throttled-network test; audible output and advancing audio position were not verified. |
| Sam | Verify the entire journey with actual assistive technology | Home semantics were inspected; API lookup found a plausible edition and manifest, and an injected audio probe advanced. | No successful app search/reader journey and no real VoiceOver, TalkBack, NVDA, magnification, or screen-reader evaluation. |
| Priya | Make listening quick to choose and safe to resume through interruptions | The Time Machine reader displayed story prose; an Audio-filtered Austen result was found. | The player was not reached; playback, audio metadata, offline use, and real-device interruption behavior remain unverified. |
| Jordan | Turn a casual topic into an approachable first result | Topic search surfaced travel-history volumes; a title search then reached actual story prose, and audio position advanced. | No audible listening, total duration, or sustained session verification; the topic mismatch is an observed result, not a diagnosed root cause. |
| Morgan | Make reading comfort tangible and offline expectations explicit | Sherlock Holmes prose rendered after changing text size and font; an audio result showed narrator, duration, chapters, and advancing position. | No actual dyslexic participant, sustained comfort, real phone, poor-network, offline, or audible-quality test. |

## Recommended next steps

These are research-informed priorities, not commitments or estimates.

1. **Validate and improve result comprehension.** Test known-item and exploratory
   searches separately. For each result, make title/author/language/source and
   available format evident; where metadata supports it, distinguish a direct
   title match from a related/topic result. Confirm the existing known-item
   behavior against the specification. Do not invent scholarly, primary-source,
   completeness, or relevance labels from a source name alone.
2. **Make the access action and its conditions explicit.** Before selection,
   distinguish reading/listening in the app from opening another site or
   borrowing. Identify which source/edition supplies each Read or Listen
   action. State account or regional conditions only when known, and avoid
   promising offline access unless the content has actually been saved.
3. **Make audio time and availability truthful.** When duration or chapter
   metadata is missing, show that it is unavailable rather than deriving a
   changing total from elapsed position. Handle empty chapter lists, loading,
   buffering, and errors clearly. Validate actual audible playback, seeking,
   chapter transitions, and interruption/resume on supported web and native
   targets; a changing control or position label is insufficient evidence.
4. **Reduce small-screen filter cost without hiding useful choices.** Prototype
   a compact active-filter summary and optional expanded source/language
   controls. Test whether people can still find Text/Audio and recover from a
   broad or poor result. This is a proposal to investigate, not an instruction
   to remove the current filters.
5. **Validate accessibility and reading comfort with people and assistive
   technology.** The product spec already sets WCAG 2.2 AA as an expectation and
   names automated checks, but those do not replace testing with screen-reader
   users. Cover search through result opening, reader navigation, focus
   restoration, enlarged text, settings, and external handoffs. Include
   sustained reading with participants who have relevant access needs.
6. **Treat resuming, offline reading, citations, and curated discovery as
   separate decisions.** They are useful persona-specific requests, but the
   reviews do not establish one common solution or demonstrate current gaps in
   every path. First audit existing behavior, then test the highest-value
   addition with the intended users.

## Specification impact

**No `spec.md` change is recommended from this round alone.** The current spec
already covers known-item search, accessibility expectations, reader settings,
source-specific access, and the undecided offline milestone. This exercise is
simulated, has important evidence gaps, and explicitly makes no product
decisions. If follow-up research confirms a change, update the corresponding
requirements and tests together—for example, define result-match explanations,
unknown audio-duration behavior, or a specific offline/resume promise before
implementing it.

## Overall conclusion

The product demonstrates meaningful discovery and reading value, but
confidence depends on the details around the content: why it matched, which
edition and language it is, what an action will do, and whether the audio or
reader is ready. The best next investment is not a broad feature expansion. It
is to validate and clarify those moments, with direct accessibility and
playback testing, while keeping the low-friction first-use experience intact.


## Review of this analysis (2026-10-27)

A source review of the app after reading the ten reports. The fixes are in
[the fix plan](../superpowers/plans/2026-10-27-persona-round-one-fixes.md).

### Disagreements

- **The audio failures follow one pattern.** Merged Gutenberg + LibriVox
  results open the Gutenberg audio eBook (`Work.bestBook`,
  `app/lib/models/models.dart`), which has no chapters or length, and the
  player (`audio_player.dart`) then shows elapsed time as the total. This is a
  diagnosed cause, not only a data-dependent presentation problem.
  Plan: Tasks 3 and 4.
- **Resuming is a real gap.** `ReaderPage` restores only a manual bookmark,
  which never moves, so spec.md's "where they left off" is not met.
  Plan: Task 5.
- **"No spec change" is too strong.** spec.md's resume promise is not met
  (above), and its dyslexia-friendly font promise is not met while the font is
  not bundled. Plan: Task 5 (spec updated); the font is out of scope, needs a
  decision.
- **"Heartstopper" and "time travel" are different problems.** Heartstopper is
  not in any catalog we search (an expectation problem); "time travel" is a
  ranking question. Plan: Tasks 8 and 12 for the first; the ranking is out of
  scope, needs a decision.

### Additions

- A LibriVox chapter title shows `&amp;` (Lucía). Plan: Task 2.
- An empty Chapters heading shows on recordings with no chapters. Plan: Task 4.
- Books open on front matter rather than the story (Maya, Elaine, Lucía,
  Priya, Jordan). Out of scope, needs a decision.
- The Title search choice may reset to Anything (Jordan). Plan: Task 6.
- Ask for language before the search, and allow several languages (Lucía).
  Out of scope, needs a decision.
- Justified, hyphenated text on mobile (Morgan). Plan: Task 11.
- Evidence counts: Ruth, Sam and Priya never finished an in-app journey, so
  their reports weigh less on in-app behavior. No task.
- Seven reviewers lost time to the "Enable accessibility" placeholder; turn on
  semantics when the page loads for round two. Plan: Task 13.
