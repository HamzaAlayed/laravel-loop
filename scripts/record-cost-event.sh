#!/usr/bin/env bash
# Cost ledger: writes one JSONL record per Agent/Task lifecycle signal to
# .claude/loop-cost.jsonl, so a completed /loop run can be priced per
# invocation, per phase, and per slice -- see
# docs/loop/laravel-loop-cost-requirements.md R1.1. Nobody running this
# plugin can otherwise answer "what did that unit of work cost".
#
# Wired as PreToolUse (writes a "start" record) and PostToolUse (writes a
# "finish" record) on matcher "Agent|Task" (Task is the pre-2.1.63 alias of
# Agent). SubagentStop is deliberately NOT registered here: laravel-team's
# emit-agent-events.sh (running alongside this plugin in this very repo)
# shows it is a SECOND finish signal for the same invocation and carries no
# tokens -- a `subagent_stop` record with null tokens, followed later by a
# `completed` PostToolUse record carrying the real totalTokens/
# totalDurationMs. Registering only PostToolUse here means "exactly one
# finish record per invocation" holds by construction. See "Exactly-once
# under concurrency" below for how a second finish signal -- SubagentStop or
# otherwise -- is handled if it reaches this script anyway (S3).
#
# The `Unit:`/`Slice:` envelope lines (loop-protocol) live in
# `tool_input.prompt` -- the actual text handed to the subagent -- not in
# `tool_input.description`, which is a short label. This was unconfirmed by
# this repo's own committed evidence (spec.md E1/E2 prove `description` and
# `subagent_type` are populated; they prove nothing about `prompt`), so it
# was checked directly before writing any extraction logic, per this
# slice's early-exit rule: a real Agent tool_use recorded on this machine's
# own Claude Code session transcripts has input keys {subagent_type,
# description, run_in_background, prompt}, and `prompt` carries the full
# brief. `tool_use_id` -- confirmed present in hook payloads by inspecting
# the installed `claude` binary's own string table -- is the correlation
# key between one invocation's start and finish record (S3 dedupes on it).
#
# Zero dependency: bash + coreutils, degrading jq -> python3 -> a safe
# no-op. No parser available means no write at all, never a raw or partial
# JSON line. Exits 0 on every path, including its own internal errors:
# cost accounting must never block, delay, or alter a spawn.
#
# Disable entirely: LARAVEL_LOOP_COST_LEDGER=0 (or "off"), matching the
# LARAVEL_LOOP_REFINE_CAP=0 convention.
#
# Exactly-once under concurrency (S3, spec.md L1/L5/L9). No flock -- it is
# not present on macOS by default and this repo is bash + coreutils only.
# Two guarantees instead of one lock:
#   1. Atomic append. Each record is assembled entirely in memory and
#      emitted with a single `>>` write, and every field that could grow
#      unboundedly is truncated so the line stays comfortably inside the
#      size a single write() to an O_APPEND-opened file is atomic at on a
#      local filesystem (kept well under 4096 bytes; see "oversize record"
#      near the bottom for the fallback if it ever isn't). This is what
#      makes L5 hold: N concurrent finishes for distinct invocations land as
#      N intact lines, never interleaved or torn, because no writer's append
#      is ever split across two syscalls.
#   2. Exactly-once via mkdir. `mkdir "$FINISHED_DIR/$id"` is atomic across
#      processes on any POSIX filesystem -- exactly one caller can ever
#      create a given directory name -- so "has this invocation's finish
#      already been recorded" is answered by one syscall, with no lock file,
#      no spin-wait, and no window where two writers both believe they own
#      it. Only finish signals are deduped: L9 is specifically about
#      finishes, and a duplicate start is neither tested nor attempted here.
#      A second finish for a key already marked finished -- the same
#      payload delivered twice, the hook wired both as a plugin and by hand,
#      or a genuine second host signal for one invocation -- is discarded
#      silently, exit 0. If the finished-marker directory can't even be
#      created (e.g. an unwritable .claude/), dedup is skipped rather than
#      blocking the write: a possible duplicate is preferable to a
#      guaranteed drop, so L7 (never block) outranks L9 in that one failure
#      mode.
#
# SubagentStop, if it ever reaches this script, never writes a line of its
# own, and is not registered in hooks.json for exactly this reason: E4
# established it carries no tokens, and this repo's own real evidence
# (.claude/agents-board.jsonl) shows it can arrive either BEFORE the
# token-carrying PostToolUse finish (a normal sync completion) or AFTER a
# null-token async_launched PostToolUse finish (an async one) -- in both
# orderings PostToolUse is the useful signal. Because this script can only
# append and never edit an already-written line, there is no ordering-safe
# way to let a SubagentStop line ever outrank a PostToolUse one once both
# exist. Making PostToolUse the sole source of a finish record sidesteps
# that: "one finish record, and it is the one carrying tokens" (S3 case c)
# holds by construction rather than by a race a lock would otherwise have to
# settle. Handled explicitly below -- not left to the tool_name gate to
# discard by accident -- so a reader, or someone who wires SubagentStop
# manually, can see this was a considered decision.
#
# Bound + oldest-first eviction (S4, spec.md H2-H5). The ledger is capped at
# LARAVEL_LOOP_COST_MAX_LINES lines (default 5000; a non-numeric value falls
# back to that default rather than disabling the bound or crashing -- same
# parser shape as enforce-refine-cap.sh's CAP). Every invocation that appends
# a line then checks whether the ledger is over cap and, if so, evicts the
# oldest lines itself -- there is no separate long-running evictor process.
#
# No flock (absent on macOS by default; this repo is bash + coreutils only),
# so eviction uses the same primitive as S3's dedup: a `mkdir`-based mutex
# (.claude/loop-cost-evict.lock), held only by whichever invocation is
# currently trimming the file. Appenders never contend for that lock and
# never block on it (L7) -- they poll briefly for it to clear, then append
# regardless of whether it did, because cost accounting that can stall a
# spawn is worse than a ledger that sits slightly over cap for a moment.
#
# Eviction itself never truncates the file to empty, not even transiently
# (H3): the trimmed content is written to a fresh temp file first (`tail -n
# $MAX_LINES`, always non-empty whenever eviction runs at all) and only then
# swapped into place with `mv`, an atomic rename on a local filesystem. A
# reader that opens the ledger mid-swap gets the pre-eviction file or the
# post-eviction file, in full, never a truncated or empty one. The eviction
# loop re-checks the line count a bounded number of times before releasing
# the lock, so a burst of appends that lands during the trim gets caught up
# rather than silently re-growing the file past cap the moment the lock
# clears.
#
# The ledger being absent is normal, not an error (H5): every append below
# already does `mkdir -p` + `>>`, which recreates a deleted file from
# nothing, so eviction needs no special handling for "file missing" beyond
# what the append path already does.

