# Known Gaps

Deliberately scoped-out or unresolved edges surfaced during the extraction/
generation pipeline work, logged here rather than silently left implicit.
Each entry states what's missing and why it wasn't closed in the pass that
found it — not a TODO list to clear reflexively, a record for whoever
touches this code next to make an informed call.

## 1. Certification dual-priority ambiguity (Stage 1 — source-of-truth priority)

`ResumeSanitizer.deduplicateCertifications` has no doc-type priority
tiebreak, unlike experience/education merging. The spec called for two
different priority orders depending on certification type — "Awards/
badges: STP > NCOER" vs. "Training/coursework: JST > NCOER > STP" — but
both kinds of entries live in the same list at dedup time, before certType
classification runs (`_classifyCertifications` happens *after*
`deduplicateCertifications` in `parseFieldMappings`). Telling award entries
from training entries reliably enough to apply the right order per-entry
isn't available at that point in the pipeline without reordering
classification ahead of dedup — a bigger change than this stage's scope.
Left unimplemented rather than applying one order to both cases.

## 2. Duplicate-role-collision UI gap (Phase2ApiService.generateTailoredResume)

`generateTailoredResume`'s `onDuplicateRoleCollision` hook lets a caller
resolve same-title+company experience-entry collisions via a real
conflict-resolution UI (pre-selecting the most-bullets entry, requiring
confirmation) — but no caller supplies it today. `create_tailored_resume_screen.dart`
has no interactive surface between pre-processing and generation (a plain
progress spinner), so every collision currently falls through to the safe
default: keep every colliding entry distinct rather than guessing a winner.
That's correct and non-destructive, but it means a user can end up with two
near-identical experience entries in a generated tailored resume that they
have to notice and merge manually in the editor. The hook is ready for a
future screen to wire up; building that screen wasn't in scope for the bug
fix that added the hook.

## 3. `_mergeTwoRoles` experience-entry location conflicts — no normalization check

