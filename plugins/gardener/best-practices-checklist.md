---
name: Claude Code Best Practices Checklist
description: Comprehensive audit checklist derived from official Claude Code best practices and community references
version: 1
last_synced: 2026-04-19
sources:
  - url: https://code.claude.com/docs/en/best-practices
    label: Anthropic — Best Practices for Claude Code
    last_fetched: 2026-04-19
  - url: https://github.com/shanraisshan/claude-code-best-practice
    label: shanraisshan/claude-code-best-practice (community checklist)
    last_fetched: 2026-04-19
---

# Claude Code Best Practices Checklist

This is the authoritative audit checklist for the `gardener` skill's **Best Practices Audit** section. Each item should be evaluated as **pass / fail / n/a**, with a short rationale and (where possible) a file/line pointer.

When a check refers to an external concept (hooks, skills, subagents, MCP, plugins), cite the relevant source URL from the frontmatter so the user can follow up.

---

## 1. CLAUDE.md Quality

Context: CLAUDE.md is loaded at the start of every session, so bloat is expensive. Only include what can't be inferred from the code.

- [ ] **CLAUDE.md exists** at the project root, and optionally at `~/.claude/CLAUDE.md` for personal overrides.
- [ ] **Concise** — under ~200 lines per file; ruthlessly pruned. For each line ask: *"Would removing this cause Claude to make mistakes?"*
- [ ] **Covers the essentials**: project overview, build/test/lint commands, code style rules, architecture notes, repository etiquette, common gotchas.
- [ ] **Excludes the obvious**: no standard language conventions, no file-by-file descriptions, no self-evident practices, no frequently changing info.
- [ ] **Provides verification criteria** — test commands, linter commands, expected outputs — so Claude can self-check.
- [ ] **Uses emphasis judiciously** (`IMPORTANT`, `YOU MUST`) only where adherence has been a problem.
- [ ] **Uses `@path` imports** for shared fragments rather than duplicating content.
- [ ] **Personal overrides** live in `./CLAUDE.local.md` (gitignored) or `~/.claude/CLAUDE.md`, not in the shared file.
- [ ] **Hierarchy is intentional** in monorepos — ancestor and descendant CLAUDE.md files are loaded together; avoid contradictions.
- [ ] **Checked into git** so the team can contribute (except `CLAUDE.local.md`).

## 2. Settings & Permissions

Context: repeated permission prompts lead to rubber-stamping. Scope permissions so routine work flows and risky actions still get reviewed.

- [ ] **`.claude/settings.json` exists** for shared, deterministic behavior (attribution, permissions, model selection).
- [ ] **Permissions are scoped** — allowlist specific tools (`Bash(npm run *)`, `Bash(git commit *)`) rather than broad wildcards or `--dangerously-skip-permissions`.
- [ ] **`settings.local.json`** is used for environment-specific overrides and is gitignored.
- [ ] **Auto mode** (classifier-gated) is preferred over `--dangerously-skip-permissions` when fewer prompts are needed.
- [ ] **Sandboxing** (`/sandbox`) is considered for workflows that touch the filesystem or network heavily.
- [ ] **No secrets** (API keys, tokens) are committed to `settings.json` — use env vars or `settings.local.json`.
- [ ] **Model selection** is appropriate for the task profile (Opus for planning/hard problems, Sonnet for routine execution).

## 3. Hooks

Context: hooks are deterministic — they guarantee an action happens, unlike CLAUDE.md instructions which are advisory.

- [ ] **PostToolUse hooks** auto-format or lint after edits to prevent CI failures (e.g., prettier, eslint, `go fmt`).
- [ ] **PreToolUse hooks** block writes to sensitive paths (migrations, production configs, secret files).
- [ ] **Stop hooks** nudge verification at turn boundaries (tests, type-check) where applicable.
- [ ] **Notification hooks** surface important events (long-running job done, review ready).
- [ ] **Hooks are documented** — each hook's purpose is clear to a reader who didn't configure it.
- [ ] **No hooks silently suppress errors** — hook output should be visible when failures occur.

## 4. Skills

Context: skills extend Claude's knowledge on-demand without bloating every conversation.

- [ ] **`.claude/skills/`** (or top-level skill directories if this is a skills repo) exists for repeatable workflows and domain knowledge.
- [ ] **Each `SKILL.md`** has a `name`, a `description` written as a **trigger** ("when should I fire?"), and a body focused on a single responsibility.
- [ ] **Progressive disclosure** — large skills split reference material into sibling files (`references/`, `scripts/`, `examples/`) and link to them rather than inlining everything.
- [ ] **`disable-model-invocation: true`** is set for skills that should only run when explicitly invoked (e.g., side-effectful workflows).
- [ ] **No railroading** — skills describe goals and constraints, not rigid step-by-step scripts, unless determinism is the point.
- [ ] **Gotchas sections** capture failure modes learned over time.
- [ ] **Skills are discoverable** — naming is intentional and overlapping skills are de-duplicated.

## 5. Subagents

Context: subagents run in their own context window. Use them to keep the main conversation small and to get independent review.

