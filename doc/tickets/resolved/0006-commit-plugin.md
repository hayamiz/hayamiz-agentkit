---
title: Consolidate commit-session and commit-all into a commit plugin
type: refactor
priority: medium
status: resolved
created: 2026-07-04
updated: 2026-07-04
---

## Description

`commit-session` and `commit-all` currently live as two standalone skills under
`skills/`, shipped through APM (listed in `apm.yml` / `apm.lock.yaml` and
deployed into `.claude/skills/` by `apm install`). This ticket unifies their
distribution: bundle both into a single Claude Code plugin, `commit`,
installable through the plugin marketplace (`/plugin install
commit@hayamiz-agentkit`) rather than APM.

Motivation: the repo already distributes `gardener` and `ticket` as
marketplace plugins. Moving the commit skills to the same channel removes the
split where a user must add both the marketplace *and* run `apm install` to get
the full toolkit — they become installable through one framework.

### Naming decision (settled)

The plugin is named **`commit`**, and the two skill directories keep their
existing names **`commit-session/`** and **`commit-all/`**. Because the plugin
is named `commit`, the repo's `<plugin>-` skill-prefix convention (root
`CLAUDE.md`) is already satisfied by the existing directory names, so the
slash-commands stay `/commit-session` and `/commit-all` (fully qualified
`commit:commit-session` / `commit:commit-all`) — no command renames, no user
churn. This mirrors how the `ticket` plugin owns `ticket-*` skills.

### Scope of the migration

1. **Create the plugin skeleton** — `plugins/commit/` following the Claude
   Code plugin layout (`.claude-plugin/plugin.json` with `name: "commit"`,
   `description`, `version`, `author`, mirroring `plugins/gardener` /
   `plugins/ticket`).
2. **Move the two skills** — relocate `skills/commit-session/` and
   `skills/commit-all/` into `plugins/commit/skills/` (directory names
   unchanged). The SKILL.md bodies themselves should not need behavioral
   changes.
3. **Register in the marketplace** — add a `commit` entry to
   `.claude-plugin/marketplace.json` under `plugins`, pointing at
   `./plugins/commit`.
4. **Drop the APM dependencies** — remove the
   `hayamiz/hayamiz-agentkit/skills/commit-all` and `.../commit-session`
   entries from `apm.yml`, and remove their entries from `apm.lock.yaml`
   (or re-run `apm install` to regenerate the lockfile).
5. **Update the docs** — reconcile every place that describes the current
   layout:
   - Root `CLAUDE.md`: the "Two distribution channels" intro, the
     "Repository Layout" tree (`skills/` no longer lists `commit-*`; add
     `plugins/commit/`), the "The repo consumes its own APM skills" note (it
     currently claims `apm.yml` lists `commit-*`), and the "Commands" list.
   - `README.md`: directory-structure listing and any APM `apm install
     hayamiz/hayamiz-agentkit/skills/commit-*` install examples.
   - `skills/CLAUDE.md`: if `skills/` ends up empty of real skills, note that.
   - `plugins/gardener/best-practices-checklist.md` if it references the
     commit skills' location (verify during the fix).
   - **Not a change:** `/commit-session` command references inside the `ticket`
     plugin (`plugins/ticket/CLAUDE.md`, `ticket-fix`, `ticket-lint`) stay as-is
     — the command name is unchanged, so those invocations keep working.

### Deliverable

- `plugins/commit/` created with a valid `plugin.json` (`name: "commit"`) and
  both skills moved in.
- `.claude-plugin/marketplace.json` lists `commit`.
- `apm.yml` and `apm.lock.yaml` no longer reference the two commit skills.
- Root `CLAUDE.md` (and any other doc naming the old layout) updated.

### Acceptance

- `/plugin install commit@hayamiz-agentkit` would install both commit skills
  (structurally correct plugin layout; not necessarily live-tested).
- Repo `## Verification` passes (`bash -n` over `*.sh`, JSON validity over
  `*plugin.json` / `*marketplace.json`, ticket lint).
- No dangling references to `skills/commit-session` or `skills/commit-all` in
  `apm.yml`, `apm.lock.yaml`, or documentation.

## Triage

