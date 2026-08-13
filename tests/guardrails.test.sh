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
