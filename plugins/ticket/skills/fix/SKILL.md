---
name: fix
description: "Implement fixes for all tickets triaged as mechanically fixable. Delegates each fix to a subagent, runs project-declared verification, and marks tickets resolved. Does not commit — use /commit-session afterwards."
argument-hint: "[ticket-number]"
allowed-tools: Bash(*) Read Edit Write Glob Grep
---

# Ticket Fix

Implement fixes for open tickets that `/ticket:triage` has marked as mechanically fixable (no user decision needed). Each fix is delegated to a subagent to keep the main conversation context lean. This skill **does not commit** — after resolution, use `/commit-session` to commit the changes.

## Portability (maintainers, read this before editing)

These skills must remain project-agnostic. When updating this SKILL.md, do **not** introduce hardcoded references to specific languages, frameworks, test runners, build tools, file paths, or directory layouts (e.g., `go vet`, `npx playwright`, `pytest`, `doc/SPEC.md`, `e2e/tests/`, `server_test.go`). Project-specific knowledge belongs in the host repo's `CLAUDE.md` and the host repo's `<ticket-dir>/CLAUDE.md` — this skill **reads** that configuration at runtime, it does not embed it. If a new instruction would only make sense in one tech stack, rewrite it as a principle (e.g., "run the verification commands declared in `CLAUDE.md`") before merging.

## Instructions

### Step 1: Resolve the ticket directory and project conventions

1. Read the host repo's root `CLAUDE.md` (if present) for:
   - The ticket directory (e.g., `Tickets: <path>`). Default: `doc/tickets/`.
   - A spec / design document to keep in sync (e.g., `Spec: doc/SPEC.md`). Optional.
   - Verification commands (tests, linters, type checks) — typically under a `## Verification` or `## Testing` heading. Optional.
2. Read `<ticket-dir>/CLAUDE.md` for the ticket schema, lifecycle, and any declarations it adds (spec path, verification commands) that the root `CLAUDE.md` didn't set.

If a spec path is not declared anywhere, the spec-update step is skipped later.

If verification commands are not declared anywhere, ask the user **once** what to run (e.g., "How should I verify changes — what commands run the test suite, linter, or type-checker?"). Remember the answer for the rest of this invocation.

### Step 2: Collect candidates

List tickets in `<ticket-dir>/` that meet ALL of:

- `status: open` or `status: in-progress`.
- Has a `## Triage` section.
- Triage indicates `Mechanical fix: yes` and `Requires user decision: no`.

If `$ARGUMENTS` contains a ticket number, narrow the set to just that ticket (and check it meets the criteria above; if not, tell the user why and stop).

If open tickets exist but **none** have been triaged, tell the user to run `/ticket:triage` first and stop. Do not attempt to fix un-triaged tickets.

### Step 3: Dispatch subagents (one per ticket)

Sort candidates by priority (`critical` > `high` > `medium` > `low`), then by ticket number. Process in that order.

**Context discipline**: the parent (you) orchestrates only — reading tickets, dispatching subagents, verifying their output, and presenting the final summary. Do not read source code or perform fixes directly in the main conversation.

**Parallelism**: launch subagents in parallel when their tickets touch disjoint files. When two tickets touch the same files, run them sequentially so later subagents see the earlier fix.

**Subagent prompt requirements** (include every one of these, or the subagent cannot do its job):

1. The **full text** of the ticket file, pasted inline.
2. A pointer to read the host repo's root `CLAUDE.md` (and any project-specific guides it references) before making changes, so the subagent follows project conventions.
3. The spec path (if any), so the subagent knows what to keep in sync.
4. The verification commands (from Step 1) the subagent must run before declaring success.
5. The **steps** below (a–f), copied verbatim into the prompt.
6. Clear success criteria: "Report which files you changed, which tests you added, whether verification passed, and whether the ticket was moved to `resolved/`."

