---
name: ticket-fix
description: "Implement fixes for tickets triaged as mechanically fixable. Trivial fixes edit in place; non-trivial fixes run in an isolated git worktree that carries source + tests only (the ticket stays in the main tree), checked by an independent reviewer (the Codex CLI when available, else a Sonnet evaluator subagent), and landed on your branch only via /ticket-apply. Review-gate progress is a Review-state marker in the ticket's Resolution, not a status. Claims each ticket with a lock so parallel runs don't collide. Does not merge to your branch."
argument-hint: "[ticket-number]"
allowed-tools: Bash(*) Read Edit Write Glob Grep
---

# Ticket Fix

Implement fixes for open tickets that `/ticket-triage` marked as mechanically
fixable (no user decision needed). Each fix runs in its own subagent to keep the
main conversation lean. Two paths:

- **In-place** — a trivial change (one file, a few lines) is edited directly in
  the working tree, leaving it dirty for `/commit-session`, exactly as before.
- **Worktree** — a non-trivial change is built in an isolated git worktree on a
  `ticket/NNNN-<slug>` branch that carries **source + tests only**; the ticket
  file itself never rides the branch — it stays in the main tree, where the parent
  records the fix's progress. The change is checked by an independent **evaluator**
  subagent and committed to that branch. On PASS the parent writes a
  `Review-state:` marker (`awaiting-review`, or `ready-to-apply` when the reviewer
  marks review skippable) into the main-tree ticket's `## Resolution` — the ticket
  `status:` stays `open`. It reaches your branch only when you run `/ticket-apply`
  — never automatically; the human review in between happens through
  `/ticket-review`.

This skill **does not merge or commit to your current branch**. All ticket
`status` changes go through the bundled `ticket-state.sh` script, and every
ticket is **claimed** with a lock first so parallel runs never process the same
one twice.

## Instructions

### Step 1: Resolve conventions and run the lint gate

1. Read the host repo's root `CLAUDE.md` (if present) for:
   - The ticket directory (e.g., `Tickets: <path>`). Default: `doc/tickets/`.
   - A spec / design document to keep in sync (e.g., `Spec: doc/SPEC.md`). Optional.
   - Verification commands (tests, linters, type checks), typically under a `## Verification` or `## Testing` heading. Optional.
2. Read `<ticket-dir>/CLAUDE.md` for the schema, lifecycle, and any declarations it adds (spec path, verification commands, `Lock TTL:`).
3. Run the lint gate:

   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> lint --all
   ```

   If it exits non-zero, **stop** and show the output — do not fix on top of a corrupt ticket state. Ask the user to repair (optionally `/ticket-lint <n> --fix`).

If a spec path is not declared anywhere, skip the spec-update step later. If verification commands are not declared anywhere, ask the user **once** what to run and remember the answer for this invocation.

### Step 2: Collect candidates

List tickets in `<ticket-dir>/` that meet ALL of:

- `status: open` or `status: in-progress`.
- Has a `## Triage` section with `Mechanical fix: yes` and `Requires user decision: no`.

Read each candidate's `Fix strategy` and `Affected files` from its `## Triage` section — they seed the strategy decision in Step 3.

If `$ARGUMENTS` contains a ticket number, narrow to just that ticket (and verify it meets the criteria; if not, say why and stop). If open tickets exist but **none** are triaged, tell the user to run `/ticket-triage` first and stop.

### Step 3: Claim each ticket, then choose its path

Sort candidates by priority (`critical` > `high` > `medium` > `low`), then by number. For each, in order:

1. **Claim it first** (before any work), so no other agent or invocation processes it:

   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> claim NNNN --owner "${CLAUDE_SESSION_ID}"
   ```

   - exit `0` → you own it; continue.
   - exit `3` → another agent holds it; **skip** and list it under "Skipped (claimed elsewhere)".
   - exit `4` → resolved/blocked/missing; skip.

2. **Decide the path.** Start from Triage's `Fix strategy`. Use **in-place** only when the change is genuinely small and self-contained — a few lines. Judge by **size, not file count**: "a few lines" is the deciding factor, so a large single-file addition (a new doc, a new module) belongs in a **worktree** even though it touches one file, while a couple of trivial edits across two files can stay in-place. When in doubt, prefer worktree.

**Context discipline**: you (the parent) orchestrate only — read tickets, claim, create worktrees, dispatch subagents, verify their output, present the summary. Do not read source or perform fixes directly in the main conversation.

**Parallelism**: worktree isolation makes parallel fixes safe (each on its own branch). Still cap concurrent worktrees (about 4) to bound compute and token cost. In-place fixes touching the same files must run sequentially.

### Step 4: In-place path (trivial)

Dispatch one subagent that edits the working tree directly. Its prompt MUST include the full ticket text, a pointer to read the host `CLAUDE.md`, the spec path (if any), the verification commands, and the steps below. The subagent:

a. **Mark in progress**: `ticket-state.sh --dir <ticket-dir> transition NNNN --from open --to in-progress` (use `--from in-progress` if it was already in progress).
b. **Implement** the minimal change the ticket requires; follow the host `CLAUDE.md`; no unrelated refactors.
c. **Add or update tests** (required) — see *Test principles* below.
d. **Verify**: run the declared verification commands; all must pass.
e. **Update the spec** only if a spec path is declared AND the change is user-visible.
f. **Resolve or bounce back** (see *Resolve / bounce* below).

Leaves the working tree dirty → the user commits with `/commit-session`.

### Step 5: Worktree path (non-trivial)

For each claimed non-trivial ticket, the parent:

1. **Create the worktree and branch** off the current HEAD (kept out of the working tree, under the shared git dir so it never shows in `git status`):

   ```
   WT="$(git rev-parse --git-common-dir)/ticket-worktrees/ticket-NNNN"
   git worktree add "$WT" -b ticket/NNNN-<slug>          # <slug> = the ticket's kebab subject
   ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> \
       claim NNNN --owner "${CLAUDE_SESSION_ID}" --worktree "$WT" --branch ticket/NNNN-<slug>
   ```

   (The second claim is idempotent for the same owner; it records the worktree/branch in the lock for later staleness checks.)

   The ticket file **stays in the main tree** — it never rides the `ticket/NNNN` branch. The branch carries source + tests only, so its state on the base doesn't matter here: there is no ticket-file merge, no divergent resolved-move, and no stale-copy reconciliation. The fix runs with no precondition and never halts to ask you to commit the ticket first.

2. **Dispatch the generator subagent.** Its prompt MUST include: the full ticket text; the absolute worktree path `$WT` with an instruction to `cd "$WT"` **first** and run everything there; a pointer to read the host `CLAUDE.md`; the spec path (if any); the verification commands; the *Test principles*; and these steps. The generator commits **source + tests only** — it never touches the ticket file (no status transition, no `## Resolution`, no ticket commit); the ticket stays in the main tree and the parent records progress there (Step 4). The generator:
   - `cd "$WT"`.
   - Implement the minimal fix (steps b–e above).
   - **Commit the fix proactively.** Once verification passes, stage the specific changed source and test files (never `git add -A`, and never the ticket file) and commit them to the branch with a Conventional Commits message. The branch is isolated and disposable — it is *not* your current branch — so committing is safe and expected: commit the finished work, don't leave it sitting uncommitted in the worktree.
   - Leave the worktree clean (everything committed) before reporting files changed, tests added, and the verification result. Do **not** transition the ticket or write `## Resolution` — that is the parent's job on the main-tree ticket.

