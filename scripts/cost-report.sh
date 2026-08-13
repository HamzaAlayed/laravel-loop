#!/usr/bin/env bash
# Read-only formatter for `/cost` (commands/cost.md). Prints what
# .claude/loop-cost.jsonl can and cannot see for one unit of work -- or, with
# no argument, one line per unit the ledger holds -- and states that
# coverage before it ever states a total (spec.md CV1). This is the reader:
# it never writes, prunes, rotates, or reshapes the ledger, and it never
# reads a sibling plugin's own separate event feed, the network, or any
# account -- .claude/loop-cost.jsonl and nothing else (CO2). Every figure
# below comes from scripts/cost-ledger-lib.sh, never
# from a second parse of the file here, so a later slice's budget gate can
# never disagree with what this prints (CV7/CV8).
#
# Usage: scripts/cost-report.sh [slug]
#   no slug -- one line per unit in the ledger, most recent first (CO1)
#   a slug  -- that unit's coverage, then its priced-subset total (CV1/CV3)
#
# Always exits 0. A reporting tool that can crash is worse than one that
# plainly says it could not read something (CO3, CO13), and every message
# below goes to stdout so commands/cost.md -- which relays stdout verbatim
# and nothing else -- always has something to show.

set -uo pipefail

ROOT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
LEDGER="$ROOT_DIR/.claude/loop-cost.jsonl"
# Pure bash, deliberately -- no external `dirname` -- so resolving this
# script's own directory never depends on a coreutil being on PATH, even
# before the jq/python3 check below runs (CO13).
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

SLUG="${1:-}"

if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  printf 'Cannot read the cost ledger: neither jq nor python3 is on PATH. Install either one to use /cost.\n'
  exit 0
fi

# shellcheck source=cost-ledger-lib.sh
source "$SCRIPT_DIR/cost-ledger-lib.sh"

print_absent() {
  cat <<'EOF'
No cost ledger found at .claude/loop-cost.jsonl.

Likely causes:
  - the cost-ledger hooks are not wired into this project's settings.json
  - LARAVEL_LOOP_COST_LEDGER=0 (or "off") is disabling the ledger

Nothing has been observed yet -- this is not an error.
EOF
}

print_empty() {
  printf 'The cost ledger exists at .claude/loop-cost.jsonl but holds no records yet.\n'
}

print_no_slug() {
  local slug="$1" present
  printf 'No records for unit "%s" in the cost ledger.\n' "$slug"
  printf '\n'
  printf 'Units present in the ledger:\n'
  present="$(cost_list_slugs "$LEDGER")"
  if [ -z "$present" ]; then
    printf '  (none)\n'
  else
    printf '%s\n' "$present" | while IFS= read -r s; do
      [ -n "$s" ] && printf '  - %s\n' "$s"
    done
  fi
  printf '\n'
  printf 'A typo in the slug and a unit that has not run yet look the same from here --\n'
  printf 'check the name above against docs/loop/<slug>/.\n'
}

# One phase's row for the Coverage section's per-phase split. Uses bash
# indirect expansion (${!name}), never eval, to read the four
# COST_*_<PHASE> variables cost_scan set for $1.
print_phase_row() {
  local phase="$1" label pv_name uv_name iv_name inv_name pv uv iv inv
  label="$(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]')"
  pv_name="COST_N_PRICED_$phase"; uv_name="COST_N_UNPRICED_$phase"
  iv_name="COST_N_INFLIGHT_$phase"; inv_name="COST_N_INVOCATIONS_$phase"
  pv="${!pv_name}"; uv="${!uv_name}"; iv="${!iv_name}"; inv="${!inv_name}"
  if [ "$phase" = "UNKNOWN" ] && [ "$inv" -eq 0 ] && [ "$iv" -eq 0 ]; then
    return 0
  fi
  printf '    %-6s %s/%s priced' "$label" "$pv" "$inv"
  [ "$iv" -gt 0 ] && printf ' (+%s in flight)' "$iv"
  printf ' (%s unpriced)\n' "$uv"
}

