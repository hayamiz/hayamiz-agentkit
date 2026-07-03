# Loop Engineering

A durable, in-repo summary of the "Loop Engineering" write-up that informed this
repo's `ticket` plugin design (worktree-isolated fixes, the generator/evaluator
review gate, the loop framing). The source PDF is **not** vendored here; it is
cited by URL and bibliography in the [Reference](#reference) section.

## Summary

### Definition and framing

**Loop engineering** (coined June 2026; surfaced independently by Peter
Steinberger, Boris Cherny, and Addy Osmani, then named and written up by Osmani)
is the practice of *stopping being the person who prompts the agent and instead
designing the system that prompts it*. It sits one floor **above** the harness.
It became practical only recently, once tooling crossed a threshold: coding
agents grew reliable enough to finish a task unattended, harnesses gained
scheduling primitives, and per-run cost dropped low enough to run work on a
timer.

### The four-layer stack

Each layer's unit of concern is larger than the one below it:

- **Prompt engineering** — the words you tell the model.
- **Context engineering** — what goes in the window right now (retrieve /
  summarize / clear).
- **Harness engineering** — arming a single run: which tools it has, which
  actions it may take, and what counts as "done".
- **Loop engineering** — scheduling on top of the harness so it runs itself over
  and over. Loop adds three verbs the harness lacks: it **runs on a timer**, it
  **spawns helpers**, and it **feeds its own output back** as the next input
  (memory across conversations).

### Blast radius by layer

The same bug — the agent misreads a return value — costs more the higher up the
stack it happens, because cost scales with the number of turns a mistake
survives before someone catches it:

- **Prompt** — one wrong answer, caught immediately.
- **Context** — confidently wrong from stale docs; fixed by clearing the window.
- **Harness** — the agent acts once, but the diff is reviewed before it ships.
- **Loop** — the mistake is written into the state file, read back the next
  morning as established fact, and built upon for many turns until it becomes
  load-bearing.

The core intuition: a loop is a machine for maximizing turns, so the evaluator,
the checkpoints, and the budget caps all exist to **shorten the distance between
a mistake and its discovery**.

### The five moves of one turn

- **Discovery** — find work worth doing. Let the agent find its own work through
  a skill rather than a pasted wall of instructions; this move sets the quality
  ceiling for everything after it.
- **Handoff** — hand the task off in isolation: one git worktree per finding.
- **Verification** — swap in another agent whose job is to say "no". The easiest
  move to skip and the least affordable one to skip.
- **Persistence** — write state outside the conversation (PR + inbox + state
  file).
- **Scheduling** — make the loop come round again; a timer, with unfinished work
  carried into the next run.

### The six parts that realize the moves

- **Automations** — schedule/trigger mechanics (local vs cloud) → *scheduling*.
- **Worktrees** — isolated directories for parallel agents → *handoff*.
- **Skills** — permanent knowledge in a `SKILL.md` → *discovery*; pays off
  "intent debt", the cost of re-explaining the project on every run.
- **Connectors** — MCP links to external systems → *persistence/discovery*; they
  set the loop's radius of vision.
- **Sub-agents** — a generator separated from a judge → *verification*.
- **Memory** — persistent on-disk state → *persistence*; the agent forgets, the
  repo does not. Memory is not the same thing as context.

### Generator / evaluator

Per **Prithvi Rajasekaran (Anthropic)**, an agent asked to grade its own output
tends to praise it. This is not a smarts problem — it is grading its own
homework: the generator's context is full of the reasons it wrote the code that
way, so it re-reads its own chain of self-persuasion rather than the result.
Making the generator self-critical works poorly; tuning a **separate, skeptical
evaluator** is far more tractable, in a structural, GAN-like way.

A good evaluator **acts** rather than merely reads — e.g. driving the Playwright
MCP to open the page, click, and screenshot — and judges "does it run right",
not "does it look right". Swapping the model helps too, since the same model
keeps its own blind spots. Its default stance is to assume the code is broken
until proven otherwise. In Claude Code, `/goal` runs until a condition holds,
with a fresh, small model judging the stop condition — the banking
"maker–checker" principle. **A loop's floor is its evaluator.**

### Five failure modes

Each failure mode is one of the five moves skipped:

- **Nodding loop** — no verification; it self-approves.
- **Amnesiac loop** — no persistence; it forgets and redoes work.
- **Manual loop** — no scheduling; a script run by hand until attention wanders.
- **Blind loop** — no discovery; a human still hands it the work.
- **Tangled loop** — no handoff; parallel agents collide in one directory.

Hasty loops install only the two moves with visible output (discovery + handoff)
and skip the three that produce safety.

### Three real loops

- **One-engineer morning triage loop** (Osmani) — an automation triggers a
  `SKILL`, not a giant instruction block.
- **Stripe's "Minions"** (Steve Kaliski, *How I AI* podcast) — 1,300+ PRs merged
  per week, none hand-written. The trigger is light (`@bot` in Slack, an emoji),
  but reliability comes from a **deterministic orchestrator that runs before the
  model wakes**: it assembles context by scanning links, pulling Jira, and using
  Sourcegraph + MCP to find code. Anything deterministic is kept out of the
  probabilistic model. The pipeline interleaves hard-coded gates and LLM steps
  (agent writes → linter runs and cannot be skipped → agent fixes lint →
  hard-coded commit). The sandbox is Devbox-on-EC2, "cattle not pets", and the
  PRs are still human-reviewed — the human moved from writing to reviewing.
  Notably it is a fork of the open-source Goose, not a stronger model:
  reliability is the quality of the constraints, not model size.
- **Scheduling, local vs cloud** — local `/loop` and desktop tasks need the
  machine on; Cloud Routines / GitHub Actions schedules run with the machine off
  but are coarser (~1h minimum interval, a fresh clone, no local files). Choose
  by whether the work is glued to the local machine; do not conflate "local
  rerun while I'm here" with "cloud runs while I'm away". Mature loops use both.
  The same capabilities exist in Codex under different names — loop engineering
  is a set of capabilities, not a product.

### Four silent costs

They reinforce one another:

- **Verification debt** — unverified output piling up in the gap between "runs"
  and "right". Guard: an independent evaluator.
- **Comprehension rot** — the codebase grows past your mental map. Guard: read a
  representative sample daily and force yourself to explain the changes.
- **Cognitive surrender** — you stop having an opinion and just accept output.
  Guard: the loop may execute but must not decide; stay able to say "this is
  wrong".
- **Token blowout** — helpers and retries spin all night into a surprise bill.
  Guard: hard caps — per-run budget, daily budget, max retries.

A worked example chains them: 20 green overnight PRs, 3 with subtle uncovered
bugs, merge (debt) → your mental model lags 20 changes (rot) → you stop reading
(surrender) → the bill triples (blowout) → the buried bugs surface later as a
production incident.

### Closing thesis

The same loop built by two people yields opposite outcomes, because a loop is a
faithful **multiplier** of whatever the builder brings — understanding or
laziness. Loops make generation nearly free; **judgment stays scarce** (which
plan is right, which output runs fine but is wrong at the root). The amplifier
cuts both ways: a lapse in judgment is executed in bulk, with no slow gear to
catch it. The discipline that follows is: read a sample always; cap before you
ship; and keep one door open — a human checkpoint — so you stay able to
intervene. The one sentence to keep: *stop prompting the agent and design the
system that prompts it — but build it like someone who intends to stay the
engineer, not just the one who presses "go".*

## How it maps to this repo's `ticket` plugin

The `ticket` plugin's fix workflow is a small, disciplined loop, and its parts
line up with the five moves:

- **Worktrees = handoff isolation.** `/ticket-fix` runs each non-trivial fix in
  its own git worktree on a `ticket/NNNN-<slug>` branch, so parallel fixes never
  collide in one directory (the antidote to the tangled loop).
- **The review gate = verification.** An adversarial reviewer (the Codex CLI
  when available, otherwise a Sonnet evaluator subagent) is a *separate* judge
  from the generator, and it assumes the code is broken until proven otherwise —
  the generator/evaluator separation in practice (the antidote to the nodding
  loop).
- **`/ticket-apply` = the human review point.** The loop never merges to your
  branch on its own; landing a fix is a deliberate human step, which keeps the
  "one door open" checkpoint that guards against cognitive surrender.
- **Claim locks + lint = persistence integrity.** Atomic claim locks under
  `.git/ticket-locks/` stop two runs grabbing the same ticket, and
  `ticket-state.sh` lint enforces the frontmatter schema and the
  status↔location invariant. Together they keep the on-disk ticket state
  trustworthy across runs — persistence that the next turn can rely on.

## Reference

- **Title:** *Loop Engineering: The Anthropic Playbook for Designing Systems
  That Prompt Your Agents* (subtitle: *A Field Study of Designing Loops That Run
  Themselves*).
- **Attribution:** ©2026 HuaShu — an independent, conference-style reformatting
  of Addy Osmani's open "Orange Book" guide *Loop Engineering: Stop Asking Me
  What It Is* (v260615, June 2026), huasheng.ai/orange-books. Key sources
  within: Addy Osmani (framework and coinage), Prithvi Rajasekaran / Anthropic
  (generator–evaluator findings), and Steve Kaliski / Stripe (the Minions case).
- **Source URL:**
  <https://drive.google.com/file/d/1qzKI4DKnyHRpXK1J3ATPqwaqLc0iNu-M/view>
  (Google Drive PDF; retrieved 2026-07-03).
