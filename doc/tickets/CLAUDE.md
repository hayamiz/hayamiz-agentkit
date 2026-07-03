# Ticket conventions

This directory holds file-based work-item tickets. Each ticket is a Markdown
file with YAML frontmatter. Tickets are managed by the `ticket` plugin
(`/ticket-create`, `/ticket-check`, `/ticket-triage`, `/ticket-fix`).

## File naming

- Open / in-progress / blocked tickets: `doc/tickets/NNNN-<kebab-subject>.md`
- Resolved tickets: `doc/tickets/resolved/NNNN-<kebab-subject>.md`
- `NNNN` is a zero-padded 4-digit sequence; never reuse numbers.
- `<kebab-subject>` is 2–5 words in kebab-case.

## Frontmatter schema

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

## Body sections

Required:

- `## Description` — what and why. Include enough context that a reader
  unfamiliar with the conversation can act on it.

Added by `/ticket-triage`:

- `## Triage`
  - `Complexity: low | medium | high`
  - `Mechanical fix: yes | no`
  - `Requires user decision: yes | no`
  - `Notes:` a short rationale.

Added by `/ticket-triage` when `Mechanical fix: no`:

- `## Implementation Notes` — concrete plan, alternatives, open questions,
  specific decision points for the user.

Added by `/ticket-fix` on resolution:

- `## Resolution` — what was changed, which tests were added, any follow-ups.

## Lifecycle

- `open` — newly created, not yet triaged.
- `in-progress` — being worked on (set by `/ticket-fix`).
- `blocked` — waiting on external input; keep in the open directory.
- `resolved` — done; file moves to `doc/tickets/resolved/`.

## Project integration

If this project has a spec or design doc that tickets should stay consistent
with, name it here (e.g., `Spec: doc/SPEC.md`). `/ticket-fix` will read this
hint and update the spec when a fix changes user-visible behavior. If no
spec is declared, the spec-update step is skipped.

If this project has verification commands (tests, linters, type checks)
that `/ticket-fix` should run, list them here under a `## Verification`
heading as a shell-ready checklist. If none are declared, `/ticket-fix`
will ask the user what to run.

## Concurrency

`/ticket-fix` may work on several tickets in parallel, each in its own git
worktree. To stop two agents from grabbing the same ticket, the `ticket`
plugin takes atomic claim locks under the repo's shared git dir
(`.git/ticket-locks/`, never committed) via the bundled `ticket-state.sh`
script. This protects agents running against the **same clone**; it does not
coordinate across separate clones (e.g. a cloud run vs. a local one), which
rely on git merge-conflict detection plus the `/ticket-apply` human gate.

- `Lock TTL: 2h` — how long a claim lock is honored before a fresh run may
  steal it (assuming the previous owner died). Accepts `2h`, `90m`, `1h30m`,
  or bare seconds. Omit this line to use the 2h default.

## Verification

This repo ships Markdown skills, plugin manifests, and shell scripts — there is
no test suite, so `/ticket-fix` verifies changes with syntax / schema / lint
checks. Run from the repo root; each command fails loudly (non-zero) on a
problem:

```sh
# 1) shell scripts parse
for f in $(git ls-files '*.sh'); do bash -n "$f" || exit 1; done
# 2) plugin & marketplace manifests are valid JSON
for f in $(git ls-files '*plugin.json' '*marketplace.json'); do \
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" || exit 1; done
# 3) ticket state is consistent (frontmatter, invariants, locks)
plugins/ticket/scripts/ticket-state.sh --dir doc/tickets lint --all
```

`shellcheck` is worth running manually on changed shell scripts when it's
installed (`shellcheck -S warning <file>`), but it is kept out of the auto-run
list above: it isn't present in the standard dev image, and `ticket-state.sh`
has not yet been audited clean against it.
