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

# Writes VERSION / plugin.json / marketplace.json into a fixture dir with
# the given values, so gate 3 has something real to read. marketplace.json
# always carries a decoy top-level "version" key (real marketplace.json
# schema has none, per S5, but the reader must not assume that -- it must
# still land on plugins[0].version, not the first "version" string in the
# file) ahead of the real plugins[0] entry.
write_ship_versions() {
  local dir="$1" version="$2" plugin_version="$3" market_version="$4"
  mkdir -p "$dir/.claude-plugin"
  printf '%s\n' "$version" > "$dir/VERSION"
  cat > "$dir/.claude-plugin/plugin.json" <<JSON
{
  "name": "fixture-plugin",
  "version": "$plugin_version"
}
JSON
  cat > "$dir/.claude-plugin/marketplace.json" <<JSON
{
  "name": "fixture-marketplace",
  "version": "9.9.9",
  "plugins": [
    {
      "name": "fixture-plugin",
      "source": "./",
      "version": "$market_version"
    }
  ]
}
JSON
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
  write_ship_versions "$dir" "0.2.0" "0.2.0" "0.2.0"
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

SHIP7="$(new_ship_fixture)"
ship_run "$SHIP7"
G3_STATE="$(gate_line "$SHIP_OUT" 3)"
case "$G3_STATE" in
  *"passed"*) G3_PASSED="yes" ;;
  *) G3_PASSED="no" ;;
esac
case "$SHIP_OUT" in
  *"verdict: go"*) VERDICT_GO="yes" ;;
  *) VERDICT_GO="no" ;;
esac
expect "ship: three agreeing versions pass the version gate" "yes yes 0" \
  "$G3_PASSED $VERDICT_GO $SHIP_EXIT"
rm -rf "$SHIP7"

SHIP8="$(new_ship_fixture)"
write_ship_versions "$SHIP8" "0.2.0" "0.2.0" "0.1.9"
git -C "$SHIP8" add -A
git -C "$SHIP8" commit --quiet -m "disagree"
ship_run "$SHIP8"
G3_STATE="$(gate_line "$SHIP_OUT" 3)"
case "$G3_STATE" in
  *"failed"*) G3_FAILED="yes" ;;
  *) G3_FAILED="no" ;;
esac
case "$SHIP_OUT" in
  *"verdict: hold"*) VERDICT_HOLD="yes" ;;
  *) VERDICT_HOLD="no" ;;
esac
NAMES_ALL_THREE="no"
case "$SHIP_OUT" in
  *"VERSION: 0.2.0"*)
    case "$SHIP_OUT" in
      *".claude-plugin/plugin.json: 0.2.0"*)
        case "$SHIP_OUT" in
          *".claude-plugin/marketplace.json: 0.1.9"*) NAMES_ALL_THREE="yes" ;;
        esac
        ;;
    esac
    ;;
esac
expect "ship: a disagreeing version file gives hold and names all three files with values" \
  "yes yes yes 1" "$G3_FAILED $VERDICT_HOLD $NAMES_ALL_THREE $SHIP_EXIT"
rm -rf "$SHIP8"

SHIP9="$(new_ship_fixture)"
rm -f "$SHIP9/VERSION"
git -C "$SHIP9" add -A
git -C "$SHIP9" commit --quiet -m "drop VERSION"
ship_run "$SHIP9"
case "$SHIP_OUT" in
  *"VERSION: MISSING"*) NAMED_MISSING="yes" ;;
  *) NAMED_MISSING="no" ;;
esac
case "$SHIP_OUT" in
  *"verdict: hold"*) VERDICT_HOLD="yes" ;;
  *) VERDICT_HOLD="no" ;;
esac
expect "ship: a missing version file gives hold and names it" "yes yes 1" \
  "$NAMED_MISSING $VERDICT_HOLD $SHIP_EXIT"
rm -rf "$SHIP9"