- Complexity: medium
- Mechanical fix: yes
- Requires user decision: no
- Affected files: ~11 (4 config: new `plugins/commit/.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json`, `apm.yml`, `apm.lock.yaml`; 2 skill dirs
  moved: `skills/commit-session/`, `skills/commit-all/` → `plugins/commit/skills/`;
  ~5 docs: root `CLAUDE.md`, `README.md`, `skills/CLAUDE.md`, and any gardener/ticket
  doc that names the old layout)
- Fix strategy: worktree
- Notes: Unambiguous now that the naming decision is settled (plugin `commit`,
  skills keep `commit-session`/`commit-all`, commands unchanged) — no open design
  choices, so mechanical. Worktree over in-place because it spans directory moves
  plus several config/doc edits (substance dominates file count). Concrete gotchas
  surfaced in triage: (a) `apm.lock.yaml` has 3 entries — remove only the two
  `commit-*` blocks, keep `skill-creator`; (b) both SKILL.md bodies are
  self-contained (no cross-skill paths/scripts) so they move verbatim; (c) the new
  `plugin.json` needs a `version` (e.g. `0.1.0`); (d) `README.md` also lists the
  old layout / APM install examples and must be updated; (e) `/commit-session`
  command references inside the `ticket` plugin need NO change — the command name
  is preserved. Verify with the repo `## Verification` block (bash -n, JSON
  validity, ticket lint).

## Resolution

Migrated `commit-session` / `commit-all` from standalone APM skills to a single
marketplace plugin, `commit`. Commands are unchanged (`/commit-session`,
`/commit-all`).

Changes (commit `21ca110`):

- **New plugin skeleton**: `plugins/commit/.claude-plugin/plugin.json`
  (`name: "commit"`, `version: "0.1.0"`, author Yuto Hayamizu, description
  covering both helpers), mirroring `plugins/gardener` / `plugins/ticket`.
- **Skills moved verbatim** with `git mv` (recorded as 100%-similarity renames):
  `skills/commit-session` → `plugins/commit/skills/commit-session` and
  `skills/commit-all` → `plugins/commit/skills/commit-all`. SKILL.md bodies
  unchanged; the `/commit-all` cross-reference inside `commit-session` still
  resolves because the command name is preserved.
- **Marketplace**: added the `commit` entry (`source: "./plugins/commit"`) to
  `.claude-plugin/marketplace.json`, keeping gardener/ticket.
- **APM dropped**: removed the two `commit-*` dependency lines from `apm.yml`
  and their two `virtual_path` blocks from `apm.lock.yaml`; kept
  `skill-creator` in both.
- **Docs reconciled**: root `CLAUDE.md` (distribution-channels intro, layout
  tree, the former "consumes its own APM skills" note reworded — the repo no
  longer dogfoods its own skills via APM; `apm.yml` now lists only the external
  `skill-creator` — and the Commands section, with a
  `/plugin install commit@hayamiz-agentkit` line); `README.md` (layout listing,
  plugin install list + post-install command list, and the Skills/APM section
  rewritten since no standalone skills ship from here anymore); `skills/CLAUDE.md`
  (note that `skills/` currently ships no standalone skills, generic
  add-a-skill guidance retained). The `gardener/best-practices-checklist.md`
  had no reference to the commit skills' location, so it was left untouched, as
  were the `/commit-session` invocations inside the `ticket` plugin (command
  name unchanged).

### Tests / verification

This repo has **no unit-test suite and no test framework** — none was
introduced, which is correct here (it ships Markdown skills, JSON plugin
manifests, and shell scripts). Verification is the syntax/schema/lint checklist
from `doc/tickets/CLAUDE.md`, all run from the worktree root and all passing:

- `bash -n` over every tracked `*.sh` — PASS (exit 0)
- JSON validity over every `*plugin.json` / `*marketplace.json` (incl. the new
  `plugins/commit/.claude-plugin/plugin.json`) — PASS (exit 0)
- `ticket-state.sh lint --all` — PASS (0 errors, 0 warnings)

`git ls-files plugins/commit/` shows both moved SKILL.md files + the new
plugin.json; `git ls-files skills/commit-session skills/commit-all` shows
nothing (fully moved). No stray `skills/commit-*` path or APM-distribution
references remain (grep confirmed only the unchanged command names and the new
`commit` plugin location).

### Follow-up

To actually use `/commit-session` / `/commit-all` in this working tree, the
repo now installs the `commit` plugin via the marketplace
(`/plugin install commit@hayamiz-agentkit`) rather than `apm install`. `apm
install` still deploys the external `skill-creator` but no longer the commit
helpers.
