#!/usr/bin/env bash
# Budget gate: pauses the loop before the NEXT agent spawns, once a human has
# set a per-unit spend threshold and the ledger's priced total for that unit
# has reached it. See docs/loop/cost-reporting-v0.3/spec.md BG1-BG14, CV8.
#
# Wired PreToolUse / `Agent|Task`, deliberately never PostToolUse (hooks/
# hooks.json). A check that only fires after a spawn has already happened
# cannot un-spawn it -- by the time PostToolUse fires, the tokens for that
# invocation are already being spent. The only point where pausing costs
# nothing already committed is BEFORE the next spawn, which is exactly what
# "gate, don't kill" (BG4) requires: nothing already in flight is ever
# interrupted, signalled, or abandoned by this script, under any condition.
#
# No default threshold ships anywhere in this file (G0-D1). With both
# LARAVEL_LOOP_BUDGET_WARN and LARAVEL_LOOP_BUDGET_HARD unset or empty, this
# exits on the very first check below -- before it reads the hook payload,
# the ledger, or anything else -- so a /loop run with no threshold set is
# byte-for-byte indistinguishable from a run with this hook absent entirely
# (BG1). There is no baseline in this repo to derive a number from (spec.md
# E1: the ledger has never held a full run; E2: ~9 of 10 invocations this
# repo has ever recorded carry no token figure at all), and G0-D1 forbids
# guessing one regardless.
#
# An unparseable threshold is a typo, not a missing feature, and the
# likeliest way anyone ever reaches this path is a stray character in a
# number they meant to set. Unlike LARAVEL_LOOP_COST_MAX_LINES
# (record-cost-event.sh), which falls back to a default line count on a bad
# value because a bound failing open is harmless either way, a SPEND gate
# failing open silently on a typo is the false-safety case this must never
# copy (spec.md E9): a bad value disables evaluation for that variable and
# says so loudly, naming the variable and the value, every single time it is
# read. It never falls back to any number.
#
# Lives entirely outside record-cost-event.sh (BG13): that script is
# observe-only by its own v0.2 spec and must never be able to pause a spawn,
# under any condition including its own failure. This script only ever READS
# .claude/loop-cost.jsonl, exclusively through scripts/cost-ledger-lib.sh --
# the identical arithmetic /cost uses -- so a threshold is never compared
# against a second, independently-parsed total (CV7/CV8). Nothing here
# writes to the ledger, to .claude/loop-refine-passes.tsv, or to
# record-cost-event.sh's own state.
#
# A bug in THIS script may never stop work (BG10): an unreadable ledger, no
# jq/python3 on PATH, or an internal error of its own all exit 0 and say
# plainly that the run is proceeding as if no threshold were set. A gate
# that can itself break is worse than a gate that quietly does nothing.
#
# No unfired gate ever reads as "within budget" anywhere in this file (BG6):
# silence here means either no threshold was set, or the observed total
# (which may itself be an undercount -- CV8) has not yet reached it. Neither
# is ever spelled out as reassurance; only the fact that something WAS
# breached, or WILL be told once, is ever printed.
#
# Zero dependency: bash + coreutils, degrading jq -> python3, matching every
# other script in this repo. Neither present -> proceeds as if no threshold
# were set (BG10), the same as any other internal failure.

set -uo pipefail

INPUT="$(cat)" || exit 0

WARN_RAW="${LARAVEL_LOOP_BUDGET_WARN:-}"
HARD_RAW="${LARAVEL_LOOP_BUDGET_HARD:-}"

# BG1 -- the entire point. Both unset/empty: return now, before reading the
# payload, the ledger, or anything else. No evaluation, no message, no FLAG,
# no output of any kind about spend.
if [ -z "$WARN_RAW" ] && [ -z "$HARD_RAW" ]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
LEDGER="$ROOT/.claude/loop-cost.jsonl"

HAVE_JQ=0
HAVE_PY=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1
command -v python3 >/dev/null 2>&1 && HAVE_PY=1

if [ "$HAVE_JQ" -eq 0 ] && [ "$HAVE_PY" -eq 0 ]; then
  echo "budget gate: neither jq nor python3 is on PATH -- cannot evaluate a threshold; proceeding as if no threshold were set." >&2
  exit 0
fi

# shellcheck source=cost-ledger-lib.sh
source "$SCRIPT_DIR/cost-ledger-lib.sh"

extract() {
  local jq_path="$1" py_expr="$2"
  if [ "$HAVE_JQ" -eq 1 ]; then
    printf '%s' "$INPUT" | jq -r "$jq_path // empty" 2>/dev/null
  elif [ "$HAVE_PY" -eq 1 ]; then
    printf '%s' "$INPUT" | python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
    v=$py_expr
    print(v if isinstance(v,str) else '')
except Exception:
    pass" 2>/dev/null || true
  fi
}

HOOK_EVENT="$(extract '.hook_event_name' 'd.get(\"hook_event_name\",\"\")')"
TOOL_NAME="$(extract '.tool_name' 'd.get(\"tool_name\",\"\")')"

