---
title: ticket-state.sh _pad mis-parses zero-padded numbers with 8/9 as octal
type: bug
priority: high
status: resolved
created: 2026-07-04
updated: 2026-07-04
---

## Description

`scripts/ticket-state.sh`'s `_pad()` normalises a ticket number with
`printf '%04d' "$1"`. Under bash (the script's shebang is `#!/usr/bin/env
bash`), a numeric argument with a leading `0` is parsed as **octal**, so any
zero-padded ticket number containing an `8` or `9` in an octal-significant
position fails:

```
$ printf '%04d' 0008
bash: printf: 0008: invalid octal number      # rc=1, prints 0000
```

Because every state command routes its number through `_pad`
(`claim`/`release`/`transition` at the `nnnn=$(_pad "$1") || die "…: unexpected
arg $1"` lines, plus `status` and number-specific `lint`), the failure makes the
whole state machine reject those tickets:

```
$ ticket-state.sh --dir doc/tickets claim 0008 --owner …
ticket-state.sh: line 60: printf: 0008: invalid octal number
claim: unexpected arg 0008                     # rc=2
```

Affected numbers are `0008`, `0009`, `0018`, `0019`, `0028`, … — every
zero-padded value whose octal reading hits an 8 or 9. `0001`–`0007` happen to be
valid octal, which is why the bug lay dormant until ticket **0008**.

This is a **workflow-blocking, self-perpetuating** bug: it cannot be fixed
through the normal `/ticket-create → /ticket-triage → /ticket-fix` flow, because
`/ticket-fix` must `claim` the ticket, and the next free number (`0009`) is
itself un-claimable. It must be patched by hand to bootstrap out. Surfaced while
running `/ticket-fix 0008`.

## Triage

- Complexity: low
- Mechanical fix: yes
- Requires user decision: no
- Affected files: 2 (`plugins/ticket/scripts/ticket-state.sh` — one line in
  `_pad`; `plugins/ticket/.claude-plugin/plugin.json` — version bump)
- Fix strategy: in-place (one-line change) — but applied by hand, not via
  `/ticket-fix`, because the claim step is exactly what this bug breaks.
- Notes: Root cause is a single expression; scanned the whole script and `_pad`
  line 60 is the only octal-sensitive spot on ticket numbers (the other `$((…))`
  uses are on TTLs / counters / timestamps). Fix forces base-10.

## Resolution

Fixed `_pad` to force base-10 parsing:

```sh
-    *) printf '%04d' "$1" ;;
+    *) printf '%04d' "$((10#$1))" ;;   # 10# forces base-10 so 0008/0009 aren't parsed as octal
```

The `*[!0-9]*` case already filters non-digits, so `$1` is guaranteed
all-digits (or empty, caught by `''`) when the `10#` branch runs.

Verification:
- `bash -n plugins/ticket/scripts/ticket-state.sh` — parses.
- `claim 0088` now reaches the existence check (`rc=4 "not found"`) instead of
  dying at `rc=2 "unexpected arg"`.
- `lint 0008` — no octal error, `0 error(s), 0 warning(s)`.

Bumped `plugins/ticket/.claude-plugin/plugin.json` `version` 0.5.0 → 0.5.1 so a
`/reload-plugins` refreshes the cached copy the skills invoke.

Applied by hand (in-place, direct to the base branch) rather than through
`/ticket-fix`, since the bug blocks the claim step the fix flow depends on.
