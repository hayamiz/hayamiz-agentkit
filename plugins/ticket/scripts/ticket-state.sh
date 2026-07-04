#!/usr/bin/env bash
# ticket-state.sh — race-safe state machine for the `ticket` plugin.
#
# Single entry point for ticket status changes and locking. Portable across
# Linux and macOS: atomic locking uses mkdir (no flock dependency) and the
# script avoids bash 4+ features (no associative arrays, no ${var,,}).
#
# Locks live under the shared git common dir so they are visible to every
# worktree of the same clone; they are never committed. This protects
# concurrency WITHIN a single clone (multiple worktrees + local sessions).
# Cross-clone / cloud-vs-local coordination is out of scope — that relies on
# git merge-conflict detection plus the /ticket-apply human gate.
#
# Usage:
#   ticket-state.sh --dir <ticket-dir> <subcommand> [args]
#
# Subcommands:
#   claim      NNNN --owner <id> [--worktree <path>] [--branch <name>]
#   release    NNNN --owner <id> [--force]
#   transition NNNN --from <status> --to <status> [--move]
#   status     [NNNN]
#   lint       [NNNN|--all] [--fix]
#
# Exit codes:
#   0 success   2 usage/error   3 lock held by another owner
#   4 not claimable (resolved/blocked/missing)   5 transition 'from' mismatch
#   6 lint found hard errors

set -u

PROG=${0##*/}

TICKET_DIR=${TICKET_DIR:-}
DEFAULT_TTL=7200 # seconds (2h)

VALID_STATUS="open in-progress blocked awaiting-review ready-to-apply resolved"
VALID_TYPE="bug feature enhancement refactor docs test chore"
VALID_PRIORITY="critical high medium low"

die()  { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }
warn() { printf '%s: warning: %s\n' "$PROG" "$*" >&2; }

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

_now()   { date +%s; }
_today() { date +%F; }

_lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# membership test: _contains <word> <space-separated-list>
_contains() {
  case " $2 " in *" $1 "*) return 0;; *) return 1;; esac
}

_pad() {
  case $1 in
    ''|*[!0-9]*) printf '%s' "$1" ;;
    *) printf '%04d' "$((10#$1))" ;;   # 10# forces base-10 so 0008/0009 aren't parsed as octal
  esac
}

_git_common_dir() {
  local gcd
  gcd=$(git rev-parse --git-common-dir 2>/dev/null) || die "not inside a git repository"
  case $gcd in
    /*) printf '%s' "$gcd" ;;
    *)  ( cd "$gcd" && pwd ) ;;
  esac
}

_lock_root() { printf '%s/ticket-locks' "$(_git_common_dir)"; }

# _ticket_file NNNN -> prints path, or returns 1
_ticket_file() {
  local n=$1 f
  for f in "$TICKET_DIR/$n"-*.md; do
    [ -e "$f" ] && { printf '%s' "$f"; return 0; }
  done
  for f in "$TICKET_DIR/resolved/$n"-*.md; do
    [ -e "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

# _fm_get <file> <key> -> value from the first frontmatter block (trimmed)
_fm_get() {
  awk -v k="$2" '
    NR==1 && $0!="---" { exit }
    NR==1 { infm=1; next }
    infm && $0=="---" { exit }
    infm {
      if ($0 ~ "^"k":[ \t]*") {
        sub("^"k":[ \t]*", "")
        sub("[ \t]+$", "")
        print
        exit
      }
    }
  ' "$1"
}

# lock TTL in seconds: from "Lock TTL:" in <dir>/CLAUDE.md, else default.
# accepts bare seconds or combinations of <n>h <n>m <n>s (e.g. 2h, 1h30m, 90s).
_ttl() {
  local raw sec=0 n unit rest
  raw=$(grep -iE '^Lock TTL:' "$TICKET_DIR/CLAUDE.md" 2>/dev/null | head -1 \
        | sed -E 's/^[Ll]ock [Tt][Tt][Ll]:[ \t]*//')
  [ -z "$raw" ] && { printf '%s' "$DEFAULT_TTL"; return; }
  if printf '%s' "$raw" | grep -qE '^[0-9]+$'; then printf '%s' "$raw"; return; fi
  rest=$raw
  while printf '%s' "$rest" | grep -qE '^[0-9]+[hms]'; do
    n=$(printf '%s' "$rest" | sed -E 's/^([0-9]+)[hms].*/\1/')
    unit=$(printf '%s' "$rest" | sed -E 's/^[0-9]+([hms]).*/\1/')
    case $unit in
      h) sec=$((sec + n * 3600)) ;;
      m) sec=$((sec + n * 60)) ;;
      s) sec=$((sec + n)) ;;
    esac
    rest=$(printf '%s' "$rest" | sed -E 's/^[0-9]+[hms]//')
  done
  [ "$sec" -gt 0 ] && printf '%s' "$sec" || printf '%s' "$DEFAULT_TTL"
}

