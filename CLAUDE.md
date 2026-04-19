# hayamiz-agentkit

Personal collection of skills and plugins for coding agents (primarily Claude Code,
with room to grow to other harnesses). Distributed via [APM](https://github.com/apm-pkg/apm).

## Repository Layout

```
skills/                 Skill packages (one per directory, each with SKILL.md)
  commit-all/
  commit-session/
plugins/                Claude Code plugins (one per directory)
  gardener/             Repo-health audit plugin.
  ticket/               File-based ticket workflow (init / create / check / triage / fix).
apm.yml                 APM project manifest (this repo's own dependencies)
apm.lock.yaml           APM resolved versions
apm_modules/            APM install output (gitignored)
.claude/                Runtime state for the repo's own Claude Code sessions
  skills/               Deployed skills (gitignored — populated by `apm install`)
  settings.local.json   Local-only settings (gitignored)
.devcontainer/          Dev container config
```

- **`skills/`** holds standalone skills. Each is shipped as an APM package using
  the directory name as the package name (e.g. `skills/commit-session` →
  `hayamiz/hayamiz-agentkit/skills/commit-session`).
- **`plugins/`** holds Claude Code plugins. A plugin bundles its own skills,
  commands, hooks, and reference files in one directory. `plugins/gardener` is
  the current example.
- **The repo consumes its own packages**: `apm.yml` lists this repo's skills
  and plugins as APM dependencies so `apm install` deploys them into
  `.claude/skills/` for use in this working tree.

## When Adding or Editing Content

- **New skill**: create `skills/<name>/SKILL.md` with `name`, a trigger-style
  `description`, and a single-responsibility body. Add a matching entry to
  `apm.yml` under `dependencies.apm`.
- **New plugin**: create `plugins/<name>/` following Claude Code's plugin layout.
  Add the plugin root to `apm.yml` (e.g. `hayamiz/hayamiz-agentkit/plugins/<name>`).
- **Skill quality**: prefer progressive disclosure — keep `SKILL.md` focused and
  move reference material, scripts, or long checklists into sibling files.
  See `plugins/gardener/best-practices-checklist.md` §4 for the full rubric.

## Commands

- `apm install` — install/refresh dependencies into `apm_modules/` and
  `.claude/skills/`.
- `/commit-session` — commit only the files changed in the current session,
  grouped into semantically coherent commits.
- `/commit-all` — commit every dirty file, similarly grouped.
- `/ticket:init` / `/ticket:create` / `/ticket:check` / `/ticket:triage` /
  `/ticket:fix` — file-based ticket workflow (provided by the `ticket` plugin).
  See each skill's `SKILL.md` for details.
- `/gardener` — repo health audit. Reference checklists live in
  `plugins/gardener/*.md`.

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
- The repo was renamed from `hayamiz-skills` to `hayamiz-agentkit`. The local
  working directory may still be named `hayamiz-skills` — that's cosmetic and
  doesn't affect anything.
