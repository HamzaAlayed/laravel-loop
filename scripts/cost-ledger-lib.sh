#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034
# SC2034 ("appears unused") is disabled file-wide deliberately: every
# COST_* variable this file sets is this file's own public output --
# consumed by scripts/cost-report.sh and, per slices.md's pinned interface,
# by later slices' scripts -- never read within this file itself.
#
# Read-only arithmetic over .claude/loop-cost.jsonl, for /cost (scripts/cost-report.sh)
# and, in later slices of cost-reporting-v0.3, the budget gate and the log writer.
#
# Sourced, never executed and never registered as a hook. Functions only --
# nothing below runs at source time -- so `source cost-ledger-lib.sh` under a
# caller's own `set -uo pipefail` never has a side effect of its own and never
# changes the caller's shell options.
#
# Why a shared lib instead of each consumer re-reading the ledger: CV7/CV8
# require one ledger to produce one number everywhere it is used -- a report
# and a budget gate that each parsed the file independently could silently
# disagree, which is exactly the "second implementation" this file exists to
# prevent. Every figure any consumer of this file prints or compares must
# come from the functions below; nothing may re-parse the ledger itself.
#
# Zero dependency: bash + coreutils, degrading jq -> python3. Neither present
# -> cost_scan sets COST_SCAN_STATE="no-parser" and every counter stays at
# its zeroed default; it never guesses, and it never crashes. Callers decide
# how to report that (cost-report.sh's CO13 path does).
#
# v0.2 L3, inherited here and never collapsed: a null in the ledger means
# "unavailable", a zero means "measured". cost_fmt is the single place that
# renders that distinction, so no consumer can accidentally print a
# fabricated 0 for a figure that was never observed.
#
# The three record shapes a reader must handle (spec.md E6), and how this
# file treats each one:
#   - ordinary start/finish: identified by `invocation_id`. A finish with a
#     numeric `total_tokens` is PRICED; a finish without one (missing key or
#     JSON null -- record-cost-event.sh's `with_entries(select(.value !=
#     null))` normally omits the key entirely, but a null value is honoured
#     identically) is UNPRICED. A start with no matching finish in the same
#     scan is IN-FLIGHT -- never folded into UNPRICED (CO10).
#   - `event:"cap_trip"`: carries rework/slice information (left for a later
#     slice to consume) but has no `invocation_id` and is never counted as an
#     invocation, priced or not (CO10). Tracked only as COST_N_CAPTRIP.
#   - `status:"line_too_long"`: a real finish record (it carries
#     `invocation_id`), just one whose token fields were dropped by the
#     writer's own oversize fallback. Counted as an invocation, UNPRICED
#     (CO10) -- exactly like an ordinary finish with no token fields.
# Every other shape (a line that fails to parse as a JSON object, or one that
# parses but names neither of the above) is counted in COST_N_SKIPPED (CO8).
#
# Public functions (the ones later slices are told to depend on by name --
# see docs/loop/cost-reporting-v0.3/slices.md's "Lib interface, minimum pin"):
#   cost_fmt <value>
#   cost_coverage_sentence
#   cost_scan <ledger-path> <slug-or-empty>
#   cost_list_slugs <ledger-path>
#
# cost_scan sets (never anything outside this COST_* namespace):
#   COST_SCAN_STATE           "absent" | "empty" | "no-slug" | "ok" | "no-parser" | "scan-error"
#   COST_SLUGS_PRESENT        newline-separated, every distinct slug in the WHOLE ledger,
#                             regardless of the requested slug filter (so a caller can
#                             report "no-slug" and list what IS there in the same breath)
#   COST_N_LINES              non-blank lines read
#   COST_N_SKIPPED            lines that were neither parseable JSON nor a recognised shape
#   COST_N_CAPTRIP            cap_trip records seen for the requested slug (or all, if empty)
#   COST_N_INVOCATIONS        resolved invocations (has a finish) -- priced + unpriced
#   COST_N_PRICED             of those, the ones carrying a numeric total_tokens
#   COST_N_UNPRICED           of those, the ones that finished with no token figure
#   COST_N_INFLIGHT           started, no finish yet -- excluded from the two counts above
#   COST_TOKENS_PRICED        sum of total_tokens over the priced invocations only (CV5:
#                             an unpriced invocation is never added to this as a zero)
#   ...and the same five, suffixed _SPEC / _SLICE / _BUILD / _VERIFY / _UNKNOWN, split by
#   the ledger's own `phase` field (an invocation's phase is the one on its finish record,
#   falling back to its start record's if it has no finish yet).
#
# COST_N_INVOCATIONS deliberately does NOT include COST_N_INFLIGHT: an in-flight
# invocation has not resolved into "carries a token figure" or "does not" yet,
# so it is its own bucket rather than diluting a share it cannot yet belong to
# (CV5). CV1's "how many invocations the ledger holds" is COST_N_INVOCATIONS +
# COST_N_INFLIGHT; a caller that wants the raw total adds the two explicitly,
# in its own output, rather than this file inventing a fourth combined figure
# nobody asked for.

