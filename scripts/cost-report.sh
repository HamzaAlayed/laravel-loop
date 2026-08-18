#!/usr/bin/env bash
# Read-only formatter for `/cost` (commands/cost.md). Prints what
# .claude/loop-cost.jsonl can and cannot see for one unit of work -- or, with
# no argument, one line per unit the ledger holds -- and states that
# coverage before it ever states a total (spec.md CV1). This is the reader:
# it never writes, prunes, rotates, or reshapes the ledger, and it never
# reads a sibling plugin's own separate event feed, the network, or any
# account -- .claude/loop-cost.jsonl and nothing else (CO2). Every figure
# below comes from scripts/cost-ledger-lib.sh, never
# from a second parse of the file here, so a later slice's budget gate can
# never disagree with what this prints (CV7/CV8).
#
# Usage: scripts/cost-report.sh [slug]
#   no slug -- one line per unit in the ledger, most recent first (CO1)
#   a slug  -- that unit's coverage, then its priced-subset total (CV1/CV3)
#
# Always exits 0. A reporting tool that can crash is worse than one that
# plainly says it could not read something (CO3, CO13), and every message
# below goes to stdout so commands/cost.md -- which relays stdout verbatim
# and nothing else -- always has something to show.

set -uo pipefail

ROOT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
LEDGER="$ROOT_DIR/.claude/loop-cost.jsonl"
# Pure bash, deliberately -- no external `dirname` -- so resolving this
# script's own directory never depends on a coreutil being on PATH, even
# before the jq/python3 check below runs (CO13).
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

SLUG="${1:-}"

if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  printf 'Cannot read the cost ledger: neither jq nor python3 is on PATH. Install either one to use /cost.\n'
  exit 0
fi

# shellcheck source=cost-ledger-lib.sh
source "$SCRIPT_DIR/cost-ledger-lib.sh"

print_absent() {
  cat <<'EOF'
No cost ledger found at .claude/loop-cost.jsonl.

Likely causes:
  - the cost-ledger hooks are not wired into this project's settings.json
  - LARAVEL_LOOP_COST_LEDGER=0 (or "off") is disabling the ledger

Nothing has been observed yet -- this is not an error.
EOF
}

print_empty() {
  printf 'The cost ledger exists at .claude/loop-cost.jsonl but holds no records yet.\n'
}

print_no_slug() {
  local slug="$1" present
  printf 'No records for unit "%s" in the cost ledger.\n' "$slug"
  printf '\n'
  printf 'Units present in the ledger:\n'
  present="$(cost_list_slugs "$LEDGER")"
  if [ -z "$present" ]; then
    printf '  (none)\n'
  else
    printf '%s\n' "$present" | while IFS= read -r s; do
      [ -n "$s" ] && printf '  - %s\n' "$s"
    done
  fi
  printf '\n'
  printf 'A typo in the slug and a unit that has not run yet look the same from here --\n'
  printf 'check the name above against docs/loop/<slug>/.\n'
}

# One phase's row for the Coverage section's per-phase split. Uses bash
# indirect expansion (${!name}), never eval, to read the four
# COST_*_<PHASE> variables cost_scan set for $1.
print_phase_row() {
  local phase="$1" label pv_name uv_name iv_name inv_name pv uv iv inv
  label="$(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]')"
  pv_name="COST_N_PRICED_$phase"; uv_name="COST_N_UNPRICED_$phase"
  iv_name="COST_N_INFLIGHT_$phase"; inv_name="COST_N_INVOCATIONS_$phase"
  pv="${!pv_name}"; uv="${!uv_name}"; iv="${!iv_name}"; inv="${!inv_name}"
  if [ "$phase" = "UNKNOWN" ] && [ "$inv" -eq 0 ] && [ "$iv" -eq 0 ]; then
    return 0
  fi
  printf '    %-6s %s/%s priced' "$label" "$pv" "$inv"
  [ "$iv" -gt 0 ] && printf ' (+%s in flight)' "$iv"
  printf ' (%s unpriced)\n' "$uv"
}

