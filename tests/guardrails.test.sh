#!/usr/bin/env bash
# Zero-dependency test harness for laravel-loop's guardrail scripts.
#
# No bats, no npm, nothing to install — pure bash + coreutils, so this runs
# identically on a contributor's laptop and in CI.
#
#   ./tests/guardrails.test.sh
#
# Exit code is the number of failures (0 = all green).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"

PASS=0
FAIL=0
ALLOW=0
BLOCK=2

run_hook() {
  local script="$1" json="$2"
  printf '%s' "$json" | bash "$SCRIPTS/$script" >/dev/null 2>&1
  echo $?
}

expect() {
  local desc="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1)); printf '  ok   %s\n' "$desc"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %s (expected exit %s, got %s)\n' "$desc" "$want" "$got"
  fi
}

# ---------------------------------------------------------------------------
echo "enforce-refine-cap.sh (inner-loop refine cap)"
CAPDIR="$(mktemp -d)"
fail_json() { printf '{"agent_type":"loop-build","tool_input":{"command":"php artisan test --filter=%s"},"tool_response":"FAIL  Tests\\\\Feature\\\\%s\\n  Tests: 1 failed"}' "$1" "$1"; }
pass_json() { printf '{"agent_type":"loop-build","tool_input":{"command":"php artisan test --filter=%s"},"tool_response":"PASS  Tests\\\\Feature\\\\%s\\n  Tests: 1 passed"}' "$1" "$1"; }
cap() { CLAUDE_PROJECT_DIR="$CAPDIR" run_hook enforce-refine-cap.sh "$1"; }

expect "1st failing run allows"                "$ALLOW" "$(cap "$(fail_json InvoiceTest)")"
expect "2nd failing run allows"                "$ALLOW" "$(cap "$(fail_json InvoiceTest)")"
expect "3rd failing run blocks (cap reached)"  "$BLOCK" "$(cap "$(fail_json InvoiceTest)")"
expect "counter cleared after the block"       "$ALLOW" "$(cap "$(fail_json InvoiceTest)")"

rm -rf "$CAPDIR"; CAPDIR="$(mktemp -d)"
expect "red -> green -> red -> red never trips (normal TDD)" "$ALLOW" \
  "$(cap "$(fail_json TotalTest)" >/dev/null; cap "$(pass_json TotalTest)" >/dev/null; cap "$(fail_json TotalTest)" >/dev/null; cap "$(fail_json TotalTest)")"
expect "different targets counted separately" "$ALLOW" \
  "$(cap "$(fail_json AaaTest)" >/dev/null; cap "$(fail_json BbbTest)" >/dev/null; cap "$(fail_json CccTest)")"
expect "non-test command ignored" "$ALLOW" \
  "$(cap '{"agent_type":"loop-build","tool_input":{"command":"git status"},"tool_response":"FAIL"}')"
expect "MAIN THREAD failures never counted (no agent_type)" "$ALLOW" \
  "$(for _ in 1 2 3 4; do CLAUDE_PROJECT_DIR="$CAPDIR" run_hook enforce-refine-cap.sh '{"tool_input":{"command":"php artisan test --filter=X"},"tool_response":"FAIL Tests: 1 failed"}' >/dev/null; done; CLAUDE_PROJECT_DIR="$CAPDIR" run_hook enforce-refine-cap.sh '{"tool_input":{"command":"php artisan test --filter=X"},"tool_response":"FAIL Tests: 1 failed"}')"

rm -rf "$CAPDIR"; CAPDIR="$(mktemp -d)"
expect "LARAVEL_LOOP_REFINE_CAP=0 disables the guard" "$ALLOW" \
  "$(for _ in 1 2 3 4; do LARAVEL_LOOP_REFINE_CAP=0 cap "$(fail_json ZedTest)" >/dev/null; done; LARAVEL_LOOP_REFINE_CAP=0 cap "$(fail_json ZedTest)")"
