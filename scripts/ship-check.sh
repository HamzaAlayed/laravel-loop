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
#   3. version consistency across VERSION / plugin.json / marketplace.json --
#      reads VERSION (bare string), plugin.json's top-level "version", and
#      marketplace.json's plugins[0].version, using bash + grep/sed only
#      (jq/python3 are never required, so this gate cannot go not-run for
#      lack of a parser). Reports failed, by name, on any mismatch or any
#      missing/unreadable/fieldless file -- never silently treated as a match.
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

# -- gate 3: version consistency -------------------------------------------
# bash + grep/sed only, deliberately -- jq and python3 may be absent on the
# machine running this, and a version-consistency check that goes not-run
# for lack of a JSON parser would be worse than useless (D2).

# Sets VERSION_READ_V / VERSION_READ_S (value / status) for a bare
# `X.Y.Z` version file, e.g. `VERSION`. Status is one of:
# ok | missing | unreadable | empty (no non-blank content found).
read_bare_version() {
  local f="$1" v
  VERSION_READ_V=""
  if [ ! -e "$f" ]; then VERSION_READ_S="missing"; return; fi
  if [ ! -r "$f" ]; then VERSION_READ_S="unreadable"; return; fi
  v="$(head -n1 "$f" 2>/dev/null | tr -d '[:space:]')"
  if [ -z "$v" ]; then VERSION_READ_S="empty"; return; fi
  VERSION_READ_V="$v"
  VERSION_READ_S="ok"
}

# Sets VERSION_READ_V / VERSION_READ_S for a top-level `"<key>": "..."` in a
# JSON file that has exactly one such key at the top level, e.g.
# plugin.json's "version". grep/sed only.
read_json_top_version() {
  local f="$1" key="$2" v
  VERSION_READ_V=""
  if [ ! -e "$f" ]; then VERSION_READ_S="missing"; return; fi
  if [ ! -r "$f" ]; then VERSION_READ_S="unreadable"; return; fi
  v="$(grep -m1 "\"$key\"[[:space:]]*:" "$f" 2>/dev/null \
    | sed -E "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\\1/")"
  if [ -z "$v" ]; then VERSION_READ_S="empty"; return; fi
  VERSION_READ_V="$v"
  VERSION_READ_S="ok"
}

# Isolates the first element of a top-level `"plugins": [ {...}, ... ]`
# array (i.e. plugins[0]) by counting braces in pure bash, then greps
# "version" inside that isolated block only -- so a decoy "version" that
# appears anywhere else in the file (top level, owner, a later plugin
# entry) is never picked up. No jq, no python3.
extract_plugin0_version() {
  local f="$1"
  # Portable line read, not `mapfile`/`readarray` -- those are bash-4+ and
  # the default /bin/bash on macOS is 3.2.
  local -a lines=()
  local raw_line
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    lines+=("$raw_line")
  done <"$f"

  local i plugins_idx=-1 start_idx=-1 end_idx=-1 depth=0
  for i in "${!lines[@]}"; do
    if [[ "${lines[$i]}" =~ \"plugins\"[[:space:]]*: ]]; then
      plugins_idx=$i
      break
    fi
  done
  [ "$plugins_idx" -ge 0 ] || return 1

  for ((i = plugins_idx; i < ${#lines[@]}; i++)); do
    if [[ "${lines[$i]}" == *"{"* ]]; then
      start_idx=$i
      break
    fi
  done
  [ "$start_idx" -ge 0 ] || return 1

  for ((i = start_idx; i < ${#lines[@]}; i++)); do
    local line="${lines[$i]}" opens closes
    opens="${line//[^\{]/}"
    closes="${line//[^\}]/}"
    depth=$((depth + ${#opens} - ${#closes}))
    if [ "$depth" -le 0 ]; then
      end_idx=$i
      break
    fi
  done
  [ "$end_idx" -ge 0 ] || return 1

  printf '%s\n' "${lines[@]:start_idx:end_idx-start_idx+1}" \
    | grep -m1 '"version"[[:space:]]*:' \
    | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/'
}

# Sets VERSION_READ_V / VERSION_READ_S for marketplace.json's
# plugins[0].version specifically -- never the first "version" string
# the file happens to contain.
read_marketplace_plugin_version() {
  local f="$1" v
  VERSION_READ_V=""
  if [ ! -e "$f" ]; then VERSION_READ_S="missing"; return; fi
  if [ ! -r "$f" ]; then VERSION_READ_S="unreadable"; return; fi
  v="$(extract_plugin0_version "$f" 2>/dev/null)"
  if [ -z "$v" ]; then VERSION_READ_S="empty"; return; fi
  VERSION_READ_V="$v"
  VERSION_READ_S="ok"
}

# Renders a (status, value) pair for the report line -- never blank, never
# implying a match when the read failed.
describe_version_read() {
  case "$1" in
    ok) printf '%s' "$2" ;;
    missing) printf 'MISSING' ;;
    unreadable) printf 'UNREADABLE' ;;
    empty) printf 'NO VERSION FIELD' ;;
    *) printf 'UNKNOWN' ;;
  esac
}

gate3_version() {
  local version_path=".claude-plugin/plugin.json"
  local marketplace_path=".claude-plugin/marketplace.json"

  read_bare_version "$ROOT/VERSION"
  local v_val="$VERSION_READ_V" v_stat="$VERSION_READ_S"

  read_json_top_version "$ROOT/$version_path" "version"
  local p_val="$VERSION_READ_V" p_stat="$VERSION_READ_S"

  read_marketplace_plugin_version "$ROOT/$marketplace_path"
  local m_val="$VERSION_READ_V" m_stat="$VERSION_READ_S"

  GATE3_OUTPUT="$(printf 'VERSION: %s\n%s: %s\n%s: %s' \
    "$(describe_version_read "$v_stat" "$v_val")" \
    "$version_path" "$(describe_version_read "$p_stat" "$p_val")" \
    "$marketplace_path" "$(describe_version_read "$m_stat" "$m_val")")"

  if [ "$v_stat" = "ok" ] && [ "$p_stat" = "ok" ] && [ "$m_stat" = "ok" ] \
    && [ "$v_val" = "$p_val" ] && [ "$p_val" = "$m_val" ]; then
    GATE3_STATE="passed"
    GATE3_OUTPUT=""
    return
  fi

  GATE3_STATE="failed"
  if [ "$v_stat" != "ok" ] || [ "$p_stat" != "ok" ] || [ "$m_stat" != "ok" ]; then
    GATE3_REASON="a version file is missing, unreadable, or has no version field -- see output"
  else
    GATE3_REASON="VERSION, $version_path, and $marketplace_path disagree"
  fi
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