_meta_get() { # <lockdir> <key>
  [ -f "$1/meta" ] || return 0
  grep "^$2=" "$1/meta" 2>/dev/null | head -1 | cut -d= -f2-
}

_write_meta() { # <lockdir> <owner> <worktree> <branch>
  {
    printf 'owner=%s\n' "$2"
    printf 'ts=%s\n' "$(_now)"
    printf 'worktree=%s\n' "$3"
    printf 'branch=%s\n' "$4"
  } > "$1/meta.tmp" && mv "$1/meta.tmp" "$1/meta"
}

_acquire_txn() { # <txndir>
  local i=0
  until mkdir "$1" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -gt 50 ] && die "could not acquire transition lock: $1"
    sleep 0.1
  done
}
_release_txn() { rmdir "$1" 2>/dev/null || true; }

_mv() { # move a ticket file, preserving git history when tracked
  if git ls-files --error-unmatch "$1" >/dev/null 2>&1; then
    git mv -f "$1" "$2"
  else
    mv "$1" "$2"
  fi
}

# ---------------------------------------------------------------- claim
cmd_claim() {
  local nnnn="" owner="" wt="" branch=""
  while [ $# -gt 0 ]; do
    case $1 in
      --owner)    owner=$2; shift 2 ;;
      --worktree) wt=$2; shift 2 ;;
      --branch)   branch=$2; shift 2 ;;
      -*) die "claim: unknown flag $1" ;;
      *)  [ -z "$nnnn" ] && nnnn=$(_pad "$1") || die "claim: unexpected arg $1"; shift ;;
    esac
  done
  [ -n "$nnnn" ]  || die "claim: ticket number required"
  [ -n "$owner" ] || die "claim: --owner required"

  local file status
  file=$(_ticket_file "$nnnn") || { echo "not-claimable: ticket $nnnn not found" >&2; exit 4; }
  status=$(_fm_get "$file" status)
  if [ "$status" = resolved ] || [ "$status" = blocked ]; then
    echo "not-claimable: ticket $nnnn is $status" >&2
    exit 4
  fi

  local root lock; root=$(_lock_root); mkdir -p "$root"; lock="$root/$nnnn"
  if mkdir "$lock" 2>/dev/null; then
    _write_meta "$lock" "$owner" "$wt" "$branch"
    echo "claimed $nnnn by $owner"
    return 0
  fi

  local cur_owner cur_ts cur_wt age ttl stale=0
  cur_owner=$(_meta_get "$lock" owner)
  if [ "$cur_owner" = "$owner" ]; then
    _write_meta "$lock" "$owner" "$wt" "$branch"
    echo "already-owned $nnnn by $owner"
    return 0
  fi
  cur_ts=$(_meta_get "$lock" ts); cur_wt=$(_meta_get "$lock" worktree)
  ttl=$(_ttl); age=$(( $(_now) - ${cur_ts:-0} ))
  if [ "${cur_ts:-0}" -gt 0 ] && [ "$age" -gt "$ttl" ]; then stale=1; fi
  if [ -n "$cur_wt" ] && [ ! -d "$cur_wt" ]; then stale=1; fi
  if [ "$stale" = 1 ]; then
    warn "stealing stale lock on $nnnn (was '$cur_owner', age ${age}s)"
    _write_meta "$lock" "$owner" "$wt" "$branch"
    echo "claimed $nnnn by $owner (stolen)"
    return 0
  fi
  echo "held: ticket $nnnn is locked by '$cur_owner' (age ${age}s)" >&2
  exit 3
}