print_elapsed() {
  # CO11: labelled elapsed wall-clock, derived only from this unit's own
  # start/finish timestamps -- never a sum of durations, so overlapping
  # (concurrent) invocations are never double-counted into an "agent time"
  # total (E5). COST_TS_MIN/COST_TS_MAX come straight from cost_scan; this
  # never re-reads the ledger.
  printf '  elapsed (wall-clock, first recorded start to last recorded finish; never summed across overlapping invocations): '
  if [ "${COST_TS_MIN:--1}" -lt 0 ] || [ "${COST_TS_MAX:--1}" -lt 0 ] || [ "$COST_TS_MAX" -lt "$COST_TS_MIN" ]; then
    printf 'unavailable\n'
  else
    printf '%s second(s)\n' "$((COST_TS_MAX - COST_TS_MIN))"
  fi
}

# CL1: every unpriced invocation is named with the reason it is unpriced,
# taken only from its own finish record's `status` field -- never guessed
# from phase, agent, or duration. CL2: "launched in background, outcome
# never observed" is its own named category, distinct from truncated,
# no-usage-figure, and in-flight -- a launch is not a finish.
print_unpriced_reasons() {
  local bg="${COST_N_UNPRICED_BACKGROUNDED:-0}" nu="${COST_N_UNPRICED_NO_USAGE:-0}"
  local tr="${COST_N_UNPRICED_TRUNCATED:-0}" un="${COST_N_UNPRICED_UNSTATED:-0}"
  if [ "$bg" -eq 0 ] && [ "$nu" -eq 0 ] && [ "$tr" -eq 0 ] && [ "$un" -eq 0 ]; then
    return 0
  fi
  printf '  unpriced invocation(s), by reason (taken only from the finish record'"'"'s own status, never guessed):\n'
  [ "$bg" -gt 0 ] && printf '    %s launched in background, outcome never observed\n' "$bg"
  [ "$nu" -gt 0 ] && printf '    %s observed, no usage figure\n' "$nu"
  [ "$tr" -gt 0 ] && printf '    %s truncated (ledger line too long)\n' "$tr"
  [ "$un" -gt 0 ] && printf '    %s reason not stated\n' "$un"
}

# CL3: states, once per report and only when this unit actually holds a
# backgrounded invocation, why the figure is absent -- a measured fact
# (E2's two controlled probes), never a promise that it will be recovered.
# A fully foreground unit has nothing to gain from this line, so it is
# gated on the same COST_N_UNPRICED_BACKGROUNDED count print_unpriced_reasons
# already reads (CV7: no second parse), and it prints exactly once no
# matter how many such invocations this unit holds -- it explains the
# category, not each member of it (S1's per-invocation count already did
# that above). Worded to stay true if recovery ever lands: it names what a
# backgrounded invocation's figure IS (measured, delivered) rather than
# asserting this tool will ever go get it, so it describes the residue
# recovery would leave behind, not a gap that no longer exists.
print_backgrounded_reason() {
  [ "${COST_N_UNPRICED_BACKGROUNDED:-0}" -eq 0 ] && return 0
  printf '  Why: for a backgrounded invocation, the token figure is measured by the host\n'
  printf '  and delivered into the session when it finishes -- it is not captured here.\n'
}

# --- Coverage floor (S4, CL5): governs what is PRINTED below, never what
# scripts/check-budget-gate.sh compares or whether it fires -- G0-D1 is not
# reopened by any of this. A human sets the floor; this file ships no
# default, suggested starting point, or derived value for it, anywhere (Do
# NOT). Unset means today's behaviour, byte for byte: this function is only
# ever called from the branch below that already requires at least one
# priced invocation, so CV6's all-unpriced branch never reaches it and gets
# no second, contradicting statement.
#
# An out-of-range or otherwise unparseable value DISABLES the floor loudly,
# naming the field and the value -- the same discipline
# scripts/check-budget-gate.sh's is_valid_threshold already established for
# its own threshold, reused here rather than reinvented with different
# manners. This is its own parser, not a second implementation of that
# file's: the input shape differs (a bounded share, not a bare count), and
# check-budget-gate.sh itself is out of bounds for this slice.
cost_min_coverage_floor_check() {
  COST_FLOOR_BELOW=0
  COST_FLOOR_WARNING=""
  COST_FLOOR_VALUE=""
  COST_FLOOR_SHARE=0
  local raw="${LARAVEL_LOOP_COST_MIN_COVERAGE:-}"
  [ -z "$raw" ] && return 0
  local bad=0
  case "$raw" in
    *[!0-9]*) bad=1 ;;
  esac
  [ "$bad" -eq 0 ] && [ "$raw" -gt 100 ] && bad=1
  if [ "$bad" -eq 1 ]; then
    COST_FLOOR_WARNING="$(cost_min_coverage_floor_warning "$raw")"
    return 0
  fi
  COST_FLOOR_VALUE="$raw"
  local n="${COST_N_INVOCATIONS:-0}" p="${COST_N_PRICED:-0}"
  [ "$n" -gt 0 ] && COST_FLOOR_SHARE=$(( p * 100 / n ))
  [ "$COST_FLOOR_SHARE" -lt "$raw" ] && COST_FLOOR_BELOW=1
}

