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
  printf '\n'
  if [ "${COST_N_PRICED:-0}" -eq 0 ]; then
    printf 'Tokens: nothing about this unit'"'"'s token cost is observable -- %s of %s invocations carry a token figure. No token table is printed.\n' \
      "$COST_N_PRICED" "$COST_N_INVOCATIONS"
  else
    printf 'Tokens (priced subset only -- never the unit'"'"'s whole cost):\n'
    printf '  total priced tokens: %s\n' "$(cost_fmt "$COST_TOKENS_PRICED")"
    printf '  %s\n' "$(cost_coverage_sentence)"
  fi
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
  ok) print_coverage_and_tokens ;;
  *) printf 'Could not read the cost ledger.\n' ;;
esac

exit 0