# ---------------------------------------------------------------- release
cmd_release() {
  local nnnn="" owner="" force=0
  while [ $# -gt 0 ]; do
    case $1 in
      --owner) owner=$2; shift 2 ;;
      --force) force=1; shift ;;
      -*) die "release: unknown flag $1" ;;
      *)  [ -z "$nnnn" ] && nnnn=$(_pad "$1") || die "release: unexpected arg $1"; shift ;;
    esac
  done
  [ -n "$nnnn" ] || die "release: ticket number required"

  local root lock; root=$(_lock_root); lock="$root/$nnnn"
  [ -d "$lock" ] || { echo "no lock on $nnnn"; return 0; }
  local cur_owner; cur_owner=$(_meta_get "$lock" owner)
  if [ "$force" = 1 ] || [ "$cur_owner" = "$owner" ]; then
    rm -rf "$lock"
    echo "released $nnnn"
    return 0
  fi
  echo "cannot release $nnnn: owned by '$cur_owner' (use --force)" >&2
  exit 3
}

# ---------------------------------------------------------------- transition
_set_status() { # <file> <newstatus>  (rewrites status + updated atomically)
  local f=$1 st=$2 today; today=$(_today)
  awk -v st="$st" -v today="$today" '
    NR==1 && $0=="---" { infm=1; print; next }
    infm && $0=="---"  { infm=0; print; next }
    infm && /^status:/  { print "status: " st;    next }
    infm && /^updated:/ { print "updated: " today; next }
    { print }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

_relocate() { # <file> <newstatus> -> prints resulting path
  local f=$1 to=$2 base dest; base=${f##*/}
  if [ "$to" = resolved ]; then
    dest="$TICKET_DIR/resolved/$base"
    [ "$f" = "$dest" ] && { printf '%s' "$f"; return; }
    mkdir -p "$TICKET_DIR/resolved"
    _mv "$f" "$dest" >&2
  else
    dest="$TICKET_DIR/$base"
    [ "$f" = "$dest" ] && { printf '%s' "$f"; return; }
    _mv "$f" "$dest" >&2
  fi
  printf '%s' "$dest"
}

cmd_transition() {
  local nnnn="" from="" to="" move=0
  while [ $# -gt 0 ]; do
    case $1 in
      --from) from=$2; shift 2 ;;
      --to)   to=$2; shift 2 ;;
      --move) move=1; shift ;;
      -*) die "transition: unknown flag $1" ;;
      *)  [ -z "$nnnn" ] && nnnn=$(_pad "$1") || die "transition: unexpected arg $1"; shift ;;
    esac
  done
  [ -n "$nnnn" ] || die "transition: ticket number required"
  [ -n "$from" ] || die "transition: --from required"
  [ -n "$to" ]   || die "transition: --to required"
  _contains "$to" "$VALID_STATUS"   || die "transition: invalid --to '$to'"
  _contains "$from" "$VALID_STATUS" || die "transition: invalid --from '$from'"

  local file cur; file=$(_ticket_file "$nnnn") || die "transition: ticket $nnnn not found"
  cur=$(_fm_get "$file" status)
  if [ "$cur" != "$from" ]; then
    echo "transition: ticket $nnnn is '$cur', not '$from'" >&2
    exit 5
  fi

  local root txn; root=$(_lock_root); mkdir -p "$root"; txn="$root/.txn-$nnnn"
  _acquire_txn "$txn"
  _set_status "$file" "$to"
  local newfile=$file
  [ "$move" = 1 ] && newfile=$(_relocate "$file" "$to")
  _release_txn "$txn"

  if [ "$newfile" != "$file" ]; then
    echo "transitioned $nnnn: $from -> $to ($newfile)"
  else
    echo "transitioned $nnnn: $from -> $to"
  fi
}

