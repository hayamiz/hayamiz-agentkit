---
name: Gardener Self-Update Plan
description: Framework for resyncing best-practices-checklist.md against upstream reference URLs and for adding new references
type: plan
---

# Gardener Self-Update — Design Plan

This document proposes how the `gardener` skill keeps its own support files fresh — in particular [best-practices-checklist.md](best-practices-checklist.md) — without hand-editing. It is a **design proposal**, not yet an implemented sub-skill. The goal is to agree on the shape before building it.

---

## Why this is needed

Two forces cause drift:

1. **Upstream docs evolve.** `code.claude.com/docs/en/best-practices` and community references update silently. A checklist snapshot from April becomes misleading by July.
2. **The user adds new reference URLs over time.** When they do, every relevant section of the checklist potentially needs a new row — tedious and easy to skip.

Without a disciplined workflow, the checklist rots, and the Best Practices audit section of `gardener` starts reporting against stale standards.

## What the self-update workflow does

One entrypoint, two modes:

### Mode A — Resync

*"Refresh the checklist against the URLs already listed."*

1. Read the `sources:` block in [best-practices-checklist.md](best-practices-checklist.md) frontmatter.
2. For each source, `WebFetch` the URL with a prompt that asks for *"all best-practice items as a flat list."*
3. Diff the returned items against the current checklist:
   - **New items** → propose adding under the appropriate section.
   - **Removed / contradicted items** → propose marking stale or removing.
   - **Rephrased items** → surface for user review (don't silently rewrite).
4. Update `last_fetched` per source and `last_synced` at the top of the frontmatter.
5. Present a diff summary to the user and apply changes only after approval.

### Mode B — Add Reference

*"Here's a new URL — integrate it."*

1. Append the new URL to `sources:` with a label and today's date as `last_fetched`.
2. `WebFetch` it, then classify each extracted item under an existing section (or propose a new section if genuinely novel).
3. For each proposed addition, tag the recommendation with `(community)` or `(source: <label>)` so readers know provenance.
4. Re-run **Mode A** against all sources so additions are reconciled with existing content (de-dupe, merge).
5. Present diff, apply on approval.

---

## Proposed shape

Two realistic options. Pick one — don't build both.

### Option 1: Sub-skill under gardener (recommended)

Create `gardener/update-checklist/SKILL.md` as a separate skill invoked by the user:

```
/update-checklist            # Mode A: resync all sources
/update-checklist <url>      # Mode B: add a new reference URL
```

**Pros**: explicit, discoverable, lives alongside the artifact it maintains. Keeps the main `gardener` skill focused on auditing, not on maintaining itself.

**Trade-off**: another top-level skill in the user's skill list. Mitigated by the `gardener/` subfolder scoping.

### Option 2: In-skill section of gardener

Add a `## 6. Self-Update` section to [SKILL.md](SKILL.md) that triggers on focus-area `update` (e.g., `gardener update` or `gardener update <url>`).

**Pros**: no new skill. Everything gardener-related in one place.

**Trade-off**: conflates two concerns (auditing vs. maintaining the auditor). Harder to invoke directly without running the full gardener pass first.

**Recommendation: Option 1.** The workflows are different enough (WebFetch-heavy, diff-focused, no journal entry) that a dedicated skill is cleaner.

---

## Implementation sketch (for whichever option is picked)

A `update-checklist` skill body would look roughly like:

1. **Parse frontmatter** of `best-practices-checklist.md` to get `sources:`.
2. **Handle `$ARGUMENTS`**:
   - If a URL is provided → Mode B: append to `sources:` first, then fall through.
   - If empty → Mode A: resync existing sources.
3. **Fetch each source** via `WebFetch` with a consistent extraction prompt. Cache misses are fine — the 15-min cache is a bonus, not required.
4. **Build a proposed delta** as three lists: *add*, *remove/stale*, *rephrase*. Keep it small and reviewable.
5. **Show the diff to the user** using natural language + patch-style snippets. Do not auto-apply.
6. **On approval, write the file** with `Edit` (section-by-section) rather than `Write` — this preserves unrelated hand-edits.
7. **Update timestamps** (`last_fetched` per source; `last_synced` at top) and bump `version:` if items were added/removed.
8. **Leave git to handle history** — do not maintain a changelog inside the file.

## Guardrails

- **Never overwrite `best-practices-checklist.md` without showing a diff first.** The file is hand-curated and may have user-specific notes the upstream doesn't know about.
- **Do not auto-remove items** just because they're absent from upstream — upstream may have simply reorganized. Flag for review instead.
- **Respect community-source provenance.** If an item came from a community checklist, don't silently "promote" it by dropping the `(community)` tag.
- **Fail loudly** if a source URL returns an auth page, a 404, or nothing extractable — don't silently drop the source.
- **Do not self-update during a normal gardener run.** Audit and maintenance should be separate user actions.

## Open questions to resolve before implementing

1. **Where does Mode B put new items** that don't fit any existing section? Propose a new section, or force-fit, or park in an "Unsorted" bucket at the bottom of the checklist?
2. **Diff granularity**: item-level (one row at a time) or section-level (whole section rewrite)? Item-level is more reviewable but chattier.
3. **Versioning discipline**: bump `version:` on every change, or only on breaking structural changes? I lean toward the latter — `last_synced` already tracks freshness.
4. **Cadence**: is this purely on-demand, or should there be a `/loop`-style scheduled resync (e.g., monthly)? Starting on-demand is simpler; scheduling can come later.
5. **Other support files**: does the same framework generalize to other gardener artifacts (e.g., a future `security-checklist.md`)? If yes, the sub-skill should be parameterized by target file rather than hard-coded to `best-practices-checklist.md`.

## Next steps (if the user wants to proceed)

- Decide: Option 1 vs Option 2.
- Resolve the open questions above (quick — most have obvious defaults).
- Implement the skill (estimated scope: ~80–120 lines of `SKILL.md` plus the workflow prompt).
- Dry-run against the current checklist to validate the diff output is useful.

## Status

- **2026-04-19 (initial)**: implemented as a top-level `update-checklist/` skill (Option 1, flat name, parameterized by target file). `security-checklist.md` added as a second maintained artifact alongside `best-practices-checklist.md`.
- **2026-04-19 (follow-up)**: repackaged as a Claude Code plugin at `plugins/gardener/`. The `update-checklist` skill now lives at [skills/update-checklist/SKILL.md](skills/update-checklist/SKILL.md) and is invoked as `/gardener:update-checklist`. The main audit skill is at [skills/gardener/SKILL.md](skills/gardener/SKILL.md) (`/gardener:gardener`). Support files (`best-practices-checklist.md`, `security-checklist.md`, this file) live at the plugin root and are referenced from skills via `../../<file>`. The namespacing concern raised during design is resolved by the plugin's `name: gardener` in `.claude-plugin/plugin.json`.

## Answers from user

- Option 1 が望ましい
  - スキル名は /update-checklist ではなく /gardener:update-checklist という形にできないか？
- **Where does Mode B put new items**
  - 既存のsectionにフィットしない場合は、新しいsectionを提案する
- **Diff granularity**: section level
- **Versioning discipline**: only on breaking structural changes
- **Cadence**: on-demand only
- **Other support files**: yes, the framework should be generalizable to other artifacts
  - security-checklist.md も今回作成してほしい

---

## Decisions & notes from the implementation pass

- **Naming (`/gardener:update-checklist`)**: the `plugin:skill` syntax is reserved for Claude Code *plugins* (each plugin declares a `.claude-plugin/` manifest and its skills are namespaced automatically). This repo is managed by APM, which distributes skills as flat top-level directories — APM doesn't currently wrap them in a plugin namespace. Two honest paths:
  1. Keep the skill name flat as `update-checklist` for now, and revisit if/when this repo is packaged as a Claude Code plugin.
  2. Convert this repo into a plugin (add `.claude-plugin/plugin.json` with `name: gardener`, move gardener's skills under it). That's a bigger change that touches APM packaging and is out of scope for this task.
  - **Chosen for now**: path 1 (flat `update-checklist` name). Documented here so we can revisit later.
- **Generalization**: `update-checklist` is parameterized by target file — it reads the frontmatter of whatever file is passed (or defaults to `best-practices-checklist.md`). This lets the same skill maintain `security-checklist.md` or any future `<topic>-checklist.md`.
- **Target file arg**:
  - `/update-checklist` → default target (`gardener/best-practices-checklist.md`), resync mode.
  - `/update-checklist <target-file>` → resync a specific target.
  - `/update-checklist <target-file> <new-url>` → add a URL to that target, then resync.
- **Section-level diffs**: each diff unit is a whole section of the checklist. Easier to review as a block, and aligns with how upstream docs reorganize content.
- **Versioning**: `version:` bumps only on structural changes (section added/removed/renamed). Item-level churn is tracked by `last_synced` alone.
- **New-section handling in Mode B**: if a fetched item doesn't fit any existing section, the skill *proposes* a new section (with a suggested name and rationale) and waits for user approval before inserting.