print_elapsed() {
  # CO11: labelled elapsed wall-clock, derived only from this unit's own
  # start/finish timestamps -- never a sum of durations, so overlapping
  # (concurrent) invocations are never double-counted into an "agent time"
  # total (E5). COST_TS_MIN/COST_TS_MAX come straight from cost_scan; this
  # never re-reads the ledger.
  printf '  elapsed (wall-clock, first recorded start to last recorded finish; never summed across overlapping invocations): '
  if [ "${COST_TS_MIN:--1}" -lt 0 ] || [ "${COST_TS_MAX:--1}" -lt 0 ] || [ "$COST_TS_MAX" -lt "$COST_TS_MIN" ]; then
    printf 'unavailable\n'
  else
    printf '%s second(s)\n' "$((COST_TS_MAX - COST_TS_MIN))"
  fi
}

print_coverage_and_tokens() {
  printf 'Coverage:\n'
  printf '  %s\n' "$(cost_coverage_sentence)"
  printf '  %s invocation(s) started with no finish recorded yet -- in flight, not counted as unpriced.\n' \
    "$COST_N_INFLIGHT"
  if [ "${COST_N_SKIPPED:-0}" -gt 0 ]; then
    printf '  %s ledger line(s) skipped -- malformed or truncated, not JSON (never silently dropped from this count).\n' \
      "$COST_N_SKIPPED"
  fi
  if [ "${COST_N_CAPTRIP:-0}" -gt 0 ]; then
    printf '  %s cap_trip record(s) excluded from the counts above -- rework markers, not invocations.\n' \
      "$COST_N_CAPTRIP"
  fi
  printf '  per phase (priced/total invocations; in-flight and unpriced called out, never folded together):\n'
  local ph
  for ph in SPEC SLICE BUILD VERIFY UNKNOWN; do
    print_phase_row "$ph"
  done
  print_elapsed
  printf '\n'
  if [ "${COST_N_PRICED:-0}" -eq 0 ]; then
    printf 'Tokens: nothing about this unit'"'"'s token cost is observable -- %s of %s invocations carry a token figure. No token table is printed.\n' \
      "$COST_N_PRICED" "$COST_N_INVOCATIONS"
  else
    printf 'Tokens (priced subset only -- never the unit'"'"'s whole cost):\n'
    printf '  total priced tokens: %s\n' "$(cost_fmt "$COST_TOKENS_PRICED")"
    printf '  %s\n' "$(cost_coverage_sentence)"
    print_cache_read_share
  fi
}

print_cache_read_share() {
  # CV4: unavailable when cache_read_tokens is absent from EVERY priced
  # record -- never "0%", which would read as a catastrophic miss of a
  # target (>40%, requirements doc Sec.10) against a quantity that was
  # simply never measured (v0.2 D1's best-effort field, v0.2 L3).
  if [ "${COST_CACHE_READ_PRICED_N:-0}" -eq 0 ]; then
    printf '  cache-read share: unavailable (cache_read_tokens absent from every priced record)\n'
    return 0
  fi
  local denom="${COST_TOKENS_CACHE_DENOM:-0}"
  if [ "$denom" -le 0 ]; then
    printf '  cache-read share: unavailable (no priced tokens to compare against)\n'
    return 0
  fi
  printf '  cache-read share: %s%% (over the %s priced invocation(s) that reported cache-read data)\n' \
    "$((COST_TOKENS_CACHE_READ * 100 / denom))" "$COST_CACHE_READ_PRICED_N"
}

# --- Phases (CO4): per-phase breakdown of PRICED invocations, with the
# model recorded per phase and `derived` shown wherever model_source is
# derived rather than observed. Only printed when this unit has at least
# one priced invocation at all -- with none, this would be a table of
# "unavailable" rows for every phase, which CV6 forbids exactly as it
# forbids a table of zeros. A phase with priced coverage elsewhere in the
# unit but none of its own still reads "unavailable", never "0" (CO4). ------
format_models() {
  local ph="$1" var raw pair model source out=""
  var="COST_MODELS_$ph"
  raw="${!var}"
  if [ -z "$raw" ]; then
    printf 'unavailable'
    return 0
  fi
  local IFS=,
  for pair in $raw; do
    model="${pair%%::*}"
    source="${pair##*::}"
    [ -n "$out" ] && out="$out, "
    if [ "$source" = "derived" ]; then
      out="${out}${model} (derived)"
    else
      out="${out}${model}"
    fi
  done
  printf '%s' "$out"
}