# ---------------------------------------------------------------- status
cmd_status() {
  local only="${1:-}"; [ -n "$only" ] && only=$(_pad "$only")
  local root lock nnnn owner ts wt br age ttl flag any=0
  root=$(_lock_root)
  [ -d "$root" ] || { echo "no active locks"; return 0; }
  ttl=$(_ttl)
  for lock in "$root"/*/; do
    [ -d "$lock" ] || continue
    nnnn=${lock%/}; nnnn=${nnnn##*/}
    case $nnnn in .txn-*) continue ;; esac
    [ -n "$only" ] && [ "$only" != "$nnnn" ] && continue
    owner=$(_meta_get "$lock" owner); ts=$(_meta_get "$lock" ts)
    wt=$(_meta_get "$lock" worktree); br=$(_meta_get "$lock" branch)
    age=$(( $(_now) - ${ts:-0} )); flag=""
    [ "${ts:-0}" -gt 0 ] && [ "$age" -gt "$ttl" ] && flag="$flag STALE"
    [ -n "$wt" ] && [ ! -d "$wt" ] && flag="$flag DEAD-WORKTREE"
    printf '%s  owner=%s  age=%ss  branch=%s%s\n' \
      "$nnnn" "${owner:-?}" "$age" "${br:-–}" "$flag"
    any=1
  done
  [ "$any" = 0 ] && echo "no active locks"
  return 0
}

