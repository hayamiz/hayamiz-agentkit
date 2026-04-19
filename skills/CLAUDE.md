# Skills

This directory contains standalone skills. Each subdirectory is one skill,
shipped as an APM package.

Reference: <https://code.claude.com/docs/en/skills>

## Directory Structure

```
skills/
├── <skill-name>/
│   ├── SKILL.md              # required — entry point
│   ├── reference.md          # optional supporting file
│   ├── examples/             # optional
│   └── scripts/              # optional — executable helpers
```

One skill per top-level directory. Do not nest skills inside other skills.
The directory name becomes the skill's fallback name if `name` is omitted in
the frontmatter.

## SKILL.md Frontmatter

Between `---` markers at the top of `SKILL.md`. All fields are optional, but
`description` is strongly recommended.

| Field                      | Notes                                                                                                                                                             |
| :------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`                     | Lowercase letters, numbers, hyphens only. Max 64 characters. Defaults to the directory name.                                                                      |
| `description`              | Trigger-style — when should this skill fire? Combined `description` + `when_to_use` is truncated at **1,536 characters** in the skill listing. Front-load intent. |
| `when_to_use`              | Additional trigger phrases or example requests. Counts toward the 1,536-char cap.                                                                                 |
| `argument-hint`            | Autocomplete hint, e.g. `[issue-number]`.                                                                                                                         |
| `disable-model-invocation` | `true` → only the user can invoke. Use for side-effectful workflows (deploy, commit, send-message).                                                               |
| `user-invocable`           | `false` → only Claude can invoke. Use for background knowledge without a user-facing action.                                                                      |
| `allowed-tools`            | Space-separated string or YAML list. Pre-approves tools while the skill is active (does not restrict others).                                                     |
| `model` / `effort`         | Override model/effort while the skill is active.                                                                                                                  |
| `context`                  | `fork` runs the skill in a forked subagent. Pair with `agent:` to pick the agent type.                                                                            |
| `agent`                    | Subagent type when `context: fork` (built-in: `Explore`, `Plan`, `general-purpose`; or any `.claude/agents/` name).                                               |
| `hooks`                    | Skill-scoped hooks.                                                                                                                                               |
| `paths`                    | Glob patterns that restrict auto-invocation to matching files.                                                                                                    |
| `shell`                    | `bash` (default) or `powershell` for inline `` !`cmd` `` execution.                                                                                               |

## Writing the Description

Claude decides when to auto-invoke a skill based on the `description`. Good
descriptions:

- Name the trigger (`Use when ...`, `Fires on ...`)
- List a few phrases users actually say
- Are specific — vague descriptions either miss triggers or fire too often

Example:

```yaml
description: >
  Explains code with visual diagrams and analogies. Use when explaining how
  code works, teaching about a codebase, or when the user asks
  "how does this work?"
```

## Body Guidance

- **Keep SKILL.md under ~500 lines.** Move long reference material, API specs,
  or example collections into sibling files and link from the body (progressive
  disclosure). Sibling files are loaded only when referenced.
- **Describe goals and constraints, not rigid step-by-step scripts** — unless
  determinism is the point (e.g. a commit workflow).
- **Include a Gotchas / Notes section** for failure modes learned over time.
- **SKILL.md is loaded as a single message** when invoked, and stays for the
  rest of the session. Write standing instructions, not one-time steps.

## String Substitutions

Available inside SKILL.md body:

| Variable                | Expands to                                                                                    |
| :---------------------- | :-------------------------------------------------------------------------------------------- |
| `$ARGUMENTS`            | Full argument string passed after `/skill-name`. Appended as `ARGUMENTS: <value>` if omitted. |
| `$ARGUMENTS[N]` or `$N` | Positional arg, 0-indexed. Shell-style quoting — wrap multi-word values in quotes.            |
| `${CLAUDE_SESSION_ID}`  | Current session ID.                                                                           |
| `${CLAUDE_SKILL_DIR}`   | Absolute path to this skill's directory. Use for referencing bundled scripts.                 |

Inline shell injection: `` !`<command>` `` runs before the body is sent to
Claude; the output replaces the placeholder. Multi-line form uses a fenced
block opened with ` ```! `.

## Adding a New Skill to This Repo

1. Create `skills/<name>/SKILL.md` with the frontmatter above.
2. Add any supporting files (`reference.md`, `scripts/`, etc.) in the same
   directory and reference them from the body.
3. Add a dependency entry in the repo-root `apm.yml`:
   ```yaml
   - hayamiz/hayamiz-agentkit/skills/<name>
   ```
4. Run `apm install` to deploy it into `.claude/skills/`.

## Reference Checklist

For a fuller audit of skill quality, see `plugins/gardener/best-practices-checklist.md` §4.
