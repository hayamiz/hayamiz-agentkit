---
title: Worktree-based ticket-fix with generator/evaluator split, /ticket-apply, and lock/lint state management
type: feature
priority: high
status: resolved
created: 2026-07-03
updated: 2026-07-03
---

## Description

Rework the `ticket` plugin's fix workflow along the "loop engineering" playbook
(Osmani / Rajasekaran / Stripe, June 2026), so that non-trivial fixes run in
isolated git worktrees, are checked by an independent skeptical evaluator, and
land on the main branch only through an explicit, human-invoked command. Add a
robust state-management layer (atomic claim locks + frontmatter lint) so that
several agents running in parallel cannot corrupt ticket state or double-process
the same ticket.

**Why.** The current `/ticket-fix` already isolates each fix in a subagent and
runs verification, but:

- All subagents edit the **same working tree**; the only guard against parallel
  collisions is "run sequentially when files overlap", which depends on fragile
  up-front file-overlap detection (the *tangled loop* failure mode).
- Verification is the parent inspecting `git diff` — effectively the generator
  grading its own homework, which the playbook shows tends toward self-approval
  (the *nodding loop*).
- The "review and land on the main branch" decision is delegated wholesale to
  `/commit-session`; there is no explicit human gate — no single place where the
  human is structurally kept "able to say no".
- With multiple worktrees / sessions / cloud+local runs, two agents can claim
  and process the **same ticket** because a `status: in-progress` change made on
  a worktree branch is invisible in the main tree until merged.

**Goals.**

1. Non-trivial fixes run in per-ticket worktrees on `ticket/NNNN-<slug>` branches
   (true, safe parallelism); trivial fixes ("a few lines in one file") keep the
   current in-place path.
2. A separate evaluator subagent judges each fix by *running* it (not just
   reading), defaulting to doubt; only PASS fixes become apply candidates.
3. A new human-only `/ticket-apply` command reviews finished branches and merges
   the selected ones into the current branch — never auto-merged.
4. A 3-layer state-management mechanism (claim lock / atomic transition / lint)
   makes ticket state race-safe and hard to corrupt.

**Non-goals / known limits.**

- File locks protect concurrency **within a single clone** (multiple worktrees +
  multiple local sessions). Cross-clone / cloud-vs-local coordination is out of
  scope and relies on git merge-conflict detection plus the `/ticket-apply`
  human gate. This limit must be documented, not hidden.

## Implementation Notes

Design decisions below are already settled with the user — this ticket does not
need a fresh `/ticket-triage` design pass; go straight to implementation.

### Confirmed decisions

| Topic | Decision |
| :--- | :--- |
| Land into main | Commit on `ticket/NNNN-<slug>`; `/ticket-apply` runs `git merge --no-ff` into the current branch after human review, then removes worktree + branch. "Does Not Commit" is relaxed to mean "never lands on the main branch automatically". |
| Verification | Dedicated **evaluator subagent** (separate context/instructions), `cd`s into the worktree, runs tests, assumes the code is broken until proven otherwise, and does **not** write source. PASS only ⇒ apply candidate. |
| New command name | `/ticket-apply` (`disable-model-invocation: true` — user presses the button). |
| trivial vs non-trivial | `/ticket-triage` annotates `Affected files` + `Fix strategy`; `/ticket-fix` makes the final call: `complexity: low` AND single file AND small diff ⇒ in-place, else worktree. |
| Worktree mechanism | Self-managed `git worktree` from the skill body (NOT the harness-native `isolation: worktree`, whose branch naming is fixed and whose keep/remove prompt conflicts with the batched human gate). |
| Lock mechanism | Portable `mkdir`-atomic lock (macOS lacks `flock(1)`); `flock` only as an optional fast path. |
| Lock store location | `$(git rev-parse --git-common-dir)/ticket-locks/NNNN/` — shared across all worktrees of the same clone, untracked (no commit impact). |
| Lock TTL | Default 2h; overridable via `Lock TTL:` in `doc/tickets/CLAUDE.md`. |
| Status changes | ALL `status` frontmatter changes go through `ticket-state.sh transition`, never a raw Edit. |
| Lint | Runs as a read-only gate at the start of triage/fix/apply AND is exposed as a standalone `/ticket-lint` (with `--fix` and a `status` view). |

### Harness facts that shaped the design (confirmed via claude-code-guide)