SHIP10="$(new_ship_fixture)"
cat > "$SHIP10/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture-plugin"
}
JSON
git -C "$SHIP10" add -A
git -C "$SHIP10" commit --quiet -m "drop plugin.json version field"
ship_run "$SHIP10"
case "$SHIP_OUT" in
  *".claude-plugin/plugin.json: NO VERSION FIELD"*) NAMED_NO_FIELD="yes" ;;
  *) NAMED_NO_FIELD="no" ;;
esac
case "$SHIP_OUT" in
  *"verdict: hold"*) VERDICT_HOLD="yes" ;;
  *) VERDICT_HOLD="no" ;;
esac
expect "ship: a version field absent from plugin.json gives hold, not a match" "yes yes 1" \
  "$NAMED_NO_FIELD $VERDICT_HOLD $SHIP_EXIT"
rm -rf "$SHIP10"

# marketplace.json's fixture (write_ship_versions) always plants a decoy
# top-level "version" ahead of the real plugins[0].version -- proves the
# reader is scoped to the plugin entry, not "first match in the file".
SHIP11="$(new_ship_fixture)"
ship_run "$SHIP11"
case "$SHIP_OUT" in
  *"verdict: go"*) DECOY_IGNORED="yes" ;;
  *) DECOY_IGNORED="no" ;;
esac
expect "ship: marketplace version is read from the plugin entry, not the first match" \
  "yes" "$DECOY_IGNORED"
rm -rf "$SHIP11"

SHIP12="$(new_ship_fixture)"
SHIP_OUT="$(cd "$SHIP12" && PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash scripts/ship-check.sh 2>&1)"
SHIP_EXIT=$?
G3_STATE="$(gate_line "$SHIP_OUT" 3)"
case "$G3_STATE" in
  *"passed"*) G3_PASSED_NO_TOOLS="yes" ;;
  *) G3_PASSED_NO_TOOLS="no" ;;
esac
expect "ship: version gate works with jq and python3 unavailable on PATH" \
  "yes" "$G3_PASSED_NO_TOOLS"
rm -rf "$SHIP12"

# -- S3: per-gate wall-clock bound ------------------------------------------
# A stub gate 1 that never returns (`sleep 600`) must still yield a verdict.
# LARAVEL_LOOP_SHIP_GATE_TIMEOUT is set low so the case itself stays fast;
# the "600" is only ever the *asked-for* sleep -- the bound must cut it off
# long before it elapses.
hang_gate1_fixture() {
  local dir
  dir="$(new_ship_fixture)"
  printf '#!/usr/bin/env bash\nsleep 600\n' > "$dir/tests/guardrails.test.sh"
  git -C "$dir" add -A
  git -C "$dir" commit --quiet -m "hang gate 1"
  printf '%s' "$dir"
}

SHIP13="$(hang_gate1_fixture)"
START_TS="$(date +%s)"
SHIP_OUT="$(cd "$SHIP13" && LARAVEL_LOOP_SHIP_GATE_TIMEOUT=2 bash scripts/ship-check.sh 2>&1)"
SHIP_EXIT=$?
END_TS="$(date +%s)"
ELAPSED=$((END_TS - START_TS))
case "$SHIP_OUT" in
  *"verdict: hold"*) HANG_HOLD="yes" ;;
  *) HANG_HOLD="no" ;;
esac
expect "ship: a gate that never returns is bounded and gives hold" "yes 1 yes" \
  "$HANG_HOLD $([ "$SHIP_EXIT" -ne 0 ] && echo 1 || echo 0) $([ "$ELAPSED" -le 15 ] && echo yes || echo no)"

G1_STATE="$(gate_line "$SHIP_OUT" 1)"
case "$G1_STATE" in
  *"passed"*) TIMEOUT_READS_PASSED="yes" ;;
  *) TIMEOUT_READS_PASSED="no" ;;
esac
expect "ship: a timed-out gate never prints as passed" "no" "$TIMEOUT_READS_PASSED"
rm -rf "$SHIP13"