set -uo pipefail

INPUT="$(cat)" || exit 0

case "${LARAVEL_LOOP_COST_LEDGER:-}" in
  0|off|OFF|false|FALSE) exit 0 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
DIR="$ROOT/.claude"
OUT="$DIR/loop-cost.jsonl"
FINISHED_DIR="$DIR/loop-cost-finished"
EVICT_LOCK="$DIR/loop-cost-evict.lock"

# Bound parser (H2): default 5000, non-numeric falls back to it -- same shape
# as enforce-refine-cap.sh's CAP parser.
MAX_LINES="${LARAVEL_LOOP_COST_MAX_LINES:-5000}"
case "$MAX_LINES" in
  ''|*[!0-9]*) MAX_LINES=5000 ;;
esac

HAVE_JQ=0
HAVE_PY=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1
command -v python3 >/dev/null 2>&1 && HAVE_PY=1
if [ "$HAVE_JQ" -eq 0 ] && [ "$HAVE_PY" -eq 0 ]; then
  exit 0
fi

# Extract a string field. Degrades jq -> python3 (never called with both
# absent -- guarded above). Empty on any parse error, missing key, or a
# non-string value along the path.
extract() {
  local jq_path="$1" py_expr="$2"
  if [ "$HAVE_JQ" -eq 1 ]; then
    printf '%s' "$INPUT" | jq -r "$jq_path // empty" 2>/dev/null
  elif [ "$HAVE_PY" -eq 1 ]; then
    printf '%s' "$INPUT" | python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
    v=$py_expr
    print(v if isinstance(v,str) else (json.dumps(v) if v else ''))
except Exception:
    pass" 2>/dev/null || true
  fi
}

