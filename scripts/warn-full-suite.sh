#!/usr/bin/env bash
# Warns -- never blocks -- when a loop-build subagent runs an unfiltered test
# suite mid-slice, instead of the filtered run skills/laravel-validate/
# SKILL.md prescribes (php artisan test --compact --filter=<Name>, once per
# slice; the full suite once, at integration, not per slice).
#
# Wired PreToolUse deliberately, not PostToolUse: a warning that arrives
# before the run starts can still change the next command a builder issues;
# one that arrives only after the suite has already finished is just a
# receipt of wall-clock already spent, and cannot change anything.
#
# This is the one guard in this repo that advises rather than refuses
# (spec.md FS1): a wrong block would cost more than the suite run it might
# have prevented. Every path below ends in `exit 0` -- it never blocks,
# delays, or alters the command that triggered it, and never exits non-zero.
#
# Scoped to loop-build only (FS2), copying block-untested-commit.sh's
# agent_type idiom: a human on the main thread (empty agent_type) is never
# warned, and loop-verify -- which re-runs the full suite broadly and
# legitimately by design -- is never warned either. Narrowing loop-verify's
# own behaviour is R4.5, out of scope here.
#
# Escape hatch: LARAVEL_LOOP_ALLOW_FULL_SUITE=1, named inline in the warning
# itself (FS3) -- a guard with no visible way out gets disabled wholesale the
# first time it is wrong.
#
# Zero dependency: bash + coreutils, degrading jq -> python3 -> a safe
# no-op. No parser available means no warning and no crash: exit 0 (FS6).
#
# False positives are the failure mode that matters most for a warn-only
# guard (FS5): a command only ever counts as a "full suite run" when it
# actually invokes a recognised test runner -- php artisan test, its
# Sail-prefixed form, or vendor/bin/pest|phpunit, the forms
# skills/laravel-validate/SKILL.md lines 16-40 actually prescribe. A path
# that merely mentions `tests/`, an `ls`, a `grep`, or a `git` command naming
# a test file never matches a runner and is never considered, let alone
# warned on.

set -uo pipefail

INPUT="$(cat)" || exit 0

case "${LARAVEL_LOOP_ALLOW_FULL_SUITE:-0}" in
  1|true|TRUE|yes|YES) exit 0 ;;
esac

HAVE_JQ=0
HAVE_PY=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1
command -v python3 >/dev/null 2>&1 && HAVE_PY=1
if [ "$HAVE_JQ" -eq 0 ] && [ "$HAVE_PY" -eq 0 ]; then
  exit 0
fi

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

AGENT_TYPE="$(extract '.agent_type' 'd.get(\"agent_type\",\"\")')"
COMMAND="$(extract '.tool_input.command' 'd.get(\"tool_input\",{}).get(\"command\",\"\")')"

# Only loop-build is warned (FS2): never the main thread (empty agent_type),
# never loop-verify, which re-runs the full suite broadly by design.
[ "$AGENT_TYPE" = "loop-build" ] || exit 0
[ -z "$COMMAND" ] && exit 0

FLAT="$(printf '%s' "$COMMAND" | tr '\n\t' '  ')"

# Recognised runners only (FS4/FS5): php artisan test (and its Sail-prefixed
# form, since "artisan test" appears verbatim in both), or vendor/bin/pest|
# phpunit. Anything else -- ls, grep, git add of a test file, a path that
# merely contains tests/ -- never matches and is never considered a suite
# run at all.
IS_RUNNER=0
printf '%s' "$FLAT" | grep -qE '(^|[[:space:]/])artisan[[:space:]]+test([^[:alnum:]]|$)' && IS_RUNNER=1
if [ "$IS_RUNNER" -eq 0 ]; then
  printf '%s' "$FLAT" | grep -qE '(^|[[:space:]])(\./)?vendor/bin/(pest|phpunit)([^[:alnum:]]|$)' && IS_RUNNER=1
fi
[ "$IS_RUNNER" -eq 0 ] && exit 0

# Filtered means: --filter, --group, --testsuite, or a path/file argument
# (FS4). Any of these is the scoped, per-slice run the skill prescribes, not
# the full suite -- Sail-prefixed forms are treated identically because the
# check above already normalised them into the same recognised-runner path.
if printf '%s' "$FLAT" | grep -qE -- '--filter([=[:space:]]|$)|--group([=[:space:]]|$)|--testsuite([=[:space:]]|$)'; then
  exit 0
fi

read -ra WORDS <<<"$FLAT"
for w in "${WORDS[@]}"; do
  case "$w" in
    */tests/*|tests/*|*/test/*|test/*|*Test.php|*test.php|*Spec.php|*.spec.*|*.test.*)
      exit 0
      ;;
  esac
done

cat >&2 <<EOF
warn: loop-build is running the whole test suite mid-slice:
  $FLAT

skills/laravel-validate prescribes a filtered run per slice -- e.g.
php artisan test --compact --filter=<Name> -- and the full suite once, at
integration, not per slice. Running the whole suite here costs wall-clock on
every slice.

This is advice, not a block: the command above still runs unchanged. Set
LARAVEL_LOOP_ALLOW_FULL_SUITE=1 to silence this warning if the full run is
genuinely what you mean to do here.
EOF

exit 0
