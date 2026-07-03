---
title: Document the Loop Engineering reference (summary doc + external citation, no PDF in repo)
type: docs
priority: medium
status: resolved
created: 2026-07-03
updated: 2026-07-03
---

## Description

The "Loop Engineering" write-up was the design reference behind this repo's
recent `ticket` plugin work (worktree-isolated fixes, the generator/evaluator
review gate, the loop framing). We want a durable, citable summary of it in the
repo — but **not** the PDF itself. Capture the ideas as an in-repo Markdown
document and treat the source as an external reference (URL + bibliography).

### Deliverable

Create `doc/references/loop-engineering.md` containing:

1. **A summary of the source's content** at a useful density — enough that a
   reader gets the framework without the PDF. Cover:
   - the four-layer stack (prompt → context → harness → **loop**);
   - the five moves of one turn (discovery, handoff, verification, persistence,
     scheduling) and the six parts that realize them;
   - the generator/evaluator separation (don't let the writer grade its own
     work; a skeptical evaluator that *acts*);
   - the three real loops (one engineer's triage loop; Stripe's Minions;
     scheduling local vs cloud);
   - the four silent costs (verification debt, comprehension rot, cognitive
     surrender, token blowout);
   - the closing thesis (loops make generation cheap; judgment stays scarce).
   - Optionally, a short note on how these ideas map onto this repo's `ticket`
     plugin (worktrees = handoff, evaluator gate = verification, `/ticket-apply`
     = the human review point, locks/lint = persistence integrity).

2. **A "Reference" section** with the bibliographic details and the retrieval
   URL, so the source is citable without shipping the file:
   - Title: *Loop Engineering: The Anthropic Playbook for Designing Systems That
     Prompt Your Agents* (subtitle: *A Field Study of Designing Loops That Run
     Themselves*).
   - Attribution: ©2026 HuaShu — an independent conference-style reformatting of
     Addy Osmani's open "Orange Book" guide *Loop Engineering: Stop Asking Me
     What It Is* (v260615, June 2026), huasheng.ai/orange-books. Key sources
     within: Addy Osmani (framework & coinage), Prithvi Rajasekaran / Anthropic
     (generator–evaluator findings), Steve Kaliski / Stripe (the Minions case).
   - Source URL: https://drive.google.com/file/d/1qzKI4DKnyHRpXK1J3ATPqwaqLc0iNu-M/view
     (Google Drive PDF; retrieved 2026-07-03).

### Constraints

- **Do not add the PDF (or any binary copy) to the repository.** The source is
  referenced by URL and bibliography only. If a `.pdf` is staged, that's a defect.
- Match the repo's Markdown/documentation style. `doc/references/` is a new
  directory; create it.

### Acceptance

- `doc/references/loop-engineering.md` exists with the summary + a Reference
  section (URL + bibliographic info).
- No PDF/binary added anywhere in the repo (`git status` shows no `*.pdf`).

## Triage

- Complexity: low
- Mechanical fix: yes
- Requires user decision: no
- Affected files: 1 new (`doc/references/loop-engineering.md`) + new dir `doc/references/`
- Fix strategy: worktree
- Notes: The triage subagent initially flagged `Requires user decision: yes`
  over the summary's density and voice. Those are minor, in-scope stylistic
  calls; they are resolved under "Decisions taken" below (per the user's request
  to proceed), which makes the ticket mechanical. Fix strategy is set to
  `worktree` rather than the subagent's `in-place` suggestion: the deliverable is
  a substantial multi-section document, not "a few lines in one file", so per
  `/ticket-fix`'s own rule it routes through a worktree and the review gate.

## Implementation Notes

Content structure (maps to the acceptance criteria):

1. **Summary** — a prose + tight-bullet overview of: the four-layer stack
   (prompt → context → harness → loop); the five moves (discovery, handoff,
   verification, persistence, scheduling) and six parts; the generator/evaluator
   separation; the three real loops (one engineer's triage loop, Stripe's
   Minions, local-vs-cloud scheduling); the four silent costs (verification debt,
   comprehension rot, cognitive surrender, token blowout); and the closing thesis
   (generation becomes cheap, judgment stays scarce).
2. **How it maps to this repo's `ticket` plugin** — worktrees = handoff isolation,
   the review gate = verification, `/ticket-apply` = the human review point,
   claim locks + lint = persistence integrity.
3. **Reference** — the bibliographic block + retrieval URL from the Description.

### Decisions taken (resolving the flagged user-decision points)

- **Density**: concise but complete — roughly one tight paragraph or a short
  bullet cluster per concept; the whole doc a comfortable read, not exhaustive.
- **Optional repo→plugin mapping section**: include it (it is the reason this
  reference is worth keeping in-repo).
- **Voice**: matter-of-fact / technical, matching the repo's existing `CLAUDE.md`
  documentation style.

### Style

Line-wrapped Markdown; `##`/`###` headings; `**bold**` for terms; backticks for
commands/paths. Summarize in our own words — no long verbatim quotes. Do not add
the PDF or any binary.

## Resolution

Created `doc/references/loop-engineering.md` (new file; `doc/references/` is a
new directory). The document has three sections, per the acceptance criteria:

1. **Summary** — the source in our own words at concise-but-complete density:
   definition and framing, the four-layer stack (prompt → context → harness →
   loop), blast radius by layer, the five moves of one turn, the six parts that
   realize them, the generator/evaluator separation, the five failure modes, the
   three real loops (one-engineer triage, Stripe's Minions, local-vs-cloud
   scheduling), the four silent costs, and the closing thesis.
2. **How it maps to this repo's `ticket` plugin** — worktrees = handoff
   isolation, the review gate = verification, `/ticket-apply` = the human review
   point, claim locks + lint = persistence integrity.
3. **Reference** — the bibliographic block plus the retrieval URL.

No PDF or binary was added: the source is cited by URL and bibliography only
(`git status` showed no `*.pdf` or binary; the new file is UTF-8 text). Markdown
is line-wrapped to <=80 columns with `##`/`###` headings, `**bold**` terms, and
backticks for commands/paths.

Verification (docs-only change, no code paths, so no tests added): the repo's
declared checks from `doc/tickets/CLAUDE.md` passed — shell scripts parse
(`bash -n`) and plugin/marketplace manifests are valid JSON. The ticket lint
runs later in the apply flow.

- Evaluator: PASS — `ticket:ticket-evaluator` (Sonnet), the Codex-CLI fallback.
  The Codex CLI review (`codex review --base master`) exited 0 but produced no
  usable result: its bubblewrap sandbox failed to initialize in this container
  (`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`), so it could
  not inspect the diff — the fallback reviewer took over. The evaluator ran the
  repo verification (bash -n, JSON validity, ticket lint), confirmed all required
  concepts are present and coherent, no PDF/binary is tracked, and the ticket is
  resolved. Non-blocking: a few prose lines run 81–84 chars.