SHIP14="$(hang_gate1_fixture)"
START_TS="$(date +%s)"
SHIP_OUT="$(cd "$SHIP14" && LARAVEL_LOOP_SHIP_GATE_TIMEOUT=2 PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash scripts/ship-check.sh 2>&1)"
SHIP_EXIT=$?
END_TS="$(date +%s)"
ELAPSED=$((END_TS - START_TS))
case "$SHIP_OUT" in
  *"verdict: hold"*) NOPATH_HOLD="yes" ;;
  *) NOPATH_HOLD="no" ;;
esac
expect "ship: the bound holds with timeout(1) absent from PATH" "yes 1 yes" \
  "$NOPATH_HOLD $([ "$SHIP_EXIT" -ne 0 ] && echo 1 || echo 0) $([ "$ELAPSED" -le 15 ] && echo yes || echo no)"
rm -rf "$SHIP14"

SHIP15="$(hang_gate1_fixture)"
( cd "$SHIP15" && LARAVEL_LOOP_SHIP_GATE_TIMEOUT=2 bash scripts/ship-check.sh >/dev/null 2>&1 )
sleep 1
ORPHAN_COUNT="$(pgrep -f "sleep 600" | wc -l | tr -d ' ')"
expect "ship: no orphan child survives a timed-out run" "0" "$ORPHAN_COUNT"
rm -rf "$SHIP15"

# -- S4: release-context block (dirty tree + unit contract) ----------------
# Context is reported, it never changes the verdict (spec S6) -- every case
# below re-derives the verdict/exit from the same fixture with and without
# the context-triggering change and asserts they are identical.

SHIP16="$(new_ship_fixture)"
ship_run "$SHIP16"
CLEAN_VERDICT="$(printf '%s\n' "$SHIP_OUT" | grep -E '^verdict: ')"
CLEAN_EXIT="$SHIP_EXIT"
: > "$SHIP16/untracked-file.txt"
ship_run "$SHIP16"
DIRTY_VERDICT="$(printf '%s\n' "$SHIP_OUT" | grep -E '^verdict: ')"
case "$SHIP_OUT" in
  *"working tree is dirty"*) DIRTY_REPORTED="yes" ;;
  *) DIRTY_REPORTED="no" ;;
esac
expect "ship: a dirty fixture tree is reported and the verdict is unchanged" \
  "yes $CLEAN_VERDICT $CLEAN_EXIT" "$DIRTY_REPORTED $DIRTY_VERDICT $SHIP_EXIT"
rm -rf "$SHIP16"

SHIP17="$(new_ship_fixture)"
mkdir -p "$SHIP17/docs/loop/demo"
printf '# spec\n' > "$SHIP17/docs/loop/demo/spec.md"
printf '# verify\n' > "$SHIP17/docs/loop/demo/verify.md"
git -C "$SHIP17" add -A
git -C "$SHIP17" commit --quiet -m "add demo unit with a verify record"
ship_run "$SHIP17" demo
case "$SHIP_OUT" in
  *"docs/loop/demo/"*) NAMED_SLUG="yes" ;;
  *) NAMED_SLUG="no" ;;
esac
case "$SHIP_OUT" in
  *"verify record present"*"docs/loop/demo/verify.md"*) VERIFY_PRESENT="yes" ;;
  *) VERIFY_PRESENT="no" ;;
esac
expect "ship: a named slug with a verify record is reported as present" \
  "yes yes" "$NAMED_SLUG $VERIFY_PRESENT"
rm -rf "$SHIP17"

SHIP18="$(new_ship_fixture)"
mkdir -p "$SHIP18/docs/loop/demo"
printf '# spec\n' > "$SHIP18/docs/loop/demo/spec.md"
git -C "$SHIP18" add -A
git -C "$SHIP18" commit --quiet -m "add demo unit without a verify record"
ship_run "$SHIP18" demo
case "$SHIP_OUT" in
  *"verify record absent"*"docs/loop/demo/verify.md"*) VERIFY_ABSENT="yes" ;;
  *) VERIFY_ABSENT="no" ;;