cost_fmt() {
  # Prints a number, or the literal word "unavailable" for an absent one.
  # Never "0" for an absence (v0.2 L3) -- callers must not pre-round a null
  # to zero before handing it here; pass the raw value (or nothing) through.
  local v="${1:-}"
  case "$v" in
    ''|null|NULL) printf 'unavailable' ;;
    *) printf '%s' "$v" ;;
  esac
}

cost_coverage_sentence() {
  # Reads the *current* scan state (the globals the last cost_scan call set)
  # rather than taking numbers as arguments, precisely so a report and a
  # budget gate that both just called cost_scan say the identical sentence
  # from the identical numbers -- never two call sites each formatting their
  # own copy of the same three figures (pinned shape, slices.md contract table).
  local p="${COST_N_PRICED:-0}" n="${COST_N_INVOCATIONS:-0}" u="${COST_N_UNPRICED:-0}"
  printf 'based on %s of %s invocations that carry a token figure (%s unpriced, not counted)' \
    "$p" "$n" "$u"
}

# --- internal: the scan programs, one per parser, identical in behaviour ---
# (verified against each other on fixtures covering all three E6 shapes,
# malformed lines, and slug filtering, before this file was written).
# Defined inside the functions that use them, never at source time, so
# sourcing this file has no side effect beyond making functions available.