`_mergeTwoRoles` (resume_sanitizer.dart) auto-resolves a duty-station
disagreement between two merging experience entries purely by doc-type
priority (STP > NCOER > JST) whenever the two raw `location` strings differ
after a case-insensitive string comparison — it does not run them through
`isSameLocation`/`normalizeCityForComparison`/`normalizeStateToCode` (the
normalization pair built for Stage 2's `contact.location` conflict) first.
This means the exact same code path handles two different real situations
identically:
- the two strings are just differently-formatted versions of the same real
  place ("Ft Benning, GA" vs "Fort Benning, GA") — picking either is
  factually fine, no real information is lost;
- the two strings are genuinely different real places (e.g. "Fort Hood, TX"
  vs "Fort Bragg, NC") — the code still silently commits to one of them by
  doc-type priority alone, with no normalization-based sanity check and no
  user-facing conflict ever surfaced (an intentional Stage 1 design choice —
  see the asymmetry noted below), unlike Stage 2's contact-address conflict,
  which is always surfaced for confirmation.

**Existing test coverage found while investigating this** (2026-07-22): yes,
`resume_sanitizer_test.dart`'s "STP duty station wins over NCOER when they
genuinely disagree" test already uses "Fort Hood, TX" vs "Fort Bragg, NC" —
two real, geographically distinct installations, not formatting variants.
That test proves the mechanism *works as designed* (STP wins by priority).
It does **not** verify that this is the *correct* real-world outcome when
the two locations genuinely differ — i.e., whether silently picking one
real place over another (versus surfacing it, as Stage 2 does for contact
addresses) is actually the right call for this scenario. That broader
question has never been verified either way; the existing test documents
current behavior, not its correctness against ground truth. No new test was
added and no behavior was changed while investigating this — reported only,
per instruction.

## 4. ~~Stage 11's keep-together loop duplicates what Stage 7 (density tiers) will need~~ — resolved

Stage 7 landed and merged into Stage 11's loop as planned: both are now one
`_scheduleMeasurement` cycle in `_ResumeTemplateRendererState` — keep-together
spacers settle first at the current tier, then (Tailored Resumes only) the
settled height is checked against the density-tier fit target, bumping tier
and resetting spacers if it doesn't fit. No standalone second loop.

While implementing this, found and fixed a real bug in the original Stage 11
loop that had gone unnoticed: `_scheduleMeasurement()` was called both
explicitly after `setState` AND unconditionally at the end of every `build()`,
registering two overlapping `postFrameCallback`s per settle cycle. The second
could fire before the first's `setState` had actually triggered a relayout,
measuring stale (pre-rebuild) geometry against already-updated spacer state —
which caused the computed spacer to oscillate (grow, shrink, vanish, repeat)
rather than converge. It only ever *happened* to land in a passing state
because Stage 11's original retry bound (6 passes) was small enough to catch
it mid-oscillation in the right phase; Stage 7 raising that bound to
accommodate tier transitions (24 passes) is what exposed it as a real,
reproducible test failure. Fixed by having exactly one place
(`build()`'s unconditional call) own scheduling, and by computing each
block's "natural" (pre-spacer) position instead of its raw measured one, so
a block that's already correctly spaced is never mistaken for "doesn't need
this anymore" and un-fixed.

## 5. Cross-document duplicate-role clustering under-merges on real multi-document-type input (closing-sequence live-document pass, 2026-07-28/30)

Ran the full pipeline against 13 real source documents for one person (STP,
2 NCOERs, JST, civilian transcript, 6 DA-638s, 1 hazmat certificate, 1
DA-348). `mergeCrossDocumentDuplicateRoles`'s bar — exact normalized-title
match plus a fuzzy company-string match (`companiesAreLikelyTheSame`) —
essentially never fired across document types on this real dataset, even
for entries a human would immediately recognize as the same job:
- Two "Motor Transport Operator" entries at Fort Carson covering nearly
  identical 2016–2019 windows didn't merge because the company strings
  ("U.S. Army, Combat Support Battalion" vs "U.S. Army, Infantry Company,
  Fort Carson") don't token-align — `companiesAreLikelyTheSame`'s ordered
  prefix/initialism walk correctly reports them as different, because they
  *are* different-looking strings, even though they describe the same real
  unit assignment.
- Three differently-titled entries ("Network Systems Operator" from the
  STP, "Network Systems Operator-Maintainer" from the JST, "Tactical
  Communications Node Team Chief" from a DA-638) all describe the same
  Fort Polk, LA signal role spanning 2019–2021, but the exact-title-match
  gate blocks clustering outright since none of the three titles are the
  same string after normalization.

This is a documented, deliberate design choice (conservative merging to
avoid false-positive collisions of genuinely different roles), not a
regression — but real military source documents apparently phrase the same
job differently *by document type as a rule* (STP paraphrases, NCOER
narrates, DA-638 quotes unit orders verbatim), not as an occasional edge
case, so the exact-match bar rarely earns its keep on this kind of input.
Net effect measured on this dataset: the Master Resume ends up with 15
experience entries where a human reviewer would recognize roughly 8–10
distinct real jobs — technically exhaustive (nothing dropped), not
deduplicated the way a user would expect. Downstream, rendering this real
data as a Tailored Resume produced 6 pages against a 2-page max even at the
most compact density tier — the density-tier system correctly detected and
flagged the overage, but entry-count problems aren't something font/spacing
shrinking can fix. Not changed in this pass — reported per instruction
("catch drift, not confirm beliefs"), left for a deliberate decision on
whether/how to loosen the clustering bar (e.g. a lower-confidence
same-era-and-station fallback that surfaces as a user-reviewable suggestion
rather than an automatic merge) rather than fixed silently.

Separately, and independent of clustering: `resume_template_renderer.dart`
prints `experience.startDate`/`endDate` verbatim with no display
formatting (`Text(e.startDate, ...)`, and `ExperienceEntry.dateRange` is a
bare `'$startDate – $end'` concatenation) — this predates this pass and
applies to every extracted date, not just the compact-`YYYYMMDD` shape
fixed above (see `ResumeSanitizer.parseApproxDate`/`extractYear`'s v6
change). A real DA-638-derived entry still displays as `"20181025 –
20181109"` on the actual rendered resume rather than something like `"Oct
2018 – Nov 2018"` — the date-parsing fix makes these dates machine-readable
again (gap detection, cross-document overlap), it does not make them
human-readable on the page. Logged rather than fixed here since it's a
separate, broader display-formatting gap affecting all date shapes, not
scoped to what this pass was investigating.
