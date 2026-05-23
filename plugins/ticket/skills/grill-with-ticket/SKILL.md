---
name: grill-with-ticket
description: "Relentless one-question-at-a-time interview that stress-tests an open ticket's plan, sharpens fuzzy language, and crystallises decisions inline into the ticket's Implementation Notes section. Use when the user wants to harden a ticket before fixing it."
argument-hint: "[ticket number, path, partial subject — empty to choose interactively]"
allowed-tools: Bash(*) Read Write Edit Glob Grep
---

# Grill With Ticket

Run a relentless one-question-at-a-time interview against an **open ticket** (a file-based work item managed by this plugin) and crystallise the resulting decisions directly into the ticket's `## Implementation Notes` section as the session progresses. The aim is to harden a vague or under-specified ticket *before* `/ticket-fix` (or a human) starts implementing it.

Adapted from <https://github.com/mattpocock/skills/blob/main/skills/engineering/grill-with-docs/SKILL.md>. The glossary (`CONTEXT.md`) and ADR layers from the upstream skill are intentionally dropped: this repo's ticket plugin has no counterpart concept, and `## Implementation Notes` is already the canonical home for *"plan, alternatives, decision points"*.

## Portability (maintainers, read this before editing)

These skills must remain project-agnostic. When updating this SKILL.md, do **not** introduce hardcoded references to specific languages, frameworks, test runners, build tools, file paths, or directory layouts. Project-specific knowledge belongs in the host repo's `CLAUDE.md` and the host repo's `<ticket-dir>/CLAUDE.md` — these skills **read** that configuration at runtime, they do not embed it. If a new instruction would only make sense in one tech stack, rewrite it as a principle before merging.

## Instructions

### Step 1: Resolve the ticket directory

1. Read the host repo's root `CLAUDE.md` (if present). Look for a declaration of the ticket directory. Recognized hints:
   - A line of the form `Tickets: <path>` or `Ticket directory: <path>`.
   - A section heading like `## Tickets` that names a path.
2. If none is found, default to `doc/tickets/` (with resolved tickets under `doc/tickets/resolved/`).
3. Let `<ticket-dir>` denote the resolved path for the rest of this skill.

### Step 2: Locate the target ticket

Parse `$ARGUMENTS`:

- **Number** (1–4 digits, e.g. `12` or `0012`): zero-pad to 4 digits and match `<ticket-dir>/NNNN-*.md`.
- **Path**: use directly, but reject anything outside `<ticket-dir>/` and anything under `<ticket-dir>/resolved/`.
- **Partial kebab phrase**: glob `<ticket-dir>/*<phrase>*.md`.
- **Empty**: list the frontmatter `title` + `status` of every `<ticket-dir>/*.md` (skipping `resolved/`) and ask the user which to grill.
- **Free-form prose with no match**: do **not** silently create a ticket. Tell the user to run `/ticket-create "<title>"` first, then re-invoke this skill on the resulting number. Stop.

Refuse to grill a ticket under `<ticket-dir>/resolved/` — closed work is closed.

### Step 3: Read the ticket schema

Read `<ticket-dir>/CLAUDE.md` — it defines the frontmatter schema, body structure, lifecycle, and section conventions used across the `ticket` plugin. If it does not exist, tell the user to run `/ticket-init` first and stop.

### Step 4: Read the ticket

Load the target ticket file. Note its frontmatter (especially `status` and `updated`) and which body sections already exist (`## Description`, `## Triage`, `## Implementation Notes`, `## Resolution`).

### Step 5: Grill

Interview the user **relentlessly** about every aspect of the plan implied by the ticket, until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, propose your recommended answer.

**Ask the questions one at a time, waiting for feedback on each question before continuing.**

If a question can be answered by exploring the codebase, explore the codebase instead of asking.

While grilling, apply these techniques:

- **Sharpen fuzzy language.** When the user uses a vague or overloaded term, propose a precise canonical one. *"You said 'request' — do you mean the inbound HTTP request, the queued job, or the downstream API call? Those are different things."*
- **Stress-test with concrete scenarios.** When relationships or boundaries are being discussed, invent specific edge-case scenarios that force the user to be precise about where the boundaries fall.
- **Cross-reference with code.** When the user states how something works, check whether the code agrees. If you find a contradiction, surface it immediately: *"Your code does X here, but you just said Y — which is right?"*

### Step 6: Capture decisions inline

As each decision crystallises, update the ticket file **right then** — do not batch updates until the end.

- **Append to / refine `## Implementation Notes`.** Create the section if it doesn't exist (insert it after `## Triage` if present, otherwise after `## Description`). Use the structure already documented for this section in `<ticket-dir>/CLAUDE.md` (typically: *plan, alternatives, decision points*).
- **Clarify `## Description` carefully** if the grilling reveals that the ticket's stated intent is itself ambiguous. Preserve the user's original phrasing where possible; do not silently rewrite intent.
- **Bump `updated:` in the frontmatter** to today's date (ISO `YYYY-MM-DD`).
- **Do not change `status`.** `in-progress` is the contract of `/ticket-fix`; grilling is planning.
- **Do not move the file.** It stays in `<ticket-dir>/`; `resolved/` belongs to `/ticket-fix`.

### Step 7: Wrap up

Print a short summary:

- Which ticket was grilled (number + title).
- How many decisions were recorded in `## Implementation Notes`.
- Any questions that remain open.
- Suggest the natural next step — `/ticket-triage` if the ticket has not yet been triaged, otherwise `/ticket-fix`.

## Notes

- This skill is read-only with respect to source code — it only writes inside `<ticket-dir>/`, and only to the single target ticket file.
- Never write outside `<ticket-dir>/`.
- Never set `status: in-progress` — that's `/ticket-fix`'s contract.
- Never move the file to `resolved/`.
- **Deliberate divergence from `grill-with-docs`:** the glossary (`CONTEXT.md`) and ADR (`docs/adr/`) layers from the upstream skill are *not* ported. This repo has no counterpart for them; the ticket file is the artifact. Future maintainers: don't try to "complete" the port by adding a glossary mode — it would conflict with the plugin's portability rule.