- The Agent tool has no per-call `isolation: worktree`; only agent *definitions*
  support it, with harness-fixed branch names (`worktree-<value>`) and a
  keep/remove prompt on finish — unsuitable for our batched, human-gated merge.
- A dispatched subagent inherits the parent's cwd; there is no way to point it at
  another directory on invocation. ⇒ the parent creates the worktree and passes
  its absolute path in the prompt; the subagent `cd`s there as its first step.
- `/goal`'s completion evaluator judges only what is surfaced in the conversation
  and does **not** run commands itself — so it cannot replace an acting
  evaluator subagent (it may still be used as a lightweight stop condition).

### Three-layer state management

- **L1 — claim lock** (the main race the user flagged): before processing a
  ticket, atomically `mkdir` a lock dir under the shared git-common-dir. Success
  ⇒ this invocation owns the ticket; failure ⇒ another agent has it, skip.
  Prevents two invocations/worktrees from grabbing the same ticket even though
  the branch-local `status: in-progress` is invisible in main. Separates
  *runtime ownership* (lock) from *durable state* (`status`).
- **L2 — atomic transition**: `status` writes use temp-file + rename, validate
  `from` matches current, and (for `resolved`) `git mv` into/out of `resolved/`
  in the same step, enforcing the `status ⇔ location` invariant.
- **L3 — lint**: validates frontmatter (required keys, enums, date format,
  `NNNN-<slug>.md` naming, unique numbers), the `status: resolved ⇔ resolved/`
  invariant, and lock consistency (orphan / stale / leaked locks). `--fix`
  performs only safe repairs (e.g. `updated` date, enum casing, relocate to
  match status); anything needing judgment is reported.

### Bundled script: `plugins/ticket/scripts/ticket-state.sh`

Single entry point for the state machine. Portable POSIX/bash, `mkdir`-atomic.

```
ticket-state.sh --dir <ticket-dir> <subcommand>
  claim      NNNN --owner <id> [--worktree <path>] [--branch <name>]
             # atomic lock; ticket must be open/in-progress & unlocked;
             # steal if stale (TTL exceeded or worktree gone) with a warning.
             # exit 0=claimed / 3=held-by-other / 4=not-claimable
  release    NNNN --owner <id> [--force]        # owner-only; apply may --force
  transition NNNN --from <s> --to <s> [--move]  # from-guarded status write (+updated),
             # --move does the resolved/ git mv atomically
  status     [NNNN]                             # show locks / in-flight work
  lint       [NNNN|--all] [--fix]               # see L3
```

Referenced from skills via `${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh`.
Locks live under `.git`, so nothing to commit and no interaction with the
"Does Not Commit" rule.

### `/ticket-fix` worktree-path flow

```
parent (main tree):
  ticket-state.sh lint --all              # L3 gate; stop on hard errors
  collect candidates (triaged, mechanical, fix-strategy)
  per candidate: ticket-state.sh claim NNNN --owner <session>
      exit 0 -> git worktree add .claude/worktrees/ticket-NNNN -b ticket/NNNN-<slug>
                -> dispatch generator + evaluator
      exit 3 -> skip ("claimed by another agent")
  generator (worktree): cd -> fix + tests + verification
      -> ticket-state.sh transition NNNN --from open --to in-progress
      -> commit to branch
  evaluator (worktree, separate context/model): cd -> run tests, skeptical review,
      does NOT write source
      PASS   -> ticket-state.sh transition NNNN --from in-progress --to resolved --move
                + write ## Resolution + evaluator verdict, commit (keep lock until apply)
      REJECT -> record requires-user-decision in ## Triage (main),
                ticket-state.sh release NNNN, discard worktree/branch
  parent: present per-ticket review card (branch / diff --stat / verification / verdict)
```

### `/ticket-apply` (new) flow