# BG4 -- evaluated before the next spawn, and nowhere else. Any other event
# (chiefly PostToolUse's finish signal, which fires mid/after-invocation) or
# any tool other than Agent/Task is not this gate's moment: exit 0 with
# nothing printed, exactly as if this hook were not registered there --
# which, per hooks/hooks.json, it never is.
if [ "$HOOK_EVENT" != "PreToolUse" ]; then
  exit 0
fi
case "$TOOL_NAME" in
  Agent|Task) : ;;
  *) exit 0 ;;
esac

# --- slug: the same `Unit:` line convention record-cost-event.sh reads, so
# the unit this gate evaluates against is always the one the invocation
# itself declares -- never guessed from cwd or a last-seen unit (v0.2 L4). --
PROMPT="$(extract '.tool_input.prompt' 'd.get(\"tool_input\",{}).get(\"prompt\",\"\")')"
DESCRIPTION="$(extract '.tool_input.description' 'd.get(\"tool_input\",{}).get(\"description\",\"\")')"

find_label() {
  local text="$1" label="$2"
  printf '%s\n' "$text" | sed -n -E "/^${label}:[[:space:]]+/{s/^${label}:[[:space:]]+//; s/[[:space:]]+\$//; p; q;}" 2>/dev/null
}

SLUG="$(find_label "$PROMPT" "Unit")"
[ -z "$SLUG" ] && SLUG="$(find_label "$DESCRIPTION" "Unit")"
[ -z "$SLUG" ] && SLUG="unknown"
SLUG="${SLUG:0:200}"

# --- threshold parsing (BG2). Accepted form: a bare non-negative decimal
# integer -- no sign, no decimal point, no exponent, no suffix, no
# surrounding space. Anything else disables that variable's role in this
# evaluation and is reported by name and value; it is never coerced into a
# number nobody chose. -------------------------------------------------------
is_valid_threshold() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

WARN_VALID=0; WARN_VALUE=0
if [ -n "$WARN_RAW" ]; then
  if is_valid_threshold "$WARN_RAW"; then
    WARN_VALID=1
    WARN_VALUE="$WARN_RAW"
  else
    echo "budget gate: LARAVEL_LOOP_BUDGET_WARN=\"$WARN_RAW\" is not a bare non-negative integer -- the warn threshold is DISABLED, not defaulted to any number. Accepted form: digits only, e.g. 150000." >&2
  fi
fi

HARD_VALID=0; HARD_VALUE=0
if [ -n "$HARD_RAW" ]; then
  if is_valid_threshold "$HARD_RAW"; then
    HARD_VALID=1
    HARD_VALUE="$HARD_RAW"
  else
    echo "budget gate: LARAVEL_LOOP_BUDGET_HARD=\"$HARD_RAW\" is not a bare non-negative integer -- the hard gate is DISABLED, not defaulted to any number. Accepted form: digits only, e.g. 400000." >&2
  fi
fi

# BG8 -- reported plainly; resolved by picking neither, and never a reason to
# skip the hard gate below.
if [ "$WARN_VALID" -eq 1 ] && [ "$HARD_VALID" -eq 1 ] && [ "$WARN_VALUE" -gt "$HARD_VALUE" ]; then
  echo "budget gate: misconfiguration -- LARAVEL_LOOP_BUDGET_WARN ($WARN_VALUE) is set above LARAVEL_LOOP_BUDGET_HARD ($HARD_VALUE). Neither value is preferred over the other; fix the thresholds. This does not skip the hard gate below." >&2
fi

# Nothing left to evaluate.
if [ "$WARN_VALID" -eq 0 ] && [ "$HARD_VALID" -eq 0 ]; then
  exit 0
fi

# --- pinned state dir (once-per-unit markers for BG7/BG9, and BG11's
# hard-override). A failure to even create it is treated as an internal
# failure of this gate (BG10): proceed as if no threshold were set rather
# than risk spamming or mis-gating on state it cannot persist. --------------
SLUG_SAFE="$(printf '%s' "$SLUG" | tr -c 'A-Za-z0-9_.-' '_')"
[ -z "$SLUG_SAFE" ] && SLUG_SAFE="unknown"
STATE_DIR="$ROOT/.claude/loop-budget-state/$SLUG_SAFE"
if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
  echo "budget gate: could not create its state directory ($STATE_DIR) -- proceeding as if no threshold were set." >&2
  exit 0
fi

# BG11 -- read-only here (S6 is the writer). A bare integer in
# hard-override RAISES an already-valid HARD for this unit only; with HARD
# unset or unparseable the marker alone never arms anything.
EFFECTIVE_HARD="$HARD_VALUE"
if [ "$HARD_VALID" -eq 1 ] && [ -f "$STATE_DIR/hard-override" ]; then
  OVERRIDE_RAW="$(tr -d '[:space:]' < "$STATE_DIR/hard-override" 2>/dev/null)"
  if is_valid_threshold "$OVERRIDE_RAW" && [ "$OVERRIDE_RAW" -gt "$EFFECTIVE_HARD" ]; then
    EFFECTIVE_HARD="$OVERRIDE_RAW"
  fi