rm -rf "$CAPDIR"; CAPDIR="$(mktemp -d)"
expect "LARAVEL_LOOP_REFINE_CAP=2 blocks one pass earlier" "$BLOCK" \
  "$(LARAVEL_LOOP_REFINE_CAP=2 cap "$(fail_json EarlyTest)" >/dev/null; LARAVEL_LOOP_REFINE_CAP=2 cap "$(fail_json EarlyTest)")"
rm -rf "$CAPDIR"

# ---------------------------------------------------------------------------
echo "block-untested-commit.sh (test-with-the-code guard)"
REPO="$(mktemp -d)"
git -C "$REPO" init --quiet
git -C "$REPO" config user.email t@example.test
git -C "$REPO" config user.name test
mkdir -p "$REPO/app/Http/Controllers" "$REPO/app/Providers" "$REPO/tests/Feature" \
         "$REPO/database/migrations" "$REPO/config" "$REPO/docs" "$REPO/resources/js"

commit_json() { printf '{"agent_type":"loop-build","tool_input":{"command":"git commit -m \\"wip\\""}}'; }
stage() { for f in "$@"; do mkdir -p "$REPO/$(dirname "$f")"; printf 'x\n' > "$REPO/$f"; git -C "$REPO" add "$f"; done; }
unstage_all() { git -C "$REPO" reset --quiet 2>/dev/null; rm -rf "${REPO:?}/app" "${REPO:?}/tests"; mkdir -p "$REPO/app/Http/Controllers" "$REPO/app/Providers" "$REPO/tests/Feature"; }
guard() { ( cd "$REPO" && printf '%s' "$(commit_json)" | bash "$SCRIPTS/block-untested-commit.sh" >/dev/null 2>&1; echo $? ); }

stage app/Http/Controllers/InvoiceController.php
expect "app code with no test blocks" "$BLOCK" "$(guard)"

stage tests/Feature/InvoiceTest.php
expect "app code WITH a test allows" "$ALLOW" "$(guard)"

unstage_all
stage database/migrations/2026_01_01_create_invoices_table.php
expect "migration-only allows" "$ALLOW" "$(guard)"

unstage_all
stage config/invoices.php docs/notes.md resources/js/app.js
expect "config + docs + assets allow" "$ALLOW" "$(guard)"

unstage_all
stage app/Providers/AppServiceProvider.php
expect "service-provider-only allows (carve-out)" "$ALLOW" "$(guard)"

unstage_all
stage app/Actions/ChargeInvoice.php
expect "new Action with no test blocks" "$BLOCK" "$(guard)"
expect "LARAVEL_LOOP_ALLOW_UNTESTED=1 escape hatch allows" "$ALLOW" \
  "$( cd "$REPO" && printf '%s' "$(commit_json)" | LARAVEL_LOOP_ALLOW_UNTESTED=1 bash "$SCRIPTS/block-untested-commit.sh" >/dev/null 2>&1; echo $? )"
expect "MAIN THREAD commit allows (no agent_type)" "$ALLOW" \
  "$( cd "$REPO" && printf '{"tool_input":{"command":"git commit -m \"wip\""}}' | bash "$SCRIPTS/block-untested-commit.sh" >/dev/null 2>&1; echo $? )"
expect "non-commit git command ignored" "$ALLOW" \
  "$( cd "$REPO" && printf '{"agent_type":"loop-build","tool_input":{"command":"git status"}}' | bash "$SCRIPTS/block-untested-commit.sh" >/dev/null 2>&1; echo $? )"
expect "nothing staged allows" "$ALLOW" \
  "$( cd "$REPO" && git reset --quiet && printf '%s' "$(commit_json)" | bash "$SCRIPTS/block-untested-commit.sh" >/dev/null 2>&1; echo $? )"

rm -rf "$REPO"

# ---------------------------------------------------------------------------
echo "observe (capture procedure)"
OBSERVE="$ROOT/commands/observe.md"

