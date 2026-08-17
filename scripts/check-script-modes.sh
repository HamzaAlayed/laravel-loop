#!/usr/bin/env bash
# Enforces the run-me-bit rule for scripts/*.sh and tests/*.sh (A2, A5 --
# docs/loop/ship-gate-blind-to-ci/spec.md).
#
# The rule, stated once, copied verbatim from
# docs/loop/ship-gate-blind-to-ci/slices.md's pinned contract table (S4 copies
# the same wording into docs/loop/checks.md -- neither paraphrases it):
#
#   A file matched by scripts/*.sh or tests/*.sh is a library if one of its
#   first 20 lines is exactly
#   "# laravel-loop:sourced-library"; every other such file is a program. A
#   program must be committed at mode 100755. A library must be committed at
#   mode 100644. Any other combination fails, naming the file.
#
# (The marker text above is deliberately not written as its own bare line in
# this header: an exact, unindented, first-20-lines match of that literal is
# what the rule tests for, and this file must classify as a PROGRAM -- it is
# meant to be run directly -- not as a library that happens to describe one.)
#
# Why this exists rather than a second copy of the loop in ci.yml: A4 needs
# the pushed-commit checks and this local check to be structurally unable to
# disagree, and this repository already states that precedent in
# scripts/cost-ledger-lib.sh's own header, about a report and a gate that
# could "silently disagree" if each parsed its input independently.
#
# Mode basis is the COMMITTED mode from `git ls-files -s`, never the
# filesystem's `[ -x ]` -- a `chmod +x` that was never staged must still read
# as non-conforming here, the same way it would on the runner after checkout.
#
# Read-only: no write outside nothing (this script writes nothing at all), no
# network, no mutating git command. Introduces no environment variable, no
# threshold, no exempt list, no escape hatch, no --fix mode (A7) -- verified
# by this file naming no plugin-namespaced configurable anywhere.
#
# bash 3.2 + coreutils only: no mapfile/readarray, no associative arrays, no
# `grep -P`, no GNU-only flags, no jq, no python3.

set -uo pipefail

MARKER='# laravel-loop:sourced-library'

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "not inside a git work tree -- nothing checked" >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel)" || exit 1
cd "$ROOT" || exit 1

FAIL=0

# git ls-files -s prints "<mode> <sha> <stage>\t<path>" per line. Default IFS
# (space/tab/newline) splits it into exactly four fields; `path` absorbs
# whatever remains after the first three, tab included, so a path containing
# spaces still comes through whole.
while read -r mode _sha _stage path; do
  [ -z "${path:-}" ] && continue

  is_library=0
  if head -n 20 "$path" 2>/dev/null | grep -qxF "$MARKER"; then
    is_library=1
  fi

  if [ "$is_library" -eq 1 ]; then
    kind="library"; want="100644"
  else
    kind="program"; want="100755"
  fi

  if [ "$mode" != "$want" ]; then
    FAIL=1
    printf 'wrong mode: %s is a %s (committed %s, expected %s)\n' \
      "$path" "$kind" "$mode" "$want"
  fi
done <<EOF
$(git ls-files -s scripts/*.sh tests/*.sh 2>/dev/null)
EOF

exit "$FAIL"
