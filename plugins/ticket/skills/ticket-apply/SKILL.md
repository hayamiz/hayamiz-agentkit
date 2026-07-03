---
name: ticket-apply
description: "Review the worktree fixes /ticket-fix built (ticket/NNNN-<slug> branches) and merge the approved ones into your current branch. Never auto-merges — this is the human gate. Use after /ticket-fix reports 'Ready to apply'."
argument-hint: "[ticket-number]"
allowed-tools: Bash(*) Read Glob Grep
disable-model-invocation: true
---

# Ticket Apply

Review the non-trivial fixes that `/ticket-fix` built in isolated worktrees
(each on a `ticket/NNNN-<slug>` branch, evaluator-passed) and merge the ones you
approve into your current branch. This is the deliberate human checkpoint: the
loop can generate fixes at speed, but nothing lands on your branch until you say
so here. **This command never merges automatically** and only ever runs when you
invoke it.

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
branch's ticket file to confirm it is `resolved` and carries an `Evaluator: PASS`
line in `## Resolution` (a branch without a PASS should be treated with
suspicion — surface it, don't hide it).

If `$ARGUMENTS` contains a ticket number, narrow to just that one. If there are no pending fixes, report it and stop.

### Step 3: Present the review

For each pending fix show — this is the "actually read a sample" moment, so make it easy to look:

| Ticket | Title | Branch | Files | Evaluator |
|--------|-------|--------|-------|-----------|
| #NNNN  | ...   | `ticket/NNNN-<slug>` | `git diff --stat HEAD...ticket/NNNN-<slug>` | PASS — ... |

Offer to print the full diff for any ticket on request:

```
git diff HEAD...ticket/NNNN-<slug>
```

### Step 4: Ask what to do with each

For each pending fix, let the user choose:

- **land** — merge it into the current branch.
- **skip** — leave the branch and worktree in place for a later `/ticket-apply`.
- **reject** — discard the fix; the ticket returns to `open`.

Accept a blanket choice ("land all") or per-ticket decisions.

### Step 5: Execute

Process landed tickets sequentially in priority then number order, so later merges see earlier ones.

**Land NNNN** (base = your current branch):

1. If the working tree has uncommitted changes that could conflict, warn and let the user decide before proceeding. Also remove any **stale main-tree `open` copy** of this ticket: if `doc/tickets/NNNN-*.md` exists (untracked / uncommitted) while the branch carries `doc/tickets/resolved/NNNN-*.md`, delete the stale `doc/tickets/NNNN-*.md` first — otherwise the merge leaves two files for the same ticket number (open + resolved), which `lint` flags as a duplicate. (This arises when the ticket was fixed before being committed on the base.)
2. Merge, preserving a per-ticket merge commit:

   ```
   git merge --no-ff -m "merge ticket/NNNN-<slug>: <title>" ticket/NNNN-<slug>
   ```

   - **On conflict**: stop. Report the conflicted files and leave the merge in progress for the user to resolve (or run `git merge --abort` if they ask). Never force a merge. Do not continue to the next ticket until the user resolves or aborts.
3. On a clean merge, clean up:

   ```
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

The resolved-move lived only on the discarded branch, so in your working tree the ticket stays `open` — no further edit needed.

**Skip**: do nothing; it remains pending.

### Step 6: Summary

| Result | Ticket | Title | Detail |
|--------|--------|-------|--------|
| Landed | #NNNN | ... | merge commit `abc1234` |
| Rejected | #NNNN | ... | back to `open` |
| Skipped | #NNNN | ... | branch `ticket/NNNN-<slug>` still pending |

If any landed fixes should reach a remote, that is the user's call — this skill does not push.

## Notes

- **Human-only.** `disable-model-invocation: true` — Claude never lands work on its own. This is the open door the playbook insists on keeping.
- **This is the one place the plugin commits to your branch**, and only on your explicit invocation: `git merge --no-ff` creates a merge commit per landed ticket. Everything else in the plugin (generator commits, resolved-moves) stays on throwaway `ticket/*` branches, off your branch.
- **Conflicts stop for the human** — never auto-resolved or forced.
- **Cleanup removes both** the worktree and the branch; locks (under the shared git dir) are released here.
- **Cross-clone limit**: a fix built in a different clone (e.g. a cloud run) has no local worktree/branch here and will not appear. Bring it across with ordinary git (push/pull) and review it as a normal PR.
