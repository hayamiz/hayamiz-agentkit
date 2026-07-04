# ticket plugin

File-based, in-repo ticket workflow. Tickets are numbered Markdown files stored
in the project, tracked through their own lifecycle, and edited by the skills
in this plugin. Distinct from GitHub Issues: the tickets live in the working
tree and ride along with the code they describe.

## Skills in This Plugin

| Skill                | Purpose                                                                                                                  |
| :------------------- | :----------------------------------------------------------------------------------------------------------------------- |
| `/ticket-init`       | One-time setup per host project: resolve/declare `<ticket-dir>`, create its `CLAUDE.md`, migrate legacy.                 |
| `/ticket-create`     | Create a new numbered ticket under `<ticket-dir>/`.                                                                      |
| `/grill-with-ticket` | Relentless one-question-at-a-time interview against an open ticket; crystallises decisions into `## Implementation Notes`. |
| `/ticket-check`      | Read-only: list open tickets and their status.                                                                           |
| `/ticket-triage`     | Classify each open ticket by complexity, mechanical-fix feasibility, and user input needed; recommends a fix strategy (in-place / worktree). |
| `/ticket-fix`        | Implement mechanically-fixable tickets: trivial ones in place, non-trivial ones in isolated worktrees checked by an independent evaluator. On PASS routes to `awaiting-review` (or `ready-to-apply` when review is skippable). Claims tickets with locks. Does not merge to your branch. |
| `/ticket-review`     | **Human-only.** Review each `awaiting-review` worktree fix (summary, impact, full diff, traceability, verification, risk — inline or as a Claude Artifact) and, on approval, move it to `ready-to-apply`. Does not merge. |
| `/ticket-apply`      | **Human-only.** Merge the `ready-to-apply` worktree fixes into your current branch and move them to `resolved`. Never auto-merges. |
| `/ticket-lint`       | Validate ticket frontmatter and the `status`⇔location invariant; inspect/clear claim locks. `--fix` for safe repairs.    |

Typical flow on a new project:

```
/ticket-init                 # once per project
/ticket-create "<title>"     # as needed
/grill-with-ticket NNNN      # optional: stress-test the plan before fixing
/ticket-check                # see state
/ticket-triage               # classify open tickets
/ticket-fix                  # fix mechanically fixable ones (worktree fixes → awaiting-review / ready-to-apply)
/ticket-review               # human-review the awaiting-review worktree fixes → ready-to-apply
/ticket-apply                # merge the ready-to-apply (worktree) fixes into your branch
/commit-session              # commit the in-place fixes + resolved tickets
```

`/ticket-lint` can be run at any time to check ticket integrity and inspect
locks; it also runs as a read-only gate at the start of triage / fix / review /
apply.

## Concepts

### `<ticket-dir>`

The directory that holds ticket files. Default `doc/tickets/`, but each host
project declares its own path in the root `CLAUDE.md` (under a `Tickets:` or
`Ticket directory:` line, or a `## Tickets` heading). All five skills resolve
this path at runtime — never hardcode it.

### Ticket file layout

```
<ticket-dir>/
├── CLAUDE.md                    # schema + lifecycle for this project's tickets
├── 0001-<kebab-subject>.md      # open / in-progress / blocked
├── 0002-<kebab-subject>.md
└── resolved/
    └── 0003-<kebab-subject>.md  # resolved (moved by /ticket-fix)
```

- `NNNN` is a zero-padded 4-digit sequence. Never reuse numbers.
- `<kebab-subject>` is 2–5 kebab-case words.

### Frontmatter

Each ticket file starts with YAML frontmatter:

```yaml
---
title: <one-line human-readable title>
type: bug | feature | enhancement | refactor | docs | test | chore
priority: critical | high | medium | low
status: open | in-progress | blocked | awaiting-review | ready-to-apply | resolved
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

### Body sections

- `## Description` (required, at create time) — what and why, enough context to act on.
- `## Triage` (added by `/ticket-triage`) — complexity / mechanical-fix / requires-user-decision / notes.
- `## Implementation Notes` (added by `/ticket-triage` when mechanical fix is `no`) — plan, alternatives, decision points.
- `## Resolution` (added by `/ticket-fix`) — what changed, tests added, follow-ups.