# Extract a numeric field. Distinct from extract() above: a payload value of
# 0 is a measurement, not an absence (L3), and extract()'s python branch
# treats 0 as falsy and would print '' for it. This one never does.
extract_num() {
  local jq_path="$1" py_expr="$2"
  if [ "$HAVE_JQ" -eq 1 ]; then
    printf '%s' "$INPUT" | jq -r "($jq_path) as \$v | if (\$v|type)==\"number\" then (\$v|tostring) else empty end" 2>/dev/null
  elif [ "$HAVE_PY" -eq 1 ]; then
    printf '%s' "$INPUT" | python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
    v=$py_expr
    print(v if isinstance(v,(int,float)) and not isinstance(v,bool) else '')
except Exception:
    pass" 2>/dev/null || true
  fi
}

HOOK_EVENT="$(extract '.hook_event_name' 'd.get("hook_event_name","")')"
TOOL_NAME="$(extract '.tool_name' 'd.get("tool_name","")')"

# HOOK_EVENT is checked before TOOL_NAME so SubagentStop -- which carries no
# tool_name/tool_input at all -- is handled explicitly rather than falling
# into the tool_name gate below by accident (see header: "never writes a
# line of its own").
case "$HOOK_EVENT" in
  PreToolUse)   EVENT_TYPE="start" ;;
  PostToolUse)  EVENT_TYPE="finish" ;;
  SubagentStop) exit 0 ;;
  *) exit 0 ;;
esac

case "$TOOL_NAME" in
  Agent|Task) : ;;
  *) exit 0 ;;
esac

SESSION_ID="$(extract '.session_id' 'd.get("session_id","")')"
SUBAGENT_TYPE="$(extract '.tool_input.subagent_type' 'd.get("tool_input",{}).get("subagent_type","")')"
DESCRIPTION="$(extract '.tool_input.description' 'd.get("tool_input",{}).get("description","")')"
PROMPT="$(extract '.tool_input.prompt' 'd.get("tool_input",{}).get("prompt","")')"
TOOL_USE_ID="$(extract '.tool_use_id' 'd.get("tool_use_id","")')"

# --- slug / slice: an `Unit:`/`Slice:` line in the prompt, then the same
# line in description, never guessed from cwd or a last-seen unit (L4). ----
find_label() {
  local text="$1" label="$2"
  printf '%s\n' "$text" | sed -n -E "/^${label}:[[:space:]]+/{s/^${label}:[[:space:]]+//; s/[[:space:]]+\$//; p; q;}" 2>/dev/null
}

SLUG="$(find_label "$PROMPT" "Unit")"
[ -z "$SLUG" ] && SLUG="$(find_label "$DESCRIPTION" "Unit")"
[ -z "$SLUG" ] && SLUG="unknown"
SLUG="${SLUG:0:200}"

SLICE="$(find_label "$PROMPT" "Slice")"
[ -z "$SLICE" ] && SLICE="$(find_label "$DESCRIPTION" "Slice")"
SLICE="${SLICE:0:50}"

# --- agent / phase ----------------------------------------------------------
AGENT="$(printf '%s' "$SUBAGENT_TYPE" | sed -E 's/^.*://')"
[ -z "$AGENT" ] && AGENT="unknown"

