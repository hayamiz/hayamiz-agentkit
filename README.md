# hayamiz-agentkit

A personal collection of skills and plugins for coding agents (primarily
[Claude Code](https://claude.com/claude-code)) by [hayamiz](https://github.com/hayamiz).

Two distribution channels:

- **Plugins** (`plugins/`) — shipped through the Claude Code plugin marketplace. Available as commands with a plugin-name prefix (e.g. `/ticket-fix`, `/gardener`).
- **Skills** (`skills/`) — shipped via [APM](https://github.com/apm-pkg/apm). Deployed directly into `.claude/skills/` and invoked by their bare name.

## Layout

```
skills/     APM-distributed skills (one directory per skill, each with SKILL.md)
            (currently none shipped from here — the commit helpers are now the commit plugin)
plugins/    Claude Code plugin marketplace plugins (one directory per plugin)
  gardener/  Repository health audit — docs sync, best-practices checks, etc.
  ticket/    File-based ticket workflow (init / create / check / triage / fix)
  commit/    Session-aware git commit helpers (/commit-session, /commit-all)
.claude-plugin/
  marketplace.json   Marketplace manifest exposing plugins/ as a Claude Code plugin source
```

For details on each plugin or skill, see its `SKILL.md` / `plugin.json`.

## Installation

### Plugins (Claude Code)

Register the marketplace and install plugins with Claude Code's plugin commands.

```text
# Register the marketplace (first time only)
/plugin marketplace add hayamiz/hayamiz-agentkit

# Install plugins
/plugin install ticket@hayamiz-agentkit
/plugin install gardener@hayamiz-agentkit
/plugin install commit@hayamiz-agentkit
```

After installation the following commands become available:
`/ticket-init`, `/ticket-create`, `/ticket-check`, `/ticket-triage`, `/ticket-fix`, `/gardener`,
`/commit-session`, `/commit-all`.

### Skills (APM)

Requires the [`apm`](https://github.com/apm-pkg/apm) CLI. This repo currently
ships no standalone skills of its own via APM — the commit helpers that used to
live here are now the `commit` plugin (install it via the marketplace above).

To reinstall the external dependencies declared in this repo's own `apm.yml`
(currently just `skill-creator`):

```sh
apm install
```

## Development Notes

- `.claude/skills/` is gitignored — it is populated by `apm install`. Edit sources in `skills/<name>/` or `plugins/<name>/skills/<name>/` instead.
- When adding a plugin, add an entry to `.claude-plugin/marketplace.json`. When adding a skill, add it to `apm.yml` under `dependencies.apm` and run `apm install` to regenerate the lockfile.
- See [`CLAUDE.md`](CLAUDE.md), [`skills/CLAUDE.md`](skills/CLAUDE.md), and [`plugins/CLAUDE.md`](plugins/CLAUDE.md) for detailed conventions.
