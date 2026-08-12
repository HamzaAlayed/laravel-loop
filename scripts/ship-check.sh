#!/usr/bin/env bash
# G3 release readiness for laravel-loop itself -- not a downstream project's.
#
# Standing at G3, a maintainer needs one action that says whether THIS plugin
# is releasable, instead of re-running remembered checks by hand and getting
# a different answer on Friday than on Tuesday. The gate set is exactly three,
# hard-coded, in this order -- no discovery, no detection of what a project
# happens to have installed:
#   1. the guardrail test harness (tests/guardrails.test.sh)
#   2. shellcheck over scripts/*.sh
#   3. version consistency across VERSION / plugin.json / marketplace.json
#      (not implemented yet -- see docs/loop/ship-observe-automation/slices.md
#      S2; it honestly reads not-run here, which is the whole point: a gate
#      nobody could run must never read as a gate that passed)
#
# Read-only. No write outside mktemp scratch, no network, no git command that
# mutates. Prints a failing gate's own captured output verbatim and nothing
# else -- no environment dump, no `set -x`, no echo of a variable the gate
# itself did not print.
#
# ship_verdict() is kept as a small, sourceable, pure function (state in,
# "go"/"hold" out) precisely so the aggregation rule -- go only when every
# declared gate reads passed -- is testable on its own, independent of
# whether all three gates have real dispatch behind them yet.

set -uo pipefail

GATE1_STATE=""; GATE1_REASON=""; GATE1_OUTPUT=""
GATE2_STATE=""; GATE2_REASON=""; GATE2_OUTPUT=""
GATE3_STATE=""; GATE3_REASON=""; GATE3_OUTPUT=""

# go iff every state passed in is exactly "passed" -- D2: a gate that cannot
# be run must never let the run read as releasable. Sourceable in isolation.
ship_verdict() {
  local s
  for s in "$@"; do
    if [ "$s" != "passed" ]; then
      printf 'hold\n'
      return 1
    fi
  done
  printf 'go\n'
  return 0
}

gate1_harness() {
  local target="$ROOT/tests/guardrails.test.sh"
  if [ ! -f "$target" ]; then
    GATE1_STATE="not-run"
    GATE1_REASON="tests/guardrails.test.sh missing"
    return
  fi
  local out
  out="$(mktemp)"
  if bash "$target" >"$out" 2>&1; then
    GATE1_STATE="passed"
  else
    GATE1_STATE="failed"
  fi
  GATE1_OUTPUT="$(cat "$out")"
  rm -f "$out"
}

gate2_shellcheck() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    GATE2_STATE="not-run"
    GATE2_REASON="shellcheck not found on PATH"
    return
  fi
  shopt -s nullglob
  local files=("$ROOT"/scripts/*.sh)
  shopt -u nullglob
  if [ "${#files[@]}" -eq 0 ]; then
    GATE2_STATE="not-run"
    GATE2_REASON="no scripts/*.sh files found"
    return
  fi
  local out
  out="$(mktemp)"
  if shellcheck "${files[@]}" >"$out" 2>&1; then
    GATE2_STATE="passed"
  else
    GATE2_STATE="failed"
  fi
  GATE2_OUTPUT="$(cat "$out")"
  rm -f "$out"
}

gate3_version() {
  # S2 implements the real comparison across VERSION, plugin.json, and
  # marketplace.json. Until then this is the honest state, not a guess.
  GATE3_STATE="not-run"
  GATE3_REASON="not yet implemented"
}

print_gate() {
  local n="$1" name="$2" state="$3" reason="$4"
  if [ -n "$reason" ]; then
    printf 'gate %s: %s -- %s (%s)\n' "$n" "$name" "$state" "$reason"
  else
    printf 'gate %s: %s -- %s\n' "$n" "$name" "$state"
  fi
}

show_failure_output() {
  local n="$1" state="$2" output="$3"
  [ "$state" = "failed" ] || return 0
  printf -- '--- gate %s output (verbatim) ---\n' "$n"
  printf '%s\n' "$output"
  printf -- '--- end gate %s output ---\n' "$n"
  echo
}

main() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ship-check: not inside a git work tree -- stopping before running any gate." >&2
    exit 1
  fi

  ROOT="$(git rev-parse --show-toplevel)"

  gate1_harness
  gate2_shellcheck
  gate3_version

  echo "laravel-loop ship-check -- G3 release readiness for this plugin repository."
  echo "Checks laravel-loop's own release readiness only; it is not a check of a"
  echo "downstream Laravel application's gates."
  echo "This run publishes nothing and deploys nothing -- no tag, no push, no"
  echo "GitHub release, no marketplace publish, no version bump."
  echo

  print_gate 1 "guardrail test harness (tests/guardrails.test.sh)" "$GATE1_STATE" "$GATE1_REASON"
  print_gate 2 "shellcheck (scripts/*.sh)" "$GATE2_STATE" "$GATE2_REASON"
  print_gate 3 "version consistency" "$GATE3_STATE" "$GATE3_REASON"
  echo

  show_failure_output 1 "$GATE1_STATE" "$GATE1_OUTPUT"
  show_failure_output 2 "$GATE2_STATE" "$GATE2_OUTPUT"
  show_failure_output 3 "$GATE3_STATE" "$GATE3_OUTPUT"

  local verdict
  verdict="$(ship_verdict "$GATE1_STATE" "$GATE2_STATE" "$GATE3_STATE")"
  echo "verdict: $verdict"

  if [ "$verdict" = "go" ]; then
    exit 0
  fi
  exit 1
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