case "$AGENT" in
  loop-spec)   PHASE="spec" ;;
  loop-slice)  PHASE="slice" ;;
  loop-build)  PHASE="build" ;;
  loop-verify) PHASE="verify" ;;
  *)           PHASE="unknown" ;;
esac

# --- invocation id: the same tool_use_id fires on both this invocation's
# PreToolUse and PostToolUse (S3 dedupes finish signals on it). Composite
# fallback only for a payload too old or malformed to carry one. -----------
if [ -n "$TOOL_USE_ID" ]; then
  INVOCATION_ID="$TOOL_USE_ID"
elif [ -n "$SESSION_ID$SUBAGENT_TYPE$DESCRIPTION" ]; then
  INVOCATION_ID="${SESSION_ID}:${SUBAGENT_TYPE}:${DESCRIPTION}"
else
  INVOCATION_ID="unknown"
fi

# --- finish-only fields: best-effort split/cache-read tokens (D1) --------
STATUS=""; DURATION=""; TOTAL_TOKENS=""; INPUT_TOKENS=""; OUTPUT_TOKENS=""
CACHE_READ_TOKENS=""; OBSERVED_MODEL=""
if [ "$EVENT_TYPE" = "finish" ]; then
  STATUS="$(extract '.tool_response.status' 'd.get("tool_response",{}).get("status","")')"
  DURATION="$(extract_num '.tool_response.totalDurationMs' 'd.get("tool_response",{}).get("totalDurationMs")')"
  TOTAL_TOKENS="$(extract_num '.tool_response.totalTokens' 'd.get("tool_response",{}).get("totalTokens")')"
  INPUT_TOKENS="$(extract_num '.tool_response.usage.input_tokens // .tool_response.input_tokens' 'd.get("tool_response",{}).get("usage",{}).get("input_tokens")')"
  OUTPUT_TOKENS="$(extract_num '.tool_response.usage.output_tokens // .tool_response.output_tokens' 'd.get("tool_response",{}).get("usage",{}).get("output_tokens")')"
  CACHE_READ_TOKENS="$(extract_num '.tool_response.usage.cache_read_input_tokens // .tool_response.cache_read_input_tokens' 'd.get("tool_response",{}).get("usage",{}).get("cache_read_input_tokens")')"
  OBSERVED_MODEL="$(extract '.tool_response.model // .tool_response.usage.model' 'd.get("tool_response",{}).get("model") or d.get("tool_response",{}).get("usage",{}).get("model") or ""')"
  STATUS="${STATUS:0:200}"
fi

# --- model / model_source: observed beats derived beats unknown (L11). The
# agent frontmatter (model: sonnet|opus) is read only when nothing was
# observed on this invocation, and the ledger always says which it was. ----
MODEL=""
MODEL_SOURCE="unknown"
if [ -n "$OBSERVED_MODEL" ]; then
  MODEL="$OBSERVED_MODEL"
  MODEL_SOURCE="observed"
else
  AGENT_ROOT="${CLAUDE_PLUGIN_ROOT:-$ROOT}"
  AGENT_MD="$AGENT_ROOT/agents/$AGENT.md"
  if [ -f "$AGENT_MD" ]; then
    DERIVED_MODEL="$(sed -n -E '/^model:[[:space:]]*/{s/^model:[[:space:]]*//; s/[[:space:]]+$//; p; q;}' "$AGENT_MD" 2>/dev/null)"
    if [ -n "$DERIVED_MODEL" ]; then
      MODEL="$DERIVED_MODEL"
      MODEL_SOURCE="derived"
    fi
  fi
fi

num_or_null() {
  case "$1" in
    ''|*[!0-9]*) printf 'null' ;;
    *) printf '%s' "$1" ;;
  esac
}

TS="$(date +%s)"
DURATION_JSON="$(num_or_null "$DURATION")"
TOTAL_TOKENS_JSON="$(num_or_null "$TOTAL_TOKENS")"
INPUT_TOKENS_JSON="$(num_or_null "$INPUT_TOKENS")"
OUTPUT_TOKENS_JSON="$(num_or_null "$OUTPUT_TOKENS")"
CACHE_READ_TOKENS_JSON="$(num_or_null "$CACHE_READ_TOKENS")"

