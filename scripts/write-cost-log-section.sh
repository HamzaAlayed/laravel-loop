#!/usr/bin/env bash
# Writes the `## Cost` section of docs/loop/<slug>/log.md (spec.md DL1-DL5,
# DL7). Invoked by the close step (commands/loop.md, step 5) after log.md
# itself already exists -- this script never creates log.md, and never
# writes anything else under docs/loop/ (DL7, v0.2 H1). It never copies,
# moves, or mirrors the ledger; every figure below comes from
# scripts/cost-ledger-lib.sh, exactly as /cost's own report does, so the two
# can never disagree (CV7/CV8).
#
# The section is generated mechanically, not composed as prose by an agent:
# DL4's replace-not-append is arithmetic + a deterministic template, and a
# figure typed by hand stops being a figure anyone can trust as
# reproducible. Re-running this script replaces the `## Cost` section in
# place and disturbs no other byte of log.md -- `## Budget events` (S6's
# heading) included.
#
# Usage: scripts/write-cost-log-section.sh <slug>
#
# Exit codes: always 0. A close-step tool that can fail the unit over its
# own bookkeeping is worse than one that says plainly it could not write
# the section (matching cost-report.sh's own no-crash discipline).

set -uo pipefail

SLUG="${1:-}"
ROOT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

if [ -z "$SLUG" ]; then
  printf 'Usage: write-cost-log-section.sh <slug>\n' >&2
  exit 0
fi

LOG="$ROOT_DIR/docs/loop/$SLUG/log.md"
LEDGER="$ROOT_DIR/.claude/loop-cost.jsonl"

# The close step writes log.md first; this script never invents one. A
# missing log.md is not this script's problem to solve, and writing one
# here would be a second artifact type nobody asked for (DL7).
if [ ! -f "$LOG" ]; then
  printf 'No log.md found at docs/loop/%s/log.md -- nothing written. The close step writes log.md before this script runs.\n' "$SLUG" >&2
  exit 0
fi

# shellcheck source=cost-ledger-lib.sh
source "$SCRIPT_DIR/cost-ledger-lib.sh"

cost_scan "$LEDGER" "$SLUG"

# --- Rework wording, lifted from cost-report.sh's own print_rework (which
# lifted it from record-cost-event.sh's header) so the definition that
# travels with the figure here is the identical sentence a reader would see
# in /cost, never a second paraphrase of D3 (DL3). ---------------------------
print_rework_block() {
  printf 'Rework: this figure counts whole invocations that needed at least one refine pass, at\n'
  printf 'whole-invocation granularity -- deliberately over-attributing rather than estimating a\n'
  printf 'per-pass split, and NOT the cost of retrying. It is not comparable to the requirements\n'
  printf "document's <15%% target (Sec.10), which was calibrated against a narrower, per-pass\n"
  printf 'definition. No pass/fail verdict against that target is printed here.\n'
  local n="${COST_N_REWORK:-0}" m="${COST_N_INVOCATIONS:-0}"
  printf '  count: %s of %s invocation(s) marked rework\n' "$n" "$m"
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

# --- The body for the "ok" scan state: coverage first (DL2/CV1), then the
# priced-subset total labelled partial (DL1), then rework with its
# definition (DL3). No line here ever reads "within budget" or similar
# (BG6) -- this section states what was spent, never whether it was fine. --
print_ok_body() {
  printf 'Coverage: %s\n' "$(cost_coverage_sentence)"
  printf '\n'
  if [ "${COST_N_PRICED:-0}" -eq 0 ]; then
    printf "Tokens: nothing about this unit's token cost is observable -- %s of %s invocation(s)\n" \
      "$COST_N_PRICED" "$COST_N_INVOCATIONS"
    printf 'carry a token figure. No total is printed here (unmeasured, never zero).\n'
  else
    printf 'Tokens: %s (priced subset only, partial -- %s unpriced invocation(s) not counted)\n' \
      "$(cost_fmt "$COST_TOKENS_PRICED")" "${COST_N_UNPRICED:-0}"
  fi
  printf '\n'
  print_rework_block
}

# --- Every non-"ok" scan state still gets a section (DL5): a missing cost
# section and a cheap/unrun unit must never look identical in the log. None
# of these ever prints a token table, a zeroed row, or a reassurance token.
print_absent_body() {
  printf 'No cost ledger found at .claude/loop-cost.jsonl -- nothing recorded for this unit.\n'
  printf 'This is a wiring gap (hooks not registered, or LARAVEL_LOOP_COST_LEDGER=0), not\n'
  printf 'evidence the unit was free.\n'
}
print_empty_body() {
  printf 'The cost ledger exists but holds no records at all -- nothing recorded for this unit.\n'
  printf 'Not evidence the unit was free.\n'
}
print_no_slug_body() {
  printf 'No records for this unit ("%s") in the cost ledger. Not evidence the unit was free --\n' "$SLUG"
  printf 'the ledger simply has nothing filed under this slug.\n'
}
print_no_parser_body() {
  printf 'Could not read the cost ledger: neither jq nor python3 was on PATH when this section\n'
  printf 'was written. Nothing recorded for this unit -- not evidence it was free.\n'
}
print_scan_error_body() {
  printf 'Could not read the cost ledger (parse error). Nothing recorded for this unit -- not\n'
  printf 'evidence it was free.\n'
  # cost-log-section-parse-error-on-macos-ci S3 (PF1, PF2): names which
  # parser was selected, its exit status, and the route that produced this
  # state -- the three facts S2 publishes. NEVER the parser's own captured
  # stderr text (reading 1): jq and python3 both quote the offending input
  # in their own error messages, and DL7/H1 forbid ledger content anywhere
  # under docs/loop/. That text exists only in COST_SCAN_PARSER_STDERR,
  # which this function never reads.
  printf 'Parser: %s, exit status %s, route: %s. The parser wrote more to its own stderr on\n' \
    "${COST_SCAN_PARSER:-unavailable}" "${COST_SCAN_PARSER_STATUS:-unavailable}" "${COST_SCAN_ROUTE:-unavailable}"
  printf 'this run -- never repeated here, and never written under docs/loop/.\n'
}

# S3's own body for a state neither this script nor a person recognises --
# no longer print_scan_error_body's sentence verbatim (today's `*)` arm),
# which made "the scan genuinely failed" and "the caller does not
# understand its own answer" indistinguishable to every reader. Named
# unreachable by construction (the library and this script agree on every
# value COST_SCAN_STATE can hold), so this exists purely so a future
# divergence between the two says what it is rather than lying as a parse
# error.
print_unrecognised_state_body() {
  printf 'The cost scan returned a state this script does not recognise ("%s"). Nothing recorded\n' \
    "${COST_SCAN_STATE:-<unset>}"
  printf 'for this unit -- not evidence it was free, and not the same thing as a parse error.\n'
}

build_section_body() {
  case "$COST_SCAN_STATE" in
    absent) print_absent_body ;;
    empty) print_empty_body ;;
    no-slug) print_no_slug_body ;;
    no-parser) print_no_parser_body ;;
    scan-error) print_scan_error_body ;;
    ok) print_ok_body ;;
    *) print_unrecognised_state_body ;;
  esac
}