esac
WITH_SLUG_VERDICT="$(printf '%s\n' "$SHIP_OUT" | grep -E '^verdict: ')"
WITH_SLUG_EXIT="$SHIP_EXIT"
ship_run "$SHIP18"
NO_SLUG_VERDICT="$(printf '%s\n' "$SHIP_OUT" | grep -E '^verdict: ')"
NO_SLUG_EXIT="$SHIP_EXIT"
expect "ship: a named slug without a verify record says so" \
  "yes $WITH_SLUG_VERDICT $WITH_SLUG_EXIT" "$VERIFY_ABSENT $NO_SLUG_VERDICT $NO_SLUG_EXIT"
rm -rf "$SHIP18"

SHIP19="$(new_ship_fixture)"
ship_run "$SHIP19" no-such-slug
case "$SHIP_OUT" in
  *"no unit contract found"*) NO_CONTRACT_NAMED="yes" ;;
  *) NO_CONTRACT_NAMED="no" ;;
esac
ship_run "$SHIP19"
case "$SHIP_OUT" in
  *"no unit contract found"*) NO_CONTRACT_UNNAMED="yes" ;;
  *) NO_CONTRACT_UNNAMED="no" ;;
esac
expect "ship: no unit contract found is stated, not omitted" \
  "yes yes" "$NO_CONTRACT_NAMED $NO_CONTRACT_UNNAMED"
rm -rf "$SHIP19"

# ---------------------------------------------------------------------------
echo "ship (command surface — commands/ship.md)"
SHIPMD="$ROOT/commands/ship.md"

allowed_tools_line() { grep '^allowed-tools:' "$SHIPMD"; }
expect "ship: commands/ship.md declares no write-capable tool" "0" \
  "$( allowed_tools_line | grep -qE '\b(Write|Edit|MultiEdit|NotebookEdit|Agent)\b' && echo 1 || echo 0 )"

expect "ship: commands/ship.md states nothing is deployed, published, or tagged" "0" \
  "$( grep -qi 'deploys, publishes, tags, and bumps nothing' "$SHIPMD" && echo 0 || echo 1 )"

expect "ship: commands/ship.md disclaims downstream Laravel app gates" "0" \
  "$( grep -qi 'downstream Laravel' "$SHIPMD" && grep -qi 'ship-checklist' "$SHIPMD" && echo 0 || echo 1 )"

# ---------------------------------------------------------------------------
echo "docs (README matches what shipped)"
README_MD="$ROOT/README.md"

