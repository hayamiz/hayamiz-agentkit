---
title: Refine triage heuristics — docs-task mechanicality and the in-place/worktree size cue
type: enhancement
priority: low
status: resolved
created: 2026-07-03
updated: 2026-07-03
---

## Description

Two lower-priority observations from the 0003 smoke test
(`doc/tickets/resolved/0003-*.md`) about how `/ticket-triage` classifies work.
Both are guidance refinements, not defects.

### Finding 2 — triage is over-conservative on well-specified docs tasks

Triaging 0003 (write a summary doc from a given outline + "match repo style"),
the Explore subagent marked it `Requires user decision: yes` over the summary's
density and voice — which, taken literally, makes `/ticket-fix` skip it. But
calibrating density/voice within a supplied outline is ordinary implementer
discretion, not a user decision. As written, almost any docs/content ticket
would be classed non-mechanical.

Refinement: add rubric guidance to `ticket-triage` that when a docs/content
ticket supplies the content outline (and defers style to "match the repo"),
minor wording/density/voice calibration is *not* a user decision on its own —
lean `Mechanical fix: yes` unless a genuine content/architecture choice is open.

### Finding 3 — the in-place/worktree cue over-weights "single file"

Triage suggested `Fix strategy: in-place` for 0003 because it was a single new
file — but it was a substantial multi-section document, which `/ticket-fix`
correctly re-routed to `worktree`. The heuristic reads "single file" as an
in-place signal, when the deciding factor should be size/substance.

Refinement: clarify in `ticket-triage` (and the final-call note in `/ticket-fix`)
that `in-place` is for genuinely small, self-contained changes — *a few lines* —
and that "a few lines" dominates over "one file". A large single-file addition
(e.g. a new doc or a new module) should be `worktree`.

### Deliverable

- Update the triage rubric in `plugins/ticket/skills/ticket-triage/SKILL.md`
  for both findings; adjust the strategy-decision wording in
  `plugins/ticket/skills/ticket-fix/SKILL.md` if finding 3 needs it there too.

### Acceptance

- The triage rubric encodes both refinements.
- Repo `## Verification` passes (`bash -n`, JSON validity, ticket lint).

## Triage

- Complexity: low
- Mechanical fix: yes
- Requires user decision: no
- Affected files: 2 (`plugins/ticket/skills/ticket-triage/SKILL.md` rubric; `plugins/ticket/skills/ticket-fix/SKILL.md` strategy notes)
- Fix strategy: in-place
- Notes: Documentation clarification — add the two guidance refinements (Finding 2:
  docs-task mechanicality; Finding 3: "a few lines" dominates "single file") to the
  triage rubric and echo the size heuristic in `/ticket-fix`'s strategy-decision prose.
  Unambiguous — the ticket already states the problem, the solution, and the target
  sections; no code, no new files, no design choices. (Small, self-contained edits, so
  `in-place` per the very heuristic Finding 3 clarifies.)

## Resolution

Docs-only change — both findings encoded as triage-heuristic guidance across two
skill files. No code paths touched, so no tests added.

- **Finding 2 & 3 — `plugins/ticket/skills/ticket-triage/SKILL.md`** (rubric
  under "#### Triage rubric (to include in every subagent prompt)"): inserted an
  **"Applying these to two common cases:"** note after the `Fix strategy` bullet
  covering (a) *docs / content tickets* — outline-supplied, style-deferred
  wording/density/voice calibration is implementer discretion, not a
  `Requires user decision`, so lean `Mechanical fix: yes`; and (b) *sizing
  `in-place` vs `worktree`* — judge by size, not file count, with "a few lines"
  dominating "a single file" and large single-file additions going to
  `worktree`.
- **Finding 3 — `plugins/ticket/skills/ticket-fix/SKILL.md`** (Step 3, item 2
  "Decide the path"): rewrote the strategy sentence so size dominates file count
  — a large single-file addition belongs in a `worktree` even though it touches
  one file, while a couple of trivial edits across two files can stay in-place.

Verification (repo `## Verification` from `doc/tickets/CLAUDE.md`) all passed:

- `bash -n` over all tracked `*.sh` — OK.
- JSON validity over all `*plugin.json` / `*marketplace.json` — OK.
- `ticket-state.sh --dir doc/tickets lint --all` — `0 error(s), 0 warning(s)`.

No spec declared → spec-update step skipped.
