---
title: Consolidate ticket-commit decisions at the review/apply human gates
type: enhancement
priority: medium
status: awaiting-review
created: 2026-07-04
updated: 2026-07-12
---

## Description

The `ticket` plugin's workflow commits the ticket Markdown to git in exactly two
places today, and only one human-judgment point sits *outside* the intended
human gates (`/ticket-review`, `/ticket-apply`). That stray point is what this
ticket removes.

### The problem (grounded in the current v0.5.0 skills)

- **Commit topology today:** `create` / `grill` / `triage` never commit — the
  ticket stays uncommitted (dirty/untracked) in the main working tree. The
  worktree path of `/ticket-fix` commits the fix (+ tests) and the ticket onto a
  disposable `ticket/NNNN-<slug>` branch. `/ticket-apply` is the *single* place
  the plugin commits to **your** branch (`git merge --no-ff` + the
  `ready-to-apply → resolved --move` + ticket commit).
- **The stray human decision:** `/ticket-fix` Step 5.1 carries a **Precondition**
  — the ticket must be committed on the base before the worktree branch is cut,
  else "the worktree will not contain it, the resolved-move will run on a
  divergent copy, and a stale `open` copy is left in the main tree that
  duplicates the ticket at merge." So fix **halts mid-flow and tells the user to
  commit the ticket first** (`/commit-session`). This is a human commit decision
  wedged between triage and fix — exactly what we want to eliminate.
- **A related inconsistency to fix along the way:** the generator (fix Step 5.2)
  still runs `transition NNNN --from in-progress --to resolved --move` and
  commits the ticket **on the branch**, which contradicts Step 5.4's routing
  (`--from in-progress --to awaiting-review | ready-to-apply`, no `--move`, with
  the resolved-move deferred to apply). This is a half-migrated leftover from the
  0007 review-gate work and must be reconciled by any change here.

### Principle

> Mid-flow steps (`create` / `grill` / `triage` / `fix`) require **zero** human
> commit decisions. The plugin commits to **your** branch at exactly one place —
> `/ticket-apply`, a human gate. The ticket's participation in the worktree flow
> is made automatic, so no `/commit-session` detour is ever needed to unblock a
> fix.

### Chosen direction (see `## Implementation Notes` for the decisions)

The ticket file stays **main-resident**: the worktree branch carries **source +
tests only**, the ticket never rides the branch, and `/ticket-apply` commits the
ticket (its `resolved`-move) to your branch in one shot. This removes the
Precondition entirely — no ticket-file merge ever happens — at the cost of the
current "pristine main tree during a worktree fix" property.

### Likely affected files

- `plugins/ticket/skills/ticket-fix/SKILL.md` — remove the Precondition; the
  generator no longer touches the ticket file; the parent owns status
  transitions + `## Resolution` on the main-tree ticket.
- `plugins/ticket/skills/ticket-review/SKILL.md` and `ticket-apply/SKILL.md` —
  discover fixes from the main-tree ticket status + locks (not a branch ticket);
  apply merges a source-only branch then does the resolved-move.
- `plugins/ticket/CLAUDE.md` — rewrite the "branch-local status" / "pristine
  main tree" framing and the Commits-and-Merges section.
- `plugins/ticket/.claude-plugin/plugin.json` — version bump.
- `plugins/ticket/scripts/ticket-state.sh` — drop `awaiting-review` /
  `ready-to-apply` from `VALID_STATUS` (D3).
- `doc/tickets/CLAUDE.md` — frontmatter `status` enum + lifecycle (D3).

### Acceptance

- `/ticket-fix` (worktree) never halts to ask the user to commit the ticket; the
  Precondition is gone and the Step 5.2 inconsistency is resolved.
- No commit reaches your current branch before `/ticket-apply`.
- `/ticket-review` and `/ticket-apply` correctly discover and act on fixes with
  the ticket living only in the main tree.
- Lifecycle/flow docs and the plugin `version` are reconciled; skills stay
  project-agnostic.
- Repo `## Verification` passes (`bash -n` over `*.sh`, JSON validity over
  `*plugin.json` / `*marketplace.json`, ticket lint).

## Triage

- Complexity: medium
- Mechanical fix: yes
- Requires user decision: no
- Affected files: ~11 — skills `ticket-fix` / `ticket-review` / `ticket-apply`
  SKILL.md (bodies + `description:` one-liners), `ticket-check` (note +
  description), `ticket-init` (Appendix template); docs `plugins/ticket/CLAUDE.md`
  and `doc/tickets/CLAUDE.md`; config `plugins/ticket/.claude-plugin/plugin.json`
  (version bump) and `plugins/ticket/scripts/ticket-state.sh` (one-line
  `VALID_STATUS` edit).
