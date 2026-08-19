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

# cost-log-section-parse-error-on-macos-ci S4, OQ6 -- one line, identical in
# SHAPE on every platform (labelled fields; the values differ freely), so a
# job log names its own parser environment without anyone re-running
# anything to find out. An echo, never a case: it adds no PASS/FAIL and
# does not touch either job's case total (A4).
printf 'environment: bash %s, uname %s, jq %s, python3 %s, grep %s\n' \
  "${BASH_VERSION:-unknown}" "$(uname -s -m 2>/dev/null || echo unknown)" \
  "$(command -v jq >/dev/null 2>&1 && echo yes || echo no)" \
  "$(command -v python3 >/dev/null 2>&1 && echo yes || echo no)" \
  "$(command -v grep >/dev/null 2>&1 && echo yes || echo no)"

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
echo "record-cost-event.sh (cost ledger)"

COSTDIR="$(mktemp -d)"
cost() { CLAUDE_PROJECT_DIR="$COSTDIR" CLAUDE_PLUGIN_ROOT="$ROOT" run_hook record-cost-event.sh "$1"; }
LEDGER="$COSTDIR/.claude/loop-cost.jsonl"

# Builds a PreToolUse payload for one Agent/Task spawn. $4 (prompt) is the
# text actually handed to the subagent -- where Unit:/Slice: really live.
# $6 (optional) cwd -- carried at top level, as S5's rework attribution reads it.
start_json() { # $1 subagent_type $2 tool_use_id $3 description $4 prompt $5 session_id $6 cwd
  python3 - "$1" "$2" "$3" "$4" "$5" "${6:-}" <<'PY'
import json, sys
subagent, tid, desc, prompt, session, cwd = sys.argv[1:7]
payload = {
    "hook_event_name": "PreToolUse",
    "session_id": session,
    "tool_name": "Agent",
    "tool_use_id": tid,
    "tool_input": {"subagent_type": subagent, "description": desc, "prompt": prompt},
}
if cwd:
    payload["cwd"] = cwd
print(json.dumps(payload))
PY
}

# Builds the matching PostToolUse (finish) payload. $6 status, $7 total
# tokens ("null" to omit -- e.g. async_launched), $8 duration ms ("null" to
# omit), $9 optional raw JSON object merged into tool_response (usage, etc).
finish_json() { # $1 subagent_type $2 tool_use_id $3 description $4 prompt $5 session_id $6 status $7 tokens $8 duration_ms $9 extra_json
  python3 - "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" <<'PY'
import json, sys
subagent, tid, desc, prompt, session, status, tokens, dur, extra = sys.argv[1:10]
resp = {"status": status}
if tokens != "null":
    resp["totalTokens"] = int(tokens)
if dur != "null":
    resp["totalDurationMs"] = int(dur)
if extra:
    resp.update(json.loads(extra))
ti = {"subagent_type": subagent, "description": desc}
if prompt:
    ti["prompt"] = prompt
print(json.dumps({
    "hook_event_name": "PostToolUse",
    "session_id": session,
    "tool_name": "Agent",
    "tool_use_id": tid,
    "tool_input": ti,
    "tool_response": resp,
}))
PY
}

# -- (a) simulated four-phase run: one start + one finish per phase, every
# L2 field present, slug resolved from the prompt in every record (L10, L1).
SESSION="sess-fourphase"
SPEC_PROMPT=$'You own Phase 1 -- Spec.\nUnit:  cost-measurement-v0.2\n\nWrite the spec.'
SLICE_PROMPT=$'You own Phase 2 -- Slice.\nUnit:  cost-measurement-v0.2\n\nCut the slices.'
BUILD_PROMPT=$'Unit:  cost-measurement-v0.2\nSlice: S2\n\nBuild the cost ledger hook.'
VERIFY_PROMPT=$'You own Phase 4 -- Verify.\nUnit:  cost-measurement-v0.2\n\nVerify the unit.'

cost "$(start_json loop-spec toolu-sp1 "Spec cost-measurement-v0.2" "$SPEC_PROMPT" "$SESSION")" >/dev/null
cost "$(finish_json loop-spec toolu-sp1 "Spec cost-measurement-v0.2" "$SPEC_PROMPT" "$SESSION" completed 11000 5000 "")" >/dev/null

cost "$(start_json loop-slice toolu-sl1 "Slice cost-measurement-v0.2" "$SLICE_PROMPT" "$SESSION")" >/dev/null
cost "$(finish_json loop-slice toolu-sl1 "Slice cost-measurement-v0.2" "$SLICE_PROMPT" "$SESSION" completed 12000 6000 "")" >/dev/null

cost "$(start_json loop-build toolu-bd1 "S2 cost ledger hook" "$BUILD_PROMPT" "$SESSION")" >/dev/null
cost "$(finish_json loop-build toolu-bd1 "S2 cost ledger hook" "$BUILD_PROMPT" "$SESSION" completed 60787 239271 "")" >/dev/null

cost "$(start_json loop-verify toolu-vf1 "Verify cost-measurement-v0.2" "$VERIFY_PROMPT" "$SESSION")" >/dev/null
cost "$(finish_json loop-verify toolu-vf1 "Verify cost-measurement-v0.2" "$VERIFY_PROMPT" "$SESSION" completed 9000 3000 "")" >/dev/null

four_phase_check() {
  local bad=0
  python3 - "$LEDGER" <<'PY' || bad=1
import json, sys, collections
records = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
by_phase = collections.defaultdict(list)
for r in records:
    by_phase[r.get("phase")].append(r)

REQUIRED_ALWAYS = ["ts", "event", "invocation_id", "session_id", "slug", "phase", "agent", "model_source"]
REQUIRED_FINISH = ["status", "duration_ms", "total_tokens"]

for phase in ("spec", "slice", "build", "verify"):
    evs = by_phase.get(phase, [])
    assert len(evs) == 2, "%s: expected 2 records, got %d" % (phase, len(evs))
    starts = [e for e in evs if e["event"] == "start"]
    finishes = [e for e in evs if e["event"] == "finish"]
    assert len(starts) == 1, phase + ": expected exactly 1 start"
    assert len(finishes) == 1, phase + ": expected exactly 1 finish"
    for e in evs:
        for k in REQUIRED_ALWAYS:
            assert k in e, "%s %s: missing %s" % (phase, e["event"], k)
        assert e["slug"] == "cost-measurement-v0.2", phase + ": slug not resolved"
    for k in REQUIRED_FINISH:
        assert k in finishes[0], phase + " finish: missing " + k

build_finish = [e for e in by_phase["build"] if e["event"] == "finish"][0]
assert build_finish.get("slice") == "S2", "build finish: slice not resolved"
PY
  echo "$bad"
}
expect "four-phase run: 1 start + 1 finish per phase, L2 fields present, slug resolved" "0" "$(four_phase_check)"
expect "four-phase run: exactly 8 records total" "8" "$(wc -l < "$LEDGER" | tr -d ' ')"

# -- (b) no `Unit:` line anywhere -> slug "unknown", record not dropped (L4).
rm -f "$LEDGER"
cost "$(finish_json loop-build toolu-nounit "no unit here" "" "sess-nounit" completed 500 100 "")" >/dev/null
expect "no Unit: line yields slug unknown and the record is not dropped" "unknown 1" \
  "$(python3 -c "import json;print(json.loads(open('$LEDGER').read().strip())['slug'])") $(wc -l < "$LEDGER" | tr -d ' ')"

# -- (c) exit 0 on every path, asserted individually (L6, L8).
expect "cost ledger: valid payload exits 0" "0" \
  "$(cost "$(finish_json loop-build toolu-valid1 "d" "" "$SESSION" completed 10 10 "")")"

expect "cost ledger: malformed payload exits 0" "0" \
  "$(CLAUDE_PROJECT_DIR="$COSTDIR" CLAUDE_PLUGIN_ROOT="$ROOT" run_hook record-cost-event.sh '{"hook_event_name":"PreToolUse", not valid json')"

expect "cost ledger: empty payload exits 0" "0" \
  "$(CLAUDE_PROJECT_DIR="$COSTDIR" CLAUDE_PLUGIN_ROOT="$ROOT" run_hook record-cost-event.sh '')"

RODIR="$(mktemp -d)"
chmod 555 "$RODIR"
expect "cost ledger: unwritable ledger dir still exits 0" "0" \
  "$(CLAUDE_PROJECT_DIR="$RODIR" CLAUDE_PLUGIN_ROOT="$ROOT" run_hook record-cost-event.sh "$(finish_json loop-build toolu-ro1 "d" "" sess-ro completed 10 10 "")")"
chmod 755 "$RODIR"; rm -rf "$RODIR"

NOPARSER_BIN="$(mktemp -d)"
for b in cat mkdir date sed bash; do
  p="$(command -v "$b" 2>/dev/null)"
  [ -n "$p" ] && ln -s "$p" "$NOPARSER_BIN/$b"
done
NOPARSER_DIR="$(mktemp -d)"
NOPARSER_PAYLOAD="$(finish_json loop-build toolu-np1 "d" "" sess-np completed 10 10 "")"
NOPARSER_EXIT="$(PATH="$NOPARSER_BIN" CLAUDE_PROJECT_DIR="$NOPARSER_DIR" CLAUDE_PLUGIN_ROOT="$ROOT" run_hook record-cost-event.sh "$NOPARSER_PAYLOAD")"
expect "cost ledger: PATH stripped of jq+python3 still exits 0" "0" "$NOPARSER_EXIT"
expect "cost ledger: PATH stripped of jq+python3 writes no partial line" "no" \
  "$([ -e "$NOPARSER_DIR/.claude/loop-cost.jsonl" ] && echo yes || echo no)"
rm -rf "$NOPARSER_BIN" "$NOPARSER_DIR"

# -- (d) async-launched: null tokens, a status that says why, never a 0 (L3, D4).
rm -f "$LEDGER"
cost "$(finish_json loop-build toolu-async1 "d" "" sess-async async_launched null null "")" >/dev/null
async_check() {
  python3 - "$LEDGER" <<'PY'
import json, sys
r = json.loads(open(sys.argv[1]).read().strip())
fields = ["total_tokens", "input_tokens", "output_tokens", "cache_read_tokens", "duration_ms"]
ok = r.get("status") == "async_launched" and all(r.get(f) is None for f in fields)
print("yes" if ok else "no")
PY
}
expect "async-launched invocation: null tokens, status names why, never 0" "yes" "$(async_check)"

# -- (e) cache-read tokens recorded when present, omitted (not zeroed) when
# absent (C4, L3).
rm -f "$LEDGER"
cost "$(finish_json loop-build toolu-cache1 "d" "" sess-cache completed 1000 500 '{"usage":{"input_tokens":200,"output_tokens":300,"cache_read_input_tokens":150}}')" >/dev/null
cost "$(finish_json loop-build toolu-cache2 "d" "" sess-cache completed 1000 500 "")" >/dev/null
cache_check() {
  python3 - "$LEDGER" <<'PY'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
with_cache = [r for r in lines if r.get("invocation_id") == "toolu-cache1"][0]
without_cache = [r for r in lines if r.get("invocation_id") == "toolu-cache2"][0]
ok = with_cache.get("cache_read_tokens") == 150 and "cache_read_tokens" not in without_cache
print("yes" if ok else "no")
PY
}
expect "cache-read tokens recorded when present, field absent (not 0) when not" "yes" "$(cache_check)"

# -- (f) ledger path, and nothing under docs/loop (H1).
expect "ledger is written at .claude/loop-cost.jsonl" "yes" \
  "$([ -f "$COSTDIR/.claude/loop-cost.jsonl" ] && echo yes || echo no)"
expect "nothing is ever written under docs/loop" "no" \
  "$([ -e "$COSTDIR/docs" ] && echo yes || echo no)"

# -- (g) LARAVEL_LOOP_COST_LEDGER=0 writes nothing and exits 0.
rm -f "$LEDGER"
DISABLE_EXIT="$(LARAVEL_LOOP_COST_LEDGER=0 cost "$(finish_json loop-build toolu-off1 "d" "" sess-off completed 10 10 "")")"
expect "LARAVEL_LOOP_COST_LEDGER=0 exits 0" "0" "$DISABLE_EXIT"
expect "LARAVEL_LOOP_COST_LEDGER=0 writes nothing" "no" "$([ -e "$LEDGER" ] && echo yes || echo no)"

# ---------------------------------------------------------------------------
echo "record-cost-event.sh (cost ledger: exactly-once + concurrency, S3)"

# Builds a SubagentStop payload as it is really shaped (E4/agents-board.jsonl
# evidence): no tool_name, no tool_input, no tool_use_id -- .agent_type here
# identifies the agent that just stopped, not a caller.
stop_json() { # $1 agent_type $2 session_id
  python3 - "$1" "$2" <<'PY'
import json, sys
agent, session = sys.argv[1:3]
print(json.dumps({
    "hook_event_name": "SubagentStop",
    "session_id": session,
    "agent_type": agent,
}))
PY
}

valid_jsonl_lines() { # $1 file -> "yes"/"no": every non-empty line parses
  python3 - "$1" <<'PY'
import json, sys
ok = True
for line in open(sys.argv[1]):
    if not line.strip():
        continue
    try:
        json.loads(line)
    except Exception:
        ok = False
print("yes" if ok else "no")
PY
}

# -- (a) forced concurrency: N >= 20 finish events for DISTINCT invocations,
# fired in parallel with & and wait, produce exactly N lines, each a
# complete parseable JSON object, no interleaved or truncated line (L5). The
# concurrency is forced (backgrounded + waited), not hoped for.
rm -f "$LEDGER"
rm -rf "${COSTDIR:?}/.claude/loop-cost-finished"
CONC_N=25
for i in $(seq 1 "$CONC_N"); do
  cost "$(finish_json loop-build "toolu-conc-$i" "d" "" "sess-conc-$i" completed $((1000 + i)) $((10 + i)) "")" >/dev/null &
done
wait
expect "forced concurrency: N finish events yield exactly N lines" "$CONC_N" \
  "$(wc -l < "$LEDGER" | tr -d ' ')"
expect "forced concurrency: every line is a complete, parseable JSON object" "yes" \
  "$(valid_jsonl_lines "$LEDGER")"
conc_unique_ids() {
  python3 - "$LEDGER" <<'PY'
import json, sys
ids = [json.loads(l)["invocation_id"] for l in open(sys.argv[1]) if l.strip()]
print("yes" if len(ids) == len(set(ids)) else "no")
PY
}
expect "forced concurrency: no invocation_id duplicated across the N lines" "yes" \
  "$(conc_unique_ids)"

# -- (b) the same finish payload delivered twice yields one finish record (L9).
rm -f "$LEDGER"
DUP_PAYLOAD="$(finish_json loop-build toolu-dup1 "d" "" sess-dup completed 700 70 "")"
cost "$DUP_PAYLOAD" >/dev/null
cost "$DUP_PAYLOAD" >/dev/null
expect "same finish payload delivered twice yields one finish record" "1" \
  "$(wc -l < "$LEDGER" | tr -d ' ')"

# -- (c) a PostToolUse finish and a SubagentStop finish for one invocation
# yield one finish record, and it is the one carrying tokens (L1, E4).
# Proven both orderings, since real evidence shows SubagentStop can arrive
# before OR after the token-carrying PostToolUse depending on sync vs async.
one_finish_with_tokens() {
  python3 - "$LEDGER" "$1" <<'PY'
import json, sys
path, want_tokens = sys.argv[1], int(sys.argv[2])
lines = [json.loads(l) for l in open(path) if l.strip()]
ok = len(lines) == 1 and lines[0].get("total_tokens") == want_tokens
print("yes" if ok else "no")
PY
}

rm -f "$LEDGER"
cost "$(stop_json loop-build sess-stop1)" >/dev/null
cost "$(finish_json loop-build toolu-stop1 "d" "" sess-stop1 completed 900 90 "")" >/dev/null
expect "SubagentStop then PostToolUse: one finish record, carrying tokens" "yes" \
  "$(one_finish_with_tokens 900)"

rm -f "$LEDGER"
cost "$(finish_json loop-build toolu-stop2 "d" "" sess-stop2 completed 950 95 "")" >/dev/null
cost "$(stop_json loop-build sess-stop2)" >/dev/null
expect "PostToolUse then SubagentStop: one finish record, carrying tokens" "yes" \
  "$(one_finish_with_tokens 950)"

# -- (d) the script invoked twice on the same event -- simulating plugin
# plus manual install -- yields one record (L9).
rm -f "$LEDGER"
INSTALL_DUP_PAYLOAD="$(finish_json loop-build toolu-install1 "d" "" sess-install completed 400 40 "")"
CLAUDE_PROJECT_DIR="$COSTDIR" CLAUDE_PLUGIN_ROOT="$ROOT" run_hook record-cost-event.sh "$INSTALL_DUP_PAYLOAD" >/dev/null
CLAUDE_PROJECT_DIR="$COSTDIR" CLAUDE_PLUGIN_ROOT="$ROOT" run_hook record-cost-event.sh "$INSTALL_DUP_PAYLOAD" >/dev/null
expect "hook registered twice (plugin + manual install) yields one record" "1" \
  "$(wc -l < "$LEDGER" | tr -d ' ')"

# -- (e) all of S2's exit-0 cases still pass unmodified: re-run them here
# against the S3 script so a regression in this slice fails in this section,
# not silently a scroll away.
expect "S2 unmodified: valid payload exits 0" "0" \
  "$(cost "$(finish_json loop-build toolu-s2valid "d" "" "$SESSION" completed 10 10 "")")"
expect "S2 unmodified: malformed payload exits 0" "0" \
  "$(CLAUDE_PROJECT_DIR="$COSTDIR" CLAUDE_PLUGIN_ROOT="$ROOT" run_hook record-cost-event.sh '{"hook_event_name":"PreToolUse", not valid json')"
expect "S2 unmodified: empty payload exits 0" "0" \
  "$(CLAUDE_PROJECT_DIR="$COSTDIR" CLAUDE_PLUGIN_ROOT="$ROOT" run_hook record-cost-event.sh '')"
S2DIR_RO="$(mktemp -d)"
chmod 555 "$S2DIR_RO"
expect "S2 unmodified: unwritable ledger dir still exits 0" "0" \
  "$(CLAUDE_PROJECT_DIR="$S2DIR_RO" CLAUDE_PLUGIN_ROOT="$ROOT" run_hook record-cost-event.sh "$(finish_json loop-build toolu-s2ro "d" "" sess-s2ro completed 10 10 "")")"
chmod 755 "$S2DIR_RO"; rm -rf "$S2DIR_RO"
S2_NOPARSER_BIN="$(mktemp -d)"
for b in cat mkdir date sed bash; do
  p="$(command -v "$b" 2>/dev/null)"
  [ -n "$p" ] && ln -s "$p" "$S2_NOPARSER_BIN/$b"
done
S2_NOPARSER_DIR="$(mktemp -d)"
expect "S2 unmodified: PATH stripped of jq+python3 still exits 0" "0" \
  "$(PATH="$S2_NOPARSER_BIN" CLAUDE_PROJECT_DIR="$S2_NOPARSER_DIR" CLAUDE_PLUGIN_ROOT="$ROOT" run_hook record-cost-event.sh "$(finish_json loop-build toolu-s2np "d" "" sess-s2np completed 10 10 "")")"
expect "S2 unmodified: PATH stripped of jq+python3 writes no partial line" "no" \
  "$([ -e "$S2_NOPARSER_DIR/.claude/loop-cost.jsonl" ] && echo yes || echo no)"
rm -rf "$S2_NOPARSER_BIN" "$S2_NOPARSER_DIR"

# ---------------------------------------------------------------------------
echo "record-cost-event.sh (cost ledger: bound + eviction, S4)"

# -- (a) LARAVEL_LOOP_COST_MAX_LINES=50, 80 sequential events -> exactly 50
# lines remain, and they are the newest 50, in order (H2).
rm -f "$LEDGER"
rm -rf "${COSTDIR:?}/.claude/loop-cost-finished" "${COSTDIR:?}/.claude/loop-cost-evict.lock"
CAP_N=80
CAP_MAX=50
for i in $(seq 1 "$CAP_N"); do
  LARAVEL_LOOP_COST_MAX_LINES=$CAP_MAX \
    cost "$(finish_json loop-build "toolu-cap-$i" "d" "" "sess-cap-$i" completed "$i" "$i" "")" >/dev/null
done
expect "cap: 80 events with cap 50 leaves exactly 50 lines" "$CAP_MAX" \
  "$(wc -l < "$LEDGER" | tr -d ' ')"
cap_newest_in_order() {
  python3 - "$LEDGER" "$CAP_N" <<'PY'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
n = int(sys.argv[2])
want = [str(i) for i in range(n - len(lines) + 1, n + 1)]
got = [l["invocation_id"].rsplit("-", 1)[-1] for l in lines]
print("yes" if got == want else "no")
PY
}
expect "cap: the retained lines are the newest 50, in order" "yes" "$(cap_newest_in_order)"

# -- (b) eviction running concurrently with appends: the ledger is never
# observed empty, and every retained line is complete, parseable JSON (H3).
rm -f "$LEDGER"
rm -rf "${COSTDIR:?}/.claude/loop-cost-finished" "${COSTDIR:?}/.claude/loop-cost-evict.lock"
EVICT_N=60
EVICT_CAP=15
POLL_LOG="$(mktemp)"
(
  for _ in $(seq 1 600); do
    if [ -f "$LEDGER" ]; then
      wc -l < "$LEDGER" 2>/dev/null | tr -d ' ' >> "$POLL_LOG"
    fi
  done
) &
POLL_PID=$!
for i in $(seq 1 "$EVICT_N"); do
  LARAVEL_LOOP_COST_MAX_LINES=$EVICT_CAP \
    cost "$(finish_json loop-build "toolu-evb-$i" "d" "" "sess-evb-$i" completed "$i" "$i" "")" >/dev/null &
done
wait
wait "$POLL_PID" 2>/dev/null

expect "eviction under concurrency: settles at or under cap" "yes" \
  "$([ "$(wc -l < "$LEDGER" | tr -d ' ')" -le "$EVICT_CAP" ] && echo yes || echo no)"
expect "eviction under concurrency: every retained line is complete, parseable JSON" "yes" \
  "$(valid_jsonl_lines "$LEDGER")"
expect "eviction under concurrency: ledger never observed at 0 lines while polling" "yes" \
  "$(grep -qx '0' "$POLL_LOG" && echo no || echo yes)"
rm -f "$POLL_LOG"

# -- (f) convergence gap (S5, spec.md H2-H5), REPLACED per decisions.md's
# "Second G1: the ledger promises convergence, and a later invocation is
# obliged to trim": the cap promises eventual convergence (E1 property 3),
# not a bound at rest, and obligation class 3 says a LATER invocation --
# appending or not -- is obliged to trim on arrival, unconditionally. A
# lock-loser never retries on its own (OQ1's structural hole,
# spike-oq5-local-red.md SS3: 5/5 red against HEAD and against pre-S5), so
# this constructs that hole deterministically -- the identical primitive
# case (g) already uses to simulate a held evict lock (`mkdir` the lock
# directory) -- and releases it SYNCHRONOUSLY in this process, never via a
# backgrounded `sleep N; rmdir`: spike-oq5-local-red.md SS3's own 0/5 control
# at HOLD=0.02s shows a hold shorter than L7's poll budget flips the arm's
# colour, so a timed hold on a loaded runner could go green for the wrong
# reason. The over-cap-before token is what stops this being vacuous --
# without it, an assertion that only checks convergence-after would pass
# whether or not the hole was ever actually constructed.
rm -f "$LEDGER"
rm -rf "${COSTDIR:?}/.claude/loop-cost-finished" "${COSTDIR:?}/.claude/loop-cost-evict.lock"
CONV_CAP=15
CONV_LOCK="$COSTDIR/.claude/loop-cost-evict.lock"
mkdir -p "$COSTDIR/.claude"
n=1; while [ "$n" -le "$CONV_CAP" ]; do printf '{"seed":%d}\n' "$n" >> "$LEDGER"; n=$((n + 1)); done

mkdir "$CONV_LOCK"                                  # simulated concurrent evictor, held
LARAVEL_LOOP_COST_MAX_LINES=$CONV_CAP \
  cost "$(finish_json loop-build "toolu-conv-last" "d" "" "sess-conv" completed 1 1 "")" >/dev/null
CONV_OVER="$([ "$(wc -l < "$LEDGER" | tr -d ' ')" -gt "$CONV_CAP" ] && echo yes || echo no)"
rmdir "$CONV_LOCK"                                  # synchronous release -- no sleep, no background job

# One later arrival that appends nothing: a duplicate finish for an id
# already recorded above, discarded on arrival and appending no line of its
# own (S5's obligation class 3 -- discharged unconditionally on arrival).
LARAVEL_LOOP_COST_MAX_LINES=$CONV_CAP \
  cost "$(finish_json loop-build "toolu-conv-last" "d" "" "sess-conv" completed 1 1 "")" >/dev/null
CONV_CONVERGED="$([ "$(wc -l < "$LEDGER" | tr -d ' ')" -le "$CONV_CAP" ] && echo yes || echo no)"

expect "eviction convergence: a lock-losing last appender leaves the ledger over cap at rest, and it converges as soon as ANY later arrival appends nothing" "yes yes" \
  "$CONV_OVER $CONV_CONVERGED"

# -- (g) L7 regression guard (S5): with the evict lock held by another
# process for far longer than any appender should ever wait, an append still
# completes -- its own line lands, and its wall clock does not scale with how
# long the lock stays held. GREEN before and after this slice's fix: it
# proves the fix did not cost L7, not that the fix works (that is case (f)).
rm -f "$LEDGER"
rm -rf "${COSTDIR:?}/.claude/loop-cost-finished" "${COSTDIR:?}/.claude/loop-cost-evict.lock"
L7_LOCK="$COSTDIR/.claude/loop-cost-evict.lock"
mkdir -p "$COSTDIR/.claude"
mkdir "$L7_LOCK"
L7_HOLD_SECONDS=5
( sleep "$L7_HOLD_SECONDS"; rmdir "$L7_LOCK" ) &
L7_HOLDER_PID=$!
SECONDS=0
cost "$(finish_json loop-build "toolu-l7-1" "d" "" "sess-l7" completed 1 1 "")" >/dev/null
L7_ELAPSED="$SECONDS"
wait "$L7_HOLDER_PID" 2>/dev/null
expect "L7: an append lands its line while the evict lock is held, and its own wall clock stays well under the hold time" "yes yes" \
  "$(grep -q toolu-l7-1 "$LEDGER" && echo yes || echo no) $([ "$L7_ELAPSED" -lt "$L7_HOLD_SECONDS" ] && echo yes || echo no)"

# -- (h) mv-failure regression (S9, verify.md finding (a)): the pre-fix loop
# has three break paths for real I/O conditions (non-numeric wc, converged,
# mktemp failure, tail failure-or-empty) but none for a persistently failing
# `mv -f` -- reproduced at 209 and 501 iterations with no break reached. The
# script calls `mv` unqualified, so a stub `mv` placed first on PATH is a
# portable, privilege-free trigger (chflags is macOS-only; chattr +i needs
# root). The observation is bounded with bash job control -- never GNU
# `timeout`, absent on the maintainer's bash 3.2 macOS host -- following
# ship-check.sh's run_bounded() precedent: run in its own process group,
# poll with kill -0, and TERM/KILL the whole group if the bound is hit.
rm -f "$LEDGER"
rm -rf "${COSTDIR:?}/.claude/loop-cost-finished" "${COSTDIR:?}/.claude/loop-cost-evict.lock"
MVFAIL_CAP=5
MVFAIL_BOUND=5
MVFAIL_BIN="$(mktemp -d)"
cat > "$MVFAIL_BIN/mv" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$MVFAIL_BIN/mv"
for i in $(seq 1 20); do printf '{"raw":%d}\n' "$i" >> "$LEDGER"; done
MVFAIL_OUT="$(mktemp)"
(
  set -m
  PATH="$MVFAIL_BIN:$PATH" LARAVEL_LOOP_COST_MAX_LINES=$MVFAIL_CAP \
    cost "$(finish_json loop-build toolu-mvfail1 "d" "" sess-mvfail completed 1 1 "")" >"$MVFAIL_OUT" 2>&1 &
  echo $! >"$MVFAIL_OUT.pid"
  wait $!
  echo $? >"$MVFAIL_OUT.exit"
) >/dev/null 2>/dev/null &
MVFAIL_RUNNER=$!
MVFAIL_START="$SECONDS"
while kill -0 "$MVFAIL_RUNNER" 2>/dev/null; do
  if [ $((SECONDS - MVFAIL_START)) -ge "$MVFAIL_BOUND" ]; then
    MVFAIL_PGID="$(cat "$MVFAIL_OUT.pid" 2>/dev/null || true)"
    if [ -n "$MVFAIL_PGID" ]; then
      kill -TERM "-$MVFAIL_PGID" 2>/dev/null
      sleep 0.3
      kill -KILL "-$MVFAIL_PGID" 2>/dev/null
    fi
    kill -KILL "$MVFAIL_RUNNER" 2>/dev/null
    wait "$MVFAIL_RUNNER" 2>/dev/null
    break
  fi
  sleep 0.05
done
wait "$MVFAIL_RUNNER" 2>/dev/null
MVFAIL_RETURNED="$([ -f "$MVFAIL_OUT.exit" ] && echo yes || echo no)"
MVFAIL_EXIT="$(cat "$MVFAIL_OUT.exit" 2>/dev/null || echo -1)"
MVFAIL_LOCK="$COSTDIR/.claude/loop-cost-evict.lock"
expect "mv failure: append_and_evict() returns within the bound, exits 0, and releases the evict lock" "yes 0 no" \
  "$MVFAIL_RETURNED $MVFAIL_EXIT $([ -d "$MVFAIL_LOCK" ] && echo yes || echo no)"
rm -rf "$MVFAIL_BIN" "$MVFAIL_OUT" "$MVFAIL_OUT.pid" "$MVFAIL_OUT.exit"

# -- (i) arrival trim never waits (S5, L6/E5): with the evict lock held by
# another process, an arrival that appends nothing -- here, a duplicate
# finish for an id already recorded -- returns fast (one mkdir attempt, no
# poll, no retry, no sleep), exits 0, and leaves an over-cap ledger
# untrimmed. Case (g)'s shape, for the NEW path: case (g)'s subject is an
# appender, and this is the one case (g) cannot cover.
rm -f "$LEDGER"
rm -rf "${COSTDIR:?}/.claude/loop-cost-finished" "${COSTDIR:?}/.claude/loop-cost-evict.lock"
NOWAIT_CAP=15
NOWAIT_LOCK="$COSTDIR/.claude/loop-cost-evict.lock"
mkdir -p "$COSTDIR/.claude"
n=1; while [ "$n" -le $((NOWAIT_CAP + 5)) ]; do printf '{"seed":%d}\n' "$n" >> "$LEDGER"; n=$((n + 1)); done

mkdir "$NOWAIT_LOCK"
NOWAIT_HOLD_SECONDS=5
( sleep "$NOWAIT_HOLD_SECONDS"; rmdir "$NOWAIT_LOCK" 2>/dev/null ) &
NOWAIT_HOLDER_PID=$!

# First delivery: a real finish, lock held -> appends as a lock loser (same
# shape as case (f)'s setup), leaving the ledger over cap.
LARAVEL_LOOP_COST_MAX_LINES=$NOWAIT_CAP \
  cost "$(finish_json loop-build "toolu-nowait-1" "d" "" "sess-nowait" completed 1 1 "")" >/dev/null
NOWAIT_OVER="$([ "$(wc -l < "$LEDGER" | tr -d ' ')" -gt "$NOWAIT_CAP" ] && echo yes || echo no)"

# Second delivery, same id, lock STILL held: a duplicate-finish arrival that
# appends nothing -- the timed one.
SECONDS=0
NOWAIT_EXIT="$(LARAVEL_LOOP_COST_MAX_LINES=$NOWAIT_CAP \
  cost "$(finish_json loop-build "toolu-nowait-1" "d" "" "sess-nowait" completed 1 1 "")")"
NOWAIT_ELAPSED="$SECONDS"
NOWAIT_STILL_OVER="$([ "$(wc -l < "$LEDGER" | tr -d ' ')" -gt "$NOWAIT_CAP" ] && echo yes || echo no)"
wait "$NOWAIT_HOLDER_PID" 2>/dev/null

expect "arrival trim never waits: a duplicate-finish arrival with the lock held exits 0 well under the hold time, leaving the over-cap ledger untrimmed" "0 yes yes yes" \
  "$NOWAIT_EXIT $NOWAIT_OVER $([ "$NOWAIT_ELAPSED" -lt "$NOWAIT_HOLD_SECONDS" ] && echo yes || echo no) $NOWAIT_STILL_OVER"

# -- (j) boundary: arrival trim at/under cap is a no-op (S5, H3): with the
# ledger already exactly at cap, an arrival that appends nothing changes
# nothing at all -- byte-identical ledger, no leftover `.evict.` temp file,
# exit 0.
rm -f "$LEDGER"
rm -rf "${COSTDIR:?}/.claude/loop-cost-finished" "${COSTDIR:?}/.claude/loop-cost-evict.lock"
ATCAP_CAP=15
mkdir -p "$COSTDIR/.claude"
n=1; while [ "$n" -le $((ATCAP_CAP - 1)) ]; do printf '{"seed":%d}\n' "$n" >> "$LEDGER"; n=$((n + 1)); done
LARAVEL_LOOP_COST_MAX_LINES=$ATCAP_CAP \
  cost "$(finish_json loop-build "toolu-atcap-1" "d" "" "sess-atcap" completed 1 1 "")" >/dev/null
ATCAP_COUNT_BEFORE="$(wc -l < "$LEDGER" | tr -d ' ')"
ATCAP_SNAPSHOT="$(mktemp)"
cp "$LEDGER" "$ATCAP_SNAPSHOT"

# A duplicate finish for the same id: an arrival that appends nothing, with
# the ledger already exactly at cap.
ATCAP_EXIT="$(LARAVEL_LOOP_COST_MAX_LINES=$ATCAP_CAP \
  cost "$(finish_json loop-build "toolu-atcap-1" "d" "" "sess-atcap" completed 1 1 "")")"
ATCAP_IDENTICAL="$(cmp -s "$LEDGER" "$ATCAP_SNAPSHOT" && echo yes || echo no)"
ATCAP_TMP_LEFTOVER="$(find "$COSTDIR/.claude" -maxdepth 1 -name '*.evict.*' 2>/dev/null | wc -l | tr -d ' ')"
rm -f "$ATCAP_SNAPSHOT"

expect "arrival trim boundary: ledger already at cap, an arrival that appends nothing is a byte-identical no-op" "$ATCAP_CAP yes 0 0" \
  "$ATCAP_COUNT_BEFORE $ATCAP_IDENTICAL $ATCAP_TMP_LEFTOVER $ATCAP_EXIT"

# -- (c) `.claude/loop-cost.jsonl` is git-ignored, and a fixture repo shows no
# ledger (or its S3/S4 sidecar state) in `git status` after events (H4).
GITFIX="$(mktemp -d)"
(cd "$GITFIX" && git init -q && cp "$ROOT/.gitignore" . && git add .gitignore && git commit -q -m init) >/dev/null 2>&1
CLAUDE_PROJECT_DIR="$GITFIX" CLAUDE_PLUGIN_ROOT="$ROOT" \
  run_hook record-cost-event.sh "$(finish_json loop-build toolu-git1 "d" "" sess-git completed 10 10 "")" >/dev/null
expect "H4: git check-ignore succeeds for the ledger path" "0" \
  "$(cd "$GITFIX" && git check-ignore -q .claude/loop-cost.jsonl >/dev/null 2>&1; echo $?)"
expect "H4: git status --porcelain shows no ledger or sidecar state after events" "" \
  "$(cd "$GITFIX" && git status --porcelain -- .claude 2>/dev/null)"
rm -rf "$GITFIX"

# -- (d) deleting the ledger mid-sequence breaks nothing: the next event
# exits 0, recreates it, and the deleted event is simply gone (H5).
rm -f "$LEDGER"
cost "$(finish_json loop-build toolu-mid1 "d" "" sess-mid completed 1 1 "")" >/dev/null
rm -f "$LEDGER"
MIDDEL_EXIT="$(cost "$(finish_json loop-build toolu-mid2 "d" "" sess-mid completed 2 2 "")")"
expect "H5: deleting the ledger mid-sequence, the next event exits 0" "0" "$MIDDEL_EXIT"
expect "H5: the next event recreates the ledger" "yes" "$([ -f "$LEDGER" ] && echo yes || echo no)"
expect "H5: the deleted (earlier) event is simply gone, not replayed" "1" \
  "$(wc -l < "$LEDGER" | tr -d ' ')"

# -- (e) a non-numeric LARAVEL_LOOP_COST_MAX_LINES falls back to 5000 rather
# than disabling the bound or crashing. Seeded directly (no subprocess per
# line) so the assertion is cheap; only the final real event goes through the
# hook.
rm -f "$LEDGER"
rm -rf "${COSTDIR:?}/.claude/loop-cost-finished" "${COSTDIR:?}/.claude/loop-cost-evict.lock"
SEED_N=5010
: > "$LEDGER"
for i in $(seq 1 "$SEED_N"); do
  printf '{"ts":%d,"event":"finish","invocation_id":"seed-%d","slug":"seed","phase":"build","agent":"loop-build","model_source":"unknown"}\n' "$i" "$i"
done >> "$LEDGER"
NONNUM_EXIT="$(LARAVEL_LOOP_COST_MAX_LINES=abc cost "$(finish_json loop-build toolu-nonnum1 "d" "" sess-nonnum completed 1 1 "")")"
expect "non-numeric LARAVEL_LOOP_COST_MAX_LINES: hook still exits 0" "0" "$NONNUM_EXIT"
expect "non-numeric LARAVEL_LOOP_COST_MAX_LINES: falls back to 5000, not disabled" "5000" \
  "$(wc -l < "$LEDGER" | tr -d ' ')"
expect "non-numeric LARAVEL_LOOP_COST_MAX_LINES: newest line survives the fallback-bound eviction" "yes" \
  "$(tail -1 "$LEDGER" | grep -q toolu-nonnum1 && echo yes || echo no)"

rm -rf "$COSTDIR"

# ---------------------------------------------------------------------------
echo "record-cost-event.sh (rework attribution, S5)"

REWORKDIR="$(mktemp -d)"
rcost() { CLAUDE_PROJECT_DIR="$REWORKDIR" CLAUDE_PLUGIN_ROOT="$ROOT" run_hook record-cost-event.sh "$1"; }
RLEDGER="$REWORKDIR/.claude/loop-cost.jsonl"

# A PostToolUse/Bash test-run result, exactly as enforce-refine-cap.sh's own
# fixtures shape it, plus session_id/agent_type/cwd -- the attribution keys
# this slice is pinned to. $5 (optional) cwd.
bash_test_json() { # $1 session_id $2 agent_type $3 target $4 fail|pass $5 cwd
  python3 - "$1" "$2" "$3" "$4" "${5:-}" <<'PY'
import json, sys
session, agent, target, result, cwd = sys.argv[1:6]
if result == "fail":
    resp = "FAIL  Tests\\Feature\\%s\n  Tests: 1 failed" % target
else:
    resp = "PASS  Tests\\Feature\\%s\n  Tests: 1 passed" % target
payload = {
    "hook_event_name": "PostToolUse",
    "tool_name": "Bash",
    "session_id": session,
    "agent_type": agent,
    "tool_input": {"command": "php artisan test --filter=%s" % target},
    "tool_response": resp,
}
if cwd:
    payload["cwd"] = cwd
print(json.dumps(payload))
PY
}

# Reads one field off the record matching invocation_id+event in a JSONL
# ledger. "MISSING" when the record exists but lacks the field (the case
# that matters here: absent means "not rework"). "NOTFOUND" if no such
# record exists at all.
field_of() { # $1 ledger $2 invocation_id $3 event $4 field
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, sys
path, invid, event, field = sys.argv[1:5]
for line in open(path):
    line = line.strip()
    if not line:
        continue
    r = json.loads(line)
    if r.get("invocation_id") == invid and r.get("event") == event:
        print(json.dumps(r[field]) if field in r else "MISSING")
        break
else:
    print("NOTFOUND")
PY
}

# Same idea for the cap_trip terminal record, which carries no invocation_id.
cap_trip_field() { # $1 ledger $2 field
  python3 - "$1" "$2" <<'PY'
import json, sys
path, field = sys.argv[1:3]
for line in open(path):
    line = line.strip()
    if not line:
        continue
    r = json.loads(line)
    if r.get("event") == "cap_trip":
        print(json.dumps(r[field]) if field in r else "MISSING")
        break
else:
    print("NOTFOUND")
PY
}

REWORK_PROMPT=$'Unit:  cost-measurement-v0.2\nSlice: S5\n\nBuild rework attribution.'

# -- (a) red -> red -> red: the finish record is marked rework in full, with
# a refine-pass count (W1, W7). Default cap is 3, so the 3rd consecutive
# failure both marks rework AND trips the cap (covers (f) too).
SESSION_A="sess-rework-a"
rcost "$(start_json loop-build toolu-rwa1 "Build S5" "$REWORK_PROMPT" "$SESSION_A")" >/dev/null
rcost "$(bash_test_json "$SESSION_A" loop-build RwATest fail)" >/dev/null
rcost "$(bash_test_json "$SESSION_A" loop-build RwATest fail)" >/dev/null
rcost "$(bash_test_json "$SESSION_A" loop-build RwATest fail)" >/dev/null
rcost "$(finish_json loop-build toolu-rwa1 "Build S5" "$REWORK_PROMPT" "$SESSION_A" completed 5000 2000 "")" >/dev/null

expect "(a) red-red-red: finish record carries phase_detail:rework" '"rework"' \
  "$(field_of "$RLEDGER" toolu-rwa1 finish phase_detail)"
REFINE_A="$(field_of "$RLEDGER" toolu-rwa1 finish refine_passes)"
expect "(a) red-red-red: refine_passes present and >= 1" "yes" \
  "$([ "$REFINE_A" != "MISSING" ] && [ "$REFINE_A" != "NOTFOUND" ] && [ "$REFINE_A" -ge 1 ] 2>/dev/null && echo yes || echo no)"

# -- (b) red -> green: not rework (W7).
SESSION_B="sess-rework-b"
rcost "$(start_json loop-build toolu-rwb1 "Build S5" "$REWORK_PROMPT" "$SESSION_B")" >/dev/null
rcost "$(bash_test_json "$SESSION_B" loop-build RwBTest fail)" >/dev/null
rcost "$(bash_test_json "$SESSION_B" loop-build RwBTest pass)" >/dev/null
rcost "$(finish_json loop-build toolu-rwb1 "Build S5" "$REWORK_PROMPT" "$SESSION_B" completed 900 90 "")" >/dev/null
expect "(b) red-green: finish record carries no phase_detail" "MISSING" \
  "$(field_of "$RLEDGER" toolu-rwb1 finish phase_detail)"

# -- (c) red -> green -> red -> green: still not rework -- the discriminating
# case, because the loose reading ("any failure ever") would mark this and
# read 100% rework forever (W2, W7).
SESSION_C="sess-rework-c"
rcost "$(start_json loop-build toolu-rwc1 "Build S5" "$REWORK_PROMPT" "$SESSION_C")" >/dev/null
rcost "$(bash_test_json "$SESSION_C" loop-build RwCTest fail)" >/dev/null
rcost "$(bash_test_json "$SESSION_C" loop-build RwCTest pass)" >/dev/null
rcost "$(bash_test_json "$SESSION_C" loop-build RwCTest fail)" >/dev/null
rcost "$(bash_test_json "$SESSION_C" loop-build RwCTest pass)" >/dev/null
rcost "$(finish_json loop-build toolu-rwc1 "Build S5" "$REWORK_PROMPT" "$SESSION_C" completed 800 80 "")" >/dev/null
expect "(c) red-green-red-green: finish record carries no phase_detail (discriminating case)" "MISSING" \
  "$(field_of "$RLEDGER" toolu-rwc1 finish phase_detail)"

# -- (d) rework and first-attempt records are separable by reading the
# ledger alone -- a plain grep over the file, no external input (W3). At
# this point exactly one finish (rwa1) is rework and two (rwb1, rwc1) are not.
REWORK_FINISH_COUNT="$(grep '"event":"finish"' "$RLEDGER" | grep -c '"phase_detail":"rework"')"
NONREWORK_FINISH_COUNT="$(grep '"event":"finish"' "$RLEDGER" | grep -vc '"phase_detail":"rework"')"
expect "(d) grep alone partitions rework from first-attempt finish records" "1 2" \
  "$REWORK_FINISH_COUNT $NONREWORK_FINISH_COUNT"

# -- (e) no per-pass token figure anywhere: total_tokens is exactly what the
# finish payload carried, untouched by refine_passes (W5).
expect "(e) total_tokens is exactly the finish payload's value, never divided by refine_passes" "5000" \
  "$(field_of "$RLEDGER" toolu-rwa1 finish total_tokens)"
expect "(e) the script never computes a rework percentage/ratio/share (D3 rejected)" "0" \
  "$(grep -qiE 'rework[_-]?(percent|ratio|share)' "$SCRIPTS/record-cost-event.sh" && echo 1 || echo 0)"

# -- (f) a tripped cap writes its own terminal record naming the slice and
# the rework total at whole-invocation granularity (W6).
expect "(f) cap trip: terminal record names the slug" '"cost-measurement-v0.2"' \
  "$(cap_trip_field "$RLEDGER" slug)"
expect "(f) cap trip: terminal record names the slice" '"S5"' \
  "$(cap_trip_field "$RLEDGER" slice)"
expect "(f) cap trip: refine_passes is the whole-invocation total (3, the cap)" "3" \
  "$(cap_trip_field "$RLEDGER" refine_passes)"

# -- (g) the D3 granularity/over-attribution/non-comparability statement is
# in the script header, in prose (W4) -- so S6 can lift it into README.
expect "(g) script header states what the rework figure measures and its bias (W4)" "0" \
  "$(grep -q 'the cost of slices that were not right first time' "$SCRIPTS/record-cost-event.sh" \
     && grep -q 'over-attribut' "$SCRIPTS/record-cost-event.sh" \
     && grep -q 'whole-invocation granularity' "$SCRIPTS/record-cost-event.sh" \
     && grep -q '<15%' "$SCRIPTS/record-cost-event.sh" \
     && echo 0 || echo 1)"

# -- (h) enforce-refine-cap.sh is untouched, byte-for-byte (W8, X2).
expect "(h) scripts/enforce-refine-cap.sh has no diff against the committed tree" "" \
  "$(cd "$ROOT" && git diff -- scripts/enforce-refine-cap.sh)"

# -- attribution rule, pinned in the brief: session_id + agent_type (+ cwd
# when both sides carry one). When it cannot be narrowed to exactly one open
# invocation, EVERY open invocation of that agent in that session is marked,
# with rework_attribution:"ambiguous" -- over-attribution is the accepted
# bias, never a silent guess.
SESSION_AMB="sess-rework-amb"
rcost "$(start_json loop-build toolu-amb1 "Build amb1" "$REWORK_PROMPT" "$SESSION_AMB")" >/dev/null
rcost "$(start_json loop-build toolu-amb2 "Build amb2" "$REWORK_PROMPT" "$SESSION_AMB")" >/dev/null
rcost "$(bash_test_json "$SESSION_AMB" loop-build AmbTest fail)" >/dev/null
rcost "$(bash_test_json "$SESSION_AMB" loop-build AmbTest fail)" >/dev/null
rcost "$(finish_json loop-build toolu-amb1 "Build amb1" "$REWORK_PROMPT" "$SESSION_AMB" completed 100 10 "")" >/dev/null
rcost "$(finish_json loop-build toolu-amb2 "Build amb2" "$REWORK_PROMPT" "$SESSION_AMB" completed 200 20 "")" >/dev/null

expect "ambiguous attribution: every open invocation in the session is marked rework" '"rework" "rework"' \
  "$(field_of "$RLEDGER" toolu-amb1 finish phase_detail) $(field_of "$RLEDGER" toolu-amb2 finish phase_detail)"
expect "ambiguous attribution: both carry rework_attribution:ambiguous" '"ambiguous" "ambiguous"' \
  "$(field_of "$RLEDGER" toolu-amb1 finish rework_attribution) $(field_of "$RLEDGER" toolu-amb2 finish rework_attribution)"

# cwd narrows the match to one invocation when both sides carry one --
# concurrent build worktrees are the real case this covers.
SESSION_CWD="sess-rework-cwd"
rcost "$(start_json loop-build toolu-cwda "Build cwdA" "$REWORK_PROMPT" "$SESSION_CWD" "/worktrees/a")" >/dev/null
rcost "$(start_json loop-build toolu-cwdb "Build cwdB" "$REWORK_PROMPT" "$SESSION_CWD" "/worktrees/b")" >/dev/null
rcost "$(bash_test_json "$SESSION_CWD" loop-build CwdTest fail "/worktrees/a")" >/dev/null
rcost "$(bash_test_json "$SESSION_CWD" loop-build CwdTest fail "/worktrees/a")" >/dev/null
rcost "$(finish_json loop-build toolu-cwda "Build cwdA" "$REWORK_PROMPT" "$SESSION_CWD" completed 300 30 "")" >/dev/null
rcost "$(finish_json loop-build toolu-cwdb "Build cwdB" "$REWORK_PROMPT" "$SESSION_CWD" completed 400 40 "")" >/dev/null

expect "cwd narrows attribution to the matching-cwd invocation only" '"rework" MISSING' \
  "$(field_of "$RLEDGER" toolu-cwda finish phase_detail) $(field_of "$RLEDGER" toolu-cwdb finish phase_detail)"

# -- arrival trim, the frequent real path (S5, spec.md OQ1, obligation
# class 3): NOT a rework-attribution case -- placed here only because
# bash_test_json() (needed to build a PostToolUse/Bash event) is defined in
# this section, per S5's placement constraint. A passing test run is the
# most frequent hook arrival in a real session and appends nothing of its
# own; against a ledger seeded over cap it still trims to cap, unconditionally.
BASHARR_DIR="$(mktemp -d)"
BASHARR_LEDGER="$BASHARR_DIR/.claude/loop-cost.jsonl"
mkdir -p "$BASHARR_DIR/.claude"
BASHARR_CAP=15
n=1; while [ "$n" -le $((BASHARR_CAP + 5)) ]; do printf '{"seed":%d}\n' "$n" >> "$BASHARR_LEDGER"; n=$((n + 1)); done
BASHARR_EXIT="$(CLAUDE_PROJECT_DIR="$BASHARR_DIR" CLAUDE_PLUGIN_ROOT="$ROOT" LARAVEL_LOOP_COST_MAX_LINES=$BASHARR_CAP \
  run_hook record-cost-event.sh "$(bash_test_json sess-basharr loop-build BashArrTest pass)")"
BASHARR_COUNT="$(wc -l < "$BASHARR_LEDGER" | tr -d ' ')"
BASHARR_APPENDED="$(grep -q BashArrTest "$BASHARR_LEDGER" && echo yes || echo no)"
expect "arrival trim: a passing Bash event over cap trims to cap, appends no line of its own, exits 0" "$BASHARR_CAP no 0" \
  "$BASHARR_COUNT $BASHARR_APPENDED $BASHARR_EXIT"
rm -rf "$BASHARR_DIR"

rm -rf "$REWORKDIR"

# ---------------------------------------------------------------------------
echo "cost report (/cost — scripts/cost-report.sh, scripts/cost-ledger-lib.sh)"

report() { # $1 CLAUDE_PROJECT_DIR $2 slug (optional)
  CLAUDE_PROJECT_DIR="$1" bash "$SCRIPTS/cost-report.sh" "${2:-}"
}
report_exit() { # $1 CLAUDE_PROJECT_DIR $2 slug (optional)
  CLAUDE_PROJECT_DIR="$1" bash "$SCRIPTS/cost-report.sh" "${2:-}" >/dev/null 2>&1
  echo $?
}

# The mixed fixture: one priced spec invocation, one unpriced (async_launched)
# build invocation, one in-flight build invocation, a cap_trip terminal
# record naming the same slug, one malformed raw line, one verify invocation
# whose finish fell back to the line_too_long shape (E6), and a fifth
# invocation under slug:"unknown" carrying its own distinct token figure so
# a bug that merged it into "mixed-unit" would be caught, not just unnoticed.
MIXDIR="$(mktemp -d)"
mkdir -p "$MIXDIR/.claude"
MIXLEDGER="$MIXDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"a1","session_id":"s1","slug":"mixed-unit","slice":"S1","phase":"spec","agent":"loop-spec","model":"claude-opus-4","model_source":"observed"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"a1","session_id":"s1","slug":"mixed-unit","slice":"S1","phase":"spec","agent":"loop-spec","model":"claude-opus-4","model_source":"observed","status":"completed","duration_ms":5000,"total_tokens":60787,"input_tokens":50000,"output_tokens":10787}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"a2","session_id":"s1","slug":"mixed-unit","slice":"S2","phase":"build","agent":"loop-build","model":"claude-sonnet-4","model_source":"derived"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"a2","session_id":"s1","slug":"mixed-unit","slice":"S2","phase":"build","agent":"loop-build","model":"claude-sonnet-4","model_source":"derived","status":"async_launched"}'
  printf '%s\n' '{"ts":5,"event":"start","invocation_id":"a3","session_id":"s1","slug":"mixed-unit","slice":"S3","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":6,"event":"cap_trip","session_id":"s1","agent":"loop-build","target":"suite","slug":"mixed-unit","slice":"S4","phase_detail":"rework","refine_passes":3}'
  printf '%s\n' 'this line is not valid json at all {'
  printf '%s\n' '{"ts":7,"event":"start","invocation_id":"a4","session_id":"s1","slug":"mixed-unit","phase":"verify","agent":"loop-verify"}'
  printf '%s\n' '{"ts":8,"event":"finish","invocation_id":"a4","slug":"mixed-unit","phase":"verify","agent":"loop-verify","status":"line_too_long"}'
  printf '%s\n' '{"ts":9,"event":"start","invocation_id":"a5","slug":"unknown","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":10,"event":"finish","invocation_id":"a5","slug":"unknown","phase":"build","agent":"loop-build","status":"completed","total_tokens":42}'
} > "$MIXLEDGER"

MIX_OUT="$(report "$MIXDIR" mixed-unit)"

# (a) CV1 — Coverage: appears at a lower line number than any token figure.
mix_coverage_line="$(printf '%s\n' "$MIX_OUT" | grep -n '^Coverage:' | head -1 | cut -d: -f1)"
mix_tokens_line="$(printf '%s\n' "$MIX_OUT" | grep -n 'total priced tokens' | head -1 | cut -d: -f1)"
expect "(a) mixed fixture: Coverage: precedes any token figure (CV1)" "yes" \
  "$( [ -n "$mix_coverage_line" ] && [ -n "$mix_tokens_line" ] && [ "$mix_coverage_line" -lt "$mix_tokens_line" ] && echo yes || echo no )"

# (c) CV3/CV5 — total labelled as covering the priced subset, unpriced count
# in the SAME section (within a few lines of the heading, not a footnote).
mix_heading_line="$(printf '%s\n' "$MIX_OUT" | grep -n 'priced subset only' | head -1 | cut -d: -f1)"
mix_unpriced_line="$(printf '%s\n' "$MIX_OUT" | grep -n 'unpriced, not counted' | tail -1 | cut -d: -f1)"
expect "(c) mixed fixture: priced-subset label and unpriced count share the Tokens section (CV3, CV5)" "yes" \
  "$( [ -n "$mix_heading_line" ] && [ -n "$mix_unpriced_line" ] && [ "$mix_unpriced_line" -ge "$mix_heading_line" ] && [ $((mix_unpriced_line - mix_heading_line)) -le 3 ] && echo yes || echo no )"
expect "(c) mixed fixture: priced total is exactly the priced invocation's tokens, never diluted by unpriced-as-zero (CV5)" "60787" \
  "$(printf '%s\n' "$MIX_OUT" | grep 'total priced tokens' | grep -oE '[0-9]+')"

# (f) CO9 — slug:"unknown" is its own bucket: mixed-unit's total must not
# absorb the unknown-slug invocation's 42 tokens, and unknown's own report
# must show exactly that 42, isolated.
UNKNOWN_OUT="$(report "$MIXDIR" unknown)"
expect "(f) slug:unknown is its own bucket, not merged into mixed-unit (CO9)" "42" \
  "$(printf '%s\n' "$UNKNOWN_OUT" | grep 'total priced tokens' | grep -oE '[0-9]+')"

# (g) CO10 — verified directly against the lib's own counters, the most
# precise place to prove cap_trip/line_too_long/in-flight are each handled
# as spec.md requires rather than inferring it from prose.
co10_check() {
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$MIXLEDGER" "mixed-unit"
  # 4 invocations: a1 (priced), a2 (unpriced), a3 (in-flight), a4 (unpriced,
  # line_too_long) -- cap_trip contributes to neither COST_N_INVOCATIONS nor
  # COST_N_UNPRICED.
  [ "$COST_N_INVOCATIONS" = "4" ] || { echo "bad invocations $COST_N_INVOCATIONS"; return 1; }
  [ "$COST_N_PRICED" = "1" ] || { echo "bad priced $COST_N_PRICED"; return 1; }
  [ "$COST_N_UNPRICED" = "2" ] || { echo "bad unpriced $COST_N_UNPRICED"; return 1; }
  [ "$COST_N_INFLIGHT" = "1" ] || { echo "bad inflight $COST_N_INFLIGHT"; return 1; }
  [ "$COST_N_CAPTRIP" = "1" ] || { echo "bad captrip $COST_N_CAPTRIP"; return 1; }
  echo ok
}
expect "(g) cap_trip excluded, line_too_long unpriced, in-flight its own bucket (CO10)" "ok" "$(co10_check)"

# --- cost-ledger-blind-to-background-agents S2 (CL4): coverage as a share,
# and the phases that are wholly unobserved -- named alongside it. Computed
# from the per-phase COST_N_* variables cost_scan already sets (CV7: no
# second parse). mixed-unit is 1 of 4 invocations priced (build's a2/a3 and
# verify's a4 are unpriced or in-flight; spec's a1 is priced) -> 25%, with
# build and verify each wholly unobserved (>=1 invocation, 0 priced) and
# slice named nowhere (0 invocations for this unit -- absence is not a gap).
MIX_COVERAGE_LINE="$(printf '%s\n' "$MIX_OUT" | grep '^  based on' | head -1)"
expect "(S2-1) CL4: coverage sentence carries the share as a percentage (25%)" "yes" \
  "$(printf '%s\n' "$MIX_COVERAGE_LINE" | grep -qE '25 ?%' && echo yes || echo no)"
expect "(S2-2) CL4: build has invocations and zero priced -> named wholly unobserved" "yes" \
  "$(printf '%s\n' "$MIX_COVERAGE_LINE" | grep -qE 'wholly unobserved:.*\bbuild\b' && echo yes || echo no)"
expect "(S2-3) CL4 bound: slice has zero invocations for this unit -> never named" "no" \
  "$(printf '%s\n' "$MIX_COVERAGE_LINE" | grep -qE 'wholly unobserved:.*\bslice\b' && echo yes || echo no)"

# (S2-5) CL8 bound: a unit present only via a cap_trip record has zero
# invocations and zero priced (0/0) -- the share must render as a plain,
# non-crashing figure rather than a division-by-zero error or empty string,
# and with nothing observed for any phase, none is named wholly unobserved.
ZEROINVDIR="$(mktemp -d)"
mkdir -p "$ZEROINVDIR/.claude"
printf '%s\n' '{"ts":1,"event":"cap_trip","slug":"zero-inv-unit","phase_detail":"rework","refine_passes":1}' \
  > "$ZEROINVDIR/.claude/loop-cost.jsonl"
ZEROINV_OUT="$(report "$ZEROINVDIR" zero-inv-unit)"
ZEROINV_LINE="$(printf '%s\n' "$ZEROINV_OUT" | grep '^  based on' | head -1)"
expect "(S2-5) CL8 bound: 0-of-0 fixture: report exits 0" "0" "$(report_exit "$ZEROINVDIR" zero-inv-unit)"
expect "(S2-5) CL8 bound: 0-of-0 fixture: share renders as a plain 0%, no division-by-zero garbage" "yes" \
  "$(printf '%s\n' "$ZEROINV_LINE" | grep -qE '0 ?% coverage' && echo yes || echo no)"
expect "(S2-5) CL8 bound: 0-of-0 fixture: no phase is named wholly unobserved" "no" \
  "$(printf '%s\n' "$ZEROINV_LINE" | grep -q 'wholly unobserved' && echo yes || echo no)"
rm -rf "$ZEROINVDIR"

# (e) CO8 — the one malformed line above is skipped and counted, never
# silently dropped from the total without saying so.
expect "(e) one malformed line: skipped-count reported, never silent (CO8)" "yes" \
  "$(printf '%s\n' "$MIX_OUT" | grep -q '1 ledger line(s) skipped' && echo yes || echo no)"

THREEBAD_DIR="$(mktemp -d)"
mkdir -p "$THREEBAD_DIR/.claude"
THREEBAD_LEDGER="$THREEBAD_DIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' 'not json 1'
  printf '%s\n' 'not json 2 {{{'
  printf '%s\n' '{"broken truncated line with no closing'
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"z1","slug":"three-bad","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"z1","slug":"three-bad","phase":"build","agent":"loop-build","status":"completed","total_tokens":10}'
} > "$THREEBAD_LEDGER"
THREEBAD_OUT="$(report "$THREEBAD_DIR" three-bad)"
expect "(e) three malformed/truncated lines: skipped count is 3, exit 0 (CO8)" "yes" \
  "$(printf '%s\n' "$THREEBAD_OUT" | grep -q '3 ledger line(s) skipped' && echo yes || echo no)"
expect "(e) three malformed lines: report still exits 0" "0" "$(report_exit "$THREEBAD_DIR" three-bad)"
rm -rf "$THREEBAD_DIR"

# (b) CV6/CV2 — every invocation unpriced: no Tokens table, no token figure
# of 0, and the reason is stated in its own plain sentence.
COLDDIR="$(mktemp -d)"
mkdir -p "$COLDDIR/.claude"
COLDLEDGER="$COLDDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"b1","slug":"cold-unit","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"b1","slug":"cold-unit","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"b2","slug":"cold-unit","phase":"verify","agent":"loop-verify"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"b2","slug":"cold-unit","phase":"verify","agent":"loop-verify","status":"async_launched"}'
} > "$COLDLEDGER"
COLD_OUT="$(report "$COLDDIR" cold-unit)"
expect "(b) all-unpriced fixture: no Tokens (priced subset) heading is printed (CV6)" "no" \
  "$(printf '%s\n' "$COLD_OUT" | grep -q 'priced subset only' && echo yes || echo no)"
expect "(b) all-unpriced fixture: the reason is stated plainly (CV6)" "yes" \
  "$(printf '%s\n' "$COLD_OUT" | grep -qi "nothing about this unit's token cost is observable" && echo yes || echo no)"
expect "(b) all-unpriced fixture: no line reads a token figure of 0 (CV2)" "0" \
  "$(printf '%s\n' "$COLD_OUT" | grep -icE 'tokens?:[[:space:]]*0\b')"

# (d) CO3 — three distinguishable, non-crashing, non-tabular empty states.
ABSENTDIR="$(mktemp -d)"
ABSENT_OUT="$(report "$ABSENTDIR")"
expect "(d) absent ledger: names hooks-not-wired (CO3)" "yes" \
  "$(printf '%s\n' "$ABSENT_OUT" | grep -qi 'hooks are not wired' && echo yes || echo no)"
expect "(d) absent ledger: names LARAVEL_LOOP_COST_LEDGER=0 (CO3)" "yes" \
  "$(printf '%s\n' "$ABSENT_OUT" | grep -q 'LARAVEL_LOOP_COST_LEDGER=0' && echo yes || echo no)"
expect "(d) absent ledger: exits 0" "0" "$(report_exit "$ABSENTDIR")"
expect "(d) absent ledger: prints no table" "no" \
  "$(printf '%s\n' "$ABSENT_OUT" | grep -q 'Coverage:' && echo yes || echo no)"
rm -rf "$ABSENTDIR"

EMPTYDIR="$(mktemp -d)"
mkdir -p "$EMPTYDIR/.claude"
: > "$EMPTYDIR/.claude/loop-cost.jsonl"
EMPTY_OUT="$(report "$EMPTYDIR")"
expect "(d) empty ledger: distinct message from the absent case (CO3)" "yes" \
  "$(printf '%s\n' "$EMPTY_OUT" | grep -qi 'holds no records yet' && echo yes || echo no)"
expect "(d) empty ledger: exits 0" "0" "$(report_exit "$EMPTYDIR")"
expect "(d) empty ledger: prints no table" "no" \
  "$(printf '%s\n' "$EMPTY_OUT" | grep -q 'Coverage:' && echo yes || echo no)"
rm -rf "$EMPTYDIR"

NOSLUG_OUT="$(report "$MIXDIR" totally-unrequested-slug)"
expect "(d) unknown slug: distinct message listing the slugs present (CO3)" "yes" \
  "$(printf '%s\n' "$NOSLUG_OUT" | grep -qi 'No records for unit' && echo yes || echo no)"
expect "(d) unknown slug: lists mixed-unit as a present slug" "yes" \
  "$(printf '%s\n' "$NOSLUG_OUT" | grep -q 'mixed-unit' && echo yes || echo no)"
expect "(d) unknown slug: exits 0" "0" "$(report_exit "$MIXDIR" totally-unrequested-slug)"
expect "(d) unknown slug: prints no table" "no" \
  "$(printf '%s\n' "$NOSLUG_OUT" | grep -q 'Coverage:' && echo yes || echo no)"

# (h) CO1 — no slug: one line per unit, most recent first, each with its
# coverage.
LIST_OUT="$(report "$MIXDIR")"
expect "(h) no-slug listing: mentions every unit present" "yes" \
  "$(printf '%s\n' "$LIST_OUT" | grep -q 'mixed-unit' && printf '%s\n' "$LIST_OUT" | grep -q 'unknown' && echo yes || echo no)"
UNK_LN="$(printf '%s\n' "$LIST_OUT" | grep -n '  unknown ' | head -1 | cut -d: -f1)"
MIX_LN="$(printf '%s\n' "$LIST_OUT" | grep -n '  mixed-unit ' | head -1 | cut -d: -f1)"
expect "(h) no-slug listing: most recent unit first (unknown's last ts is 10, mixed-unit's is 8)" "yes" \
  "$( [ -n "$UNK_LN" ] && [ -n "$MIX_LN" ] && [ "$UNK_LN" -lt "$MIX_LN" ] && echo yes || echo no )"
expect "(h) no-slug listing: each unit line carries its own coverage sentence (2 units)" "2" \
  "$(printf '%s\n' "$LIST_OUT" | grep -c 'invocations that carry a token figure')"

# (i) CV7 — the identical ledger produces byte-identical stdout on a repeat run.
MIX_OUT_2="$(report "$MIXDIR" mixed-unit)"
expect "(i) same fixture run twice: byte-identical stdout (CV7)" "" \
  "$(diff <(printf '%s' "$MIX_OUT") <(printf '%s' "$MIX_OUT_2"))"

# (j) CO13 — PATH stripped of jq and python3: says so, exits 0, no partial report.
COST_NOPARSER_BIN="$(mktemp -d)"
for b in cat mkdir date sed bash grep; do
  p="$(command -v "$b" 2>/dev/null)"
  [ -n "$p" ] && ln -s "$p" "$COST_NOPARSER_BIN/$b"
done
COST_NOPARSER_OUT="$(PATH="$COST_NOPARSER_BIN" report "$MIXDIR" mixed-unit)"
COST_NOPARSER_EXIT="$(PATH="$COST_NOPARSER_BIN" report_exit "$MIXDIR" mixed-unit)"
expect "(j) PATH stripped of jq+python3: exits 0 (CO13)" "0" "$COST_NOPARSER_EXIT"
expect "(j) PATH stripped of jq+python3: says it cannot read the ledger (CO13)" "yes" \
  "$(printf '%s\n' "$COST_NOPARSER_OUT" | grep -qi 'neither jq nor python3' && echo yes || echo no)"
expect "(j) PATH stripped of jq+python3: prints no partial report" "no" \
  "$(printf '%s\n' "$COST_NOPARSER_OUT" | grep -q 'Coverage:' && echo yes || echo no)"
rm -rf "$COST_NOPARSER_BIN"

# (k) CO2 — no network tooling and no reading of another plugin's feed.
expect "(k) no curl/wget/nc/agents-board reference in the cost scripts (CO2)" "1" \
  "$(grep -E 'curl|wget|nc |agents-board' "$SCRIPTS/cost-report.sh" "$SCRIPTS/cost-ledger-lib.sh" >/dev/null 2>&1; echo $?)"

# (l) BG6 — no reassurance token anywhere in any fixture's output above.
ALL_COST_OUTPUT="$MIX_OUT
$UNKNOWN_OUT
$COLD_OUT
$ABSENT_OUT
$EMPTY_OUT
$NOSLUG_OUT
$LIST_OUT"
expect "(l) no reassurance token in any fixture's output (BG6)" "1" \
  "$(printf '%s\n' "$ALL_COST_OUTPUT" | grep -iE 'within budget|under budget|✓' >/dev/null 2>&1; echo $?)"

# (m) commands/cost.md declares no write-capable tool -- the ship.md pattern.
COSTMD="$ROOT/commands/cost.md"
expect "(m) commands/cost.md declares no write-capable tool" "0" \
  "$( grep '^allowed-tools:' "$COSTMD" | grep -qE '\b(Write|Edit|MultiEdit|NotebookEdit|Agent)\b' && echo 1 || echo 0 )"
expect "(m) commands/cost.md relays the report script's output verbatim" "0" \
  "$( grep -q 'scripts/cost-report.sh' "$COSTMD" && grep -qi 'relay' "$COSTMD" && echo 0 || echo 1 )"

# (n) the pre-existing "every commands/*.md has a row in README's Commands
# table" case (line ~1174 below) now exercises commands/cost.md too -- no
# separate case needed here; confirmed still green in the docs section below.

rm -rf "$MIXDIR"

# ---------------------------------------------------------------------------
# cost-ledger-blind-to-background-agents S1 (spec.md CL1, CL2, CL9) -- every
# unpriced invocation is reported with the reason it is unpriced, taken only
# from its finish record's own `status` field, and a launched-in-background
# invocation is never presented as an observed outcome. Extends the mixed
# fixture / co10_check pattern above rather than inventing a second one.
echo "cost report reasons (CL1, CL2, CL9 -- spec.md, cost-ledger-blind-to-background-agents)"

CL1DIR="$(mktemp -d)"
mkdir -p "$CL1DIR/.claude"
CL1LEDGER="$CL1DIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"c1","slug":"cl1-fixture","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"c1","slug":"cl1-fixture","phase":"spec","agent":"loop-spec","status":"completed","total_tokens":1000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"c2","slug":"cl1-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"c2","slug":"cl1-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":5,"event":"start","invocation_id":"c3","slug":"cl1-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":6,"event":"finish","invocation_id":"c3","slug":"cl1-fixture","phase":"build","agent":"loop-build","status":"completed"}'
  printf '%s\n' '{"ts":7,"event":"start","invocation_id":"c4","slug":"cl1-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":8,"event":"finish","invocation_id":"c4","slug":"cl1-fixture","phase":"build","agent":"loop-build","status":"line_too_long"}'
  printf '%s\n' '{"ts":9,"event":"start","invocation_id":"c5","slug":"cl1-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":10,"event":"start","invocation_id":"c6","slug":"cl1-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":11,"event":"finish","invocation_id":"c6","slug":"cl1-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":12,"event":"start","invocation_id":"c7","slug":"cl1-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":13,"event":"finish","invocation_id":"c7","slug":"cl1-fixture","phase":"build","agent":"loop-build"}'
} > "$CL1LEDGER"
CL1_OUT="$(report "$CL1DIR" cl1-fixture)"

# Direct-lib check, the (g)/co10_check pattern: proves the counters rather
# than inferring them from prose, and pins the one CL9 boundary (case 6 --
# c7's finish has no `status` key at all) against being folded into
# BACKGROUNDED.
cl1_check() {
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$CL1LEDGER" "cl1-fixture"
  [ "$COST_N_INVOCATIONS" = "7" ] || { echo "bad invocations $COST_N_INVOCATIONS"; return 1; }
  [ "$COST_N_UNPRICED" = "5" ] || { echo "bad unpriced $COST_N_UNPRICED"; return 1; }
  [ "$COST_N_INFLIGHT" = "1" ] || { echo "bad inflight $COST_N_INFLIGHT"; return 1; }
  [ "$COST_N_UNPRICED_BACKGROUNDED" = "2" ] || { echo "bad backgrounded $COST_N_UNPRICED_BACKGROUNDED"; return 1; }
  [ "$COST_N_UNPRICED_NO_USAGE" = "1" ] || { echo "bad no-usage $COST_N_UNPRICED_NO_USAGE"; return 1; }
  [ "$COST_N_UNPRICED_TRUNCATED" = "1" ] || { echo "bad truncated $COST_N_UNPRICED_TRUNCATED"; return 1; }
  [ "$COST_N_UNPRICED_UNSTATED" = "1" ] || { echo "bad unstated $COST_N_UNPRICED_UNSTATED"; return 1; }
  echo ok
}
expect "(1)(2)(3)(4)(6) CL1/CL9: reason counters, in-flight excluded, no-status not folded into backgrounded" "ok" "$(cl1_check)"

# (1) CL1 -- async_launched is named as its own category: "backgrounded".
expect "(1) CL1: 2 async_launched finishes named 'launched in background, outcome never observed'" "yes" \
  "$(printf '%s\n' "$CL1_OUT" | grep -q '2 launched in background, outcome never observed' && echo yes || echo no)"

# (2) CL1 -- completed with no total_tokens is named "observed, no usage figure".
expect "(2) CL1: completed-but-tokenless finish named 'observed, no usage figure'" "yes" \
  "$(printf '%s\n' "$CL1_OUT" | grep -q '1 observed, no usage figure' && echo yes || echo no)"

# (3) CL1 -- status line_too_long is named "truncated", distinct from the other two.
expect "(3) CL1: line_too_long finish named 'truncated (ledger line too long)'" "yes" \
  "$(printf '%s\n' "$CL1_OUT" | grep -q '1 truncated (ledger line too long)' && echo yes || echo no)"

# (4) CL1 -- a start with no finish is still in flight, never counted as a
# reason (c5 contributes to none of the four reason counters -- proven above
# by cl1_check's sum: 2+1+1+1 = 5 = COST_N_UNPRICED, with c5 excluded entirely).
expect "(4) CL1: in-flight invocation (no finish) is not one of the reason categories" "yes" \
  "$(printf '%s\n' "$CL1_OUT" | grep -qE '^  1 invocation\(s\) started with no finish recorded yet -- in flight' && echo yes || echo no)"

# (6) CL9 -- a finish record with no `status` field at all is read without
# error (report still exits 0) and reported under its own "reason not
# stated" category, never reclassified as backgrounded (pinned by cl1_check
# above: COST_N_UNPRICED_BACKGROUNDED stays 2, not 3).
expect "(6) CL9: finish with no status field -- report exits 0" "0" "$(report_exit "$CL1DIR" cl1-fixture)"
expect "(6) CL9: finish with no status field named 'reason not stated', not backgrounded" "yes" \
  "$(printf '%s\n' "$CL1_OUT" | grep -q '1 reason not stated' && echo yes || echo no)"

rm -rf "$CL1DIR"

# (5) CL2/E5 -- the exact defect: two async_launched finishes and zero true
# in-flight invocations. Today's "0 invocation(s) ... in flight" line reads
# as if nothing is unresolved; after S1 it must not stand alone.
E5DIR="$(mktemp -d)"
mkdir -p "$E5DIR/.claude"
E5LEDGER="$E5DIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"e1","slug":"e5-fixture","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"e1","slug":"e5-fixture","phase":"spec","agent":"loop-spec","status":"completed","total_tokens":500}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"e2","slug":"e5-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"e2","slug":"e5-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":5,"event":"start","invocation_id":"e3","slug":"e5-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":6,"event":"finish","invocation_id":"e3","slug":"e5-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
} > "$E5LEDGER"
E5_OUT="$(report "$E5DIR" e5-fixture)"

expect "(5) CL2/E5: COST_N_INFLIGHT is genuinely 0 for this fixture (the exact E5 shape)" "0" \
  "$(source "$SCRIPTS/cost-ledger-lib.sh"; cost_scan "$E5LEDGER" "e5-fixture"; printf '%s' "$COST_N_INFLIGHT")"
expect "(5) CL2/E5: the in-flight line is NOT printed as a bare '... unpriced.'" "no" \
  "$(printf '%s\n' "$E5_OUT" | grep -qE 'in flight, not counted as unpriced\.[[:space:]]*$' && echo yes || echo no)"
expect "(5) CL2/E5: the in-flight statement names the 2 backgrounded invocations inline" "yes" \
  "$(printf '%s\n' "$E5_OUT" | grep -qE 'in flight, not counted as unpriced \(plus 2 launched in background and never subsequently observed' && echo yes || echo no)"

rm -rf "$E5DIR"

# ---------------------------------------------------------------------------
# cost-ledger-blind-to-background-agents S7 (spec.md RC1, RC2, RC5, RC6, CL9
# -- second G1, RC recovery group) -- the reader recognises an
# event:"recovered" line: counts that invocation once, counts it priced, and
# says in the report how much of the total was transcribed rather than
# host-observed. Extends the S1 mixed-fixture / cl1_check pattern above
# rather than inventing a second one. No writer exists yet (S9); every
# `recovered` line below is hand-written directly into the fixture ledger.
echo "cost report recovered figures (RC1, RC2, RC5, RC6, CL9 -- spec.md, cost-ledger-blind-to-background-agents S7)"

S7DIR="$(mktemp -d)"
mkdir -p "$S7DIR/.claude"
S7LEDGER="$S7DIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s7c1","slug":"s7-fixture","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s7c1","slug":"s7-fixture","phase":"spec","agent":"loop-spec","status":"completed","total_tokens":1000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"s7c2","slug":"s7-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"s7c2","slug":"s7-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":5,"event":"start","invocation_id":"s7c3","slug":"s7-fixture","phase":"verify","agent":"loop-verify"}'
  printf '%s\n' '{"ts":6,"event":"finish","invocation_id":"s7c3","slug":"s7-fixture","phase":"verify","agent":"loop-verify","status":"async_launched"}'
  printf '%s\n' '{"ts":7,"event":"recovered","invocation_id":"s7c2","slug":"s7-fixture","total_tokens":11035,"token_source":"transcribed"}'
} > "$S7LEDGER"

# The same fixture with the recovered line removed -- the comparison every
# RC1/RC5 case below needs, and (S7-5)'s own "nothing changed" fixture.
S7NORECDIR="$(mktemp -d)"
mkdir -p "$S7NORECDIR/.claude"
S7NORECLEDGER="$S7NORECDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s7c1","slug":"s7-fixture","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s7c1","slug":"s7-fixture","phase":"spec","agent":"loop-spec","status":"completed","total_tokens":1000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"s7c2","slug":"s7-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"s7c2","slug":"s7-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":5,"event":"start","invocation_id":"s7c3","slug":"s7-fixture","phase":"verify","agent":"loop-verify"}'
  printf '%s\n' '{"ts":6,"event":"finish","invocation_id":"s7c3","slug":"s7-fixture","phase":"verify","agent":"loop-verify","status":"async_launched"}'
} > "$S7NORECLEDGER"

S7_OUT="$(report "$S7DIR" s7-fixture)"
S7NOREC_OUT="$(report "$S7NORECDIR" s7-fixture)"

# (S7-1) RC5: the recovered figure prices the invocation; its tokens land in
# COST_TOKENS_PRICED alongside the host-observed one.
s7_check() {
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$S7LEDGER" "s7-fixture"
  [ "$COST_N_PRICED" = "2" ] || { echo "bad priced $COST_N_PRICED"; return 1; }
  [ "$COST_N_UNPRICED" = "1" ] || { echo "bad unpriced $COST_N_UNPRICED"; return 1; }
  [ "$COST_TOKENS_PRICED" = "12035" ] || { echo "bad tokens $COST_TOKENS_PRICED"; return 1; }
  [ "$COST_N_PRICED_TRANSCRIBED" = "1" ] || { echo "bad priced_transcribed $COST_N_PRICED_TRANSCRIBED"; return 1; }
  [ "$COST_TOKENS_TRANSCRIBED" = "11035" ] || { echo "bad tokens_transcribed $COST_TOKENS_TRANSCRIBED"; return 1; }
  echo ok
}
expect "(S7-1) RC5: recovered figure on an unpriced backgrounded invocation -> priced, its tokens in COST_TOKENS_PRICED" "ok" "$(s7_check)"

# (S7-2) RC1: COST_N_INVOCATIONS is identical with and without the recovered
# line -- the recovered record never creates a second invocation.
s7_invocations() { # $1 ledger $2 slug
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$1" "$2"
  printf '%s' "$COST_N_INVOCATIONS"
}
expect "(S7-2) RC1: COST_N_INVOCATIONS identical with the recovered line present or removed (no duplicate invocation)" "3 3" \
  "$(s7_invocations "$S7LEDGER" s7-fixture) $(s7_invocations "$S7NORECLEDGER" s7-fixture)"

# (S7-3) RC2: the report names the recovered figure as transcribed, distinct
# from a host-observed one, and states how much of the total is transcribed
# (both the count of priced figures and the token share).
expect "(S7-3) RC2: report names the figure transcribed / distinguishable from host-observed, states the count and token share" "yes" \
  "$(printf '%s\n' "$S7_OUT" | grep -qF 'transcribed rather than host-observed' \
     && printf '%s\n' "$S7_OUT" | grep -qE '1 of 2 priced figure\(s\) transcribed' \
     && printf '%s\n' "$S7_OUT" | grep -qE '11035 of 12035 priced token\(s\)' \
     && echo yes || echo no)"

# (S7-4) RC5: coverage share and the wholly-unobserved phase list both differ
# between the recovered and non-recovered fixtures -- build drops out of the
# wholly-unobserved list once its only invocation is priced by recovery,
# while verify (never recovered) stays named in both.
expect "(S7-4) RC5: coverage share differs between the two fixtures (66% vs 33%)" "yes" \
  "$(printf '%s\n' "$S7_OUT" | grep -qE '66 ?% coverage' && printf '%s\n' "$S7NOREC_OUT" | grep -qE '33 ?% coverage' && echo yes || echo no)"
expect "(S7-4) RC5: build is no longer named wholly unobserved once recovered; verify still is in both" "yes" \
  "$(printf '%s\n' "$S7_OUT" | grep -qE 'wholly unobserved:.*\bverify\b' \
     && ! printf '%s\n' "$S7_OUT" | grep -qE 'wholly unobserved:.*\bbuild\b' \
     && printf '%s\n' "$S7NOREC_OUT" | grep -qE 'wholly unobserved:.*\bbuild\b' \
     && printf '%s\n' "$S7NOREC_OUT" | grep -qE 'wholly unobserved:.*\bverify\b' \
     && echo yes || echo no)"

# (S7-5) RC6, CL9: a ledger with NO recovered record reads and reports
# exactly as before this slice -- no word about transcription anywhere, and
# the new counters both stay at zero.
expect "(S7-5) RC6/CL9: no recovered record -> no word about transcription anywhere in the report" "no" \
  "$(printf '%s\n' "$S7NOREC_OUT" | grep -qi 'transcri' && echo yes || echo no)"
s7_norec_counters() {
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$S7NORECLEDGER" "s7-fixture"
  printf '%s %s' "$COST_N_PRICED_TRANSCRIBED" "$COST_TOKENS_TRANSCRIBED"
}
expect "(S7-5) RC6/CL9: no recovered record -> the new counters both stay at zero" "0 0" "$(s7_norec_counters)"

rm -rf "$S7DIR" "$S7NORECDIR"

# (S7-6) RC1 bound: TWO recovered records for the same invocation_id --
# still one invocation, one figure, never a double count.
S7DUPDIR="$(mktemp -d)"
mkdir -p "$S7DUPDIR/.claude"
S7DUPLEDGER="$S7DUPDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s7d1","slug":"s7-dup-fixture","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s7d1","slug":"s7-dup-fixture","phase":"spec","agent":"loop-spec","status":"completed","total_tokens":1000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"s7d2","slug":"s7-dup-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"s7d2","slug":"s7-dup-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":5,"event":"recovered","invocation_id":"s7d2","slug":"s7-dup-fixture","total_tokens":11035,"token_source":"transcribed"}'
  printf '%s\n' '{"ts":6,"event":"recovered","invocation_id":"s7d2","slug":"s7-dup-fixture","total_tokens":11035,"token_source":"transcribed"}'
} > "$S7DUPLEDGER"
s7_dup_check() {
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$S7DUPLEDGER" "s7-dup-fixture"
  [ "$COST_N_INVOCATIONS" = "2" ] || { echo "bad invocations $COST_N_INVOCATIONS"; return 1; }
  [ "$COST_N_PRICED" = "2" ] || { echo "bad priced $COST_N_PRICED"; return 1; }
  [ "$COST_N_PRICED_TRANSCRIBED" = "1" ] || { echo "bad priced_transcribed $COST_N_PRICED_TRANSCRIBED"; return 1; }
  [ "$COST_TOKENS_PRICED" = "12035" ] || { echo "bad tokens $COST_TOKENS_PRICED"; return 1; }
  echo ok
}
expect "(S7-6) RC1 bound: two recovered records for one invocation_id -> one invocation, one figure, no double count" "ok" "$(s7_dup_check)"
rm -rf "$S7DUPDIR"

# ---------------------------------------------------------------------------
# cost-ledger-blind-to-background-agents S8 (spec.md RC3 -- second G1, RC
# recovery group) -- where an observed and a transcribed figure exist for the
# SAME invocation and disagree, both are shown, each attributed to its
# source, and the report states which one the total above actually used.
# Extends the S7 fixture pattern directly above rather than inventing a
# second one. No writer exists yet (S9); every `recovered` line below is
# hand-written directly into the fixture ledger.
echo "cost report observed/transcribed conflicts (RC3 -- spec.md, cost-ledger-blind-to-background-agents S8)"

S8DIR="$(mktemp -d)"
mkdir -p "$S8DIR/.claude"
S8LEDGER="$S8DIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s8c1","slug":"s8-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s8c1","slug":"s8-fixture","phase":"build","agent":"loop-build","status":"completed","total_tokens":12102}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s8c1","slug":"s8-fixture","total_tokens":11035,"token_source":"transcribed"}'
} > "$S8LEDGER"

# The same fixture with the recovered line removed -- the comparison (S8-2)'s
# arithmetic invariant needs.
S8NORECDIR="$(mktemp -d)"
mkdir -p "$S8NORECDIR/.claude"
S8NORECLEDGER="$S8NORECDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s8c1","slug":"s8-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s8c1","slug":"s8-fixture","phase":"build","agent":"loop-build","status":"completed","total_tokens":12102}'
} > "$S8NORECLEDGER"

S8_OUT="$(report "$S8DIR" s8-fixture)"

# (S8-1) RC3: both figures appear, each attributed to its source, and the
# rule (the observed figure is the one counted in the total) is stated.
expect "(S8-1) RC3: both figures appear, each attributed to its source, the rule stated" "yes" \
  "$(printf '%s\n' "$S8_OUT" | grep -qF 'observed 12102, transcribed 11035' \
     && printf '%s\n' "$S8_OUT" | grep -qF 'observed (host-measured) figure is the one counted in the total above' \
     && printf '%s\n' "$S8_OUT" | grep -qF 'transcribed (model-reported) figure is shown for comparison only' \
     && echo yes || echo no)"

# (S8-2) RC3 (arithmetic invariant): COST_TOKENS_PRICED is identical to the
# same ledger with the recovered line removed -- no average, no max, no
# overwrite. The observed figure alone is what the total uses.
s8_tokens_priced() { # $1 ledger $2 slug
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$1" "$2"
  printf '%s' "$COST_TOKENS_PRICED"
}
expect "(S8-2) RC3: COST_TOKENS_PRICED identical with the recovered line present or removed (no average, no max, no overwrite)" "12102 12102" \
  "$(s8_tokens_priced "$S8LEDGER" s8-fixture) $(s8_tokens_priced "$S8NORECLEDGER" s8-fixture)"

rm -rf "$S8DIR" "$S8NORECDIR"

# (S8-3) RC3 boundary: equal observed and transcribed figures are not a
# disagreement -- nothing about a conflict is printed.
S8EQDIR="$(mktemp -d)"
mkdir -p "$S8EQDIR/.claude"
S8EQLEDGER="$S8EQDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s8e1","slug":"s8-eq-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s8e1","slug":"s8-eq-fixture","phase":"build","agent":"loop-build","status":"completed","total_tokens":12102}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s8e1","slug":"s8-eq-fixture","total_tokens":12102,"token_source":"transcribed"}'
} > "$S8EQLEDGER"
S8EQ_OUT="$(report "$S8EQDIR" s8-eq-fixture)"
expect "(S8-3) RC3 bound: equal observed and transcribed figures -> no disagreement reported" "no" \
  "$(printf '%s\n' "$S8EQ_OUT" | grep -qi 'disagree' && echo yes || echo no)"
s8_eq_conflicts() {
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$S8EQLEDGER" "s8-eq-fixture"
  printf '%s' "$COST_N_CONFLICTS"
}
expect "(S8-3) RC3 bound: equal figures -> COST_N_CONFLICTS stays 0" "0" "$(s8_eq_conflicts)"
rm -rf "$S8EQDIR"

# (S8-4) RC6: a ledger with no recovered records at all -> output
# byte-identical to post-S7 -- no word about a conflict anywhere, since a
# disagreement needs two figures and this ledger never had a second one.
S8NONEDIR="$(mktemp -d)"
mkdir -p "$S8NONEDIR/.claude"
S8NONELEDGER="$S8NONEDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s8n1","slug":"s8-none-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s8n1","slug":"s8-none-fixture","phase":"build","agent":"loop-build","status":"completed","total_tokens":12102}'
} > "$S8NONELEDGER"
S8NONE_OUT="$(report "$S8NONEDIR" s8-none-fixture)"
expect "(S8-4) RC6: no recovered records at all -> no word about a conflict anywhere in the report" "no" \
  "$(printf '%s\n' "$S8NONE_OUT" | grep -qi 'disagree' && echo yes || echo no)"
s8_none_conflicts() {
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$S8NONELEDGER" "s8-none-fixture"
  printf '%s' "$COST_N_CONFLICTS"
}
expect "(S8-4) RC6: no recovered records at all -> COST_N_CONFLICTS stays 0" "0" "$(s8_none_conflicts)"
rm -rf "$S8NONEDIR"

# ---------------------------------------------------------------------------
# cost-ledger-blind-to-background-agents S9 (spec.md RC1, RC4, RC7 -- second
# G1, RC recovery group) -- scripts/record-recovered-cost.sh, the only
# WRITER of an event:"recovered" line. S7/S8 above taught the reader; this
# is the entry point that actually puts one into a real ledger. Standalone
# CLI, never wired into hooks/hooks.json, never reachable from a tool
# payload -- exercised here by invoking the script directly, exactly the way
# a human or an agent would type it.
echo "record-recovered-cost.sh (RC1, RC4, RC7 -- spec.md, cost-ledger-blind-to-background-agents S9)"

recover() { # $1 CLAUDE_PROJECT_DIR, then the script's own args
  local dir="$1"; shift
  CLAUDE_PROJECT_DIR="$dir" bash "$SCRIPTS/record-recovered-cost.sh" "$@"
}
recover_exit() { # $1 CLAUDE_PROJECT_DIR, then the script's own args
  local dir="$1"; shift
  CLAUDE_PROJECT_DIR="$dir" bash "$SCRIPTS/record-recovered-cost.sh" "$@" >/dev/null 2>&1
  echo $?
}

# Reads the recorded event:"recovered" line(s) for one invocation_id and
# checks: exactly one such line exists, its slug/total_tokens/token_source
# match, and it carries the pinned field set and NO other field.
recovered_fields_ok() { # $1 ledger $2 invocation_id $3 slug $4 tokens
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, sys

path, invid, slug, tokens = sys.argv[1:5]
tokens = int(tokens)
found = None
count = 0
for line in open(path):
    line = line.strip()
    if not line:
        continue
    r = json.loads(line)
    if r.get("event") == "recovered" and r.get("invocation_id") == invid:
        count += 1
        found = r
if count != 1:
    print(f"bad count {count}")
    sys.exit(0)
if found.get("slug") != slug:
    print("bad slug " + str(found.get("slug")))
    sys.exit(0)
if found.get("total_tokens") != tokens:
    print("bad tokens " + str(found.get("total_tokens")))
    sys.exit(0)
if found.get("token_source") != "transcribed":
    print("bad token_source " + str(found.get("token_source")))
    sys.exit(0)
if set(found.keys()) != {"ts", "event", "invocation_id", "slug", "total_tokens", "token_source"}:
    print("bad keys " + ",".join(sorted(found.keys())))
    sys.exit(0)
print("ok")
PY
}

# Fixture: two backgrounded (async_launched) invocations under the same
# unit. s9c1 is used for the happy path / exactly-once boundary; s9c2 is
# reserved, present in the ledger throughout, for the failure-mode cases
# below -- so a refusal in those cases is provably about the argument under
# test, never a side effect of "unknown invocation_id" leaking in.
S9DIR="$(mktemp -d)"
mkdir -p "$S9DIR/.claude"
S9LEDGER="$S9DIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s9c1","slug":"s9-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s9c1","slug":"s9-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"s9c2","slug":"s9-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"s9c2","slug":"s9-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
} > "$S9LEDGER"

# (S9-1) RC1: valid id + valid figure -> exactly one recovered line, pinned
# fields present, token_source "transcribed".
expect "(S9-1) RC1: valid id + valid figure -> exactly one recovered line, pinned fields, token_source transcribed" "0 ok" \
  "$(recover_exit "$S9DIR" --invocation-id s9c1 --total-tokens 11035) $(recovered_fields_ok "$S9LEDGER" s9c1 s9-fixture 11035)"

# (S9-2) RC1 exactly-once boundary: the same command run twice -> still
# exactly one line, mkdir "$FINISHED_DIR/_recovered/<id>" refuses the repeat.
expect "(S9-2) RC1 bound: the same command run twice -> still exactly one recovered line" "0 ok" \
  "$(recover_exit "$S9DIR" --invocation-id s9c1 --total-tokens 11035) $(recovered_fields_ok "$S9LEDGER" s9c1 s9-fixture 11035)"

# (S9-3) RC4: invocation_id absent from the ledger -> nothing written, exit 0.
S9_SNAP3="$(cat "$S9LEDGER")"
expect "(S9-3) RC4: invocation_id absent from the ledger -> nothing written, exit 0" "0 yes" \
  "$(recover_exit "$S9DIR" --invocation-id nope-not-there --total-tokens 42) $([ "$S9_SNAP3" = "$(cat "$S9LEDGER")" ] && echo yes || echo no)"

# (S9-4) RC4: non-numeric token figure -> nothing written, exit 0.
S9_SNAP4="$(cat "$S9LEDGER")"
expect "(S9-4) RC4: non-numeric token figure -> nothing written, exit 0" "0 yes" \
  "$(recover_exit "$S9DIR" --invocation-id s9c2 --total-tokens notanumber) $([ "$S9_SNAP4" = "$(cat "$S9LEDGER")" ] && echo yes || echo no)"

# (S9-5) RC4: missing required argument (--total-tokens omitted) -> nothing
# written, exit 0.
S9_SNAP5="$(cat "$S9LEDGER")"
expect "(S9-5) RC4: missing required argument -> nothing written, exit 0" "0 yes" \
  "$(recover_exit "$S9DIR" --invocation-id s9c2) $([ "$S9_SNAP5" = "$(cat "$S9LEDGER")" ] && echo yes || echo no)"

# (S9-6) RC4, v0.2: LARAVEL_LOOP_COST_LEDGER=0 -> nothing written, exit 0.
S9_SNAP6="$(cat "$S9LEDGER")"
S9_CASE6_EXIT="$(CLAUDE_PROJECT_DIR="$S9DIR" LARAVEL_LOOP_COST_LEDGER=0 bash "$SCRIPTS/record-recovered-cost.sh" --invocation-id s9c2 --total-tokens 999 >/dev/null 2>&1; echo $?)"
expect "(S9-6) RC4/v0.2: LARAVEL_LOOP_COST_LEDGER=0 -> nothing written, exit 0" "0 yes" \
  "$S9_CASE6_EXIT $([ "$S9_SNAP6" = "$(cat "$S9LEDGER")" ] && echo yes || echo no)"

rm -rf "$S9DIR"

# (S9-7) RC7: hooks/hooks.json names no recovery script, and
# record-cost-event.sh is unchanged by this slice -- the proof is a byte
# comparison against the committed tree, not a paraphrase.
expect "(S9-7) RC7: hooks.json names no recovery script; record-cost-event.sh untouched by this slice" "yes" \
  "$(cd "$ROOT" \
     && [ -z "$(git diff -- scripts/record-cost-event.sh)" ] \
     && [ -z "$(git diff -- hooks/hooks.json)" ] \
     && ! grep -q 'record-recovered-cost' hooks/hooks.json \
     && echo yes || echo no)"

# --- cost-ledger-blind-to-background-agents S3 (CL3): the report states, in
# its own output, why a backgrounded invocation's figure is absent -- printed
# once per report, only when the unit actually holds one, worded as a
# measured fact (E2's two probes) and never as a promise that OQ2's answer
# (S6: no hook can reach the channel) is about to change.
echo "cost report backgrounded-reason (CL3 -- spec.md, cost-ledger-blind-to-background-agents)"

# (S3-1) happy path: one backgrounded invocation -> the why-statement appears
# and names both halves of E2's finding (measured by the host, delivered into
# the session) plus that it is not captured here.
S3DIR="$(mktemp -d)"
mkdir -p "$S3DIR/.claude"
S3LEDGER="$S3DIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s3a","slug":"s3-fixture","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s3a","slug":"s3-fixture","phase":"spec","agent":"loop-spec","status":"completed","total_tokens":1000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"s3b","slug":"s3-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"s3b","slug":"s3-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
} > "$S3LEDGER"
S3_OUT="$(report "$S3DIR" s3-fixture)"
expect "(S3-1) CL3: fixture with a backgrounded invocation -> the why-statement names measured/delivered/not-captured-here" "yes" \
  "$(printf '%s\n' "$S3_OUT" | grep -qF 'measured by the host' \
     && printf '%s\n' "$S3_OUT" | grep -qF 'delivered into the session' \
     && printf '%s\n' "$S3_OUT" | grep -qF 'not captured here' \
     && echo yes || echo no)"
expect "(S3-1) Do NOT: the why-statement never states or implies recovery is coming, planned, or possible" "0" \
  "$(printf '%s\n' "$S3_OUT" | grep -icE 'will be recovered|recovery is|recovery will|planned|coming soon')"
rm -rf "$S3DIR"

# (S3-2) negation: an all-foreground fixture has no gap and is not told about
# one -- the why-statement does not appear.
S3FGDIR="$(mktemp -d)"
mkdir -p "$S3FGDIR/.claude"
S3FGLEDGER="$S3FGDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s3c","slug":"s3-fg-fixture","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s3c","slug":"s3-fg-fixture","phase":"spec","agent":"loop-spec","status":"completed","total_tokens":500}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"s3d","slug":"s3-fg-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"s3d","slug":"s3-fg-fixture","phase":"build","agent":"loop-build","status":"completed","total_tokens":250}'
} > "$S3FGLEDGER"
S3FG_OUT="$(report "$S3FGDIR" s3-fg-fixture)"
expect "(S3-2) CL3 negation: all-foreground fixture -> the why-statement does not appear" "no" \
  "$(printf '%s\n' "$S3FG_OUT" | grep -qF 'not captured here' && echo yes || echo no)"
rm -rf "$S3FGDIR"

# (S3-3) frequency boundary: three backgrounded invocations -> the
# why-statement appears exactly once, not three times (it explains the
# category, not each member of it -- S1's per-invocation count already did
# that).
S3THREEDIR="$(mktemp -d)"
mkdir -p "$S3THREEDIR/.claude"
S3THREELEDGER="$S3THREEDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s3e","slug":"s3-three-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s3e","slug":"s3-three-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"s3f","slug":"s3-three-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"s3f","slug":"s3-three-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":5,"event":"start","invocation_id":"s3g","slug":"s3-three-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":6,"event":"finish","invocation_id":"s3g","slug":"s3-three-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
} > "$S3THREELEDGER"
S3THREE_OUT="$(report "$S3THREEDIR" s3-three-fixture)"
expect "(S3-3) CL3 bound: three backgrounded invocations -> the why-statement appears exactly once" "1" \
  "$(printf '%s\n' "$S3THREE_OUT" | grep -cF 'not captured here')"
rm -rf "$S3THREEDIR"

# Characterisation case (CL7), honestly labelled as such: this proves a
# property S1 must hold and later slices (S2/S4) and the RC group must keep
# holding, not a new behaviour S1 introduces. Green before this slice and
# green after it.
CL7DIR="$(mktemp -d)"
mkdir -p "$CL7DIR/.claude"
CL7LEDGER="$CL7DIR/.claude/loop-cost.jsonl"
CL7BASEDIR="$(mktemp -d)"
mkdir -p "$CL7BASEDIR/.claude"
CL7BASELEDGER="$CL7BASEDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"cl7-p1","slug":"cl7-fixture","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"cl7-p1","slug":"cl7-fixture","phase":"spec","agent":"loop-spec","status":"completed","total_tokens":500}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"cl7-p2","slug":"cl7-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"cl7-p2","slug":"cl7-fixture","phase":"build","agent":"loop-build","status":"completed","total_tokens":700}'
} > "$CL7BASELEDGER"
cp "$CL7BASELEDGER" "$CL7LEDGER"
for i in $(seq 1 20); do
  printf '{"ts":%d,"event":"start","invocation_id":"cl7-u%d","slug":"cl7-fixture","phase":"build","agent":"loop-build"}\n' "$((4 + i))" "$i"
  printf '{"ts":%d,"event":"finish","invocation_id":"cl7-u%d","slug":"cl7-fixture","phase":"build","agent":"loop-build","status":"async_launched"}\n' "$((24 + i))" "$i"
done >> "$CL7LEDGER"

CL7_OUT="$(report "$CL7DIR" cl7-fixture)"
CL7BASE_OUT="$(report "$CL7BASEDIR" cl7-fixture)"
expect "(CL7 characterisation) 2 priced + 20 unpriced: same 'total priced tokens' as 2 priced alone" "yes" \
  "$( [ "$(printf '%s\n' "$CL7_OUT" | grep 'total priced tokens')" = "$(printf '%s\n' "$CL7BASE_OUT" | grep 'total priced tokens')" ] && echo yes || echo no )"
expect "(CL7 characterisation) 2 priced + 20 unpriced: COST_N_PRICED and COST_TOKENS_PRICED unaffected by the 20" "2 1200" \
  "$(source "$SCRIPTS/cost-ledger-lib.sh"; cost_scan "$CL7LEDGER" "cl7-fixture"; printf '%s %s' "$COST_N_PRICED" "$COST_TOKENS_PRICED")"

rm -rf "$CL7DIR" "$CL7BASEDIR"

# ---------------------------------------------------------------------------
echo "cost report coverage floor (LARAVEL_LOOP_COST_MIN_COVERAGE, S4, spec.md CL5 -- cost-ledger-blind-to-background-agents)"

report_floor() { # $1 CLAUDE_PROJECT_DIR $2 slug $3 floor value (may be empty -> unset)
  LARAVEL_LOOP_COST_MIN_COVERAGE="${3:-}" CLAUDE_PROJECT_DIR="$1" bash "$SCRIPTS/cost-report.sh" "$2"
}

S4FLOORDIR="$(mktemp -d)"
mkdir -p "$S4FLOORDIR/.claude"
S4FLOORLEDGER="$S4FLOORDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s4a","slug":"s4-floor-fixture","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s4a","slug":"s4-floor-fixture","phase":"spec","agent":"loop-spec","status":"completed","total_tokens":1000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"s4b","slug":"s4-floor-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"s4b","slug":"s4-floor-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
} > "$S4FLOORLEDGER"
# 1 of 2 invocations priced -> 50% coverage share, confirmed directly
# against the lib (the co10_check pattern) rather than trusted from prose.
s4_share_check() {
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$S4FLOORLEDGER" "s4-floor-fixture"
  [ "$COST_N_INVOCATIONS" = "2" ] || { echo "bad invocations $COST_N_INVOCATIONS"; return 1; }
  [ "$COST_N_PRICED" = "1" ] || { echo "bad priced $COST_N_PRICED"; return 1; }
  echo ok
}
expect "(S4-0) fixture: 1 of 2 invocations priced -> 50% coverage share" "ok" "$(s4_share_check)"

# (S4-1) unset -> the floor feature's OWN suppression behaviour is absent:
# the unit-level total still prints, and "cost read as not established"
# (the floor's own message, asserted verbatim in S4-2 below) never appears.
#
# Was previously asserted by diffing the working tree's cost-report.sh
# against `git show HEAD:scripts/cost-report.sh` on the theory that "unset"
# should be byte-identical to "the script before this floor feature
# existed". That mechanism silently assumed cost-report.sh would never be
# touched again for any OTHER reason -- false the moment a later, unrelated
# slice legitimately changes this script's output on this same fixture (as
# recovered-figure-drops-slice-and-model S1 does: this exact fixture has a
# priced invocation with no `slice`, which is precisely the class S1 adds an
# unattributed-tokens line for). That is not a floor-feature regression, so
# a byte-diff against a moving HEAD is the wrong instrument for what this
# case actually needs to prove -- fixed here to assert the floor's own
# opt-in property directly, the same way S4-2 through S4-5b already do,
# rather than a global "nothing else in this file may ever change" claim.
S4_NEW_UNSET_OUT="$(report "$S4FLOORDIR" s4-floor-fixture)"
expect "(S4-1) CL5: LARAVEL_LOOP_COST_MIN_COVERAGE unset -> total priced tokens still prints, and 'cost read as not established' never appears" \
  "total-prints yes, not-established no" \
  "total-prints $(printf '%s\n' "$S4_NEW_UNSET_OUT" | grep -q 'total priced tokens' && echo yes || echo no), not-established $(printf '%s\n' "$S4_NEW_UNSET_OUT" | grep -qi 'not established' && echo yes || echo no)"

# (S4-1b) G2 follow-up (recovered-figure verify.md finding 2): the byte-identity
# half of what (S4-1) used to assert, restored with a durable instrument. The
# old case diffed against `git show HEAD:scripts/cost-report.sh`, which decayed
# the moment any other slice legitimately touched that file; (S4-1) above now
# asserts the floor's own opt-in property directly, which is correct but no
# longer proves that unset output is unchanged BYTE FOR BYTE.
#
# A frozen literal is the right instrument for that, and it is the one this
# suite already uses for the same job elsewhere (RD8's blocks in S1, S3 and
# S5's sections). It cannot decay silently: a slice that legitimately changes
# this output must update the block deliberately, which is the review moment
# the moving-HEAD diff never provided.
read -r -d '' S4_FROZEN_UNSET <<'FROZEN'
Coverage:
  based on 1 of 2 invocations that carry a token figure (1 unpriced, not counted) -- 50 % coverage; wholly unobserved: build
  unpriced invocation(s), by reason (taken only from the finish record's own status, never guessed):
    1 launched in background, outcome never observed
  Why: for a backgrounded invocation, the token figure is measured by the host
  and delivered into the session when it finishes -- it is not captured here.
  0 invocation(s) started with no finish recorded yet -- in flight, not counted as unpriced (plus 1 launched in background and never subsequently observed -- also unresolved, counted separately above, never folded into this count).
  per phase (priced/total invocations; in-flight and unpriced called out, never folded together):
    spec   1/1 priced (0 unpriced)
    slice  0/0 priced (0 unpriced)
    build  0/1 priced (1 unpriced)
    verify 0/0 priced (0 unpriced)
  elapsed (wall-clock, first recorded start to last recorded finish; never summed across overlapping invocations): 3 second(s)

Tokens (priced subset only -- never the unit's whole cost):
  total priced tokens: 1000
  based on 1 of 2 invocations that carry a token figure (1 unpriced, not counted) -- 50 % coverage; wholly unobserved: build
  cache-read share: unavailable (cache_read_tokens absent from every priced record)

Phases (priced invocations only; model per phase, model_source shown when derived):
    spec   unavailable
    slice  unavailable
    build  unavailable
    verify unavailable

Rework:
  This measures the cost of slices that were not right first time, at whole-invocation
  granularity -- not the cost of retrying. An invocation needing even one refine pass has
  its WHOLE token cost counted as rework, deliberately over-attributing rather than
  estimating a per-pass split. This is not comparable to the requirements document's
  <15% target (Sec.10), which was calibrated against a narrower, per-pass definition.
  No pass/fail verdict against that target is printed here.
  count: 0 of 2 invocation(s) marked rework
  token share: unavailable (no priced invocations are marked rework)

Slices (top by priced tokens, priced subset only):
  no slice attributed to any priced invocation.
  1 priced invocation(s), 1000 token(s) sit outside this ranking -- unattributed.

Flags:
  concentration could not be assessed -- 1 priced invocation(s) carry no slice attribution.

Budget:
  no threshold is set (LARAVEL_LOOP_BUDGET_WARN, LARAVEL_LOOP_BUDGET_HARD are both unset) -- nothing will gate.
FROZEN
expect "(S4-1b) CL5: the floor unset leaves this fixture's whole report byte-identical to a frozen block" "" \
  "$(diff <(printf '%s' "$S4_FROZEN_UNSET") <(printf '%s' "$S4_NEW_UNSET_OUT"))"

# (S4-2) above coverage -> no unit-level total; cost read as not
# established; the observed subset stays visible only in Coverage above,
# never repeated here as a second, competing figure.
S4_ABOVE_OUT="$(report_floor "$S4FLOORDIR" s4-floor-fixture 51)"
expect "(S4-2) CL5: floor above the fixture's share -> no 'total priced tokens' line" "no" \
  "$(printf '%s\n' "$S4_ABOVE_OUT" | grep -q 'total priced tokens' && echo yes || echo no)"
expect "(S4-2) CL5: floor above the fixture's share -> cost read as not established" "yes" \
  "$(printf '%s\n' "$S4_ABOVE_OUT" | grep -qi 'not established' && echo yes || echo no)"
expect "(S4-2) CL5: floor above the fixture's share -> the observed subset still appears in Coverage above, as a subset" "yes" \
  "$(printf '%s\n' "$S4_ABOVE_OUT" | grep -qE '^  based on 1 of 2 invocations' && echo yes || echo no)"

# (S4-3) strictly below coverage -> the total prints as it does today.
S4_BELOW_OUT="$(report_floor "$S4FLOORDIR" s4-floor-fixture 10)"
expect "(S4-3) CL5: floor strictly below the fixture's share -> total prints as today" "yes" \
  "$(printf '%s\n' "$S4_BELOW_OUT" | grep -q 'total priced tokens' && echo yes || echo no)"

# (S4-4) exactly at coverage -> boundary pinned: at-or-above prints.
S4_AT_OUT="$(report_floor "$S4FLOORDIR" s4-floor-fixture 50)"
expect "(S4-4) CL5: floor exactly at the fixture's share -> total still prints (boundary pinned)" "yes" \
  "$(printf '%s\n' "$S4_AT_OUT" | grep -q 'total priced tokens' && echo yes || echo no)"

# (S4-5) unparseable -> disabled loudly, naming the field and the value, and
# today's behaviour holds. Never silently disabled, never silently enabled.
S4_BAD_OUT="$(report_floor "$S4FLOORDIR" s4-floor-fixture notanumber)"
expect "(S4-5) CL5: unparseable floor -> total still prints (today's behaviour holds)" "yes" \
  "$(printf '%s\n' "$S4_BAD_OUT" | grep -q 'total priced tokens' && echo yes || echo no)"
expect "(S4-5) CL5: unparseable floor -> the warning names the field and the value" "yes" \
  "$(printf '%s\n' "$S4_BAD_OUT" | grep -qF 'LARAVEL_LOOP_COST_MIN_COVERAGE="notanumber"' && echo yes || echo no)"
expect "(S4-5) CL5: unparseable floor -> the warning says DISABLED, never defaulted to any number" "yes" \
  "$(printf '%s\n' "$S4_BAD_OUT" | grep -qF 'DISABLED, not defaulted to any number' && echo yes || echo no)"

# An out-of-range but numeric value (the field is a 0-100 percentage) is
# disabled the exact same way -- never clamped, never coerced.
S4_RANGE_OUT="$(report_floor "$S4FLOORDIR" s4-floor-fixture 150)"
expect "(S4-5b) CL5: out-of-range floor (150) -> disabled loudly like unparseable, total still prints" "yes" \
  "$(printf '%s\n' "$S4_RANGE_OUT" | grep -qF 'LARAVEL_LOOP_COST_MIN_COVERAGE="150"' \
     && printf '%s\n' "$S4_RANGE_OUT" | grep -q 'total priced tokens' && echo yes || echo no)"

rm -rf "$S4FLOORDIR"

# (S4-6) CL8/CV6: zero priced invocations -> CV6's existing behaviour is
# unchanged, and the floor adds no second, contradicting statement, floor
# set or not.
S4ZERODIR="$(mktemp -d)"
mkdir -p "$S4ZERODIR/.claude"
S4ZEROLEDGER="$S4ZERODIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s4z1","slug":"s4-zero-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s4z1","slug":"s4-zero-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
} > "$S4ZEROLEDGER"
S4_ZERO_OUT="$(report_floor "$S4ZERODIR" s4-zero-fixture 10)"
expect "(S4-6) CL8/CV6: zero-priced fixture with a floor set -> CV6's message is unchanged" "yes" \
  "$(printf '%s\n' "$S4_ZERO_OUT" | grep -qi "nothing about this unit's token cost is observable" && echo yes || echo no)"
expect "(S4-6) CL8/CV6: zero-priced fixture with a floor set -> no second 'not established' statement is added" "no" \
  "$(printf '%s\n' "$S4_ZERO_OUT" | grep -qi 'not established' && echo yes || echo no)"
expect "(S4-6) CL8/CV6: zero-priced fixture with a floor set -> no coverage-floor warning is printed either" "no" \
  "$(printf '%s\n' "$S4_ZERO_OUT" | grep -qF 'LARAVEL_LOOP_COST_MIN_COVERAGE' && echo yes || echo no)"
rm -rf "$S4ZERODIR"

# (S4-7) Do NOT: the floor changes only what /cost prints. It does not
# change what scripts/check-budget-gate.sh compares, whether it fires, or
# its exit codes -- G0-D1 stays unreopened. With both budget thresholds
# unset, the hook-mode gate still exits before touching the ledger at all
# (BG1), regardless of this floor.
S4BUDGET_JSON='{"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"prompt":"Unit: s4-floor-fixture\n"}}'
S4BUDGET_OUT="$(printf '%s' "$S4BUDGET_JSON" | LARAVEL_LOOP_COST_MIN_COVERAGE=10 bash "$SCRIPTS/check-budget-gate.sh" 2>&1)"
S4BUDGET_EXIT="$(printf '%s' "$S4BUDGET_JSON" | LARAVEL_LOOP_COST_MIN_COVERAGE=10 bash "$SCRIPTS/check-budget-gate.sh" >/dev/null 2>&1; echo $?)"
expect "(S4-7) Do NOT: LARAVEL_LOOP_COST_MIN_COVERAGE has no effect on check-budget-gate.sh's output" "" "$S4BUDGET_OUT"
expect "(S4-7) Do NOT: LARAVEL_LOOP_COST_MIN_COVERAGE has no effect on check-budget-gate.sh's exit code" "0" "$S4BUDGET_EXIT"

# (guard) no digit shares a line with LARAVEL_LOOP_COST_MIN_COVERAGE
# anywhere in scripts/, README, or the top-level docs -- extends the
# existing "no number in README" guard for LARAVEL_LOOP_BUDGET* (S4 of
# cost-reporting-v0.3, tests/guardrails.test.sh's pattern to copy) to this
# field and to scripts/ as well, per this slice's own brief.
# docs/loop/<slug>/{spec,slices,intent}.md are this unit's own G0/G1
# planning record and are exempt: naming the field's *shape* (a bounded
# percentage) at G1 is the slicing phase's job, not a shipped default, and
# it predates this slice's own commit.
S4_GUARD_FILES="$ROOT/README.md"
for f in "$ROOT"/docs/loop/*.md; do
  [ -f "$f" ] && S4_GUARD_FILES="$S4_GUARD_FILES $f"
done
expect "(guard) no digit shares a line with LARAVEL_LOOP_COST_MIN_COVERAGE in scripts/, README, or top-level docs (Do NOT: no number ships)" "0" \
  "$(grep -h 'LARAVEL_LOOP_COST_MIN_COVERAGE' "$SCRIPTS"/*.sh $S4_GUARD_FILES 2>/dev/null | grep -cE '[0-9]')"

# --- S3: Phases, Rework, Slices, Flags, Budget sections --------------------

# (a) CO4 — a mixed fixture with model_source "derived" on a PRICED
# invocation (unlike S2's MIXDIR, whose only derived-model invocation was
# unpriced) so the word "derived" actually appears attached to a phase that
# has coverage, and a phase with zero priced invocations (verify, slice)
# reads "unavailable", never "0".
PHASEDIR="$(mktemp -d)"
mkdir -p "$PHASEDIR/.claude"
PHASELEDGER="$PHASEDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"p1","slug":"phase-fixture","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"p1","slug":"phase-fixture","phase":"spec","agent":"loop-spec","model":"claude-opus-4","model_source":"observed","status":"completed","total_tokens":1000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"p2","slug":"phase-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"p2","slug":"phase-fixture","phase":"build","agent":"loop-build","model":"claude-sonnet-4","model_source":"derived","status":"completed","total_tokens":2000}'
  printf '%s\n' '{"ts":5,"event":"start","invocation_id":"p3","slug":"phase-fixture","phase":"verify","agent":"loop-verify"}'
  printf '%s\n' '{"ts":6,"event":"finish","invocation_id":"p3","slug":"phase-fixture","phase":"verify","agent":"loop-verify","status":"async_launched"}'
} > "$PHASELEDGER"
PHASE_OUT="$(report "$PHASEDIR" phase-fixture)"

expect "(a) CO4: 'derived' appears against the build phase's model" "yes" \
  "$(printf '%s\n' "$PHASE_OUT" | grep -qE 'build[[:space:]]+claude-sonnet-4 \(derived\)' && echo yes || echo no)"
expect "(a) CO4: spec phase shows its observed model without a derived tag" "yes" \
  "$(printf '%s\n' "$PHASE_OUT" | grep -qE 'spec[[:space:]]+claude-opus-4$' && echo yes || echo no)"
expect "(a) CO4: verify phase (no priced invocation) reads unavailable" "yes" \
  "$(printf '%s\n' "$PHASE_OUT" | grep -qE 'verify[[:space:]]+unavailable' && echo yes || echo no)"
expect "(a) CO4: slice phase (zero invocations) reads unavailable, never 0" "yes" \
  "$(printf '%s\n' "$PHASE_OUT" | grep -qE 'slice[[:space:]]+unavailable' && echo yes || echo no)"

# (i) CV7 on the phase fixture too.
PHASE_OUT_2="$(report "$PHASEDIR" phase-fixture)"
expect "(i) phase fixture: byte-identical stdout on a re-run (CV7)" "" \
  "$(diff <(printf '%s' "$PHASE_OUT") <(printf '%s' "$PHASE_OUT_2"))"

# (b) CO5 — rework entirely unpriced (E4's real case): counts labelled as
# counts, token share unavailable.
REWORKUDIR="$(mktemp -d)"
mkdir -p "$REWORKUDIR/.claude"
REWORKULEDGER="$REWORKUDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"r1","slug":"rework-unpriced","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"r1","slug":"rework-unpriced","phase":"build","agent":"loop-build","status":"async_launched","phase_detail":"rework","refine_passes":2}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"r2","slug":"rework-unpriced","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"r2","slug":"rework-unpriced","phase":"build","agent":"loop-build","status":"async_launched"}'
} > "$REWORKULEDGER"
REWORKU_OUT="$(report "$REWORKUDIR" rework-unpriced)"
expect "(b) CO5: all-unpriced rework prints count labelled as a count" "yes" \
  "$(printf '%s\n' "$REWORKU_OUT" | grep -q 'count: 1 of 2 invocation(s) marked rework' && echo yes || echo no)"
expect "(b) CO5: all-unpriced rework's token share reads unavailable" "yes" \
  "$(printf '%s\n' "$REWORKU_OUT" | grep -q 'token share: unavailable' && echo yes || echo no)"

# (b) CO5 — a priced-rework fixture prints a genuine share, labelled as a
# share, plus its ambiguous attribution shown as ambiguous, never definite.
REWORKPDIR="$(mktemp -d)"
mkdir -p "$REWORKPDIR/.claude"
REWORKPLEDGER="$REWORKPDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"q1","slug":"rework-priced","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"q1","slug":"rework-priced","phase":"build","agent":"loop-build","status":"completed","total_tokens":1000,"phase_detail":"rework","refine_passes":1,"rework_attribution":"ambiguous"}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"q2","slug":"rework-priced","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"q2","slug":"rework-priced","phase":"build","agent":"loop-build","status":"completed","total_tokens":3000}'
} > "$REWORKPLEDGER"
REWORKP_OUT="$(report "$REWORKPDIR" rework-priced)"
expect "(b) CO5: priced-rework fixture prints a token share labelled as a share" "yes" \
  "$(printf '%s\n' "$REWORKP_OUT" | grep -q 'token share: 25% of priced tokens' && echo yes || echo no)"
expect "(b) CO5: refine-pass count travels with the rework count" "yes" \
  "$(printf '%s\n' "$REWORKP_OUT" | grep -q 'count: 1 of 2 invocation(s) marked rework (refine passes: 1)' && echo yes || echo no)"
expect "rework_attribution:ambiguous shows as ambiguous, never definite (v0.2 S5)" "yes" \
  "$(printf '%s\n' "$REWORKP_OUT" | grep -qi 'ambiguous' && echo yes || echo no)"

# (c) CO6 — the D3 granularity statement and the not-comparable-to-<15%
# statement both appear, and no verdict against that target is printed.
expect "(c) CO6: states rework is not the cost of retrying (D3)" "yes" \
  "$(printf '%s\n' "$REWORKP_OUT" | grep -q 'not the cost of retrying' && echo yes || echo no)"
expect "(c) CO6: states the figure is not comparable to the <15% target" "yes" \
  "$(printf '%s\n' "$REWORKP_OUT" | grep -q 'not comparable to the' && printf '%s\n' "$REWORKP_OUT" | grep -q '<15%' && echo yes || echo no)"
expect "(c) CO6: no pass/fail verdict against the 15% target is printed" "0" \
  "$(printf '%s\n' "$REWORKP_OUT" | grep -icE 'meets the target|below the target|exceeds the target|target: *(pass|fail)')"

# (d) CO7 — one slice over 30% of the unit's priced total prints the flag.
CONCDIR="$(mktemp -d)"
mkdir -p "$CONCDIR/.claude"
CONCLEDGER="$CONCDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"c1","slug":"slice-conc","slice":"S1","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"c1","slug":"slice-conc","slice":"S1","phase":"build","agent":"loop-build","status":"completed","total_tokens":8000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"c2","slug":"slice-conc","slice":"S2","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"c2","slug":"slice-conc","slice":"S2","phase":"build","agent":"loop-build","status":"completed","total_tokens":2000}'
} > "$CONCLEDGER"
CONC_OUT="$(report "$CONCDIR" slice-conc)"
expect "(d) CO7: a slice above 30% of the priced total is flagged, named, with its percentage" "yes" \
  "$(printf '%s\n' "$CONC_OUT" | grep -qE 'S1 is 80% .*concentration threshold' && echo yes || echo no)"

# (d) CO7 — slice-level coverage cannot support the comparison (a priced
# invocation with no slice at all): states so, names what was missing, and
# prints no flag either way that could read as a passed check.
UNASSESSDIR="$(mktemp -d)"
mkdir -p "$UNASSESSDIR/.claude"
UNASSESSLEDGER="$UNASSESSDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"u1","slug":"slice-unassessable","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"u1","slug":"slice-unassessable","phase":"build","agent":"loop-build","status":"completed","total_tokens":5000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"u2","slug":"slice-unassessable","slice":"S1","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"u2","slug":"slice-unassessable","slice":"S1","phase":"build","agent":"loop-build","status":"completed","total_tokens":1000}'
} > "$UNASSESSLEDGER"
UNASSESS_OUT="$(report "$UNASSESSDIR" slice-unassessable)"
expect "(d) CO7: unassessable slice coverage states so and names what was missing" "yes" \
  "$(printf '%s\n' "$UNASSESS_OUT" | grep -q 'could not be assessed -- 1 priced invocation(s) carry no slice attribution' && echo yes || echo no)"
expect "(d) CO7: unassessable case prints no concentration percentage that could read as a passed check" "0" \
  "$(printf '%s\n' "$UNASSESS_OUT" | grep -c 'concentration threshold')"

# (e) CV4 — cache_read_tokens absent from every record: unavailable, and
# "0%" appears nowhere in the output.
CACHEDIR="$(mktemp -d)"
mkdir -p "$CACHEDIR/.claude"
CACHELEDGER="$CACHEDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"k1","slug":"cache-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"k1","slug":"cache-fixture","phase":"build","agent":"loop-build","status":"completed","total_tokens":500}'
} > "$CACHELEDGER"
CACHE_OUT="$(report "$CACHEDIR" cache-fixture)"
expect "(e) CV4: cache-read share reads unavailable when absent from every record" "yes" \
  "$(printf '%s\n' "$CACHE_OUT" | grep -q 'cache-read share: unavailable' && echo yes || echo no)"
expect "(e) CV4: the string 0% appears nowhere in the output" "0" \
  "$(printf '%s\n' "$CACHE_OUT" | grep -c '0%')"

# (f) CO11 — overlapping invocations: elapsed is a wall-clock span, never a
# sum of durations, and no "agent time" wording anywhere.
OVERLAPDIR="$(mktemp -d)"
mkdir -p "$OVERLAPDIR/.claude"
OVERLAPLEDGER="$OVERLAPDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":100,"event":"start","invocation_id":"o1","slug":"overlap-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":105,"event":"start","invocation_id":"o2","slug":"overlap-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":115,"event":"finish","invocation_id":"o2","slug":"overlap-fixture","phase":"build","agent":"loop-build","status":"completed","total_tokens":100,"duration_ms":10000}'
  printf '%s\n' '{"ts":120,"event":"finish","invocation_id":"o1","slug":"overlap-fixture","phase":"build","agent":"loop-build","status":"completed","total_tokens":200,"duration_ms":20000}'
} > "$OVERLAPLEDGER"
OVERLAP_OUT="$(report "$OVERLAPDIR" overlap-fixture)"
expect "(f) CO11: no 'agent time' wording anywhere, even with overlapping invocations" "0" \
  "$(printf '%s\n' "$OVERLAP_OUT" | grep -icE 'agent time')"
expect "(f) CO11: elapsed is labelled and is the wall-clock span, not the summed durations" "yes" \
  "$(printf '%s\n' "$OVERLAP_OUT" | grep -q 'elapsed (wall-clock' && printf '%s\n' "$OVERLAP_OUT" | grep -q '20 second(s)' && echo yes || echo no)"

# (g) CO12/BG6 — Budget section states config or its absence, never a
# reassurance token, whichever way the variables are set.
BUDGET_UNSET_OUT="$(report "$PHASEDIR" phase-fixture)"
expect "(g) CO12: unset budget vars state that nothing will gate" "yes" \
  "$(printf '%s\n' "$BUDGET_UNSET_OUT" | grep -q 'no threshold is set' && echo yes || echo no)"
BUDGET_SET_OUT="$(LARAVEL_LOOP_BUDGET_HARD=12345 report "$PHASEDIR" phase-fixture)"
expect "(g) CO12: a set threshold shows the value that was read" "yes" \
  "$(printf '%s\n' "$BUDGET_SET_OUT" | grep -q 'LARAVEL_LOOP_BUDGET_HARD=12345' && echo yes || echo no)"

# (l) BG6 — no reassurance token in any S3 fixture's output above.
ALL_S3_OUTPUT="$PHASE_OUT
$REWORKU_OUT
$REWORKP_OUT
$CONC_OUT
$UNASSESS_OUT
$CACHE_OUT
$OVERLAP_OUT
$BUDGET_UNSET_OUT
$BUDGET_SET_OUT"
expect "(g) BG6: no 'within budget', 'under budget', or checkmark in any S3 fixture's output" "1" \
  "$(printf '%s\n' "$ALL_S3_OUTPUT" | grep -iE 'within budget|under budget|✓' >/dev/null 2>&1; echo $?)"

# (h) CV7 — byte-identical output on a re-run of every S3 fixture above.
REWORKU_OUT_2="$(report "$REWORKUDIR" rework-unpriced)"
expect "(h) rework-unpriced fixture: byte-identical on a re-run (CV7)" "" \
  "$(diff <(printf '%s' "$REWORKU_OUT") <(printf '%s' "$REWORKU_OUT_2"))"
REWORKP_OUT_2="$(report "$REWORKPDIR" rework-priced)"
expect "(h) rework-priced fixture: byte-identical on a re-run (CV7)" "" \
  "$(diff <(printf '%s' "$REWORKP_OUT") <(printf '%s' "$REWORKP_OUT_2"))"
CONC_OUT_2="$(report "$CONCDIR" slice-conc)"
expect "(h) slice-conc fixture: byte-identical on a re-run (CV7)" "" \
  "$(diff <(printf '%s' "$CONC_OUT") <(printf '%s' "$CONC_OUT_2"))"
UNASSESS_OUT_2="$(report "$UNASSESSDIR" slice-unassessable)"
expect "(h) slice-unassessable fixture: byte-identical on a re-run (CV7)" "" \
  "$(diff <(printf '%s' "$UNASSESS_OUT") <(printf '%s' "$UNASSESS_OUT_2"))"
CACHE_OUT_2="$(report "$CACHEDIR" cache-fixture)"
expect "(h) cache fixture: byte-identical on a re-run (CV7)" "" \
  "$(diff <(printf '%s' "$CACHE_OUT") <(printf '%s' "$CACHE_OUT_2"))"
OVERLAP_OUT_2="$(report "$OVERLAPDIR" overlap-fixture)"
expect "(h) overlap fixture: byte-identical on a re-run (CV7)" "" \
  "$(diff <(printf '%s' "$OVERLAP_OUT") <(printf '%s' "$OVERLAP_OUT_2"))"

rm -rf "$PHASEDIR" "$REWORKUDIR" "$REWORKPDIR" "$CONCDIR" "$UNASSESSDIR" "$CACHEDIR" "$OVERLAPDIR"

# ---------------------------------------------------------------------------
echo "check-budget-gate.sh (budget gate, S4)"

budget_payload() { # $1 slug  $2 hook_event (default PreToolUse)  $3 tool_name (default Agent)
  python3 - "$1" "${2:-PreToolUse}" "${3:-Agent}" <<'PY'
import json, sys
slug, event, tool = sys.argv[1:4]
payload = {
    "hook_event_name": event,
    "tool_name": tool,
    "tool_input": {
        "subagent_type": "loop-build",
        "description": "Build " + slug,
        "prompt": "Unit: " + slug + "\nSlice: S9\n\nDo the thing.",
    },
}
print(json.dumps(payload))
PY
}

gate_exit() { # $1 json (env vars set by the caller as a prefix)
  printf '%s' "$1" | bash "$SCRIPTS/check-budget-gate.sh" >/dev/null 2>&1
  echo $?
}
gate_stdout() { # $1 json
  printf '%s' "$1" | bash "$SCRIPTS/check-budget-gate.sh" 2>/dev/null
}
gate_stderr() { # $1 json
  printf '%s' "$1" | bash "$SCRIPTS/check-budget-gate.sh" 2>&1 1>/dev/null
}

ALL_BG_STDOUT=""
ALL_BG_STDERR=""
collect_bg() { # $1 stdout $2 stderr — accumulated for the aggregate BG6 check
  ALL_BG_STDOUT="$ALL_BG_STDOUT
$1"
  ALL_BG_STDERR="$ALL_BG_STDERR
$2"
}

# -- fully-priced fixture: slice A (700000 tokens, reworked) and slice B
# (300000 tokens, not reworked). Priced total 1,000,000; coverage is
# complete (0 unpriced), so the coverage sentence below is exact and fixed.
BGFULLDIR="$(mktemp -d)"
mkdir -p "$BGFULLDIR/.claude"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"f1","slug":"full-cov-unit","slice":"A","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"f1","slug":"full-cov-unit","slice":"A","phase":"build","agent":"loop-build","status":"completed","total_tokens":700000,"phase_detail":"rework","refine_passes":2}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"f2","slug":"full-cov-unit","slice":"B","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"f2","slug":"full-cov-unit","slice":"B","phase":"build","agent":"loop-build","status":"completed","total_tokens":300000}'
} > "$BGFULLDIR/.claude/loop-cost.jsonl"
BG_FULL_JSON="$(budget_payload full-cov-unit)"
BG_FULL_COVERAGE='based on 2 of 2 invocations that carry a token figure (0 unpriced, not counted)'

# -- (a) HARD below the priced total: exit 2, numbered options, option 1 is
# re-slicing the most expensive slice, coverage sentence present verbatim
# (BG3, BG5, CV8).
BGA_ERR="$(CLAUDE_PROJECT_DIR="$BGFULLDIR" LARAVEL_LOOP_BUDGET_HARD=999999 gate_stderr "$BG_FULL_JSON")"
BGA_EXIT="$(CLAUDE_PROJECT_DIR="$BGFULLDIR" LARAVEL_LOOP_BUDGET_HARD=999999 gate_exit "$BG_FULL_JSON")"
collect_bg "" "$BGA_ERR"
expect "(a) HARD below priced total: exit 2 (BG3)" "2" "$BGA_EXIT"
expect "(a) breach message has numbered options 1/2/3" "yes" \
  "$(printf '%s\n' "$BGA_ERR" | grep -qE '^ *1\.' && printf '%s\n' "$BGA_ERR" | grep -qE '^ *2\.' && printf '%s\n' "$BGA_ERR" | grep -qE '^ *3\.' && echo yes || echo no)"
expect "(a) option 1 recommends re-slicing the most expensive slice (A) (BG5)" "yes" \
  "$(printf '%s\n' "$BGA_ERR" | grep -E '^ *1\.' | grep -qi 're-slice' && printf '%s\n' "$BGA_ERR" | grep -E '^ *1\.' | grep -q '"A"' && echo yes || echo no)"
expect "(a) breach message never recommends raising the cap as option 1" "no" \
  "$(printf '%s\n' "$BGA_ERR" | grep -E '^ *1\.' | grep -qi 'raise' && echo yes || echo no)"
expect "(a) breach message carries the coverage sentence verbatim (CV8)" "yes" \
  "$(printf '%s\n' "$BGA_ERR" | grep -qF "$BG_FULL_COVERAGE" && echo yes || echo no)"
expect "(a) breach message names the most expensive slice and its rework share (BG5)" "yes" \
  "$(printf '%s\n' "$BGA_ERR" | grep -q 'Most expensive slice: A' && printf '%s\n' "$BGA_ERR" | grep -q 'rework share: 100%' && echo yes || echo no)"

# -- (b) HARD above the total: exit 0, no output at all.
BGB_JSON="$BG_FULL_JSON"
BGB_OUT="$(CLAUDE_PROJECT_DIR="$BGFULLDIR" LARAVEL_LOOP_BUDGET_HARD=1000001 gate_stdout "$BGB_JSON")"
BGB_ERR="$(CLAUDE_PROJECT_DIR="$BGFULLDIR" LARAVEL_LOOP_BUDGET_HARD=1000001 gate_stderr "$BGB_JSON")"
BGB_EXIT="$(CLAUDE_PROJECT_DIR="$BGFULLDIR" LARAVEL_LOOP_BUDGET_HARD=1000001 gate_exit "$BGB_JSON")"
collect_bg "$BGB_OUT" "$BGB_ERR"
expect "(b) HARD above the total: exit 0" "0" "$BGB_EXIT"
expect "(b) HARD above the total: no output on stdout" "" "$BGB_OUT"
expect "(b) HARD above the total: no output on stderr" "" "$BGB_ERR"

# -- (c) both unset, against a ledger far above any plausible threshold:
# exit 0 and zero bytes on stdout and stderr, asserted as emptiness (BG1).
BGC_JSON="$BG_FULL_JSON"
BGC_OUT_BYTES="$(CLAUDE_PROJECT_DIR="$BGFULLDIR" gate_stdout "$BGC_JSON" | wc -c | tr -d ' ')"
BGC_ERR_BYTES="$(CLAUDE_PROJECT_DIR="$BGFULLDIR" gate_stderr "$BGC_JSON" | wc -c | tr -d ' ')"
BGC_EXIT="$(CLAUDE_PROJECT_DIR="$BGFULLDIR" gate_exit "$BGC_JSON")"
expect "(c) both unset: exit 0 (BG1)" "0" "$BGC_EXIT"
expect "(c) both unset: zero bytes on stdout (BG1)" "0" "$BGC_OUT_BYTES"
expect "(c) both unset: zero bytes on stderr (BG1)" "0" "$BGC_ERR_BYTES"

# -- (d) each unparseable value disables the gate and says so loudly, naming
# the variable and the value; a breach-sized ledger still does not block
# (BG2) — proving no numeric fallback happened, unlike E9's line cap.
for bad in '400k' '4e5' '-1' '1.5' ' 100'; do
  d_err="$(CLAUDE_PROJECT_DIR="$BGFULLDIR" LARAVEL_LOOP_BUDGET_HARD="$bad" gate_stderr "$BG_FULL_JSON")"
  d_exit="$(CLAUDE_PROJECT_DIR="$BGFULLDIR" LARAVEL_LOOP_BUDGET_HARD="$bad" gate_exit "$BG_FULL_JSON")"
  collect_bg "" "$d_err"
  expect "(d) LARAVEL_LOOP_BUDGET_HARD=\"$bad\": gate disabled, exit 0 (BG2)" "0" "$d_exit"
  expect "(d) LARAVEL_LOOP_BUDGET_HARD=\"$bad\": message names the variable and the value (BG2)" "yes" \
    "$(printf '%s' "$d_err" | grep -q 'LARAVEL_LOOP_BUDGET_HARD' && printf '%s' "$d_err" | grep -qF -- "$bad" && echo yes || echo no)"
done

# -- (e) WARN above HARD: misconfiguration reported plainly, and a hard
# breach still exits 2 (BG8).
BGE_ERR="$(CLAUDE_PROJECT_DIR="$BGFULLDIR" LARAVEL_LOOP_BUDGET_WARN=2000000 LARAVEL_LOOP_BUDGET_HARD=999999 gate_stderr "$BG_FULL_JSON")"
BGE_EXIT="$(CLAUDE_PROJECT_DIR="$BGFULLDIR" LARAVEL_LOOP_BUDGET_WARN=2000000 LARAVEL_LOOP_BUDGET_HARD=999999 gate_exit "$BG_FULL_JSON")"
collect_bg "" "$BGE_ERR"
expect "(e) WARN above HARD: misconfiguration reported (BG8)" "yes" \
  "$(printf '%s\n' "$BGE_ERR" | grep -qi 'misconfiguration' && echo yes || echo no)"
expect "(e) WARN above HARD: the hard breach still fires (exit 2) (BG8)" "2" "$BGE_EXIT"

rm -rf "$BGFULLDIR"

# -- (f) WARN crossed: one message on the first spawn, nothing on the next
# two (BG7). HARD left unset — this fixture isolates the warn-only path.
BGWARNDIR="$(mktemp -d)"
mkdir -p "$BGWARNDIR/.claude"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"w1","slug":"warn-unit","slice":"A","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"w1","slug":"warn-unit","slice":"A","phase":"build","agent":"loop-build","status":"completed","total_tokens":600}'
} > "$BGWARNDIR/.claude/loop-cost.jsonl"
BGWARN_JSON="$(budget_payload warn-unit)"
BGWARN_ERR1="$(CLAUDE_PROJECT_DIR="$BGWARNDIR" LARAVEL_LOOP_BUDGET_WARN=500 gate_stderr "$BGWARN_JSON")"
BGWARN_EXIT1="$(CLAUDE_PROJECT_DIR="$BGWARNDIR" LARAVEL_LOOP_BUDGET_WARN=500 gate_exit "$BGWARN_JSON")"
BGWARN_ERR2="$(CLAUDE_PROJECT_DIR="$BGWARNDIR" LARAVEL_LOOP_BUDGET_WARN=500 gate_stderr "$BGWARN_JSON")"
BGWARN_ERR3="$(CLAUDE_PROJECT_DIR="$BGWARNDIR" LARAVEL_LOOP_BUDGET_WARN=500 gate_stderr "$BGWARN_JSON")"
collect_bg "" "$BGWARN_ERR1$BGWARN_ERR2$BGWARN_ERR3"
expect "(f) WARN crossed: first spawn exits 0 and warns (BG7)" "0" "$BGWARN_EXIT1"
expect "(f) WARN crossed: first spawn message present" "yes" \
  "$(printf '%s\n' "$BGWARN_ERR1" | grep -qi 'warn threshold crossed' && echo yes || echo no)"
expect "(f) WARN crossed: second spawn is silent (BG7)" "" "$BGWARN_ERR2"
expect "(f) WARN crossed: third spawn is silent (BG7)" "" "$BGWARN_ERR3"
rm -rf "$BGWARNDIR"

# -- (g) threshold set with partial coverage: the coverage notice appears
# once with the unpriced count, and not on the next spawn (BG9). HARD is set
# far above the priced total so no breach interferes with this assertion.
BGPARTIALDIR="$(mktemp -d)"
mkdir -p "$BGPARTIALDIR/.claude"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"p1","slug":"partial-unit","slice":"A","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"p1","slug":"partial-unit","slice":"A","phase":"build","agent":"loop-build","status":"completed","total_tokens":100}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"p2","slug":"partial-unit","slice":"B","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"p2","slug":"partial-unit","slice":"B","phase":"build","agent":"loop-build","status":"async_launched"}'
} > "$BGPARTIALDIR/.claude/loop-cost.jsonl"
BGPARTIAL_JSON="$(budget_payload partial-unit)"
BGPARTIAL_ERR1="$(CLAUDE_PROJECT_DIR="$BGPARTIALDIR" LARAVEL_LOOP_BUDGET_HARD=100000 gate_stderr "$BGPARTIAL_JSON")"
BGPARTIAL_EXIT1="$(CLAUDE_PROJECT_DIR="$BGPARTIALDIR" LARAVEL_LOOP_BUDGET_HARD=100000 gate_exit "$BGPARTIAL_JSON")"
BGPARTIAL_ERR2="$(CLAUDE_PROJECT_DIR="$BGPARTIALDIR" LARAVEL_LOOP_BUDGET_HARD=100000 gate_stderr "$BGPARTIAL_JSON")"
collect_bg "" "$BGPARTIAL_ERR1$BGPARTIAL_ERR2"
expect "(g) partial coverage: first spawn exits 0 and notes it once (BG9)" "0" "$BGPARTIAL_EXIT1"
expect "(g) partial coverage: first spawn names the unpriced count" "yes" \
  "$(printf '%s\n' "$BGPARTIAL_ERR1" | grep -q '1 unpriced, not counted' && echo yes || echo no)"
expect "(g) partial coverage: not repeated on the next spawn (BG9)" "" "$BGPARTIAL_ERR2"
rm -rf "$BGPARTIALDIR"

# -- (S2-4) CL6: the gate's partial-coverage notice carries the identical
# share and identical wholly-unobserved phase name as /cost's own coverage
# sentence for the same ledger, because both call cost_coverage_sentence over
# the one and only cost_scan (CV7/CV8) -- never two call sites each computing
# their own copy. One priced spec invocation, one backgrounded build
# invocation -> 50%, build wholly unobserved.
GATESHAREDIR="$(mktemp -d)"
mkdir -p "$GATESHAREDIR/.claude"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"gs1","slug":"gate-share-unit","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"gs1","slug":"gate-share-unit","phase":"spec","agent":"loop-spec","status":"completed","total_tokens":100}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"gs2","slug":"gate-share-unit","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"gs2","slug":"gate-share-unit","phase":"build","agent":"loop-build","status":"async_launched"}'
} > "$GATESHAREDIR/.claude/loop-cost.jsonl"
GATESHARE_REPORT_OUT="$(report "$GATESHAREDIR" gate-share-unit)"
GATESHARE_SENTENCE="$(printf '%s\n' "$GATESHARE_REPORT_OUT" | grep '^  based on' | head -1 | sed 's/^  //')"
GATESHARE_JSON="$(budget_payload gate-share-unit)"
GATESHARE_GATE_ERR="$(CLAUDE_PROJECT_DIR="$GATESHAREDIR" LARAVEL_LOOP_BUDGET_HARD=999999 gate_stderr "$GATESHARE_JSON")"
collect_bg "" "$GATESHARE_GATE_ERR"
expect "(S2-4) CL6: report's coverage sentence carries the 50% share and names build" "yes" \
  "$(printf '%s\n' "$GATESHARE_SENTENCE" | grep -qE '50 ?%' && printf '%s\n' "$GATESHARE_SENTENCE" | grep -qE 'wholly unobserved:.*\bbuild\b' && echo yes || echo no)"
expect "(S2-4) CL6: gate's partial-coverage notice carries that exact sentence verbatim" "yes" \
  "$(printf '%s\n' "$GATESHARE_GATE_ERR" | grep -qF "$GATESHARE_SENTENCE" && echo yes || echo no)"
rm -rf "$GATESHAREDIR"

# -- (h) unreadable ledger, PATH stripped of jq+python3, and an unwritable
# state dir: each exits 0 and says it is proceeding as if no threshold were
# set (BG10) — asserted per case.
BGH1DIR="$(mktemp -d)"
mkdir -p "$BGH1DIR/.claude"
printf '%s\n' '{"ts":1,"event":"start","invocation_id":"h1","slug":"unreadable-unit","phase":"build","agent":"loop-build"}
{"ts":2,"event":"finish","invocation_id":"h1","slug":"unreadable-unit","phase":"build","agent":"loop-build","status":"completed","total_tokens":10}' > "$BGH1DIR/.claude/loop-cost.jsonl"
chmod 000 "$BGH1DIR/.claude/loop-cost.jsonl"
BGH1_JSON="$(budget_payload unreadable-unit)"
BGH1_ERR="$(CLAUDE_PROJECT_DIR="$BGH1DIR" LARAVEL_LOOP_BUDGET_HARD=1 gate_stderr "$BGH1_JSON")"
BGH1_EXIT="$(CLAUDE_PROJECT_DIR="$BGH1DIR" LARAVEL_LOOP_BUDGET_HARD=1 gate_exit "$BGH1_JSON")"
collect_bg "" "$BGH1_ERR"
expect "(h) unreadable ledger: exit 0 (BG10)" "0" "$BGH1_EXIT"
expect "(h) unreadable ledger: says it is proceeding as if no threshold were set (BG10)" "yes" \
  "$(printf '%s\n' "$BGH1_ERR" | grep -qi 'proceeding as if no threshold were set' && echo yes || echo no)"
chmod 644 "$BGH1DIR/.claude/loop-cost.jsonl"
rm -rf "$BGH1DIR"

BGH2DIR="$(mktemp -d)"
mkdir -p "$BGH2DIR/.claude"
printf '%s\n' '{"ts":1,"event":"start","invocation_id":"n1","slug":"noparser-unit","phase":"build","agent":"loop-build"}
{"ts":2,"event":"finish","invocation_id":"n1","slug":"noparser-unit","phase":"build","agent":"loop-build","status":"completed","total_tokens":10}' > "$BGH2DIR/.claude/loop-cost.jsonl"
BGH2_BIN="$(mktemp -d)"
for b in cat mkdir sed grep tr bash head; do
  p="$(command -v "$b" 2>/dev/null)"
  [ -n "$p" ] && ln -s "$p" "$BGH2_BIN/$b"
done
BGH2_JSON="$(budget_payload noparser-unit)"
BGH2_ERR="$(CLAUDE_PROJECT_DIR="$BGH2DIR" LARAVEL_LOOP_BUDGET_HARD=1 PATH="$BGH2_BIN" gate_stderr "$BGH2_JSON")"
BGH2_EXIT="$(CLAUDE_PROJECT_DIR="$BGH2DIR" LARAVEL_LOOP_BUDGET_HARD=1 PATH="$BGH2_BIN" gate_exit "$BGH2_JSON")"
collect_bg "" "$BGH2_ERR"
expect "(h) PATH stripped of jq+python3: exit 0 (BG10)" "0" "$BGH2_EXIT"
expect "(h) PATH stripped of jq+python3: says it is proceeding as if no threshold were set (BG10)" "yes" \
  "$(printf '%s\n' "$BGH2_ERR" | grep -qi 'proceeding as if no threshold were set' && echo yes || echo no)"
rm -rf "$BGH2DIR" "$BGH2_BIN"

BGH3DIR="$(mktemp -d)"
mkdir -p "$BGH3DIR/.claude"
printf '%s\n' '{"ts":1,"event":"start","invocation_id":"u1","slug":"unwritable-unit","phase":"build","agent":"loop-build"}
{"ts":2,"event":"finish","invocation_id":"u1","slug":"unwritable-unit","phase":"build","agent":"loop-build","status":"completed","total_tokens":10}' > "$BGH3DIR/.claude/loop-cost.jsonl"
mkdir -p "$BGH3DIR/.claude/loop-budget-state"
chmod 555 "$BGH3DIR/.claude/loop-budget-state"
BGH3_JSON="$(budget_payload unwritable-unit)"
BGH3_ERR="$(CLAUDE_PROJECT_DIR="$BGH3DIR" LARAVEL_LOOP_BUDGET_HARD=1 gate_stderr "$BGH3_JSON")"
BGH3_EXIT="$(CLAUDE_PROJECT_DIR="$BGH3DIR" LARAVEL_LOOP_BUDGET_HARD=1 gate_exit "$BGH3_JSON")"
collect_bg "" "$BGH3_ERR"
expect "(h) unwritable state dir: exit 0 (BG10)" "0" "$BGH3_EXIT"
expect "(h) unwritable state dir: says it is proceeding as if no threshold were set (BG10)" "yes" \
  "$(printf '%s\n' "$BGH3_ERR" | grep -qi 'proceeding as if no threshold were set' && echo yes || echo no)"
chmod 755 "$BGH3DIR/.claude/loop-budget-state"
rm -rf "$BGH3DIR"

# -- (i) the blocking path completes within a bounded time (BG12) — run
# under `timeout` and assert it returns rather than hanging or waiting for
# more stdin.
BGTIMEDIR="$(mktemp -d)"
mkdir -p "$BGTIMEDIR/.claude"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"t1","slug":"timeout-unit","slice":"A","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"t1","slug":"timeout-unit","slice":"A","phase":"build","agent":"loop-build","status":"completed","total_tokens":1000000}'
} > "$BGTIMEDIR/.claude/loop-cost.jsonl"
BGTIME_JSON="$(budget_payload timeout-unit)"
BGTIME_RC="$(CLAUDE_PROJECT_DIR="$BGTIMEDIR" LARAVEL_LOOP_BUDGET_HARD=1 timeout 5 bash -c 'printf "%s" "$1" | bash "$2"' _ "$BGTIME_JSON" "$SCRIPTS/check-budget-gate.sh" >/dev/null 2>&1; echo $?)"
expect "(i) blocking path returns within a bounded time, not a timeout (BG12)" "yes" \
  "$( [ "$BGTIME_RC" != "124" ] && echo yes || echo no )"
rm -rf "$BGTIMEDIR"

# -- (j) a PostToolUse finish payload produces no gate output at all, even
# with a threshold that would otherwise breach (BG4).
BGPOSTDIR="$(mktemp -d)"
mkdir -p "$BGPOSTDIR/.claude"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"j1","slug":"post-unit","slice":"A","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"j1","slug":"post-unit","slice":"A","phase":"build","agent":"loop-build","status":"completed","total_tokens":1000000}'
} > "$BGPOSTDIR/.claude/loop-cost.jsonl"
BGPOST_JSON="$(budget_payload post-unit PostToolUse)"
BGPOST_OUT="$(CLAUDE_PROJECT_DIR="$BGPOSTDIR" LARAVEL_LOOP_BUDGET_HARD=1 gate_stdout "$BGPOST_JSON")"
BGPOST_ERR="$(CLAUDE_PROJECT_DIR="$BGPOSTDIR" LARAVEL_LOOP_BUDGET_HARD=1 gate_stderr "$BGPOST_JSON")"
BGPOST_EXIT="$(CLAUDE_PROJECT_DIR="$BGPOSTDIR" LARAVEL_LOOP_BUDGET_HARD=1 gate_exit "$BGPOST_JSON")"
collect_bg "$BGPOST_OUT" "$BGPOST_ERR"
expect "(j) PostToolUse finish payload: exit 0, no gate output at all (BG4)" "0" "$BGPOST_EXIT"
expect "(j) PostToolUse finish payload: stdout empty (BG4)" "" "$BGPOST_OUT"
expect "(j) PostToolUse finish payload: stderr empty (BG4)" "" "$BGPOST_ERR"
rm -rf "$BGPOSTDIR"

# -- (l) the hard-override marker for a unit raises the effective threshold
# for that unit only; with HARD unset the marker alone produces nothing
# (BG11).
BGOVERDIR="$(mktemp -d)"
mkdir -p "$BGOVERDIR/.claude"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"o1","slug":"override-unit","slice":"A","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"o1","slug":"override-unit","slice":"A","phase":"build","agent":"loop-build","status":"completed","total_tokens":1000}'
} > "$BGOVERDIR/.claude/loop-cost.jsonl"
BGOVER_JSON="$(budget_payload override-unit)"
BGOVER_EXIT_BEFORE="$(CLAUDE_PROJECT_DIR="$BGOVERDIR" LARAVEL_LOOP_BUDGET_HARD=500 gate_exit "$BGOVER_JSON")"
expect "(l) before the override: HARD=500 vs total 1000 breaches (sanity)" "2" "$BGOVER_EXIT_BEFORE"
mkdir -p "$BGOVERDIR/.claude/loop-budget-state/override-unit"
printf '2000' > "$BGOVERDIR/.claude/loop-budget-state/override-unit/hard-override"
BGOVER_EXIT_AFTER="$(CLAUDE_PROJECT_DIR="$BGOVERDIR" LARAVEL_LOOP_BUDGET_HARD=500 gate_exit "$BGOVER_JSON")"
expect "(l) hard-override raises the effective threshold for this unit (BG11)" "0" "$BGOVER_EXIT_AFTER"
BGOVER_OUT_ALONE="$(CLAUDE_PROJECT_DIR="$BGOVERDIR" gate_stdout "$BGOVER_JSON")"
BGOVER_ERR_ALONE="$(CLAUDE_PROJECT_DIR="$BGOVERDIR" gate_stderr "$BGOVER_JSON")"
BGOVER_EXIT_ALONE="$(CLAUDE_PROJECT_DIR="$BGOVERDIR" gate_exit "$BGOVER_JSON")"
collect_bg "$BGOVER_OUT_ALONE" "$BGOVER_ERR_ALONE"
expect "(l) override marker alone with HARD unset: exit 0 (BG11/BG1)" "0" "$BGOVER_EXIT_ALONE"
expect "(l) override marker alone with HARD unset: stdout empty (BG11/BG1)" "" "$BGOVER_OUT_ALONE"
expect "(l) override marker alone with HARD unset: stderr empty (BG11/BG1)" "" "$BGOVER_ERR_ALONE"
rm -rf "$BGOVERDIR"

# -- (m) record-cost-event.sh is untouched by this slice, and stays
# observe-only (BG13, X4): no budget vocabulary was added to it.
expect "(m) record-cost-event.sh carries no LARAVEL_LOOP_BUDGET reference (BG13, X4)" "1" \
  "$(grep -q 'LARAVEL_LOOP_BUDGET' "$SCRIPTS/record-cost-event.sh"; echo $?)"

# -- (n) the new registration doesn't disturb the structure check (X5), and
# the gate is registered only on PreToolUse/Agent|Task — never on an event
# that fires mid-invocation (BG4).
expect "(n) check-budget-gate.sh is registered on PreToolUse/Agent|Task only" "1" \
  "$(python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
h = json.load(open(os.path.join(root, "hooks", "hooks.json")))["hooks"]
count = 0
for event, entries in h.items():
    for e in entries:
        for hk in e["hooks"]:
            if hk["command"].endswith("check-budget-gate.sh"):
                count += 1
                assert event == "PreToolUse" and e["matcher"] == "Agent|Task", "wrong event/matcher"
print(count)
PY
)"

# -- (o) G0-D1 regression (S4 re-brief, closing loop-verify's G2 FAIL): no
# digit ever shares a line with LARAVEL_LOOP_BUDGET_WARN or
# LARAVEL_LOOP_BUDGET_HARD anywhere in check-budget-gate.sh's OWN SOURCE.
# Mirrors the docs section's README-only case (c) below, but S8's version
# never scanned the script itself -- which is exactly how "Accepted form:
# digits only, e.g. 150000." / "...e.g. 400000." shipped undetected in the
# two disable messages: a numeric example sitting right next to the env-var
# name a human sees at the one moment they are most likely to typo it. (Proof
# this case can fail: reconstructing that exact pre-fix wording in a temp
# copy trips this same grep -- verified by hand during S4's re-brief rather
# than kept as a second permanent case, matching S8's own single-assertion
# shape below and this file's own case-count discipline.)
expect "(o) G0-D1: no digit shares a line with LARAVEL_LOOP_BUDGET_WARN or LARAVEL_LOOP_BUDGET_HARD anywhere in check-budget-gate.sh's own source" \
  "0" "$(grep -qE 'LARAVEL_LOOP_BUDGET_(WARN|HARD)[^\n]*[0-9]' "$SCRIPTS/check-budget-gate.sh" 2>/dev/null && echo 1 || echo 0)"

# -- (k) no reassurance token anywhere in any message this section produced.
expect "(k) BG6: no 'within budget', 'under budget', or checkmark in any budget-gate output" "1" \
  "$( { printf '%s\n' "$ALL_BG_STDOUT"; printf '%s\n' "$ALL_BG_STDERR"; } | grep -iE 'within budget|under budget|✓' >/dev/null 2>&1; echo $?)"

# -- S6: the conductor's own behaviour at the gate, in commands/loop.md.
# Markdown-only cases: this slice edits no script, hook, or JSON.
LOOPMD="$ROOT/commands/loop.md"

# (a) the numbered-options gate presentation, re-slicing as the recommended
# option, raising the cap listed last, the in-flight-completes rule, the
# per-unit hard-override marker path, and the unattended-run behaviour —
# echoes "0" clean, "1" if any is missing from the file's own breach-gate
# region (between "On a budget breach" and step 4).
loop_budget_gate_check() {
  local f="$1" bad=0 block
  block="$(sed -n '/On a budget breach/,/^\*\*4\. Verify/p' "$f" 2>/dev/null)"
  [ -n "$block" ] || bad=1
  printf '%s\n' "$block" | grep -qE '^1\.' || bad=1
  printf '%s\n' "$block" | grep -qE '^2\.' || bad=1
  printf '%s\n' "$block" | grep -qE '^3\.' || bad=1
  printf '%s\n' "$block" | grep -E '^1\.' | grep -qi 're-slic' || bad=1
  printf '%s\n' "$block" | grep -E '^1\.' | grep -qi 'recommended' || bad=1
  printf '%s\n' "$block" | grep -E '^3\.' | grep -qi 'raise' || bad=1
  printf '%s\n' "$block" | grep -qi 'in flight' || bad=1
  printf '%s\n' "$block" | grep -qF '.claude/loop-budget-state/<slug>/hard-override' || bad=1
  printf '%s\n' "$block" | grep -qiE 'unattended|non-interactive' || bad=1
  echo "$bad"
}

# Prove the case can fail before trusting that it can pass: strip every line
# carrying the breach-gate vocabulary from a temp copy and expect it to go red.
LOOPGATEDIR="$(mktemp -d)"
mkdir -p "$LOOPGATEDIR/commands"
grep -v -iE 'budget|re-slic|hard cap|hard-override|unattended' "$LOOPMD" > "$LOOPGATEDIR/commands/loop.md"
expect "(a) breach-gate documentation fails on a stripped copy (proves the case can fail)" \
  "1" "$(loop_budget_gate_check "$LOOPGATEDIR/commands/loop.md")"
rm -rf "$LOOPGATEDIR"

expect "(a) breach-gate documentation present in commands/loop.md (BG3, BG4, BG11, BG12)" \
  "0" "$(loop_budget_gate_check "$LOOPMD")"

# (b) raising the cap is never persisted anywhere but the marker: named
# explicitly so a later editor cannot soften it to "temporarily" (BG11).
expect "(b) commands/loop.md forbids persisting a raised cap — names settings.json, .env, an env var (BG11)" "yes" \
  "$(grep -q 'settings.json' "$LOOPMD" && grep -q '\.env' "$LOOPMD" && grep -qi 'env var' "$LOOPMD" && echo yes || echo no)"

# (c) the '## Budget events' instruction names all four event kinds and the
# threshold-in-force phrase (DL6).
expect "(c) '## Budget events' instruction names all four event kinds + threshold-in-force (DL6)" "yes" \
  "$(grep -q '## Budget events' "$LOOPMD" \
     && grep -q 'warn crossed' "$LOOPMD" \
     && grep -q 'hard gate fired' "$LOOPMD" \
     && grep -q 'cap raised' "$LOOPMD" \
     && grep -qi 'gate disabled by an unparseable value' "$LOOPMD" \
     && grep -qF 'the threshold in force at the time' "$LOOPMD" \
     && echo yes || echo no)"

# (d) negative case: never a reassurance token for spend, anywhere in
# commands/loop.md (BG6).
expect "(d) commands/loop.md never instructs 'within budget'/'under budget'/checkmark for spend (BG6)" "no" \
  "$(grep -iE 'within budget|under budget|✓' "$LOOPMD" >/dev/null 2>&1 && echo yes || echo no)"

# (e) [retired by S7 (cost-reporting-v0.3): the original version of this
# case asserted step 5 (Close) had no diff at all, which was only ever true
# because S6's own commit never touched it. That assertion goes stale the
# moment a slice legitimately edits step 5, so S7 replaces it with the
# boundary's other half — step 3/4 (the breach-gate documentation this slice
# owns, "On a budget breach" through "**4. Verify") has no diff introduced
# by S7's edits to step 5. Compares the region as last committed (HEAD)
# against the current working tree; empty means S7 touched no byte of it,
# which is S7's own done-when (h).]
build_region() {
  sed -n '/On a budget breach/,/^\*\*4\. Verify/p' "$1" 2>/dev/null
}
BUILD_HEAD="$(cd "$ROOT" && git show HEAD:commands/loop.md 2>/dev/null | sed -n '/On a budget breach/,/^\*\*4\. Verify/p')"
BUILD_WORK="$(build_region "$LOOPMD")"
expect "(e) step 3/4 (Build) breach-gate region (S6's) has no diff from S7's edits to step 5 (boundary machine-checked)" "" \
  "$(diff <(printf '%s\n' "$BUILD_HEAD") <(printf '%s\n' "$BUILD_WORK"))"

# ---------------------------------------------------------------------------
echo "check-budget-gate.sh --phase (per-phase expectations, S5)"

phase_stdout() { # $1 phase  $2 slug  (env vars set by the caller as a prefix)
  bash "$SCRIPTS/check-budget-gate.sh" --phase "$1" --unit "$2" 2>/dev/null
}
phase_stderr() { # $1 phase  $2 slug
  bash "$SCRIPTS/check-budget-gate.sh" --phase "$1" --unit "$2" 2>&1 1>/dev/null
}
phase_exit() { # $1 phase  $2 slug
  bash "$SCRIPTS/check-budget-gate.sh" --phase "$1" --unit "$2" >/dev/null 2>&1
  echo $?
}

# -- fixture: one build-phase invocation, fully priced at 500000 tokens.
PHASEXPDIR="$(mktemp -d)"
mkdir -p "$PHASEXPDIR/.claude"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"px1","slug":"phase-exp-build","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"px1","slug":"phase-exp-build","phase":"build","agent":"loop-build","status":"completed","total_tokens":500000}'
} > "$PHASEXPDIR/.claude/loop-cost.jsonl"

# (a)/(e) PE3/PE4/PE6 — threshold below the phase's priced total: exactly one
# FLAG line, containing the coverage caveat, exit 0.
PEA_OUT="$(CLAUDE_PROJECT_DIR="$PHASEXPDIR" LARAVEL_LOOP_BUDGET_PHASE_BUILD=100000 phase_stdout build phase-exp-build)"
PEA_EXIT="$(CLAUDE_PROJECT_DIR="$PHASEXPDIR" LARAVEL_LOOP_BUDGET_PHASE_BUILD=100000 phase_exit build phase-exp-build)"
expect "(a) build over its configured expectation: exit 0 (PE3)" "0" "$PEA_EXIT"
expect "(a) build over its configured expectation: exactly one FLAG line (PE6)" "yes" \
  "$(printf '%s' "$PEA_OUT" | grep -c '^FLAG:' | grep -qx 1 && echo yes || echo no)"
expect "(a) the FLAG line carries the coverage caveat (PE4)" "yes" \
  "$(printf '%s\n' "$PEA_OUT" | grep -q 'unpriced, not counted' && echo yes || echo no)"
expect "(a) the FLAG line says it never blocks (PE3)" "yes" \
  "$(printf '%s\n' "$PEA_OUT" | grep -qi 'blocks nothing' && echo yes || echo no)"
expect "(e) the printed flag is exactly one line, asserted with wc -l (PE6)" "1" \
  "$(printf '%s\n' "$PEA_OUT" | wc -l | tr -d ' ')"

# (b) PE1 — unset: zero bytes of output on either stream, exit 0.
PEB_OUT_BYTES="$(CLAUDE_PROJECT_DIR="$PHASEXPDIR" phase_stdout build phase-exp-build | wc -c | tr -d ' ')"
PEB_ERR_BYTES="$(CLAUDE_PROJECT_DIR="$PHASEXPDIR" phase_stderr build phase-exp-build | wc -c | tr -d ' ')"
PEB_EXIT="$(CLAUDE_PROJECT_DIR="$PHASEXPDIR" phase_exit build phase-exp-build)"
expect "(b) LARAVEL_LOOP_BUDGET_PHASE_BUILD unset: exit 0 (PE1)" "0" "$PEB_EXIT"
expect "(b) LARAVEL_LOOP_BUDGET_PHASE_BUILD unset: zero bytes on stdout (PE1)" "0" "$PEB_OUT_BYTES"
expect "(b) LARAVEL_LOOP_BUDGET_PHASE_BUILD unset: zero bytes on stderr (PE1)" "0" "$PEB_ERR_BYTES"

# (c) an unparseable value disables the comparison loudly, names the field
# and the value, and never compares (mirrors BG2's discipline exactly).
for bad in '400k' '4e5' '-1' '1.5' ' 100'; do
  c_err="$(CLAUDE_PROJECT_DIR="$PHASEXPDIR" LARAVEL_LOOP_BUDGET_PHASE_BUILD="$bad" phase_stderr build phase-exp-build)"
  c_out="$(CLAUDE_PROJECT_DIR="$PHASEXPDIR" LARAVEL_LOOP_BUDGET_PHASE_BUILD="$bad" phase_stdout build phase-exp-build)"
  c_exit="$(CLAUDE_PROJECT_DIR="$PHASEXPDIR" LARAVEL_LOOP_BUDGET_PHASE_BUILD="$bad" phase_exit build phase-exp-build)"
  expect "(c) LARAVEL_LOOP_BUDGET_PHASE_BUILD=\"$bad\": disabled, exit 0" "0" "$c_exit"
  expect "(c) LARAVEL_LOOP_BUDGET_PHASE_BUILD=\"$bad\": names the field and the value" "yes" \
    "$(printf '%s' "$c_err" | grep -q 'LARAVEL_LOOP_BUDGET_PHASE_BUILD' && printf '%s' "$c_err" | grep -qF -- "$bad" && echo yes || echo no)"
  expect "(c) LARAVEL_LOOP_BUDGET_PHASE_BUILD=\"$bad\": no FLAG, no comparison performed" "no" \
    "$(printf '%s' "$c_out" | grep -q '^FLAG:' && echo yes || echo no)"
done

# threshold set ABOVE the priced total: never flags, and never reassures
# (BG6's discipline, applied per phase — PE5).
PEZ_OUT="$(CLAUDE_PROJECT_DIR="$PHASEXPDIR" LARAVEL_LOOP_BUDGET_PHASE_BUILD=999999999 phase_stdout build phase-exp-build)"
PEZ_ERR="$(CLAUDE_PROJECT_DIR="$PHASEXPDIR" LARAVEL_LOOP_BUDGET_PHASE_BUILD=999999999 phase_stderr build phase-exp-build)"
expect "threshold above the total: no FLAG" "" "$PEZ_OUT"
expect "threshold above the total: no reassurance text anywhere" "1" \
  "$(printf '%s\n%s\n' "$PEZ_OUT" "$PEZ_ERR" | grep -iE 'within expectation|✓|\bOK\b' >/dev/null 2>&1; echo $?)"

rm -rf "$PHASEXPDIR"

# (d) PE5/BG6 — a fixture whose only build invocation is unpriced: no FLAG
# at any threshold, however low, and no "within expectation" or checkmark
# text anywhere.
PHASEUNPRICEDDIR="$(mktemp -d)"
mkdir -p "$PHASEUNPRICEDDIR/.claude"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"pu1","slug":"phase-exp-unpriced","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"pu1","slug":"phase-exp-unpriced","phase":"build","agent":"loop-build","status":"async_launched"}'
} > "$PHASEUNPRICEDDIR/.claude/loop-cost.jsonl"
PED_OUT="$(CLAUDE_PROJECT_DIR="$PHASEUNPRICEDDIR" LARAVEL_LOOP_BUDGET_PHASE_BUILD=1 phase_stdout build phase-exp-unpriced)"
PED_ERR="$(CLAUDE_PROJECT_DIR="$PHASEUNPRICEDDIR" LARAVEL_LOOP_BUDGET_PHASE_BUILD=1 phase_stderr build phase-exp-unpriced)"
PED_EXIT="$(CLAUDE_PROJECT_DIR="$PHASEUNPRICEDDIR" LARAVEL_LOOP_BUDGET_PHASE_BUILD=1 phase_exit build phase-exp-unpriced)"
expect "(d) all-unpriced phase: exit 0 even at threshold=1 (PE5)" "0" "$PED_EXIT"
expect "(d) all-unpriced phase: no FLAG at any threshold (PE5)" "" "$PED_OUT"
expect "(d) all-unpriced phase: no 'within expectation' or checkmark anywhere (BG6)" "1" \
  "$(printf '%s\n%s\n' "$PED_OUT" "$PED_ERR" | grep -iE 'within expectation|✓' >/dev/null 2>&1; echo $?)"
rm -rf "$PHASEUNPRICEDDIR"

# -- (h) every S4 (hook-mode) case is unaffected by this mode's addition:
# the whole check-budget-gate.sh (budget gate, S4) section above already
# reran and passed unmodified in this same file, so nothing further to
# assert here beyond the fact this section changed no fixture of that one.

# -- (f)/(g) documentation: SKILL.md names all four fields, how to set them,
# that nothing is defaulted and why, and the in-flight limitation; every
# agent instructs the check and carries the FLAG wording; the section itself
# never exemplifies a number next to a field name (G0-D2).
phase_doc_check() {
  local root="$1" bad=0 skill
  skill="$root/skills/loop-protocol/SKILL.md"
  local f
  for f in SPEC SLICE BUILD VERIFY; do
    grep -q "LARAVEL_LOOP_BUDGET_PHASE_${f}" "$skill" || bad=1
  done
  grep -qi 'set by default' "$skill" || bad=1
  grep -qi 'no baseline' "$skill" || bad=1
  grep -qi 'bare non-negative integer' "$skill" || bad=1
  grep -qi 'finish record' "$skill" || bad=1
  for f in loop-spec loop-slice loop-build loop-verify; do
    grep -q -- '--phase' "$root/agents/$f.md" || bad=1
    grep -q 'FLAG' "$root/agents/$f.md" || bad=1
  done
  echo "$bad"
}

# Prove the case can fail before trusting that it can pass: strip every
# phase-expectations-carrying line from a temp copy and expect the check to
# go red (the "envelope attribution" idiom, run here first).
PHASEDOCDIR="$(mktemp -d)"
mkdir -p "$PHASEDOCDIR/skills/loop-protocol" "$PHASEDOCDIR/agents"
cp "$ROOT/skills/loop-protocol/SKILL.md" "$PHASEDOCDIR/skills/loop-protocol/SKILL.md"
cp "$ROOT"/agents/loop-spec.md "$ROOT"/agents/loop-slice.md "$ROOT"/agents/loop-build.md "$ROOT"/agents/loop-verify.md "$PHASEDOCDIR/agents/"
for f in "$PHASEDOCDIR/skills/loop-protocol/SKILL.md" "$PHASEDOCDIR"/agents/*.md; do
  grep -v -i -E 'LARAVEL_LOOP_BUDGET_PHASE|--phase|set by default|no baseline|bare non-negative integer|finish record|FLAG' "$f" > "$f.stripped" && mv "$f.stripped" "$f"
done
expect "phase expectations doc: fails on a stripped copy (proves the case can fail)" \
  "1" "$(phase_doc_check "$PHASEDOCDIR")"
rm -rf "$PHASEDOCDIR"

expect "phase expectations doc: present on the real tree" "0" "$(phase_doc_check "$ROOT")"

# (g) G0-D2 — the new SKILL.md section itself contains no digit at all, so no
# example number can ever sit next to a LARAVEL_LOOP_BUDGET_PHASE_* name.
PHASE_SECTION="$(awk '/^## Per-phase expectations/{f=1} /^## The refine cap/{f=0} f' "$ROOT/skills/loop-protocol/SKILL.md")"
expect "phase expectations doc: section names all four fields" "yes" \
  "$(printf '%s\n' "$PHASE_SECTION" | grep -q 'LARAVEL_LOOP_BUDGET_PHASE_SPEC' && printf '%s\n' "$PHASE_SECTION" | grep -q 'LARAVEL_LOOP_BUDGET_PHASE_SLICE' && printf '%s\n' "$PHASE_SECTION" | grep -q 'LARAVEL_LOOP_BUDGET_PHASE_BUILD' && printf '%s\n' "$PHASE_SECTION" | grep -q 'LARAVEL_LOOP_BUDGET_PHASE_VERIFY' && echo yes || echo no)"
expect "phase expectations doc: no digit anywhere in the section (G0-D2)" "0" \
  "$(printf '%s\n' "$PHASE_SECTION" | grep -c '[0-9]')"

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

expect "observe: O4 — attribution recorded as a followable reference, never a guess" "0" \
  "$( grep -qi 'followable' "$OBSERVE" \
      && grep -qi 'no guess' "$OBSERVE" \
      && grep -qi 'commit SHA' "$OBSERVE" \
      && echo 0 || echo 1 )"

expect "observe: O5 — no credentials, no telemetry client, no network call" "0" \
  "$( ! grep -qiE 'curl |wget |\btoken\b|api[._-]?key' "$OBSERVE" \
      && grep -qi 'not telemetry' "$OBSERVE" \
      && grep -qi 'no network call' "$OBSERVE" \
      && grep -qi 'credential' "$OBSERVE" \
      && echo 0 || echo 1 )"

expect "observe: O6 — project-agnostic, assumes nothing about language or toolchain" "0" \
  "$( grep -qi 'regardless of language or toolchain' "$OBSERVE" \
      && grep -qi 'repository' "$OBSERVE" \
      && echo 0 || echo 1 )"

# ---------------------------------------------------------------------------
echo "loop-protocol (outer loop's ↺ resolution — skills/loop-protocol/SKILL.md)"
LOOP_PROTOCOL_SKILL="$ROOT/skills/loop-protocol/SKILL.md"

expect "loop-protocol: outer-loop diagram's ↺ resolves to /observe's capture step" "0" \
  "$( grep -q '↺' "$LOOP_PROTOCOL_SKILL" \
      && grep -q '/observe' "$LOOP_PROTOCOL_SKILL" \
      && grep -qi 'capture step' "$LOOP_PROTOCOL_SKILL" \
      && echo 0 || echo 1 )"

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

# Builds a directory holding exactly the external tools scripts/ship-check.sh
# itself needs -- resolved against the CALLER's own PATH before any pruning,
# symlinked under their bare names -- and deliberately omits shellcheck.
# Setting PATH to this directory alone forces GENUINE, PORTABLE absence: it
# never guesses which directories a platform's package manager avoids (the
# old fixture's `/usr/bin:/bin:/usr/sbin:/sbin` allow-list broke exactly
# because apt's shellcheck lands inside it -- spike-case-b.md §1), and it
# never strips bash/coreutils just because a platform happens to co-locate
# them with shellcheck. That co-location is real, not hypothetical: on
# Ubuntu's merged /usr/bin, `bash` and `shellcheck` resolve to the SAME
# real directory, so excluding wherever shellcheck resolves wholesale would
# take bash down with it and the case would fail for the wrong reason
# (confirmed against a throwaway container, investigation-grade).
new_shellcheck_absent_path() {
  local dir tool resolved
  dir="$(mktemp -d)"
  for tool in bash git mktemp cat rm head tr grep sed sleep; do
    resolved="$(command -v "$tool" 2>/dev/null || true)"
    [ -n "$resolved" ] && ln -s "$resolved" "$dir/$tool"
  done
  printf '%s' "$dir"
}

# recovered-figure-drops-slice-and-model S2 -- makes jq genuinely absent while
# leaving every other tool cost-report.sh/cost-ledger-lib.sh might reach for
# (python3, grep, sed, ...) resolvable, so a parity case exercises the real
# python3 fallback rather than a parse-error path. A CURATED list, the same
# shape as new_shellcheck_absent_path above, is NOT enough here: verified
# 2026-08-18 that a sparser PATH missing grep/sed makes the lib report a
# parse error instead of falling through to python3, which would make a
# parity case pass for the wrong reason. Symlinking every resolvable entry of
# the standard bin directories, skipping only jq's own name, avoids that.
new_jq_absent_path() {
  local dir bindir f base
  dir="$(mktemp -d)"
  for bindir in /usr/bin /bin /usr/sbin /sbin /opt/homebrew/bin /usr/local/bin; do
    [ -d "$bindir" ] || continue
    for f in "$bindir"/*; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      [ "$base" = "jq" ] && continue
      [ -e "$dir/$base" ] && continue
      ln -s "$f" "$dir/$base" 2>/dev/null
    done
  done
  printf '%s' "$dir"
}

# cost-log-section-parse-error-on-macos-ci S1 -- makes grep genuinely absent
# while leaving every other tool cost_scan reaches for (bash, awk, mktemp,
# mv, tr, jq-or-python3) resolvable, following new_jq_absent_path()'s shape
# exactly (PF12-PF15's pinned PATH-fixture contract): a curated allow-list
# is not enough, per the same 2026-08-18 finding this file already records
# above -- a sparser PATH missing grep made the library report a parse
# error, which is the exact defect this slice closes. Symlinking every
# resolvable entry of the standard bin directories, skipping only grep's
# own name, is what forces the route without also forcing something else.
new_grep_absent_path() {
  local dir bindir f base
  dir="$(mktemp -d)"
  for bindir in /usr/bin /bin /usr/sbin /sbin /opt/homebrew/bin /usr/local/bin; do
    [ -d "$bindir" ] || continue
    for f in "$bindir"/*; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      [ "$base" = "grep" ] && continue
      [ -e "$dir/$base" ] && continue
      ln -s "$f" "$dir/$base" 2>/dev/null
    done
  done
  printf '%s' "$dir"
}

# cost-log-section-parse-error-on-macos-ci S2 -- follows new_jq_absent_path()
# and new_grep_absent_path()'s shape exactly (PF1/PF2's pinned PATH-fixture
# contract), but this one is parametrised: it skips BOTH real jq and real
# python3 during the symlink pass (never just the one named), then plants a
# STUB at the requested name only. That means the other parser is genuinely
# ABSENT from this PATH -- never symlinked, never stubbed -- so a case can
# force the real python3 fallback to run against a chosen jq behaviour (or
# vice versa) without the untouched parser's real binary interfering.
# Reused by S3 and S4 rather than redefined (slices.md's "one helper,
# defined once").
new_stub_parser_path() { # $1 parser to stub (jq|python3) $2 stub script body
  local parser="$1" body="$2"
  local dir bindir f base
  dir="$(mktemp -d)"
  for bindir in /usr/bin /bin /usr/sbin /sbin /opt/homebrew/bin /usr/local/bin; do
    [ -d "$bindir" ] || continue
    for f in "$bindir"/*; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      case "$base" in jq|python3) continue ;; esac
      [ -e "$dir/$base" ] && continue
      ln -s "$f" "$dir/$base" 2>/dev/null
    done
  done
  printf '%s\n' "$body" > "$dir/$parser"
  chmod +x "$dir/$parser"
  printf '%s' "$dir"
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
SHELLCHECK_ABSENT_PATH="$(new_shellcheck_absent_path)"

# The defect this case exists to fix: the old fixture ASSUMED its hard-coded
# PATH allow-list achieved shellcheck's absence and never checked -- on
# Linux, apt's shellcheck lives inside that very allow-list, so the
# assumption was simply false there. Assert the precondition directly,
# under the exact PATH the invocation right below uses, so a future PATH
# layout that also fails to exclude shellcheck is caught here rather than
# silently producing the same false green the old fixture did.
PATH="$SHELLCHECK_ABSENT_PATH" command -v shellcheck >/dev/null 2>&1
SHELLCHECK_LOOKUP_EXIT=$?
expect "ship: case B's fixture trigger genuinely excludes shellcheck from PATH" \
  "1" "$SHELLCHECK_LOOKUP_EXIT"

SHIP_OUT="$(cd "$SHIP3" && PATH="$SHELLCHECK_ABSENT_PATH" bash scripts/ship-check.sh 2>&1)"
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
rm -rf "$SHIP3" "$SHELLCHECK_ABSENT_PATH"

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

SHIP20="$(new_ship_fixture)"
ship_run "$SHIP20"
case "$SHIP_OUT" in
  *"own release readiness"*"not a check of a"*"downstream Laravel application"*) OWN_READINESS_DISCLAIMED="yes" ;;
  *) OWN_READINESS_DISCLAIMED="no" ;;
esac
expect "ship: summary states it checks its own release readiness, not a downstream Laravel app's check" \
  "yes" "$OWN_READINESS_DISCLAIMED"
rm -rf "$SHIP20"

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

# gate 2 must run shellcheck at the same -S warning severity as CI and every
# slice's own Done-when bar. A style/info-only notice (SC2005 here) must not
# turn gate 2 red -- bare `shellcheck` (no -S) on the same file does flag it,
# which is what proves this case can fail.
SHIP13="$(new_ship_fixture)"
printf '#!/usr/bin/env bash\necho "$(echo styleonly)"\n' > "$SHIP13/scripts/clean.sh"
ship_run "$SHIP13"
G2_STATE="$(gate_line "$SHIP_OUT" 2)"
case "$G2_STATE" in
  *passed*) G2_PASSED_ON_STYLE_ONLY="yes" ;;
  *) G2_PASSED_ON_STYLE_ONLY="no" ;;
esac
BARE_SHELLCHECK_FLAGS_IT="no"
if ! shellcheck "$SHIP13/scripts/clean.sh" >/dev/null 2>&1; then
  BARE_SHELLCHECK_FLAGS_IT="yes"
fi
expect "ship: gate 2 uses -S warning, so a style-only notice still passes" \
  "yes" "$G2_PASSED_ON_STYLE_ONLY"
expect "ship: gate 2's case can fail -- bare shellcheck flags the same file" \
  "yes" "$BARE_SHELLCHECK_FLAGS_IT"
rm -rf "$SHIP13"

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

# README documents the cost ledger the way it documents the other two state
# files (S6, spec.md X4): the ledger path, both env var names, the "never
# leaves the machine" claim, the not-money statement, and the D3 rework
# wording lifted from record-cost-event.sh's own header. Every env var and
# path README names is also asserted to exist in the script itself, so the
# docs cannot describe a switch that was never built.
readme_ledger_check() {
  local bad=0 readme="$README_MD" script="$ROOT/scripts/record-cost-event.sh"
  grep -q 'loop-cost\.jsonl' "$readme" || bad=1
  grep -q 'LARAVEL_LOOP_COST_LEDGER' "$readme" || bad=1
  grep -q 'LARAVEL_LOOP_COST_MAX_LINES' "$readme" || bad=1
  grep -qi 'never leaves the machine' "$readme" || bad=1
  grep -qi 'not money' "$readme" || bad=1
  grep -q 'cost of slices that were not right first time' "$readme" || bad=1
  # the docs cannot name a switch or path the script does not actually have
  grep -q 'LARAVEL_LOOP_COST_LEDGER' "$script" || bad=1
  grep -q 'LARAVEL_LOOP_COST_MAX_LINES' "$script" || bad=1
  grep -q 'loop-cost\.jsonl' "$script" || bad=1
  echo $bad
}
expect "docs: README documents the cost ledger (path, env vars, machine, money, rework wording)" \
  "0" "$(readme_ledger_check)"

# S4 (eviction-cap-not-honoured-under-contention, spec.md E1) -- the eviction
# header names the cap's actual guarantee (eventual convergence, E1's
# property 3), the moment it holds at (a later invocation having arrived and
# discharged the trim -- not merely "converges" on its own), and states
# plainly that a bound at rest is not achievable while L7 stands; README's
# ledger paragraph carries that same moment in one clause. Flattened first
# (the CHECKSMD_FLAT technique) because the header wraps at ~76 columns and
# a single-line grep for a sentence spanning several lines fails for the
# wrong reason. One conjoined case, four labelled tokens: splitting it would
# let one surface drift while the other stayed green.
EVICTION_HEADER_FLAT="$(sed -n '/^# Bound + oldest-first eviction/,/^# Rework attribution/p' "$ROOT/scripts/record-cost-event.sh" | tr '#' ' ' | tr '\n' ' ' | tr -s ' ')"
README_LEDGER_LINE="$(grep 'LARAVEL_LOOP_COST_MAX_LINES' "$README_MD")"
expect "S4: eviction header states the cap's property (eventual convergence), the moment it holds at (a later invocation has arrived), that a bound at rest is not achievable while L7 stands, and README's ledger paragraph carries the same moment" \
  "property yes, moment yes, l7-limit yes, readme-moment yes" \
  "property $(printf '%s' "$EVICTION_HEADER_FLAT" | grep -qi 'eventual convergence' && echo yes || echo no), moment $(printf '%s' "$EVICTION_HEADER_FLAT" | grep -qi 'later invocation has arrived' && echo yes || echo no), l7-limit $(printf '%s' "$EVICTION_HEADER_FLAT" | grep -qi 'bound at rest is not achievable' && printf '%s' "$EVICTION_HEADER_FLAT" | grep -qi 'L7' && echo yes || echo no), readme-moment $(printf '%s' "$README_LEDGER_LINE" | grep -qi 'later invocation has arrived' && echo yes || echo no)"

# S8 (spec.md X6) -- README documents /cost, the budget gate (both env
# vars), the per-phase family, the full-suite guard's escape hatch, "unset
# means disabled", the no-default reasoning, and the never-money statement.
# Each of these strings is absent from README before this slice's edit.
readme_cost_report_and_budget_names_check() {
  local bad=0 readme="$README_MD"
  grep -q '/cost' "$readme" || bad=1
  grep -q '\.claude/loop-cost\.jsonl' "$readme" || bad=1
  grep -q 'LARAVEL_LOOP_BUDGET_WARN' "$readme" || bad=1
  grep -q 'LARAVEL_LOOP_BUDGET_HARD' "$readme" || bad=1
  grep -q 'LARAVEL_LOOP_ALLOW_FULL_SUITE' "$readme" || bad=1
  grep -q 'LARAVEL_LOOP_BUDGET_PHASE_SPEC' "$readme" || bad=1
  grep -qi 'unset means disabled' "$readme" || bad=1
  grep -qi 'no baseline' "$readme" || bad=1
  grep -qi 'never from a number in a document' "$readme" || bad=1
  grep -qi 'never in money' "$readme" || bad=1
  echo $bad
}
expect "docs: README names /cost, both budget env vars, the full-suite escape hatch, the per-phase family, 'unset means disabled', the no-default reasoning, and the never-money statement (X6)" \
  "0" "$(readme_cost_report_and_budget_names_check)"

# (b) -- every env var and script path this section names actually exists in
# the scripts that implement it, mirroring readme_ledger_check's own pattern:
# the docs cannot describe a switch that was never built.
readme_cost_report_and_budget_switches_exist_check() {
  local bad=0
  grep -q 'LARAVEL_LOOP_BUDGET_WARN' "$ROOT/scripts/check-budget-gate.sh" || bad=1
  grep -q 'LARAVEL_LOOP_BUDGET_HARD' "$ROOT/scripts/check-budget-gate.sh" || bad=1
  grep -q 'LARAVEL_LOOP_BUDGET_PHASE_' "$ROOT/scripts/check-budget-gate.sh" || bad=1
  grep -q 'LARAVEL_LOOP_ALLOW_FULL_SUITE' "$ROOT/scripts/warn-full-suite.sh" || bad=1
  [ -x "$ROOT/scripts/cost-report.sh" ] || bad=1
  [ -x "$ROOT/scripts/check-budget-gate.sh" ] || bad=1
  [ -x "$ROOT/scripts/warn-full-suite.sh" ] || bad=1
  [ -x "$ROOT/scripts/write-cost-log-section.sh" ] || bad=1
  echo $bad
}
expect "docs: every env var and script path README names for /cost and the budget gate exists and is executable in the scripts (b)" \
  "0" "$(readme_cost_report_and_budget_switches_exist_check)"

# (c) -- negative: G0-D1 forbids a suggested value anywhere near either
# budget variable or the per-phase family. No digit ever shares a line with
# a LARAVEL_LOOP_BUDGET* name in README, so a "helpful" example can never
# reintroduce a default.
expect "docs: no digit shares a line with any LARAVEL_LOOP_BUDGET* name in README (G0-D1)" "0" \
  "$(grep 'LARAVEL_LOOP_BUDGET' "$README_MD" | grep -cE '[0-9]')"

# (d) -- negative: BG6's discipline applies to README too. No unfired gate
# is ever framed as reassurance.
expect "docs: no 'within budget'/'under budget'/checkmark framing anywhere in README (BG6)" "1" \
  "$(grep -iE 'within budget|under budget|✓' "$README_MD" >/dev/null 2>&1; echo $?)"

# (e) -- X7: ship-check.sh's own version-consistency gate, run against this
# repository's REAL VERSION / plugin.json / marketplace.json (not a
# fixture), reads them as agreeing post-bump. Sourced rather than executed
# so only gate3_version runs -- executing the whole script here would invoke
# gate 1, which runs this very test file.
expect "docs: ship-check.sh's version gate reads this repo's real VERSION/plugin.json/marketplace.json as agreeing (X7)" \
  "passed" \
  "$(bash -c 'source "'"$ROOT"'/scripts/ship-check.sh"; ROOT="'"$ROOT"'"; gate3_version; printf "%s" "$GATE3_STATE"')"

# (f) -- S5 (spec.md X5, X6 -- cost-ledger-blind-to-background-agents):
# README states what the ledger can and cannot see about background-launched
# invocations, names the coverage-floor variable and its unset behaviour with
# no number attached, and decisions.md's superseded bullet is corrected in
# place while the 4%-coverage rejection stands untouched.
readme_background_majority_check() {
  local bad=0 readme="$README_MD"
  grep -qi 'majority of a' "$readme" || bad=1
  grep -q 'launched in background, outcome never observed' "$readme" || bad=1
  echo $bad
}
expect "docs: README states background-launched invocations are the majority of a /loop run and how they are treated (X5)" \
  "0" "$(readme_background_majority_check)"

readme_min_coverage_named_check() {
  local bad=0 readme="$README_MD"
  grep -q 'LARAVEL_LOOP_COST_MIN_COVERAGE' "$readme" || bad=1
  grep -qi "unset means today's behaviour" "$readme" || bad=1
  echo $bad
}
expect "docs: README names LARAVEL_LOOP_COST_MIN_COVERAGE and states unset means today's behaviour (X5)" \
  "0" "$(readme_min_coverage_named_check)"

expect "docs: no digit shares a line with LARAVEL_LOOP_COST_MIN_COVERAGE in README (X5/CL5)" "0" \
  "$(grep 'LARAVEL_LOOP_COST_MIN_COVERAGE' "$README_MD" | grep -cE '[0-9]')"

decisions_superseded_check() {
  local bad=0 dec="$ROOT/docs/loop/decisions.md"
  grep -qi 'upstream of this plugin' "$dec" && bad=1
  grep -qF '**4%**' "$dec" || bad=1
  grep -qF 'Rejected as a **spend control**: only invocations run in the **foreground** return a payload' "$dec" || bad=1
  echo $bad
}
expect "docs: decisions.md no longer claims the figure is upstream of this plugin, and the 4%-coverage rejection stands verbatim (X6)" \
  "0" "$(decisions_superseded_check)"

# S10 (spec.md X5, RC2, RC6, CL3) -- README documents the transcription entry
# point: a recovered figure is model-transcribed rather than host-observed,
# the CLI that writes one and its two arguments, and that recovery narrows
# the gap rather than closing it. Four cases, one per documentation claim.
readme_recovered_transcribed_check() {
  local bad=0 readme="$README_MD"
  grep -qi 'model-transcribed' "$readme" || bad=1
  grep -qi 'not host-observed' "$readme" || bad=1
  echo $bad
}
expect "docs: README states a recovered figure is model-transcribed, not host-observed (X5/RC2)" \
  "0" "$(readme_recovered_transcribed_check)"

readme_recovery_cli_check() {
  local bad=0 readme="$README_MD"
  grep -q 'scripts/record-recovered-cost\.sh' "$readme" || bad=1
  grep -q -- '--invocation-id' "$readme" || bad=1
  grep -q -- '--total-tokens' "$readme" || bad=1
  echo $bad
}
expect "docs: README names scripts/record-recovered-cost.sh and its two arguments (X5)" \
  "0" "$(readme_recovery_cli_check)"

# (negative) -- CL3's residue wording: recovery narrows the gap for
# invocations somebody transcribed, and for no others. README must never
# claim the gap is closed.
readme_recovery_not_closed_check() {
  local bad=0 readme="$README_MD"
  grep -qi 'narrows the gap' "$readme" || bad=1
  grep -qi 'for no others' "$readme" || bad=1
  grep -qiE 'closes the gap|gap is closed|gap no longer exists' "$readme" && bad=1
  echo $bad
}
expect "docs: README does not claim the background gap is closed -- S3's residue wording survives (CL3)" \
  "0" "$(readme_recovery_not_closed_check)"

# decisions.md carries the second-G1 entry while S6's spike entry and the
# 4%-coverage rejection stand verbatim -- fingerprints unique to each.
decisions_second_g1_check() {
  local bad=0 dec="$ROOT/docs/loop/decisions.md"
  grep -qi 'Second G1: land model-transcribed recovery' "$dec" || bad=1
  grep -qi 'Hold S11' "$dec" || bad=1
  grep -qi 'transcript scraping' "$dec" || bad=1
  grep -qi 'fuzzy selector' "$dec" || bad=1
  grep -qF 'no hook of any of the eight registered types fired a second time' "$dec" || bad=1
  grep -qF '**4%**' "$dec" || bad=1
  echo $bad
}
expect "docs: decisions.md carries the second-G1 entry, and S6's spike entry plus the 4%-coverage rejection stand untouched (X6)" \
  "0" "$(decisions_second_g1_check)"

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
    if s.startswith(".") or not os.path.isdir(os.path.join(root, "skills", s)):
        continue
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
    if s.startswith(".") or not os.path.isdir(os.path.join(root, "skills", s)):
        continue
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

# ---------------------------------------------------------------------------
echo
echo "warn-full-suite.sh (full-suite guard, R4.4)"

suite_json() { # $1 agent_type ("" for none/main-thread) $2 command
  python3 - "$1" "$2" <<'PY'
import json, sys
agent, command = sys.argv[1:3]
payload = {"tool_input": {"command": command}}
if agent:
    payload["agent_type"] = agent
print(json.dumps(payload))
PY
}

# One invocation per case, not two: sets FS_RC (exit code) and FS_OUT
# (stderr) together from a single run, then both are read as plain
# variables. An earlier version invoked the script twice per case --
# once merging stdout+stderr to /dev/null for the exit code, once more
# with stdout/stderr swapped for the stderr text -- with the swapped
# capture itself wrapped in an extra `warned()` helper's own command
# substitution. That extra layer of nested command substitution around
# the fd swap intermittently lost the captured stderr under bash 3.2
# (macOS's stock /bin/bash: the script provably still wrote its warning
# every time -- confirmed by instrumenting it directly -- but the
# doubly-nested subshell occasionally failed to relay it up to the
# caller), producing a ~3-10% flake rate reproduced in a tight local
# loop with nothing else running on the box, i.e. a real bash/fd race,
# not a concurrency artifact of this session's worktrees. A single
# invocation, captured once, removes the extra nesting level and the
# double invocation; 1000 consecutive clean runs found no recurrence.
capture() { # $1 json -> sets FS_RC, FS_OUT
  FS_OUT="$(printf '%s' "$1" | bash "$SCRIPTS/warn-full-suite.sh" 2>&1 1>/dev/null)"
  FS_RC=$?
}
warned_from_out() { # $1 stderr text (already captured, no invocation) -> "warn" or "silent"
  printf '%s' "$1" | grep -qi 'warn' && echo warn || echo silent
}

# -- (a) unfiltered `php artisan test` from loop-build warns AND exits 0 --
# exit code and stderr asserted as separate cases (FS1), from one capture.
FS_A="$(suite_json loop-build "php artisan test")"
capture "$FS_A"; FS_A_OUT="$FS_OUT"
expect "FS1: unfiltered 'php artisan test' from loop-build exits 0" "0" "$FS_RC"
expect "FS1: unfiltered 'php artisan test' from loop-build warns on stderr" "warn" "$(warned_from_out "$FS_A_OUT")"

# -- (b) Sail-prefixed form warns too (FS4) --
FS_B="$(suite_json loop-build "./vendor/bin/sail artisan test")"
capture "$FS_B"
expect "FS4: unfiltered sail-prefixed 'artisan test' exits 0" "0" "$FS_RC"
expect "FS4: unfiltered sail-prefixed 'artisan test' warns" "warn" "$(warned_from_out "$FS_OUT")"

# -- (c) a filter, or a path/file argument, means filtered: never warns (FS4) --
FS_C1="$(suite_json loop-build "php artisan test --compact --filter=InvoiceTest")"
capture "$FS_C1"
expect "FS4: filtered 'php artisan test --filter=' does not warn" "silent" "$(warned_from_out "$FS_OUT")"
expect "FS4: filtered 'php artisan test --filter=' exits 0" "0" "$FS_RC"

FS_C2="$(suite_json loop-build "vendor/bin/pest tests/Feature/InvoiceTest.php")"
capture "$FS_C2"
expect "FS4: 'vendor/bin/pest' with a path argument does not warn" "silent" "$(warned_from_out "$FS_OUT")"
expect "FS4: 'vendor/bin/pest' with a path argument exits 0" "0" "$FS_RC"

# -- (d) never warns on loop-verify or the main thread (FS2) -- two cases --
FS_D1="$(suite_json loop-verify "php artisan test")"
capture "$FS_D1"
expect "FS2: unfiltered run from loop-verify does not warn" "silent" "$(warned_from_out "$FS_OUT")"
expect "FS2: unfiltered run from loop-verify exits 0" "0" "$FS_RC"

FS_D2="$(suite_json "" "php artisan test")"
capture "$FS_D2"
expect "FS2: unfiltered run with no agent_type (main thread) does not warn" "silent" "$(warned_from_out "$FS_OUT")"
expect "FS2: unfiltered run with no agent_type exits 0" "0" "$FS_RC"

# -- (e) escape hatch silences it; the warning names the variable (FS3) --
LARAVEL_LOOP_ALLOW_FULL_SUITE=1 capture "$FS_A"
expect "FS3: LARAVEL_LOOP_ALLOW_FULL_SUITE=1 silences the warning" "silent" "$(warned_from_out "$FS_OUT")"
expect "FS3: LARAVEL_LOOP_ALLOW_FULL_SUITE=1 still exits 0" "0" "$FS_RC"
expect "FS3: the warning names LARAVEL_LOOP_ALLOW_FULL_SUITE" "found" \
  "$(printf '%s' "$FS_A_OUT" | grep -q 'LARAVEL_LOOP_ALLOW_FULL_SUITE' && echo found || echo missing)"

# -- (f) false positives never warn (FS5) -- asserted per command --
FS_F1="$(suite_json loop-build "ls tests/")"
capture "$FS_F1"
expect "FS5: 'ls tests/' from loop-build does not warn" "silent" "$(warned_from_out "$FS_OUT")"
expect "FS5: 'ls tests/' from loop-build exits 0" "0" "$FS_RC"

FS_F2="$(suite_json loop-build "grep -r foo tests/")"
capture "$FS_F2"
expect "FS5: 'grep -r foo tests/' from loop-build does not warn" "silent" "$(warned_from_out "$FS_OUT")"
expect "FS5: 'grep -r foo tests/' from loop-build exits 0" "0" "$FS_RC"

FS_F3="$(suite_json loop-build "git add tests/InvoiceTest.php")"
capture "$FS_F3"
expect "FS5: 'git add tests/InvoiceTest.php' from loop-build does not warn" "silent" "$(warned_from_out "$FS_OUT")"
expect "FS5: 'git add tests/InvoiceTest.php' from loop-build exits 0" "0" "$FS_RC"

# -- (g) exit 0 on every degenerate input, asserted individually (FS6) --
capture '{"agent_type":"loop-build","tool_input": not valid json'
expect "FS6: malformed payload exits 0" "0" "$FS_RC"
capture ''
expect "FS6: empty payload exits 0" "0" "$FS_RC"

FS_NOPARSER_BIN="$(mktemp -d)"
for b in cat grep tr bash; do
  p="$(command -v "$b" 2>/dev/null)"
  [ -n "$p" ] && ln -s "$p" "$FS_NOPARSER_BIN/$b"
done
FS_NOPARSER_JSON="$(suite_json loop-build "php artisan test")"
FS_NOPARSER_EXIT="$(printf '%s' "$FS_NOPARSER_JSON" | PATH="$FS_NOPARSER_BIN" bash "$SCRIPTS/warn-full-suite.sh" >/dev/null 2>&1; echo $?)"
expect "FS6: PATH stripped of jq+python3 exits 0" "0" "$FS_NOPARSER_EXIT"
rm -rf "$FS_NOPARSER_BIN"

# -- (h) new registration doesn't disturb the structure check (X5), and the
# script is not registered anywhere that could fire mid-invocation.
expect "FS: warn-full-suite.sh is registered on PreToolUse/Bash, not elsewhere" "1" \
  "$(python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
h = json.load(open(os.path.join(root, "hooks", "hooks.json")))["hooks"]
count = 0
for event, entries in h.items():
    for e in entries:
        for hk in e["hooks"]:
            if hk["command"].endswith("warn-full-suite.sh"):
                count += 1
                assert event == "PreToolUse" and e["matcher"] == "Bash", "wrong event/matcher"
print(count)
PY
)"

# ---------------------------------------------------------------------------
echo
echo "cost in log.md (scripts/write-cost-log-section.sh, S7)"

# cost-log-section-parse-error-on-macos-ci S4 -- writelog()/writelog_exit()
# used to discard stderr entirely (>/dev/null 2>&1), which is what threw
# away the only evidence a degraded run left behind before any assertion
# could read it. One real invocation, one place stderr and the exit status
# land (WRITELOG_LAST_STDERR/WRITELOG_LAST_EXIT); every existing call site's
# own return value is unchanged -- writelog_exit still echoes the exit
# code, writelog_stderr still prints the stderr text -- so no existing
# case's expected value moves.
writelog_run() { # $1 CLAUDE_PROJECT_DIR $2 slug
  WRITELOG_LAST_STDERR="$(CLAUDE_PROJECT_DIR="$1" bash "$SCRIPTS/write-cost-log-section.sh" "$2" 2>&1 1>/dev/null)"
  WRITELOG_LAST_EXIT=$?
}
writelog() { # $1 CLAUDE_PROJECT_DIR $2 slug
  writelog_run "$1" "$2"
}
writelog_exit() { # $1 CLAUDE_PROJECT_DIR $2 slug
  writelog_run "$1" "$2"
  echo "$WRITELOG_LAST_EXIT"
}
writelog_stderr() { # $1 CLAUDE_PROJECT_DIR $2 slug
  writelog_run "$1" "$2"
  printf '%s' "$WRITELOG_LAST_STDERR"
}

# Fixture: a log.md shaped like a real one -- pre-existing headings plus a
# seeded '## Budget events' block (S6's heading) and a trailing section
# after it -- alongside a mixed ledger (one priced spec invocation marked
# rework, one unpriced build invocation) under the same slug.
LOGDIR="$(mktemp -d)"
mkdir -p "$LOGDIR/.claude" "$LOGDIR/docs/loop/cost-log-fixture"
LOGFILE="$LOGDIR/docs/loop/cost-log-fixture/log.md"
{
  printf '%s\n' '# Log — cost-log-fixture'
  printf '\n'
  printf '%s\n' '## G0 — Spec'
  printf '%s\n' 'Some spec notes.'
  printf '\n'
  printf '%s\n' '## G1 — Slice'
  printf '%s\n' 'Some slice notes.'
  printf '\n'
  printf '%s\n' '## Budget events'
  printf '%s\n' '- warn crossed at 100000 tokens (threshold LARAVEL_LOOP_BUDGET_WARN=100000)'
  printf '\n'
  printf '%s\n' '## Conventions / decisions carried forward'
  printf '%s\n' 'Nothing.'
} > "$LOGFILE"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"a1","slug":"cost-log-fixture","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"a1","slug":"cost-log-fixture","phase":"spec","agent":"loop-spec","status":"completed","total_tokens":60787,"phase_detail":"rework","refine_passes":1}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"a2","slug":"cost-log-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"a2","slug":"cost-log-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
} > "$LOGDIR/.claude/loop-cost.jsonl"

expect "(a) write-cost-log-section.sh exits 0 on the mixed fixture" "0" "$(writelog_exit "$LOGDIR" cost-log-fixture)"
writelog "$LOGDIR" cost-log-fixture
LOG_OUT1="$(cat "$LOGFILE")"
S4_RUN1_STDERR="$WRITELOG_LAST_STDERR"
S4_RUN1_EXIT="$WRITELOG_LAST_EXIT"

expect "(a) a '## Cost' heading is written" "1" "$(grep -cx '## Cost' "$LOGFILE")"
expect "(a) the section carries the coverage sentence (DL1, DL2, CV1)" "yes" \
  "$(printf '%s\n' "$LOG_OUT1" | grep -q 'unpriced, not counted' && echo yes || echo no)"
expect "(a) the priced-subset total is labelled partial, with the unpriced count adjacent (DL1)" "yes" \
  "$(printf '%s\n' "$LOG_OUT1" | grep -q '60787 (priced subset only, partial -- 1 unpriced' && echo yes || echo no)"
expect "(a) the rework figure carries its count (DL3)" "yes" \
  "$(printf '%s\n' "$LOG_OUT1" | grep -q 'count: 1 of 2 invocation(s) marked rework' && echo yes || echo no)"
expect "(a) the rework figure carries D3's definition alongside it, not just the count (DL3)" "yes" \
  "$(printf '%s\n' "$LOG_OUT1" | grep -qi 'not the cost of retrying' && echo yes || echo no)"

# (b) DL4 -- re-running the close step replaces the section rather than
# appending a second one, and disturbs no other byte -- '## Budget events'
# and every pre-existing heading included, asserted with diff.
expect "(b) exactly one '## Cost' heading after the first run" "1" "$(grep -cx '## Cost' "$LOGFILE")"
writelog "$LOGDIR" cost-log-fixture
LOG_OUT2="$(cat "$LOGFILE")"
S4_RUN2_STDERR="$WRITELOG_LAST_STDERR"
S4_RUN2_EXIT="$WRITELOG_LAST_EXIT"
expect "(b) exactly one '## Cost' heading after a second run (DL4)" "1" "$(grep -cx '## Cost' "$LOGFILE")"

# cost-log-section-parse-error-on-macos-ci S4 (PF5): when either of case
# (b)'s own comparisons below fails, print the evidence a job log would
# need to diagnose it -- each run's exit status, its own stderr (S4's
# writelog_run capture, no longer discarded), and the body it actually
# wrote -- rather than only the byte-diff this case already produced.
# Printed ONLY on failure (PF5's own boundary); a green run gains nothing
# here beyond OQ6's one line at suite start.
s4_case_b_evidence() {
  printf 'CASE (b) EVIDENCE -- run 1: exit=%s stderr=%s\n' "$S4_RUN1_EXIT" "${S4_RUN1_STDERR:-<empty>}"
  printf 'CASE (b) EVIDENCE -- run 1 body:\n%s\n' "$LOG_OUT1"
  printf 'CASE (b) EVIDENCE -- run 2: exit=%s stderr=%s\n' "$S4_RUN2_EXIT" "${S4_RUN2_STDERR:-<empty>}"
  printf 'CASE (b) EVIDENCE -- run 2 body:\n%s\n' "$LOG_OUT2"
}

# (S4-1) OQ4/PF9: case (b) is STRENGTHENED, not replaced -- it keeps every
# existing assertion (the byte-identity diff below stays) and GAINS a
# direct assertion of run 2's OWN body, so "run 2 degraded" is detectable
# as itself and not only as a diff against run 1.
S4_RUN2_OK="$(printf '%s' "$LOG_OUT2" | grep -q 'unpriced, not counted' && echo yes || echo no)"
S4_RUN2_PARTIAL="$(printf '%s' "$LOG_OUT2" | grep -q '60787 (priced subset only, partial -- 1 unpriced' && echo yes || echo no)"
S4_RUN2_REWORK="$(printf '%s' "$LOG_OUT2" | grep -q 'count: 1 of 2 invocation(s) marked rework' && echo yes || echo no)"
if [ "$S4_RUN2_OK $S4_RUN2_PARTIAL $S4_RUN2_REWORK" != "yes yes yes" ]; then
  s4_case_b_evidence
fi
expect "(S4-1) case (b) strengthened: run 2's own body carries the coverage sentence, the partial total, and the rework count directly (OQ4, PF9)" \
  "yes yes yes" "$S4_RUN2_OK $S4_RUN2_PARTIAL $S4_RUN2_REWORK"

S4_DIFF_B="$(diff <(printf '%s' "$LOG_OUT1") <(printf '%s' "$LOG_OUT2"))"
if [ -n "$S4_DIFF_B" ]; then
  s4_case_b_evidence
fi
expect "(b) the file is byte-identical across the second run (DL4, CV7)" "" "$S4_DIFF_B"
expect "(b) '## Budget events' and every pre-existing heading survive untouched (DL4)" "yes" \
  "$(printf '%s\n' "$LOG_OUT2" | grep -qx '## Budget events' \
     && printf '%s\n' "$LOG_OUT2" | grep -q 'warn crossed at 100000' \
     && printf '%s\n' "$LOG_OUT2" | grep -qx '## G0 — Spec' \
     && printf '%s\n' "$LOG_OUT2" | grep -qx '## G1 — Slice' \
     && printf '%s\n' "$LOG_OUT2" | grep -qx '## Conventions / decisions carried forward' \
     && echo yes || echo no)"

# (c) a ledger with no record for the slug: the section is written and says
# so; never omitted, never a zeroed table (DL5).
NOSLUGDIR="$(mktemp -d)"
mkdir -p "$NOSLUGDIR/.claude" "$NOSLUGDIR/docs/loop/other-slug"
NOSLUGLOG="$NOSLUGDIR/docs/loop/other-slug/log.md"
printf '# Log — other-slug\n\n## G0 — Spec\nnotes\n' > "$NOSLUGLOG"
cp "$LOGDIR/.claude/loop-cost.jsonl" "$NOSLUGDIR/.claude/loop-cost.jsonl"
expect "(c) unrecorded slug: exits 0" "0" "$(writelog_exit "$NOSLUGDIR" other-slug)"
writelog "$NOSLUGDIR" other-slug
NOSLUG_OUT="$(cat "$NOSLUGLOG")"
expect "(c) unrecorded slug: '## Cost' section is written, not omitted (DL5)" "yes" \
  "$(printf '%s\n' "$NOSLUG_OUT" | grep -qx '## Cost' && echo yes || echo no)"
expect "(c) unrecorded slug: says so plainly" "yes" \
  "$(printf '%s\n' "$NOSLUG_OUT" | grep -qi 'No records for this unit' && echo yes || echo no)"
expect "(c) unrecorded slug: no zeroed token table" "no" \
  "$(printf '%s\n' "$NOSLUG_OUT" | grep -qiE 'tokens?:[[:space:]]*0\b' && echo yes || echo no)"

# (d) DL7/H1 -- the only changed path under docs/loop/ is that unit's
# log.md, and no ledger content appears anywhere beneath docs/loop/.
DL7DIR="$(mktemp -d)"
mkdir -p "$DL7DIR/.claude" "$DL7DIR/docs/loop/dl7-fixture" "$DL7DIR/docs/loop/untouched-unit"
printf '# Log — dl7-fixture\n\n## G0 — Spec\nnotes\n' > "$DL7DIR/docs/loop/dl7-fixture/log.md"
printf '# Log — untouched-unit\n\n## G0 — Spec\nnotes\n' > "$DL7DIR/docs/loop/untouched-unit/log.md"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"dl7-unique-token-zzz","slug":"dl7-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"dl7-unique-token-zzz","slug":"dl7-fixture","phase":"build","agent":"loop-build","status":"completed","total_tokens":777}'
} > "$DL7DIR/.claude/loop-cost.jsonl"
DL7_BEFORE="$(find "$DL7DIR/docs/loop" -type f | sort | while IFS= read -r f; do cksum "$f"; done)"
writelog "$DL7DIR" dl7-fixture
DL7_AFTER="$(find "$DL7DIR/docs/loop" -type f | sort | while IFS= read -r f; do cksum "$f"; done)"
expect "(d) untouched-unit's log.md is byte-identical (only the target unit's log.md changed)" "" \
  "$(diff <(printf '%s\n' "$DL7_BEFORE" | grep untouched-unit) <(printf '%s\n' "$DL7_AFTER" | grep untouched-unit))"
expect "(d) no ledger content (invocation_id) appears anywhere under docs/loop/ (H1)" "no" \
  "$(grep -rl 'dl7-unique-token-zzz' "$DL7DIR/docs/loop" >/dev/null 2>&1 && echo yes || echo no)"
expect "(d) the file set under docs/loop/ is unchanged -- nothing added, nothing removed" "yes" \
  "$(diff <(printf '%s\n' "$DL7_BEFORE" | awk '{print $NF}') <(printf '%s\n' "$DL7_AFTER" | awk '{print $NF}') >/dev/null 2>&1 && echo yes || echo no)"
rm -rf "$DL7DIR"

# (e) log.md absent: exit 0, nothing written, a message saying why -- the
# close step writes log.md first; this script never invents one.
ABSENTLOGDIR="$(mktemp -d)"
mkdir -p "$ABSENTLOGDIR/.claude" "$ABSENTLOGDIR/docs/loop"
cp "$LOGDIR/.claude/loop-cost.jsonl" "$ABSENTLOGDIR/.claude/loop-cost.jsonl"
expect "(e) log.md absent: exits 0" "0" "$(writelog_exit "$ABSENTLOGDIR" no-log-yet)"
ABSENT_ERR="$(writelog_stderr "$ABSENTLOGDIR" no-log-yet)"
expect "(e) log.md absent: says why, on stderr" "yes" \
  "$(printf '%s' "$ABSENT_ERR" | grep -qi 'No log.md found' && echo yes || echo no)"
expect "(e) log.md absent: nothing written -- no path created for that unit" "no" \
  "$([ -e "$ABSENTLOGDIR/docs/loop/no-log-yet" ] && echo yes || echo no)"
rm -rf "$ABSENTLOGDIR"

# (f) BG6 -- no reassurance token anywhere in this section, across every
# fixture's output above.
expect "(f) no 'within budget'/'under budget'/checkmark anywhere in the Cost section (BG6)" "1" \
  "$(printf '%s\n%s\n%s\n' "$LOG_OUT1" "$LOG_OUT2" "$NOSLUG_OUT" | grep -iE 'within budget|under budget|✓' >/dev/null 2>&1; echo $?)"

# ---------------------------------------------------------------------------
# cost-log-section-parse-error-on-macos-ci S1 -- neither of cost_scan's two
# grep sites (scripts/cost-ledger-lib.sh:976/:990) may depend on an external
# tool being resolvable (PF12-PF15). Reuses this section's own mixed
# cost-log-fixture ($LOGDIR/$LOGFILE, its ledger still on disk) rather than
# building a new one, per the slice's own instruction.
GREP_ABSENT_PATH="$(new_grep_absent_path)"

# (S1-1) fixture self-check: new_grep_absent_path resolves everything
# cost_scan's degraded-and-ok paths need -- bash, awk, mktemp, mv, tr (the
# out-of-bounds dependency at :310 that cost_coverage_sentence needs for an
# ok body) and a parser -- and does NOT resolve grep. A PATH fixture that
# silently resolved grep would make S1-2..S1-5 pass for the wrong reason.
# Each check runs in its own subshell/process (`bash -c`) rather than as a
# builtin in this long-lived harness shell: this shell has already resolved
# and hashed "grep" hundreds of times over, and bash's command hash table
# is consulted ahead of a merely-temporary PATH override on `command -v`,
# so checking in-process here would report a false "yes" for exactly the
# tool this fixture must prove absent -- a fresh process starts unhashed,
# which also matches how cost_scan actually runs (a freshly exec'd bash).
s1_resolves() { # $1 PATH-dir $2 tool -> "yes"/"no", asked of a clean process
  PATH="$1" bash -c 'command -v "$0" >/dev/null 2>&1 && echo yes || echo no' "$2"
}
expect "(S1-1) new_grep_absent_path resolves bash/awk/mktemp/mv/tr/a-parser and does NOT resolve grep" \
  "bash yes, awk yes, mktemp yes, mv yes, tr yes, parser yes, grep no" \
  "bash $(s1_resolves "$GREP_ABSENT_PATH" bash), awk $(s1_resolves "$GREP_ABSENT_PATH" awk), mktemp $(s1_resolves "$GREP_ABSENT_PATH" mktemp), mv $(s1_resolves "$GREP_ABSENT_PATH" mv), tr $(s1_resolves "$GREP_ABSENT_PATH" tr), parser $(PATH="$GREP_ABSENT_PATH" bash -c 'command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1' && echo yes || echo no), grep $(s1_resolves "$GREP_ABSENT_PATH" grep)"

PATH="$GREP_ABSENT_PATH" writelog "$LOGDIR" cost-log-fixture
GREPLESS_OUT="$(cat "$LOGFILE")"

# (S1-2) PF14's RED-BEFORE-GREEN (reproduced separately against the
# pre-change library and recorded in this slice's return, not shipped as a
# red case): under a PATH that resolves the parser but not grep, the
# cost-log-fixture writes the SAME ok body it writes with grep on PATH --
# the coverage sentence, the priced-subset partial total, and the rework
# count -- and never the parse-error sentence. [PF12, PF14]
expect "(S1-2) grep-less PATH: cost-log-fixture still writes the ok body (coverage, partial total, rework count), never the parse-error sentence" \
  "yes yes yes no" \
  "$(printf '%s' "$GREPLESS_OUT" | grep -q 'unpriced, not counted' && echo yes || echo no) $(printf '%s' "$GREPLESS_OUT" | grep -q '60787 (priced subset only, partial -- 1 unpriced' && echo yes || echo no) $(printf '%s' "$GREPLESS_OUT" | grep -q 'count: 1 of 2 invocation(s) marked rework' && echo yes || echo no) $(printf '%s' "$GREPLESS_OUT" | grep -qi 'parse error' && echo yes || echo no)"

# (S1-3) PF13's DISCRIMINATOR (also reproduced separately against a
# :976-only patch and recorded in this slice's return): the same run does
# NOT write the "No records for this unit" body, and the slug-filtered
# figure is present -- proving the slug the fixture actually holds was
# recognised as present rather than the failure having relocated from
# :976 to :990. [PF13]
expect "(S1-3) grep-less PATH: the present slug is never reported no-slug, and its own figure is present" \
  "no yes" \
  "$(printf '%s' "$GREPLESS_OUT" | grep -qi 'No records for this unit' && echo yes || echo no) $(printf '%s' "$GREPLESS_OUT" | grep -q '60787 (priced subset only, partial -- 1 unpriced' && echo yes || echo no)"

# (S1-4) the slug test still discriminates -- three tokens in one expect,
# all under the same grep-less PATH: a slug genuinely absent from the
# ledger; a slug that is a strict substring (prefix) of the present slug
# "cost-log-fixture"; and a slug containing a glob metacharacter. All three
# must be no-slug -- grep -qxF's exact-line, fixed-string semantics,
# preserved without grep. A hand-rolled match that widened this would make
# no-slug unreachable for a real caller, invisible to S1-2/S1-3 above. [PF13, DL5]
cost_scan_state_for_slug() { # $1 ledger $2 slug (PATH set by the caller)
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$1" "$2"
  printf '%s' "$COST_SCAN_STATE"
}
S1_SLUG_LEDGER="$LOGDIR/.claude/loop-cost.jsonl"
S1_ABSENT_STATE="$(PATH="$GREP_ABSENT_PATH" cost_scan_state_for_slug "$S1_SLUG_LEDGER" "not-a-real-slug")"
S1_SUBSTRING_STATE="$(PATH="$GREP_ABSENT_PATH" cost_scan_state_for_slug "$S1_SLUG_LEDGER" "cost-log-fix")"
S1_GLOB_STATE="$(PATH="$GREP_ABSENT_PATH" cost_scan_state_for_slug "$S1_SLUG_LEDGER" "cost-log-*")"
expect "(S1-4) grep-less PATH: an absent slug, a strict-substring slug, and a slug containing a glob metacharacter are ALL no-slug" \
  "no-slug no-slug no-slug" "$S1_ABSENT_STATE $S1_SUBSTRING_STATE $S1_GLOB_STATE"

# (S1-5) the marker test can still fail: a stub jq that exits non-zero with
# no output, on a PATH shaped the same way (grep also unresolvable), still
# yields scan-error -- the section is still written and the write still
# exits 0. Proves :976's replacement has not become unconditionally true. [PF12, PF8/DL5]
S1_STUBDIR="$(mktemp -d)"
printf '#!/usr/bin/env bash\nexit 7\n' > "$S1_STUBDIR/jq"
chmod +x "$S1_STUBDIR/jq"
S1_STUB_PATH="$S1_STUBDIR:$GREP_ABSENT_PATH"
PATH="$S1_STUB_PATH" writelog "$LOGDIR" cost-log-fixture
S1_STUBBED_OUT="$(cat "$LOGFILE")"
S1_STUBBED_EXIT="$(PATH="$S1_STUB_PATH" writelog_exit "$LOGDIR" cost-log-fixture)"
expect "(S1-5) a broken parser under a grep-less PATH still yields the parse-error body, and the write still exits 0" \
  "yes 0" \
  "$(printf '%s' "$S1_STUBBED_OUT" | grep -qi 'Could not read the cost ledger (parse error)' && echo yes || echo no) $S1_STUBBED_EXIT"
rm -rf "$S1_STUBDIR" "$GREP_ABSENT_PATH"

# ---------------------------------------------------------------------------
# cost-log-section-parse-error-on-macos-ci S2 -- a degraded cost_scan now
# PUBLISHES which parser ran, its exit status, a bounded capture of its own
# stderr, and one of three route values (PF1, PF2), instead of discarding
# all three. Reuses this section's own mixed cost-log-fixture ($LOGDIR,
# S1_SLUG_LEDGER) rather than building a new one. None of these re-assert
# S1's fix (S1 owns that).
cost_scan_fields_for_slug() { # $1 ledger $2 slug (PATH set by caller) ->
  # "STATE<US>PARSER<US>STATUS<US>ROUTE<US>STDERR" (US = \x1f, so a stderr
  # capture containing an ordinary space never misaligns the split below)
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$1" "$2"
  printf '%s\x1f%s\x1f%s\x1f%s\x1f%s' \
    "$COST_SCAN_STATE" "$COST_SCAN_PARSER" "$COST_SCAN_PARSER_STATUS" \
    "$COST_SCAN_ROUTE" "$COST_SCAN_PARSER_STDERR"
}

# (S2-1) fixture self-check: new_stub_parser_path() plants the STUB at the
# requested name (never the real binary -- both real jq and real python3 are
# excluded from this PATH's symlink pass, so there is no real one for the
# stub to compete with), and still resolves everything else cost_scan's
# degraded-and-ok paths need. A PATH fixture that silently resolved the real
# parser instead of the stub would make S2-2..S2-5 pass for the wrong
# reason. [OQ5's discipline]
S2_SELFCHECK_BODY='#!/usr/bin/env bash
exit 0'
S2_SELFCHECK_PATH="$(new_stub_parser_path jq "$S2_SELFCHECK_BODY")"
S2_JQ_RESOLVED="$(PATH="$S2_SELFCHECK_PATH" bash -c 'command -v jq' 2>/dev/null)"
expect "(S2-1) new_stub_parser_path resolves the STUB jq (not the real one), python3 stays absent, and bash/awk/mktemp/tr/grep still resolve" \
  "yes no bash yes, awk yes, mktemp yes, tr yes, grep yes" \
  "$([ "$S2_JQ_RESOLVED" = "$S2_SELFCHECK_PATH/jq" ] && echo yes || echo no) $(s1_resolves "$S2_SELFCHECK_PATH" python3) bash $(s1_resolves "$S2_SELFCHECK_PATH" bash), awk $(s1_resolves "$S2_SELFCHECK_PATH" awk), mktemp $(s1_resolves "$S2_SELFCHECK_PATH" mktemp), tr $(s1_resolves "$S2_SELFCHECK_PATH" tr), grep $(s1_resolves "$S2_SELFCHECK_PATH" grep)"
rm -rf "$S2_SELFCHECK_PATH"

# (S2-2) jq stub exits non-zero and writes to stderr -> PARSER=jq,
# STATUS=<that status>, ROUTE=parser-failed, and the stderr text is present
# in COST_SCAN_PARSER_STDERR. [PF1, PF2]
S2_C2_BODY='#!/usr/bin/env bash
printf "jq-stub-stderr-sentinel: unexpected token near line 4\n" >&2
exit 3'
S2_C2_PATH="$(new_stub_parser_path jq "$S2_C2_BODY")"
S2_C2_FIELDS="$(PATH="$S2_C2_PATH" cost_scan_fields_for_slug "$S1_SLUG_LEDGER" "")"
IFS=$'\x1f' read -r S2_C2_STATE S2_C2_PARSER S2_C2_STATUS S2_C2_ROUTE S2_C2_STDERR <<< "$S2_C2_FIELDS"
expect "(S2-2) jq stub exits 3 with stderr -> scan-error/jq/3/parser-failed, stderr captured" \
  "scan-error jq 3 parser-failed yes" \
  "$S2_C2_STATE $S2_C2_PARSER $S2_C2_STATUS $S2_C2_ROUTE $(printf '%s' "$S2_C2_STDERR" | grep -q 'jq-stub-stderr-sentinel' && echo yes || echo no)"
rm -rf "$S2_C2_PATH"

# (S2-3) jq absent (new_stub_parser_path excludes it unconditionally),
# python3 stub exits 0 with output lacking the marker -> PARSER=python3,
# STATUS=0, ROUTE=parser-output-unrecognised, captured stderr empty. This is
# the pairwise row proving parser identity is READ, not assumed to be jq.
# [PF1, PF2]
S2_C3_BODY='#!/usr/bin/env bash
printf "not-the-marker-anyone-is-looking-for\n"
exit 0'
S2_C3_PATH="$(new_stub_parser_path python3 "$S2_C3_BODY")"
S2_C3_FIELDS="$(PATH="$S2_C3_PATH" cost_scan_fields_for_slug "$S1_SLUG_LEDGER" "")"
IFS=$'\x1f' read -r S2_C3_STATE S2_C3_PARSER S2_C3_STATUS S2_C3_ROUTE S2_C3_STDERR <<< "$S2_C3_FIELDS"
expect "(S2-3) jq absent, python3 stub exits 0 with unrecognised output -> scan-error/python3/0/parser-output-unrecognised, stderr empty" \
  "scan-error python3 0 parser-output-unrecognised " \
  "$S2_C3_STATE $S2_C3_PARSER $S2_C3_STATUS $S2_C3_ROUTE $S2_C3_STDERR"
rm -rf "$S2_C3_PATH"

# (S2-4) jq stub produces nothing at all on EITHER stream (killed by a
# signal before it can print anything) -> ROUTE=parser-no-output, with the
# signal's own (non-zero) status still recorded -- distinguishable from
# (S2-2)'s parser-failed, whose stderr is non-empty. [PF2]
S2_C4_BODY='#!/usr/bin/env bash
kill -KILL $$'
S2_C4_PATH="$(new_stub_parser_path jq "$S2_C4_BODY")"
S2_C4_FIELDS="$(PATH="$S2_C4_PATH" cost_scan_fields_for_slug "$S1_SLUG_LEDGER" "")"
IFS=$'\x1f' read -r S2_C4_STATE S2_C4_PARSER S2_C4_STATUS S2_C4_ROUTE S2_C4_STDERR <<< "$S2_C4_FIELDS"
expect "(S2-4) jq stub killed by a signal, nothing on either stream -> scan-error/jq/parser-no-output, a non-zero status still recorded, stderr empty" \
  "scan-error jq parser-no-output yes " \
  "$S2_C4_STATE $S2_C4_PARSER $S2_C4_ROUTE $([ "$S2_C4_STATUS" != "0" ] && [ -n "$S2_C4_STATUS" ] && echo yes || echo no) $S2_C4_STDERR"
rm -rf "$S2_C4_PATH"

# (S2-5) boundary, the bound: a stub writing far more than 200 characters to
# stderr -> COST_SCAN_PARSER_STDERR is ONE LINE (newlines collapsed to
# spaces) of AT MOST 200 characters, and it is the FIRST 200 -- a truncation
# that kept the tail would discard the parser's actual error and would show
# a "chunk59" token here instead of "chunk00". [PF1]
S2_C5_BODY='#!/usr/bin/env bash
i=0
while [ $i -lt 60 ]; do
  printf "chunk%02d-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n" "$i" >&2
  i=$((i + 1))
done
exit 9'
S2_C5_PATH="$(new_stub_parser_path jq "$S2_C5_BODY")"
S2_C5_FIELDS="$(PATH="$S2_C5_PATH" cost_scan_fields_for_slug "$S1_SLUG_LEDGER" "")"
IFS=$'\x1f' read -r S2_C5_STATE S2_C5_PARSER S2_C5_STATUS S2_C5_ROUTE S2_C5_STDERR <<< "$S2_C5_FIELDS"
S2_C5_LEN="${#S2_C5_STDERR}"
case "$S2_C5_STDERR" in *$'\n'*) S2_C5_HAS_NL="yes" ;; *) S2_C5_HAS_NL="no" ;; esac
case "$S2_C5_STDERR" in chunk00-*) S2_C5_STARTS_FIRST="yes" ;; *) S2_C5_STARTS_FIRST="no" ;; esac
case "$S2_C5_STDERR" in *chunk59*) S2_C5_HAS_LAST="yes" ;; *) S2_C5_HAS_LAST="no" ;; esac
expect "(S2-5) state/parser/status/route still reported correctly, and stderr longer than the bound is one line, at most 200 chars, holding the FIRST chunk and never the last" \
  "scan-error jq 9 parser-failed 200 no yes no" \
  "$S2_C5_STATE $S2_C5_PARSER $S2_C5_STATUS $S2_C5_ROUTE $S2_C5_LEN $S2_C5_HAS_NL $S2_C5_STARTS_FIRST $S2_C5_HAS_LAST"
rm -rf "$S2_C5_PATH"

# (S2-6) boundary, the ok path: with the real parser on PATH, an ok scan of
# the cost-log-fixture publishes all four new variables as EMPTY (PF10), and
# /cost's own output for that unit is byte-identical to the pre-change
# library's -- captured via `git show`, not asserted from memory, per this
# repository's standing discipline. [PF10, PF8]
S2_OK_FIELDS="$(cost_scan_fields_for_slug "$S1_SLUG_LEDGER" "cost-log-fixture")"
IFS=$'\x1f' read -r S2_OK_STATE S2_OK_PARSER S2_OK_STATUS S2_OK_ROUTE S2_OK_STDERR <<< "$S2_OK_FIELDS"

S2_PARITY_DIR="$(mktemp -d)"
mkdir -p "$S2_PARITY_DIR/scripts"
git -C "$ROOT" show HEAD:scripts/cost-ledger-lib.sh > "$S2_PARITY_DIR/scripts/cost-ledger-lib.sh"
cp "$SCRIPTS/cost-report.sh" "$S2_PARITY_DIR/scripts/cost-report.sh"
S2_PRECHANGE_REPORT="$(CLAUDE_PROJECT_DIR="$LOGDIR" bash "$S2_PARITY_DIR/scripts/cost-report.sh" cost-log-fixture)"
S2_POSTCHANGE_REPORT="$(CLAUDE_PROJECT_DIR="$LOGDIR" bash "$SCRIPTS/cost-report.sh" cost-log-fixture)"
S2_REPORT_DIFF="$(diff <(printf '%s' "$S2_PRECHANGE_REPORT") <(printf '%s' "$S2_POSTCHANGE_REPORT"))"
expect "(S2-6) ok scan: all four new variables stay empty (PF10), and /cost's ok output is byte-identical to the pre-change library's for the same fixture (PF10, PF8)" \
  "ok    " "$S2_OK_STATE $S2_OK_PARSER $S2_OK_STATUS $S2_OK_ROUTE $S2_OK_STDERR$S2_REPORT_DIFF"
rm -rf "$S2_PARITY_DIR"

# ---------------------------------------------------------------------------
# cost-log-section-parse-error-on-macos-ci S3 -- both reader surfaces name
# the route (PF2), a degraded write says so on stderr (PF3), and the `*)`
# arm stops borrowing scan-error's sentence. Reuses S2's
# new_stub_parser_path() and this section's own mixed cost-log-fixture.

# (S3-1) degraded body: the section names the parser (jq), its exit status
# and the route -- and never the stub's own stderr text (DL7/H1). [PF1, PF2, PF8]
S3_C1_BODY='#!/usr/bin/env bash
printf "s3-stub-stderr-sentinel-should-never-appear-in-log\n" >&2
exit 5'
S3_C1_PATH="$(new_stub_parser_path jq "$S3_C1_BODY")"
PATH="$S3_C1_PATH" writelog "$LOGDIR" cost-log-fixture
S3_C1_OUT="$(cat "$LOGFILE")"
expect "(S3-1) degraded body names the parser, its exit status and the route, never the stub's own stderr text" \
  "yes yes yes no" \
  "$(printf '%s' "$S3_C1_OUT" | grep -q 'Parser: jq, exit status 5' && echo yes || echo no) $(printf '%s' "$S3_C1_OUT" | grep -qi 'route: parser-failed' && echo yes || echo no) $(printf '%s' "$S3_C1_OUT" | grep -q 'Could not read the cost ledger (parse error)' && echo yes || echo no) $(printf '%s' "$S3_C1_OUT" | grep -q 's3-stub-stderr-sentinel' && echo yes || echo no)"

# (S3-2) PF3, degraded: writelog_stderr on that same run names the slug and
# the route, and the write still exits 0. [PF3]
S3_C2_ERR="$(PATH="$S3_C1_PATH" writelog_stderr "$LOGDIR" cost-log-fixture)"
S3_C2_EXIT="$(PATH="$S3_C1_PATH" writelog_exit "$LOGDIR" cost-log-fixture)"
expect "(S3-2) PF3 degraded: stderr names the slug and the route, exit still 0" \
  "yes yes 0" \
  "$(printf '%s' "$S3_C2_ERR" | grep -q 'cost-log-fixture' && echo yes || echo no) $(printf '%s' "$S3_C2_ERR" | grep -q 'parser-failed' && echo yes || echo no) $S3_C2_EXIT"
rm -rf "$S3_C1_PATH"

# (S3-3) PF3/PF10, ok: writelog_stderr is EMPTY, exit is 0, and the ok
# section is byte-identical to the pre-change script's rendering of the
# same fixture (git show, not asserted from memory). [PF3, PF10]
S3_PRECHANGE_DIR="$(mktemp -d)"
mkdir -p "$S3_PRECHANGE_DIR/scripts"
git -C "$ROOT" show HEAD:scripts/write-cost-log-section.sh > "$S3_PRECHANGE_DIR/scripts/write-cost-log-section.sh"
cp "$SCRIPTS/cost-ledger-lib.sh" "$S3_PRECHANGE_DIR/scripts/cost-ledger-lib.sh"
CLAUDE_PROJECT_DIR="$LOGDIR" bash "$S3_PRECHANGE_DIR/scripts/write-cost-log-section.sh" cost-log-fixture >/dev/null 2>&1
S3_PRECHANGE_OK="$(cat "$LOGFILE")"
rm -rf "$S3_PRECHANGE_DIR"
writelog "$LOGDIR" cost-log-fixture
S3_POSTCHANGE_OK="$(cat "$LOGFILE")"
S3_OK_ERR="$(writelog_stderr "$LOGDIR" cost-log-fixture)"
S3_OK_EXIT="$(writelog_exit "$LOGDIR" cost-log-fixture)"
expect "(S3-3) ok write: silent stderr, exit 0, section byte-identical to the pre-change script's rendering" \
  "yes 0 " \
  "$([ -z "$S3_OK_ERR" ] && echo yes || echo no) $S3_OK_EXIT $(diff <(printf '%s' "$S3_PRECHANGE_OK") <(printf '%s' "$S3_POSTCHANGE_OK"))"

# (S3-4) the `*)` arm: a stripped copy that still borrows scan-error's own
# sentence is caught by this check (proves it can fail), and the real
# file's `*)` arm calls a DIFFERENT body function -- read, not forced: no
# input can produce an unrecognised state while the library and this
# script agree. [PF2]
s3_arm_calls_scan_error() { # $1 file -> "yes" if the *) arm's body matches scan-error's arm verbatim
  local f="$1" scan_line arm_line
  scan_line="$(grep -E '^ *scan-error\)' "$f" | sed -E 's/^ *scan-error\) *//')"
  arm_line="$(grep -E '^ *\*\)' "$f" | sed -E 's/^ *\*\) *//')"
  [ -n "$scan_line" ] && [ "$scan_line" = "$arm_line" ] && echo yes || echo no
}
S3_STRIPPED="$(mktemp)"
sed 's/print_unrecognised_state_body ;;/print_scan_error_body ;;/' "$SCRIPTS/write-cost-log-section.sh" > "$S3_STRIPPED"
expect "(S3-4) stripped copy (still borrowing scan-error's sentence) is caught, and the real file's *) arm calls a DIFFERENT body function" \
  "yes no" "$(s3_arm_calls_scan_error "$S3_STRIPPED") $(s3_arm_calls_scan_error "$SCRIPTS/write-cost-log-section.sh")"
rm -f "$S3_STRIPPED"

# (S3-5) /cost's degraded read names the route, in the same clause shape,
# and its ok output for the fixture is byte-identical to the pre-change
# script's (git show, not asserted from memory). [PF2, PF10]
S3_C5_BODY='#!/usr/bin/env bash
printf "s3-cost-report-stub-stderr\n" >&2
exit 4'
S3_C5_PATH="$(new_stub_parser_path jq "$S3_C5_BODY")"
S3_C5_DEGRADED_OUT="$(CLAUDE_PROJECT_DIR="$LOGDIR" PATH="$S3_C5_PATH" bash "$SCRIPTS/cost-report.sh" cost-log-fixture)"
S3_PRECHANGE_REPORT_DIR="$(mktemp -d)"
mkdir -p "$S3_PRECHANGE_REPORT_DIR/scripts"
git -C "$ROOT" show HEAD:scripts/cost-report.sh > "$S3_PRECHANGE_REPORT_DIR/scripts/cost-report.sh"
cp "$SCRIPTS/cost-ledger-lib.sh" "$S3_PRECHANGE_REPORT_DIR/scripts/cost-ledger-lib.sh"
S3_PRECHANGE_REPORT_OK="$(CLAUDE_PROJECT_DIR="$LOGDIR" bash "$S3_PRECHANGE_REPORT_DIR/scripts/cost-report.sh" cost-log-fixture)"
S3_POSTCHANGE_REPORT_OK="$(CLAUDE_PROJECT_DIR="$LOGDIR" bash "$SCRIPTS/cost-report.sh" cost-log-fixture)"
rm -rf "$S3_C5_PATH" "$S3_PRECHANGE_REPORT_DIR"
expect "(S3-5) /cost's degraded read names the route, and its ok output for the fixture is byte-identical to the pre-change script's" \
  "yes " \
  "$(printf '%s' "$S3_C5_DEGRADED_OUT" | grep -q 'route: parser-failed' && echo yes || echo no) $(diff <(printf '%s' "$S3_PRECHANGE_REPORT_OK") <(printf '%s' "$S3_POSTCHANGE_REPORT_OK"))"

# ---------------------------------------------------------------------------
# cost-log-section-parse-error-on-macos-ci S4 -- the harness can now tell
# degraded-correctly from degraded-wrongly (PF4), and a forced degraded
# write's evidence answers PF6's three questions from the run's own output
# (PF5, PF6). Reuses S2's new_stub_parser_path() and cost_scan_fields_for_slug().

# (S4-2) PF4, degraded-correctly, unforced-route branch (OQ5): READ FIRST
# (scripts/cost-ledger-lib.sh's jq/python3 programs, both confirmed above)
# -- unrecognised lines are COUNTED (COST_N_SKIPPED), never failed on, so
# no portable ledger content makes both parsers exit non-zero. No
# input-unparseable route is forced here; the honest alternative is
# asserted instead: a ledger of nothing but unrecognised lines still reads
# ok, with a skipped count and no fabricated total, section still written,
# exit still 0.
s4_skipped_count() { # $1 ledger $2 slug (PATH set by caller)
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$1" "$2"
  printf '%s' "$COST_N_SKIPPED"
}
S4_GARBAGE_DIR="$(mktemp -d)"
mkdir -p "$S4_GARBAGE_DIR/.claude" "$S4_GARBAGE_DIR/docs/loop/s4-garbage"
printf '# Log — s4-garbage\n\n## G0 — Spec\nnotes\n' > "$S4_GARBAGE_DIR/docs/loop/s4-garbage/log.md"
{
  printf '%s\n' 'this is not json at all'
  printf '%s\n' '{"not":"a recognised shape"}'
  printf '%s\n' '{"event":"something_else","slug":"s4-garbage"}'
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"g1","slug":"s4-garbage","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"g1","slug":"s4-garbage","phase":"build","agent":"loop-build","status":"async_launched"}'
} > "$S4_GARBAGE_DIR/.claude/loop-cost.jsonl"
S4_GARBAGE_LEDGER="$S4_GARBAGE_DIR/.claude/loop-cost.jsonl"
S4_GARBAGE_FIELDS="$(cost_scan_fields_for_slug "$S4_GARBAGE_LEDGER" "s4-garbage")"
IFS=$'\x1f' read -r S4_G_STATE S4_G_PARSER S4_G_STATUS S4_G_ROUTE S4_G_STDERR <<< "$S4_GARBAGE_FIELDS"
S4_G_SKIPPED="$(s4_skipped_count "$S4_GARBAGE_LEDGER" "s4-garbage")"
S4_G_EXIT="$(writelog_exit "$S4_GARBAGE_DIR" s4-garbage)"
S4_G_SECTION="$(grep -cx '## Cost' "$S4_GARBAGE_DIR/docs/loop/s4-garbage/log.md")"
S4_G_NO_TOTAL="$(grep -q "nothing about this unit's token cost is observable" "$S4_GARBAGE_DIR/docs/loop/s4-garbage/log.md" && echo yes || echo no)"
expect "(S4-2) PF4/OQ5: three unrecognised lines are counted as skipped (not failed on), the recognised record still reads ok with the four route variables empty (PF10), no fabricated total, section still written, exit 0" \
  "ok     3 1 0 yes" \
  "$S4_G_STATE $S4_G_PARSER $S4_G_STATUS $S4_G_ROUTE $S4_G_STDERR $S4_G_SKIPPED $S4_G_SECTION $S4_G_EXIT $S4_G_NO_TOTAL"
rm -rf "$S4_GARBAGE_DIR"

# (S4-3) PF4, degraded-wrongly is detectable: over the valid mixed fixture,
# neither run's output contains the degraded sentence -- this is the case
# that would have caught the c32daf0 sighting as a degradation rather than
# as a bare byte-diff.
expect "(S4-3) PF4: over the valid mixed fixture, neither run's output contains the degraded sentence" \
  "no no" \
  "$(printf '%s' "$LOG_OUT1" | grep -qi 'parse error' && echo yes || echo no) $(printf '%s' "$LOG_OUT2" | grep -qi 'parse error' && echo yes || echo no)"

# (S4-4) PF5/PF6: for a forced degraded write, the harness's captured
# stderr TOGETHER WITH the run's own body (both now readable -- S4's
# writelog_run capture, S3's body sentence) answer all three of PF6's
# questions: which parser ran, what it returned, which route produced the
# state -- from the run's own output alone, no re-run and no machine access.
S4_EVID_BODY='#!/usr/bin/env bash
printf "s4-evidence-stub-stderr\n" >&2
exit 6'
S4_EVID_PATH="$(new_stub_parser_path jq "$S4_EVID_BODY")"
PATH="$S4_EVID_PATH" writelog "$LOGDIR" cost-log-fixture
S4_EVID_COMBINED="$WRITELOG_LAST_STDERR
$(cat "$LOGFILE")"
expect "(S4-4) PF5/PF6: captured stderr plus the run's own body together name the parser, its exit status, and the route" \
  "yes yes yes" \
  "$(printf '%s' "$S4_EVID_COMBINED" | grep -q 'Parser: jq' && echo yes || echo no) $(printf '%s' "$S4_EVID_COMBINED" | grep -q 'exit status 6' && echo yes || echo no) $(printf '%s' "$S4_EVID_COMBINED" | grep -q 'parser-failed' && echo yes || echo no)"
rm -rf "$S4_EVID_PATH"

# (S4-5) reading 1 / DL7-H1 under instrumentation: a stub parser whose
# stderr carries a unique token produces a degraded section, and that
# token is found NOWHERE under this fixture's docs/loop -- the case that
# stops a future instrumentation change quietly breaking DL7/H1.
S4_C5_BODY='#!/usr/bin/env bash
printf "s4-unique-ledger-content-token-9f8e7d\n" >&2
exit 8'
S4_C5_PATH="$(new_stub_parser_path jq "$S4_C5_BODY")"
PATH="$S4_C5_PATH" writelog "$LOGDIR" cost-log-fixture
S4_C5_SECTION="$(grep -cx '## Cost' "$LOGFILE")"
S4_C5_FOUND="$(grep -rl 's4-unique-ledger-content-token-9f8e7d' "$LOGDIR/docs/loop" 2>/dev/null | wc -l | tr -d ' ')"
expect "(S4-5) PF1/PF8: a stub's unique stderr token produces a degraded section but is found nowhere under docs/loop (DL7/H1)" \
  "1 0" "$S4_C5_SECTION $S4_C5_FOUND"
rm -rf "$S4_C5_PATH"

rm -rf "$LOGDIR" "$NOSLUGDIR"

# (g) commands/loop.md step 5 names the script -- prove-it-can-fail run
# against a stripped temp copy first (the same idiom S5/S6 use).
close_script_named_check() { # $1 file -> "0" present, "1" missing
  local f="$1"
  if grep -q 'write-cost-log-section.sh' "$f" && grep -q '## Cost' "$f"; then
    echo 0
  else
    echo 1
  fi
}
CLOSEDIR="$(mktemp -d)"
mkdir -p "$CLOSEDIR/commands"
grep -v -i -E 'write-cost-log-section|## Cost' "$LOOPMD" > "$CLOSEDIR/commands/loop.md"
expect "(g) stripped copy fails the check (proves the case can fail)" "1" \
  "$(close_script_named_check "$CLOSEDIR/commands/loop.md")"
rm -rf "$CLOSEDIR"
expect "(g) commands/loop.md step 5 (Close) names write-cost-log-section.sh" "0" \
  "$(close_script_named_check "$LOOPMD")"

# (h) S6's cases pass unmodified and its step 3/4 region is untouched by
# this slice's diff -- machine-checked above in the (retired-and-replaced)
# S6 boundary case; nothing further to assert here.

# (i) byte-identical section content on a re-run of the same ledger -- (b)
# already asserted the whole file is byte-identical; this isolates just the
# '## Cost' section's own bytes.
extract_cost_section() {
  awk '
    /^## Cost$/ { flag=1; print; next }
    flag && /^## / { exit }
    flag { print }
  ' "$1"
}
LOGDIR2="$(mktemp -d)"
mkdir -p "$LOGDIR2/.claude" "$LOGDIR2/docs/loop/cost-log-fixture2"
LOGFILE2="$LOGDIR2/docs/loop/cost-log-fixture2/log.md"
printf '# Log — cost-log-fixture2\n\n## G0 — Spec\nnotes\n' > "$LOGFILE2"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"c1","slug":"cost-log-fixture2","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"c1","slug":"cost-log-fixture2","phase":"build","agent":"loop-build","status":"completed","total_tokens":500}'
} > "$LOGDIR2/.claude/loop-cost.jsonl"
writelog "$LOGDIR2" cost-log-fixture2
SECTION_1="$(extract_cost_section "$LOGFILE2")"
writelog "$LOGDIR2" cost-log-fixture2
SECTION_2="$(extract_cost_section "$LOGFILE2")"
expect "(i) the '## Cost' section's own bytes are identical on a re-run of the same ledger (CV7)" "" \
  "$(diff <(printf '%s' "$SECTION_1") <(printf '%s' "$SECTION_2"))"
rm -rf "$LOGDIR2"

# -- executable bit + shellcheck (X1) --
expect "write-cost-log-section.sh is executable" "yes" \
  "$([ -x "$SCRIPTS/write-cost-log-section.sh" ] && echo yes || echo no)"

# ---------------------------------------------------------------------------
echo
echo "check-script-modes.sh (script-mode rule, S1 -- spec.md A2/A5/A7, ship-gate-blind-to-ci)"

CSM="$SCRIPTS/check-script-modes.sh"

# Fixture content, built with printf rather than a heredoc so the marker
# literal never appears as its own column-0 comment line inside this file --
# a column-0 occurrence here would make the harness classify itself as a
# library under the very rule it is testing (the slice's own anchor note).
csm_program_content()          { printf '#!/usr/bin/env bash\necho program\n'; }
csm_library_content()          { printf '#!/usr/bin/env bash\n# laravel-loop:sourced-library\necho library\n'; }
csm_indented_marker_content()  { printf '#!/usr/bin/env bash\n  # laravel-loop:sourced-library\necho indented\n'; }

# Builds a throwaway git repo containing exactly one scripts/*.sh or
# tests/*.sh file, committed at the requested mode. The mode is forced via
# `git update-index --chmod` after `add`, not left to core.fileMode picking
# up the filesystem bit, so the committed mode is exact regardless of host
# fileMode settings. $1 repo dir (already mktemp -d'd) $2 relative path
# $3 mode (100644|100755) $4 file content
csm_repo_with_file() {
  local dir="$1" relpath="$2" mode="$3" content="$4" chmodflag
  mkdir -p "$dir/$(dirname "$relpath")"
  printf '%s' "$content" > "$dir/$relpath"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email t@example.test
  git -C "$dir" config user.name test
  git -C "$dir" add "$relpath"
  [ "$mode" = "100755" ] && chmodflag="+x" || chmodflag="-x"
  git -C "$dir" update-index --chmod="$chmodflag" "$relpath"
  git -C "$dir" commit --quiet -m init
}

csm_run() { # $1 repo dir -> sets CSM_RC, CSM_OUT
  CSM_OUT="$(cd "$1" && bash "$CSM" 2>&1)"
  CSM_RC=$?
}

# names() -> "yes"/"no": did the checker's output name the given path?
csm_names() { printf '%s' "$CSM_OUT" | grep -qF "$1" && echo yes || echo no; }
# nz() -> "nonzero"/"zero": is CSM_RC non-zero?
csm_nz() { [ "$CSM_RC" -ne 0 ] && echo nonzero || echo zero; }

# -- 1: unmarked program at 100644 -> non-zero, names the path --
CSM1="$(mktemp -d)"
csm_repo_with_file "$CSM1" "scripts/csm-fixture-a.sh" "100644" "$(csm_program_content)"
csm_run "$CSM1"
expect "1: unmarked program at 100644 -> non-zero, names the path" "nonzero yes" \
  "$(csm_nz) $(csm_names scripts/csm-fixture-a.sh)"
rm -rf "$CSM1"

# -- 2: unmarked program at 100755 -> exit 0 --
CSM2="$(mktemp -d)"
csm_repo_with_file "$CSM2" "scripts/csm-fixture-b.sh" "100755" "$(csm_program_content)"
csm_run "$CSM2"
expect "2: unmarked program at 100755 exits 0" "0" "$CSM_RC"
rm -rf "$CSM2"

# -- 3: marked library at 100644 -> exit 0 (the exemption OQ1 chose) --
CSM3="$(mktemp -d)"
csm_repo_with_file "$CSM3" "scripts/csm-fixture-c.sh" "100644" "$(csm_library_content)"
csm_run "$CSM3"
expect "3: marked library at 100644 exits 0" "0" "$CSM_RC"
rm -rf "$CSM3"

# -- 4: marked library at 100755 -> non-zero, names the path (bidirectional) --
CSM4="$(mktemp -d)"
csm_repo_with_file "$CSM4" "scripts/csm-fixture-d.sh" "100755" "$(csm_library_content)"
csm_run "$CSM4"
expect "4: marked library at 100755 -> non-zero, names the path" "nonzero yes" \
  "$(csm_nz) $(csm_names scripts/csm-fixture-d.sh)"
rm -rf "$CSM4"

# -- 5: marker present but unanchored (indented) -> classified as a program,
# so 100644 fails (closes the self-exemption trap) --
CSM5="$(mktemp -d)"
csm_repo_with_file "$CSM5" "scripts/csm-fixture-e.sh" "100644" "$(csm_indented_marker_content)"
csm_run "$CSM5"
expect "5: indented marker does not exempt -- 100644 is non-zero, names the path" "nonzero yes" \
  "$(csm_nz) $(csm_names scripts/csm-fixture-e.sh)"
rm -rf "$CSM5"

# -- 6: run outside a git work tree -> says so, exits non-zero, names no file --
CSM6="$(mktemp -d)"
csm_run "$CSM6"
expect "6: outside a git work tree -> non-zero, says so, names no scripts/tests file" \
  "nonzero yes no" \
  "$(csm_nz) $(printf '%s' "$CSM_OUT" | grep -qi 'git work tree' && echo yes || echo no) \
$(printf '%s' "$CSM_OUT" | grep -qE '(^|[[:space:]])(scripts|tests)/[^[:space:]]+\.sh' && echo yes || echo no)"
rm -rf "$CSM6"

# -- 7: LARAVEL_LOOP_* exported with arbitrary values changes nothing (A7) --
CSM7="$(mktemp -d)"
csm_repo_with_file "$CSM7" "scripts/csm-fixture-f.sh" "100644" "$(csm_program_content)"
csm_run "$CSM7"
CSM7_RC_PLAIN="$CSM_RC"; CSM7_OUT_PLAIN="$CSM_OUT"
CSM_OUT="$(cd "$CSM7" && LARAVEL_LOOP_FOO=arbitrary LARAVEL_LOOP_SHIP_GATE_TIMEOUT=nonsense bash "$CSM" 2>&1)"
CSM_RC=$?
expect "7: LARAVEL_LOOP_* exported -> identical exit+output, no such literal in the script (A7)" \
  "same same 0" \
  "$([ "$CSM_RC" = "$CSM7_RC_PLAIN" ] && echo same || echo different) \
$(diff <(printf '%s' "$CSM7_OUT_PLAIN") <(printf '%s' "$CSM_OUT") >/dev/null 2>&1 && echo same || echo different) \
$(grep -c 'LARAVEL_LOOP' "$CSM")"
rm -rf "$CSM7"

# ---------------------------------------------------------------------------
echo
echo "cost-ledger-lib.sh conforms to the script-mode rule (S2 -- spec.md A5, ship-gate-blind-to-ci)"

# -- 1: the checker exits 0 over this repository's own real tree --
CSM_REAL_OUT="$(cd "$ROOT" && bash "$CSM" 2>&1)"
CSM_REAL_RC=$?
expect "1: check-script-modes.sh exits 0 over this repository's own tree" "0" "$CSM_REAL_RC"

# -- 2: A5, iterated -- for every scripts/*.sh and tests/*.sh file, the rule's
# classification (marker present, unindented, within the first 20 lines ->
# library, else program) agrees with the mode git ls-files -s reports for it.
# Deliberately not a hardcoded file count (today 12, having been 11 before S1
# landed) -- only "at least one file was actually checked" and "zero
# mismatches" are asserted.
A5_MISMATCHES=0
A5_CHECKED=0
while read -r a5_mode _a5_sha _a5_stage a5_path; do
  [ -z "${a5_path:-}" ] && continue
  A5_CHECKED=$((A5_CHECKED + 1))
  if head -n 20 "$ROOT/$a5_path" 2>/dev/null | grep -qxF '# laravel-loop:sourced-library'; then
    a5_want="100644"
  else
    a5_want="100755"
  fi
  [ "$a5_mode" = "$a5_want" ] || A5_MISMATCHES=$((A5_MISMATCHES + 1))
done <<EOF
$(cd "$ROOT" && git ls-files -s scripts/*.sh tests/*.sh 2>/dev/null)
EOF
A5_HAS_FILES=0
[ "$A5_CHECKED" -gt 0 ] && A5_HAS_FILES=1
expect "2: A5 -- every scripts/*.sh & tests/*.sh file's committed mode agrees with the rule's classification, iterated" \
  "0 mismatches, checked-some 1" \
  "$A5_MISMATCHES mismatches, checked-some $A5_HAS_FILES"

# ---------------------------------------------------------------------------
echo
echo "ci.yml 'scripts are executable' step defers to check-script-modes.sh (S3, ship-gate-blind-to-ci)"

CIYML="$ROOT/.github/workflows/ci.yml"

# extract_ci_step_run: prints the run: body of the named step in ci.yml's
# guardrails job -- handles both the block-scalar form (`run: |` followed by
# indented lines) and the single-line form (`run: <command>`). Extraction
# yielding nothing is a failure (rc 1, empty stdout), never a silent skip --
# A4's proof depends on this reading ci.yml itself, not a retyped copy of it.
# bash + sed only, no YAML parser.
extract_ci_step_run() {
  local file="$1" name="$2" block line in_block=0 body=""
  block="$(sed -n "/^      - name: ${name}\$/,\$p" "$file" | tail -n +2 | sed '/^      - name:/,$d')"
  [ -z "$block" ] && return 1

  while IFS= read -r line; do
    if [ "$in_block" -eq 0 ]; then
      case "$line" in
        '        run: |'*)
          in_block=1
          ;;
        '        run: '*)
          body="${line#        run: }"
          in_block=1
          break
          ;;
      esac
    else
      case "$line" in
        '          '*)
          body="${body}${line#          }
"
          ;;
        '')
          body="${body}
"
          ;;
        *)
          break
          ;;
      esac
    fi
  done <<CIBLOCK
$block
CIBLOCK

  printf '%s' "$body" | grep -q '[^[:space:]]' || return 1
  printf '%s\n' "$body"
}

CI_STEP_BODY="$(extract_ci_step_run "$CIYML" "scripts are executable")"
CI_STEP_RC=$?

# -- 1: extraction of the step's run: body yields a non-empty command
# (fail-closed guard on the extractor itself) --
expect "1: extraction of the step's run: body from ci.yml yields a non-empty command" \
  "0 nonempty" \
  "$CI_STEP_RC $([ -n "$(printf '%s' "$CI_STEP_BODY" | tr -d '[:space:]')" ] && echo nonempty || echo empty)"

# Builds a throwaway git repo carrying a real copy of check-script-modes.sh
# (so both the extracted-CI answer and the direct answer see the very same
# checker) plus exactly one committed scripts/*.sh fixture file at the
# requested mode. $1 dir $2 relpath $3 mode $4 content
s3_repo_with_file() {
  local dir="$1" relpath="$2" mode="$3" content="$4" chmodflag
  mkdir -p "$dir/scripts" "$dir/$(dirname "$relpath")"
  cp "$CSM" "$dir/scripts/check-script-modes.sh"
  printf '%s' "$content" > "$dir/$relpath"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email t@example.test
  git -C "$dir" config user.name test
  git -C "$dir" add -A
  git -C "$dir" update-index --chmod=+x scripts/check-script-modes.sh
  [ "$mode" = "100755" ] && chmodflag="+x" || chmodflag="-x"
  git -C "$dir" update-index --chmod="$chmodflag" "$relpath"
  git -C "$dir" commit --quiet -m init
}

s3_nz() { [ "$1" -ne 0 ] && echo nonzero || echo zero; }
s3_names() { printf '%s' "$1" | grep -qF "$2" && echo yes || echo no; }

# -- 2: parity, fixture holding a marked library at 100644 -- extracted-CI
# answer == direct answer (both exit 0, both silent). Fails today: today's
# inline [ -x ] loop rejects the file the checker accepts --
S3LIBDIR="$(mktemp -d)"
s3_repo_with_file "$S3LIBDIR" "scripts/s3-fixture-lib.sh" "100644" "$(csm_library_content)"
S3_CI_OUT="$(cd "$S3LIBDIR" && bash -c "$CI_STEP_BODY" 2>&1)"; S3_CI_RC=$?
S3_DIRECT_OUT="$(cd "$S3LIBDIR" && bash scripts/check-script-modes.sh 2>&1)"; S3_DIRECT_RC=$?
expect "2: parity, fixture holding a marked library at 100644: extracted-CI answer == direct answer (both exit 0, both silent)" \
  "0 0 empty empty" \
  "$S3_CI_RC $S3_DIRECT_RC $([ -z "$S3_CI_OUT" ] && echo empty || echo nonempty) $([ -z "$S3_DIRECT_OUT" ] && echo empty || echo nonempty)"
rm -rf "$S3LIBDIR"

# -- 3: parity, fixture holding an unmarked program at 100644 -- extracted-CI
# answer == direct answer (both non-zero, both naming the same path) --
S3PROGDIR="$(mktemp -d)"
s3_repo_with_file "$S3PROGDIR" "scripts/s3-fixture-prog.sh" "100644" "$(csm_program_content)"
S3_CI_OUT2="$(cd "$S3PROGDIR" && bash -c "$CI_STEP_BODY" 2>&1)"; S3_CI_RC2=$?
S3_DIRECT_OUT2="$(cd "$S3PROGDIR" && bash scripts/check-script-modes.sh 2>&1)"; S3_DIRECT_RC2=$?
expect "3: parity, fixture holding an unmarked program at 100644: extracted-CI answer == direct answer (both non-zero, both naming the same path)" \
  "nonzero nonzero yes yes" \
  "$(s3_nz "$S3_CI_RC2") $(s3_nz "$S3_DIRECT_RC2") $(s3_names "$S3_CI_OUT2" "scripts/s3-fixture-prog.sh") $(s3_names "$S3_DIRECT_OUT2" "scripts/s3-fixture-prog.sh")"
rm -rf "$S3PROGDIR"

# -- 4: structural -- the step invokes scripts/check-script-modes.sh and
# retains no [ -x loop of its own (catches an inline copy that happens to
# agree on the two fixtures above) --
expect "4: structural -- the step invokes scripts/check-script-modes.sh and retains no [ -x loop of its own" \
  "yes no" \
  "$(printf '%s' "$CI_STEP_BODY" | grep -qF 'scripts/check-script-modes.sh' && echo yes || echo no) $(printf '%s' "$CI_STEP_BODY" | grep -qF '[ -x' && echo yes || echo no)"

# ---------------------------------------------------------------------------
echo
echo "docs/loop/checks.md (S4 -- spec.md A3, A6, ship-gate-blind-to-ci)"

CHECKSMD="$ROOT/docs/loop/checks.md"

# Flattened, markdown-stripped copy of the doc for multi-word phrase matching:
# newlines collapsed to spaces (so a phrase wrapped across two source lines by
# the editor's line width still reads as one phrase, exactly as markdown
# renders it), backticks and bold markers (`` ` `` and `**`) removed. A single
# literal `*` (as in `scripts/*.sh`) is left alone -- only the doubled bold
# marker is stripped.
CHECKSMD_FLAT="$(tr '\n' ' ' < "$CHECKSMD" | sed -e 's/`//g' -e 's/\*\*//g')"

# -- 1: every '- name:' in ci.yml's guardrails job, extracted from the YAML,
# appears in docs/loop/checks.md. Iterated, not hardcoded, so a future fourth
# step fails this the moment it lands without a matching row here. --
CHECKS_STEP_MISSING=0
CHECKS_STEP_CHECKED=0
while IFS= read -r checks_step_name; do
  [ -z "$checks_step_name" ] && continue
  CHECKS_STEP_CHECKED=$((CHECKS_STEP_CHECKED + 1))
  printf '%s' "$CHECKSMD_FLAT" | grep -qF "$checks_step_name" || CHECKS_STEP_MISSING=$((CHECKS_STEP_MISSING + 1))
done <<EOF
$(grep -E '^      - name: ' "$CIYML" | sed -E 's/^      - name: //')
EOF
expect "1: every ci.yml guardrails step name appears in docs/loop/checks.md, iterated" \
  "checked-some 1, missing 0" \
  "checked-some $([ "$CHECKS_STEP_CHECKED" -gt 0 ] && echo 1 || echo 0), missing $CHECKS_STEP_MISSING"

# -- 2: all three gate names, extracted from ship-check.sh's own header list
# (the numbered "1./2./3." lines, not the wrapped continuation lines under
# gate 3), appear in docs/loop/checks.md. --
SHIPCHECK="$ROOT/scripts/ship-check.sh"
CHECKS_GATE_MISSING=0
CHECKS_GATE_CHECKED=0
while IFS= read -r checks_gate_name; do
  [ -z "$checks_gate_name" ] && continue
  CHECKS_GATE_CHECKED=$((CHECKS_GATE_CHECKED + 1))
  printf '%s' "$CHECKSMD_FLAT" | grep -qF "$checks_gate_name" || CHECKS_GATE_MISSING=$((CHECKS_GATE_MISSING + 1))
done <<EOF
$(grep -E '^#   [0-9]+\. ' "$SHIPCHECK" | sed -E 's/^#   [0-9]+\. //; s/ --$//')
EOF
expect "2: all three ship-check.sh header gate names appear in docs/loop/checks.md" \
  "checked 3, missing 0" \
  "checked $CHECKS_GATE_CHECKED, missing $CHECKS_GATE_MISSING"

# -- 3: the document names version-agreement as absent from the pushed-commit
# side, names gate 1's harness as the only (indirect) path by which the mode
# rule reaches the G3 verdict, and states that indirection as OQ2's chosen
# cost rather than an oversight. One case, three conjoined facts about the
# same paragraph -- splitting them would let one drift without the others. --
expect "3: doc names version-agreement as absent from pushed-commit, names the mode rule's only path to the verdict as indirect via gate 1's harness, and calls that OQ2's chosen cost" \
  "absent-version yes, indirect-via-gate1 yes, oq2-chosen-cost yes" \
  "absent-version $(printf '%s' "$CHECKSMD_FLAT" | grep -qF 'Absent from this side:' && printf '%s' "$CHECKSMD_FLAT" | grep -qi 'version consistency' && echo yes || echo no), indirect-via-gate1 $(printf '%s' "$CHECKSMD_FLAT" | grep -qi 'not a declared gate' && printf '%s' "$CHECKSMD_FLAT" | grep -qi 'indirectly' && printf '%s' "$CHECKSMD_FLAT" | grep -qi 'gate 1' && echo yes || echo no), oq2-chosen-cost $(printf '%s' "$CHECKSMD_FLAT" | grep -qi 'OQ2' && printf '%s' "$CHECKSMD_FLAT" | grep -qi 'chosen cost' && echo yes || echo no)"

# -- 4: the document names all six affected versions and records the earliest
# run's cause as unknown (A6). --
CHECKS_VERSION_MISSING=0
for checks_version in v0.2.0 v0.3.0 v0.3.1 v0.4.0 v0.5.0 v0.6.0; do
  grep -qF "$checks_version" "$CHECKSMD" || CHECKS_VERSION_MISSING=$((CHECKS_VERSION_MISSING + 1))
done
expect "4: doc names all six affected versions and records the earliest run's cause as unknown" \
  "missing-versions 0, names-run-id yes, says-unknown yes" \
  "missing-versions $CHECKS_VERSION_MISSING, names-run-id $(grep -qF '31696279581' "$CHECKSMD" && echo yes || echo no), says-unknown $(grep -qi 'unknown' "$CHECKSMD" && echo yes || echo no)"

# -- 5: every `runs-on:` value in ci.yml appears in docs/loop/checks.md's own
# claimed-platforms statement, tied to the exact "<platform> is claimed"
# phrasing rather than to bare substring presence (both platform labels
# already appear elsewhere in the doc as job headers, so a naked substring
# check would pass without the statement existing at all). Iterated over the
# YAML, not hardcoded, so a third `runs-on:` added later without a matching
# row fails this the moment it lands.
CLAIMED_PLATFORM_MISSING=0
CLAIMED_PLATFORM_CHECKED=0
while IFS= read -r runs_on_value; do
  [ -z "$runs_on_value" ] && continue
  CLAIMED_PLATFORM_CHECKED=$((CLAIMED_PLATFORM_CHECKED + 1))
  printf '%s' "$CHECKSMD_FLAT" | grep -qF "${runs_on_value} is claimed" || CLAIMED_PLATFORM_MISSING=$((CLAIMED_PLATFORM_MISSING + 1))
done <<EOF
$(grep -E '^[[:space:]]*runs-on: ' "$CIYML" | sed -E 's/^[[:space:]]*runs-on: //')
EOF
expect "5: every ci.yml runs-on value appears in docs/loop/checks.md's claimed-platforms statement, iterated" \
  "checked-some 1, missing 0" \
  "checked-some $([ "$CLAIMED_PLATFORM_CHECKED" -gt 0 ] && echo 1 || echo 0), missing $CLAIMED_PLATFORM_MISSING"

# -- 6: the statement carries, per claimed platform, a named evidence
# producer, AND the citation-is-not-proof limit, AND the rolling-image
# caveat -- one conjoined case over the flattened doc, the same shape as
# case 3 above, because a single case covering both directions of the
# mapping would keep passing while half of it drifted.
expect "6: claimed-platforms statement names each platform's evidence producer, the citation-is-not-proof limit, and the rolling-image caveat" \
  "ubuntu-producer yes, macos-producer yes, citation-not-proof yes, rolling-image yes" \
  "ubuntu-producer $(printf '%s' "$CHECKSMD_FLAT" | grep -qi 'ubuntu-latest is claimed' && printf '%s' "$CHECKSMD_FLAT" | grep -qi 'guardrails job.s own guardrail tests step' && echo yes || echo no), macos-producer $(printf '%s' "$CHECKSMD_FLAT" | grep -qi 'macos-latest is claimed' && printf '%s' "$CHECKSMD_FLAT" | grep -qi 'guardrails-macos job.s own guardrail tests (macos) step' && echo yes || echo no), citation-not-proof $(printf '%s' "$CHECKSMD_FLAT" | grep -qi 'citable image manifest is not proof' && echo yes || echo no), rolling-image $(printf '%s' "$CHECKSMD_FLAT" | grep -qi 'rolling image' && echo yes || echo no)"

# ---------------------------------------------------------------------------
echo "cost report + budget gate: incomplete slice ranking says so (S1, recovered-figure-drops-slice-and-model, spec.md RD3/RD4)"

# Fixture 1 -- all-transcribed, real shape: a start+finish carrying model, the
# finish itself async_launched with no total_tokens, plus a `recovered` line
# supplying the only figure this invocation has. Reproduces the live
# `harness-fails-only-on-linux` shape at unit scale: cost_scan (and so
# COST_N_PRICED/COST_TOKENS_PRICED) counts it priced, and the whole priced
# population sits outside the ranking, which is what (S1-2) asserts the
# Slices section must say out loud.
#
# S5 RE-POINTED THIS FIXTURE, and it is a re-point rather than a weakening:
# the records carried `"slice":"S1"` when S1 was built, because before S5 the
# slice pass discarded every `recovered` record and so ranked nothing whatever
# the label said ("the pass never saw it"). After S5 that same fixture ranks
# correctly and has nothing outside the ranking, so the assertion below could
# only ever pass while the defect existed. Dropping the label moves the
# fixture to the state the assertion is about -- a priced invocation the
# ranking genuinely cannot place -- leaving both assertions byte-identical and
# both still able to go red. The clash itself was a G1 defect: S1's cases and
# S5's own "Done when" disagreed about this fixture, and the human ruled at
# the S5 lane (see decisions.md).
S1ATDIR="$(mktemp -d)"
mkdir -p "$S1ATDIR/.claude"
S1ATLEDGER="$S1ATDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s1at1","slug":"s1-all-transcribed","phase":"build","agent":"loop-build","model":"opus","model_source":"derived"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s1at1","slug":"s1-all-transcribed","phase":"build","agent":"loop-build","model":"opus","model_source":"derived","status":"async_launched"}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s1at1","slug":"s1-all-transcribed","total_tokens":42000,"token_source":"transcribed"}'
} > "$S1ATLEDGER"
S1AT_OUT="$(report "$S1ATDIR" s1-all-transcribed)"

expect "(S1-1) RD4: all-transcribed unit -- '(no flags raised)' does NOT appear (today it does)" "no" \
  "$(printf '%s\n' "$S1AT_OUT" | grep -qF '(no flags raised)' && echo yes || echo no)"

s1at_check() {
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_scan "$S1ATLEDGER" "s1-all-transcribed"
  printf '%s %s' "$COST_N_PRICED" "$COST_TOKENS_PRICED"
}
S1AT_NT="$(s1at_check)"
S1AT_N="${S1AT_NT% *}"
S1AT_T="${S1AT_NT#* }"
expect "(S1-2) RD3: Slices section names the unattributed count and token total, equal to COST_N_PRICED/COST_TOKENS_PRICED" "yes" \
  "$(printf '%s\n' "$S1AT_OUT" | grep -qF "${S1AT_N} priced invocation(s), ${S1AT_T} token(s) sit outside this ranking" && echo yes || echo no)"

rm -rf "$S1ATDIR"

# Fixture 2 -- mixed and deliberately INCOMPLETE: one observed, ranked
# invocation (S1, 50000 tokens) and one priced invocation the ranking cannot
# place (10000 transcribed tokens, no slice on its own start/finish records).
# The population is unequal, so the concentration verdict and the gate's
# re-slice recommendation must both stay silent about a "largest share" --
# that is what the three cases below assert.
#
# S5 RE-POINTED THIS FIXTURE, same reason as fixture 1 and the same G1 defect:
# the second invocation carried `"slice":"S2"` when S1 was built, and was
# invisible to the slice pass only because the pass discarded `recovered`
# records. After S5 it ranks, the population is complete, and the 83 %
# concentration flag fires -- which is exactly what S5's own "Done when"
# requires and what (S1-3) forbade. Dropping the label keeps every assertion
# below byte-identical while pointing them at a population that is still
# genuinely incomplete; the now-complete mixed shape is asserted in S5's own
# section, where the flag is required to fire.
S1MIXDIR="$(mktemp -d)"
mkdir -p "$S1MIXDIR/.claude"
S1MIXLEDGER="$S1MIXDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s1mix-big","slug":"s1-mixed-fixture","slice":"S1","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s1mix-big","slug":"s1-mixed-fixture","slice":"S1","phase":"build","agent":"loop-build","status":"completed","total_tokens":50000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"s1mix-small","slug":"s1-mixed-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"s1mix-small","slug":"s1-mixed-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":5,"event":"recovered","invocation_id":"s1mix-small","slug":"s1-mixed-fixture","total_tokens":10000,"token_source":"transcribed"}'
} > "$S1MIXLEDGER"
S1MIX_OUT="$(report "$S1MIXDIR" s1-mixed-fixture)"

expect "(S1-3) RD4: incomplete mixed fixture -- no 'concentration threshold' string anywhere while a priced invocation sits outside the ranking" "no" \
  "$(printf '%s\n' "$S1MIX_OUT" | grep -qF 'concentration threshold' && echo yes || echo no)"

# (S1-4) guard, CO7 unassessable shape (existing UNASSESS_OUT fixture: one
# priced invocation with no slice at all, one properly sliced) -- the
# pre-existing Flags sentence is kept byte-identical, wording and section.
expect "(S1-4) guard: the (d) CO7 unassessable shape still prints the Flags sentence verbatim" "yes" \
  "$(printf '%s\n' "$UNASSESS_OUT" | grep -qF 'could not be assessed -- 1 priced invocation(s) carry no slice attribution' && echo yes || echo no)"

# (S1-5) RD8, guard: a recovery-free fixture where every priced invocation
# DOES carry a slice (the existing (d) CO7 30%-fixture, CONC_OUT) is
# byte-identical to a frozen expected block -- this slice must not change a
# single byte of output when there is nothing outside the ranking.
read -r -d '' S1_FROZEN_CONC <<'FROZEN'
Coverage:
  based on 2 of 2 invocations that carry a token figure (0 unpriced, not counted) -- 100 % coverage
  0 invocation(s) started with no finish recorded yet -- in flight, not counted as unpriced.
  per phase (priced/total invocations; in-flight and unpriced called out, never folded together):
    spec   0/0 priced (0 unpriced)
    slice  0/0 priced (0 unpriced)
    build  2/2 priced (0 unpriced)
    verify 0/0 priced (0 unpriced)
  elapsed (wall-clock, first recorded start to last recorded finish; never summed across overlapping invocations): 3 second(s)

Tokens (priced subset only -- never the unit's whole cost):
  total priced tokens: 10000
  based on 2 of 2 invocations that carry a token figure (0 unpriced, not counted) -- 100 % coverage
  cache-read share: unavailable (cache_read_tokens absent from every priced record)

Phases (priced invocations only; model per phase, model_source shown when derived):
    spec   unavailable
    slice  unavailable
    build  unavailable
    verify unavailable

Rework:
  This measures the cost of slices that were not right first time, at whole-invocation
  granularity -- not the cost of retrying. An invocation needing even one refine pass has
  its WHOLE token cost counted as rework, deliberately over-attributing rather than
  estimating a per-pass split. This is not comparable to the requirements document's
  <15% target (Sec.10), which was calibrated against a narrower, per-pass definition.
  No pass/fail verdict against that target is printed here.
  count: 0 of 2 invocation(s) marked rework
  token share: unavailable (no priced invocations are marked rework)

Slices (top by priced tokens, priced subset only):
  S1                   8000 tokens (1 priced invocation(s), 0 reworked)
  S2                   2000 tokens (1 priced invocation(s), 0 reworked)

Flags:
  S1 is 80% of this unit's priced total -- above the 30% concentration threshold.

Budget:
  no threshold is set (LARAVEL_LOOP_BUDGET_WARN, LARAVEL_LOOP_BUDGET_HARD are both unset) -- nothing will gate.
FROZEN
expect "(S1-5) RD8: recovery-free, fully-sliced fixture is byte-identical to a frozen expected block" "" \
  "$(diff <(printf '%s' "$S1_FROZEN_CONC") <(printf '%s' "$CONC_OUT"))"

# (S1-6) the gate's breach message on the mixed fixture: with a hard
# threshold set, it must not recommend re-slicing "S1" as "the largest
# share" while S2's transcribed tokens sit outside the ranking -- it must
# say how many invocations and how many tokens instead.
S1MIX_JSON="$(budget_payload s1-mixed-fixture)"
S1MIX_GATE_ERR="$(CLAUDE_PROJECT_DIR="$S1MIXDIR" LARAVEL_LOOP_BUDGET_HARD=1000 gate_stderr "$S1MIX_JSON")"
expect "(S1-6) RD4: gate breach message names no top slice as the largest share while priced tokens sit outside the ranking; states the count and tokens instead" \
  "no-largest-share yes, states-outside yes" \
  "no-largest-share $(printf '%s\n' "$S1MIX_GATE_ERR" | grep -qF "largest share of this unit's observed spend" && echo no || echo yes), states-outside $(printf '%s\n' "$S1MIX_GATE_ERR" | grep -qE '1 priced invocation\(s\), 10000 token\(s\) sit outside this ranking' && echo yes || echo no)"

# (S1-7) RD10: the report and the gate state the SAME unattributed count for
# the same fixture -- structurally guaranteed by both calling the one
# cost_slice_unranked() helper, asserted here rather than only by
# construction.
S1MIX_REPORT_N="$(printf '%s\n' "$S1MIX_OUT" | grep -oE '^  [0-9]+ priced invocation\(s\), [0-9]+ token\(s\) sit outside this ranking' | grep -oE '^  [0-9]+' | tr -d ' ')"
S1MIX_GATE_N="$(printf '%s\n' "$S1MIX_GATE_ERR" | grep -oE '[0-9]+ priced invocation\(s\), [0-9]+ token\(s\) sit outside this ranking' | grep -oE '^[0-9]+')"
expect "(S1-7) RD10: report and gate state the same unattributed invocation count for one fixture" \
  "1 1" "$S1MIX_REPORT_N $S1MIX_GATE_N"

rm -rf "$S1MIXDIR"

# ---------------------------------------------------------------------------
echo "cost report parser parity: jq vs python3 (S2, recovered-figure-drops-slice-and-model)"

# (S2-1) self-check of the fixture itself: a parity case over a broken PATH
# proves nothing, so this asserts the precondition directly, under the exact
# PATH the cases below use -- python3 resolves, jq does not.
JQ_ABSENT_PATH="$(new_jq_absent_path)"
expect "(S2-1) new_jq_absent_path resolves python3 and not jq" "python3 yes, jq no" \
  "python3 $(PATH="$JQ_ABSENT_PATH" command -v python3 >/dev/null 2>&1 && echo yes || echo no), jq $(PATH="$JQ_ABSENT_PATH" command -v jq >/dev/null 2>&1 && echo yes || echo no)"

# (S2-2) cost_scan via the full report, on the S7 recovered fixture (the
# same ledger content as the S7 fixture above -- reconstructed here because
# that fixture's directory was already removed).
S2S7DIR="$(mktemp -d)"
mkdir -p "$S2S7DIR/.claude"
S2S7LEDGER="$S2S7DIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s7c1","slug":"s7-fixture","phase":"spec","agent":"loop-spec"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s7c1","slug":"s7-fixture","phase":"spec","agent":"loop-spec","status":"completed","total_tokens":1000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"s7c2","slug":"s7-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"s7c2","slug":"s7-fixture","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":5,"event":"start","invocation_id":"s7c3","slug":"s7-fixture","phase":"verify","agent":"loop-verify"}'
  printf '%s\n' '{"ts":6,"event":"finish","invocation_id":"s7c3","slug":"s7-fixture","phase":"verify","agent":"loop-verify","status":"async_launched"}'
  printf '%s\n' '{"ts":7,"event":"recovered","invocation_id":"s7c2","slug":"s7-fixture","total_tokens":11035,"token_source":"transcribed"}'
} > "$S2S7LEDGER"
S2S7_JQ_OUT="$(report "$S2S7DIR" s7-fixture)"
S2S7_PY_OUT="$(PATH="$JQ_ABSENT_PATH" report "$S2S7DIR" s7-fixture)"
expect "(S2-2) full report byte-identical jq vs python3 on the S7 recovered fixture" "" \
  "$(diff <(printf '%s' "$S2S7_JQ_OUT") <(printf '%s' "$S2S7_PY_OUT"))"
rm -rf "$S2S7DIR"

# (S2-3) cost_scan via the full report, on the S8 observed/transcribed
# conflict fixture (reconstructed for the same reason as S2-2).
S2S8DIR="$(mktemp -d)"
mkdir -p "$S2S8DIR/.claude"
S2S8LEDGER="$S2S8DIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s8c1","slug":"s8-fixture","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s8c1","slug":"s8-fixture","phase":"build","agent":"loop-build","status":"completed","total_tokens":12102}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s8c1","slug":"s8-fixture","total_tokens":11035,"token_source":"transcribed"}'
} > "$S2S8LEDGER"
S2S8_JQ_OUT="$(report "$S2S8DIR" s8-fixture)"
S2S8_PY_OUT="$(PATH="$JQ_ABSENT_PATH" report "$S2S8DIR" s8-fixture)"
expect "(S2-3) full report byte-identical jq vs python3 on the S8 observed/transcribed conflict fixture" "" \
  "$(diff <(printf '%s' "$S2S8_JQ_OUT") <(printf '%s' "$S2S8_PY_OUT"))"
rm -rf "$S2S8DIR"

# (S2-4) cost_scan via the full report, on the (d) CO7 concentration fixture
# (reconstructed for the same reason as S2-2/S2-3).
S2CONCDIR="$(mktemp -d)"
mkdir -p "$S2CONCDIR/.claude"
S2CONCLEDGER="$S2CONCDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"c1","slug":"slice-conc","slice":"S1","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"c1","slug":"slice-conc","slice":"S1","phase":"build","agent":"loop-build","status":"completed","total_tokens":8000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"c2","slug":"slice-conc","slice":"S2","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"c2","slug":"slice-conc","slice":"S2","phase":"build","agent":"loop-build","status":"completed","total_tokens":2000}'
} > "$S2CONCLEDGER"
S2CONC_JQ_OUT="$(report "$S2CONCDIR" slice-conc)"
S2CONC_PY_OUT="$(PATH="$JQ_ABSENT_PATH" report "$S2CONCDIR" slice-conc)"
expect "(S2-4) full report byte-identical jq vs python3 on the (d) CO7 concentration fixture" "" \
  "$(diff <(printf '%s' "$S2CONC_JQ_OUT") <(printf '%s' "$S2CONC_PY_OUT"))"

# (S2-5) cost_slice_rows' own rows, byte-identical jq vs python3, on the same
# concentration fixture -- the reader S5 will teach to recognise a recovered
# record, proven testable before that slice touches it.
s2_conc_rows() {
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_slice_rows "$S2CONCLEDGER" "slice-conc"
}
S2CONC_ROWS_JQ="$(s2_conc_rows)"
S2CONC_ROWS_PY="$(PATH="$JQ_ABSENT_PATH" s2_conc_rows)"
expect "(S2-5) cost_slice_rows' rows byte-identical jq vs python3 on the concentration fixture" "" \
  "$(diff <(printf '%s' "$S2CONC_ROWS_JQ") <(printf '%s' "$S2CONC_ROWS_PY"))"
rm -rf "$S2CONCDIR"

# (S2-6) G2 follow-up (verify.md finding 1): the same rows parity, on a ledger
# where a TRANSCRIBED figure is the thing being ranked -- the path S5 added.
# (S2-5) above runs on a recovery-free fixture and S2-2/S2-3's recovered
# fixtures carry no `slice` label at all, so before this case the SLICEROW
# emission path for a transcribed figure was exercised by each program and
# compared by NEITHER. The label is a real-world en-dash range, as two of the
# 21 real recovered records' invocations are labelled.
#
# Both tokens matter: identical-and-empty would pass a bare diff while proving
# nothing, so the row count is asserted alongside the agreement. A future
# change that quietly stops ranking transcribed figures fails on the second
# token rather than passing on the first.
S2TRDIR="$(mktemp -d)"
mkdir -p "$S2TRDIR/.claude"
S2TRLEDGER="$S2TRDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s2tr-big","slug":"s2-transcribed","slice":"S1–S4","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s2tr-big","slug":"s2-transcribed","slice":"S1–S4","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s2tr-big","slug":"s2-transcribed","total_tokens":50000,"token_source":"transcribed"}'
  printf '%s\n' '{"ts":4,"event":"start","invocation_id":"s2tr-obs","slug":"s2-transcribed","slice":"S2","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":5,"event":"finish","invocation_id":"s2tr-obs","slug":"s2-transcribed","slice":"S2","phase":"build","agent":"loop-build","status":"completed","total_tokens":10000}'
  printf '%s\n' '{"ts":6,"event":"start","invocation_id":"s2tr-noslice","slug":"s2-transcribed","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":7,"event":"finish","invocation_id":"s2tr-noslice","slug":"s2-transcribed","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":8,"event":"recovered","invocation_id":"s2tr-noslice","slug":"s2-transcribed","total_tokens":7000,"token_source":"transcribed"}'
} > "$S2TRLEDGER"
s2_tr_rows() {
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  # >/dev/null: cost_slice_rows prints the rows AND publishes them, so the
  # unattributed count is read from the global rather than from stdout.
  cost_slice_rows "$S2TRLEDGER" "s2-transcribed" >/dev/null
  printf '%s\n%s' "$COST_SLICE_ROWS" "unknown=$COST_SLICE_UNKNOWN_PRICED"
}
S2TR_ROWS_JQ="$(s2_tr_rows)"
S2TR_ROWS_PY="$(PATH="$JQ_ABSENT_PATH" s2_tr_rows)"
expect "(S2-6) cost_slice_rows' rows AND unattributed count byte-identical jq vs python3 on a fixture where a transcribed figure is ranked" " 3" \
  "$(diff <(printf '%s' "$S2TR_ROWS_JQ") <(printf '%s' "$S2TR_ROWS_PY")) $(printf '%s' "$S2TR_ROWS_JQ" | grep -c .)"
rm -rf "$S2TRDIR" "$JQ_ABSENT_PATH"

# ---------------------------------------------------------------------------
echo "cost report: per-phase model restored for a transcribed-only figure (S3, recovered-figure-drops-slice-and-model, spec.md RD1/RD5/RD6/RD8/RD11)"

# (S3-1) RD1 happy path: a start+finish carrying model+model_source, the
# finish itself async_launched with no total_tokens, plus a `recovered` line
# supplying the only figure -- the real shape verified against all 21
# existing recovered records. The Phases block must name the model those
# records carry, marked (derived) because the records say derived.
S3ATDIR="$(mktemp -d)"
mkdir -p "$S3ATDIR/.claude"
S3ATLEDGER="$S3ATDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s3at1","slug":"s3-all-transcribed","phase":"build","agent":"loop-build","model":"opus","model_source":"derived"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s3at1","slug":"s3-all-transcribed","phase":"build","agent":"loop-build","model":"opus","model_source":"derived","status":"async_launched"}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s3at1","slug":"s3-all-transcribed","total_tokens":42000,"token_source":"transcribed"}'
} > "$S3ATLEDGER"
S3AT_OUT="$(report "$S3ATDIR" s3-all-transcribed)"
expect "(S3-1) RD1: all-transcribed unit -- build phase reads 'opus (derived)' (today: unavailable)" "yes" \
  "$(printf '%s\n' "$S3AT_OUT" | grep -qE 'build[[:space:]]+opus \(derived\)' && echo yes || echo no)"
rm -rf "$S3ATDIR"

# (S3-2) RD5: a transcribed-only invocation whose own start/finish records
# carry NO model -- the phase still reads unavailable, and no model name
# absent from the ledger is fabricated or inherited.
S3NMDIR="$(mktemp -d)"
mkdir -p "$S3NMDIR/.claude"
S3NMLEDGER="$S3NMDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s3nm1","slug":"s3-no-model","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s3nm1","slug":"s3-no-model","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s3nm1","slug":"s3-no-model","total_tokens":9000,"token_source":"transcribed"}'
} > "$S3NMLEDGER"
S3NM_OUT="$(report "$S3NMDIR" s3-no-model)"
S3NM_UNAVAILABLE="$(printf '%s\n' "$S3NM_OUT" | grep -qE 'build[[:space:]]+unavailable' && echo yes || echo no)"
S3NM_FABRICATED="$(printf '%s\n' "$S3NM_OUT" | sed -n '/^Phases/,/^$/p' | grep -qE 'opus|sonnet|claude-' && echo yes || echo no)"
expect "(S3-2) RD5: transcribed-only, no model -- build phase reads unavailable, nothing fabricated" "yes no" \
  "$S3NM_UNAVAILABLE $S3NM_FABRICATED"
rm -rf "$S3NMDIR"

# (S3-3) mixed phase: one observed invocation carrying a model, one
# transcribed-only invocation whose own records carry none, both in the
# SAME phase -- both entries must be named, neither dropped. Verified live
# before writing any code: today's output reads "build  sonnet" alone,
# silently suppressing the transcribed entry.
S3MPDIR="$(mktemp -d)"
mkdir -p "$S3MPDIR/.claude"
S3MPLEDGER="$S3MPDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s3mpa","slug":"s3-mixed-phase","phase":"build","agent":"loop-build","model":"sonnet","model_source":"observed"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s3mpa","slug":"s3-mixed-phase","phase":"build","agent":"loop-build","model":"sonnet","model_source":"observed","status":"completed","total_tokens":5000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"s3mpb","slug":"s3-mixed-phase","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"s3mpb","slug":"s3-mixed-phase","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":5,"event":"recovered","invocation_id":"s3mpb","slug":"s3-mixed-phase","total_tokens":9000,"token_source":"transcribed"}'
} > "$S3MPLEDGER"
S3MP_OUT="$(report "$S3MPDIR" s3-mixed-phase)"
expect "(S3-3) mixed phase: observed model AND unavailable both named, neither dropped (today drops the transcribed entry)" "yes" \
  "$(printf '%s\n' "$S3MP_OUT" | grep -qE 'build[[:space:]]+sonnet, unavailable' && echo yes || echo no)"
rm -rf "$S3MPDIR"

# (S3-4) RD6: the recovered line duplicated for the same invocation_id --
# identical phase model line and identical counters to the single-line
# fixture (S3-1). Exactly-once precedence extends to the model write.
S3DUPDIR="$(mktemp -d)"
mkdir -p "$S3DUPDIR/.claude"
S3DUPLEDGER="$S3DUPDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s3d1","slug":"s3-dup","phase":"build","agent":"loop-build","model":"opus","model_source":"derived"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s3d1","slug":"s3-dup","phase":"build","agent":"loop-build","model":"opus","model_source":"derived","status":"async_launched"}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s3d1","slug":"s3-dup","total_tokens":42000,"token_source":"transcribed"}'
  printf '%s\n' '{"ts":4,"event":"recovered","invocation_id":"s3d1","slug":"s3-dup","total_tokens":42000,"token_source":"transcribed"}'
} > "$S3DUPLEDGER"
S3DUP_OUT="$(report "$S3DUPDIR" s3-dup)"
expect "(S3-4) RD6: duplicated recovered line -- output identical to the single-line fixture" "" \
  "$(diff <(printf '%s' "$S3DUP_OUT") <(printf '%s' "$S3AT_OUT"))"
rm -rf "$S3DUPDIR"

# (S3-5) RD8 guard: a recovery-free fixture -- report output byte-identical
# to a frozen expected block. This slice must not change a single byte of
# output when there is no `recovered` record in the ledger.
S3RFDIR="$(mktemp -d)"
mkdir -p "$S3RFDIR/.claude"
S3RFLEDGER="$S3RFDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s3rf1","slug":"s3-recovery-free","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s3rf1","slug":"s3-recovery-free","phase":"build","agent":"loop-build","model":"claude-sonnet-4","model_source":"derived","status":"completed","total_tokens":5000}'
} > "$S3RFLEDGER"
S3RF_OUT="$(report "$S3RFDIR" s3-recovery-free)"
read -r -d '' S3_FROZEN_RF <<'FROZEN'
Coverage:
  based on 1 of 1 invocations that carry a token figure (0 unpriced, not counted) -- 100 % coverage
  0 invocation(s) started with no finish recorded yet -- in flight, not counted as unpriced.
  per phase (priced/total invocations; in-flight and unpriced called out, never folded together):
    spec   0/0 priced (0 unpriced)
    slice  0/0 priced (0 unpriced)
    build  1/1 priced (0 unpriced)
    verify 0/0 priced (0 unpriced)
  elapsed (wall-clock, first recorded start to last recorded finish; never summed across overlapping invocations): 1 second(s)

Tokens (priced subset only -- never the unit's whole cost):
  total priced tokens: 5000
  based on 1 of 1 invocations that carry a token figure (0 unpriced, not counted) -- 100 % coverage
  cache-read share: unavailable (cache_read_tokens absent from every priced record)

Phases (priced invocations only; model per phase, model_source shown when derived):
    spec   unavailable
    slice  unavailable
    build  claude-sonnet-4 (derived)
    verify unavailable

Rework:
  This measures the cost of slices that were not right first time, at whole-invocation
  granularity -- not the cost of retrying. An invocation needing even one refine pass has
  its WHOLE token cost counted as rework, deliberately over-attributing rather than
  estimating a per-pass split. This is not comparable to the requirements document's
  <15% target (Sec.10), which was calibrated against a narrower, per-pass definition.
  No pass/fail verdict against that target is printed here.
  count: 0 of 1 invocation(s) marked rework
  token share: unavailable (no priced invocations are marked rework)

Slices (top by priced tokens, priced subset only):
  no slice attributed to any priced invocation.
  1 priced invocation(s), 5000 token(s) sit outside this ranking -- unattributed.

Flags:
  concentration could not be assessed -- 1 priced invocation(s) carry no slice attribution.

Budget:
  no threshold is set (LARAVEL_LOOP_BUDGET_WARN, LARAVEL_LOOP_BUDGET_HARD are both unset) -- nothing will gate.
FROZEN
expect "(S3-5) RD8: recovery-free fixture is byte-identical to a frozen expected block" "" \
  "$(diff <(printf '%s' "$S3_FROZEN_RF") <(printf '%s' "$S3RF_OUT"))"
rm -rf "$S3RFDIR"

# (S3-6) RD11: PATH stripped of BOTH jq and python3 against a ledger holding
# recovered records -- today's degraded-environment message still appears,
# exit 0, no partial figure. Extends the existing (j) CO13 shape to a ledger
# this slice's own code path touches.
S3NPDIR="$(mktemp -d)"
mkdir -p "$S3NPDIR/.claude"
S3NPLEDGER="$S3NPDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s3np1","slug":"s3-no-parser","phase":"build","agent":"loop-build","model":"opus","model_source":"derived"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s3np1","slug":"s3-no-parser","phase":"build","agent":"loop-build","model":"opus","model_source":"derived","status":"async_launched"}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s3np1","slug":"s3-no-parser","total_tokens":42000,"token_source":"transcribed"}'
} > "$S3NPLEDGER"
S3NOPARSER_BIN="$(mktemp -d)"
for b in cat mkdir date sed bash grep; do
  p="$(command -v "$b" 2>/dev/null)"
  [ -n "$p" ] && ln -s "$p" "$S3NOPARSER_BIN/$b"
done
S3NOPARSER_OUT="$(PATH="$S3NOPARSER_BIN" report "$S3NPDIR" s3-no-parser)"
S3NOPARSER_EXIT="$(PATH="$S3NOPARSER_BIN" report_exit "$S3NPDIR" s3-no-parser)"
S3NOPARSER_SAID="$(printf '%s\n' "$S3NOPARSER_OUT" | grep -qi 'neither jq nor python3' && echo yes || echo no)"
S3NOPARSER_PARTIAL="$(printf '%s\n' "$S3NOPARSER_OUT" | grep -q 'Coverage:' && echo yes || echo no)"
expect "(S3-6) RD11: PATH stripped of jq+python3 on a ledger with recovered records -- exit 0, says so, no partial report" \
  "0 yes no" "$S3NOPARSER_EXIT $S3NOPARSER_SAID $S3NOPARSER_PARTIAL"
rm -rf "$S3NPDIR" "$S3NOPARSER_BIN"

# ---------------------------------------------------------------------------
echo "cost report: rework token share stops contradicting the count (S4, recovered-figure-drops-slice-and-model, spec.md OQ2)"

# (S4-1/S4-2) transcribed-rework fixture: the rework-marked invocation's
# ONLY figure is transcribed (finish is async_launched, no total_tokens; a
# recovered line supplies the figure). Before this slice, rework_priced_n
# and rework_tokens are incremented only in the host-observed branch, so a
# rework invocation priced purely by a recovered record contradicts itself:
# "count: 1 ... marked rework" next to "token share: unavailable (no priced
# invocations are marked rework)" even though one plainly is.
S4TRDIR="$(mktemp -d)"
mkdir -p "$S4TRDIR/.claude"
S4TRLEDGER="$S4TRDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s4tr1","slug":"s4-transcribed-rework","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s4tr1","slug":"s4-transcribed-rework","phase":"build","agent":"loop-build","status":"async_launched","phase_detail":"rework","refine_passes":2}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s4tr1","slug":"s4-transcribed-rework","total_tokens":6000,"token_source":"transcribed"}'
  printf '%s\n' '{"ts":4,"event":"start","invocation_id":"s4tr2","slug":"s4-transcribed-rework","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":5,"event":"finish","invocation_id":"s4tr2","slug":"s4-transcribed-rework","phase":"build","agent":"loop-build","status":"completed","total_tokens":2000}'
} > "$S4TRLEDGER"
S4TR_OUT="$(report "$S4TRDIR" s4-transcribed-rework)"

expect "(S4-1) transcribed-rework fixture: a real token share prints, labelled as a share" "yes" \
  "$(printf '%s\n' "$S4TR_OUT" | grep -q 'token share: 75% of priced tokens (1 of 2 priced invocation(s) marked rework)' && echo yes || echo no)"

expect "(S4-2) the contradiction is gone: 'no priced invocations are marked rework' does not appear while the rework count is non-zero" "yes 0" \
  "$(printf '%s\n' "$S4TR_OUT" | grep -q 'count: 1 of 2 invocation(s) marked rework' && echo yes || echo no) $(printf '%s\n' "$S4TR_OUT" | grep -c 'no priced invocations are marked rework')"

# (S4-3) the same fixture through the SECOND consumer, write-cost-log-section.sh
# -- the committed docs/loop/<slug>/log.md carries the same figure, never the
# false sentence, which is the reason OQ2 asked about this consumer at all.
mkdir -p "$S4TRDIR/docs/loop/s4-transcribed-rework"
S4TRLOG="$S4TRDIR/docs/loop/s4-transcribed-rework/log.md"
printf '%s\n' '# Log — s4-transcribed-rework' > "$S4TRLOG"
writelog "$S4TRDIR" s4-transcribed-rework
S4TRLOG_OUT="$(cat "$S4TRLOG")"
expect "(S4-3) write-cost-log-section.sh: the log section carries the same figure as the report, not the false sentence" "yes 0" \
  "$(printf '%s\n' "$S4TRLOG_OUT" | grep -q 'token share: 75% of priced tokens' && echo yes || echo no) $(printf '%s\n' "$S4TRLOG_OUT" | grep -c 'no priced invocations are marked rework')"
rm -rf "$S4TRDIR"

# (S4-4) guard: the two states the existing CO5 cases already pin are kept
# intact -- an all-unpriced rework fixture still reads token share:
# unavailable, and a host-observed priced-rework fixture still reads 25%.
expect "(S4-4) guard: all-unpriced rework (CO5) still unavailable, host-observed priced-rework (CO5) still 25%" "yes yes" \
  "$(printf '%s\n' "$REWORKU_OUT" | grep -q 'token share: unavailable' && echo yes || echo no) $(printf '%s\n' "$REWORKP_OUT" | grep -q 'token share: 25% of priced tokens' && echo yes || echo no)"

# ---------------------------------------------------------------------------
echo "cost report per-slice ranking reads recovered figures (S5, recovered-figure-drops-slice-and-model, spec.md RD2/RD5/RD6/RD7/RD8/RD10)"

# (S5-1) The happy path, in the real ledger's own shape: a transcribed-only
# invocation whose start/finish records carry a slice label that is a RANGE
# containing a multi-byte en-dash -- `S1–S4`, exactly as two of the 21 real
# recovered records' invocations are labelled. Before S5 the slice pass
# discarded every `recovered` record, so this printed `no slice attributed to
# any priced invocation` while cost_scan counted the very same invocation
# priced. The label is asserted whole, so a byte-level mangling of the en-dash
# fails the case rather than passing a substring match.
S5RDIR="$(mktemp -d)"
mkdir -p "$S5RDIR/.claude"
S5RLEDGER="$S5RDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s5r1","slug":"s5-ranked","slice":"S1–S4","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s5r1","slug":"s5-ranked","slice":"S1–S4","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s5r1","slug":"s5-ranked","total_tokens":50000,"token_source":"transcribed"}'
} > "$S5RLEDGER"
S5R_OUT="$(report "$S5RDIR" s5-ranked)"
expect "(S5-1) RD2: a transcribed-only invocation is ranked against the slice its own records name, en-dash label intact" "yes yes 0" \
  "$(printf '%s\n' "$S5R_OUT" | grep -qF 'S1–S4' && echo yes || echo no) $(printf '%s\n' "$S5R_OUT" | grep -qE 'S1–S4 +50000 tokens \(1 priced invocation\(s\), 0 reworked\)' && echo yes || echo no) $(printf '%s\n' "$S5R_OUT" | grep -c 'no slice attributed to any priced invocation')"
rm -rf "$S5RDIR"

# (S5-2) The mixed shape, now COMPLETE: one observed invocation (S1, 50000)
# and one transcribed-only invocation (S2, 10000) whose records both carry a
# slice. Both rows rank, the populations reconcile so nothing sits outside the
# ranking, and the concentration verdict -- which S1 gated on population
# equality -- is therefore assessable and fires for the 83 % holder. This is
# the fixture S1's own cases were re-pointed away from, asserted here in the
# state S5's envelope requires.
S5MIXDIR="$(mktemp -d)"
mkdir -p "$S5MIXDIR/.claude"
S5MIXLEDGER="$S5MIXDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s5mix-big","slug":"s5-mixed","slice":"S1","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s5mix-big","slug":"s5-mixed","slice":"S1","phase":"build","agent":"loop-build","status":"completed","total_tokens":50000}'
  printf '%s\n' '{"ts":3,"event":"start","invocation_id":"s5mix-small","slug":"s5-mixed","slice":"S2","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":4,"event":"finish","invocation_id":"s5mix-small","slug":"s5-mixed","slice":"S2","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":5,"event":"recovered","invocation_id":"s5mix-small","slug":"s5-mixed","total_tokens":10000,"token_source":"transcribed"}'
} > "$S5MIXLEDGER"
S5MIX_OUT="$(report "$S5MIXDIR" s5-mixed)"
expect "(S5-2) RD2: mixed fixture ranks both rows, nothing sits outside the ranking, and the 83 % concentration flag fires" "yes yes 0 yes" \
  "$(printf '%s\n' "$S5MIX_OUT" | grep -qE 'S1 +50000 tokens \(1 priced invocation\(s\)' && echo yes || echo no) $(printf '%s\n' "$S5MIX_OUT" | grep -qE 'S2 +10000 tokens \(1 priced invocation\(s\)' && echo yes || echo no) $(printf '%s\n' "$S5MIX_OUT" | grep -c 'sit outside this ranking') $(printf '%s\n' "$S5MIX_OUT" | grep -qE 'S1 is 83% .*concentration threshold' && echo yes || echo no)"

# (S5-3) RD5, the slice-less half: a transcribed figure whose invocation
# carries NO slice on its own records is counted in COST_SLICE_UNKNOWN_PRICED
# -- it is priced, so the population must account for it -- and no slice name
# is invented for it. Read off the library directly, because the count is the
# thing being asserted, not its rendering.
s5_unknown_check() { # $1 ledger $2 slug -> "<unknown> <rows>"
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  # >/dev/null: cost_slice_rows PRINTS the rows as well as publishing them in
  # COST_SLICE_ROWS (see its doc block), so a helper that echoes the variable
  # too would report every row twice.
  cost_slice_rows "$1" "$2" >/dev/null
  printf '%s %s' "$COST_SLICE_UNKNOWN_PRICED" "$(printf '%s' "$COST_SLICE_ROWS" | grep -c . )"
}
S5NSDIR="$(mktemp -d)"
mkdir -p "$S5NSDIR/.claude"
S5NSLEDGER="$S5NSDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s5ns1","slug":"s5-noslice","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s5ns1","slug":"s5-noslice","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s5ns1","slug":"s5-noslice","total_tokens":7000,"token_source":"transcribed"}'
} > "$S5NSLEDGER"
expect "(S5-3) RD5: a transcribed figure with no slice on its own records is counted unattributed, and no slice name is invented" "1 0" \
  "$(s5_unknown_check "$S5NSLEDGER" s5-noslice)"
rm -rf "$S5NSDIR"

# (S5-4) RD5's boundary: a `recovered` record for an id with NO start and no
# finish anywhere (the hand-written shape). It is neither ranked NOR counted
# as priced -- cost_scan does not count it priced either, so the two passes
# still reconcile -- nothing is fabricated, and the report exits 0.
S5ORPHDIR="$(mktemp -d)"
mkdir -p "$S5ORPHDIR/.claude"
S5ORPHLEDGER="$S5ORPHDIR/.claude/loop-cost.jsonl"
printf '%s\n' '{"ts":1,"event":"recovered","invocation_id":"s5-orphan","slug":"s5-orphan-unit","total_tokens":9999,"token_source":"transcribed"}' > "$S5ORPHLEDGER"
S5ORPH_OUT="$(report "$S5ORPHDIR" s5-orphan-unit)"
expect "(S5-4) RD5 boundary: a recovered record with no start/finish is neither ranked nor counted priced, nothing fabricated, exit 0" "0 0 0 0" \
  "$(report_exit "$S5ORPHDIR" s5-orphan-unit) $(printf '%s\n' "$S5ORPH_OUT" | grep -c '9999') $(printf '%s\n' "$S5ORPH_OUT" | grep -c 'sit outside this ranking') $(printf '%s' "$(s5_unknown_check "$S5ORPHLEDGER" s5-orphan-unit)" | cut -d' ' -f1)"
rm -rf "$S5ORPHDIR"

# (S5-5) RD6, exactly-once: a SECOND identical `recovered` line for the same
# invocation_id yields one attribution -- every per-slice row byte-identical
# to the single-line fixture's, not a doubled token total.
S5DUPDIR="$(mktemp -d)"
mkdir -p "$S5DUPDIR/.claude"
S5DUPLEDGER="$S5DUPDIR/.claude/loop-cost.jsonl"
{
  cat "$S5MIXLEDGER"
  printf '%s\n' '{"ts":6,"event":"recovered","invocation_id":"s5mix-small","slug":"s5-mixed","total_tokens":10000,"token_source":"transcribed"}'
} > "$S5DUPLEDGER"
s5_rows() { # $1 ledger $2 slug
  # shellcheck source=/dev/null
  source "$SCRIPTS/cost-ledger-lib.sh"
  cost_slice_rows "$1" "$2" >/dev/null   # see s5_unknown_check on the redirect
  printf '%s' "$COST_SLICE_ROWS"
}
expect "(S5-5) RD6: a duplicated recovered line leaves every per-slice row identical to the single-line fixture" "" \
  "$(diff <(s5_rows "$S5MIXLEDGER" s5-mixed) <(s5_rows "$S5DUPLEDGER" s5-mixed))"
rm -rf "$S5DUPDIR"

# (S5-6) RD7, observed-wins inside THIS pass: an invocation with both a
# host-observed figure (12102) and a disagreeing transcribed one (11035) --
# the (S8-1) conflict shape, given a slice label here because the fixture at
# :1338 carries none and so produces no slice row at all to assert on. The
# slice row must hold the OBSERVED figure, never the transcribed one and never
# their sum, exactly as cost_scan resolves it.
S5CONFDIR="$(mktemp -d)"
mkdir -p "$S5CONFDIR/.claude"
S5CONFLEDGER="$S5CONFDIR/.claude/loop-cost.jsonl"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s5conf1","slug":"s5-conflict","slice":"S3","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s5conf1","slug":"s5-conflict","slice":"S3","phase":"build","agent":"loop-build","status":"completed","total_tokens":12102}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s5conf1","slug":"s5-conflict","total_tokens":11035,"token_source":"transcribed"}'
} > "$S5CONFLEDGER"
expect "(S5-6) RD7: with both figures present the slice row carries the observed one, not the transcribed one and not their sum" "S3	12102	1	0	0" \
  "$(s5_rows "$S5CONFLEDGER" s5-conflict)"
rm -rf "$S5CONFDIR"

# (S5-7) RD8 + RD10 together. RD8: a recovery-free fixture whose priced
# invocations all carry a slice is untouched by this slice -- byte-identical
# to the block S1 froze, so reading `recovered` records changed nothing for a
# run that produced none. RD10: on the now-complete mixed fixture the report
# and the gate name the SAME top slice, which is only interesting once the
# ranking includes transcribed figures -- before S5 the gate would have named
# a top slice from a population missing them.
S5MIX_JSON="$(budget_payload s5-mixed)"
S5MIX_GATE_ERR="$(CLAUDE_PROJECT_DIR="$S5MIXDIR" LARAVEL_LOOP_BUDGET_HARD=1000 gate_stderr "$S5MIX_JSON")"
S5MIX_REPORT_TOP="$(printf '%s\n' "$S5MIX_OUT" | sed -n '/^Slices/,/^$/p' | sed -n '2p' | awk '{print $1}')"
S5MIX_GATE_TOP="$(printf '%s\n' "$S5MIX_GATE_ERR" | grep -oE 'Re-slice "[^"]+"' | head -1 | sed 's/Re-slice "//; s/"$//')"
expect "(S5-7) RD8: recovery-free fixture still byte-identical to the frozen block; RD10: report and gate name the same top slice on the complete mixed fixture" " S1 S1" \
  "$(diff <(printf '%s' "$S1_FROZEN_CONC") <(printf '%s' "$CONC_OUT")) $S5MIX_REPORT_TOP $S5MIX_GATE_TOP"

rm -rf "$S5MIXDIR"

# ---------------------------------------------------------------------------
echo "docs: a restored dimension is documented and this gate's decisions are recorded (S6, recovered-figure-drops-slice-and-model, spec.md RD9)"

# The one README paragraph this slice adds, isolated once and reused by the
# three README cases below -- README is one line per paragraph, so the
# paragraph IS the grep unit, and (S6-4) needs it isolated to assert what it
# does NOT say.
S6_README_DIMS="$(grep -F 'A recovered record carries exactly one dimension' "$README_MD")"

# (S6-1) README states WHERE a restored dimension comes from -- the
# invocation's own start/finish records, never the recovered record. Before
# this slice README said a recovered figure is model-transcribed and stopped
# there, which left a reader unable to explain how a slice row can exist for a
# figure nobody measured.
expect "(S6-1) README states the restored dimensions come from the invocation's own start/finish records" "yes yes" \
  "$(printf '%s' "$S6_README_DIMS" | grep -qF 'comes from the invocation'"'"'s own `start` and `finish` records' && echo yes || echo no) $(printf '%s' "$S6_README_DIMS" | grep -qF 'neither carries those fields nor invents them' && echo yes || echo no)"

# (S6-2) README states the honest failure mode: a priced invocation whose own
# records name no slice is reported unattributed, never guessed -- and the
# orphan shape (a recovered record with no start/finish anywhere) is left out
# of both the ranking and the priced population.
expect "(S6-2) README states a priced invocation with no slice is reported unattributed, never guessed" "yes yes yes" \
  "$(printf '%s' "$S6_README_DIMS" | grep -qF 'nothing is guessed' && echo yes || echo no) $(printf '%s' "$S6_README_DIMS" | grep -qF 'reported as **unattributed**' && echo yes || echo no) $(printf '%s' "$S6_README_DIMS" | grep -qF 'no `start` or `finish` anywhere is left out of the ranking' && echo yes || echo no)"

# (S6-3) decisions.md records the reader-side answer WITH its reason -- the 21
# records already on disk, which is the fact that decided it. A future session
# reading decisions.md alone must find both, or the entry is a conclusion
# without an argument.
s6_decisions_check() {
  local bad=0 dec="$ROOT/docs/loop/decisions.md"
  grep -qi 'reader-side' "$dec" || bad=1
  grep -qi '21 recovered records already exist' "$dec" || bad=1
  grep -qi 'writer-side field' "$dec" || bad=1
  grep -qi 'transcript scraping' "$dec" || bad=1
  grep -qi 'fuzzy selector' "$dec" || bad=1
  echo $bad
}
expect "(S6-3) decisions.md records the reader-side answer, the 21 records as its reason, and what the pass forecloses" "0" \
  "$(s6_decisions_check)"

# (S6-4) RD9 guard, both halves. The report's coverage sentence still says a
# transcribed figure is `transcribed rather than host-observed` -- asserted on
# a live report, not on the source -- and README's new paragraph never
# describes a restored dimension as observed, in any form: it is the fields'
# provenance being explained, and calling any of it observed would undo
# exactly the distinction the sentence above preserves.
S6RD9DIR="$(mktemp -d)"
mkdir -p "$S6RD9DIR/.claude"
{
  printf '%s\n' '{"ts":1,"event":"start","invocation_id":"s6r1","slug":"s6-rd9","slice":"S1","phase":"build","agent":"loop-build"}'
  printf '%s\n' '{"ts":2,"event":"finish","invocation_id":"s6r1","slug":"s6-rd9","slice":"S1","phase":"build","agent":"loop-build","status":"async_launched"}'
  printf '%s\n' '{"ts":3,"event":"recovered","invocation_id":"s6r1","slug":"s6-rd9","total_tokens":1234,"token_source":"transcribed"}'
} > "$S6RD9DIR/.claude/loop-cost.jsonl"
S6RD9_OUT="$(report "$S6RD9DIR" s6-rd9)"
expect "(S6-4) RD9: the coverage sentence still says transcribed rather than host-observed, and README's restored-dimension paragraph never calls one observed" "yes 0" \
  "$(printf '%s\n' "$S6RD9_OUT" | grep -qF 'transcribed rather than host-observed' && echo yes || echo no) $(printf '%s' "$S6_README_DIMS" | grep -ci 'observed')"
rm -rf "$S6RD9DIR"

# ---------------------------------------------------------------------------
# S1 (stale-evict-lock-permanently-defeats-the-cap, spec.md SL1) -- an
# interrupted holder leaves .claude/loop-cost-evict.lock behind and nothing
# in either writer ever removes it, so from then on every later invocation
# polls, gives up, and appends anyway (L7) without ever converging: the cap
# is not enforced again for as long as that directory exists. Both writers
# carry an independent copy of the same mkdir/rmdir mutex (record-cost-
# event.sh:205, record-recovered-cost.sh:99), so a reader of either header
# must learn this without reading the other file. One CONJOINED case, four
# labelled tokens -- the EVICTION_HEADER_FLAT house shape -- because two
# separate header cases would let one writer's note drift while the other
# stayed green.
HOOK_ORPHAN_HEADER_FLAT="$(sed -n '/^# Bound + oldest-first eviction/,/^# Rework attribution/p' "$ROOT/scripts/record-cost-event.sh" | tr '#' ' ' | tr '\n' ' ' | tr -s ' ')"
RECOVERED_ORPHAN_HEADER_FLAT="$(sed -n '/^# Same bounded-append discipline/,/^# Zero new dependency/p' "$ROOT/scripts/record-recovered-cost.sh" | tr '#' ' ' | tr '\n' ' ' | tr -s ' ')"
expect "S1: an orphaned lock's effect on the cap, the remedy, and the lock's path are named in the hook writer's header, and the recovered CLI's header carries the same note" \
  "orphan-case yes, remedy yes, lock-path yes, recovered yes" \
  "orphan-case $(printf '%s' "$HOOK_ORPHAN_HEADER_FLAT" | grep -qi 'left behind' && printf '%s' "$HOOK_ORPHAN_HEADER_FLAT" | grep -qi 'not enforced again' && echo yes || echo no), remedy $(printf '%s' "$HOOK_ORPHAN_HEADER_FLAT" | grep -qi 'no run is active' && echo yes || echo no), lock-path $(printf '%s' "$HOOK_ORPHAN_HEADER_FLAT" | grep -qF '.claude/loop-cost-evict.lock' && echo yes || echo no), recovered $(printf '%s' "$RECOVERED_ORPHAN_HEADER_FLAT" | grep -qi 'not enforced again' && printf '%s' "$RECOVERED_ORPHAN_HEADER_FLAT" | grep -qF '.claude/loop-cost-evict.lock' && echo yes || echo no)"

# S1 (spec.md SL1) -- the claim-word guard: no SENTENCE anywhere in the
# pinned surfaces below names the lock (or "orphan"/"stale lock") and also
# makes a bare, ungoverned claim that this leak is fixed, closed, resolved,
# or prevented. Sentence-scoped (flatten each file, split on '. '), never
# file-scoped, because a file-wide grep for "fixed" matches half the
# repository and would be red for the wrong reason.
#
# Two exclusions, both narrow on purpose, replacing an earlier design that
# was too broad in both directions (caught in review before this landed):
#   - spec.md and slices.md are excluded BY PATH, not by content. Both
#     files define this very rule in the words it forbids ("...also
#     contains fixed / closed / resolved / prevented"), which is a property
#     of those two documents, not a property of sentences that happen to
#     name all four words -- a count-based exemption keyed on "all four
#     present" is an exemption an author controls, which is the wrong
#     shape for a guard.
#   - A negation EXEMPTS A CLAIM WORD ONLY WHEN IT GOVERNS THAT WORD --
#     within 3 tokens immediately before it ("not fixed", "never closed",
#     "no longer prevented", "cannot be resolved"). A negation anywhere
#     else in the same sentence does not exempt: "fixed, so no further
#     action is required" is a bare claim with an unrelated, later
#     negation, and it is the single most likely way a real overclaim gets
#     written -- a sentence-wide negation check would let it through.
is_negation_token() {
  case "$1" in
    never|not|no|cannot|isn|doesn|wasn|hasn|won|aren|weren|cant|nor) return 0 ;;
    *) return 1 ;;
  esac
}
claim_word_guard_check() {
  local bad=0 f base flat sentence norm i n w
  local files="$ROOT/scripts/record-cost-event.sh $ROOT/scripts/record-recovered-cost.sh $ROOT/scripts/cost-report.sh $ROOT/README.md $ROOT/docs/loop/decisions.md"
  for f in $files "$ROOT"/docs/loop/stale-evict-lock-permanently-defeats-the-cap/*.md; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in
      spec.md|slices.md) continue ;;
    esac
    flat="$(tr '\n' ' ' < "$f" | tr -s ' ')"
    while IFS= read -r sentence; do
      [ -z "$sentence" ] && continue
      if printf '%s' "$sentence" | grep -qiE 'loop-cost-evict\.lock|orphan|stale lock'; then
        norm="$(printf '%s' "$sentence" | tr 'A-Z' 'a-z' | tr -s '.,;:!?()"'"'"'\`*_/-' ' ' | tr -s ' ')"
        # shellcheck disable=SC2206
        local wordsarr=($norm)
        n=${#wordsarr[@]}
        for ((i = 0; i < n; i++)); do
          w="${wordsarr[$i]}"
          case "$w" in
            fixed|closed|resolved|prevented)
              local governed=0 j back
              for j in 1 2 3; do
                back=$((i - j))
                [ "$back" -lt 0 ] && break
                is_negation_token "${wordsarr[$back]}" && { governed=1; break; }
              done
              [ "$governed" -eq 0 ] && bad=1
              ;;
          esac
        done
      fi
    done <<SENTENCES
$(printf '%s' "$flat" | awk 'BEGIN{RS="\\. "}{print}')
SENTENCES
  done
  echo "$bad"
}
expect "S1: no sentence anywhere in the pinned surfaces names the lock/orphan and makes a bare, ungoverned claim that the leak is fixed, closed, resolved, or prevented" \
  "0" "$(claim_word_guard_check)"

# ---------------------------------------------------------------------------
# S8 (spec.md, §Development case count) -- this MUST be the last case in the
# file. The harness's actual total is only known once every case above has
# run, including any inside a loop that fires more than once per source
# line -- a static grep over `expect "` call sites undercounts those, so the
# only honest source of truth is the live PASS/FAIL tally this file has kept
# all along. This case's own contribution is the last one counted, so
# PASS+FAIL+1 here *is* the grand total the closing printf below reports.
echo
echo "docs (case count)"
DEV_SECTION="$(sed -n '/^## Development/,/^## /p' "$ROOT/README.md")"
README_CASE_COUNT="$(printf '%s\n' "$DEV_SECTION" | grep -oE '[0-9]+ cases' | grep -oE '[0-9]+')"
EXPECTED_TOTAL=$((PASS + FAIL + 1))
expect "docs: README's Development section case count equals the harness's actual total" \
  "$EXPECTED_TOTAL" "${README_CASE_COUNT:-}"

echo
echo "----------------------------------------"
printf 'total: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL GREEN" || echo "FAILURES PRESENT"
exit "$FAIL"
