---
name: ticket-review
description: "Human review gate for worktree fixes awaiting review. Presents the full review material (summary, functional impact, diff, traceability, verification/reviewer provenance, change map, risk) for each awaiting-review fix — inline for small changes, as a Claude Artifact for large ones — then, on your OK, moves it to ready-to-apply. Human-only. Use after /ticket-fix reports fixes awaiting review, before /ticket-apply."
argument-hint: "[ticket-number]"
allowed-tools: Bash(*) Read Glob Grep Artifact
disable-model-invocation: true
---

# Ticket Review

Conduct the **human review** of the non-trivial fixes that `/ticket-fix` built in
isolated worktrees and left in `awaiting-review`. For each, present the review
material so you can judge "is this fix good enough to land?", then record your
decision. This is the review step that sits **between** `/ticket-fix` and
`/ticket-apply`: review answers whether to land; apply is the mechanical
consequence of a yes.

**Human-only** (`disable-model-invocation: true`) — like `/ticket-apply`, Claude
never self-invokes it; a human runs it deliberately. This skill **does not merge**
to your branch; approving only moves a fix to `ready-to-apply`, and `/ticket-apply`
does the merge.

## Instructions

### Step 1: Resolve the ticket directory and lint

Resolve `<ticket-dir>` from the host `CLAUDE.md` (default `doc/tickets/`), then run the lint gate:

```
${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> lint --all
```

If it exits non-zero, show the output and stop until it's resolved.

### Step 2: Discover fixes awaiting review

An awaiting-review fix is a `ticket/NNNN-<slug>` branch with a live worktree under
the shared git dir whose branch ticket is `status: awaiting-review`. Enumerate:

```
git worktree list --porcelain          # worktree path + branch for each
${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> status   # lock owner / branch / stale flags
```

Keep only worktrees whose branch matches `ticket/*`. For each, read that branch's
ticket file (`<ticket-dir>/NNNN-*.md` on the branch — it stays there, not in
`resolved/`, until apply) and keep those with `status: awaiting-review`. A branch
without an `Evaluator: PASS` line in `## Resolution` should be treated with
suspicion — surface it, don't hide it.

If `$ARGUMENTS` contains a ticket number, narrow to just that one. If there are no
awaiting-review fixes, report it (point the user at `/ticket-apply` for any
`ready-to-apply` fixes that skipped review) and stop.

### Step 3: Assemble the review material for each fix

For each awaiting-review fix, gather everything below from the branch and its
ticket. All commands run against the branch versus the base it was cut from
(`HEAD...ticket/NNNN-<slug>`; read the base from `git worktree list` / the branch's
merge-base if needed). The review material comprises **three required items plus
four accepted extra categories**:

**Required**