# Kept in its own function so the field's name and the numeric range in its
# error text never share one physical source line -- the guard case this
# slice adds to tests/guardrails.test.sh checks exactly that, across
# scripts/, README, and docs.
cost_min_coverage_floor_warning() {
  local raw="$1" name
  name="LARAVEL_LOOP_COST_MIN_COVERAGE"
  printf '%s="%s" is not a bare percentage -- the coverage floor is DISABLED, not defaulted to any number. Accepted form: digits only, whole percent, zero through one hundred inclusive.' \
    "$name" "$raw"
}

# Below-floor Tokens statement (CL5): no total, the unit's cost is not
# established, and the observed subset stays exactly where Coverage above
# already showed it -- never repeated here as if it were a second, competing
# total.
print_below_floor_tokens() {
  printf 'Tokens: not established -- coverage is below the configured floor (LARAVEL_LOOP_COST_MIN_COVERAGE=%s%%). No unit-level token total is printed; the observed subset already appears in the Coverage section above.\n' \
    "$COST_FLOOR_VALUE"
}

print_coverage_and_tokens() {
  printf 'Coverage:\n'
  printf '  %s\n' "$(cost_coverage_sentence)"
  print_unpriced_reasons
  print_backgrounded_reason
  # CL2/E5: an async_launched finish record is a launch, not a resolved
  # outcome -- it is not in COST_N_INFLIGHT (which counts only a start with
  # NO finish record at all), so without this addendum the line below could
  # read as a bare "0" while invocations that were still running when their
  # launch was recorded sit unmentioned. Appended on the same line so the
  # statement as a whole is never read in isolation from that fact.
  printf '  %s invocation(s) started with no finish recorded yet -- in flight, not counted as unpriced' \
    "$COST_N_INFLIGHT"
  if [ "${COST_N_UNPRICED_BACKGROUNDED:-0}" -gt 0 ]; then
    printf ' (plus %s launched in background and never subsequently observed -- also unresolved, counted separately above, never folded into this count)' \
      "$COST_N_UNPRICED_BACKGROUNDED"
  fi
  printf '.\n'
  if [ "${COST_N_SKIPPED:-0}" -gt 0 ]; then
    printf '  %s ledger line(s) skipped -- malformed or truncated, not JSON (never silently dropped from this count).\n' \
      "$COST_N_SKIPPED"
  fi
  if [ "${COST_N_CAPTRIP:-0}" -gt 0 ]; then
    printf '  %s cap_trip record(s) excluded from the counts above -- rework markers, not invocations.\n' \
      "$COST_N_CAPTRIP"
  fi
  printf '  per phase (priced/total invocations; in-flight and unpriced called out, never folded together):\n'
  local ph
  for ph in SPEC SLICE BUILD VERIFY UNKNOWN; do
    print_phase_row "$ph"
  done
  print_elapsed
  printf '\n'
  if [ "${COST_N_PRICED:-0}" -eq 0 ]; then
    printf 'Tokens: nothing about this unit'"'"'s token cost is observable -- %s of %s invocations carry a token figure. No token table is printed.\n' \
      "$COST_N_PRICED" "$COST_N_INVOCATIONS"
  else
    cost_min_coverage_floor_check
    if [ -n "$COST_FLOOR_WARNING" ]; then
      printf '%s\n' "$COST_FLOOR_WARNING"
    fi
    if [ "$COST_FLOOR_BELOW" -eq 1 ]; then
      print_below_floor_tokens
    else
      printf 'Tokens (priced subset only -- never the unit'"'"'s whole cost):\n'
      printf '  total priced tokens: %s\n' "$(cost_fmt "$COST_TOKENS_PRICED")"
      printf '  %s\n' "$(cost_coverage_sentence)"
      print_transcription_conflicts
      print_cache_read_share
    fi
  fi
}

