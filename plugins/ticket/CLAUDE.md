# ticket plugin

File-based, in-repo ticket workflow. Tickets are numbered Markdown files stored
in the project, tracked through their own lifecycle, and edited by the skills
in this plugin. Distinct from GitHub Issues: the tickets live in the working
tree and ride along with the code they describe.

## Skills in This Plugin

| Skill             | Purpose                                                                                                  |
| :---------------- | :------------------------------------------------------------------------------------------------------- |
| `/ticket:init`    | One-time setup per host project: resolve/declare `<ticket-dir>`, create its `CLAUDE.md`, migrate legacy. |
| `/ticket:create`  | Create a new numbered ticket under `<ticket-dir>/`.                                                      |
| `/ticket:check`   | Read-only: list open tickets and their status.                                                           |
| `/ticket:triage`  | Classify each open ticket by complexity, mechanical-fix feasibility, and whether user input is needed.   |
| `/ticket:fix`     | Implement fixes for all tickets triaged as mechanically fixable. Does not commit.                        |

Typical flow on a new project:

```
/ticket:init                 # once per project
/ticket:create "<title>"     # as needed
/ticket:check                # see state
/ticket:triage               # classify open tickets
/ticket:fix                  # resolve mechanically fixable ones
/commit-session              # commit the resulting changes
```

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
    └── 0003-<kebab-subject>.md  # resolved (moved by /ticket:fix)
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
status: open | in-progress | blocked | resolved
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

### Body sections

- `## Description` (required, at create time) — what and why, enough context to act on.
- `## Triage` (added by `/ticket:triage`) — complexity / mechanical-fix / requires-user-decision / notes.
- `## Implementation Notes` (added by `/ticket:triage` when mechanical fix is `no`) — plan, alternatives, decision points.
- `## Resolution` (added by `/ticket:fix`) — what changed, tests added, follow-ups.

### Lifecycle

- `open` → newly created, not yet triaged.
- `in-progress` → being worked on (set by `/ticket:fix`).
- `blocked` → waiting on external input; stays in `<ticket-dir>/`, not `resolved/`.
- `resolved` → done; file moves to `<ticket-dir>/resolved/`.

## Project Integration

Host-project specifics live in **the host repo's** `<ticket-dir>/CLAUDE.md`,
not in this plugin:

- **Spec**: `Spec: doc/SPEC.md` line tells `/ticket:fix` to reconcile the spec
  when a fix changes user-visible behavior.
- **Verification**: a `## Verification` section lists shell commands
  (tests, linters, type checks) that `/ticket:fix` runs after each fix.

If neither is declared, `/ticket:fix` falls back to asking the user.

## Portability Rule (for plugin maintainers)

Every skill here must stay project-agnostic. No hardcoded language, framework,
test runner, or path conventions in the skill bodies. Project-specific
knowledge belongs in the host repo's `CLAUDE.md` and `<ticket-dir>/CLAUDE.md`
— the skills **read** that configuration at runtime. Before merging an edit to
any `skills/*/SKILL.md` here, check that a new instruction would make sense
across stacks; if not, rewrite it as a principle or move it to the per-project
`CLAUDE.md` template in `skills/init/SKILL.md`'s Appendix.

## Does Not Commit

None of the skills in this plugin run `git commit`, `git add`, or equivalent.
After `/ticket:fix` resolves a batch, the working tree is dirty with resolved
tickets moved and source/test edits applied. Use `/commit-session` (from the
`commit-session` skill in this repo) to commit the result.

## Reference

Upstream plugin spec: <https://code.claude.com/docs/en/plugins-reference>.
For individual skill details, see each `skills/*/SKILL.md`.
