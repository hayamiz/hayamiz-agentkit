---
title: Harden the ticket-fix workflow from the 0003 smoke-test findings
type: bug
priority: medium
status: resolved
created: 2026-07-03
updated: 2026-07-03
---

## Description

Running the real 0.4.2 workflow end-to-end on ticket 0003 (see
`doc/tickets/resolved/0003-*.md`) surfaced two concrete defects to fix.

### Finding 1 — an uncommitted ticket duplicates at merge (the important one)

`/ticket-fix`'s worktree path branches off the current HEAD. If the ticket being
fixed is **not yet committed** on that base (it was created/triaged but is still
an untracked or dirty file in the main tree), the worktree branch does not
contain it. The generator then has to bring a copy into the worktree to run the
resolved-move, which commits `doc/tickets/resolved/NNNN-*.md` on the branch —
while the original untracked `doc/tickets/NNNN-*.md` (still `open`) sits in the
main tree. At `/ticket-apply` time the merge lands the `resolved/` copy, leaving
**two files for the same ticket number** (open + resolved) → a `lint` duplicate.

Fix:
- **`/ticket-fix`**: before creating the worktree, check whether the target
  ticket is committed on the base. If it is untracked or has uncommitted changes,
  do not silently diverge — tell the user to commit it first (e.g.
  `/commit-session`), or note clearly that `/ticket-apply` will reconcile. (Keep
  the "does not commit to your branch" rule — do not auto-commit the ticket.)
- **`/ticket-apply`**: when landing a ticket, defensively remove any stale
  main-tree `open` copy `doc/tickets/NNNN-*.md` so it cannot duplicate the merged
  `resolved/NNNN-*.md`. (This is what had to be done by hand for 0003.)

### Finding 4 — reviewer sandbox/tooling failure was not an explicit fallback trigger

`codex review` in this environment exits `0` but cannot inspect the diff: its
bubblewrap sandbox cannot create the network namespace it needs
(`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`) — this persists
even with bubblewrap installed, because the container withholds the capability.
The output is "could not inspect … no findings", not an auth/rate-limit/empty
case. The Sonnet fallback did engage (good), but only because "empty output"
loosely matched.

Fix:
- **`/ticket-fix` Step 5.3**: make the fallback trigger list explicitly include
  "a sandbox/tooling failure, or any output indicating the reviewer could not
  inspect the diff (e.g. bubblewrap / namespace errors, 'could not inspect')".
- Add a short note that `codex review`'s sandbox needs user/network-namespace
  creation, which some containers block; when that happens the Sonnet evaluator
  is the reviewer of record.
- **Experiment result**: `codex review --base <ref> -c sandbox_mode="danger-full-access"`
  **works** in this container — Codex skips its own bwrap sandbox, runs `git diff`
  directly, and returned a real review that caught the planted bug. So the fix is
  to have `/ticket-fix` pass `-c sandbox_mode="danger-full-access"` to
  `codex review` (the review is read-mostly, and the surrounding agent/container
  is already the sandbox); the broadened fallback still covers any residual
  failure.

### Also noted (lower priority, out of scope unless trivial)

- Triage was conservative for a well-specified docs task (flagged
  `Requires user decision` over summary density).
- The in-place/worktree cue leaned on "single file" for a large new doc; the
  orchestrator overrode to worktree correctly.

### Acceptance

- `/ticket-fix` and `/ticket-apply` SKILL.md updated for findings 1 and 4.
- Repo `## Verification` passes (`bash -n`, JSON validity, ticket lint).

## Triage

- Complexity: low
- Mechanical fix: yes
- Requires user decision: no
- Affected files: 3–4 (`plugins/ticket/skills/ticket-fix/SKILL.md`, `plugins/ticket/skills/ticket-apply/SKILL.md`, `plugins/ticket/CLAUDE.md`, `plugins/ticket/.claude-plugin/plugin.json`)
- Fix strategy: in-place
- Notes: The fixes are precise, well-specified edits to this plugin's own skill
  instructions (findings 1 and 4 both resolved concretely — the Codex sandbox
  flag now works). `in-place` is chosen deliberately over `worktree`: routing an
  edit of `ticket-fix` itself through `ticket-fix`'s own worktree/review flow is
  needless recursion for a doc-style change, and the repo verification covers it.

## Resolution

Both findings fixed as in-place edits to the plugin's skill instructions.

- **Finding 1**: `/ticket-fix` (Step 5.1) now checks that the ticket is committed
  on the base before branching, and tells the user to commit it first if it is
  untracked/dirty; `/ticket-apply` (Land) now removes a stale main-tree `open`
  copy before merging so it cannot duplicate the merged `resolved/` version.
- **Finding 4**: `/ticket-fix` now invokes
  `codex review --base <base> -c sandbox_mode="danger-full-access"` — verified to
  work in this container (Codex skips its otherwise-blocked bubblewrap sandbox,
  runs `git diff`, and returned a real review that caught a planted bug). The
  fallback trigger list now also covers a sandbox/tooling failure or a
  "could not inspect the diff" result. `plugins/ticket/CLAUDE.md` Review Gate
  updated; plugin bumped 0.4.2 → 0.4.3.
- Findings 2/3 (triage docs-conservatism, in-place/worktree cue) left as noted —
  lower priority, deferred.

Verification: repo `## Verification` passes (`bash -n`, JSON validity, ticket lint).