# S8 (RC3): where an invocation carries both a host-observed figure and a
# transcribed one and they disagree, that is never resolved silently. Both
# numbers are shown, each attributed to its source, and the rule this
# report already follows (the observed figure is the one summed into the
# total above -- unchanged since S7) is stated in the same place. Printed
# only when at least one such disagreement exists (COST_N_CONFLICTS > 0);
# equal figures are not a disagreement (RC3's own boundary) and print
# nothing.
print_transcription_conflicts() {
  [ "${COST_N_CONFLICTS:-0}" -gt 0 ] || return 0
  printf '  %s invocation(s) have an observed figure and a transcribed figure that disagree -- the observed (host-measured) figure is the one counted in the total above; the transcribed (model-reported) figure is shown for comparison only, and is never averaged, maximised, minimised, or allowed to overwrite it:\n' \
    "$COST_N_CONFLICTS"
  local id observed transcribed diff
  while IFS=$'\t' read -r id observed transcribed; do
    [ -z "$id" ] && continue
    diff=$((observed > transcribed ? observed - transcribed : transcribed - observed))
    printf '    %s: observed %s, transcribed %s (difference %s)\n' \
      "$id" "$observed" "$transcribed" "$diff"
  done <<EOF
$COST_CONFLICT_ROWS
EOF
}

print_cache_read_share() {
  # CV4: unavailable when cache_read_tokens is absent from EVERY priced
  # record -- never "0%", which would read as a catastrophic miss of a
  # target (>40%, requirements doc Sec.10) against a quantity that was
  # simply never measured (v0.2 D1's best-effort field, v0.2 L3).
  if [ "${COST_CACHE_READ_PRICED_N:-0}" -eq 0 ]; then
    printf '  cache-read share: unavailable (cache_read_tokens absent from every priced record)\n'
    return 0
  fi
  local denom="${COST_TOKENS_CACHE_DENOM:-0}"
  if [ "$denom" -le 0 ]; then
    printf '  cache-read share: unavailable (no priced tokens to compare against)\n'
    return 0
  fi
  printf '  cache-read share: %s%% (over the %s priced invocation(s) that reported cache-read data)\n' \
    "$((COST_TOKENS_CACHE_READ * 100 / denom))" "$COST_CACHE_READ_PRICED_N"
}

# --- Phases (CO4): per-phase breakdown of PRICED invocations, with the
# model recorded per phase and `derived` shown wherever model_source is
# derived rather than observed. Only printed when this unit has at least
# one priced invocation at all -- with none, this would be a table of
# "unavailable" rows for every phase, which CV6 forbids exactly as it
# forbids a table of zeros. A phase with priced coverage elsewhere in the
# unit but none of its own still reads "unavailable", never "0" (CO4). ------
format_models() {
  local ph="$1" var raw pair model source out=""
  var="COST_MODELS_$ph"
  raw="${!var}"
  if [ -z "$raw" ]; then
    printf 'unavailable'
    return 0
  fi
  local IFS=,
  for pair in $raw; do
    model="${pair%%::*}"
    source="${pair##*::}"
    [ -n "$out" ] && out="$out, "
    if [ "$source" = "derived" ]; then
      out="${out}${model} (derived)"
    else
      out="${out}${model}"
    fi
  done
  printf '%s' "$out"
}

print_phases() {
  [ "${COST_N_PRICED:-0}" -eq 0 ] && return 0
  printf 'Phases (priced invocations only; model per phase, model_source shown when derived):\n'
  local ph label inv_name
  for ph in SPEC SLICE BUILD VERIFY UNKNOWN; do
    if [ "$ph" = "UNKNOWN" ]; then
      inv_name="COST_N_INVOCATIONS_UNKNOWN"
      [ "${!inv_name}" -eq 0 ] && continue
    fi
    label="$(printf '%s' "$ph" | tr '[:upper:]' '[:lower:]')"
    printf '    %-6s %s\n' "$label" "$(format_models "$ph")"
  done
}