- [ ] **`.claude/agents/`** defines specialized subagents for isolated tasks (security review, code review, exploration).
- [ ] **Each subagent** has scoped `tools:` (principle of least privilege) and a clear role in its system prompt.
- [ ] **Model selection** per subagent matches the task (e.g., Opus for security review, Sonnet for routine exploration).
- [ ] **Investigation-heavy work** (broad greps, file tours) is delegated to subagents to protect main context.
- [ ] **Writer/Reviewer pattern** or similar multi-agent workflows are documented if used.
- [ ] **`isolation: "worktree"`** is considered for subagents that make changes, to keep experiments isolated.

## 6. MCP & External Tools

Context: MCP and CLI tools are the most context-efficient way to interact with external services.

- [ ] **`.mcp.json`** (or MCP config in `settings.json`) exists if the project uses external services (databases, APIs, issue trackers, design tools).
- [ ] **MCP servers** are scoped to the project — avoid loading global servers that aren't used here.
- [ ] **CLI tools are preferred** over raw API calls where available (`gh`, `aws`, `gcloud`, `sentry-cli`, `linear`, etc.) — document them in CLAUDE.md so Claude knows to reach for them.
- [ ] **Credentials for MCP/CLI** are stored outside the repo (env, keychain, auth flows) — never committed.

## 7. Project Structure

- [ ] **`.claude/`** directory exists and contains the relevant subdirectories: `skills/`, `agents/`, `commands/`, `hooks/` (as applicable).
- [ ] **`.gitignore`** covers Claude Code runtime files: `.claude/settings.local.json`, `CLAUDE.local.md`, `.gardener-journal.md` (if personal), local logs.
- [ ] **`/` slash commands** exist for workflows run multiple times a day (checked into git under `.claude/commands/`).
- [ ] **Plugins** are documented if the project depends on any — note which ones and why.
- [ ] **Task tracking** uses conventions the team agrees on (e.g., `~/.claude/tasks/`, GitHub issues, Linear) rather than ad-hoc notes.

## 8. Workflow Patterns

Context: the recommended loop is **Explore → Plan → Implement → Commit**, with verification at every stage.

- [ ] **Plan Mode** is used (or documented as the convention) for non-trivial multi-file changes.
- [ ] **Verification is embedded** in typical prompts — tests, linters, screenshots, example outputs.
- [ ] **Subagents for research** are the convention when scoping investigations (instead of letting main context absorb everything).
- [ ] **Context management** is practiced — `/clear` between unrelated tasks, `/compact` with hints before limits, `/rewind` to back out of failed approaches.
- [ ] **Non-interactive mode** (`claude -p`) is leveraged where applicable (CI, pre-commit, batch migrations).
- [ ] **Small focused PRs** are the norm (p50 ~118 lines), with squash-merges for linear history.
- [ ] **Course-correction is quick** — after two failed corrections, the convention is to `/clear` and restart with a better prompt.

## 9. Verification & Quality Gates

- [ ] **Tests exist** and are runnable with a single documented command.
- [ ] **Linter/formatter** are configured and runnable (and wired to a hook where appropriate).
- [ ] **Type check** (if applicable) is runnable and fast enough to invoke routinely.
- [ ] **CI** runs the same checks locally available — no "green locally, red in CI" drift.
- [ ] **UI verification** path exists for frontend changes (screenshot diff, Playwright, Claude in Chrome, or manual steps documented).

## 10. Dependency & Security Hygiene

(Operational checks — overlap with the `security-review` skill, but summarized here for the gardener pass.)

- [ ] **Dependency manifests** (`package.json`, `go.mod`, `pyproject.toml`, `requirements.txt`, `Cargo.toml`, etc.) are present where expected.
- [ ] **Lockfiles are committed** and in sync with manifests.
- [ ] **Vulnerability scan** (`npm audit`, `pip audit`, `govulncheck`, `cargo audit`) is run and findings triaged.
- [ ] **No credential files** (`.env`, `credentials.json`, private keys) are committed. `.gitignore` covers common sensitive paths.
- [ ] **Outdated dependencies** are tracked — major version lag is intentional, not abandoned.

## 11. Repository Hygiene

- [ ] **Branches**: stale branches are pruned; long-lived branches have an owner.
- [ ] **Large files**: anything >1MB in git is intentional (consider git-lfs).
- [ ] **TODO/FIXME/HACK**: categorized; stale ones resolved or deleted.
- [ ] **Dead code**: files not imported or referenced are flagged for review.
- [ ] **Pre-commit hooks**: configured and succeeding locally.

---

## How to Use This Checklist

1. Cite this file from `SKILL.md`'s Best Practices section — do not duplicate its content.
2. When running the audit, walk each section top-to-bottom. For each item, produce:
   - **Status**: pass / fail / n/a
   - **Evidence**: a file path, command output, or observation
   - **Recommendation**: concrete next step if not passing
3. Prioritize findings in the final report by **impact × reversibility**: failing verification gates and secret leaks are critical; style and naming are info-level.
4. When the sources in the frontmatter are updated (new URLs added, upstream docs change), run the **gardener self-update** workflow to resync.

---

## Notes on Drift

- Upstream docs change. Treat any item here that contradicts a fresh fetch of the source URLs as **stale** and update this file.
- Community sources (e.g., shanraisshan's checklist) capture field experience that may not yet be official. Flag such items with "(community)" in the recommendation so the user can weigh them accordingly.
- Revision history lives in `git log` for this file — don't maintain a changelog here.