- Fix strategy: worktree
- Notes: Design fully settled by grilling (D1–D10) with D4 finalised here, so
  mechanical with no user decision remaining. Independent triage against the
  v0.5.0 code confirmed the plan holds: (a) removing `awaiting-review` /
  `ready-to-apply` touches only the enum + docs + skill text —
  `ticket-state.sh` has no status-specific logic beyond `VALID_STATUS`
  validation (`_relocate` and the `lint` location invariant special-case only
  `resolved`), and `transition --from open --to resolved --move` works for any
  valid pair (D3/D6 mechanical); (b) nothing assumes `## Resolution` ⇒
  `resolved`, so D2's Resolution-on-an-open-ticket is safe; (c) the substantive
  work is D5 — `/ticket-review` and `/ticket-apply` Steps 2–3 today read the
  *branch* ticket and must be rewritten to read the *main-tree* ticket + marker
  (a control-flow change, unambiguous but not a trivial enum edit). Overrode the
  triage subagent's `in-place` suggestion: this is a coordinated behavioral
  rewrite spanning ~11 files across fix/review/apply plus a state-machine change
  — far beyond "a few lines"; the repo rubric sizes by substance, not file
  count, and says prefer worktree when in doubt. Verify with the repo
  `## Verification` block (`bash -n` over `*.sh`, JSON validity over
  `*plugin.json` / `*marketplace.json`, ticket lint). No plan/code conflicts
  found.

## Implementation Notes

Decisions crystallised via `/grill-with-ticket` and refined at triage. These
supersede the Description where they overlap.

### D1 — Ticket is main-resident; branch carries source only; one commit at apply (decided)

During a worktree fix the ticket Markdown **never goes on the `ticket/NNNN`
branch**. It stays in the main working tree; its `status` and `## Resolution`
are written there (dirty) as the fix progresses. `/ticket-review` and
`/ticket-apply` discover and read the **main-tree** ticket. `/ticket-apply`
performs the single commit to your branch: merge the source-only branch, then
`transition ready-to-apply → resolved --move` + commit the ticket.

- **Removes the root cause.** Because no ticket file is ever on the branch, there
  is no ticket-file merge, no divergent resolved-move, and no stale-copy
  reconciliation — the `/ticket-fix` Step 5.1 Precondition is deleted outright.
- **Cost (accepted):** the "pristine main tree during a worktree fix" property is
  given up — while a fix is in flight the main tree shows the ticket file
  modified (status line). Source changes remain isolated on the branch, so the
  user's code work on main is untouched; the churn is ticket metadata only.
- **Rejected alternatives:**
  - *Auto-commit the ticket onto the disposable branch* (keep today's
    architecture, just replace the human halt with an automatic branch commit):
    preserves the pristine main tree but keeps the finicky stale-copy
    reconciliation (untracked-overwrite on merge, restore-on-reject) the codebase
    itself calls "not the clean path".
  - *Progress-as-lock-runtime-state* (leave the main ticket wholly untouched;
    track awaiting-review/ready-to-apply in the claim lock): cleanest main tree,
    but the largest change to `ticket-state.sh` (locks gain review state) and to
    every reader (`/ticket-check`, review, apply). Heavier than warranted.

### D2 — In-flight review-gate state is a `## Resolution` marker, not a `status:` value (decided)

Because the main-tree ticket is dirty during a worktree fix (D1) and this repo
leans on `/commit-session`, a `status:` of `awaiting-review` / `ready-to-apply`
would leak onto your branch if committed before `/ticket-apply`. So during the
whole worktree fix the ticket's **`status:` stays `open`**, and the review-gate
progress is recorded as a **marker in `## Resolution`** (which `/ticket-review`
and `/ticket-apply` already read for the `Evaluator:` / `human-review:` lines).
`/ticket-apply` transitions `open → resolved --move` at land time.

- **Why:** an accidental early commit then captures a *truthful* `open` ticket —
  harmless, and no transient status pollutes your branch history. Upholds
  "commit to your branch only at `/ticket-apply`" completely.
- **Consequence (see D3):** the worktree flow no longer uses `awaiting-review` /
  `ready-to-apply` as `status:` values — this partially unwinds the 0007
  status-machine additions.

### D3 — Remove `awaiting-review` / `ready-to-apply` from VALID_STATUS (decided)

`status:` returns to `open | in-progress | blocked | resolved`.

- `ticket-state.sh`: drop the two from `VALID_STATUS`. The `lint` location
  invariant simplifies to just `resolved ⇔ resolved/` (the two removed states
  were "others", so no invariant-code change beyond the enum).