3. **Review the fix — Codex CLI first, Sonnet evaluator as fallback.**
   - **If the Codex CLI is available** (`command -v codex` succeeds), try it first. It is a non-Claude model, so its judgement is genuinely independent of the generator. From the fix's worktree (so the ticket branch is checked out), review the branch against the base it was cut from, with a bounded timeout (the review can be slow):

     ```
     cd "$WT" && codex review --base <base-branch> -c sandbox_mode="danger-full-access"
     ```

     `codex review --base <ref>` reviews the current branch versus `<ref>`; it does not accept a custom prompt alongside `--base`, so this uses Codex's built-in review. The `-c sandbox_mode="danger-full-access"` override matters in containers/CI: Codex's own bubblewrap sandbox has to create a user/network namespace, which sandboxed environments often block (`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`) — without it `codex review` exits 0 but cannot inspect the diff. The review only reads git and files, and the surrounding agent/container is already the sandbox. Turn the result into the gate: a clean review ⇒ PASS; any blocking correctness/security finding ⇒ REJECT.
   - **Fall back to the Sonnet evaluator** whenever the Codex CLI is **absent**, or its run does **not** return a usable result — a non-zero exit, a "not authenticated / login required" message, a rate-limit / quota error, a timeout, empty output, or a sandbox/tooling failure where it reports it could not inspect the diff (e.g. bubblewrap / namespace errors such as "RTM_NEWADDR: Operation not permitted"). Dispatch the bundled evaluator subagent with `subagent_type: ticket:ticket-evaluator` (it runs on Sonnet). Its prompt MUST include the full ticket text, the absolute worktree path `$WT` (instruct it to `cd "$WT"` first), and the verification commands. It assumes the code is broken until proven otherwise, runs the verification itself, judges behavior over intent, edits nothing, and returns `VERDICT: PASS | REJECT` **plus a `human-review: recommended | optional` line** with evidence.
   - Whichever reviewer ran, it produces the single PASS/REJECT verdict used by steps 4–5. Note in the final summary which reviewer was used (Codex CLI or the Sonnet evaluator).

   **Obtain the `human-review` skip signal** (drives the PASS routing in step 4). The signal says whether a human must review before apply. `optional` requires ALL of: low-risk, **no user-visible behavior change**, no security-sensitive surface (auth, input handling, path handling), tests present. Default is conservative — treat anything unclear as `recommended`.
   - **Sonnet evaluator path:** parse the `human-review: recommended | optional` line the evaluator already emitted (per its output contract). If it is missing or ambiguous, treat it as `recommended`.
   - **Codex path:** `codex review --base` uses Codex's built-in review and cannot emit a custom signal, so after a Codex **PASS**, obtain the signal from a **dedicated lightweight Sonnet skip-judge**: dispatch a second `subagent_type: ticket:ticket-evaluator` in "skip-eligibility only" mode. Its prompt MUST tell it to `cd "$WT"`, read the branch diff against its base, apply the four `optional` criteria above, **edit nothing and run no verification**, and return **only** a single `human-review: recommended | optional` line (no PASS/REJECT — Codex already owns that verdict). On any failure, empty, or ambiguous result, default to `recommended`.