# ---------------------------------------------------------------- lint
cmd_lint() {
  local only="" fix=0
  while [ $# -gt 0 ]; do
    case $1 in
      --all) shift ;;
      --fix) fix=1; shift ;;
      -*) die "lint: unknown flag $1" ;;
      *)  only=$(_pad "$1"); shift ;;
    esac
  done

  local files f base nnnn type prio status created updated
  local errors=0 warnings=0 numbers=""
  files=""
  for f in "$TICKET_DIR"/*.md "$TICKET_DIR"/resolved/*.md; do
    [ -e "$f" ] || continue
    case ${f##*/} in CLAUDE.md) continue ;; esac
    [ -n "$only" ] && { case ${f##*/} in "$only"-*) ;; *) continue ;; esac; }
    files="$files $f"
  done

  for f in $files; do
    base=${f##*/}
    if ! printf '%s' "$base" | grep -qE '^[0-9]{4}-[a-z0-9]+(-[a-z0-9]+)*\.md$'; then
      echo "ERROR $base: filename must be NNNN-<kebab-subject>.md"; errors=$((errors + 1))
    fi
    nnnn=${base%%-*}; numbers="$numbers $nnnn"

    if [ "$(head -1 "$f")" != "---" ]; then
      echo "ERROR $base: missing YAML frontmatter"; errors=$((errors + 1)); continue
    fi

    type=$(_fm_get "$f" type); prio=$(_fm_get "$f" priority)
    status=$(_fm_get "$f" status)
    created=$(_fm_get "$f" created); updated=$(_fm_get "$f" updated)
    [ -n "$(_fm_get "$f" title)" ] || { echo "ERROR $base: missing 'title'"; errors=$((errors + 1)); }
    [ -n "$type" ]    || { echo "ERROR $base: missing 'type'"; errors=$((errors + 1)); }
    [ -n "$prio" ]    || { echo "ERROR $base: missing 'priority'"; errors=$((errors + 1)); }
    [ -n "$status" ]  || { echo "ERROR $base: missing 'status'"; errors=$((errors + 1)); }
    [ -n "$created" ] || { echo "ERROR $base: missing 'created'"; errors=$((errors + 1)); }
    [ -n "$updated" ] || { echo "ERROR $base: missing 'updated'"; errors=$((errors + 1)); }

    # optional safe repair: normalize enum casing
    if [ "$fix" = 1 ]; then
      if [ -n "$type" ] && _contains "$(_lc "$type")" "$VALID_TYPE" && [ "$type" != "$(_lc "$type")" ]; then
        _fm_fix "$f" type "$(_lc "$type")"; type=$(_lc "$type"); echo "FIXED $base: type -> $type"
      fi
      if [ -n "$prio" ] && _contains "$(_lc "$prio")" "$VALID_PRIORITY" && [ "$prio" != "$(_lc "$prio")" ]; then
        _fm_fix "$f" priority "$(_lc "$prio")"; prio=$(_lc "$prio"); echo "FIXED $base: priority -> $prio"
      fi
    fi

    [ -z "$type" ] || _contains "$type" "$VALID_TYPE" || { echo "ERROR $base: invalid type '$type'"; errors=$((errors + 1)); }
    [ -z "$prio" ] || _contains "$prio" "$VALID_PRIORITY" || { echo "ERROR $base: invalid priority '$prio'"; errors=$((errors + 1)); }
    [ -z "$status" ] || _contains "$status" "$VALID_STATUS" || { echo "ERROR $base: invalid status '$status'"; errors=$((errors + 1)); }
    for d in "$created" "$updated"; do
      [ -z "$d" ] && continue
      printf '%s' "$d" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || { echo "ERROR $base: date not YYYY-MM-DD: '$d'"; errors=$((errors + 1)); }
    done

    # status <-> location invariant
    case "$f" in
      */resolved/*)
        if [ "$status" != resolved ]; then
          if [ "$fix" = 1 ]; then
            _mv "$f" "$TICKET_DIR/$base" >&2; echo "FIXED $base: moved out of resolved/ (status=$status)"
          else
            echo "ERROR $base: in resolved/ but status='$status'"; errors=$((errors + 1))
          fi
        fi
        ;;
      *)
        if [ "$status" = resolved ]; then
          if [ "$fix" = 1 ]; then
            mkdir -p "$TICKET_DIR/resolved"; _mv "$f" "$TICKET_DIR/resolved/$base" >&2
            echo "FIXED $base: moved into resolved/ (status=resolved)"
          else
            echo "ERROR $base: status=resolved but not under resolved/"; errors=$((errors + 1))
          fi
        fi
        ;;
    esac
  done

  # duplicate ticket numbers
  local dupes
  dupes=$(printf '%s\n' $numbers | sort | uniq -d)
  if [ -n "$dupes" ]; then
    echo "ERROR: duplicate ticket numbers:" $dupes; errors=$((errors + 1))
  fi

  # lock consistency (orphan / stale)
  local root lock ln ts age ttl
  root=$(_lock_root); ttl=$(_ttl)
  if [ -d "$root" ]; then
    for lock in "$root"/*/; do
      [ -d "$lock" ] || continue
      ln=${lock%/}; ln=${ln##*/}
      case $ln in .txn-*) continue ;; esac
      if ! _ticket_file "$ln" >/dev/null; then
        echo "WARN: orphan lock $ln (no matching ticket)"; warnings=$((warnings + 1))
      fi
      ts=$(_meta_get "$lock" ts); age=$(( $(_now) - ${ts:-0} ))
      [ "${ts:-0}" -gt 0 ] && [ "$age" -gt "$ttl" ] && { echo "WARN: stale lock $ln (age ${age}s > ttl ${ttl}s)"; warnings=$((warnings + 1)); }
    done
  fi

  echo "lint: $errors error(s), $warnings warning(s)"
  [ "$errors" -gt 0 ] && exit 6
  return 0
}

_fm_fix() { # <file> <key> <value>  (rewrite a single frontmatter scalar in place)
  local f=$1 k=$2 v=$3
  awk -v k="$k" -v v="$v" '
    NR==1 && $0=="---" { infm=1; print; next }
    infm && $0=="---"  { infm=0; print; next }
    infm && $0 ~ "^"k":" { print k ": " v; next }
    { print }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# ---------------------------------------------------------------- main
SUB=""
while [ $# -gt 0 ]; do
  case $1 in
    --dir)   TICKET_DIR=$2; shift 2 ;;
    --dir=*) TICKET_DIR=${1#--dir=}; shift ;;
    -h|--help) usage; exit 0 ;;
    claim|release|transition|status|lint) SUB=$1; shift; break ;;
    *) die "unknown option or command: $1 (try --help)" ;;
  esac
done
[ -n "$SUB" ] || { usage; exit 2; }

TICKET_DIR=${TICKET_DIR%/}
[ -n "$TICKET_DIR" ] || die "--dir <ticket-dir> (or TICKET_DIR env) is required"
[ -d "$TICKET_DIR" ] || die "ticket directory not found: $TICKET_DIR"

case $SUB in
  claim)      cmd_claim "$@" ;;
  release)    cmd_release "$@" ;;
  transition) cmd_transition "$@" ;;
  status)     cmd_status "$@" ;;
  lint)       cmd_lint "$@" ;;
esac