- `doc/tickets/CLAUDE.md`: drop them from the frontmatter `status` enum and the
  lifecycle list.
- `plugins/ticket/CLAUDE.md`: drop them from the lifecycle section.
- `/ticket-review`, `/ticket-apply`: rewrite every `status: awaiting-review` /
  `ready-to-apply` reference to the D4 `## Resolution` marker.
- **Also (surfaced at triage):** the skill `description:` frontmatter one-liners
  of `ticket-fix` / `ticket-review` / `ticket-apply` / `ticket-check` mention the
  two statuses; and `ticket-init/SKILL.md`'s Appendix template (the per-project
  `CLAUDE.md` new projects copy) plus a status-list note in `ticket-check` list
  them. All must match the reduced enum.
- **Migration:** no live tickets sit at these statuses today (0007 is not
  applied), so removal needs no data migration; a `lint --all` after the change
  confirms it.

### D4 — Review-gate marker format in `## Resolution` (decided)

One line in `## Resolution`, beside the existing `Evaluator:` / `human-review:`
lines:

```
Review-state: awaiting-review | ready-to-apply
```

Set by:
- `/ticket-fix` PASS + `human-review: recommended` → `Review-state: awaiting-review`
- `/ticket-fix` PASS + `human-review: optional` → `Review-state: ready-to-apply`
- `/ticket-review` approve → rewrite to `Review-state: ready-to-apply`

Parsing default: a `ticket/*` worktree whose main-tree ticket lacks a clear
marker (or lacks `Evaluator: PASS`) is treated as **awaiting-review** and
surfaced, never silently applied. (Triage confirmed the exact marker string is
ordinary implementer discretion, not a behavior fork — hence "decided".)

### D5 — Discovery for `/ticket-review` and `/ticket-apply` (derived)

The branch has no ticket file and the main-tree `status:` is `open`, so discovery
is **worktree/lock-driven, not status-driven**: enumerate `ticket/*` branches via
`git worktree list --porcelain` + `ticket-state.sh status` (locks), then read the
**main-tree** ticket's `## Resolution` D4 marker to sort `awaiting-review` vs
`ready-to-apply`.

**Triage note — this is the substantive part of the fix.** Today
`/ticket-review` and `/ticket-apply` Steps 2–3 read the *branch* ticket
(`<ticket-dir>/NNNN-*.md` on `ticket/NNNN`, which currently rides the branch).
D5 rewrites those steps to read the *main-tree* ticket + marker instead — a
control-flow change to discovery, not a small enum edit.

### D6 — Apply transition + guard (derived)

`/ticket-apply` lands `ready-to-apply`-marked fixes: `git merge --no-ff` the
source-only branch, then on your branch `transition --from open --to resolved
--move` + commit the moved ticket. The "is it ready" guard is the D4 marker, not
a `status:` value (`transition` accepts any valid status pair). This stays the
one place the plugin commits to your branch.

### D7 — Escape hatch preserved, marker-based (derived)

`/ticket-apply` can still land an unreviewed fix (marker `awaiting-review`) after
warning + explicit confirm — same land path, gated on the marker instead of the
`awaiting-review` status.

### D8 — In-place path unchanged (derived)

The in-place (trivial) path keeps `open → in-progress → resolved --move` on the
main tree, dirty, committed via `/commit-session`. It has no branch and no
Precondition, so it is untouched; `in-progress` therefore stays in VALID_STATUS.
The review gate remains worktree-only.

### D9 — Generator stops touching the ticket; parent owns `## Resolution` (decided — resolves the Step 5.2 leftover)

The worktree generator commits **only source + tests** to the branch — no status
transition, no `resolved --move`, no ticket commit. It *reports* what it changed;
the **parent** writes `## Resolution` + the D4 marker onto the **main-tree**
ticket (whose `status:` stays `open`). This deletes the contradictory
`transition ... --to resolved --move` in today's fix Step 5.2 and keeps the
ticket off the branch per D1.

### D10 — Reject cleans the main-tree ticket (derived)

On `/ticket-review` or `/ticket-apply` reject: discard the branch/worktree and
release the lock (unchanged), **and** strip the `## Resolution` markers the
attempt wrote onto the main-tree ticket, then set `## Triage` to `Mechanical fix:
no` / `Requires user decision: yes` per existing behavior. The `status:` is
already `open`, so no status reset is needed.

### D11 — `/ticket-check` shows in-flight worktree fixes as `open` (derived, accepted)