```
resolve ticket dir; discover pending via `git worktree list` + `ticket/*` branches
present review table (ticket / title / branch / diff --stat / verification / verdict);
  full diff on request
user picks land / skip / reject (narrow by $ARGUMENTS ticket number if given)
land   -> git merge --no-ff ticket/NNNN-<slug> into current branch (sequential,
          priority/number order; stop & report on conflict)
          -> git worktree remove + git branch -d
          -> ticket-state.sh release NNNN --force
reject -> git worktree remove --force + git branch -D
          -> ticket-state.sh release NNNN --force  (ticket stays open in main)
```

### Files to create / change

- `plugins/ticket/scripts/ticket-state.sh` — NEW (claim/release/transition/status/lint).
- `plugins/ticket/skills/ticket-lint/SKILL.md` — NEW (user-facing lint `--fix` + status).
- `plugins/ticket/skills/ticket-apply/SKILL.md` — NEW.
- `plugins/ticket/skills/ticket-fix/SKILL.md` — 2-path strategy; worktree
  orchestration; generator + evaluator subagents; lint gate + claim/release;
  route status changes through the script; "Ready to apply" summary section.
- `plugins/ticket/skills/ticket-triage/SKILL.md` — emit `affected_files` +
  `fix_strategy`; add `Affected files:` / `Fix strategy:` to `## Triage`;
  lint gate.
- `plugins/ticket/skills/ticket-init/SKILL.md` — extend the per-project
  `CLAUDE.md` template with the new `## Triage` fields, `Lock TTL:`, and a note
  about `.git/ticket-locks/`.
- `plugins/ticket/CLAUDE.md` — add `/ticket-apply` and `/ticket-lint` to the
  skills table + typical flow; document the lock mechanism, invariants, TTL, the
  single-clone-only limit, and that the script is the sole state-machine entry;
  add the merge carve-out to the "Does Not Commit" section.
- `plugins/ticket/.claude-plugin/plugin.json` — bump `version` 0.3.0 -> 0.4.0.

### Suggested phasing (verification checkpoints)

1. **State layer**: `ticket-state.sh` + `/ticket-lint` + init/schema updates.
   Verify: `bash -n`, a manual claim/transition/lint round-trip on a scratch
   ticket, stale-lock steal, `status ⇔ location` enforcement.
2. **Fix rework**: `/ticket-triage` annotations + `/ticket-fix` 2-path +
   generator/evaluator + lint gate + claim/release. Verify: a trivial ticket
   goes in-place; a non-trivial ticket produces a `ticket/NNNN-*` branch with an
   evaluator verdict; a REJECT bounces back and releases the lock.
3. **Apply**: `/ticket-apply` land/reject + worktree cleanup + lock release.
   Verify: land merges and cleans up; reject discards and leaves the ticket open;
   a simulated second concurrent claim is refused.
4. **Docs/version**: `plugins/ticket/CLAUDE.md`, plugin.json bump.

May be split into per-phase sub-tickets if preferred; kept as one ticket for now.

### Portability guardrails (per plugin's Portability Rule)

No hardcoded language/framework/test-runner/paths in skill bodies. `ticket-state.sh`
must run on Linux and macOS (no `flock` dependency). Ticket dir, spec, and
verification commands are resolved at runtime from the host repo's `CLAUDE.md`
and `<ticket-dir>/CLAUDE.md`.

## Resolution

Implemented across four phases and verified before commit.

- **State layer**: added `plugins/ticket/scripts/ticket-state.sh`
  (claim / release / transition / status / lint; atomic `mkdir` locks under the
  shared git dir; portable — no `flock`, bash 3.2 safe) and the `/ticket-lint`
  skill. Added a `Lock TTL` / concurrency block to the `ticket-init` schema
  template.
- **Fix rework**: `/ticket-triage` now emits `Affected files` + `Fix strategy`;
  `/ticket-fix` splits into in-place vs worktree paths, runs a generator plus an
  independent evaluator subagent, claims/releases each ticket, routes all
  `status` changes through the script, and commits worktree work proactively to
  a `ticket/NNNN-<slug>` branch.
- **Human gate**: added `/ticket-apply` (`disable-model-invocation`) to review
  and `git merge --no-ff` approved worktree fixes, then clean up
  worktree / branch / lock.
- **Docs**: `plugins/ticket/CLAUDE.md` gained a "State Management & Isolation"
  section and a rewritten "Commits and Merges"; plugin bumped to 0.4.0.

Verification: `ticket-state.sh` unit round-trip (claim / held / steal,
transition from-guard + `--move`, lint detection + `--fix`), plus an end-to-end
run proving the claim lock is shared across worktrees and that a branch-local
status change stays invisible in the main tree. Real `doc/tickets` lints clean.

Follow-ups (out of scope here): optionally ship a dedicated evaluator agent
definition (`agents/ticket-evaluator.md`) to pin a different model for the
evaluator; optionally declare a `## Verification` block for this repo's scripts
(`bash -n`, shellcheck).