LINE=""
if [ "$HAVE_JQ" -eq 1 ]; then
  LINE="$(jq -nc \
    --argjson ts "$TS" \
    --arg event "$EVENT_TYPE" \
    --arg invocation_id "$INVOCATION_ID" \
    --arg session_id "$SESSION_ID" \
    --arg slug "$SLUG" \
    --arg slice "$SLICE" \
    --arg phase "$PHASE" \
    --arg agent "$AGENT" \
    --arg model "$MODEL" \
    --arg model_source "$MODEL_SOURCE" \
    --arg status "$STATUS" \
    --argjson duration_ms "$DURATION_JSON" \
    --argjson total_tokens "$TOTAL_TOKENS_JSON" \
    --argjson input_tokens "$INPUT_TOKENS_JSON" \
    --argjson output_tokens "$OUTPUT_TOKENS_JSON" \
    --argjson cache_read_tokens "$CACHE_READ_TOKENS_JSON" \
    'def z: if . == "" then null else . end;
     {ts:$ts, event:$event, invocation_id:($invocation_id|z), session_id:($session_id|z),
      slug:$slug, slice:($slice|z), phase:$phase, agent:$agent,
      model:($model|z), model_source:$model_source, status:($status|z),
      duration_ms:$duration_ms, total_tokens:$total_tokens,
      input_tokens:$input_tokens, output_tokens:$output_tokens,
      cache_read_tokens:$cache_read_tokens}
     | with_entries(select(.value != null))' 2>/dev/null)"
elif [ "$HAVE_PY" -eq 1 ]; then
  LINE="$(python3 - "$TS" "$EVENT_TYPE" "$INVOCATION_ID" "$SESSION_ID" "$SLUG" "$SLICE" \
    "$PHASE" "$AGENT" "$MODEL" "$MODEL_SOURCE" "$STATUS" \
    "$DURATION_JSON" "$TOTAL_TOKENS_JSON" "$INPUT_TOKENS_JSON" "$OUTPUT_TOKENS_JSON" \
    "$CACHE_READ_TOKENS_JSON" <<'PY' 2>/dev/null
import sys, json


def num(s):
    return None if s == "null" else int(s)


def z(s):
    return None if s == "" else s


(ts, event, invocation_id, session_id, slug, slice_, phase, agent, model,
 model_source, status, duration_ms, total_tokens, input_tokens,
 output_tokens, cache_read_tokens) = sys.argv[1:17]

record = {
    "ts": int(ts),
    "event": event,
    "invocation_id": z(invocation_id),
    "session_id": z(session_id),
    "slug": slug,
    "slice": z(slice_),
    "phase": phase,
    "agent": agent,
    "model": z(model),
    "model_source": model_source,
    "status": z(status),
    "duration_ms": num(duration_ms),
    "total_tokens": num(total_tokens),
    "input_tokens": num(input_tokens),
    "output_tokens": num(output_tokens),
    "cache_read_tokens": num(cache_read_tokens),
}
record = {k: v for k, v in record.items() if v is not None}
print(json.dumps(record, separators=(",", ":")))
PY
)"
fi

[ -z "$LINE" ] && exit 0

# --- oversize record: truncate or omit rather than split a line (S3). The
# per-field truncation above (SLUG, SLICE, STATUS) makes this vanishingly
# unlikely in practice; this is the last-resort net so a pathological
# payload still never produces a line that could straddle two writes. -----
if [ "${#LINE}" -ge 4096 ]; then
  LINE=""
  if [ "$HAVE_JQ" -eq 1 ]; then
    LINE="$(jq -nc \
      --argjson ts "$TS" \
      --arg event "$EVENT_TYPE" \
      --arg invocation_id "$INVOCATION_ID" \
      --arg slug "${SLUG:0:80}" \
      --arg phase "$PHASE" \
      --arg agent "$AGENT" \
      '{ts:$ts, event:$event, invocation_id:$invocation_id, slug:$slug,
        phase:$phase, agent:$agent, status:"line_too_long"}' 2>/dev/null)"
  elif [ "$HAVE_PY" -eq 1 ]; then
    LINE="$(python3 - "$TS" "$EVENT_TYPE" "$INVOCATION_ID" "${SLUG:0:80}" "$PHASE" "$AGENT" <<'PY' 2>/dev/null
