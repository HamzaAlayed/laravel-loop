#!/usr/bin/env bash
# The transcription entry point: writes ONE event:"recovered" record for an
# invocation the host never priced -- typically one launched in the
# background and never observed again (record-cost-event.sh's
# "async_launched" status). This is the ONLY writer of that event type in the
# whole plugin. See docs/loop/cost-ledger-blind-to-background-agents/spec.md
# RC1-RC7 and slices.md's "Pinned contracts for the RC group" for the design
# this mirrors.
#
#   scripts/record-recovered-cost.sh --invocation-id <id> --total-tokens <n>
#
# Standalone CLI. NOT registered in hooks/hooks.json, never invoked by a
# hook, never reachable from a tool payload -- RC7's own words. This script
# never runs unless a human or an agent types the command by hand; nothing
# here can pause, delay, or steer a spawn, because nothing here is wired into
# the spawn path at all. record-cost-event.sh (the ledger's ONLY hook-wired
# writer) is not edited by this file's existence, not even to share a helper
# -- the two scripts duplicate a handful of small conventions on purpose (see
# below) rather than factor out a shared library that would put a second
# caller on record-cost-event.sh's own code.
#
# Both arguments are transcribable from a single <task-notification> block:
# a real one on this machine carries <tool-use-id>toolu_...</tool-use-id>
# alongside <usage><subagent_tokens>NNN</subagent_tokens>...</usage>, and
# record-cost-event.sh already uses tool_use_id AS invocation_id. So there is
# no slug, slice, agent, or recency selector here, ever -- exactly one
# invocation_id, typed by whoever read the figure off that block, or nothing
# is written at all.
#
# Every failure mode below is a REFUSAL, not an error: nothing is written,
# nothing is fabricated, one line goes to stderr, and the exit code is
# always 0 -- cost accounting must never be a reason a command appears to
# have failed. Refuses on: LARAVEL_LOOP_COST_LEDGER=0/off (the v0.2 switch,
# honoured identically here); a missing or empty --invocation-id or
# --total-tokens; a --total-tokens that is not a plain non-negative integer
# (empty, non-numeric, or negative -- a leading '-' is itself a non-digit
# character, so the same single check rejects all three, exactly the
# discipline record-cost-event.sh's own num_or_null() uses); no JSON parser
# available; and an --invocation-id that this ledger has no start/finish
# record for at all (RC4 -- nothing fabricated for an invocation nobody
# here has ever heard of).
#
# "Does this invocation_id exist, and under which slug" is answered through
# scripts/cost-ledger-lib.sh's cost_invocation_lookup() -- a dedicated
# single-pass scan added there for exactly this question, alongside its
# existing cost_scan/cost_list_slugs/cost_slice_rows -- never a second,
# bespoke parse of the ledger written here. The slug this script writes is
# always the one the ledger already holds for that invocation; nothing about
# phase, status, model, duration, or slice is ever copied forward or
# inferred, per the RC group's pinned record shape:
#   {"ts":<int>,"event":"recovered","invocation_id":"<id>","slug":"<slug>",
#    "total_tokens":<int>,"token_source":"transcribed"}
# No other field, ever -- reusing event:"finish" here would be unsafe by
# inspection (cost-ledger-lib.sh's finish branch assigns tokens last-wins,
# so a second finish record could silently overwrite an observed figure).
# A distinct event type leaves that branch untouched entirely.
#
# Exactly-once (RC1), mirroring record-cost-event.sh's own finish-marker
# discipline exactly: `mkdir "$FINISHED_DIR/_recovered/<sanitised id>"` is
# atomic across processes on any POSIX filesystem, so "has this invocation
# already been recovered" is answered by one syscall, no lock file, no
# spin-wait. A second recovery attempt for an id already marked is discarded
# silently, exit 0 -- the note on a real <task-notification> block that "the
# same task-id may notify more than once" makes a second transcription
# expected, not hypothetical. This lives in its OWN namespace
# (`_recovered/`, not the plain `$FINISHED_DIR/<id>` a normal finish already
# claims) because that plain name is already taken by the async_launched
# finish itself -- reusing it would refuse every recovery outright. Already
# covered by this repo's existing "loop-cost-finished/" .gitignore entry, so
# no new ignore entry is needed.
#
# Same bounded-append discipline as the ledger writer (append_and_evict()
# below is the same shape as record-cost-event.sh's, kept independent on
# purpose -- see the no-shared-helper note above): one atomic in-memory-
# assembled `>>` write per record, and the same LARAVEL_LOOP_COST_MAX_LINES
# oldest-first eviction via a `mkdir`-based mutex (no flock -- absent on
# macOS by default, and this repo is bash + coreutils only).
#
# A holder killed by a CATCHABLE signal -- INT (a Ctrl-C at this prompt),
# TERM, or HUP -- releases the lock itself before dying (S3): it traps
# those three, checks that it is the one that created
# .claude/loop-cost-evict.lock, and rmdir's it before exiting 0, the same
# hygiene as record-cost-event.sh's. A holder that dies by an UNCATCHABLE
# route instead -- KILL, an OOM kill, a power loss, or the machine-sleep
# class this repository has actually recorded (docs/loop/conventions.md)
# and has not established to be in the catchable class -- still leaves the
# lock behind exactly as it would in record-cost-event.sh, and from then on
# the cap is not enforced again in either writer for as long as that
# directory exists. This is not fixed, only narrowed to the kill classes a
# signal handler cannot see: the remedy today is still a human removing
# .claude/loop-cost-evict.lock by hand, once no run is active.
#
# Zero new dependency: jq -> python3 -> a safe no-op (no parser -> refuse,
# nothing written). Exits 0 on every path, including its own internal
# errors: a broken recovery attempt must never look like a failed command.