4. **On PASS**: the parent records the verdict on the **main-tree** ticket (whose `status:` stays `open`) — write a `## Resolution` section (what changed, tests added, spec updates, drawn from the generator's report) with an `Evaluator: PASS — <reviewer + what was run>` line and the `human-review: <recommended|optional>` signal — then **route on the pair** by writing a `Review-state:` marker into that same `## Resolution`, keeping the branch, worktree, and claim lock in place either way:
   - **PASS + `optional`** → `Review-state: ready-to-apply` (review skipped — low-risk). The fix is ready for `/ticket-apply`.
   - **PASS + `recommended`** → `Review-state: awaiting-review`. The fix awaits human review via `/ticket-review`.

   The marker is a line in `## Resolution` beside `Evaluator:` / `human-review:`; it is **not** a `status:` value (the branch carries no ticket, and `status:` stays `open` until `/ticket-apply` does the `open → resolved --move` at land time). These main-tree edits stay dirty for now — do not commit them here; `/ticket-apply` commits the ticket when the fix lands.

5. **On REJECT** (*bounce back*): do not force it. In the **main-tree** ticket file, set the `## Triage` to `Mechanical fix: no` / `Requires user decision: yes` with a note quoting the reviewer's reason, and keep `status: open`. Then discard the attempt and release the lock:

   ```
   git worktree remove --force "$WT"
   git branch -D ticket/NNNN-<slug>
   ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-state.sh --dir <ticket-dir> release NNNN --owner "${CLAUDE_SESSION_ID}"
   ```

After each subagent, verify its output before moving on (inspect the branch diff / read the evaluator's pasted output).

#### Resolve / bounce (in-place path, step f)

- Success (b–e passed): `ticket-state.sh --dir <ticket-dir> transition NNNN --from in-progress --to resolved --move`, write `## Resolution`, then release the lock (`release NNNN --owner "${CLAUDE_SESSION_ID}"`). The file move is done by the script; do not `git mv` the ticket yourself.
- Failure (needs user input, or verification keeps failing): revert the subagent's source edits (leave the ticket file), set `## Triage` to `Requires user decision: yes` with a reason, keep `status: open`, release the lock, and report.

#### Test principles (language- and framework-agnostic)

- **Coverage**: every new code path (function, branch, endpoint, interaction) needs at least one test.
- **Match the project**: follow the repo's existing test framework, layout, and naming. If the area has no tests, **stop and ask** before introducing a framework the project doesn't use.
- **Risk-weighted**: *must test* security-sensitive changes (input sanitization, auth, path handling), error paths, and core public behavior; *should test* user-facing interactions, state changes, boundaries; cosmetic changes are nice-to-have.
- **Security-sensitive changes** must cover all relevant malicious-input variants (traversal, injection, oversized input), not just the happy path.
- **Bug fixes** must include a regression test that fails without the fix and passes with it.

### Step 6: Present the summary

#### Awaiting review (worktree, PASS + review recommended)

| Ticket | Title | Branch | Review-state | Evaluator |
|--------|-------|--------|--------------|-----------|
| #NNNN  | ...   | `ticket/NNNN-<slug>` | `awaiting-review` | PASS — ... |

#### Ready to apply (worktree, PASS + review skipped — low-risk)

| Ticket | Title | Branch | Review-state | Evaluator |
|--------|-------|--------|--------------|-----------|
| #NNNN  | ...   | `ticket/NNNN-<slug>` | `ready-to-apply` | PASS — ... (`human-review: optional`) |

#### Fixed in place (dirty working tree)

| Ticket | Title | What was done |
|--------|-------|---------------|
| #NNNN  | ...   | ...           |

#### Could not fix (now needs user decision)

| Ticket | Title | Reason (incl. evaluator REJECT) |
|--------|-------|--------|
| #NNNN  | ...   | ...    |

#### Skipped

| Ticket | Title | Why (already needs a decision / claimed elsewhere) |
|--------|-------|-----------------|
| #NNNN  | ...   | ...             |

End with the right next step(s):

- "Run `/ticket-review` to review the N `awaiting-review` worktree fixes."
- "Run `/ticket-apply` to land the K `ready-to-apply` worktree fixes (review skipped — low-risk)."
- "Run `/commit-session` to commit the M in-place fixes."

## Notes

- **Commit proactively in the worktree.** Isolation is exactly what makes committing safe, so once a worktree fix is done, commit it — the generator commits the fix (+ tests) to the branch, leaving the worktree clean. Do not leave finished work uncommitted. The ticket file is **not** among those commits: it stays in the main tree, edited (dirty) by the parent, and is committed only by `/ticket-apply` at land time. This only applies to the worktree path; the in-place path touches your current branch directly, so it must *not* auto-commit — it stays dirty for `/commit-session`.
- **The ticket stays main-resident.** The `ticket/NNNN-<slug>` branch carries source + tests only. The parent records the fix's progress on the main-tree ticket — the `## Resolution`, the `Evaluator:` verdict, and the `Review-state:` marker — while its `status:` stays `open`. This removes the old precondition (no ticket-file merge, no divergent resolved-move, no stale-copy cleanup) at the cost of the main tree showing the ticket file modified while a fix is in flight.
- **Does not touch your current branch.** Worktree commits land on their own `ticket/NNNN-<slug>` branch and reach your branch only through `/ticket-apply` (the human gate). The plugin's "never lands on your branch automatically" rule is upheld — only `/ticket-apply` merges and commits the ticket's `open → resolved --move`.
- **Review gate is worktree-only, tracked by a marker.** A worktree PASS gets a `Review-state:` marker in the main-tree ticket's `## Resolution`: `awaiting-review` (review recommended → run `/ticket-review`) or `ready-to-apply` (review skipped — low-risk → run `/ticket-apply`). The marker is not a `status:` value — `status:` stays `open`, and the `resolved`-move happens later, at apply time. In-place (trivial) fixes never take this path — they go straight to `resolved` + dirty tree, gated by `/commit-session`.
- **Status is script-owned.** Never edit the `status:` line or `git mv` a ticket by hand — always use `ticket-state.sh transition`, which keeps the `status ⇔ location` invariant. (The `Review-state:` marker is ordinary `## Resolution` prose, edited directly — it is not a `status:` value.)
- **Claim before work, release when done.** A ticket is locked for the whole fix→review→apply window; `/ticket-review` releases the lock on reject, `/ticket-apply` releases worktree locks on land/reject. Bounced and in-place fixes release their own lock.
- **Evaluator separation is the point.** The agent that wrote the code never grades its own work; a separate reviewer that *runs* the change decides PASS **and** the `human-review` skip signal. Try the **Codex CLI** first (`codex review --base <base>` from the worktree) for a genuinely independent, non-Claude judgement; because Codex cannot emit a custom signal, a lightweight Sonnet skip-judge supplies `human-review:` after a Codex PASS. If Codex is unavailable or does not return a usable result (no auth, rate-limited, timeout, empty), fall back to the bundled `ticket:ticket-evaluator` subagent (Claude on **Sonnet**, adversarial by prompt), which emits both the verdict and the skip signal. A worktree fix with no PASS gets no `Review-state:` marker at all.
- **Do not skip user-decision tickets**, and keep each fix focused — if a fix organically wants to grow, that's a signal it isn't mechanical; bounce it back.
- **Per-ticket subagent isolation is non-negotiable** — it keeps the skill usable on projects with many tickets without blowing up the parent context.