_cost_scan_jq_program() {
  cat <<'JQ_EOF'
def to_rec: (try fromjson catch null);
def phase_key:
  if   . == "spec"   then "SPEC"
  elif . == "slice"  then "SLICE"
  elif . == "build"  then "BUILD"
  elif . == "verify" then "VERIFY"
  else "UNKNOWN" end;

(reduce (inputs | select(length > 0)) as $line
  ( {lines:0, skipped:0, captrip:0, slugs:{}, inv:{}}
  ; .lines += 1
  | ($line | to_rec) as $r
  | if $r == null or ($r|type) != "object" then
      .skipped += 1
    elif ($r.event // "") == "cap_trip" then
      (($r.slug // "unknown")) as $slg
      | .slugs[$slg] = 1
      | (if ($slugfilter == "" or $slugfilter == $slg) then .captrip += 1 else . end)
    elif (($r.event // "") == "start" or ($r.event // "") == "finish") then
      (($r.slug // "unknown")) as $slg
      | .slugs[$slg] = 1
      | if ($slugfilter != "" and $slugfilter != $slg) then .
        else
          (($r.invocation_id // ("noid-" + ((.lines)|tostring)))) as $id
          | (.inv[$id] // {start:false, finish:false, priced:false, tokens:null, phase:"unknown"}) as $e
          | ( $e
              | if $r.event == "start" then (.start = true) | (.phase = ($r.phase // .phase)) else . end
              | if $r.event == "finish" then
                  (.finish = true)
                  | (.phase = ($r.phase // .phase))
                  | (if (($r|has("total_tokens")) and ($r.total_tokens != null)) then
                       (.priced = true) | (.tokens = $r.total_tokens)
                     else
                       (.priced = false)
                     end)
                else . end
            ) as $ne
          | .inv[$id] = $ne
        end
    else
      .skipped += 1
    end
  )
) as $acc
| ($acc.inv | to_entries) as $entries
| (reduce $entries[] as $e (
     { inv:0, priced:0, unpriced:0, inflight:0, tokens:0,
       byphase: { SPEC:{inv:0,priced:0,unpriced:0,inflight:0,tokens:0},
                  SLICE:{inv:0,priced:0,unpriced:0,inflight:0,tokens:0},
                  BUILD:{inv:0,priced:0,unpriced:0,inflight:0,tokens:0},
                  VERIFY:{inv:0,priced:0,unpriced:0,inflight:0,tokens:0},
                  UNKNOWN:{inv:0,priced:0,unpriced:0,inflight:0,tokens:0} } }
   ;
     ($e.value.phase | phase_key) as $pk
   | (.inv += 1) | (.byphase[$pk].inv += 1)
   | if $e.value.finish then
       if $e.value.priced then
         (.priced += 1) | (.tokens += $e.value.tokens)
         | (.byphase[$pk].priced += 1) | (.byphase[$pk].tokens += $e.value.tokens)
       else
         (.unpriced += 1) | (.byphase[$pk].unpriced += 1)
       end
     elif $e.value.start then
       (.inflight += 1) | (.byphase[$pk].inflight += 1)
     else . end
   )) as $agg
| ( "COUNT\tCOST_N_LINES\t\($acc.lines)",
    "COUNT\tCOST_N_SKIPPED\t\($acc.skipped)",
    "COUNT\tCOST_N_CAPTRIP\t\($acc.captrip)",
    "COUNT\tCOST_N_INVOCATIONS\t\($agg.inv)",
    "COUNT\tCOST_N_PRICED\t\($agg.priced)",
    "COUNT\tCOST_N_UNPRICED\t\($agg.unpriced)",
    "COUNT\tCOST_N_INFLIGHT\t\($agg.inflight)",
    "COUNT\tCOST_TOKENS_PRICED\t\($agg.tokens)"
  ), (
    $agg.byphase | to_entries[] | (
      "COUNT\tCOST_N_INVOCATIONS_\(.key)\t\(.value.inv)",
      "COUNT\tCOST_N_PRICED_\(.key)\t\(.value.priced)",
      "COUNT\tCOST_N_UNPRICED_\(.key)\t\(.value.unpriced)",
      "COUNT\tCOST_N_INFLIGHT_\(.key)\t\(.value.inflight)",
      "COUNT\tCOST_TOKENS_PRICED_\(.key)\t\(.value.tokens)"
    )
  ), (
    $acc.slugs | keys_unsorted[] | "SLUG\t\(.)"
  )
JQ_EOF
}

_cost_scan_py_program() {
  cat <<'PY_EOF'
import sys, json

slugfilter = sys.argv[1] if len(sys.argv) > 1 else ""
lines = 0
skipped = 0
captrip = 0
slugs = {}
inv = {}


def phase_key(p):
    p = p if p in ("spec", "slice", "build", "verify") else "unknown"
    return p.upper()


for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "":
        continue
    lines += 1
    try:
        r = json.loads(line)
        if not isinstance(r, dict):
            raise ValueError()
    except Exception:
        skipped += 1
        continue
    event = r.get("event") or ""
    slg = r.get("slug") or "unknown"
    if event == "cap_trip":
        slugs[slg] = 1
        if slugfilter == "" or slugfilter == slg:
            captrip += 1
        continue
    if event in ("start", "finish"):
        slugs[slg] = 1
        if slugfilter != "" and slugfilter != slg:
            continue
        invid = r.get("invocation_id") or ("noid-" + str(lines))
        e = inv.get(invid) or {"start": False, "finish": False, "priced": False,
                                "tokens": None, "phase": "unknown"}
        if event == "start":
            e["start"] = True
            e["phase"] = r.get("phase") or e["phase"]
        if event == "finish":
            e["finish"] = True
            e["phase"] = r.get("phase") or e["phase"]
            if "total_tokens" in r and r.get("total_tokens") is not None:
                e["priced"] = True
                e["tokens"] = r.get("total_tokens")
            else:
                e["priced"] = False
        inv[invid] = e
        continue
    skipped += 1

agg = {"inv": 0, "priced": 0, "unpriced": 0, "inflight": 0, "tokens": 0}
byphase = {k: {"inv": 0, "priced": 0, "unpriced": 0, "inflight": 0, "tokens": 0}
           for k in ("SPEC", "SLICE", "BUILD", "VERIFY", "UNKNOWN")}

for e in inv.values():
    pk = phase_key(e["phase"])
    agg["inv"] += 1
    byphase[pk]["inv"] += 1
    if e["finish"]:
        if e["priced"]:
            agg["priced"] += 1
            agg["tokens"] += e["tokens"]
            byphase[pk]["priced"] += 1
            byphase[pk]["tokens"] += e["tokens"]
        else:
            agg["unpriced"] += 1
            byphase[pk]["unpriced"] += 1
    elif e["start"]:
        agg["inflight"] += 1
        byphase[pk]["inflight"] += 1

out = [
    f"COUNT\tCOST_N_LINES\t{lines}",
    f"COUNT\tCOST_N_SKIPPED\t{skipped}",
    f"COUNT\tCOST_N_CAPTRIP\t{captrip}",
    f"COUNT\tCOST_N_INVOCATIONS\t{agg['inv']}",
    f"COUNT\tCOST_N_PRICED\t{agg['priced']}",
    f"COUNT\tCOST_N_UNPRICED\t{agg['unpriced']}",
    f"COUNT\tCOST_N_INFLIGHT\t{agg['inflight']}",
    f"COUNT\tCOST_TOKENS_PRICED\t{agg['tokens']}",
]
for k in ("SPEC", "SLICE", "BUILD", "VERIFY", "UNKNOWN"):
    v = byphase[k]
    out.append(f"COUNT\tCOST_N_INVOCATIONS_{k}\t{v['inv']}")
    out.append(f"COUNT\tCOST_N_PRICED_{k}\t{v['priced']}")
    out.append(f"COUNT\tCOST_N_UNPRICED_{k}\t{v['unpriced']}")
    out.append(f"COUNT\tCOST_N_INFLIGHT_{k}\t{v['inflight']}")
    out.append(f"COUNT\tCOST_TOKENS_PRICED_{k}\t{v['tokens']}")
for s in slugs.keys():
    out.append(f"SLUG\t{s}")

print("\n".join(out))
PY_EOF
}

_cost_list_jq_program() {
  cat <<'JQ_EOF'
def to_rec: (try fromjson catch null);
(reduce (inputs | select(length>0)) as $line
  ( {}
  ; ($line|to_rec) as $r
  | if $r == null or ($r|type) != "object" then .
    else
      (($r.slug // "unknown")) as $slg
      | (($r.ts // 0)) as $t
      | (.[$slg] // -1) as $cur
      | if $t > $cur then .[$slg] = $t else . end
    end
  )
) as $m
| ($m | to_entries | sort_by([-(.value), .key]) | .[] | .key)
JQ_EOF
}

_cost_list_py_program() {
  cat <<'PY_EOF'
import sys, json

m = {}
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "":
        continue
    try:
        r = json.loads(line)
        if not isinstance(r, dict):
            raise ValueError()
    except Exception:
        continue
    slg = r.get("slug") or "unknown"
    t = r.get("ts") or 0
    if t > m.get(slg, -1):
        m[slg] = t

for slg, _ in sorted(m.items(), key=lambda kv: (-kv[1], kv[0])):
    print(slg)
PY_EOF
}

_cost_reset_scan_vars() {
  COST_SCAN_STATE="absent"
  COST_SLUGS_PRESENT=""
  COST_N_LINES=0
  COST_N_SKIPPED=0
  COST_N_CAPTRIP=0
  COST_N_INVOCATIONS=0
  COST_N_PRICED=0
  COST_N_UNPRICED=0
  COST_N_INFLIGHT=0
  COST_TOKENS_PRICED=0
  COST_N_INVOCATIONS_SPEC=0; COST_N_PRICED_SPEC=0; COST_N_UNPRICED_SPEC=0
  COST_N_INFLIGHT_SPEC=0; COST_TOKENS_PRICED_SPEC=0
  COST_N_INVOCATIONS_SLICE=0; COST_N_PRICED_SLICE=0; COST_N_UNPRICED_SLICE=0
  COST_N_INFLIGHT_SLICE=0; COST_TOKENS_PRICED_SLICE=0
  COST_N_INVOCATIONS_BUILD=0; COST_N_PRICED_BUILD=0; COST_N_UNPRICED_BUILD=0
  COST_N_INFLIGHT_BUILD=0; COST_TOKENS_PRICED_BUILD=0
  COST_N_INVOCATIONS_VERIFY=0; COST_N_PRICED_VERIFY=0; COST_N_UNPRICED_VERIFY=0
  COST_N_INFLIGHT_VERIFY=0; COST_TOKENS_PRICED_VERIFY=0
  COST_N_INVOCATIONS_UNKNOWN=0; COST_N_PRICED_UNKNOWN=0; COST_N_UNPRICED_UNKNOWN=0
  COST_N_INFLIGHT_UNKNOWN=0; COST_TOKENS_PRICED_UNKNOWN=0
}

_cost_apply_scan_line() {
  # $1 tag  $2 key-or-slug  $3 value (COUNT lines only)
  local tag="$1" k="$2" v="${3:-}"
  if [ "$tag" = "SLUG" ]; then
    if [ -z "$COST_SLUGS_PRESENT" ]; then
      COST_SLUGS_PRESENT="$k"
    else
      COST_SLUGS_PRESENT="$COST_SLUGS_PRESENT
$k"
    fi
    return 0
  fi
  [ "$tag" = "COUNT" ] || return 0
  case "$k" in
    COST_N_LINES) COST_N_LINES="$v" ;;
    COST_N_SKIPPED) COST_N_SKIPPED="$v" ;;
    COST_N_CAPTRIP) COST_N_CAPTRIP="$v" ;;
    COST_N_INVOCATIONS) COST_N_INVOCATIONS="$v" ;;
    COST_N_PRICED) COST_N_PRICED="$v" ;;
    COST_N_UNPRICED) COST_N_UNPRICED="$v" ;;
    COST_N_INFLIGHT) COST_N_INFLIGHT="$v" ;;
    COST_TOKENS_PRICED) COST_TOKENS_PRICED="$v" ;;
    COST_N_INVOCATIONS_SPEC) COST_N_INVOCATIONS_SPEC="$v" ;;
    COST_N_PRICED_SPEC) COST_N_PRICED_SPEC="$v" ;;
    COST_N_UNPRICED_SPEC) COST_N_UNPRICED_SPEC="$v" ;;
    COST_N_INFLIGHT_SPEC) COST_N_INFLIGHT_SPEC="$v" ;;
    COST_TOKENS_PRICED_SPEC) COST_TOKENS_PRICED_SPEC="$v" ;;
    COST_N_INVOCATIONS_SLICE) COST_N_INVOCATIONS_SLICE="$v" ;;
    COST_N_PRICED_SLICE) COST_N_PRICED_SLICE="$v" ;;
    COST_N_UNPRICED_SLICE) COST_N_UNPRICED_SLICE="$v" ;;
    COST_N_INFLIGHT_SLICE) COST_N_INFLIGHT_SLICE="$v" ;;
    COST_TOKENS_PRICED_SLICE) COST_TOKENS_PRICED_SLICE="$v" ;;
    COST_N_INVOCATIONS_BUILD) COST_N_INVOCATIONS_BUILD="$v" ;;
    COST_N_PRICED_BUILD) COST_N_PRICED_BUILD="$v" ;;
    COST_N_UNPRICED_BUILD) COST_N_UNPRICED_BUILD="$v" ;;
    COST_N_INFLIGHT_BUILD) COST_N_INFLIGHT_BUILD="$v" ;;
    COST_TOKENS_PRICED_BUILD) COST_TOKENS_PRICED_BUILD="$v" ;;
    COST_N_INVOCATIONS_VERIFY) COST_N_INVOCATIONS_VERIFY="$v" ;;
    COST_N_PRICED_VERIFY) COST_N_PRICED_VERIFY="$v" ;;
    COST_N_UNPRICED_VERIFY) COST_N_UNPRICED_VERIFY="$v" ;;
    COST_N_INFLIGHT_VERIFY) COST_N_INFLIGHT_VERIFY="$v" ;;
    COST_TOKENS_PRICED_VERIFY) COST_TOKENS_PRICED_VERIFY="$v" ;;
    COST_N_INVOCATIONS_UNKNOWN) COST_N_INVOCATIONS_UNKNOWN="$v" ;;
    COST_N_PRICED_UNKNOWN) COST_N_PRICED_UNKNOWN="$v" ;;
    COST_N_UNPRICED_UNKNOWN) COST_N_UNPRICED_UNKNOWN="$v" ;;
    COST_N_INFLIGHT_UNKNOWN) COST_N_INFLIGHT_UNKNOWN="$v" ;;
    COST_TOKENS_PRICED_UNKNOWN) COST_TOKENS_PRICED_UNKNOWN="$v" ;;
    *) : ;;
  esac
}