print_phases() {
  [ "${COST_N_PRICED:-0}" -eq 0 ] && return 0
  printf 'Phases (priced invocations only; model per phase, model_source shown when derived):\n'
  local ph label inv_name
  for ph in SPEC SLICE BUILD VERIFY UNKNOWN; do
    if [ "$ph" = "UNKNOWN" ]; then
      inv_name="COST_N_INVOCATIONS_UNKNOWN"
      [ "${!inv_name}" -eq 0 ] && continue
    fi
    label="$(printf '%s' "$ph" | tr '[:upper:]' '[:lower:]')"
    printf '    %-6s %s\n' "$label" "$(format_models "$ph")"
  done
}

# --- Rework (CO5, CO6, D3): invocation counts always -- computable
# regardless of pricing (E4) -- and a token share only where the rework
# invocations are themselves priced. Each figure labelled as which it is,
# so neither can be mistaken for the other. The wording below is lifted
# from record-cost-event.sh's own header, written there to be lifted. ------
print_rework() {
  printf 'Rework:\n'
  printf '  This measures the cost of slices that were not right first time, at whole-invocation\n'
  printf '  granularity -- not the cost of retrying. An invocation needing even one refine pass has\n'
  printf '  its WHOLE token cost counted as rework, deliberately over-attributing rather than\n'
  printf '  estimating a per-pass split. This is not comparable to the requirements document'"'"'s\n'
  printf '  <15%% target (Sec.10), which was calibrated against a narrower, per-pass definition.\n'
  printf '  No pass/fail verdict against that target is printed here.\n'
  local n="${COST_N_REWORK:-0}" m="${COST_N_INVOCATIONS:-0}" passes="${COST_REWORK_REFINE_PASSES:-}"
  if [ -n "$passes" ]; then
    printf '  count: %s of %s invocation(s) marked rework (refine passes: %s)\n' "$n" "$m" "$passes"
  else
    printf '  count: %s of %s invocation(s) marked rework\n' "$n" "$m"
  fi
  if [ "${COST_REWORK_HAS_AMBIGUOUS:-0}" -eq 1 ]; then
    printf '  at least one rework marking above carries rework_attribution: ambiguous -- shown as ambiguous, never as definite.\n'
  fi
  local rp="${COST_N_REWORK_PRICED:-0}"
  if [ "$rp" -gt 0 ] && [ "${COST_TOKENS_PRICED:-0}" -gt 0 ]; then
    printf '  token share: %s%% of priced tokens (%s of %s priced invocation(s) marked rework)\n' \
      "$((COST_TOKENS_REWORK_PRICED * 100 / COST_TOKENS_PRICED))" "$rp" "${COST_N_PRICED:-0}"
  else
    printf '  token share: unavailable (no priced invocations are marked rework)\n'
  fi
}

