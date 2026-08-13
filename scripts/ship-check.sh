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
#
# Every gate that shells out (1 and 2) runs under a per-gate wall-clock bound
# (LARAVEL_LOOP_SHIP_GATE_TIMEOUT seconds, default 120) so a gate that never
# returns produces a hold instead of a hang the human waits on forever. This
# never shells out to `timeout(1)`: that's GNU coreutils, present on the CI
# runner but absent from a stock macOS -- the maintainer's own machine -- so
# relying on it would only hold the guarantee on Linux. It is bash job
# control end to end instead -- see run_bounded() below.
#
# A release-context block (spec S9) reports, alongside the verdict, whether
# the working tree is dirty and whether this unit of work has a contract
# under docs/loop/<slug>/ (and a verify record in it). Context is reported,
# never a fourth gate: it cannot flip go/hold, or S6's "the verdict is a
# function of exactly the three gate results" stops being true. The slug is
# an optional first argument; with none given it is resolved from the
# current branch, and it is never guessed from "the most recent directory".
# Presence or absence is always stated -- "no unit contract found" is
# printed, not omitted, the same discipline the gates apply to `not-run`.

set -uo pipefail

GATE1_STATE=""; GATE1_REASON=""; GATE1_OUTPUT=""
GATE2_STATE=""; GATE2_REASON=""; GATE2_OUTPUT=""
GATE3_STATE=""; GATE3_REASON=""; GATE3_OUTPUT=""

GATE_TIMEOUT="${LARAVEL_LOOP_SHIP_GATE_TIMEOUT:-120}"
case "$GATE_TIMEOUT" in ''|*[!0-9]*) GATE_TIMEOUT=120 ;; esac

# Runs "$@", capturing its combined stdout+stderr into the file named by $1.
# Sets BOUNDED_STATE to "ok" (BOUNDED_EXIT holds the real exit code) or
# "timeout" (killed after $GATE_TIMEOUT seconds without returning;
# BOUNDED_EXIT is 124, matching coreutils `timeout`'s convention).
#
# No `timeout(1)`, `gtimeout`, `setsid`, `perl`, or `python3` anywhere in
# here -- bash job control only. `set -m` inside the inner subshell gives
# the backgrounded command its own process group (pgid == its own pid,
# because job control assigns a fresh group to each job it starts), so on
# timeout `kill -TERM -"$pid"` (the leading `-` addresses the whole group,
# not just that one pid) reaches every descendant a hung gate spawned --
# e.g. a stray `sleep` -- not only its immediate child. That is what leaves
# no orphan behind. The inner subshell's own stdout/stderr are discarded so
# bash's job-control notices ("Terminated") never leak into the gate's
# captured output or this script's own.
run_bounded() {
  local out="$1"; shift
  : >"$out"
  (
    set -m
    "$@" >"$out" 2>&1 &
    echo $! >"$out.pid"
    wait $!
    echo $? >"$out.exit"
  ) >/dev/null 2>/dev/null &
  local runner=$! start
  start="$SECONDS"
  while kill -0 "$runner" 2>/dev/null; do
    if [ $((SECONDS - start)) -ge "$GATE_TIMEOUT" ]; then
      local pgid
      pgid="$(cat "$out.pid" 2>/dev/null || true)"
      if [ -n "$pgid" ]; then
        kill -TERM "-$pgid" 2>/dev/null || true
        sleep 0.3
        kill -KILL "-$pgid" 2>/dev/null || true
      fi
      kill -KILL "$runner" 2>/dev/null || true
      wait "$runner" 2>/dev/null || true
      BOUNDED_STATE="timeout"
      BOUNDED_EXIT=124
      rm -f "$out.pid" "$out.exit"
      return
    fi
    sleep 0.2
  done
  wait "$runner" 2>/dev/null || true
  BOUNDED_STATE="ok"
  BOUNDED_EXIT="$(cat "$out.exit" 2>/dev/null || echo 1)"
  rm -f "$out.pid" "$out.exit"
}

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
  run_bounded "$out" bash "$target"
  if [ "$BOUNDED_STATE" = "timeout" ]; then
    GATE1_STATE="failed"
    GATE1_REASON="timed out after ${GATE_TIMEOUT}s without returning"
  elif [ "$BOUNDED_EXIT" -eq 0 ]; then
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
  # -S warning matches CI (.github/workflows/ci.yml) and every slice's own
  # Done-when bar. Without it, info/style-only notices (e.g. SC1091 on a
  # sourced sibling script, SC2317 on an indirectly-invoked function) fail
  # this gate even though nothing in the project treats them as failures.
  run_bounded "$out" shellcheck -S warning "${files[@]}"
  if [ "$BOUNDED_STATE" = "timeout" ]; then
    GATE2_STATE="failed"
    GATE2_REASON="timed out after ${GATE_TIMEOUT}s without returning"
  elif [ "$BOUNDED_EXIT" -eq 0 ]; then
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

# -- release context: dirty tree + unit contract ---------------------------
# Read-only: `git status --porcelain` and reads under docs/loop/ only. Never
# writes, never influences $GATE*_STATE or the verdict.

# Sets SLUG from $1 if given; otherwise from the current branch. Never
# "HEAD" for a detached checkout -- `symbolic-ref` fails there (empty), and
# an empty SLUG is reported as "no unit contract found" rather than guessed.
resolve_slug() {
  local arg="${1:-}"
  SLUG=""
  if [ -n "$arg" ]; then
    SLUG="$arg"
    return
  fi
  SLUG="$(git -C "$ROOT" symbolic-ref --short -q HEAD 2>/dev/null || true)"
}

# Prints the context block. Presence or absence is always stated, in the
# same words the spec and failure-mode table use, so a human (or a harness
# case) never has to infer a missing line means "clean" or "found".
print_context() {
  local porcelain
  porcelain="$(git -C "$ROOT" status --porcelain 2>/dev/null)"
  if [ -n "$porcelain" ]; then
    echo "context: working tree is dirty -- not what a release would contain"
  fi

  if [ -z "$SLUG" ]; then
    echo "context: no unit contract found -- no slug given and none resolved from the current branch"
    return
  fi

  local unit_dir="$ROOT/docs/loop/$SLUG"
  if [ ! -d "$unit_dir" ]; then
    echo "context: no unit contract found for slug '$SLUG' -- docs/loop/$SLUG/ does not exist"
    return
  fi

  echo "context: unit contract docs/loop/$SLUG/ found"
  if [ -f "$unit_dir/verify.md" ]; then
    echo "context: verify record present -- docs/loop/$SLUG/verify.md"
  else
    echo "context: verify record absent -- no docs/loop/$SLUG/verify.md"
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
  resolve_slug "${1:-}"

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

  print_context
  echo

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
