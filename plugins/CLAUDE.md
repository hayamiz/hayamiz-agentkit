# Plugins

This directory contains Claude Code plugins. Each subdirectory is one
self-contained plugin bundling skills, agents, hooks, MCP servers, etc.

Reference: <https://code.claude.com/docs/en/plugins-reference>

## Plugin Directory Structure

```
<plugin-name>/
├── .claude-plugin/
│   └── plugin.json          # manifest (optional but recommended)
├── skills/                  # <skill-name>/SKILL.md each
├── commands/                # flat .md skill files (legacy; prefer skills/)
├── agents/                  # <agent-name>.md each
├── output-styles/           # <style>.md each
├── monitors/
│   └── monitors.json
├── hooks/
│   └── hooks.json
├── .mcp.json                # MCP servers
├── .lsp.json                # language servers
├── bin/                     # executables added to Bash PATH
├── scripts/                 # helper scripts referenced by hooks, etc.
├── settings.json            # plugin defaults (agent, subagentStatusLine only)
├── LICENSE
└── CHANGELOG.md
```

> ⚠️ Component directories (`skills/`, `agents/`, `hooks/`, etc.) live at the
> plugin root, **not** inside `.claude-plugin/`. Only `plugin.json` goes in
> `.claude-plugin/`.

## plugin.json Schema

`.claude-plugin/plugin.json` is optional. If omitted, Claude Code auto-discovers
components in default locations and derives the plugin name from the directory
name. Add a manifest when you need metadata or custom component paths.

### Required

| Field  | Type   | Notes                                           |
| :----- | :----- | :---------------------------------------------- |
| `name` | string | Unique identifier, kebab-case, no spaces.       |

### Metadata (optional)

`version` (semver), `description`, `author` (object with `name`/`email`/`url`),
`homepage`, `repository`, `license`, `keywords` (array).

### Component path fields (optional)

All paths are relative to the plugin root and **must start with `./`**.
Specifying a custom path **replaces** the default directory for `skills`,
`commands`, `agents`, `outputStyles`, and `monitors`. To keep the default and
add more, include both:

```json
"skills": ["./skills/", "./extras/"]
```

| Field          | Default location         | Accepts            |
| :------------- | :----------------------- | :----------------- |
| `skills`       | `skills/`                | string \| array    |
| `commands`     | `commands/`              | string \| array    |
| `agents`       | `agents/`                | string \| array    |
| `outputStyles` | `output-styles/`         | string \| array    |
| `hooks`        | `hooks/hooks.json`       | string \| array \| object (inline) |
| `mcpServers`   | `.mcp.json`              | string \| array \| object (inline) |
| `lspServers`   | `.lsp.json`              | string \| array \| object (inline) |
| `monitors`     | `monitors/monitors.json` | string \| array    |
| `userConfig`   | —                        | object             |
| `channels`     | —                        | array              |
| `dependencies` | —                        | array              |

### Minimal manifest

```json
{
  "name": "my-plugin"
}
```

### Complete manifest example

```json
{
  "name": "deployment-tools",
  "version": "1.2.0",
  "description": "Deployment automation",
  "author": { "name": "Yuto Hayamizu" },
  "license": "MIT",
  "skills": "./skills/",
  "hooks": "./hooks/hooks.json",
  "mcpServers": "./.mcp.json"
}
```

## Component Notes

### Skills

Same format as top-level `skills/` (see `skills/CLAUDE.md` at the repo root).
A plugin skill is namespaced as `<plugin-name>:<skill-name>`.

### Agents

Markdown files with frontmatter. Supported fields: `name`, `description`,
`model`, `effort`, `maxTurns`, `tools`, `disallowedTools`, `skills`, `memory`,
`background`, `isolation` (only `"worktree"` is valid).

Plugin-shipped agents **cannot** set `hooks`, `mcpServers`, or `permissionMode`
(security restriction).

### Hooks

JSON with event matchers and actions. Events include `PreToolUse`, `PostToolUse`,
`Stop`, `SessionStart`, `UserPromptSubmit`, `FileChanged`, `PreCompact`,
`PostCompact`, etc. (full list in the upstream docs).

Hook types: `command`, `http`, `prompt`, `agent`.

### MCP / LSP servers

Reference executables and scripts via `${CLAUDE_PLUGIN_ROOT}` (see below).

### Monitors

Background processes that stream stdout as notifications. Each entry needs
`name`, `command`, `description`. Optional `when` controls startup:
`"always"` (default) or `"on-skill-invoke:<skill-name>"`.

## Environment Variables

Available in skill content, agent content, hook commands, monitor commands,
and MCP/LSP configs:

| Variable               | Notes                                                                    |
| :--------------------- | :----------------------------------------------------------------------- |
| `${CLAUDE_PLUGIN_ROOT}` | Absolute path to the plugin install dir. Changes when the plugin updates — don't write durable state here. |
| `${CLAUDE_PLUGIN_DATA}` | Persistent data dir that survives updates. For `node_modules`, caches, generated code. |
| `${user_config.KEY}`    | Per-`userConfig` entry (non-sensitive values only in skill/agent content). |

Paths referenced in hook scripts and MCP configs should almost always use
`${CLAUDE_PLUGIN_ROOT}` — never hard-code absolute paths.

## Adding a New Plugin to This Repo

1. Create `plugins/<name>/` with the structure above.
2. At minimum, add `.claude-plugin/plugin.json` with a `name` field, or rely on
   the directory name.
3. Add a dependency entry in the repo-root `apm.yml`:
   ```yaml
   - hayamiz/hayamiz-agentkit/plugins/<name>
   ```
4. Run `apm install` to deploy.
5. Bump `version` in `plugin.json` on every release — Claude Code uses the
   version to decide whether to refresh cached copies, so unchanged version
   numbers hide code changes from existing users.

## Constraints to Remember

- Paths in `plugin.json` must start with `./` (no absolute paths, no `../`).
- Path traversal outside the plugin root is blocked — use symlinks if you need
  shared code.
- Component directories must be at the plugin root, not inside `.claude-plugin/`.
- Installed plugins run from `~/.claude/plugins/cache/` — files written to
  `${CLAUDE_PLUGIN_ROOT}` do not survive updates.
