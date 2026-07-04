# hayamiz-agentkit

Personal collection of skills and plugins for coding agents (primarily Claude Code,
with room to grow to other harnesses).

Two distribution channels:

- **Plugins** (`plugins/`) — shipped through the Claude Code plugin marketplace
  defined in `.claude-plugin/marketplace.json`. Installed via `/plugin install
  <name>@hayamiz-agentkit`. Claude Code slash-command names are *not*
  auto-namespaced by plugin, so plugin-owned skills use a manual `<plugin>-`
  prefix on the skill directory (e.g. `ticket-fix/` → `/ticket-fix`).
- **Skills** (`skills/`) — shipped through [APM](https://github.com/apm-pkg/apm).
  Installed via `apm install hayamiz/hayamiz-agentkit/skills/<name>`, deployed
  to `.claude/skills/<name>/` with no namespace prefix. (This repo currently
  ships no standalone skills of its own — the commit helpers are now the
  `commit` plugin; see below.)

## Repository Layout

```
skills/                 Standalone skills, shipped via APM (currently none — see plugins/commit)
plugins/                Claude Code plugins, shipped via marketplace.json
  gardener/             Repo-health audit plugin.
  ticket/               File-based ticket workflow (init / create / grill / check / triage / fix).
  commit/               Session-aware git commit helpers (/commit-session, /commit-all).
.claude-plugin/
  marketplace.json      Marketplace manifest listing plugins/* for Claude Code.
apm.yml                 APM project manifest (this repo's own dependencies — skills only)
apm.lock.yaml           APM resolved versions
apm_modules/            APM install output (gitignored)
.claude/                Runtime state for the repo's own Claude Code sessions
  skills/               Deployed skills (gitignored — populated by `apm install`)
  settings.local.json   Local-only settings (gitignored)
.devcontainer/          Dev container config
```

- **APM dependencies**: the repo no longer dogfoods its own skills via APM —
  `apm.yml` now lists only the external `anthropics/skills/skills/skill-creator`,
  which `apm install` deploys into `.claude/skills/`. The commit helpers that
  used to be dogfooded this way are now the `commit` plugin, loaded through the
  Claude Code plugin marketplace, not APM. Plugins are always loaded via the
  marketplace, not APM.

## When Adding or Editing Content

- **New skill** (goes to `skills/`): create `skills/<name>/SKILL.md` with
  `name`, a trigger-style `description`, and a single-responsibility body. Add
  a matching entry to `apm.yml` under `dependencies.apm`.
- **New plugin** (goes to `plugins/`): create `plugins/<name>/` following
  Claude Code's plugin layout (include `.claude-plugin/plugin.json`). Add an
  entry to `.claude-plugin/marketplace.json` under `plugins`.
- **Skill quality**: prefer progressive disclosure — keep `SKILL.md` focused and
  move reference material, scripts, or long checklists into sibling files.
  See `plugins/gardener/best-practices-checklist.md` §4 for the full rubric.

## Commands

- `apm install` — install/refresh APM skills into `apm_modules/` and
  `.claude/skills/`.
- `/plugin marketplace add hayamiz/hayamiz-agentkit` — register the marketplace
  for plugins. Then `/plugin install ticket@hayamiz-agentkit`,
  `/plugin install gardener@hayamiz-agentkit`,
  `/plugin install commit@hayamiz-agentkit`.
- `/commit-session` — commit only the files changed in the current session,
  grouped into semantically coherent commits (provided by the `commit` plugin).
- `/commit-all` — commit every dirty file, similarly grouped (provided by the
  `commit` plugin).
- `/ticket-init` / `/ticket-create` / `/grill-with-ticket` / `/ticket-check` /
  `/ticket-triage` / `/ticket-fix` — file-based ticket workflow (provided by the
  `ticket` plugin). See each skill's `SKILL.md` for details.
- `/gardener` — repo health audit. Reference checklists live in
  `plugins/gardener/*.md`.

## Tickets

Ticket directory: doc/tickets/

File-based work-item tickets for this project live under `doc/tickets/`.
Managed by the `ticket` plugin (`/ticket-create`, `/ticket-check`,
`/ticket-triage`, `/ticket-fix`). See `doc/tickets/CLAUDE.md` for the
ticket schema and lifecycle.

## Conventions

- **Commit style**: Conventional Commits prefixes (`feat`, `fix`, `chore`,
  `refactor`, `docs`, `test`). See recent `git log` for examples.
- **No mass `git add`**: skills that commit (`commit-session`, `commit-all`)
  stage files explicitly, never with `-A` or `.`.
- **Skill packaging**: one skill per directory at the top of `skills/`. Do not
  nest skills under other skills.
- **Plugin packaging**: plugin-owned skills live inside the plugin (e.g.
  `plugins/gardener/skills/`), not in top-level `skills/`.

## Gotchas

- `.claude/skills/` is **gitignored** — it's populated by `apm install` from
  `apm.yml`. Editing files there will be overwritten on the next install; edit
  the source in `skills/<name>/` or `plugins/<name>/skills/<name>/` instead.
- `apm.lock.yaml` is committed. When you rename or move a skill directory,
  update both `apm.yml` (dependency path) and `apm.lock.yaml` (`virtual_path`)
  or re-run `apm install` to regenerate the lockfile.
- **Do not add `plugins/*` to `apm.yml`.** Plugins are distributed through
  `marketplace.json`, not APM. APM installs plugin contents flat into
  `.claude/skills/`, which loses the `<plugin>-` directory prefix and can
  collide with built-in skill names (e.g. plugin `init` vs built-in `/init`).

## Coding Guidelines

### Think Before Coding
State assumptions explicitly before implementation. Surface multiple interpretations rather than choosing silently. Highlight simpler alternatives and push back when appropriate. Stop and ask if anything remains unclear.

### Simplicity First
Write only what was requested — no extra features, unnecessary abstractions, or error handling for edge cases that won't occur. Rewrite if you can reduce 200 lines to 50.

### Surgical Changes
When editing existing code, match its style without improving unrelated areas. Remove imports and variables that your changes orphaned, but mention (don't delete) pre-existing dead code.

### Goal-Driven Execution
Transform tasks into verifiable goals with clear success criteria. For multi-step work, outline the plan with verification checkpoints. Strong criteria enable independent iteration; vague ones require constant clarification.
