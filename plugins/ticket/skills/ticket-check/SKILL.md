---
name: ticket-check
description: "List all currently open tickets in the project's ticket directory. Read-only summary of file-based work items (distinct from GitHub Issues)."
allowed-tools: Read Glob Grep
---

# Ticket Check

Display a summary of all currently non-resolved tickets in the project's ticket directory. Read-only — this skill never modifies any files.

## Portability (maintainers, read this before editing)

These skills must remain project-agnostic. When updating this SKILL.md, do **not** introduce hardcoded references to specific languages, frameworks, test runners, build tools, file paths, or directory layouts. Project-specific knowledge belongs in the host repo's `CLAUDE.md` and the host repo's `<ticket-dir>/CLAUDE.md` — these skills **read** that configuration at runtime, they do not embed it. If a new instruction would only make sense in one tech stack, rewrite it as a principle before merging.

## Instructions

### Step 1: Resolve the ticket directory

1. Read the host repo's root `CLAUDE.md` (if present) for a declaration of the ticket directory (e.g., `Tickets: <path>`).
2. If none is declared, default to `doc/tickets/`.
3. Let `<ticket-dir>` denote the resolved path.

If `<ticket-dir>` does not exist, report "No ticket directory found — run `/ticket-create` to bootstrap one." and stop.

### Step 2: Collect non-resolved tickets

- List all `*.md` files directly in `<ticket-dir>/` that match `NNNN-*.md`.
- Exclude `<ticket-dir>/CLAUDE.md` and anything under `<ticket-dir>/resolved/`.
- Read each file's YAML frontmatter.
- Keep only tickets whose `status` is one of `open`, `in-progress`, or `blocked`.

### Step 3: Display

Present the tickets as a table, sorted first by priority (`critical` > `high` > `medium` > `low`) then by ticket number:

| Ticket | Title | Type | Priority | Status | Created |
|--------|-------|------|----------|--------|---------|
| #NNNN  | ...   | ...  | ...      | ...    | ...     |

### Step 4: Summary line

Below the table, show:

- Total count of non-resolved tickets.
- Breakdown by status (e.g., `3 open, 1 in-progress, 1 blocked`).
- Breakdown by priority (e.g., `1 critical, 2 high, 1 medium, 1 low`).

### Step 5: Empty and error cases

- If there are no non-resolved tickets, report `No open tickets.` and stop.
- If any ticket file has malformed frontmatter, list it under a `Warnings` section after the table but do not fail the whole command. Include the file path and a brief reason (e.g., "missing `priority` field").

## Notes

- This skill is read-only. Do not modify, move, or rewrite any ticket file, even to fix malformed frontmatter — report warnings and let the user or `/ticket-triage` address them.
- Recognized status values default to `open`, `in-progress`, `blocked`, `resolved`. If `<ticket-dir>/CLAUDE.md` defines a different status vocabulary, honor that instead.