### Lifecycle

- `open` → newly created, not yet triaged.
- `in-progress` → being worked on (set by `/ticket-fix`).
- `blocked` → waiting on external input; stays in `<ticket-dir>/`, not `resolved/`.
- `awaiting-review` → a worktree fix passed the evaluator and needs human review
  (set by `/ticket-fix`; branch-local). Stays in `<ticket-dir>/`, not `resolved/`.
- `ready-to-apply` → reviewed-and-approved (via `/ticket-review`), or the reviewer
  marked review skippable (low-risk); ready for `/ticket-apply` to merge.
  Branch-local; stays in `<ticket-dir>/`, not `resolved/`.
- `resolved` → landed on your branch; file moves to `<ticket-dir>/resolved/`. The
  `resolved`-move now happens at **apply** time (on your current branch), not on
  the throwaway `ticket/*` branch — so `resolved` honestly means "merged and done".

## State Management & Isolation

All ticket `status` changes and locking go through one bundled script,
`scripts/ticket-state.sh` (invoked as
`${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh`). It is the single entry point
to the state machine — this is what keeps parallel runs from corrupting ticket
state. Three layers:

- **Claim locks** — before working a ticket, `/ticket-fix` atomically claims it
  (a `mkdir` lock under the shared git dir,
  `$(git rev-parse --git-common-dir)/ticket-locks/NNNN/`). A second agent that
  tries the same ticket is refused. This separates *runtime ownership* (the
  lock) from *durable state* (the `status:` field), which matters because a
  branch-local `status: in-progress` is invisible in the main tree until merged.
  Portable via `mkdir` atomicity — no `flock` dependency (macOS has none). Stale
  locks (older than `Lock TTL`, default 2h, or whose worktree is gone) are stolen
  with a warning.
- **Atomic transitions** — `transition` rewrites `status` + `updated` with a
  temp-file rename and, for `resolved`, does the `resolved/` move in the same
  step, enforcing the `status: resolved ⇔ under resolved/` invariant. Never edit
  the `status:` line or `git mv` a ticket by hand.
- **Lint** — `lint` validates frontmatter, filenames, unique numbers, the
  location invariant, and lock consistency (orphan / stale). It runs as a
  read-only gate at the start of triage / fix / apply, and standalone as
  `/ticket-lint`.

**Worktrees** for non-trivial fixes live at
`$(git rev-parse --git-common-dir)/ticket-worktrees/ticket-NNNN` on
`ticket/NNNN-<slug>` branches — outside the working tree, so they never appear
in `git status`. `/ticket-apply` merges and removes them.