After each subagent completes, verify its output: inspect `git diff` or read the changed files to confirm the fix matches the ticket and the verification truly passed. Only then move to the next subagent.

#### Steps each subagent must perform

**a. Mark in progress.** Update the ticket file's `status` to `in-progress` and set `updated` to today's date.

**b. Implement the fix.** Make the minimal code changes the ticket requires. Follow the conventions in the host repo's `CLAUDE.md`. Do not refactor surrounding code or add unrelated improvements.

**c. Add or update tests.** This is required, not optional. Analyze every code path that was added or changed, and add tests that cover the new or modified behavior.

   **Principles** (language- and framework-agnostic):

   - **Coverage**: every new code path (new function, new branch, new endpoint, new user interaction) needs at least one test exercising it.
   - **Match the project**: follow the testing patterns already in the repository. Use the same test framework, directory layout, and naming conventions. If the repository has no tests in this area, **stop and ask the user** before inventing a new testing approach — don't introduce a framework the project doesn't use.
   - **Risk-weighted prioritization**:
     - *Must test*: security-sensitive changes (input sanitization, auth, path handling), error paths, core public behavior (new endpoints, new API contracts, new CLI flags).
     - *Should test*: user-facing interactions, state changes, boundary conditions (empty input, limits).
     - *Nice to have*: purely cosmetic changes.
   - **Security-sensitive changes must test all malicious-input variants** relevant to the surface (e.g., traversal sequences, injection payloads, oversized input) — not just the happy path.
   - **Bug fixes must include a regression test** that reproduces the original failure scenario and passes only with the fix in place.

**d. Verify.** Run the verification commands declared for this project (Step 1). All of them must pass. If verification fails after reasonable attempts to fix, do not force the change — see step (f).

**e. Update the spec (only if a spec path is declared AND the change is user-visible).** User-visible changes include new/altered endpoints, new CLI flags, changed defaults, altered response formats, new configuration options. Internal refactors, test-only changes, and comment tweaks do not require spec updates. Skip this step entirely if no spec path is declared.

**f. Resolve or bounce back.**

- If steps (b)–(e) succeeded: set the ticket's `status` to `resolved`, update `updated` to today, fill in a `## Resolution` section summarizing what changed (including tests added and spec updates), then move the file to `<ticket-dir>/resolved/`.
- If the fix turned out to need user input, or verification kept failing: **do not force the fix**. Revert any changes the subagent made to source files (leave the ticket file untouched), update the ticket's `## Triage` section to set `Mechanical fix: no` and `Requires user decision: yes` with a note explaining why, keep `status: open`, and return a failure report to the parent.

### Step 4: Present the summary

After all candidates are processed, show:

#### Fixed

| Ticket | Title | What was done |
|--------|-------|---------------|
| #NNNN  | ...   | ...           |

#### Could not fix (now needs user decision)

| Ticket | Title | Reason |
|--------|-------|--------|
| #NNNN  | ...   | ...    |

#### Skipped (already required user decision)

| Ticket | Title | Decision needed |
|--------|-------|-----------------|
| #NNNN  | ...   | ...             |

End with a pointer to run `/commit-session` (or the project's preferred commit flow) to commit the resolved fixes.

## Notes

- **Do not commit.** This skill never runs `git commit`, `git add`, or equivalent. It leaves the working tree dirty with resolved tickets moved and source/test edits staged in the filesystem, ready for the user (or `/commit-session`) to commit.
- **Do not skip user-decision tickets.** Tickets marked `Requires user decision: yes` in triage must never be auto-fixed — list them under "Skipped" and move on.
- **Keep each fix focused.** No refactoring of surrounding code, no unrelated improvements, no drive-by changes. If the fix organically wants to grow, that's a signal it's not mechanical; bounce it back per step (f).
- **Per-ticket subagent isolation is non-negotiable** — this is how the skill stays usable on projects with many tickets without blowing up the parent context.
