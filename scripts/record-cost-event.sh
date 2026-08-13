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
# finish record per invocation" holds by construction; deduping a second
# finish signal, once SubagentStop is added, is later work (see slices.md
# S3), not this script's job today.
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

set -uo pipefail

INPUT="$(cat)" || exit 0

case "${LARAVEL_LOOP_COST_LEDGER:-}" in
  0|off|OFF|false|FALSE) exit 0 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

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

case "$TOOL_NAME" in
  Agent|Task) : ;;
  *) exit 0 ;;
esac

case "$HOOK_EVENT" in
  PreToolUse)  EVENT_TYPE="start" ;;
  PostToolUse) EVENT_TYPE="finish" ;;
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

SLICE="$(find_label "$PROMPT" "Slice")"
[ -z "$SLICE" ] && SLICE="$(find_label "$DESCRIPTION" "Slice")"

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

DIR="$ROOT/.claude"
OUT="$DIR/loop-cost.jsonl"

mkdir -p "$DIR" 2>/dev/null || exit 0
printf '%s\n' "$LINE" >> "$OUT" 2>/dev/null

exit 0