set -uo pipefail

refuse() {
  printf 'record-recovered-cost.sh: %s\n' "$1" >&2
  exit 0
}

case "${LARAVEL_LOOP_COST_LEDGER:-}" in
  0|off|OFF|false|FALSE) refuse "cost ledger disabled (LARAVEL_LOOP_COST_LEDGER)" ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
DIR="$ROOT/.claude"
OUT="$DIR/loop-cost.jsonl"
FINISHED_DIR="$DIR/loop-cost-finished"
RECOVERED_DIR="$FINISHED_DIR/_recovered"
EVICT_LOCK="$DIR/loop-cost-evict.lock"

# Ownership flag + catchable-signal release (S3, spec.md SL3/SL5/SL8) --
# identical in shape to record-cost-event.sh's, kept independent on purpose
# (see the no-shared-helper note above): set the instant THIS process's own
# mkdir "$EVICT_LOCK" succeeds, cleared the instant this process's own
# rmdir runs, so the handler is a no-op in any process that never became
# the lock's holder -- including one still polling for it to clear, or one
# that lost the race to mkdir it. No identity is ever written INSIDE the
# lock directory (rmdir fails on a non-empty directory, which would break
# every release below) -- this flag lives only in this process's own
# memory. No EXIT trap: an unconditional release on exit could rmdir a
# lock a DIFFERENT process acquired in the window after this one already
# released its own.
_evict_lock_owned=0
_release_evict_lock_on_signal() {
  if [ "$_evict_lock_owned" -eq 1 ]; then
    rmdir "$EVICT_LOCK" 2>/dev/null
    _evict_lock_owned=0
  fi
  exit 0
}
trap _release_evict_lock_on_signal INT TERM HUP

# Bound parser (same shape as record-cost-event.sh's and
# enforce-refine-cap.sh's CAP parser): default 5000, non-numeric falls back
# to it rather than disabling the bound or crashing.
MAX_LINES="${LARAVEL_LOOP_COST_MAX_LINES:-5000}"
case "$MAX_LINES" in
  ''|*[!0-9]*) MAX_LINES=5000 ;;
esac

INVOCATION_ID=""
TOTAL_TOKENS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --invocation-id)
      INVOCATION_ID="${2:-}"
      shift 2 2>/dev/null || shift $#
      ;;
    --total-tokens)
      TOTAL_TOKENS="${2:-}"
      shift 2 2>/dev/null || shift $#
      ;;
    *)
      shift
      ;;
  esac
done

[ -n "$INVOCATION_ID" ] || refuse "missing required argument --invocation-id"

# Non-negative integer only: empty, any non-digit character (including a
# leading '-' for a negative figure, or a decimal point), all fail this one
# check -- the same shape as record-cost-event.sh's num_or_null().
case "$TOTAL_TOKENS" in
  ''|*[!0-9]*) refuse "missing, non-numeric, or negative --total-tokens" ;;
esac

HAVE_JQ=0
HAVE_PY=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1
command -v python3 >/dev/null 2>&1 && HAVE_PY=1
if [ "$HAVE_JQ" -eq 0 ] && [ "$HAVE_PY" -eq 0 ]; then
  refuse "no JSON parser available (need jq or python3)"
fi

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
LIB="$LIB_DIR/cost-ledger-lib.sh"
if [ -z "$LIB_DIR" ] || [ ! -f "$LIB" ]; then
  refuse "cost-ledger-lib.sh not found"
