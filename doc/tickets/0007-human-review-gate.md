---
title: Separate human review from apply — add /ticket-review and a review gate state
type: feature
priority: medium
created: 2026-07-04
updated: 2026-07-04
status: open
---

## Description

Today human review is baked **inside** `/ticket-apply`: that skill presents the
diff, asks land/skip/reject, *and* performs the `git merge --no-ff` in one step
(`ticket-apply/SKILL.md` Steps 3–5). But conceptually review is the thing you do
*before* deciding to apply — it answers "is this fix good enough to land?", and
apply is the mechanical consequence of a yes. Folding both into one command makes
the flow feel unnatural and gives review nowhere to live as a first-class state.

This ticket separates the two: after `/ticket-fix` finishes, a fix should sit in
an **awaiting-human-review** state; a new **`/ticket-review`** skill conducts the
review and, on approval, moves it to **ready-to-apply**; `/ticket-apply` then
becomes (mostly) a merge step over ready-to-apply fixes.

### Current behavior (grounded)

- `ticket-state.sh` valid statuses: `open in-progress blocked resolved`. No
  review/apply-gate states exist.
- Worktree path of `/ticket-fix`: on evaluator PASS it sets the branch ticket to
  `resolved`, appends `Evaluator: PASS — …` to `## Resolution`, and **keeps the
  worktree, branch, and claim lock**, "awaiting `/ticket-apply`" (fix Step 5.4).
- `resolved` on a worktree fix is **branch-local** — it lives on
  `ticket/NNNN-<slug>` and is invisible in the main working tree until merged.
  Any new state added on the worktree path inherits this constraint.
- In-place (trivial) path: no branch/worktree; the fix leaves the working tree
  dirty and the ticket at `resolved`, to be committed via `/commit-session`.
- `/ticket-apply` is `disable-model-invocation: true` (human-only) and is the one
  place the plugin merges to your branch.

### Desired design

1. **New state after fix.** When a worktree fix passes the evaluator, it lands in
   a state meaning "fix done, waiting for a human to review before apply" (working
   name **`awaiting-review`**), instead of going straight to a plain
   "ready for `/ticket-apply`" limbo.
2. **New `/ticket-review` skill.** Conducts the human review over
   awaiting-review fixes, presents review material (see below), and on the user's
   OK transitions the ticket to **`ready-to-apply`**. On a "no", it bounces the
   fix back (same effect as today's `reject` in apply: discard branch/worktree,
   ticket returns to `open` with a note), or parks it.
3. **Trivial fixes may skip human review.** A clearly trivial fix can move
   straight to `ready-to-apply` without `/ticket-review`. The judgment of "trivial
   enough to skip" should be explicit and come from the fix step (see §"ticket-fix
   changes"), not be an ad-hoc call at apply time.