NEWSECTION="$(mktemp)"
trap 'rm -f "$NEWSECTION"' EXIT
{
  printf '## Cost\n\n'
  build_section_body
  printf '\n'
} > "$NEWSECTION"

# --- Replace the `## Cost` section in place, or append it if this is the
# first close on this unit. Everything else in log.md -- every other
# heading, `## Budget events` included -- passes through byte-for-byte
# (DL4). Lines between the old `## Cost` heading and the next `## ` heading
# (or EOF) are the only ones ever discarded. ---------------------------------
TMP_OUT="$(mktemp)"
awk -v newfile="$NEWSECTION" '
  BEGIN {
    n = 0
    while ((getline line < newfile) > 0) {
      n++
      news[n] = line
    }
    close(newfile)
    found = 0
    skipping = 0
  }
  {
    if ($0 == "## Cost") {
      found = 1
      skipping = 1
      for (i = 1; i <= n; i++) print news[i]
      next
    }
    if (skipping == 1) {
      if ($0 ~ /^## /) {
        skipping = 0
      } else {
        next
      }
    }
    print $0
  }
  END {
    if (found == 0) {
      print ""
      for (i = 1; i <= n; i++) print news[i]
    }
  }
' "$LOG" > "$TMP_OUT" && mv "$TMP_OUT" "$LOG"

# cost-log-section-parse-error-on-macos-ci S3 (PF3): a degraded write says
# so on stderr, naming the slug and (when the scan has one to name) the
# route -- the moment nobody was told about before this slice (spec.md's
# Problem, item 1). An "ok" write stays completely silent here: no byte,
# not even a "wrote section" line (PF10). The route is only ever non-empty
# for scan-error (S2's three-way split); for the other four degraded
# states the state name IS the whole story, so it stands in for the route.
if [ "$COST_SCAN_STATE" != "ok" ]; then
  if [ -n "${COST_SCAN_ROUTE:-}" ]; then
    printf 'Cost section for "%s" degraded while writing -- state: %s, route: %s. See docs/loop/%s/log.md.\n' \
      "$SLUG" "$COST_SCAN_STATE" "$COST_SCAN_ROUTE" "$SLUG" >&2
  else
    printf 'Cost section for "%s" degraded while writing -- state: %s. See docs/loop/%s/log.md.\n' \
      "$SLUG" "$COST_SCAN_STATE" "$SLUG" >&2
  fi
fi

exit 0