# --- Rework (CO5, CO6, D3): invocation counts always -- computable
# regardless of pricing (E4) -- and a token share only where the rework
# invocations are themselves priced. Each figure labelled as which it is,
# so neither can be mistaken for the other. The wording below is lifted
# from record-cost-event.sh's own header, written there to be lifted. ------
print_rework() {
  printf 'Rework:\n'
  printf '  This measures the cost of slices that were not right first time, at whole-invocation\n'
  printf '  granularity -- not the cost of retrying. An invocation needing even one refine pass has\n'
  printf '  its WHOLE token cost counted as rework, deliberately over-attributing rather than\n'
  printf '  estimating a per-pass split. This is not comparable to the requirements document'"'"'s\n'
  printf '  <15%% target (Sec.10), which was calibrated against a narrower, per-pass definition.\n'
  printf '  No pass/fail verdict against that target is printed here.\n'
  local n="${COST_N_REWORK:-0}" m="${COST_N_INVOCATIONS:-0}" passes="${COST_REWORK_REFINE_PASSES:-}"
  if [ -n "$passes" ]; then
    printf '  count: %s of %s invocation(s) marked rework (refine passes: %s)\n' "$n" "$m" "$passes"
  else
    printf '  count: %s of %s invocation(s) marked rework\n' "$n" "$m"
  fi
  if [ "${COST_REWORK_HAS_AMBIGUOUS:-0}" -eq 1 ]; then
    printf '  at least one rework marking above carries rework_attribution: ambiguous -- shown as ambiguous, never as definite.\n'
  fi
  local rp="${COST_N_REWORK_PRICED:-0}"
  if [ "$rp" -gt 0 ] && [ "${COST_TOKENS_PRICED:-0}" -gt 0 ]; then
    printf '  token share: %s%% of priced tokens (%s of %s priced invocation(s) marked rework)\n' \
      "$((COST_TOKENS_REWORK_PRICED * 100 / COST_TOKENS_PRICED))" "$rp" "${COST_N_PRICED:-0}"
  else
    printf '  token share: unavailable (no priced invocations are marked rework)\n'
  fi
}

# --- Slices + Flags (CO7): top priced slices, and the >30%-concentration
# flag -- printed only where slice-level coverage supports the comparison.
# Where a priced invocation carries no slice at all, ranking would silently
# under-count whichever slice that tokens actually belonged to, so this
# says the comparison could not be assessed instead of guessing (CO7).
#
# recovered-figure-drops-slice-and-model S1 (RD3/RD4): the same incompleteness
# can also arise with COST_SLICE_UNKNOWN_PRICED at zero -- a priced invocation
# this pass never even recognised as priced (pre-S5, any invocation priced
# only by a `recovered` record). cost_slice_unranked() states BOTH cases the
# same way: how many invocations and how many tokens sit outside the ranking.
# The COST_SLICE_UNKNOWN_PRICED>0 branch below is kept byte-identical on
# purpose (RD8/RC6 -- a run that transcribed nothing must read exactly as it
# always has); the new line in the Slices section is the only thing added for
# that path, and a concentration verdict never prints while either gap is
# nonzero (RD4). -------------------------------------------------------------
print_slices_and_flags() {
  if [ "${COST_N_PRICED:-0}" -eq 0 ]; then
    printf 'Slices: no priced invocations for this unit -- nothing to rank by cost.\n'
    printf '\n'
    printf 'Flags:\n'
    printf '  concentration could not be assessed -- no priced invocations to rank.\n'
    return 0
  fi

  # Called directly, never through command substitution: cost_slice_rows
  # sets COST_SLICE_UNKNOWN_PRICED/COST_SLICE_ROWS as side effects, and
  # command substitution would run it in a subshell that discards them.
  cost_slice_rows "$LEDGER" "$SLUG" >/dev/null
  local rows="$COST_SLICE_ROWS" unknown="${COST_SLICE_UNKNOWN_PRICED:-0}"

  # Same reason as above: a side effect this caller reads afterward, so this
  # runs outside any command substitution too.
  cost_slice_unranked
  local outside_n="${COST_SLICE_OUTSIDE_N:-0}" outside_tokens="${COST_SLICE_OUTSIDE_TOKENS:-0}"
  local unreconciled="${COST_SLICE_OUTSIDE_UNRECONCILED:-0}"

  printf 'Slices (top by priced tokens, priced subset only):\n'
  if [ -z "$rows" ]; then
    printf '  no slice attributed to any priced invocation.\n'
  else
    printf '%s\n' "$rows" | while IFS=$'\t' read -r slice tokens inv _rtoks rinv; do
      [ -z "$slice" ] && continue
      printf '  %-20s %s tokens (%s priced invocation(s), %s reworked)\n' "$slice" "$tokens" "$inv" "$rinv"
    done
  fi
  if [ "$outside_n" -gt 0 ] || [ "$unreconciled" -eq 1 ]; then
    printf '  %s priced invocation(s), %s token(s) sit outside this ranking -- unattributed.\n' \
      "$outside_n" "$outside_tokens"
  fi

  printf '\n'
  printf 'Flags:\n'
  if [ "$unknown" -gt 0 ]; then
    printf '  concentration could not be assessed -- %s priced invocation(s) carry no slice attribution.\n' "$unknown"
    return 0
  fi
  if [ "$outside_n" -gt 0 ] || [ "$unreconciled" -eq 1 ]; then
    printf '  concentration could not be assessed -- %s priced invocation(s), %s token(s) sit outside this ranking.\n' \
      "$outside_n" "$outside_tokens"
    return 0
  fi
  if [ -z "$rows" ]; then
    printf '  (no flags raised)\n'
    return 0
  fi
  local top_slice top_tokens flagged=0
  top_slice="$(printf '%s\n' "$rows" | head -1 | cut -f1)"
  top_tokens="$(printf '%s\n' "$rows" | head -1 | cut -f2)"
  if [ -n "$top_slice" ] && [ "${COST_TOKENS_PRICED:-0}" -gt 0 ]; then
    if [ $((top_tokens * 100)) -gt $((COST_TOKENS_PRICED * 30)) ]; then
      printf '  %s is %s%% of this unit'"'"'s priced total -- above the 30%% concentration threshold.\n' \
        "$top_slice" "$((top_tokens * 100 / COST_TOKENS_PRICED))"
      flagged=1
    fi
  fi
  [ "$flagged" -eq 0 ] && printf '  (no flags raised)\n'
}