**Scope limit** (state this honestly, don't oversell): locks coordinate agents
against the **same clone** (multiple worktrees + local sessions). They do not
span clones — a cloud run and a local run use separate git dirs. Cross-clone
safety relies on git merge-conflict detection plus the `/ticket-apply` human
gate.

## The Review Gate (generator / evaluator)

A non-trivial fix is checked by an **independent reviewer** before it counts as
"ready to apply" — the agent that wrote the code never grades its own work.
`/ticket-fix` picks the reviewer in this order:

1. **The Codex CLI, if available and working** — from the fix's worktree,
   `codex review --base <base> -c sandbox_mode="danger-full-access"` reviews the
   ticket branch against its base with a **non-Claude** model, so the judgement is
   genuinely independent of the generator (the strongest form of the split). The
   sandbox override lets it run in containers / CI where Codex's own bubblewrap
   sandbox cannot create a namespace (otherwise it exits 0 without inspecting the
   diff); the review only reads git and files. This depends only on the user's
   `codex` CLI being installed and authenticated — no plugin, no coupling to any
   plugin's internals.
2. **The bundled `ticket:ticket-evaluator` agent (on Sonnet)** — the fallback
   whenever the Codex CLI is absent or does not return a usable result (not
   authenticated, rate-limited, timed out, empty). It is a Claude subagent
   (`model: sonnet`) that is adversarial *by prompt* (assume-broken-until-proven,
   run the tests, judge behavior not intent, edit nothing). Sonnet is a different
   tier from the Opus-class generator; its independence comes from that tier gap
   plus the fresh context, skeptical instructions, and worktree isolation.

The Codex CLI is an **optional external dependency**: if `codex` is on the
user's PATH and logged in, `/ticket-fix` uses it automatically; otherwise the
Sonnet evaluator handles the review with no extra setup.

### The independent PASS vs. the human review

The reviewer above answers "is this code correct?" — an **independent machine
check**. It does not replace the **human** looking at the change before it lands.
The two are now separate steps:

- On PASS, `/ticket-fix` routes the worktree fix by a **`human-review` skip
  signal** the reviewer emits alongside its verdict:
  - `human-review: recommended` → `awaiting-review`. `/ticket-review` presents the
    full review material (summary, functional impact, full diff, traceability,
    verification/provenance, change map, risk — inline or as a Claude Artifact for
    large diffs) and, on approval, moves it to `ready-to-apply`.
  - `human-review: optional` → `ready-to-apply` directly (review skipped —
    low-risk). `optional` requires ALL of: low-risk, no user-visible behavior
    change, no security-sensitive surface, tests present; the default is
    conservative (`recommended` whenever in doubt). `/ticket-apply` still lists
    these distinctly so the human keeps the final merge action.
- **Emitting the skip signal.** The Sonnet evaluator emits `human-review:` itself
  (part of its output contract). The **Codex path cannot** (`codex review --base`
  takes no custom prompt), so after a Codex PASS `/ticket-fix` obtains the signal
  from a **dedicated lightweight Sonnet skip-judge** — a second
  `ticket:ticket-evaluator` dispatch in "skip-eligibility only" mode that reads the
  branch diff and returns only `human-review: recommended | optional`, editing
  nothing. On any failure or ambiguity it defaults to `recommended`, so both
  reviewer paths route consistently.

## Project Integration

Host-project specifics live in **the host repo's** `<ticket-dir>/CLAUDE.md`,
not in this plugin:

- **Spec**: `Spec: doc/SPEC.md` line tells `/ticket-fix` to reconcile the spec
  when a fix changes user-visible behavior.
- **Verification**: a `## Verification` section lists shell commands
  (tests, linters, type checks) that `/ticket-fix` runs after each fix.

If neither is declared, `/ticket-fix` falls back to asking the user.

## Portability Rule (for plugin maintainers)

Every skill here must stay project-agnostic. No hardcoded language, framework,
test runner, or path conventions in the skill bodies. Project-specific
knowledge belongs in the host repo's `CLAUDE.md` and `<ticket-dir>/CLAUDE.md`
— the skills **read** that configuration at runtime. Before merging an edit to
any `skills/*/SKILL.md` here, check that a new instruction would make sense
across stacks; if not, rewrite it as a principle or move it to the per-project
`CLAUDE.md` template in `skills/ticket-init/SKILL.md`'s Appendix.

## Commits and Merges

The plugin never lands work on your current branch on its own:

- **In-place (trivial) fixes** leave the working tree dirty — resolved tickets
  moved, source/test edits applied. Commit them with `/commit-session` (from the
  `commit-session` skill in this repo).
- **Non-trivial fixes** are committed by `/ticket-fix` proactively onto
  throwaway `ticket/NNNN-<slug>` branches — the fix and its tests, then the ticket
  moved to `awaiting-review` / `ready-to-apply` (it stays in `<ticket-dir>/`, not
  `resolved/`) — never your branch. Worktree isolation is what makes eager
  committing safe. They reach your branch only when **you** run `/ticket-apply`,
  which does a `git merge --no-ff` per approved ticket **and** the
  `ready-to-apply → resolved --move` on your branch — the single, human-invoked
  place the plugin commits to your branch. `/ticket-review` in between only moves
  the branch ticket to `ready-to-apply`; it never touches your branch.
- Claim locks live under `.git` and are never committed.

So the rule is now "never commits or merges to *your* branch automatically":
generator commits are confined to disposable branches, and integration is gated
behind the human-only `/ticket-apply`.

## Reference

Upstream plugin spec: <https://code.claude.com/docs/en/plugins-reference>.
For individual skill details, see each `skills/*/SKILL.md`.
