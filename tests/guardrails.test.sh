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

warn_exit() { # $1 json
  printf '%s' "$1" | bash "$SCRIPTS/warn-full-suite.sh" >/dev/null 2>&1
  echo $?
}
warn_stderr() { # $1 json
  printf '%s' "$1" | bash "$SCRIPTS/warn-full-suite.sh" 2>&1 1>/dev/null
}
warned() { # $1 json -> "warn" or "silent"
  printf '%s' "$(warn_stderr "$1")" | grep -qi 'warn' && echo warn || echo silent
}

# -- (a) unfiltered `php artisan test` from loop-build warns AND exits 0 --
# exit code and stderr asserted as separate cases (FS1).
FS_A="$(suite_json loop-build "php artisan test")"
expect "FS1: unfiltered 'php artisan test' from loop-build exits 0" "0" "$(warn_exit "$FS_A")"
expect "FS1: unfiltered 'php artisan test' from loop-build warns on stderr" "warn" "$(warned "$FS_A")"

# -- (b) Sail-prefixed form warns too (FS4) --
FS_B="$(suite_json loop-build "./vendor/bin/sail artisan test")"
expect "FS4: unfiltered sail-prefixed 'artisan test' exits 0" "0" "$(warn_exit "$FS_B")"
expect "FS4: unfiltered sail-prefixed 'artisan test' warns" "warn" "$(warned "$FS_B")"

# -- (c) a filter, or a path/file argument, means filtered: never warns (FS4) --
FS_C1="$(suite_json loop-build "php artisan test --compact --filter=InvoiceTest")"
expect "FS4: filtered 'php artisan test --filter=' does not warn" "silent" "$(warned "$FS_C1")"
expect "FS4: filtered 'php artisan test --filter=' exits 0" "0" "$(warn_exit "$FS_C1")"

FS_C2="$(suite_json loop-build "vendor/bin/pest tests/Feature/InvoiceTest.php")"
expect "FS4: 'vendor/bin/pest' with a path argument does not warn" "silent" "$(warned "$FS_C2")"
expect "FS4: 'vendor/bin/pest' with a path argument exits 0" "0" "$(warn_exit "$FS_C2")"

# -- (d) never warns on loop-verify or the main thread (FS2) -- two cases --
FS_D1="$(suite_json loop-verify "php artisan test")"
expect "FS2: unfiltered run from loop-verify does not warn" "silent" "$(warned "$FS_D1")"
expect "FS2: unfiltered run from loop-verify exits 0" "0" "$(warn_exit "$FS_D1")"

FS_D2="$(suite_json "" "php artisan test")"
expect "FS2: unfiltered run with no agent_type (main thread) does not warn" "silent" "$(warned "$FS_D2")"
expect "FS2: unfiltered run with no agent_type exits 0" "0" "$(warn_exit "$FS_D2")"

# -- (e) escape hatch silences it; the warning names the variable (FS3) --
expect "FS3: LARAVEL_LOOP_ALLOW_FULL_SUITE=1 silences the warning" "silent" \
  "$(LARAVEL_LOOP_ALLOW_FULL_SUITE=1 warned "$FS_A")"
expect "FS3: LARAVEL_LOOP_ALLOW_FULL_SUITE=1 still exits 0" "0" \
  "$(LARAVEL_LOOP_ALLOW_FULL_SUITE=1 warn_exit "$FS_A")"
expect "FS3: the warning names LARAVEL_LOOP_ALLOW_FULL_SUITE" "found" \
  "$(printf '%s' "$(warn_stderr "$FS_A")" | grep -q 'LARAVEL_LOOP_ALLOW_FULL_SUITE' && echo found || echo missing)"

# -- (f) false positives never warn (FS5) -- asserted per command --
FS_F1="$(suite_json loop-build "ls tests/")"
expect "FS5: 'ls tests/' from loop-build does not warn" "silent" "$(warned "$FS_F1")"
expect "FS5: 'ls tests/' from loop-build exits 0" "0" "$(warn_exit "$FS_F1")"

FS_F2="$(suite_json loop-build "grep -r foo tests/")"
expect "FS5: 'grep -r foo tests/' from loop-build does not warn" "silent" "$(warned "$FS_F2")"
expect "FS5: 'grep -r foo tests/' from loop-build exits 0" "0" "$(warn_exit "$FS_F2")"

FS_F3="$(suite_json loop-build "git add tests/InvoiceTest.php")"
expect "FS5: 'git add tests/InvoiceTest.php' from loop-build does not warn" "silent" "$(warned "$FS_F3")"
expect "FS5: 'git add tests/InvoiceTest.php' from loop-build exits 0" "0" "$(warn_exit "$FS_F3")"

# -- (g) exit 0 on every degenerate input, asserted individually (FS6) --
expect "FS6: malformed payload exits 0" "0" \
  "$(warn_exit '{"agent_type":"loop-build","tool_input": not valid json')"
expect "FS6: empty payload exits 0" "0" "$(warn_exit '')"

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

writelog() { # $1 CLAUDE_PROJECT_DIR $2 slug
  CLAUDE_PROJECT_DIR="$1" bash "$SCRIPTS/write-cost-log-section.sh" "$2" >/dev/null 2>&1
}
writelog_exit() { # $1 CLAUDE_PROJECT_DIR $2 slug
  CLAUDE_PROJECT_DIR="$1" bash "$SCRIPTS/write-cost-log-section.sh" "$2" >/dev/null 2>&1
  echo $?
}
writelog_stderr() { # $1 CLAUDE_PROJECT_DIR $2 slug
  CLAUDE_PROJECT_DIR="$1" bash "$SCRIPTS/write-cost-log-section.sh" "$2" 2>&1 1>/dev/null
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
expect "(b) exactly one '## Cost' heading after a second run (DL4)" "1" "$(grep -cx '## Cost' "$LOGFILE")"
expect "(b) the file is byte-identical across the second run (DL4, CV7)" "" \
  "$(diff <(printf '%s' "$LOG_OUT1") <(printf '%s' "$LOG_OUT2"))"
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
