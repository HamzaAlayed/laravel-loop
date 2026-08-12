#!/usr/bin/env bash
# Blocks a subagent from committing app code with no test alongside it.
#
# The loop's third slice test says a slice is only well-formed if it is
# independently testable, and loop-build is told to write the test in the same
# slice as the code. This makes that a property of the system: a commit whose
# staged changes touch application code but include no test file is refused.
#
# Scoped to subagents via the PreToolUse payload's `agent_type`. A human on the
# main thread committing whatever they like is a deliberate, visible act; an
# agent quietly shipping untested code is not.
#
# Deliberately narrow — it fires only on `git commit`, only when app code is
# staged, and skips the changes where a test would be noise (migrations-only,
# config, docs, dependency bumps, frontend assets).
#
# Escape hatch: LARAVEL_LOOP_ALLOW_UNTESTED=1 for the genuine exception, and
# the block message names it. A guard with no escape hatch gets disabled
# wholesale the first time it is wrong.
#
# Hook receives the tool invocation JSON on stdin; exit 0 to allow, 2 to block.

set -uo pipefail

INPUT="$(cat)"

case "${LARAVEL_LOOP_ALLOW_UNTESTED:-0}" in
  1|true|TRUE|yes|YES) exit 0 ;;
esac

extract() {
  local jq_path="$1" py_expr="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r "$jq_path // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
    v=$py_expr
    print(v if isinstance(v,str) else '')
except Exception:
    pass" 2>/dev/null || true
  fi
}

AGENT_TYPE="$(extract '.agent_type' 'd.get(\"agent_type\",\"\")')"
COMMAND="$(extract '.tool_input.command' 'd.get(\"tool_input\",{}).get(\"command\",\"\")')"

# No parser available -> raw-payload mode, but only when a subagent is named.
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  printf '%s' "$INPUT" | grep -qE '"agent_type"[[:space:]]*:[[:space:]]*"[^"]+"' || exit 0
  AGENT_TYPE="subagent"
  COMMAND="$(printf '%s' "$INPUT" | tr '"' ' ')"
fi

# Main thread -> allow.
[ -z "$AGENT_TYPE" ] && exit 0
[ -z "$COMMAND" ] && exit 0

FLAT="$(printf '%s' "$COMMAND" | tr '\n\t' '  ')"

# Only `git commit`. Not `git commit --amend --no-edit` on a merge, not log/diff.
printf '%s' "$FLAT" | grep -qE '(^|[;&| ])git[ ]+(-[^ ]+[ ]+)*commit([ ]|$)' || exit 0

# Need a repo to inspect; if git is unavailable or this is not a work tree,
# fail open rather than blocking work the guard cannot reason about.
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

STAGED="$(git diff --cached --name-only 2>/dev/null)"
[ -z "$STAGED" ] && exit 0

# A test anywhere in the staged set satisfies the guard.
if printf '%s' "$STAGED" | grep -qE '(^|/)(tests?|spec)/|[A-Za-z0-9_]+(Test|Spec)\.php$|\.(test|spec)\.(js|ts|jsx|tsx)$'; then
  exit 0
fi

# Application code — the only category that requires a test.
APP_CODE="$(printf '%s' "$STAGED" | grep -E '^(app|src|routes|packages/[^/]+/src)/.*\.php$' || true)"
[ -z "$APP_CODE" ] && exit 0

# Carve-outs where a test would be noise rather than signal.
MEANINGFUL="$(printf '%s' "$APP_CODE" \
  | grep -vE '^app/Providers/[A-Za-z]+ServiceProvider\.php$' \
  | grep -vE '^app/Console/Kernel\.php$' \
  | grep -vE '^app/Http/Kernel\.php$' || true)"
[ -z "$MEANINGFUL" ] && exit 0

echo "blocked: subagent ($AGENT_TYPE) is committing application code with no test staged." >&2
echo "" >&2
echo "staged app code:" >&2
printf '%s\n' "$MEANINGFUL" | sed 's/^/  /' >&2
echo "" >&2
cat >&2 <<'EOF'
A slice is only well-formed if it is independently testable, and the test ships
in the same commit as the code it proves — not in a follow-up that never comes.

Do one of:
  - stage the test that proves this change (the slice named it at G1)
  - if this genuinely needs no test, say why in your return and set
    LARAVEL_LOOP_ALLOW_UNTESTED=1 for this command

Do not weaken or delete an existing test to get past this.
EOF
exit 2