1. **Summary of the final change** — what changed and why, at a glance (draw from
   the ticket's `## Resolution` and the commit messages on the branch).
2. **Functional additions/changes** — if the fix adds or changes user-visible
   behavior: an explanation, **at least one representative usage example**, and an
   explicit **impact / blast-radius** statement (what else is affected). If the
   change is not user-visible, say so plainly.
3. **Full diff** of the change (`git diff HEAD...ticket/NNNN-<slug>`).

**Extras (all accepted)**

4. **Traceability to acceptance** — restate the ticket's ask / acceptance criteria
   and map each to where the diff satisfies it (did the fix do what was asked, no
   more, no less?).
5. **Verification evidence + reviewer provenance** — which verification commands
   ran and their result; which reviewer graded it (Codex CLI or the Sonnet
   evaluator), its verdict, and the `human-review: recommended | optional` signal —
   so you need not re-run to trust the PASS. (Read these from the branch ticket's
   `## Resolution` / `Evaluator:` line.)
6. **Change map** — `git diff --stat HEAD...ticket/NNNN-<slug>` plus a one-line
   rationale per file, as a map before the full diff, with any added/changed
   **tests called out separately** for a quick coverage read.
7. **Risk / out-of-scope / docs-spec impact** — anything the fix or reviewer
   flagged as uncertain, items deliberately not done, and whether a declared
   spec / docs were (or should be) updated.

### Step 4: Present it — inline or Artifact

Choose the presentation by the size of the change:

- **Full diff ≤ ~200 changed lines AND ≤ 5 files changed** → present **inline** in
  the terminal (change map first, then the material in the order above).
- **Full diff > ~200 changed lines OR > 5 files changed** → render a **Claude
  Artifact**.

These thresholds are a starting default; the user may always request the other
presentation explicitly (inline for a big change, an Artifact for a small one).
Measure size with `git diff --shortstat HEAD...ticket/NNNN-<slug>` (insertions +
deletions) and the file count from `--stat`.

**The Artifact** (follow the `artifact-design` guidance; this skill describes the
behavior — do not hand-build the HTML in this file):

- A **single self-contained HTML page** — all CSS/JS inline, no external hosts
  (the Artifact CSP blocks CDNs). One Artifact per fix, or one page covering all
  fixes with in-page navigation if there are several; keep the title stable and
  descriptive (e.g. "Ticket #NNNN review — <title>").
- Lead with the summary and the change map, then the functional impact and its
  example, traceability, and verification/provenance; put the **full diff last, in
  its own horizontally-scrollable block** (`overflow-x: auto`) so long lines never
  make the page body scroll sideways, with tabular, monospace, syntax-neutral
  formatting and clear per-file separators.
- A utilitarian, documentary treatment: real typographic hierarchy, a picked
  (not defaulted) neutral palette, semantic color only for added/removed diff
  lines and for the risk / review-signal callouts. No decorative flourishes — this
  is a document to scan and act on.
- Keep it project-agnostic: it renders whatever the diff and ticket contain; no
  host-specific stacks, paths, or test-runner assumptions baked into the page.

### Step 5: Decide per fix

For each fix, after presenting its material, let the user choose one of:

- **approve** → move it to `ready-to-apply` (leave the branch, worktree, and lock
  in place for `/ticket-apply`):

  ```
  ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> transition NNNN --from awaiting-review --to ready-to-apply
  ```

  Commit this status change on the branch (so the branch ticket reflects
  `ready-to-apply`).

- **reject** → the human is overriding a fix that **already passed the independent
  evaluator**, so the mechanical assumption was likely wrong and a plain re-`fix`
  would tend to reproduce it. Discard the attempt and route it back through human
  re-planning:

  ```
  git worktree remove --force "<worktree-path>"
  git branch -D ticket/NNNN-<slug>
  ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> release NNNN --force
  ```

  Then in the **main-tree** ticket file (still `status: open`), set its `## Triage`
  to `Mechanical fix: no` / `Requires user decision: yes` with a note quoting the
  human's reason for rejecting. Suggest `/grill-with-ticket NNNN` to re-plan rather
  than another mechanical `/ticket-fix`. (The `awaiting-review` status lived only
  on the discarded branch, so the main-tree ticket stays `open` — no status edit
  needed there.)

- **defer** → do nothing; the fix stays `awaiting-review` for a later
  `/ticket-review`.

Accept a blanket choice ("approve all") or per-fix decisions.

### Step 6: Summary

| Result | Ticket | Title | Detail |
|--------|--------|-------|--------|
| Approved | #NNNN | ... | now `ready-to-apply` — run `/ticket-apply` |
| Rejected | #NNNN | ... | discarded; ticket back to `open`, needs a user decision (`/grill-with-ticket`) |
| Deferred | #NNNN | ... | still `awaiting-review` |

End with the next step: "Run `/ticket-apply` to land the approved fixes."

## Notes

- **Human-only.** `disable-model-invocation: true` — this is a human-review step,
  not something Claude self-invokes.
- **Approving does not merge.** It only moves a fix to `ready-to-apply`; the merge
  is `/ticket-apply`'s job (the single human-invoked place the plugin commits to
  your branch). Review answers "should this land?"; apply is the consequence.
- **Reject is a re-plan, not a retry.** Because the fix already passed the
  independent evaluator, a human reject means the ticket was mis-triaged as
  mechanical — send it back to human planning, don't re-`fix` it blindly.
- **Skip is decided upstream, not here.** Fixes the reviewer marked
  `human-review: optional` never enter `awaiting-review` — `/ticket-fix` sends them
  straight to `ready-to-apply`. `/ticket-apply` lists those distinctly so they
  still get the final human merge action. `/ticket-review` only handles fixes that
  need a human look.
- **Status is script-owned.** Never edit the `status:` line or `git mv` a ticket by
  hand — always use `ticket-state.sh transition`.
- **Cross-clone limit**: a fix built in a different clone (e.g. a cloud run) has no
  local worktree/branch here and will not appear. Bring it across with ordinary git
  and review it as a normal PR.