fi

# --- the one and only ledger read (CV7/CV8: never re-parsed, never a second
# implementation of the total). ---------------------------------------------
cost_scan "$LEDGER" "$SLUG"
case "$COST_SCAN_STATE" in
  no-parser|scan-error)
    echo "budget gate: could not read the cost ledger ($COST_SCAN_STATE) -- proceeding as if no threshold were set." >&2
    exit 0
    ;;
esac

TOTAL="${COST_TOKENS_PRICED:-0}"
UNPRICED="${COST_N_UNPRICED:-0}"

# BG9 -- once per unit, independent of whether anything else fires below.
if [ "$UNPRICED" -gt 0 ]; then
  PARTIAL_MARK="$STATE_DIR/partial-coverage-notified"
  if [ ! -f "$PARTIAL_MARK" ]; then
    echo "budget gate: coverage for this unit's comparison is partial -- $(cost_coverage_sentence). Shown once per unit; every comparison below and hereafter is against the priced subset only." >&2
    : > "$PARTIAL_MARK" 2>/dev/null
  fi
fi

# --- BG3/BG5/CV8: the hard breach. Never deduped -- it must keep pausing
# every subsequent spawn until a human resolves it, which is what makes it a
# gate rather than a one-time notice. --------------------------------------
print_breach_message() {
  echo "" >&2
  echo "BUDGET HARD LIMIT REACHED for unit \"$SLUG\"." >&2
  echo "" >&2
  echo "$(cost_coverage_sentence)" >&2
  echo "Priced total: $TOTAL token(s) -- at or above the hard threshold of $EFFECTIVE_HARD token(s)." >&2
  echo "" >&2

  cost_slice_rows "$LEDGER" "$SLUG" >/dev/null
  local top_line="" top_slice="" top_tokens=0 top_inv=0 top_rtokens=0 top_rinv=0
  if [ "${COST_SLICE_UNKNOWN_PRICED:-0}" -gt 0 ] && [ -z "${COST_SLICE_ROWS:-}" ]; then
    echo "Most expensive slice could not be identified -- every priced invocation for this unit carries no slice attribution." >&2
  elif [ "${COST_SLICE_UNKNOWN_PRICED:-0}" -gt 0 ]; then
    echo "Most expensive slice could not be reliably identified -- ${COST_SLICE_UNKNOWN_PRICED} priced invocation(s) carry no slice attribution and could outrank the ranking below." >&2
  elif [ -z "${COST_SLICE_ROWS:-}" ]; then
    echo "Most expensive slice could not be identified -- no priced invocation for this unit carries a slice attribution." >&2
  else
    top_line="$(printf '%s\n' "$COST_SLICE_ROWS" | head -1)"
    IFS=$'\t' read -r top_slice top_tokens top_inv top_rtokens top_rinv <<<"$top_line"
  fi

  if [ -n "$top_line" ]; then
    local rshare
    if [ "$top_rtokens" -gt 0 ] && [ "$top_tokens" -gt 0 ]; then
      rshare="$((top_rtokens * 100 / top_tokens))% ($top_rinv of $top_inv priced invocation(s) reworked)"
    else
      rshare="unavailable (no priced rework in this slice)"
    fi
    echo "Most expensive slice: $top_slice -- $top_tokens token(s), rework share: $rshare" >&2
    echo "" >&2
  fi

  echo "This is a gate, not a kill: any slice already in flight completes; nothing is interrupted. This only pauses the NEXT spawn." >&2
  echo "" >&2
  echo "Choose one:" >&2
  if [ -n "$top_line" ]; then
    echo "  1. (recommended) Re-slice \"$top_slice\" -- it is the largest share of this unit's observed spend." >&2
  else
    echo "  1. (recommended) Re-slice the unit's largest slice once coverage can identify which one that is." >&2
  fi
  echo "  2. Raise the hard cap for this unit only. Does not persist beyond it." >&2
  echo "  3. Stop here and review manually before continuing." >&2
  echo "" >&2
  echo "This returns immediately and waits for no further input -- an unattended run stops here and keeps its artifacts rather than continuing or hanging." >&2
}

if [ "$HARD_VALID" -eq 1 ] && [ "$TOTAL" -ge "$EFFECTIVE_HARD" ]; then
  print_breach_message
  exit 2
fi

# --- BG7: warn fires once per unit and never gates. ------------------------
if [ "$WARN_VALID" -eq 1 ] && [ "$TOTAL" -ge "$WARN_VALUE" ]; then
  WARN_MARK="$STATE_DIR/warn-notified"
  if [ ! -f "$WARN_MARK" ]; then
    {
      echo "budget gate: warn threshold crossed for unit \"$SLUG\"."
      echo "$(cost_coverage_sentence)"
      echo "Priced total: $TOTAL token(s) -- at or above the warn threshold of $WARN_VALUE token(s). This is advice, not a gate: nothing pauses."
    } >&2
    : > "$WARN_MARK" 2>/dev/null
  fi
fi

exit 0