fi
# shellcheck source=/dev/null
source "$LIB"

# RC4: an invocation this ledger has never heard of gets nothing fabricated
# for it. cost_invocation_lookup() itself tolerates an absent/empty ledger
# (COST_INVOCATION_FOUND stays 0), so no separate existence check is needed
# here -- "no ledger" and "no matching record" refuse identically.
cost_invocation_lookup "$OUT" "$INVOCATION_ID"
[ "$COST_INVOCATION_FOUND" = "1" ] || refuse "invocation_id not found in ledger: $INVOCATION_ID"

SLUG="$COST_INVOCATION_SLUG"
[ -z "$SLUG" ] && SLUG="unknown"

# Exactly-once (RC1): its own namespace under FINISHED_DIR, distinct from the
# plain per-id marker a normal finish already claims -- see header.
SAFE_ID="$(printf '%s' "$INVOCATION_ID" | tr -c 'A-Za-z0-9_.-' '_')"
SAFE_ID="${SAFE_ID:0:200}"
[ -z "$SAFE_ID" ] && SAFE_ID="unknown"

if ! mkdir -p "$RECOVERED_DIR" 2>/dev/null; then
  refuse "cannot create recovery marker directory"
fi
if ! mkdir "$RECOVERED_DIR/$SAFE_ID" 2>/dev/null; then
  # Already recovered once for this invocation_id -- a second transcription
  # of the same task-id is expected, not an error. Discard silently.
  exit 0
fi

TS="$(date +%s)"

LINE=""
if [ "$HAVE_JQ" -eq 1 ]; then
  LINE="$(jq -nc \
    --argjson ts "$TS" \
    --arg invocation_id "$INVOCATION_ID" \
    --arg slug "$SLUG" \
    --argjson total_tokens "$TOTAL_TOKENS" \
    '{ts:$ts, event:"recovered", invocation_id:$invocation_id, slug:$slug,
      total_tokens:$total_tokens, token_source:"transcribed"}' 2>/dev/null)"
elif [ "$HAVE_PY" -eq 1 ]; then
  LINE="$(python3 - "$TS" "$INVOCATION_ID" "$SLUG" "$TOTAL_TOKENS" <<'PY' 2>/dev/null
import json, sys

ts, invocation_id, slug, total_tokens = sys.argv[1:5]
record = {
    "ts": int(ts),
    "event": "recovered",
    "invocation_id": invocation_id,
    "slug": slug,
    "total_tokens": int(total_tokens),
    "token_source": "transcribed",
}
print(json.dumps(record, separators=(",", ":")))
PY
)"
fi

if [ -z "$LINE" ]; then
  # An internal parser failure after the marker was claimed: release the
  # marker so a later, working attempt is not refused by this one's own
  # dedup (RC4/RC7 -- an internal error must never leave a permanent block).
  rmdir "$RECOVERED_DIR/$SAFE_ID" 2>/dev/null
  exit 0
fi

# --- append + bound: same mechanism as record-cost-event.sh's
# append_and_evict(), reimplemented independently here rather than sourced or
# extracted into a shared helper (see header note on why the two writers do
# not share code). --------------------------------------------------------
append_and_evict() {
  local line="$1"
  [ -z "$line" ] && return 0
  local backoff=0
  while [ -d "$EVICT_LOCK" ] && [ "$backoff" -lt 5 ]; do
    sleep 0.02
    backoff=$((backoff + 1))
  done

  mkdir -p "$DIR" 2>/dev/null || return 0
  printf '%s\n' "$line" >> "$OUT" 2>/dev/null

  if mkdir "$EVICT_LOCK" 2>/dev/null; then
    _evict_lock_owned=1
    local attempt=0 count tmp
    while [ "$attempt" -lt 5 ]; do
      attempt=$((attempt + 1))
      count="$(wc -l < "$OUT" 2>/dev/null | tr -d ' ')"
      case "$count" in ''|*[!0-9]*) break ;; esac
      [ "$count" -le "$MAX_LINES" ] && break
      tmp="$(mktemp "$OUT.evict.XXXXXX" 2>/dev/null)" || break
      if ! tail -n "$MAX_LINES" "$OUT" > "$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        break
      fi
      mv -f "$tmp" "$OUT" 2>/dev/null || rm -f "$tmp"
    done
    rmdir "$EVICT_LOCK" 2>/dev/null
    _evict_lock_owned=0
  fi
  return 0
}

append_and_evict "$LINE"

exit 0