# --- Budget (CO12): states configuration, evaluates nothing. Deciding
# anything against these thresholds is S4's job (check-budget-gate.sh);
# this only ever shows what a human would discover they set or did not. ----
print_budget() {
  local warn="${LARAVEL_LOOP_BUDGET_WARN:-}" hard="${LARAVEL_LOOP_BUDGET_HARD:-}"
  printf 'Budget:\n'
  if [ -z "$warn" ] && [ -z "$hard" ]; then
    printf '  no threshold is set (LARAVEL_LOOP_BUDGET_WARN, LARAVEL_LOOP_BUDGET_HARD are both unset) -- nothing will gate.\n'
    return 0
  fi
  printf '  LARAVEL_LOOP_BUDGET_WARN=%s\n' "${warn:-not set}"
  printf '  LARAVEL_LOOP_BUDGET_HARD=%s\n' "${hard:-not set}"
}

print_list() {
  local slugs s
  slugs="$(cost_list_slugs "$LEDGER")"
  if [ -z "$slugs" ]; then
    printf 'No units recorded in the cost ledger yet.\n'
    return 0
  fi
  printf 'Units in the cost ledger (most recent first):\n'
  printf '%s\n' "$slugs" | while IFS= read -r s; do
    [ -z "$s" ] && continue
    cost_scan "$LEDGER" "$s"
    printf '  %-40s %s\n' "$s" "$(cost_coverage_sentence)"
  done
}

if [ ! -f "$LEDGER" ]; then
  print_absent
  exit 0
fi
if [ ! -s "$LEDGER" ]; then
  print_empty
  exit 0
fi

if [ -z "$SLUG" ]; then
  print_list
  exit 0
fi

cost_scan "$LEDGER" "$SLUG"
case "$COST_SCAN_STATE" in
  absent) print_absent ;;
  empty) print_empty ;;
  no-slug) print_no_slug "$SLUG" ;;
  no-parser) printf 'Cannot read the cost ledger: neither jq nor python3 is on PATH. Install either one to use /cost.\n' ;;
  scan-error) printf 'Could not read the cost ledger (parse error). Nothing is reported, rather than a partial or wrong total.\n' ;;
  ok)
    print_coverage_and_tokens
    printf '\n'
    print_phases
    [ "${COST_N_PRICED:-0}" -gt 0 ] && printf '\n'
    print_rework
    printf '\n'
    print_slices_and_flags
    printf '\n'
    print_budget
    ;;
  *) printf 'Could not read the cost ledger.\n' ;;
esac

exit 0