cost_scan() {
  local ledger="${1:-}" slug="${2:-}"
  _cost_reset_scan_vars

  [ -n "$ledger" ] && [ -f "$ledger" ] || { COST_SCAN_STATE="absent"; return 0; }
  [ -s "$ledger" ] || { COST_SCAN_STATE="empty"; return 0; }

  local have_jq=0 have_py=0
  command -v jq >/dev/null 2>&1 && have_jq=1
  [ "$have_jq" -eq 0 ] && command -v python3 >/dev/null 2>&1 && have_py=1
  if [ "$have_jq" -eq 0 ] && [ "$have_py" -eq 0 ]; then
    COST_SCAN_STATE="no-parser"
    return 0
  fi

  local out=""
  if [ "$have_jq" -eq 1 ]; then
    out="$(jq -Rn -r --arg slugfilter "$slug" "$(_cost_scan_jq_program)" < "$ledger" 2>/dev/null)"
  else
    out="$(python3 -c "$(_cost_scan_py_program)" "$slug" < "$ledger" 2>/dev/null)"
  fi

  if ! printf '%s' "$out" | grep -q 'COST_N_LINES'; then
    COST_SCAN_STATE="scan-error"
    return 0
  fi

  local tag k v
  while IFS=$'\t' read -r tag k v; do
    [ -z "$tag" ] && continue
    _cost_apply_scan_line "$tag" "$k" "$v"
  done <<EOF
$out
EOF

  if [ -n "$slug" ]; then
    if ! printf '%s\n' "$COST_SLUGS_PRESENT" | grep -qxF "$slug"; then
      COST_SCAN_STATE="no-slug"
      return 0
    fi
  fi
  COST_SCAN_STATE="ok"
  return 0
}

cost_list_slugs() {
  # Prints one slug per line, most-recently-active first (by the max `ts`
  # across every record carrying that slug, including cap_trip), ties broken
  # by the slug's own byte ordering -- never a locale-dependent sort, and
  # never `sort`'s own collation, so this is identical on every machine
  # (CV7). Used by cost-report.sh's no-argument listing (CO1) and by the
  # "unknown slug" empty state (CO3) to say what IS in the ledger.
  local ledger="${1:-}"
  [ -n "$ledger" ] && [ -f "$ledger" ] && [ -s "$ledger" ] || return 0

  if command -v jq >/dev/null 2>&1; then
    jq -Rn -r "$(_cost_list_jq_program)" < "$ledger" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "$(_cost_list_py_program)" < "$ledger" 2>/dev/null
  fi
  return 0
}
