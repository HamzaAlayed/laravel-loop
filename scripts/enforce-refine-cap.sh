#!/usr/bin/env bash
# Enforces the loop protocol's inner-loop refine cap.
#
# The inner loop is Parse -> Plan -> Generate -> Validate -> Refine, and Refine
# is capped: loop-build must stop and return STATUS: blocked after N consecutive
# failing runs of the SAME target rather than keep grinding. Pass N+1 is where
# agents start weakening assertions to reach green — and a tripped cap is
# feedback on the slice, not on the builder, so it belongs back at G1.
#
# Wire as a PostToolUse hook on Bash: unlike PreToolUse this sees the command's
# result, so it counts *failures*, not attempts. A normal TDD rhythm
# (red -> implement -> green) never trips it, because a green run resets the
# counter for that target.
#
# Scoped to subagents. The PostToolUse stdin JSON carries `agent_type` when a
# subagent calls; the main thread has a human watching it and is never counted.
# Requires a host whose hook payload carries agent identity (Claude Code).
#
# Cap is 3. Override with LARAVEL_LOOP_REFINE_CAP=<n>; set to 0 or "off" to
# disable. State lives in .claude/loop-refine-passes.tsv (safe to delete anytime).
#
# Hook receives the tool invocation JSON on stdin; exit 0 to allow, exit 2 to
# feed the escalation notice back to the agent as a blocking error.

set -uo pipefail

INPUT="$(cat)"

CAP="${LARAVEL_LOOP_REFINE_CAP:-3}"
case "$CAP" in
  0|off|OFF|false|FALSE) exit 0 ;;
  *[!0-9]*|'') CAP=3 ;;
esac

# Extract a field from the hook JSON. Degrades jq -> python3 -> empty.
extract() {
  local jq_path="$1" py_expr="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r "$jq_path // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
    v=$py_expr
    print(v if isinstance(v,str) else (json.dumps(v) if v else ''))
except Exception:
    pass" 2>/dev/null || true
  fi
}

AGENT_TYPE="$(extract '.agent_type' 'd.get("agent_type","")')"
COMMAND="$(extract '.tool_input.command' 'd.get("tool_input",{}).get("command","")')"
RESPONSE="$(extract '.tool_response' 'd.get("tool_response","")')"

# No parser available -> raw-payload mode. Screen the whole payload rather than
# failing open, but only when it names a subagent at all.
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  printf '%s' "$INPUT" | grep -qE '"agent_type"[[:space:]]*:[[:space:]]*"[^"]+"' || exit 0
  AGENT_TYPE="subagent"
  COMMAND="$(printf '%s' "$INPUT" | tr '"' ' ')"
  RESPONSE="$COMMAND"
fi

# Main thread (no agent_type) -> never counted.
[ -z "$AGENT_TYPE" ] && exit 0
[ -z "$COMMAND" ] && exit 0

FLAT="$(printf '%s' "$COMMAND" | tr '\n\t' '  ')"

# --- Is this a test run? ----------------------------------------------------
printf '%s' "$FLAT" | grep -qiE '(artisan[ ]+test|(^|[;&|/ ])(pest|phpunit)([ ]|$)|vendor/bin/(pest|phpunit)|(npm|pnpm|yarn)[ ]+(run[ ]+)?test|vitest|jest)' || exit 0

# --- Which target? ----------------------------------------------------------
# --filter=X / --filter X / a trailing test path. Everything else is "suite".
TARGET="$(printf '%s' "$FLAT" | sed -nE 's/.*--filter[= ]+["'"'"']?([A-Za-z0-9_:\\\/.-]+).*/\1/p' | head -1)"
if [ -z "$TARGET" ]; then
  TARGET="$(printf '%s' "$FLAT" | grep -oE '(tests|spec)/[A-Za-z0-9_/.-]+' | head -1)"
fi
[ -z "$TARGET" ] && TARGET="suite"

KEY="$(printf '%s|%s' "$AGENT_TYPE" "$TARGET" | tr -c 'A-Za-z0-9|_:./-' '_')"

# --- Did it fail? -----------------------------------------------------------
# Pest/PHPUnit/vitest all surface a recognisable failure line. Absence of any
# failure marker is treated as green — the guard's bias is to under-count, so a
# false block is far less likely than a missed one.
is_failure() {
  printf '%s' "$RESPONSE" | grep -qiE '(^|[^A-Za-z])(FAIL|FAILED|FAILURES!|ERRORS!)([^A-Za-z]|$)|Tests:[^\n]*(failed|errored)|[0-9]+[ ]+fail(ed|ures?)|Fatal error|PHP Parse error|Assertion.*failed'
}

STATE_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude"
STATE_FILE="$STATE_DIR/loop-refine-passes.tsv"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

read_count() {
  [ -f "$STATE_FILE" ] || { echo 0; return; }
  local n
  n="$(grep -F "$KEY	" "$STATE_FILE" 2>/dev/null | tail -1 | cut -f2)"
  case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac
}

write_count() {
  local n="$1" tmp
  tmp="$(mktemp "${STATE_FILE}.XXXXXX")" || return 0
  if [ -f "$STATE_FILE" ]; then
    grep -vF "$KEY	" "$STATE_FILE" > "$tmp" 2>/dev/null || true
  fi
  printf '%s\t%s\n' "$KEY" "$n" >> "$tmp"
  # Keep the file bounded; these are per-task counters, not history.
  tail -200 "$tmp" > "$STATE_FILE" 2>/dev/null || true
  rm -f "$tmp"
}

if ! is_failure; then
  # Green run -> this target is done refining. Reset so the next task starts clean.
  write_count 0
  exit 0
fi

COUNT="$(read_count)"
COUNT=$((COUNT + 1))
write_count "$COUNT"

[ "$COUNT" -lt "$CAP" ] && exit 0

# --- Cap reached ------------------------------------------------------------
write_count 0   # clear, so the escalation isn't re-fired on the next command
cat >&2 <<EOF
blocked: refine cap reached — $COUNT consecutive failing runs of "$TARGET" by $AGENT_TYPE.

The loop protocol caps the inner refine loop at $CAP passes. Three failures on the
same target means the slice was too coarse or the context too thin — both live
upstream, which is exactly why a fourth attempt at the same brief cannot fix it.

Stop refining. Return now with:
  STATUS   BLOCKED
  DID      what you changed across the $COUNT attempts
  VERIFIED the exact failing assertion + command (evidence, not a claim)
  FLAGS    what you believe is blocking — wrong slice, missing context, bad assumption
  NEXT     the smallest question or decision that would unblock you

Do NOT delete or weaken the test to get green. Raise the slice back to gate G1.

Override for this session: LARAVEL_LOOP_REFINE_CAP=<n> (0 disables).
Reset the counter: rm .claude/loop-refine-passes.tsv
EOF
exit 2