# --- Slices + Flags (CO7): top priced slices, and the >30%-concentration
# flag -- printed only where slice-level coverage supports the comparison.
# Where a priced invocation carries no slice at all, ranking would silently
# under-count whichever slice that tokens actually belonged to, so this
# says the comparison could not be assessed instead of guessing (CO7). -----
print_slices_and_flags() {
  if [ "${COST_N_PRICED:-0}" -eq 0 ]; then
    printf 'Slices: no priced invocations for this unit -- nothing to rank by cost.\n'
    printf '\n'
    printf 'Flags:\n'
    printf '  concentration could not be assessed -- no priced invocations to rank.\n'
    return 0
  fi

  # Called directly, never through command substitution: cost_slice_rows
  # sets COST_SLICE_UNKNOWN_PRICED/COST_SLICE_ROWS as side effects, and
  # command substitution would run it in a subshell that discards them.
  cost_slice_rows "$LEDGER" "$SLUG" >/dev/null
  local rows="$COST_SLICE_ROWS" unknown="${COST_SLICE_UNKNOWN_PRICED:-0}"

  printf 'Slices (top by priced tokens, priced subset only):\n'
  if [ -z "$rows" ]; then
    printf '  no slice attributed to any priced invocation.\n'
  else
    printf '%s\n' "$rows" | while IFS=$'\t' read -r slice tokens inv _rtoks rinv; do
      [ -z "$slice" ] && continue
      printf '  %-20s %s tokens (%s priced invocation(s), %s reworked)\n' "$slice" "$tokens" "$inv" "$rinv"
    done
  fi

  printf '\n'
  printf 'Flags:\n'
  if [ "$unknown" -gt 0 ]; then
    printf '  concentration could not be assessed -- %s priced invocation(s) carry no slice attribution.\n' "$unknown"
    return 0
  fi
  if [ -z "$rows" ]; then
    printf '  (no flags raised)\n'
    return 0
  fi
  local top_slice top_tokens flagged=0
  top_slice="$(printf '%s\n' "$rows" | head -1 | cut -f1)"
  top_tokens="$(printf '%s\n' "$rows" | head -1 | cut -f2)"
  if [ -n "$top_slice" ] && [ "${COST_TOKENS_PRICED:-0}" -gt 0 ]; then
    if [ $((top_tokens * 100)) -gt $((COST_TOKENS_PRICED * 30)) ]; then
      printf '  %s is %s%% of this unit'"'"'s priced total -- above the 30%% concentration threshold.\n' \
        "$top_slice" "$((top_tokens * 100 / COST_TOKENS_PRICED))"
      flagged=1
    fi
  fi
  [ "$flagged" -eq 0 ] && printf '  (no flags raised)\n'
}

# --- Budget (CO12): states configuration, evaluates nothing. Deciding
# anything against these thresholds is S4's job (check-budget-gate.sh);
# this only ever shows what a human would discover they set or did not. ----
print_budget() {
  local warn="${LARAVEL_LOOP_BUDGET_WARN:-}" hard="${LARAVEL_LOOP_BUDGET_HARD:-}"
  printf 'Budget:\n'
  if [ -z "$warn" ] && [ -z "$hard" ]; then
    printf '  no threshold is set (LARAVEL_LOOP_BUDGET_WARN, LARAVEL_LOOP_BUDGET_HARD are both unset) -- nothing will gate.\n'
    return 0
  fi
  printf '  LARAVEL_LOOP_BUDGET_WARN=%s\n' "${warn:-not set}"
  printf '  LARAVEL_LOOP_BUDGET_HARD=%s\n' "${hard:-not set}"
}

print_list() {
  local slugs s
  slugs="$(cost_list_slugs "$LEDGER")"
  if [ -z "$slugs" ]; then
    printf 'No units recorded in the cost ledger yet.\n'
    return 0
  fi
  printf 'Units in the cost ledger (most recent first):\n'
  printf '%s\n' "$slugs" | while IFS= read -r s; do
    [ -z "$s" ] && continue
    cost_scan "$LEDGER" "$s"
    printf '  %-40s %s\n' "$s" "$(cost_coverage_sentence)"
  done
}

if [ ! -f "$LEDGER" ]; then
  print_absent
  exit 0
fi
if [ ! -s "$LEDGER" ]; then
  print_empty
  exit 0
fi

if [ -z "$SLUG" ]; then
  print_list
  exit 0
fi

cost_scan "$LEDGER" "$SLUG"
case "$COST_SCAN_STATE" in
  absent) print_absent ;;
  empty) print_empty ;;
  no-slug) print_no_slug "$SLUG" ;;
  no-parser) printf 'Cannot read the cost ledger: neither jq nor python3 is on PATH. Install either one to use /cost.\n' ;;
  scan-error) printf 'Could not read the cost ledger (parse error). Nothing is reported, rather than a partial or wrong total.\n' ;;
  ok)
    print_coverage_and_tokens
    printf '\n'
    print_phases
    [ "${COST_N_PRICED:-0}" -gt 0 ] && printf '\n'
    print_rework
    printf '\n'
    print_slices_and_flags
    printf '\n'
    print_budget
    ;;
  *) printf 'Could not read the cost ledger.\n' ;;
esac

exit 0
