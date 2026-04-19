---
name: ticket-init
description: "Initialize the project's ticket directory. Resolves (or declares) the ticket path in CLAUDE.md, creates the directory and its CLAUDE.md, and offers to migrate pre-existing ticket-like directories (e.g. doc/issues/)."
allowed-tools: Bash(*) Read Write Edit Glob Grep
---

# Ticket Init

One-time setup for the `ticket-*` skill family on a host project. Decides where tickets will live, records that decision in the project's root `CLAUDE.md`, creates the directory plus its conventions file, and — if the repo already has a legacy ticket-like directory — offers to migrate its contents.

Run this before `ticket-create` / `ticket-check` / `ticket-triage` / `ticket-fix` on a new project. Running it again on an already-initialized project is safe: it detects existing state and does not overwrite.

## Portability (maintainers, read this before editing)

These skills must remain project-agnostic. When updating this SKILL.md, do **not** introduce hardcoded references to specific languages, frameworks, test runners, build tools, file paths, or directory layouts. Project-specific knowledge belongs in the host repo's `CLAUDE.md` and the host repo's `<ticket-dir>/CLAUDE.md` — these skills **read** that configuration at runtime, they do not embed it. If a new instruction would only make sense in one tech stack, rewrite it as a principle before merging.

## Instructions

### Step 1: Resolve the ticket directory

1. Read the host repo's root `CLAUDE.md` if it exists. Look for a declaration of the ticket directory. Recognized hints:
   - A line of the form `Tickets: <path>` or `Ticket directory: <path>`.
   - A section heading like `## Tickets` or `## Ticket directory` that names a path.
2. If such a declaration is found, let `<ticket-dir>` be that path and skip to Step 2 — do not modify `CLAUDE.md`.
3. If no declaration is found:
   - Let `<ticket-dir>` default to `doc/tickets/`.
   - Append a declaration to the root `CLAUDE.md` so subsequent `ticket-*` invocations resolve the path without defaulting. Format:

     ```markdown
     ## Tickets

     Ticket directory: doc/tickets/

     File-based work-item tickets for this project live under `doc/tickets/`.
     Managed by the `ticket-*` skill family (`ticket-create`, `ticket-check`,
     `ticket-triage`, `ticket-fix`). See `doc/tickets/CLAUDE.md` for the
     ticket schema and lifecycle.
     ```

   - If the root `CLAUDE.md` does not exist at all, **ask the user** whether to create it before writing. Do not silently create a root `CLAUDE.md` — it's a significant project-wide artifact.
   - Tell the user which file was updated (or created).

### Step 2: Ensure the ticket directory exists

- If `<ticket-dir>` does not exist, create it (and its `resolved/` subdirectory).
- If it already exists, leave it alone.

### Step 3: Ensure `<ticket-dir>/CLAUDE.md` exists

If `<ticket-dir>/CLAUDE.md` does not exist, create it with the template shown in the Appendix of this file. If it already exists, **do not** overwrite it — the project may have customized it.

### Step 4: Detect and offer to migrate legacy ticket-like directories

Scan the repo for directories that look like pre-existing file-based ticket trackers. Heuristics — a directory is a candidate if **all** of:

- Its name suggests a tracker: one of `issues`, `issue`, `tickets`, `ticket`, `tasks`, `todos`, `chores`, or has a parent `doc/`, `docs/`, `design/`, `planning/` whose direct child matches one of those names.
- It contains two or more files matching `NNNN-*.md` (zero-padded numeric prefix + kebab-subject), **or** it contains Markdown files whose YAML frontmatter includes a `status:` field with values like `open`, `in-progress`, `resolved`, `blocked`.
- It is **not** `<ticket-dir>` itself.

Use `Glob` / `Grep` to find candidates. If none are found, skip to Step 5.

For each candidate found:

1. Report the candidate to the user, including: path, approximate file count, and a sample of 2–3 ticket titles (from the first line of each file or from frontmatter).
2. **Always ask the user whether to migrate**, even under `bypassPermission` or Auto mode. The question must be explicit — offer `migrate`, `skip`, `abort` (stop ticket-init entirely). Do not proceed without an answer. This ask is mandatory regardless of permission mode because migration moves and renames user-authored content.
3. If the user chooses `migrate`:
   - Determine the next available ticket number in `<ticket-dir>/` (highest `NNNN` in both `<ticket-dir>/` and `<ticket-dir>/resolved/`, plus one; start at `0001` if empty).
   - For each file in the legacy directory matching `NNNN-*.md`:
     - **Keep the original filename and number** if that number is not already used in `<ticket-dir>/` (including `resolved/`). This preserves history and any external references.
     - If the number collides, renumber the incoming file to the next available slot and record the old → new mapping for the final report.
   - Preserve the file's status: if frontmatter says `status: resolved`, place it under `<ticket-dir>/resolved/`; otherwise place it directly in `<ticket-dir>/`.
   - Use `git mv` if the file is tracked by git, so history is preserved. Fall back to plain `mv` for untracked files.
   - If the legacy directory has its own `CLAUDE.md` and `<ticket-dir>/CLAUDE.md` was freshly created in Step 3, **replace** `<ticket-dir>/CLAUDE.md` with the legacy one (preserves the project's existing schema). If `<ticket-dir>/CLAUDE.md` was already non-empty before this run, do not overwrite — instead copy the legacy `CLAUDE.md` to `<ticket-dir>/CLAUDE.legacy.md` and tell the user to reconcile manually.
   - After migration, remove the now-empty legacy directory (again prefer `git rm` for tracked files). If any non-ticket files remain in it, leave the directory in place and report which files were not migrated.
4. If the user chooses `skip`: leave the legacy directory alone and continue with the next candidate (or Step 5 if none left).
5. If the user chooses `abort`: stop the skill immediately. Do not undo earlier steps (the ticket directory and CLAUDE.md edits are already in place and safe to keep), but make no further changes.

### Step 5: Summary

Report to the user:

- The resolved `<ticket-dir>` path and whether it was newly created.
- Whether the root `CLAUDE.md` was updated (or created) with the declaration.
- Whether `<ticket-dir>/CLAUDE.md` was newly created or already existed.
- For each migrated legacy directory: files moved, any renumbering that happened, and files that were **not** migrated (if any).
- Next recommended command: `/ticket-check` to see the state, or `/ticket-create <title>` to add a new ticket.

## Notes

- This skill only writes to the root `CLAUDE.md`, inside `<ticket-dir>/`, and — during migration — inside the legacy directory it's moving from. It never touches source code.
- Re-running `ticket-init` on an already-initialized project should be a no-op unless a new legacy directory has appeared.
- The mandatory migration ask in Step 4 is a safety rail. A misidentified "legacy tracker" could be a design doc directory or unrelated Markdown collection — moving those silently would destroy the user's organization. The ask stands even in Auto mode.

## Appendix: default `<ticket-dir>/CLAUDE.md`

If `<ticket-dir>/CLAUDE.md` is missing, create it with the following content. The host project may later edit this file to customize the schema — downstream `ticket-*` skills will respect the edits.

```markdown
# Ticket conventions

This directory holds file-based work-item tickets. Each ticket is a Markdown
file with YAML frontmatter. Tickets are managed by the `ticket-*` skill
family (`ticket-create`, `ticket-check`, `ticket-triage`, `ticket-fix`).

## File naming

- Open / in-progress / blocked tickets: `<ticket-dir>/NNNN-<kebab-subject>.md`
- Resolved tickets: `<ticket-dir>/resolved/NNNN-<kebab-subject>.md`
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

Added by `ticket-triage`:

- `## Triage`
  - `Complexity: low | medium | high`
  - `Mechanical fix: yes | no`
  - `Requires user decision: yes | no`
  - `Notes:` a short rationale.

Added by `ticket-triage` when `Mechanical fix: no`:

- `## Implementation Notes` — concrete plan, alternatives, open questions,
  specific decision points for the user.

Added by `ticket-fix` on resolution:

- `## Resolution` — what was changed, which tests were added, any follow-ups.

## Lifecycle

- `open` — newly created, not yet triaged.
- `in-progress` — being worked on (set by `ticket-fix`).
- `blocked` — waiting on external input; keep in the open directory.
- `resolved` — done; file moves to `<ticket-dir>/resolved/`.

## Project integration

If this project has a spec or design doc that tickets should stay consistent
with, name it here (e.g., `Spec: doc/SPEC.md`). `ticket-fix` will read this
hint and update the spec when a fix changes user-visible behavior. If no
spec is declared, the spec-update step is skipped.

If this project has verification commands (tests, linters, type checks)
that `ticket-fix` should run, list them here under a `## Verification`
heading as a shell-ready checklist. If none are declared, `ticket-fix`
will ask the user what to run.
```
