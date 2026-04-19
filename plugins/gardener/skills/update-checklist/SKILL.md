---
name: update-checklist
description: "Resync gardener support-file checklists (best-practices, security, etc.) against their upstream reference URLs, or add a new reference URL to a checklist. Parameterized by target file."
argument-hint: "[target-file] [new-url]"
allowed-tools: Read Edit WebFetch Glob Bash(git diff:*) Bash(git status:*)
---

# Update Checklist

Keep `gardener`'s support-file checklists fresh against their upstream reference URLs. One workflow, two modes, generalized over any target checklist file.

Design rationale and open questions live in [self-update.md](../../self-update.md) (plugin root). This skill is the executable counterpart.

---

## Target file resolution

Checklist support files live at the plugin root. When resolving a target file:

- Plugin-root-relative paths (default): `best-practices-checklist.md`, `security-checklist.md`.
- If the user passes a repo-relative path (e.g., starting with `plugins/gardener/`), accept it and use as-is.
- If the user passes a bare filename (e.g., `security-checklist.md`), resolve it against the plugin root.

---

## Arguments

Parse `$ARGUMENTS`:

- **No args** → default target = `best-practices-checklist.md` at plugin root, Mode A (resync).
- **One arg, path-like** (contains `/` or ends in `.md`) → that is the target file, Mode A.
- **One arg, URL-like** (starts with `http`) → default target, Mode B (add URL + resync).
- **Two args** → first is target file, second is new URL, Mode B on that target.

If the target file doesn't exist or is missing a `sources:` frontmatter block, stop and tell the user — don't guess.

---

## Mode A — Resync an existing checklist

1. **Read the target file**.
2. **Parse frontmatter**: extract `sources:` entries (each has `url`, `label`, `last_fetched`) and the top-level `last_synced`.
3. **Fetch each source** via `WebFetch` with this extraction prompt template:

   > "Extract all actionable best-practice / checklist items from this page as a flat bullet list. For each item, give a one-line description. Group by the topic headings used on the page. Do not include prose, examples, or commentary."

   If a fetch returns an auth wall, 404, or empty content, **do not silently drop the source** — surface it and ask the user whether to remove it from `sources:` or keep it for later.

4. **Build a section-level diff** by comparing the fetched items against the current checklist:
   - For each existing section: which items map to upstream items, which look stale, which upstream items are new.
   - Group proposed changes **by section** (not item-by-item). Each section-level change is one reviewable unit.
   - Classify upstream items that don't fit any existing section as **candidates for a new section** (with a suggested name + rationale).

5. **Present the diff to the user** as a structured report:

   ```
   ## Proposed changes to <target-file>

   ### Section: <name>  (status: unchanged | updated | new | stale)
   - Add: ...
   - Remove (stale): ...
   - Rephrase: ... → ...

   ### New section candidate: <suggested name>
   Rationale: <why this doesn't fit existing sections>
   Items:
   - ...
   ```

   Wait for user approval **before** writing.

6. **On approval**, apply changes with `Edit` (section by section — not a wholesale `Write`), so any unrelated hand-edits in the file are preserved.

7. **Update frontmatter**:
   - `last_fetched` per source → today's date.
   - `last_synced` at top → today's date.
   - `version:` → bump **only** if structural changes occurred (section added / removed / renamed). Item-level churn does not bump version.

8. **Report the result** with a short summary and a pointer to `git diff <target-file>` for the full view.

---

## Mode B — Add a new reference URL

1. Validate the URL (must start with `http`, must be fetchable). Reject if it points to an authenticated service — the fetch won't work.
2. **Append to `sources:`**:
   ```yaml
   - url: <new-url>
     label: <short label — ask the user if not obvious from the URL>
     last_fetched: <today>
   ```
3. `WebFetch` the new URL with the same extraction prompt as Mode A.
4. **Classify each extracted item** under an existing section. For items that don't fit, propose a **new section** with suggested name and rationale — do not force-fit, do not drop.
5. **Tag additions with provenance**: items sourced from the new URL get `(source: <label>)` appended to the recommendation line, so readers can trace origin.
6. **Fall through to Mode A** to reconcile the additions against existing items (de-dupe, merge rephrases).
7. Present one combined diff, apply on approval, update frontmatter, report.

---

## Guardrails

- **Never overwrite the target without showing a diff first.** These files are hand-curated and may contain user-specific notes.
- **Do not auto-remove items** just because they're absent from upstream — upstream may have reorganized. Flag as stale for review instead.
- **Respect provenance tags**. Don't silently promote `(community)` items to un-tagged ones.
- **Fail loudly** on bad fetches. A silent drop of a source is worse than a noisy error.
- **Do not maintain a changelog** inside the file — `git log <target-file>` is authoritative.
- **Do not run as part of a normal gardener pass.** Audit and maintenance are separate user actions.

---

## Output on completion

After applying changes (or after a dry-run preview), emit:

- Target file path
- Sources fetched (with success/fail per source)
- Sections changed (added / updated / stale / unchanged)
- Whether `version:` was bumped, and `last_synced` delta
- Suggested follow-up: "run `/gardener:gardener` again to audit against the refreshed checklist"
