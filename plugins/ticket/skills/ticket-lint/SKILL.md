---
name: ticket-lint
description: "Validate ticket files and inspect claim locks. Checks frontmatter schema, the status<->location invariant, unique numbers, and lock consistency (orphan/stale). Runs the bundled ticket-state.sh script. Use to check ticket health or before/after a batch of fixes."
argument-hint: "[ticket-number] [--fix]"
allowed-tools: Bash(*) Read Glob Grep
---

# Ticket Lint

Validate the integrity of the project's ticket files and inspect the runtime
claim locks. This is the read-only guardrail that keeps ticket-based state
management from silently drifting: `/ticket-triage`, `/ticket-fix`, and
`/ticket-apply` all run the same check as a gate before mutating anything.

All the logic lives in the bundled script `ticket-state.sh` — this skill
resolves the ticket directory and drives that script.

## Instructions

### Step 1: Resolve the ticket directory

Read the host repo's root `CLAUDE.md` for a ticket-directory declaration
(`Tickets:` / `Ticket directory:` line or a `## Tickets` heading). Default:
`doc/tickets/`. If `<ticket-dir>/CLAUDE.md` is missing, tell the user to run
`/ticket-init` first and stop.

### Step 2: Run lint

Invoke the bundled script (it must run inside the git repository):

```
${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> lint [--all|NNNN] [--fix]
```

- No argument, or `--all`: lint every ticket.
- A ticket number in `$ARGUMENTS`: lint only that ticket.
- `--fix` in `$ARGUMENTS`: apply **safe** repairs only (normalize enum casing,
  relocate a file to match its `status`). Everything else is reported, not
  changed.

What the script checks:

- Frontmatter has the required keys (`title`, `type`, `priority`, `status`,
  `created`, `updated`) with valid enum values and `YYYY-MM-DD` dates.
- Filenames are `NNNN-<kebab-subject>.md` and ticket numbers are unique.
- **`status: resolved` ⇔ file under `resolved/`** (and vice-versa).
- Lock consistency: warns on orphan locks (no matching ticket) and stale locks
  (older than the lock TTL).

The script exits non-zero (`6`) when any hard error remains. Relay the script's
output to the user. If errors remain after a plain run, offer to re-run with
`--fix`, but call out that a bad `status` value or a missing key needs a manual
edit — `--fix` will not invent content.

### Step 3: Inspect locks (when asked about in-flight work)

To show which tickets are currently claimed (and by whom / how old / on which
branch), run:

```
${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> status [NNNN]
```

Entries flagged `STALE` (older than the TTL) or `DEAD-WORKTREE` (their worktree
is gone) are safe to clear — a subsequent `/ticket-fix` will steal them
automatically, or the user can release one explicitly.

## Notes

- **Read-only by default.** Without `--fix`, this skill never modifies ticket
  files; it only reports. `--fix` performs only the two safe repairs above.
- **Locks live under `.git`**, not in the working tree, so they are shared
  across all worktrees of the clone and are never committed. Clearing a stale
  lock has no effect on committed state.
- This skill does not commit. If `--fix` moved or edited files, use
  `/commit-session` to commit the result.