Because `status:` stays `open` during a worktree fix (D2), `/ticket-check` lists
an in-flight fix as an ordinary `open` ticket. Accepted as a minor UX cost — the
active claim lock (`ticket-state.sh status` / `/ticket-lint`) and the
`## Resolution` marker already distinguish it. Optionally `/ticket-check` could
annotate "(in flight — claimed)" by reading locks, but that is out of scope here.

## Resolution

Implemented D1–D11: during a worktree fix the ticket file stays main-resident
(never on the branch), the branch carries source + tests only, and the
review-gate progress is a `Review-state: awaiting-review | ready-to-apply` marker
in `## Resolution` — not a `status:` value. `status:` stays `open` until
`/ticket-apply` does `open → resolved --move`.

Files changed:

- `plugins/ticket/scripts/ticket-state.sh` — `VALID_STATUS` reduced to
  `open in-progress blocked resolved` (D3). No other logic referenced the two
  removed states (`_relocate` / lint invariant special-case only `resolved`).
- `doc/tickets/CLAUDE.md` — frontmatter `status` enum + lifecycle drop the two
  states; add the main-resident + `Review-state:` marker note (D3).
- `plugins/ticket/skills/ticket-init/SKILL.md` — Appendix per-project template
  enum + lifecycle updated to match (D3).
- `plugins/ticket/skills/ticket-fix/SKILL.md` — deleted the Step 5.1 Precondition
  (D1); generator now commits source + tests only, no status transition / no
  `## Resolution` / no ticket commit (D9, resolving the Step 5.2 leftover); parent
  writes `## Resolution` + the `Review-state:` marker on the main-tree ticket
  (D2/D4); PASS routing sets the marker instead of a status transition; header
  `description:`, intro bullets, Step 6 tables, and Notes rewritten to the marker
  model.
- `plugins/ticket/skills/ticket-review/SKILL.md` — discovery reads the main-tree
  ticket + `Review-state:` marker via `git worktree list` + locks, not a branch
  ticket / status (D5); approve rewrites the marker to `ready-to-apply` (D4, no
  status transition); reject strips the `## Resolution` markers (D10);
  `description:` updated.
- `plugins/ticket/skills/ticket-apply/SKILL.md` — discovery via the marker (D5);
  land = `git merge --no-ff` the source-only branch then `open → resolved --move`
  + commit on your branch (D6); escape hatch gated on the `awaiting-review` marker
  (D7); reject strips markers (D10); `description:` updated.
- `plugins/ticket/skills/ticket-check/SKILL.md` — note that an in-flight worktree
  fix shows as `open`, distinguishable by lock + marker; no new lock-reading logic
  (D11).
- `plugins/ticket/CLAUDE.md` — lifecycle, State-Management, review-gate, and
  Commits-and-Merges sections rewritten to the main-resident + marker model
  (D1/D2).
- `plugins/ticket/.claude-plugin/plugin.json` — `version` `0.5.1` → `0.6.0`
  (behavioral change).

Verification (repo `## Verification` block, all pass):

- `bash -n` over all `*.sh` — OK.
- JSON validity over `*plugin.json` / `*marketplace.json` — OK.
- `ticket-state.sh --dir doc/tickets lint --all` — 0 error(s), 0 warning(s).
- `shellcheck` not installed in this image — skipped (kept out of the auto-run
  list per repo policy).

Review (independent evaluator):

- Reviewer: Sonnet `ticket:ticket-evaluator`. (The Codex CLI was auto-mode-denied
  for its unsandboxed `sandbox_mode="danger-full-access"` run, so the skill's
  Sonnet fallback ran instead.)
- Verdict: **REJECT — overridden (bootstrap false-positive).** The REJECT rested
  on this fix's own worktree branch carrying the ticket file (a D1/D9 "the ticket
  never rides the branch" violation) and a resulting apply-time transition
  mismatch. That is a **self-modification bootstrap artifact**, not a defect in
  the delivered change: 0008 changes how `/ticket-fix` works, and the new
  main-resident behavior only takes effect *after* 0008 is merged and the plugin
  reloaded — so 0008 itself had to be built with the *current* ticket-on-branch
  process, and the not-yet-active D1/D9 rule cannot bind the very commit that
  introduces it. The evaluator confirmed the diff passes all verification and is
  internally coherent and complete; its concrete "apply breaks" point is resolved
  by the normal PASS routing step (below). Overridden by maintainer decision
  (2026-07-06). 0008 lands via the *current* flow (branch-local `awaiting-review`
  → `ready-to-apply`, still in cache `VALID_STATUS`); the new main-resident model
  governs *future* tickets once this merges and the plugin reloads.
- `human-review: recommended` — broad, user-visible workflow change → routed to
  `awaiting-review` so `/ticket-review` gives it the final human look before land.