import json, sys
ts, event, invocation_id, slug, phase, agent = sys.argv[1:7]
print(json.dumps({"ts": int(ts), "event": event, "invocation_id": invocation_id,
                   "slug": slug, "phase": phase, "agent": agent,
                   "status": "line_too_long"}, separators=(",", ":")))
PY
)"
  fi
  [ -z "$LINE" ] && exit 0
fi

# --- exactly-once: only finish signals are deduped (L9); see header for why
# a mkdir'd directory name, not flock, is the atomic primitive here. -------
if [ "$EVENT_TYPE" = "finish" ]; then
  SAFE_ID="$(printf '%s' "$INVOCATION_ID" | tr -c 'A-Za-z0-9_.-' '_')"
  SAFE_ID="${SAFE_ID:0:200}"
  [ -z "$SAFE_ID" ] && SAFE_ID="unknown"
  if mkdir -p "$FINISHED_DIR" 2>/dev/null; then
    if ! mkdir "$FINISHED_DIR/$SAFE_ID" 2>/dev/null; then
      # A finish for this invocation was already recorded: duplicate
      # delivery, double registration, or a second host signal for one
      # invocation (E4/L9). Discard silently.
      exit 0
    fi
  fi
  # else: dedup infra unavailable (e.g. unwritable .claude/) -- fall through
  # and attempt the write anyway rather than dropping a possible first-time
  # record (L7 outranks L9 here).
fi

# --- bound the ledger (H2/H3): give a concurrent eviction a brief, bounded
# window to finish before this append's own open() lands, without ever
# blocking on it -- see header. This only ever shortens, never removes, the
# already-small race between an append's open() and an eviction's rename. --
BACKOFF=0
while [ -d "$EVICT_LOCK" ] && [ "$BACKOFF" -lt 5 ]; do
  sleep 0.02
  BACKOFF=$((BACKOFF + 1))
done

mkdir -p "$DIR" 2>/dev/null || exit 0
printf '%s\n' "$LINE" >> "$OUT" 2>/dev/null

# --- oldest-first eviction, in place, never emptying the file even
# transiently (H2/H3). Only the invocation that finds the ledger over cap
# does the trimming; a `mkdir` on EVICT_LOCK is the (non-blocking, evictor-
# only) mutex that keeps two invocations from trimming at once. If the lock
# can't be acquired, another invocation is already evicting -- this one
# leaves the ledger as-is rather than waiting (L7 outranks H2 here too: a
# file that sits briefly over cap beats a spawn that stalls). -------------
if mkdir "$EVICT_LOCK" 2>/dev/null; then
  ATTEMPT=0
  while [ "$ATTEMPT" -lt 5 ]; do
    ATTEMPT=$((ATTEMPT + 1))
    COUNT="$(wc -l < "$OUT" 2>/dev/null | tr -d ' ')"
    case "$COUNT" in ''|*[!0-9]*) break ;; esac
    [ "$COUNT" -le "$MAX_LINES" ] && break
    TMP="$(mktemp "$OUT.evict.XXXXXX" 2>/dev/null)" || break
    if ! tail -n "$MAX_LINES" "$OUT" > "$TMP" 2>/dev/null || [ ! -s "$TMP" ]; then
      rm -f "$TMP"
      break
    fi
    mv -f "$TMP" "$OUT" 2>/dev/null || rm -f "$TMP"
  done
  rmdir "$EVICT_LOCK" 2>/dev/null
fi

exit 0
