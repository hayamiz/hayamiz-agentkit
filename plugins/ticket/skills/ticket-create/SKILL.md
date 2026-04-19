---
name: ticket-create
description: "Create a new ticket in the project's ticket directory. Tickets are file-based, numbered work items tracked in the repository (distinct from GitHub Issues)."
argument-hint: "<title or description>"
allowed-tools: Bash(*) Read Write Glob Grep
---

# Ticket Create

Create a new ticket file in the project's **ticket directory** (a file-based, in-repo work-item tracker). Tickets are numbered Markdown files with YAML frontmatter. This family of skills (`ticket-create`, `ticket-check`, `ticket-triage`, `ticket-fix`) together manages the lifecycle of such tickets.

## Portability (maintainers, read this before editing)

These skills must remain project-agnostic. When updating this SKILL.md, do **not** introduce hardcoded references to specific languages, frameworks, test runners, build tools, file paths, or directory layouts. Project-specific knowledge belongs in the host repo's `CLAUDE.md` and the host repo's `<ticket-dir>/CLAUDE.md` — these skills **read** that configuration at runtime, they do not embed it. If a new instruction would only make sense in one tech stack, rewrite it as a principle (e.g., "run the verification commands declared in `CLAUDE.md`") before merging.

## Instructions

### Step 1: Resolve the ticket directory

1. Read the host repo's root `CLAUDE.md` (if present). Look for a declaration of the ticket directory. Recognized hints:
   - A line of the form `Tickets: <path>` or `Ticket directory: <path>`.
   - A section heading like `## Tickets` that names a path.
2. If none is found, default to `doc/tickets/` (with resolved tickets under `doc/tickets/resolved/`).
3. Let `<ticket-dir>` denote the resolved path for the rest of this skill.

### Step 2: Ensure `<ticket-dir>/CLAUDE.md` exists

Read `<ticket-dir>/CLAUDE.md` — it defines the frontmatter schema, body structure, lifecycle, and triage-section format used by all four `ticket-*` skills.

If it does not exist, tell the user to run `/ticket-init` first — that skill handles project bootstrap (creating `<ticket-dir>`, writing `<ticket-dir>/CLAUDE.md`, declaring the path in the root `CLAUDE.md`, and migrating any legacy ticket-like directory). Stop here.

Do **not** silently overwrite an existing `<ticket-dir>/CLAUDE.md`.

### Step 3: Determine the next ticket number

- List files in `<ticket-dir>/` and `<ticket-dir>/resolved/` matching the `NNNN-*.md` pattern.
- Take the highest `NNNN` and increment by 1. If none, start at `0001`.
- Use zero-padded, 4-digit numbering.

### Step 4: Gather ticket details

Parse `$ARGUMENTS` for the user's input:

- If the user provided a full description, use it.
- If only a brief phrase was provided, use it as the title; infer the body from context when possible, or ask the user for a one-paragraph description.

### Step 5: Determine metadata

Follow the schema defined in `<ticket-dir>/CLAUDE.md`. At minimum:

- `type`: infer from the description (e.g., `bug`, `feature`, `enhancement`, `refactor`, `docs`, `test`, `chore`). If unclear, ask.
- `priority`: infer from the description; default to `medium` if unclear. Allowed values should follow `<ticket-dir>/CLAUDE.md`.
- `status`: always `open` for new tickets.
- `created` and `updated`: today's date (ISO `YYYY-MM-DD`).

### Step 6: Create the file

- Filename: `<ticket-dir>/NNNN-<kebab-case-subject>.md`.
  - `<subject>` is a 2–5 word kebab-case summary of the ticket.
- Body: use the exact frontmatter + body template from `<ticket-dir>/CLAUDE.md`.

### Step 7: Report

Print the created file path and a one-line summary of the ticket.

## Notes

- Never write the ticket into any directory other than `<ticket-dir>/` (resolved tickets live under `<ticket-dir>/resolved/` and are moved there by `ticket-fix`, not here).
- If the user's input already describes an existing ticket (same subject), warn them and ask whether to create a duplicate or update the existing one.
- This skill is read-only with respect to source code — it only writes inside `<ticket-dir>/`.
- Project bootstrap (creating `<ticket-dir>`, writing `<ticket-dir>/CLAUDE.md`, declaring the path in the root `CLAUDE.md`, migrating legacy ticket directories) is handled by `/ticket-init`. This skill assumes that step has already been done.
