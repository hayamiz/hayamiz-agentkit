---
name: ticket-apply
description: "Merge the reviewed worktree fixes (ticket/NNNN-<slug> branches, status ready-to-apply) into your current branch. Never auto-merges — this is the human gate. Use after /ticket-review approves fixes, or after /ticket-fix reports fixes that skipped review."
argument-hint: "[ticket-number]"
allowed-tools: Bash(*) Read Glob Grep
disable-model-invocation: true
---

# Ticket Apply

Merge the non-trivial fixes that `/ticket-fix` built in isolated worktrees (each
on a `ticket/NNNN-<slug>` branch) and that are now `ready-to-apply` — either
approved by `/ticket-review` or marked review-skippable (low-risk) by the
reviewer. This is the deliberate human checkpoint: the loop can generate fixes at
speed, but nothing lands on your branch until you say so here. **This command
never merges automatically** and only ever runs when you invoke it.

The review-decision itself (present material → approve / reject / defer) lives in
`/ticket-review`. This skill is the apply step: discover → confirm → merge →
cleanup. Reject is still available here as a discard path, but the primary review
decision has moved to `/ticket-review`.

## Instructions

### Step 1: Resolve the ticket directory and lint

Resolve `<ticket-dir>` from the host `CLAUDE.md` (default `doc/tickets/`), then run the lint gate:

```
${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> lint --all
```

If it exits non-zero, show the output and stop until it's resolved.

### Step 2: Discover pending fixes

A pending fix is a `ticket/NNNN-<slug>` branch that has a live worktree under the
shared git dir. Enumerate them and map each branch to its worktree path:

```
git worktree list --porcelain          # worktree path + branch for each
${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> status   # lock owner / branch / stale flags
```

Keep only worktrees whose branch matches `ticket/*`. For each, read that
branch's ticket file (`<ticket-dir>/NNNN-*.md` on the branch — it stays there,
not in `resolved/`, until apply) and sort by its `status:`:

- `ready-to-apply` — the normal case: approved by `/ticket-review`, or marked
  review-skippable by the reviewer. These are what this skill applies. Read the
  ticket's `## Resolution` to tell the two apart: a `human-review: optional` line
  (never went through `/ticket-review`) means **review was skipped — low-risk**;
  list those distinctly so the human can still inspect or reject them.
- `awaiting-review` — not yet reviewed. Not applied in the normal flow; see the
  **escape hatch** in Step 4. Surface it, don't hide it.
- Anything else (no `Evaluator: PASS`, an unexpected status) — treat with
  suspicion and surface it.

If `$ARGUMENTS` contains a ticket number, narrow to just that one. If there are no pending fixes, report it and stop.

### Step 3: Present what will be applied

For each pending fix show — make it easy to look before merging:

| Ticket | Title | Branch | Status | Files | Review |
|--------|-------|--------|--------|-------|--------|
| #NNNN  | ...   | `ticket/NNNN-<slug>` | `ready-to-apply` | `git diff --stat HEAD...ticket/NNNN-<slug>` | approved / **review skipped — low-risk** |

Offer to print the full diff for any ticket on request:

```
git diff HEAD...ticket/NNNN-<slug>
```

### Step 4: Confirm each

For each `ready-to-apply` fix, let the user choose:

- **land** — merge it into the current branch.
- **skip** — leave the branch and worktree in place for a later `/ticket-apply`.
- **reject** — discard the fix (a rescue path if the human spots a problem here);
  the ticket returns to `open`.

Accept a blanket choice ("land all") or per-ticket decisions.

**Escape hatch — an `awaiting-review` fix applied directly.** If a fix is still
`awaiting-review` (invoked directly, or listed above), **warn that it has not been
reviewed** and offer to show its review material / full diff. Only on explicit
confirmation, apply it inline: it takes the same land path below except its
resolved-move transitions straight from `awaiting-review`
(`transition --from awaiting-review --to resolved --move`, skipping
`ready-to-apply`; the `transition` command accepts any valid status pair). This
folds review + apply back together on demand instead of forcing the two-step
dance. All the safety below still applies.

### Step 5: Execute

Process landed tickets sequentially in priority then number order, so later merges see earlier ones.

**Land NNNN** (base = your current branch):

1. If the working tree has uncommitted changes that could conflict, warn and let the user decide before proceeding. (The branch keeps the ticket file in `<ticket-dir>/` — not `resolved/` — until now, so there is no stale open+resolved duplicate to clean up; the resolved-move happens here in step 3.)
2. Merge, preserving a per-ticket merge commit:

   ```
   git merge --no-ff -m "merge ticket/NNNN-<slug>: <title>" ticket/NNNN-<slug>
   ```

   - **On conflict**: stop. Report the conflicted files and leave the merge in progress for the user to resolve (or run `git merge --abort` if they ask). Never force a merge. Do not continue to the next ticket until the user resolves or aborts.
3. On a clean merge, move the ticket to `resolved` **on your current branch** (this is where the resolved-move happens now — the branch kept the file in `<ticket-dir>/` until apply), commit it, then clean up:

   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> transition NNNN --from ready-to-apply --to resolved --move
   # (escape-hatch: --from awaiting-review instead)
   # commit the moved ticket file so your branch reflects the landed, resolved state
   git worktree remove "<worktree-path>"
   git branch -d ticket/NNNN-<slug>
   ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> release NNNN --force
   ```

**Reject NNNN**:

```
git worktree remove --force "<worktree-path>"
git branch -D ticket/NNNN-<slug>
${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> release NNNN --force
```

The `ready-to-apply` (or `awaiting-review`) status lived only on the discarded branch, so in your working tree the ticket stays `open` — no further edit needed.

**Skip**: do nothing; it remains pending.

### Step 6: Summary

| Result | Ticket | Title | Detail |
|--------|--------|-------|--------|
| Landed | #NNNN | ... | merge commit `abc1234` (note "review skipped — low-risk" where applicable) |
| Rejected | #NNNN | ... | back to `open` |
| Skipped | #NNNN | ... | branch `ticket/NNNN-<slug>` still pending |

If any landed fixes should reach a remote, that is the user's call — this skill does not push.

## Notes

- **Human-only.** `disable-model-invocation: true` — Claude never lands work on its own. This is the open door the playbook insists on keeping.
- **This is the one place the plugin commits to your branch**, and only on your explicit invocation: `git merge --no-ff` creates a merge commit per landed ticket, and the `ready-to-apply → resolved --move` (with its ticket-file commit) happens here too. Generator commits and the review-gate transitions (`awaiting-review` / `ready-to-apply`) stay on throwaway `ticket/*` branches until this step; `resolved` — and the move into `resolved/` — now honestly means "landed on your branch".
- **Conflicts stop for the human** — never auto-resolved or forced.
- **Cleanup removes both** the worktree and the branch; locks (under the shared git dir) are released here.
- **Cross-clone limit**: a fix built in a different clone (e.g. a cloud run) has no local worktree/branch here and will not appear. Bring it across with ordinary git (push/pull) and review it as a normal PR.