observe_script_present() {
  local f
  for f in "$SCRIPTS"/*observe* "$SCRIPTS"/*capture*; do
    [ -e "$f" ] && return 0
  done
  return 1
}
expect "observe: no capture script exists — the surface is markdown only" "0" \
  "$( observe_script_present && echo 1 || echo 0 )"

expect "observe: procedure names all five required capture fields" "0" \
  "$( grep -q 'What was observed' "$OBSERVE" \
      && grep -q 'Where it surfaced' "$OBSERVE" \
      && grep -q '## When' "$OBSERVE" \
      && grep -q 'What was already tried' "$OBSERVE" \
      && grep -qi 'suspected unit or commit' "$OBSERVE" \
      && echo 0 || echo 1 )"

expect "observe: procedure records unknown rather than inferring" "0" \
  "$( grep -qi 'unknown' "$OBSERVE" && grep -qi 'is ever inferred' "$OBSERVE" && echo 0 || echo 1 )"

expect "observe: procedure forbids editing an existing unit's spec, slices, or verify" "0" \
  "$( grep -q 'spec.md' "$OBSERVE" && grep -q 'slices.md' "$OBSERVE" && grep -q 'verify.md' "$OBSERVE" \
      && grep -qi 'never opened for writing\|never overwrite\|never touch' "$OBSERVE" \
      && echo 0 || echo 1 )"

expect "observe: procedure refuses a slug collision" "0" \
  "$( grep -qi 'slug' "$OBSERVE" && grep -qi 'collision' "$OBSERVE" \
      && grep -qi 'refuse\|distinct slug' "$OBSERVE" && echo 0 || echo 1 )"

expect "observe: capture carries no acceptance criteria and hands off at G0" "0" \
  "$( grep -qi 'no acceptance criteria' "$OBSERVE" && grep -q 'G0' "$OBSERVE" && echo 0 || echo 1 )"

# ---------------------------------------------------------------------------
echo "ship-check.sh (G3 release readiness)"

# Every case below runs ship-check.sh inside a throwaway git-repo fixture,
# never against this repo's own root: gate 1 IS `bash tests/guardrails.test.sh`,
# i.e. this very file, so pointing ship-check at $ROOT from in here recurses.

SHIP_OUT=""
SHIP_EXIT=0
ship_run() {
  local dir="$1"; shift
  SHIP_OUT="$(cd "$dir" && bash scripts/ship-check.sh "$@" 2>&1)"
  SHIP_EXIT=$?
}

new_ship_fixture() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email t@example.test
  git -C "$dir" config user.name test
  mkdir -p "$dir/scripts" "$dir/tests"
  cp "$SCRIPTS/ship-check.sh" "$dir/scripts/ship-check.sh"
  chmod +x "$dir/scripts/ship-check.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/tests/guardrails.test.sh"
  chmod +x "$dir/tests/guardrails.test.sh"
  printf '#!/usr/bin/env bash\necho clean\n' > "$dir/scripts/clean.sh"
  chmod +x "$dir/scripts/clean.sh"
  git -C "$dir" add -A
  git -C "$dir" commit --quiet -m init
  printf '%s' "$dir"
}

gate_line() { # $1=output $2=gate number
  printf '%s\n' "$1" | grep -E "^gate $2: "
}

SHIP1="$(new_ship_fixture)"
ship_run "$SHIP1"
GATE_LINES="$(printf '%s\n' "$SHIP_OUT" | grep -cE '^gate [0-9]: ')"
expect "ship: summary prints exactly three gate lines" "3" "$GATE_LINES"
rm -rf "$SHIP1"

expect "ship: all runnable gates passing gives go and exit 0" "go 0" \
  "$(bash -c 'source "'"$SCRIPTS"'/ship-check.sh"; v=$(ship_verdict passed passed passed); printf "%s %s" "$v" "$?"')"

SHIP2="$(new_ship_fixture)"
printf '#!/usr/bin/env bash\necho "SHIP-GATE1-SENTINEL-OUTPUT"\nexit 1\n' > "$SHIP2/tests/guardrails.test.sh"
git -C "$SHIP2" add -A
git -C "$SHIP2" commit --quiet -m "break gate 1"
ship_run "$SHIP2"
expect "ship: a failing gate gives hold and non-zero exit" "1" "$SHIP_EXIT"
case "$SHIP_OUT" in
  *SHIP-GATE1-SENTINEL-OUTPUT*) VERBATIM_FOUND="yes" ;;
  *) VERBATIM_FOUND="no" ;;
esac
expect "ship: a failing gate's own output appears verbatim" "yes" "$VERBATIM_FOUND"
rm -rf "$SHIP2"

SHIP3="$(new_ship_fixture)"
SHIP_OUT="$(cd "$SHIP3" && PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash scripts/ship-check.sh 2>&1)"
SHIP_EXIT=$?
G2_STATE="$(gate_line "$SHIP_OUT" 2)"
case "$G2_STATE" in
  *not-run*) G2_NOTRUN="yes" ;;
  *) G2_NOTRUN="no" ;;
esac
case "$SHIP_OUT" in
  *"verdict: hold"*) VERDICT_HOLD="yes" ;;
  *) VERDICT_HOLD="no" ;;
esac
expect "ship: shellcheck absent from PATH reads not-run, verdict hold" "yes yes 1" \
  "$G2_NOTRUN $VERDICT_HOLD $([ "$SHIP_EXIT" -ne 0 ] && echo 1 || echo 0)"
rm -rf "$SHIP3"

SHIP4="$(new_ship_fixture)"
rm -f "$SHIP4/tests/guardrails.test.sh"
ship_run "$SHIP4"
G1_STATE="$(gate_line "$SHIP_OUT" 1)"
case "$G1_STATE" in
  *"not-run"*"tests/guardrails.test.sh"*) G1_NAMED="yes" ;;
  *) G1_NAMED="no" ;;
esac
case "$SHIP_OUT" in
  *"verdict: hold"*) VERDICT_HOLD="yes" ;;
  *) VERDICT_HOLD="no" ;;
esac
expect "ship: a missing gate file reads not-run by name, verdict hold" "yes yes 1" \
  "$G1_NAMED $VERDICT_HOLD $([ "$SHIP_EXIT" -ne 0 ] && echo 1 || echo 0)"
rm -rf "$SHIP4"

SHIP5="$(new_ship_fixture)"
ship_run "$SHIP5"
FIRST_OUT="$SHIP_OUT"; FIRST_EXIT="$SHIP_EXIT"
ship_run "$SHIP5"
SECOND_OUT="$SHIP_OUT"; SECOND_EXIT="$SHIP_EXIT"
FIRST_VERDICT="$(printf '%s\n' "$FIRST_OUT" | grep -E '^verdict: ')"
SECOND_VERDICT="$(printf '%s\n' "$SECOND_OUT" | grep -E '^verdict: ')"
expect "ship: two runs on an unchanged tree give the same verdict and exit code" \
  "$FIRST_VERDICT $FIRST_EXIT" "$SECOND_VERDICT $SECOND_EXIT"

REFS_BEFORE="$(git -C "$SHIP5" show-ref; git -C "$SHIP5" tag; git -C "$SHIP5" status --porcelain)"
ship_run "$SHIP5"
REFS_AFTER="$(git -C "$SHIP5" show-ref; git -C "$SHIP5" tag; git -C "$SHIP5" status --porcelain)"
expect "ship: fixture refs, tags, and porcelain status are byte-identical after a run" \
  "$REFS_BEFORE" "$REFS_AFTER"
rm -rf "$SHIP5"

NOGIT="$(mktemp -d)"
cp "$SCRIPTS/ship-check.sh" "$NOGIT/ship-check.sh"
chmod +x "$NOGIT/ship-check.sh"
SHIP_OUT="$(cd "$NOGIT" && bash ship-check.sh 2>&1)"
SHIP_EXIT=$?
case "$SHIP_OUT" in
  *"not inside a git work tree"*) SAID_SO="yes" ;;
  *) SAID_SO="no" ;;
esac
case "$SHIP_OUT" in
  *"gate 1:"*|*"gate 2:"*|*"gate 3:"*) RAN_A_GATE="yes" ;;
  *) RAN_A_GATE="no" ;;
esac
expect "ship: outside a git work tree it says so and runs no gate" "yes no 1" \
  "$SAID_SO $RAN_A_GATE $([ "$SHIP_EXIT" -ne 0 ] && echo 1 || echo 0)"
rm -rf "$NOGIT"

SHIP6="$(new_ship_fixture)"
ship_run "$SHIP6"
case "$SHIP_OUT" in
  *"publishes nothing and deploys nothing"*) DISCLAIMED="yes" ;;
  *) DISCLAIMED="no" ;;
esac
expect "ship: summary states it publishes and deploys nothing" "yes" "$DISCLAIMED"
rm -rf "$SHIP6"

# ---------------------------------------------------------------------------
echo "manifest + component structure"
structure_check() {
  local bad=0
  python3 - "$ROOT" <<'PY' || bad=1
import json, os, sys
root = sys.argv[1]
m = json.load(open(os.path.join(root, ".claude-plugin", "plugin.json")))
assert m["name"] == "laravel-loop", "plugin name"
assert m["name"].islower() and " " not in m["name"], "kebab-case name"
json.load(open(os.path.join(root, "hooks", "hooks.json")))
for d, ext in (("agents", ".md"), ("commands", ".md")):
    files = [f for f in os.listdir(os.path.join(root, d)) if f.endswith(ext)]
    assert files, d + " empty"
for s in os.listdir(os.path.join(root, "skills")):
    assert os.path.isfile(os.path.join(root, "skills", s, "SKILL.md")), s + " missing SKILL.md"
# every script named in hooks.json exists and is executable
named = set()
for entries in json.load(open(os.path.join(root, "hooks", "hooks.json")))["hooks"].values():
    for e in entries:
        for h in e["hooks"]:
            named.add(h["command"].rsplit("/", 1)[-1])
for n in named:
    p = os.path.join(root, "scripts", n)
    assert os.path.isfile(p), n + " named in hooks.json but missing"
    assert os.access(p, os.X_OK), n + " not executable"
PY
  echo $bad
}
expect "manifest, components, and hook scripts valid" "0" "$(structure_check)"

frontmatter_check() {
  local bad=0
  python3 - "$ROOT" <<'PY' || bad=1
import os, sys
root = sys.argv[1]
for d in ("agents", "commands"):
    for f in sorted(os.listdir(os.path.join(root, d))):
        if not f.endswith(".md"):
            continue
        text = open(os.path.join(root, d, f)).read()
        assert text.startswith("---\n"), d + "/" + f + ": no frontmatter"
        fm = text.split("---\n", 2)[1]
        key = "name:" if d == "agents" else "description:"
        assert key in fm, d + "/" + f + ": missing " + key
for s in sorted(os.listdir(os.path.join(root, "skills"))):
    text = open(os.path.join(root, "skills", s, "SKILL.md")).read()
    assert text.startswith("---\n"), s + ": no frontmatter"
    fm = text.split("---\n", 2)[1]
    assert "name:" in fm and "description:" in fm, s + ": incomplete frontmatter"
PY
  echo $bad
}
expect "agent, command, and skill frontmatter present" "0" "$(frontmatter_check)"

echo
echo "----------------------------------------"
printf 'total: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL GREEN" || echo "FAILURES PRESENT"
exit "$FAIL"