4. **`/ticket-apply` becomes the apply step.** It merges fixes that are
   `ready-to-apply`. If the user invokes `/ticket-apply` directly on a fix that is
   still `awaiting-review`, it should **confirm with the user** ("this hasn't been
   reviewed — apply anyway?") and, on yes, apply it inline — i.e. an escape hatch
   that folds review+apply back together on demand, without forcing the two-step
   dance every time.

### State machine changes

- Add statuses to `ticket-state.sh` `VALID_STATUS` and to the lifecycle docs
  (`doc/tickets/CLAUDE.md`, `plugins/ticket/CLAUDE.md`). Working names:
  `awaiting-review`, `ready-to-apply`.
- Define the transitions and which skill owns each:
  - `in-progress → resolved` (unchanged, on the branch) then
    `resolved → awaiting-review` — or collapse into a single
    `in-progress → awaiting-review`? (open question below.)
  - `awaiting-review → ready-to-apply` (via `/ticket-review` approve, or the
    trivial-skip path in `/ticket-fix`).
  - `awaiting-review → open` (review rejects; discard the attempt).
  - `ready-to-apply → resolved` on successful merge in `/ticket-apply`.
- Decide the **location invariant** for the new states. `resolved` currently maps
  to `resolved/`; `awaiting-review` / `ready-to-apply` fixes are still
  branch-local and not "done", so they likely stay in `<ticket-dir>/` (not
  `resolved/`) — confirm and encode in the `lint` invariant check.
- Keep the change backward compatible with existing tickets/locks; update `lint`
  so the new states don't trip the status⇔location check.

### `/ticket-review` skill (new)

A human-facing review skill (likely `disable-model-invocation: true`, like
apply). It enumerates `awaiting-review` fixes (branch + worktree, mirroring how
apply discovers pending fixes), and for each presents review material, then asks
the user to **approve** (→ `ready-to-apply`), **reject** (→ `open`, discard), or
**defer**.

**Review material — required (from the request):**

1. **Summary of the final change** — what changed and why, at a glance.
2. **Functional additions/changes** — if the fix adds or changes user-visible
   behavior: an explanation, at least one representative **example** of how to use
   it, and an explicit **impact/blast-radius** statement (what else is affected).
3. **Full diff** of the change.

**Review material — proposed additions (for the user to accept/trim):**

4. **Ticket ↔ change traceability** — restate the ticket's ask and acceptance
   criteria and map each to where the diff satisfies it (did the fix actually do
   what was asked, no more/no less?).
5. **Verification evidence** — which verification commands were run and their
   result, plus which reviewer graded it (Codex CLI vs Sonnet evaluator) and its
   verdict/notes. Surfaces "PASS" provenance rather than asking the human to
   re-run.
6. **Tests added/changed** — called out separately from the source diff, so the
   reviewer can judge coverage quickly.
7. **Files-changed overview** — `git diff --stat` and a one-line rationale per
   file, as a map before the full diff.
8. **Risk / things-to-double-check** — anything the fix or reviewer flagged as
   uncertain, plus out-of-scope items deliberately not done.
9. **Docs/spec impact** — whether a declared spec or docs were updated (or should
   be), since fixes can change user-visible behavior.

**Presentation / Artifact.** For small changes, present inline in the terminal.
When the change is large (needs a threshold — e.g. diff exceeds N lines / M
files, open question below), render the review material as a **Claude Artifact**
(single self-contained HTML page) so the user can browse the summary, examples,
stat, and full diff comfortably in the browser/app instead of scrolling a
terminal. The Artifact should follow the `artifact-design` guidance and embed the
full diff in a horizontally-scrollable block.

### `/ticket-fix` changes

- On evaluator PASS, transition the worktree fix to `awaiting-review` (not the
  current terminal-ish `resolved`+keep), keep the worktree/branch/lock as today,
  and report "N fixes awaiting review — run `/ticket-review`".
- **Revise the review request to the reviewer subagent** (Codex CLI / the
  `ticket:ticket-evaluator`) so it *also* reports whether human review can be
  skipped — i.e. add a **skip-eligibility / triviality-risk signal** alongside the
  PASS/REJECT verdict (e.g. "human-review: recommended | optional (trivial)").
  The fix step then uses that signal to decide `awaiting-review` vs.
  `ready-to-apply` (trivial-skip). Define what makes a fix skip-eligible
  (small, self-contained, no user-visible behavior change, no security-sensitive
  surface, tests present) and keep the default conservative (recommend review
  unless clearly trivial).
- Reconcile with the **in-place (trivial) path**, which has no branch/worktree and
  today ends at `resolved` + dirty tree. Decide whether in-place fixes participate
  in the review-gate states at all, or remain the "already trivial, no gate"
  channel (see open questions).

### `/ticket-apply` changes

- Operate over `ready-to-apply` fixes as the normal case (discover → confirm →
  merge → cleanup), stripping the review-decision UI that now lives in
  `/ticket-review`.
- Keep the direct-invoke escape hatch: if invoked on an `awaiting-review` fix,
  confirm with the user and, on yes, apply inline (review+apply folded back
  together on demand). Preserve all existing safety (conflict stops for the human,
  never auto-merge, stale-copy cleanup, lock release).

### Open questions (need a user decision)

- **State names/count.** `awaiting-review` + `ready-to-apply` as above, or fewer
  (e.g. reuse `resolved` for "fix done" and track review-approval as a separate
  flag/line rather than a status)? Fewer statuses = smaller state-machine churn.
- **Branch-local representation.** Since the new states are branch-local on
  worktree fixes, is a `status:` value the right home, or should the
  review/approval verdict be a `## Resolution` line (like `Evaluator: PASS`) with
  the `status:` staying `resolved`? This affects how `/ticket-review` and
  `/ticket-apply` discover work (branch scan vs. main-tree status).
- **Trivial-skip authority.** Who decides skip-eligibility — the reviewer subagent
  (Codex/Sonnet) as a signal, `/ticket-fix` from the triage `Complexity`, or a
  combination? And how conservative should the default be?
- **In-place fixes & the gate.** Do trivial in-place fixes need review at all
  (they're already "trivial") — or is the whole review gate a worktree-path
  concept?
- **Artifact threshold.** What size triggers the Artifact vs. inline terminal
  presentation (diff line/file count, or always offer both)?
- **Docs to update.** `plugins/ticket/plugin.json` (version bump + the
  `init → create → check → triage → fix → apply` description string), both
  `CLAUDE.md` lifecycle sections, the skills table, and the "typical flow" block
  all need to learn about `/ticket-review` and the new states.

### Acceptance

- New `/ticket-review` skill exists, is portable (no host-specific paths), and
  presents at least the three required review items, escalating to a Claude
  Artifact for large changes.
- `ticket-state.sh` supports the new state(s) and their transitions; `lint`'s
  status⇔location invariant is updated and passes on existing tickets.
- `/ticket-fix` routes evaluator-PASS worktree fixes to `awaiting-review`
  (or `ready-to-apply` when the reviewer marks them skip-eligible) and asks the
  reviewer for a skip-eligibility signal.
- `/ticket-apply` applies `ready-to-apply` fixes and, when invoked directly on an
  `awaiting-review` fix, confirms then applies inline.
- All lifecycle/skills docs and the plugin `version`/description are reconciled.
- Repo `## Verification` passes (`bash -n` over `*.sh`, JSON validity over
  `*plugin.json` / `*marketplace.json`, ticket lint).

## Triage

- Complexity: medium
- Mechanical fix: yes
- Requires user decision: no
- Affected files: 9 (1 new: `plugins/ticket/skills/ticket-review/SKILL.md`; 8
  existing: `plugins/ticket/scripts/ticket-state.sh`,
  `plugins/ticket/.claude-plugin/plugin.json`, `plugins/ticket/CLAUDE.md`,
  `plugins/ticket/agents/ticket-evaluator.md`,
  `plugins/ticket/skills/ticket-fix/SKILL.md`,
  `plugins/ticket/skills/ticket-apply/SKILL.md`, `doc/tickets/CLAUDE.md`,
  `plugins/ticket/skills/ticket-init/SKILL.md` — Appendix template for new projects)
- Fix strategy: worktree
- Notes: Grilling settled every design choice (D1–D7 in Implementation Notes), so
  no user decision remains — mechanical. The state-machine change is surgical: a
  one-line `VALID_STATUS` addition, and the `lint` status⇔location invariant is
  already written so any non-`resolved` status stays out of `resolved/` (no
  invariant code change; verify with a lint run). The weight is the new
  `/ticket-review` skill (four review-material categories + Artifact escalation for
  large diffs) and the **evaluator skip-eligibility signal** — a contract change
  coordinated across `ticket-evaluator.md`, `ticket-fix`, and `ticket-apply` (see
  the parsing-contract caveat in Implementation Notes). Worktree over in-place: a
  new skill plus multi-file behavioral edits, far beyond "a few lines". Verify with
  the repo `## Verification` block (`bash -n` over `*.sh`, JSON validity over
  `*plugin.json`/`*marketplace.json`, ticket lint). No plan/code conflicts found in
  triage.

## Implementation Notes

Decisions crystallised via `/grill-with-ticket`. These supersede the matching
"Open questions" above where they overlap.

### D1 — State representation: formal statuses (decided)

Represent the review gate as **real `status:` values**, not a `## Resolution`
text marker.

- Add `awaiting-review` and `ready-to-apply` to `ticket-state.sh`'s
  `VALID_STATUS` (→ `open in-progress blocked awaiting-review ready-to-apply
  resolved`).
- **Defer the `resolved`-move to apply-time.** The worktree fix no longer moves
  the ticket into `resolved/`; it stops at `awaiting-review` (file stays in
  `<ticket-dir>/`). Transitions:
  - fix: `in-progress → awaiting-review` (no `--move`)
  - review: `awaiting-review → ready-to-apply` (no `--move`)
  - apply: `ready-to-apply → resolved --move` (→ `resolved/`), **after** a
    successful merge, on the user's current branch.
- Rationale: every hop is guarded by `transition --from/--to`; `resolved` now
  honestly means "landed on your branch and moved to `resolved/`" (today the
  branch pre-moves to `resolved/` while the fix is still off-branch, which is a
  small lie). Because the branch keeps the file in `<ticket-dir>/` until apply,
  the current "stale open + resolved duplicate at merge" handling in
  `/ticket-apply` Step 5.1 is **no longer needed** and should be removed.
- Cost is small: the `ticket-state.sh` change is just the two extra words in
  `VALID_STATUS`. The `lint` status⇔location invariant already reads as
  "`resolved` ⇔ under `resolved/`", so the two new (non-`resolved`) statuses are
  automatically required to stay out of `resolved/` — **verify** this holds with
  a lint run over a fixture, but no invariant code change is expected.
- The states remain **branch-local** on worktree fixes (unchanged reality);
  `/ticket-review` and `/ticket-apply` still discover work by branch scan
  (`git worktree list` for `ticket/*`), reading the branch ticket's `status:`.
  The precondition "the ticket must be committed on the base before branching"
  (fix Step 5.1) still stands.

### D2 — Skip authority: the reviewer, on a risk axis (decided)

Terminology fix: "trivial → skip review" means **low-risk**, not small.
Genuinely small fixes are already the **in-place** path (no branch, no review
gate); worktree fixes are non-trivial *by size* by construction (fix Step 3, the
"new doc / new module" example). So skip-eligibility is a **risk** axis
orthogonal to the size-based in-place/worktree split.

- The **reviewer** (Codex CLI / `ticket:ticket-evaluator`) decides, not the
  generator — the author never grades its own work, and the reviewer has actually
  read the diff (the parent, judging from triage alone, has not).
- The reviewer emits, alongside `PASS`/`REJECT`, a
  **`human-review: recommended | optional`** signal. `optional` requires ALL of:
  low-risk, **no user-visible behavior change**, no security-sensitive surface
  (auth, input handling, path handling), tests present. Default is conservative —
  emit `recommended` whenever in doubt.
- `/ticket-fix` routes on the pair:
  - `PASS` + `optional` → `ready-to-apply` (review skipped)
  - `PASS` + `recommended` → `awaiting-review`
  - `REJECT` → bounce back (unchanged)
- **Safety valve:** a skipped fix is still branch-local and only lands when the
  human runs `/ticket-apply`. `/ticket-apply` must **list `ready-to-apply` fixes
  that skipped review distinctly** (e.g. "review skipped — low-risk") so the human
  can still inspect or reject them; skip only suppresses the detailed review
  material, it does not remove the final human merge action.
- Rejected earlier alternatives: triage `Complexity` alone (decides before seeing
  the diff); requiring triage-low AND reviewer-optional (double gate would make
  skip almost never fire, defeating the requirement); generator self-declaring
  (author grading own work).

### D3 — In-place fixes stay outside the gate (decided)

The review gate (`awaiting-review` / `ready-to-apply` / `/ticket-review`) is a
**worktree-path concept only**. In-place (trivially small) fixes are unchanged:
implement → verify → `resolved` + dirty tree → committed via `/commit-session`.

- Their natural human checkpoint is already `/commit-session`, where the user
  sees the diff before committing. Clean role split: **in-place → gated by
  `/commit-session`; worktree → gated by `/ticket-review` + `/ticket-apply`.**
- In-place fixes therefore never take the new statuses; they go straight to
  `resolved` as today. No new evaluator/reviewer step is added to the in-place
  path.
- Keeps the change surgical and matches the existing philosophy (in-place is for
  the trivially small).

### D4 — `/ticket-review` reject bounces to needs-user-decision (decided)

`/ticket-review` offers **approve** (→ `ready-to-apply`), **reject**, and
**defer** (leave `awaiting-review`, do nothing). On **reject**:

- Discard the attempt exactly like today's `/ticket-apply` reject: `git worktree
  remove --force`, `git branch -D ticket/NNNN-<slug>`, release the lock.
- In the **main-tree** ticket (still `open`), set `## Triage` to
  `Mechanical fix: no` / `Requires user decision: yes` with a note quoting the
  human's reason — mirroring `/ticket-fix`'s evaluator-REJECT bounce.
- Rationale: the human is overriding a fix that **already passed the independent
  evaluator**, so the mechanical assumption was likely wrong; a plain re-`fix`
  would tend to reproduce it. Route it back through human re-planning
  (`/grill-with-ticket`) rather than another mechanical attempt.
- `/ticket-review` is **human-only** (`disable-model-invocation: true`), like
  `/ticket-apply` — it is a human-review step, not something Claude self-invokes.

### D5 — Review material: required 3 + all proposed extras (decided)

The review material `/ticket-review` presents comprises the three required items
plus all six proposed extras. This supersedes the "proposed additions" list in
the Description (all accepted). Final set:

Required (from the request):
1. Summary of the final change.
2. Functional additions/changes — explanation + at least one representative
   usage **example** + explicit impact/blast-radius.
3. Full diff.

Extras (all accepted):
4. **Traceability to acceptance** — restate the ticket's ask / acceptance
   criteria and map each to where the diff satisfies it (did it do what was
   asked, no more/less).
5. **Verification evidence + reviewer provenance** — which verification commands
   ran and their result; which reviewer (Codex CLI / Sonnet evaluator) graded it,
   its verdict, and the `human-review: recommended|optional` signal — so the human
   need not re-run to trust the PASS.
6. **Change map** — `git diff --stat` + a one-line rationale per file as a map
   before the full diff, with added/changed **tests called out separately** for a
   quick coverage read.
7. **Risk / out-of-scope / docs-spec impact** — anything the fix or reviewer
   flagged as uncertain, items deliberately not done, and whether a declared
   spec/docs were (or should be) updated.

(Items 6–7 above fold the originally-separate "files-changed overview", "tests
added/changed", "risk/things-to-double-check", and "docs/spec impact" proposals.)

### D6 — Artifact escalation: size threshold (decided)

`/ticket-review` renders the material as a **Claude Artifact** (single
self-contained HTML page, per the `artifact-design` guidance, full diff in a
horizontally-scrollable block) when the change is large, otherwise inline in the
terminal.

- Trigger: **full diff > ~200 changed lines OR > 5 files changed** → Artifact;
  otherwise inline. Numbers are a starting default, tunable during implementation.
- The user can always request the other presentation explicitly (inline for a big
  change, or an Artifact for a small one).

### D7 — `/ticket-apply` behavior + direct-invoke escape hatch (derived)

`/ticket-apply` becomes the **apply** step; the review-decision UI (land/skip/
reject prompting) moves to `/ticket-review`.

- **Normal case:** operate over `ready-to-apply` fixes — discover (branch scan)
  → confirm → `git merge --no-ff` → on clean merge `transition --from
  ready-to-apply --to resolved --move` on the current branch → cleanup
  (worktree remove, branch -d, release lock). Fixes that **skipped review**
  (D2) are listed distinctly ("review skipped — low-risk").
- **Escape hatch (from the request):** if invoked directly on an
  `awaiting-review` fix, warn that it has not been reviewed, offer to show the
  review material / diff, and on confirmation apply it inline —
  `transition --from awaiting-review --to resolved --move` (skipping
  `ready-to-apply`; any `VALID_STATUS`→`VALID_STATUS` pair is accepted by the
  `transition` command, so no special-casing is needed). This folds review+apply
  back together on demand instead of forcing the two-step dance every time.
- Preserve all existing safety: conflicts stop for the human (never auto-merge or
  force), reject still available as a discard path, locks released on land/reject.
  The stale open+resolved duplicate handling is removed (see D1).

### Docs / packaging to reconcile (checklist, not an open question)

- `plugins/ticket/.claude-plugin/plugin.json`: bump `version`; update the
  `init → create → check → triage → fix → apply` description string to include
  `review`.
- `plugins/ticket/CLAUDE.md`: skills table (+ `/ticket-review` row), the "typical
  flow" block (insert `/ticket-review` between `/ticket-fix` and `/ticket-apply`),
  the lifecycle section (new statuses), and the review-gate section.
- `doc/tickets/CLAUDE.md`: frontmatter `status` enum + lifecycle list get the two
  new states; note that `awaiting-review`/`ready-to-apply` stay in `<ticket-dir>/`
  (not `resolved/`).
- `ticket-fix`/`ticket-apply` SKILL.md bodies updated per D1–D2, D7; new
  `ticket-review` SKILL.md added.
- Keep everything **project-agnostic** (portability rule): no host-specific paths
  or stacks in the new skill body.

### D8 — Skip-signal parsing contract (from triage)

The D2 skip signal is the critical coordination point across three files, so the
contract for *how it is emitted and parsed* must be pinned during the fix (triage
flagged this as the one gap in D1–D7):

- **Sonnet evaluator (`ticket-evaluator.md`):** extend its output beyond the
  current `VERDICT: PASS | REJECT` to also carry the skip signal in a clearly
  delimited, machine-parseable form on its own line, e.g.
  `VERDICT: PASS` + `human-review: optional`. `/ticket-fix` parses both.
- **Codex CLI path:** `codex review --base <ref>` uses Codex's built-in review and
  does not accept a custom prompt, so it will not natively emit a
  `human-review:` line. Decide the fix's approach — most likely `/ticket-fix`
  derives the skip signal itself from the Codex review result + the ticket's
  triage `Complexity` (Codex still owns PASS/REJECT), or a conservative default of
  `recommended` is used whenever the reviewer cannot supply the signal. Document
  whichever is chosen so the two reviewer paths route consistently.
- Default remains conservative: absent a clear `optional`, treat as
  `recommended` → `awaiting-review`.
