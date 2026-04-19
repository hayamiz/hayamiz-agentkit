---
name: ticket-triage
description: "Triage all open tickets in the project's ticket directory — classify by complexity, whether a mechanical fix is possible, and whether the fix needs a user decision."
argument-hint: "[ticket-number]"
allowed-tools: Bash(*) Read Edit Glob Grep
---

# Ticket Triage

Analyze all open tickets in the project's ticket directory and classify each by complexity, feasibility of a mechanical fix, and whether user input is required. Results are written back into each ticket's `## Triage` section and summarized for the user.

## Portability (maintainers, read this before editing)

These skills must remain project-agnostic. When updating this SKILL.md, do **not** introduce hardcoded references to specific languages, frameworks, test runners, build tools, file paths, or directory layouts. Project-specific knowledge belongs in the host repo's `CLAUDE.md` and the host repo's `<ticket-dir>/CLAUDE.md` — these skills **read** that configuration at runtime, they do not embed it. If a new instruction would only make sense in one tech stack, rewrite it as a principle before merging.

## Instructions

### Step 1: Resolve the ticket directory

1. Read the host repo's root `CLAUDE.md` (if present) for a declaration of the ticket directory. Default: `doc/tickets/`.
2. Read `<ticket-dir>/CLAUDE.md` for the triage-section format and status vocabulary.

If `<ticket-dir>/CLAUDE.md` is missing, instruct the user to run `/ticket-create` first (which bootstraps it) and stop.

### Step 2: Collect tickets to triage

- List `*.md` files directly in `<ticket-dir>/` that match `NNNN-*.md` (exclude `CLAUDE.md` and anything under `resolved/`).
- Filter to tickets whose `status` is `open` or `in-progress`.
- If `$ARGUMENTS` contains a single ticket number (e.g., `0007`), narrow the set to just that ticket.
- If the filtered set is empty, report it and stop.

### Step 3: Identify project context sources

Before dispatching subagents, identify what the host project considers authoritative context. From the host repo's root `CLAUDE.md`, look for hints like:

- A spec or design doc path (e.g., `Spec: doc/SPEC.md`, `Design: ARCHITECTURE.md`).
- A conventions file.
- Existing test directories.

If none are declared, subagents will fall back to reading `CLAUDE.md`, the repository README, and source files they deem relevant. Do **not** assume any particular file exists.

### Step 4: Triage each ticket via subagents

Dispatch one `Explore` subagent per ticket, in parallel where possible. The subagent prompt MUST include:

1. The **full text** of the ticket file (copy it into the prompt — the subagent has no conversation history).
2. The paths of project context sources identified in Step 3.
3. The triage rubric (copied verbatim below).
4. An instruction to return a structured analysis.

#### Triage rubric (to include in every subagent prompt)

Assess the ticket against these three axes:

- **Complexity**: `low` / `medium` / `high` — based on the number of files affected, scope of changes, and potential for regressions elsewhere.
- **Mechanical fix**: `yes` / `no` — can this be fixed unambiguously from the spec, existing tests, and repository conventions, without design choices? If multiple reasonable approaches exist and they would produce meaningfully different behavior, answer `no`.
- **Requires user decision**: `yes` / `no` — does the fix need input from the user on behavior, UX, architecture, or trade-offs?

**If `Mechanical fix` is `no`**, before concluding the triage the subagent must:

1. Research the relevant source code, specs, and dependencies in depth.
2. Draft a concrete implementation plan: which files to change, what approach to take, what alternatives exist, and what the trade-offs of each alternative are.
3. Update the ticket file's `## Implementation Notes` section (create it if missing) with that plan, open questions, and specific decision points for the user.
4. Only then decide `Requires user decision`: some non-mechanical tickets become mechanical once the plan is fleshed out.

The subagent must return:

- `complexity`, `mechanical_fix`, `requires_user_decision` fields (values as above).
- A short rationale (2–4 sentences).
- A one-line summary usable in the final table.
- (If applicable) the text appended to `## Implementation Notes`.

### Step 5: Update each ticket file

For each triaged ticket, append or replace the `## Triage` section using the format defined in `<ticket-dir>/CLAUDE.md`. At minimum, the section must contain:

```
## Triage

- Complexity: <low|medium|high>
- Mechanical fix: <yes|no>
- Requires user decision: <yes|no>
- Notes: <short rationale>
```

Also update the frontmatter `updated` field to today's date. If the subagent produced `## Implementation Notes`, apply that too.

### Step 6: Present summary

Show the user two tables:

#### Mechanically fixable (no user decision needed)

| Ticket | Title | Priority | Complexity | Summary |
|--------|-------|----------|------------|---------|
| #NNNN  | ...   | ...      | ...        | ...     |

#### Requires user decision

| Ticket | Title | Priority | Complexity | Decision needed |
|--------|-------|----------|------------|-----------------|
| #NNNN  | ...   | ...      | ...        | ...             |

End with a one-line recommendation, e.g. "Run `/ticket-fix` to implement the N mechanically fixable tickets."

## Notes

- If a ticket already has a `## Triage` section, re-analyze it — the repository may have changed since the last triage. Overwrite the old section.
- Run subagents in parallel for efficiency, but if triage takes longer than expected on a batch, it's fine to sequence them.
- Triage is non-destructive with respect to source code: subagents may read freely but must not edit source files. The only files this skill writes are ticket Markdown files inside `<ticket-dir>/`.
- If there are no non-resolved tickets, report `No open tickets to triage.` and stop.
