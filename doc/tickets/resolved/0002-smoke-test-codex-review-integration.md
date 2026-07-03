---
title: Smoke-test the Codex review integration in /ticket-fix and refine it from the results
type: test
priority: medium
status: resolved
created: 2026-07-03
updated: 2026-07-03
---

## Description

`/ticket-fix` (v0.4.1) routes the review of a non-trivial, worktree-isolated fix
to Codex — `/codex:adversarial-review` from codex-plugin-cc — when that plugin is
installed, falling back to the bundled `ticket:ticket-evaluator` Claude subagent
otherwise (see [[the review gate]] in `plugins/ticket/CLAUDE.md`).

That routing was written from the plugin's README, not from its actual behavior.
Two assumptions are unverified and worth a smoke test before we trust the flow:

1. **Auto-dispatch feasibility** — can the `/ticket-fix` orchestrator actually
   trigger the Codex review programmatically, or are `/codex:*` user-only?
2. **Branch targeting** — Codex review compares `<base>...HEAD`. Does it review
   the intended `ticket/NNNN-<slug>` diff when that branch lives in a worktree,
   and how must it be invoked (cwd, `--scope`, `--wait`) to do so?
3. **Readiness** — is the Codex CLI authenticated, and what happens on failure
   (does the fallback engage)?

### Goal / acceptance

- Empirically exercise the Codex review path against a throwaway worktree branch
  carrying a deliberately flawed diff, and record what actually happens.
- From the results, refine `/ticket-fix`'s review-gate instructions so they match
  reality (or confirm the fallback), and apply the clear-cut fixes.
- Deliverable: documented smoke-test findings + concrete improvement, recorded in
  this ticket's `## Resolution`.

Codex is installed here (`codex-cli 0.142.5`), so the test can run against the
real plugin. Note the ticket plugin *installed* in this session is a pre-0.4.1
cache; the 0.4.1 logic under test is driven from this repo's skill sources.

## Triage

- Complexity: medium
- Mechanical fix: no
- Requires user decision: no
- Affected files: 2 (`plugins/ticket/skills/ticket-fix/SKILL.md`, `plugins/ticket/CLAUDE.md`)
- Fix strategy: in-place (edits to this plugin's own skill instructions — no product code to isolate and no evaluator run to gate)
- Notes: the "fix" is (1) an empirical smoke test of the Codex review path and (2) a doc/instruction correction driven by the result. Not mechanical because the correction depends on what the test reveals.

## Implementation Notes

Run the smoke test, then reconcile `/ticket-fix`'s review-gate instructions with
Codex's observed behavior. Likely correction (to confirm empirically before
rewriting): because `/codex:review` and `/codex:adversarial-review` are
`disable-model-invocation` user-only commands wrapping
`scripts/codex-companion.mjs`, `/ticket-fix` cannot auto-dispatch them, and the
companion script's absolute path is version-specific (not portable). So the
automated gate should stay the `ticket:ticket-evaluator` subagent, with Codex
repositioned as an optional, **user-invoked** cross-model review at the
review / apply boundary (e.g. `cd <worktree> && /codex:adversarial-review
--base <base> --scope branch`). Decision points: (a) keep any automated Codex
attempt at all vs. purely recommend it; (b) where to surface the recommendation
(fix summary and/or `/ticket-apply`).

### Smoke test results (2026-07-03)

Ran against a scratch repo: a `ticket/0009-demo` branch in a worktree with a
planted bug (empty-filter divide-by-zero → NaN). Invoked from the worktree:
`node <codex-companion.mjs> adversarial-review "--base master --scope branch --wait"`.

- **Codex is authenticated and works** (`~/.codex/auth.json`; companion exit 0).
- **Branch targeting is correct**: it reviewed exactly the `master...ticket/0009-demo`
  diff and **caught the planted bug** at `util.js:11`, returning
  `Verdict: needs-attention` plus a machine-readable `{"verdict":"needs-attention",…}`.
  Mapping: any findings / `needs-attention` ⇒ REJECT; clean ⇒ PASS.
- **`/codex:review` and `/codex:adversarial-review` are `disable-model-invocation`**
  (user-only slash commands) — an orchestrating skill **cannot** auto-trigger them.
- **The companion script CAN be run programmatically** via Bash from the worktree
  (proven above), but its path is version-specific
  (`~/.claude/plugins/cache/openai-codex/codex/<ver>/scripts/codex-companion.mjs`),
  i.e. coupling to codex-plugin-cc internals. (`codex review` also exists as a
  native CLI subcommand — a more stable surface, not exercised here.)

Conclusion: fully-automatic codex review is achievable only by coupling to
internals; the *supported* surface is the user-invoked slash command. The three
improvement options (A automated/coupled, B evaluator-auto + codex recommended at
the human gate, C hybrid) are put to the user before rewriting `/ticket-fix`.

## Resolution

Per the decision, the review integration was switched **off codex-plugin-cc and
onto the Codex CLI directly**, and every codex-plugin-cc reference was removed
from the shipped plugin.

- **Reviewer order in `/ticket-fix`**: try the **Codex CLI** first — from the
  fix's worktree, `codex review --base <base>` reviews the ticket branch vs its
  base with a non-Claude model. If `codex` is absent or the run does not yield a
  usable result (not authenticated, rate-limited, timed out, empty), fall back to
  the bundled `ticket:ticket-evaluator` subagent, now pinned to `model: sonnet`.
- **Why not the plugin**: `/codex:review` / `/codex:adversarial-review` are
  `disable-model-invocation` (user-only), and the companion script path is
  version-specific — coupling a skill to plugin internals. The Codex CLI is a
  stable, PATH-level surface with first-class `--base <ref>` branch review.
- **CLI caveats found in the smoke test**: `codex review --base <ref>` cannot take
  a custom prompt (so it uses Codex's built-in review, no adversarial framing),
  and it can be slow (>2 min on a tiny diff) — hence the bounded-timeout + fallback.

Changed: `plugins/ticket/skills/ticket-fix/SKILL.md` (reviewer step, description,
notes), `plugins/ticket/agents/ticket-evaluator.md` (`model: inherit` → `sonnet`),
`plugins/ticket/CLAUDE.md` (Review Gate rewritten, install section removed),
`plugins/ticket/.claude-plugin/plugin.json` (0.4.1 → 0.4.2). No product code or
tests — this ticket's deliverable is the doc/skill correction itself. Verified:
the repo `## Verification` block passes and grep confirms no codex-plugin-cc
references remain under `plugins/ticket/`.
