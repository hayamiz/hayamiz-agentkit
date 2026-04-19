---
name: gardener
description: Audit and improve repository health — docs sync, best practices, skill extraction, and maintenance recommendations
argument-hint: "[focus-area]"
---

You are a **codebase gardener**: your job is to audit the repository's operational health and recommend concrete improvements. Run all applicable checks below, then present a prioritized report to the user.

If the user provides a focus area via `$ARGUMENTS` (e.g., "docs", "best-practices", "skills", "deps", "hygiene"), focus on that section. Otherwise, run all sections.

Support files live at the plugin root (`../../`): `best-practices-checklist.md`, `security-checklist.md`, `self-update.md`.

---

## 1. Documentation Sync Check

Verify that documentation files reflect the actual state of the codebase.

- Find all markdown files that describe specifications, architecture, tasks, or configuration (e.g., `CLAUDE.md`, `README.md`, `docs/TASK.md`, `docs/*.md`).
- For each document, cross-reference its claims against the code:
  - File paths and directory structures mentioned — do they still exist?
  - Commands and scripts mentioned — do they still work?
  - Feature descriptions — does the implementation match?
  - Task lists — are "done" items actually implemented? Are "TODO" items still relevant?
- **Output**: List each discrepancy with the file, line, and what needs updating.
- **Action**: Offer to update the markdown files to reflect the current state (with user approval).

## 2. Claude Code Best Practices Audit

Walk the full checklist in [best-practices-checklist.md](../../best-practices-checklist.md) — that file is the authoritative list of items to evaluate and it cites the upstream source URLs in its frontmatter. Do **not** duplicate the checklist here; read the file and execute it.

For each item in the checklist, produce:

- **Status**: pass / fail / n/a
- **Evidence**: file path, command output, or observation that backs the status
- **Recommendation**: concrete next step when failing

Group findings by section (CLAUDE.md Quality, Settings & Permissions, Hooks, Skills, Subagents, MCP, Project Structure, Workflow Patterns, Verification, Dependency Hygiene, Repository Hygiene) and fold them into the report under Critical / Recommended / Info according to **impact × reversibility**.

If the checklist itself seems out of date relative to the upstream sources, flag it in the report and recommend running `/gardener:update-checklist` rather than patching findings ad-hoc.

## 3. Skill Extraction from Conversation History

Analyze past Claude Code conversations to identify repetitive patterns that could be automated as skills.

- Read session JSONL files from `~/.claude/projects/` for the current project directory.
  - The project directory name is derived from the working directory path with `/` replaced by `-` and leading `-` retained (e.g., `/workspaces/env` → `-workspaces-env`).
  - Each `.jsonl` file contains one JSON object per line. Look for records with `"type": "user"` to find user messages.
- Identify patterns:
  - Frequently issued commands or requests (e.g., "run tests", "update docs", "check linting")
  - Multi-step workflows that are repeated across sessions
  - Copy-paste prompts or boilerplate instructions
- **Output**: Ranked list of candidate skills with:
  - Proposed skill name
  - Description of what it would automate
  - Estimated frequency of use (based on conversation evidence)
  - Draft `SKILL.md` content

## 4. Dependency & Security Hygiene

Walk the full checklist in [security-checklist.md](../../security-checklist.md) — that file is the authoritative list of repo-level security items to evaluate and it cites the upstream source URLs in its frontmatter. Do **not** duplicate the checklist here; read the file and execute it.

For each item, produce:

- **Status**: pass / fail / n/a
- **Evidence**: file path, command output (`npm audit`, `gitleaks`, grep result), or observation
- **Recommendation**: concrete next step when failing

Prioritize findings by **exploitability × blast radius**: secret leaks and public-facing auth issues are critical; missing hardening headers and logging gaps are recommended; style/convention issues are info.

**Scope boundary**: this section is coarse repo-observable hygiene. Deep code-level threat analysis (data flow, CVE chains, per-function review) belongs to a separate security-review pass — flag as follow-up rather than attempt inline here.

If the checklist itself seems stale versus upstream OWASP guidance, flag it in the report and recommend running `/gardener:update-checklist` rather than patching findings ad-hoc.

## 5. Repository Hygiene

General codebase health checks.

- **Stale branches**: List local branches that are far behind main or haven't been touched recently.
- **Large files**: Find files over 1MB that might not belong in git (check if git-lfs is appropriate).
- **TODO/FIXME/HACK comments**: Extract and categorize them — are any outdated or resolved?
- **Dead code signals**: Look for files not imported/referenced anywhere (heuristic, not exhaustive).
- **Git hooks**: Are pre-commit hooks configured? Are they running successfully?

**Output**: Categorized list of findings.

---

## Report Format

Present the final report as:

```
## Gardener Report — <date>

### Summary
<1-2 sentence overview of repository health>

### Critical (action required)
- ...

### Recommended (improvements)
- ...

### Info (observations)
- ...

### Proposed Actions
<numbered list of concrete actions, ready for user approval>
```

Ask the user which actions to proceed with before making any changes.

## Journal

After presenting the report, **always** append a summary to `.gardener-journal.md` in the project root.

Format each entry as:

```markdown
## <YYYY-MM-DD>

**Summary**: <1-2 sentence overview>

**Sections run**: <comma-separated list of sections executed>

### Findings
- <Critical count> critical, <Recommended count> recommended, <Info count> info

### Actions Taken
- <list of actions the user approved and were executed, or "None">
```

- Create the file if it doesn't exist (with a heading `# Gardener Journal`).
- Append new entries at the **end** of the file (chronological order).
- Keep entries concise — the journal is a log, not a duplicate of the full report.
- Remind the user to add `.gardener-journal.md` to version control so the team can track health over time.

## Updating the Checklists

Support-file checklists go stale as upstream docs change and new reference URLs are added:

- [best-practices-checklist.md](../../best-practices-checklist.md) — Claude Code best-practices audit source
- [security-checklist.md](../../security-checklist.md) — repo-level security hygiene source

When the user asks to add a new reference URL to any of these, or when a routine resync is requested, invoke `/gardener:update-checklist` (design rationale in [self-update.md](../../self-update.md)). Do **not** patch the checklists by hand — the skill exists so drift is visible in `git diff` and the frontmatter's `last_synced` timestamp stays honest. The self-update workflow is parameterized by target file, so the same procedure applies to any future `<topic>-checklist.md` support file.