commands_table_check() {
  local bad=0 table name
  table="$(sed -n '/^## Commands/,/^## Skills/p' "$README_MD")"
  for f in "$ROOT"/commands/*.md; do
    name="$(basename "$f" .md)"
    echo "$table" | grep -qE "\`/${name}[\` ]" || bad=1
  done
  echo $bad
}
expect "docs: every commands/*.md has a row in README's Commands table" "0" \
  "$(commands_table_check)"

expect "docs: README no longer claims Ship and Observe are missing" "0" \
  "$( { grep -qi 'No Ship phase automation' "$README_MD" || grep -qi 'No Observe phase' "$README_MD"; } && echo 1 || echo 0 )"

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

# ---------------------------------------------------------------------------
echo "envelope attribution (Unit/Slice propagation)"

# Checks: the literal `Unit:` line in SKILL.md's envelope block, `Unit:` set in
# every command that briefs an agent, and every agent naming Unit and Slice
# (plus the P4 no-brief wording) in its return. Returns "0" clean, "1" if any
# check fails, so it can be run against both the real tree and a stripped copy.
envelope_check() {
  local root="$1" bad=0
  grep -q '^Unit:' "$root/skills/loop-protocol/SKILL.md" || bad=1
  for f in loop.md slice.md verify.md; do
    grep -q 'Unit:' "$root/commands/$f" || bad=1
  done
  for f in "$root"/agents/*.md; do
    grep -q 'Unit' "$f" || bad=1
    grep -q 'Slice' "$f" || bad=1
    grep -q 'briefed without Unit/Slice' "$f" || bad=1
  done
  echo "$bad"
}

# Prove the case can fail before trusting that it can pass: strip every
# Unit/Slice-carrying line from a temp copy and expect the check to go red.
ENVDIR="$(mktemp -d)"
mkdir -p "$ENVDIR/skills/loop-protocol" "$ENVDIR/commands" "$ENVDIR/agents"
cp "$ROOT/skills/loop-protocol/SKILL.md" "$ENVDIR/skills/loop-protocol/SKILL.md"
cp "$ROOT/commands/loop.md" "$ROOT/commands/slice.md" "$ROOT/commands/verify.md" "$ENVDIR/commands/"
cp "$ROOT"/agents/*.md "$ENVDIR/agents/"
for f in "$ENVDIR/skills/loop-protocol/SKILL.md" "$ENVDIR"/commands/*.md "$ENVDIR"/agents/*.md; do
  grep -v -i -E 'unit|slice' "$f" > "$f.stripped" && mv "$f.stripped" "$f"
done
expect "envelope attribution fails on a stripped copy (proves the case can fail)" \
  "1" "$(envelope_check "$ENVDIR")"
rm -rf "$ENVDIR"

expect "envelope attribution present on the real tree" "0" "$(envelope_check "$ROOT")"

echo
echo "prompt ordering (cache-friendly ordering, R4.1)"

# "Top half" of a file = its first 50% of lines, rounded down. Stated here
# because C3 requires the definition to live in the test, not be assumed.
top_half() {
  local file="$1" total half
  total=$(wc -l < "$file")
  half=$((total / 2))
  head -n "$half" "$file"
}

# The violation set is the literal one from the spec: timestamp, run id,
# counter. {{args}} is explicitly NOT a violation (D5) — asserted below by a
# dedicated case rather than left to chance.
has_ordering_violation() {
  top_half "$1" | grep -Eiq '\{\{[[:space:]]*(timestamp|run[_-]?id|counter)[[:space:]]*\}\}'
}

ordering_check() {
  local dir="$1" bad=0 f
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    if has_ordering_violation "$f"; then bad=1; fi
  done
  echo "$bad"
}

expect "no volatile interpolation in top half of agents/*.md" "0" "$(ordering_check "$ROOT/agents")"
expect "no volatile interpolation in top half of commands/*.md" "0" "$(ordering_check "$ROOT/commands")"

ARGSDIR="$(mktemp -d)"
printf -- '---\ndesc\n---\n\n# Title -- `{{args}}`\n\nbody\n' > "$ARGSDIR/cmd.md"
expect "{{args}} in a command title does not trip the check (D5)" "0" "$(ordering_check "$ARGSDIR")"
rm -rf "$ARGSDIR"

VIOLDIR="$(mktemp -d)"
cp "$ROOT"/agents/*.md "$VIOLDIR/"
TARGET="$(ls "$VIOLDIR"/*.md | head -n1)"
awk 'NR==2{print "Seeded violation: {{timestamp}}"} {print}' "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
expect "seeded {{timestamp}} in the top half is caught (proves the case can fail)" "1" "$(ordering_check "$VIOLDIR")"
rm -rf "$VIOLDIR"

skill_check() {
  local f="$ROOT/skills/loop-protocol/SKILL.md" bad=0
  grep -q 'never interpolate a timestamp, run id, or counter above the task envelope' "$f" || bad=1
  grep -q 'invalidates the whole cached prefix behind it' "$f" || bad=1
  echo "$bad"
}
expect "SKILL.md states the ordering rule and its rationale (C1)" "0" "$(skill_check)"

echo
echo "----------------------------------------"
printf 'total: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL GREEN" || echo "FAILURES PRESENT"
exit "$FAIL"
