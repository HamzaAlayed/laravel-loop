#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034
# laravel-loop:sourced-library
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
#   cost_slice_rows <ledger-path> <slug-or-empty>   (added in cost-reporting-v0.3 S3)
#   cost_slice_unranked   (added in recovered-figure-drops-slice-and-model S1) -- takes
#     no arguments and reparses nothing; pure shell arithmetic over the globals cost_scan
#     and cost_slice_rows already published for the caller's own ledger/slug (CV7/CV8: one
#     arithmetic, two surfaces). A caller must have already called both for the ledger/slug
#     it wants this answer for -- both cost-report.sh and check-budget-gate.sh already do,
#     for other reasons, before calling this.
#   cost_invocation_lookup <ledger-path> <invocation-id>   (added in
#     cost-ledger-blind-to-background-agents S9, RC group) -- the one question
#     scripts/record-recovered-cost.sh needs answered before it may write
#     anything: "does this invocation_id already have a start/finish record in
#     this ledger, and if so, under which slug". A dedicated single-pass scan,
#     alongside cost_scan/cost_list_slugs/cost_slice_rows above rather than a
#     bespoke parser inside the CLI itself -- CV7/CV8's "one ledger, one
#     implementation" holds exactly the same way here as it does for every
#     other consumer of this file. Sets:
#       COST_INVOCATION_FOUND   "1" if a start or finish record for that
#                                invocation_id exists anywhere in the ledger,
#                                else "0" -- including when the ledger is
#                                absent, empty, or no parser is available
#                                (never fabricated, never a guess).
#       COST_INVOCATION_SLUG    the slug carried by that invocation's own
#                                records (a finish record's slug wins over a
#                                start's, matching cost_scan's own last-wins
#                                convention for this field), or "" if not found.
#     Only "start"/"finish" events are considered a match -- an existing
#     `recovered` record naming the same invocation_id is not itself proof of
#     a ledger entry, since RC4 requires the underlying invocation to already
#     be there.
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
# cost-ledger-blind-to-background-agents S1 additions to cost_scan (CL1, CL2, CL9):
#   COST_N_UNPRICED_BACKGROUNDED  of COST_N_UNPRICED, the ones whose finish record carries
#                             status "async_launched" -- a launch, not an observed outcome
#                             (CL2: never folded into COST_N_INFLIGHT, which means "started,
#                             no finish record at all" -- an async_launched record DOES have
#                             a finish record, it is just not a resolved one).
#   COST_N_UNPRICED_NO_USAGE of COST_N_UNPRICED, the ones whose finish record's status is
#                             anything else non-empty (typically "completed") but carried no
#                             total_tokens -- the invocation was observed, just with no usage
#                             figure attached.
#   COST_N_UNPRICED_TRUNCATED of COST_N_UNPRICED, the ones whose finish record's status is
#                             "line_too_long" -- record-cost-event.sh's own oversize fallback.
#   COST_N_UNPRICED_UNSTATED of COST_N_UNPRICED, the ones whose finish record carries no
#                             `status` field at all (missing key or JSON null) -- read
#                             without error and reported as its own reason, never guessed
#                             into any of the three above (CL9).
#   The four sum to COST_N_UNPRICED exactly; the reason is read only from the finish
#   record's own `status` field, per invocation, and nothing else -- never inferred from
#   phase, agent, or duration (CL1's own words).
#
# S2 addition (CL4, CL6): cost_coverage_sentence() now appends a coverage
# SHARE (COST_N_PRICED / COST_N_INVOCATIONS, as a percentage) and names every
# phase, of the five per-phase families above, that is *wholly* unobserved --
# at least one invocation and zero priced. Both are derived entirely from the
# COUNT variables already listed above; nothing new is added to cost_scan's
# output for this. Same sentence, same call sites (the report and the budget
# gate), so CL6 holds by construction rather than by two call sites agreeing
# to format the same numbers twice.
#
# S7 additions to cost_scan (the second G1's RC group, RC1/RC2/RC5): a
# `recovered` record (pinned shape: {"ts", "event":"recovered",
# "invocation_id", "slug", "total_tokens", "token_source":"transcribed"} --
# no other field) is merged into the SAME per-invocation entry as its
# start/finish records, keyed by `invocation_id`, never a second entry -- so
# however many `recovered` records name one invocation, it is still one
# invocation, priced at most once (RC1). It never carries `phase`, so it
# never overrides the phase the invocation's own start/finish already set.
#   COST_N_PRICED_TRANSCRIBED of COST_N_PRICED, the ones with NO host-observed
#                             total_tokens (an ordinary finish never priced
#                             them) whose figure came only from a `recovered`
#                             record instead. An invocation already priced by
#                             its own finish record is never moved into this
#                             bucket by a later `recovered` line -- the
#                             observed figure always wins (S8 pinned
#                             precedence); this slice does not yet print that
#                             disagreement, only counts the unambiguous case.
#   COST_TOKENS_TRANSCRIBED  sum of total_tokens over that same subset -- a
#                             subset of COST_TOKENS_PRICED, never counted
#                             twice and never added on top of it.
# cost_coverage_sentence() appends a further clause -- "N of P priced
# figure(s) transcribed rather than host-observed (T of TOTAL priced
# token(s), S %)" -- only when COST_N_PRICED_TRANSCRIBED > 0, so a ledger
# holding no `recovered` record is byte-identical to before this addition
# (RC6, CL9). Same sentence, same call sites, so the budget gate inherits
# this clause the same way it inherited S2's share and phase list.
#
# S8 additions to cost_scan (RC3): when an invocation carries BOTH a
# host-observed figure (its own finish record's total_tokens) AND a
# transcribed one (a `recovered` record) and the two DISAGREE, that is
# never resolved silently -- S7's precedence (observed wins the total) does
# not change here; this slice only makes the disagreement visible. Equal
# figures are not a disagreement and produce no output at all (RC3's own
# boundary). Computed inside cost_scan's single existing reduce -- no
# second parse of the ledger (CV7):
#   COST_N_CONFLICTS         count of invocations whose observed and
#                             transcribed figures both exist and differ.
#                             Zero on a ledger with no `recovered` record,
#                             or where every recovered figure matches its
#                             observed one exactly.
#   COST_CONFLICT_ROWS       newline-joined TSV, one line per conflicting
#                             invocation: invocation_id<TAB>observed_tokens
#                             <TAB>transcribed_tokens, sorted by
#                             invocation_id ascending in byte order (never
#                             hash-iteration order -- CV7), following
#                             COST_SLICE_ROWS's shape.
# cost-report.sh's Tokens section prints these rows only when
# COST_N_CONFLICTS > 0, states which figure the total above actually used
# (the observed one, unchanged from S7), and never averages, maxes, mins,
# or overwrites either figure.
#
# S3 additions to cost_scan (same rules: never a fabricated 0, never a re-parse elsewhere):
#   COST_MODELS_SPEC / _SLICE / _BUILD / _VERIFY / _UNKNOWN
#                             comma-separated "model::model_source" pairs, one per distinct
#                             model actually seen on a PRICED invocation in that phase (CO4).
#                             Empty string means no priced invocation in that phase --
#                             callers render that as "unavailable", never "0" (cost-report.sh
#                             does this formatting; the lib hands over data, not prose).
#   COST_N_REWORK             resolved invocations (priced + unpriced) with phase_detail
#                             "rework" -- the "n" in "n of m invocations marked rework" (CO5)
#   COST_N_REWORK_PRICED      of those, the ones also priced
#   COST_TOKENS_REWORK_PRICED sum of total_tokens over priced rework invocations only -- a
#                             token SHARE is this divided by COST_TOKENS_PRICED, computed by
#                             the caller, never by this file re-deriving a percentage view
#   COST_REWORK_HAS_AMBIGUOUS "1" if any counted invocation carries rework_attribution
#                             "ambiguous", else "0" -- a caller must show it as ambiguous,
#                             never fold it into an unqualified count (v0.2 S5)
#   COST_REWORK_REFINE_PASSES comma-separated refine_passes counts, one per rework
#                             invocation, sorted by pass-count descending then invocation id
#                             ascending -- fixed sort keys so this is byte-identical on a
#                             re-run (CV7), never an unordered hash-iteration artifact
#   COST_CACHE_READ_PRICED_N count of priced invocations that carry a cache_read_tokens
#                             field at all (present, non-null) -- zero here means the field
#                             is absent from every priced record, which is the CV4 case a
#                             caller must render as "unavailable", never "0%"
#   COST_TOKENS_CACHE_READ    sum of cache_read_tokens over that same subset
#   COST_TOKENS_CACHE_DENOM   sum of total_tokens over that same subset (the share's
#                             denominator -- computed only over invocations that actually
#                             reported cache-read data, per CV5's "priced invocations only,
#                             and says so")
#   COST_TS_MIN               earliest `ts` seen on any start record for the requested slug,
#                             or -1 if none -- raw ledger data, never wall-clock-of-now
#   COST_TS_MAX               latest `ts` seen on any finish record for the requested slug,
#                             or -1 if none. (COST_TS_MAX - COST_TS_MIN) is a wall-clock
#                             SPAN, not a sum of durations -- CO11 forbids ever summing
#                             overlapping invocations' elapsed times into one "agent time"
#                             total, and this pair of timestamps is the only elapsed figure
#                             this file computes for exactly that reason.
#
# cost_slice_rows sets, as a side effect (call it directly, never through
# command substitution -- see the function's own comment for why), and also
# prints the same rows to stdout for a caller that only wants a stream:
#   COST_SLICE_UNKNOWN_PRICED count of priced invocations for the requested slug that carry
#                             no `slice` field at all. Non-zero means a per-slice ranking
#                             would silently exclude tokens that could belong to the biggest
#                             slice -- the signal cost-report.sh's Flags section uses to
#                             print "could not be assessed" instead of a ranking (CO7)
#   COST_SLICE_ROWS           newline-joined TSV, one line per slice that DOES have at least
#                             one priced invocation: slice<TAB>priced_tokens<TAB>
#                             priced_invocations<TAB>rework_priced_tokens<TAB>
#                             rework_priced_invocations, sorted by priced_tokens descending,
#                             ties broken by slice name ascending (byte ordering, never a
#                             locale-dependent sort -- CV7)
#
# recovered-figure-drops-slice-and-model S1 (RD3/RD4): cost_slice_rows's own ranking can be
# INCOMPLETE relative to the unit total cost_scan reports, two different ways -- a priced
# invocation carrying no `slice` at all (already counted once above, in
# COST_SLICE_UNKNOWN_PRICED), or a priced invocation this pass never recognised as priced in
# the first place (pre-S5, any invocation priced only by a `recovered` record, since this
# pass's own event filter discards that event type before any join happens). Either way, a
# concentration verdict computed only over the ranked rows would compare an incomplete
# population against the unit's whole priced total and could print a number nobody can trust.
# cost_slice_unranked() states the gap instead of hiding it, as pure arithmetic over what
# cost_scan and cost_slice_rows already published -- it re-parses nothing and re-implements
# neither pass. Sets, as a side effect (call it directly after cost_scan and cost_slice_rows
# have both already run for this ledger/slug; nothing here calls either itself):
#   COST_SLICE_OUTSIDE_N          COST_N_PRICED minus the sum of the `inv` column over every
#                             row in COST_SLICE_ROWS -- how many priced invocations this
#                             unit's total counts that the per-slice ranking does not.
#   COST_SLICE_OUTSIDE_TOKENS      COST_TOKENS_PRICED minus the sum of the `tokens` column over
#                             every COST_SLICE_ROWS row -- the token total that gap represents.
#   COST_SLICE_OUTSIDE_UNRECONCILED  "1" if either subtraction above would go negative (the
#                             ranked rows claim more invocations or tokens than cost_scan
#                             itself counted as priced -- the `noid` keying asymmetry pinned
#                             in slices.md is one way this can happen), else "0". Both OUTSIDE
#                             figures clamp to 0 in that case rather than ever printing a
#                             negative count; a caller checks UNRECONCILED explicitly, never
#                             infers it from a zero (a genuinely complete ranking also reads
#                             zero for both).
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
  #
  # cost-ledger-blind-to-background-agents S2 (CL4, CL6): the sentence above
  # is kept as a literal, unmodified prefix -- tests/guardrails.test.sh:1123's
  # grep -qF for it verbatim (BG3's coverage-honesty case) is exactly what
  # makes CL8 achievable, so nothing here reorders or rewords it. Everything
  # below is APPENDED: a coverage share, and the phases (of the per-phase
  # variables cost_scan already sets -- no second parse, CV7) that are
  # *wholly* unobserved -- at least one invocation and zero priced. A phase
  # with zero invocations at all is never named: absence is not a gap.
  local p="${COST_N_PRICED:-0}" n="${COST_N_INVOCATIONS:-0}" u="${COST_N_UNPRICED:-0}"
  local share=0
  [ "$n" -gt 0 ] && share=$(( p * 100 / n ))
  local ph inv_var pv_var inv pv label unobserved=""
  for ph in SPEC SLICE BUILD VERIFY UNKNOWN; do
    inv_var="COST_N_INVOCATIONS_$ph"
    pv_var="COST_N_PRICED_$ph"
    inv="${!inv_var}"
    pv="${!pv_var}"
    if [ "$inv" -gt 0 ] && [ "$pv" -eq 0 ]; then
      label="$(printf '%s' "$ph" | tr '[:upper:]' '[:lower:]')"
      if [ -z "$unobserved" ]; then
        unobserved="$label"
      else
        unobserved="$unobserved, $label"
      fi
    fi
  done
  # The space between the number and "%" is deliberate, not a typo: CV4
  # (tests/guardrails.test.sh's cache-read-share case) asserts the literal
  # substring "0%" appears nowhere in a fully-priced fixture's output, and a
  # tight "100%" contains that substring as its own last two characters. The
  # space keeps every share -- including 0% and 100% -- out of that trap
  # without touching CV4's own, unrelated formatting.
  local suffix=" -- ${share} % coverage"
  [ -n "$unobserved" ] && suffix="${suffix}; wholly unobserved: ${unobserved}"
  # S7 (RC1, RC2, RC5): appended, never reworded, and only when at least one
  # transcribed figure was actually counted -- a ledger with no `recovered`
  # record produces the identical suffix as before this clause existed
  # (RC6, CL9). "N %" spacing throughout, per CV4's 0% trap.
  local pt="${COST_N_PRICED_TRANSCRIBED:-0}" tt="${COST_TOKENS_TRANSCRIBED:-0}" tp="${COST_TOKENS_PRICED:-0}"
  if [ "$pt" -gt 0 ]; then
    local tshare=0
    [ "$tp" -gt 0 ] && tshare=$(( tt * 100 / tp ))
    suffix="${suffix}; ${pt} of ${p} priced figure(s) transcribed rather than host-observed (${tt} of ${tp} priced token(s), ${tshare} %)"
  fi
  printf 'based on %s of %s invocations that carry a token figure (%s unpriced, not counted)%s' \
    "$p" "$n" "$u" "$suffix"
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
    elif (($r.event // "") == "start" or ($r.event // "") == "finish" or ($r.event // "") == "recovered") then
      (($r.slug // "unknown")) as $slg
      | .slugs[$slg] = 1
      | if ($slugfilter != "" and $slugfilter != $slg) then .
        else
          (($r.invocation_id // ("noid-" + ((.lines)|tostring)))) as $id
          | (.inv[$id] // {start:false, finish:false, priced:false, tokens:null, phase:"unknown",
                           model:null, model_source:null, ts_start:null, ts_finish:null,
                           cache_read:null, cache_read_present:false,
                           phase_detail:null, refine_passes:null, rework_attribution:null,
                           status:null, transcribed:false, transcribed_tokens:null}) as $e
          | ( $e
              | if $r.event == "start" then
                  (.start = true)
                  | (.phase = ($r.phase // .phase))
                  | (.model = ($r.model // .model))
                  | (.model_source = ($r.model_source // .model_source))
                  | (.ts_start = ($r.ts // .ts_start))
                else . end
              | if $r.event == "finish" then
                  (.finish = true)
                  | (.phase = ($r.phase // .phase))
                  | (.model = ($r.model // .model))
                  | (.model_source = ($r.model_source // .model_source))
                  | (.ts_finish = ($r.ts // .ts_finish))
                  | (.phase_detail = ($r.phase_detail // .phase_detail))
                  | (.refine_passes = ($r.refine_passes // .refine_passes))
                  | (.rework_attribution = ($r.rework_attribution // .rework_attribution))
                  | (.status = ($r.status // .status))
                  | (if (($r|has("total_tokens")) and ($r.total_tokens != null)) then
                       (.priced = true) | (.tokens = $r.total_tokens)
                     else
                       (.priced = false)
                     end)
                  | (if (($r|has("cache_read_tokens")) and ($r.cache_read_tokens != null)) then
                       (.cache_read_present = true) | (.cache_read = $r.cache_read_tokens)
                     else . end)
                else . end
              | if $r.event == "recovered" then
                  (if (($r|has("total_tokens")) and ($r.total_tokens != null)) then
                     (.transcribed = true) | (.transcribed_tokens = $r.total_tokens)
                   else . end)
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
       unpriced_backgrounded:0, unpriced_no_usage:0, unpriced_truncated:0, unpriced_unstated:0,
       priced_transcribed:0, tokens_transcribed:0,
       conflict_n:0, conflict_list:[],
       ts_min:null, ts_max:null,
       rework_n:0, rework_priced_n:0, rework_tokens:0, rework_ambiguous:0, rework_list:[],
       cache_n:0, cache_sum:0, cache_denom:0,
       byphase: { SPEC:{inv:0,priced:0,unpriced:0,inflight:0,tokens:0,models:{}},
                  SLICE:{inv:0,priced:0,unpriced:0,inflight:0,tokens:0,models:{}},
                  BUILD:{inv:0,priced:0,unpriced:0,inflight:0,tokens:0,models:{}},
                  VERIFY:{inv:0,priced:0,unpriced:0,inflight:0,tokens:0,models:{}},
                  UNKNOWN:{inv:0,priced:0,unpriced:0,inflight:0,tokens:0,models:{}} } }
   ;
     ($e.value.phase | phase_key) as $pk
   | (.inv += 1) | (.byphase[$pk].inv += 1)
   | (if $e.value.ts_start != null then
        (.ts_min = (if .ts_min == null then $e.value.ts_start else ([.ts_min, $e.value.ts_start] | min) end))
      else . end)
   | if $e.value.finish then
       (if $e.value.ts_finish != null then
          (.ts_max = (if .ts_max == null then $e.value.ts_finish else ([.ts_max, $e.value.ts_finish] | max) end))
        else . end)
       | (if $e.value.phase_detail == "rework" then
            (.rework_n += 1)
            | (.rework_list += [{id: $e.key, passes: ($e.value.refine_passes // 0)}])
            | (if $e.value.rework_attribution == "ambiguous" then (.rework_ambiguous = 1) else . end)
          else . end)
       | if $e.value.priced then
           (.priced += 1) | (.tokens += $e.value.tokens)
           | (.byphase[$pk].priced += 1) | (.byphase[$pk].tokens += $e.value.tokens)
           | (.byphase[$pk].models[(($e.value.model // "unavailable") + "::" + ($e.value.model_source // "unknown"))] = 1)
           | (if $e.value.cache_read_present then
                (.cache_n += 1) | (.cache_sum += $e.value.cache_read) | (.cache_denom += $e.value.tokens)
              else . end)
           | (if $e.value.phase_detail == "rework" then
                (.rework_priced_n += 1) | (.rework_tokens += $e.value.tokens)
              else . end)
           | (if ($e.value.transcribed and ($e.value.transcribed_tokens != $e.value.tokens)) then
                # S8 (RC3): both a host-observed and a transcribed figure
                # exist for this invocation and they disagree. The observed
                # figure already won the total above (S7's precedence,
                # unchanged); this only records the pair so the report can
                # show both and say so -- never resolved by averaging,
                # maxing, minning, or a silent overwrite.
                (.conflict_n += 1)
                | (.conflict_list += [{id: $e.key, observed: $e.value.tokens, transcribed: $e.value.transcribed_tokens}])
              else . end)
         elif $e.value.transcribed then
           # S7 (RC1, RC5): no host-observed figure exists for this
           # invocation -- its ONLY figure is the recovered one, so it
           # becomes priced here. An invocation already priced above never
           # reaches this branch (mutually exclusive `if`/`elif`), so the
           # observed figure is never displaced by a later `recovered` line.
           (.priced += 1) | (.tokens += $e.value.transcribed_tokens)
           | (.byphase[$pk].priced += 1) | (.byphase[$pk].tokens += $e.value.transcribed_tokens)
           | (.byphase[$pk].models[(($e.value.model // "unavailable") + "::" + ($e.value.model_source // "unknown"))] = 1)
           | (.priced_transcribed += 1) | (.tokens_transcribed += $e.value.transcribed_tokens)
           # S4 (OQ2): a rework-marked invocation priced ONLY by a recovered
           # figure counts toward the rework token share, exactly as the
           # host-observed branch above counts one -- with its transcribed
           # figure, since that is the figure that priced it. Without this the
           # report printed a non-zero rework count beside "token share:
           # unavailable (no priced invocations are marked rework)" while one
           # plainly was. cache_read is deliberately NOT extended here: that
           # is a separate, named gap (spec.md non-goal).
           | (if $e.value.phase_detail == "rework" then
                (.rework_priced_n += 1) | (.rework_tokens += $e.value.transcribed_tokens)
              else . end)
         else
           (.unpriced += 1) | (.byphase[$pk].unpriced += 1)
           | (($e.value.status // "")) as $st
           | (if $st == "async_launched" then (.unpriced_backgrounded += 1)
              elif $st == "line_too_long" then (.unpriced_truncated += 1)
              elif $st == "" then (.unpriced_unstated += 1)
              else (.unpriced_no_usage += 1)
              end)
         end
     elif $e.value.start then
       (.inflight += 1) | (.byphase[$pk].inflight += 1)
     else . end
   )) as $agg
| ( $agg.rework_list | sort_by([-(.passes), .id]) | map(.passes|tostring) | join(",") ) as $passeslist
| ( "COUNT\tCOST_N_LINES\t\($acc.lines)",
    "COUNT\tCOST_N_SKIPPED\t\($acc.skipped)",
    "COUNT\tCOST_N_CAPTRIP\t\($acc.captrip)",
    "COUNT\tCOST_N_INVOCATIONS\t\($agg.inv)",
    "COUNT\tCOST_N_PRICED\t\($agg.priced)",
    "COUNT\tCOST_N_UNPRICED\t\($agg.unpriced)",
    "COUNT\tCOST_N_UNPRICED_BACKGROUNDED\t\($agg.unpriced_backgrounded)",
    "COUNT\tCOST_N_UNPRICED_NO_USAGE\t\($agg.unpriced_no_usage)",
    "COUNT\tCOST_N_UNPRICED_TRUNCATED\t\($agg.unpriced_truncated)",
    "COUNT\tCOST_N_UNPRICED_UNSTATED\t\($agg.unpriced_unstated)",
    "COUNT\tCOST_N_INFLIGHT\t\($agg.inflight)",
    "COUNT\tCOST_TOKENS_PRICED\t\($agg.tokens)",
    "COUNT\tCOST_N_PRICED_TRANSCRIBED\t\($agg.priced_transcribed)",
    "COUNT\tCOST_TOKENS_TRANSCRIBED\t\($agg.tokens_transcribed)",
    "COUNT\tCOST_N_REWORK\t\($agg.rework_n)",
    "COUNT\tCOST_N_REWORK_PRICED\t\($agg.rework_priced_n)",
    "COUNT\tCOST_TOKENS_REWORK_PRICED\t\($agg.rework_tokens)",
    "COUNT\tCOST_REWORK_HAS_AMBIGUOUS\t\($agg.rework_ambiguous)",
    "COUNT\tCOST_CACHE_READ_PRICED_N\t\($agg.cache_n)",
    "COUNT\tCOST_TOKENS_CACHE_READ\t\($agg.cache_sum)",
    "COUNT\tCOST_TOKENS_CACHE_DENOM\t\($agg.cache_denom)",
    "COUNT\tCOST_TS_MIN\t\($agg.ts_min // -1)",
    "COUNT\tCOST_TS_MAX\t\($agg.ts_max // -1)",
    "COUNT\tCOST_N_CONFLICTS\t\($agg.conflict_n)",
    "REFINEPASSES\t\($passeslist)"
  ), (
    $agg.byphase | to_entries[] | (
      "COUNT\tCOST_N_INVOCATIONS_\(.key)\t\(.value.inv)",
      "COUNT\tCOST_N_PRICED_\(.key)\t\(.value.priced)",
      "COUNT\tCOST_N_UNPRICED_\(.key)\t\(.value.unpriced)",
      "COUNT\tCOST_N_INFLIGHT_\(.key)\t\(.value.inflight)",
      "COUNT\tCOST_TOKENS_PRICED_\(.key)\t\(.value.tokens)",
      "MODEL\t\(.key)\t\((.value.models | keys_unsorted | join(",")))"
    )
  ), (
    $acc.slugs | keys_unsorted[] | "SLUG\t\(.)"
  ), (
    # S8 (RC3): conflict rows, sorted by invocation_id ascending in byte
    # order -- jq's default string comparison is codepoint order, never a
    # hash-iteration artifact (CV7). Same read loop as every other line
    # cost_scan already emits; a fourth tab-separated column carries the
    # transcribed figure.
    $agg.conflict_list | sort_by(.id)[] | "CONFLICTROW\t\(.id)\t\(.observed)\t\(.transcribed)"
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
    if event in ("start", "finish", "recovered"):
        slugs[slg] = 1
        if slugfilter != "" and slugfilter != slg:
            continue
        invid = r.get("invocation_id") or ("noid-" + str(lines))
        e = inv.get(invid) or {"start": False, "finish": False, "priced": False,
                                "tokens": None, "phase": "unknown",
                                "model": None, "model_source": None,
                                "ts_start": None, "ts_finish": None,
                                "cache_read": None, "cache_read_present": False,
                                "phase_detail": None, "refine_passes": None,
                                "rework_attribution": None, "status": None,
                                "transcribed": False, "transcribed_tokens": None}
        if event == "start":
            e["start"] = True
            e["phase"] = r.get("phase") or e["phase"]
            e["model"] = r.get("model") or e["model"]
            e["model_source"] = r.get("model_source") or e["model_source"]
            e["ts_start"] = r.get("ts") if r.get("ts") is not None else e["ts_start"]
        if event == "finish":
            e["finish"] = True
            e["phase"] = r.get("phase") or e["phase"]
            e["model"] = r.get("model") or e["model"]
            e["model_source"] = r.get("model_source") or e["model_source"]
            e["ts_finish"] = r.get("ts") if r.get("ts") is not None else e["ts_finish"]
            e["phase_detail"] = r.get("phase_detail") or e["phase_detail"]
            e["refine_passes"] = r.get("refine_passes") if r.get("refine_passes") is not None else e["refine_passes"]
            e["rework_attribution"] = r.get("rework_attribution") or e["rework_attribution"]
            e["status"] = r.get("status") or e["status"]
            if "total_tokens" in r and r.get("total_tokens") is not None:
                e["priced"] = True
                e["tokens"] = r.get("total_tokens")
            else:
                e["priced"] = False
            if "cache_read_tokens" in r and r.get("cache_read_tokens") is not None:
                e["cache_read_present"] = True
                e["cache_read"] = r.get("cache_read_tokens")
        if event == "recovered":
            if "total_tokens" in r and r.get("total_tokens") is not None:
                e["transcribed"] = True
                e["transcribed_tokens"] = r.get("total_tokens")
        inv[invid] = e
        continue
    skipped += 1

agg = {"inv": 0, "priced": 0, "unpriced": 0, "inflight": 0, "tokens": 0,
       "unpriced_backgrounded": 0, "unpriced_no_usage": 0,
       "unpriced_truncated": 0, "unpriced_unstated": 0,
       "priced_transcribed": 0, "tokens_transcribed": 0,
       "conflict_n": 0,
       "ts_min": None, "ts_max": None,
       "rework_n": 0, "rework_priced_n": 0, "rework_tokens": 0, "rework_ambiguous": 0}
rework_list = []
conflict_rows = []
byphase = {k: {"inv": 0, "priced": 0, "unpriced": 0, "inflight": 0, "tokens": 0, "models": {}}
           for k in ("SPEC", "SLICE", "BUILD", "VERIFY", "UNKNOWN")}

for invid, e in inv.items():
    pk = phase_key(e["phase"])
    agg["inv"] += 1
    byphase[pk]["inv"] += 1
    if e["ts_start"] is not None:
        agg["ts_min"] = e["ts_start"] if agg["ts_min"] is None else min(agg["ts_min"], e["ts_start"])
    if e["finish"]:
        if e["ts_finish"] is not None:
            agg["ts_max"] = e["ts_finish"] if agg["ts_max"] is None else max(agg["ts_max"], e["ts_finish"])
        if e["phase_detail"] == "rework":
            agg["rework_n"] += 1
            rework_list.append((e["refine_passes"] or 0, invid))
            if e["rework_attribution"] == "ambiguous":
                agg["rework_ambiguous"] = 1
        if e["priced"]:
            agg["priced"] += 1
            agg["tokens"] += e["tokens"]
            byphase[pk]["priced"] += 1
            byphase[pk]["tokens"] += e["tokens"]
            mkey = (e["model"] or "unavailable") + "::" + (e["model_source"] or "unknown")
            byphase[pk]["models"][mkey] = 1
            if e["cache_read_present"]:
                agg["cache_n"] = agg.get("cache_n", 0) + 1
                agg["cache_sum"] = agg.get("cache_sum", 0) + e["cache_read"]
                agg["cache_denom"] = agg.get("cache_denom", 0) + e["tokens"]
            if e["phase_detail"] == "rework":
                agg["rework_priced_n"] += 1
                agg["rework_tokens"] += e["tokens"]
            if e["transcribed"] and e["transcribed_tokens"] != e["tokens"]:
                # S8 (RC3): both a host-observed and a transcribed figure
                # exist for this invocation and they disagree. The observed
                # figure already won the total above (S7's precedence,
                # unchanged); this only records the pair so the report can
                # show both and say so -- never resolved by averaging,
                # maxing, minning, or a silent overwrite.
                agg["conflict_n"] += 1
                conflict_rows.append((invid, e["tokens"], e["transcribed_tokens"]))
        elif e["transcribed"]:
            # S7 (RC1, RC5): no host-observed figure exists for this
            # invocation -- its ONLY figure is the recovered one, so it
            # becomes priced here. An invocation already priced above never
            # reaches this branch (the `if e["priced"]` above already took
            # it), so the observed figure is never displaced by a later
            # `recovered` line.
            agg["priced"] += 1
            agg["tokens"] += e["transcribed_tokens"]
            byphase[pk]["priced"] += 1
            byphase[pk]["tokens"] += e["transcribed_tokens"]
            mkey = (e["model"] or "unavailable") + "::" + (e["model_source"] or "unknown")
            byphase[pk]["models"][mkey] = 1
            agg["priced_transcribed"] += 1
            agg["tokens_transcribed"] += e["transcribed_tokens"]
            # S4 (OQ2): mirrors the host-observed branch above, with the
            # transcribed figure -- the one that priced this invocation. See
            # the jq program's comment; cache_read stays out by non-goal.
            if e["phase_detail"] == "rework":
                agg["rework_priced_n"] += 1
                agg["rework_tokens"] += e["transcribed_tokens"]
        else:
            agg["unpriced"] += 1
            byphase[pk]["unpriced"] += 1
            st = e["status"] or ""
            if st == "async_launched":
                agg["unpriced_backgrounded"] += 1
            elif st == "line_too_long":
                agg["unpriced_truncated"] += 1
            elif st == "":
                agg["unpriced_unstated"] += 1
            else:
                agg["unpriced_no_usage"] += 1
    elif e["start"]:
        agg["inflight"] += 1
        byphase[pk]["inflight"] += 1

rework_list.sort(key=lambda t: (-t[0], t[1]))
passeslist = ",".join(str(p) for p, _ in rework_list)

out = [
    f"COUNT\tCOST_N_LINES\t{lines}",
    f"COUNT\tCOST_N_SKIPPED\t{skipped}",
    f"COUNT\tCOST_N_CAPTRIP\t{captrip}",
    f"COUNT\tCOST_N_INVOCATIONS\t{agg['inv']}",
    f"COUNT\tCOST_N_PRICED\t{agg['priced']}",
    f"COUNT\tCOST_N_UNPRICED\t{agg['unpriced']}",
    f"COUNT\tCOST_N_UNPRICED_BACKGROUNDED\t{agg['unpriced_backgrounded']}",
    f"COUNT\tCOST_N_UNPRICED_NO_USAGE\t{agg['unpriced_no_usage']}",
    f"COUNT\tCOST_N_UNPRICED_TRUNCATED\t{agg['unpriced_truncated']}",
    f"COUNT\tCOST_N_UNPRICED_UNSTATED\t{agg['unpriced_unstated']}",
    f"COUNT\tCOST_N_INFLIGHT\t{agg['inflight']}",
    f"COUNT\tCOST_TOKENS_PRICED\t{agg['tokens']}",
    f"COUNT\tCOST_N_PRICED_TRANSCRIBED\t{agg['priced_transcribed']}",
    f"COUNT\tCOST_TOKENS_TRANSCRIBED\t{agg['tokens_transcribed']}",
    f"COUNT\tCOST_N_REWORK\t{agg['rework_n']}",
    f"COUNT\tCOST_N_REWORK_PRICED\t{agg['rework_priced_n']}",
    f"COUNT\tCOST_TOKENS_REWORK_PRICED\t{agg['rework_tokens']}",
    f"COUNT\tCOST_REWORK_HAS_AMBIGUOUS\t{agg['rework_ambiguous']}",
    f"COUNT\tCOST_CACHE_READ_PRICED_N\t{agg.get('cache_n', 0)}",
    f"COUNT\tCOST_TOKENS_CACHE_READ\t{agg.get('cache_sum', 0)}",
    f"COUNT\tCOST_TOKENS_CACHE_DENOM\t{agg.get('cache_denom', 0)}",
    f"COUNT\tCOST_TS_MIN\t{agg['ts_min'] if agg['ts_min'] is not None else -1}",
    f"COUNT\tCOST_TS_MAX\t{agg['ts_max'] if agg['ts_max'] is not None else -1}",
    f"COUNT\tCOST_N_CONFLICTS\t{agg['conflict_n']}",
    f"REFINEPASSES\t{passeslist}",
]
for k in ("SPEC", "SLICE", "BUILD", "VERIFY", "UNKNOWN"):
    v = byphase[k]
    out.append(f"COUNT\tCOST_N_INVOCATIONS_{k}\t{v['inv']}")
    out.append(f"COUNT\tCOST_N_PRICED_{k}\t{v['priced']}")
    out.append(f"COUNT\tCOST_N_UNPRICED_{k}\t{v['unpriced']}")
    out.append(f"COUNT\tCOST_N_INFLIGHT_{k}\t{v['inflight']}")
    out.append(f"COUNT\tCOST_TOKENS_PRICED_{k}\t{v['tokens']}")
    out.append(f"MODEL\t{k}\t{','.join(v['models'].keys())}")
for s in slugs.keys():
    out.append(f"SLUG\t{s}")

# S8 (RC3): conflict rows, sorted by invocation_id ascending -- Python's
# default string comparison is codepoint order, matching jq's and never a
# dict-iteration artifact (CV7).
for invid, observed, transcribed in sorted(conflict_rows, key=lambda t: t[0]):
    out.append(f"CONFLICTROW\t{invid}\t{observed}\t{transcribed}")

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
  COST_N_UNPRICED_BACKGROUNDED=0
  COST_N_UNPRICED_NO_USAGE=0
  COST_N_UNPRICED_TRUNCATED=0
  COST_N_UNPRICED_UNSTATED=0
  COST_N_INFLIGHT=0
  COST_TOKENS_PRICED=0
  COST_N_PRICED_TRANSCRIBED=0
  COST_TOKENS_TRANSCRIBED=0
  COST_N_CONFLICTS=0
  COST_CONFLICT_ROWS=""
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
  COST_N_REWORK=0
  COST_N_REWORK_PRICED=0
  COST_TOKENS_REWORK_PRICED=0
  COST_REWORK_HAS_AMBIGUOUS=0
  COST_REWORK_REFINE_PASSES=""
  COST_CACHE_READ_PRICED_N=0
  COST_TOKENS_CACHE_READ=0
  COST_TOKENS_CACHE_DENOM=0
  COST_TS_MIN=-1
  COST_TS_MAX=-1
  COST_MODELS_SPEC=""
  COST_MODELS_SLICE=""
  COST_MODELS_BUILD=""
  COST_MODELS_VERIFY=""
  COST_MODELS_UNKNOWN=""
}

_cost_apply_scan_line() {
  # $1 tag  $2 key-or-slug  $3 value (COUNT lines only)  $4 second value
  # (CONFLICTROW only -- the transcribed figure, alongside $3's observed one)
  local tag="$1" k="$2" v="${3:-}" v2="${4:-}"
  if [ "$tag" = "SLUG" ]; then
    if [ -z "$COST_SLUGS_PRESENT" ]; then
      COST_SLUGS_PRESENT="$k"
    else
      COST_SLUGS_PRESENT="$COST_SLUGS_PRESENT
$k"
    fi
    return 0
  fi
  if [ "$tag" = "MODEL" ]; then
    case "$k" in
      SPEC) COST_MODELS_SPEC="$v" ;;
      SLICE) COST_MODELS_SLICE="$v" ;;
      BUILD) COST_MODELS_BUILD="$v" ;;
      VERIFY) COST_MODELS_VERIFY="$v" ;;
      UNKNOWN) COST_MODELS_UNKNOWN="$v" ;;
      *) : ;;
    esac
    return 0
  fi
  if [ "$tag" = "REFINEPASSES" ]; then
    COST_REWORK_REFINE_PASSES="$k"
    return 0
  fi
  if [ "$tag" = "CONFLICTROW" ]; then
    # S8 (RC3): $k invocation_id, $v observed tokens, $v2 transcribed
    # tokens -- appended to COST_CONFLICT_ROWS in the order the scan program
    # already emitted them (sorted by invocation_id ascending, byte order),
    # following COST_SLICE_ROWS's own accumulation shape.
    local row
    row="$(printf '%s\t%s\t%s' "$k" "$v" "$v2")"
    if [ -z "$COST_CONFLICT_ROWS" ]; then
      COST_CONFLICT_ROWS="$row"
    else
      COST_CONFLICT_ROWS="$COST_CONFLICT_ROWS
$row"
    fi
    return 0
  fi
  [ "$tag" = "COUNT" ] || return 0
  case "$k" in
    COST_N_LINES) COST_N_LINES="$v" ;;
    COST_N_CONFLICTS) COST_N_CONFLICTS="$v" ;;
    COST_N_REWORK) COST_N_REWORK="$v" ;;
    COST_N_REWORK_PRICED) COST_N_REWORK_PRICED="$v" ;;
    COST_TOKENS_REWORK_PRICED) COST_TOKENS_REWORK_PRICED="$v" ;;
    COST_REWORK_HAS_AMBIGUOUS) COST_REWORK_HAS_AMBIGUOUS="$v" ;;
    COST_CACHE_READ_PRICED_N) COST_CACHE_READ_PRICED_N="$v" ;;
    COST_TOKENS_CACHE_READ) COST_TOKENS_CACHE_READ="$v" ;;
    COST_TOKENS_CACHE_DENOM) COST_TOKENS_CACHE_DENOM="$v" ;;
    COST_TS_MIN) COST_TS_MIN="$v" ;;
    COST_TS_MAX) COST_TS_MAX="$v" ;;
    COST_N_SKIPPED) COST_N_SKIPPED="$v" ;;
    COST_N_CAPTRIP) COST_N_CAPTRIP="$v" ;;
    COST_N_INVOCATIONS) COST_N_INVOCATIONS="$v" ;;
    COST_N_PRICED) COST_N_PRICED="$v" ;;
    COST_N_UNPRICED) COST_N_UNPRICED="$v" ;;
    COST_N_UNPRICED_BACKGROUNDED) COST_N_UNPRICED_BACKGROUNDED="$v" ;;
    COST_N_UNPRICED_NO_USAGE) COST_N_UNPRICED_NO_USAGE="$v" ;;
    COST_N_UNPRICED_TRUNCATED) COST_N_UNPRICED_TRUNCATED="$v" ;;
    COST_N_UNPRICED_UNSTATED) COST_N_UNPRICED_UNSTATED="$v" ;;
    COST_N_INFLIGHT) COST_N_INFLIGHT="$v" ;;
    COST_TOKENS_PRICED) COST_TOKENS_PRICED="$v" ;;
    COST_N_PRICED_TRANSCRIBED) COST_N_PRICED_TRANSCRIBED="$v" ;;
    COST_TOKENS_TRANSCRIBED) COST_TOKENS_TRANSCRIBED="$v" ;;
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

  local tag k v v2
  while IFS=$'\t' read -r tag k v v2; do
    [ -z "$tag" ] && continue
    _cost_apply_scan_line "$tag" "$k" "$v" "$v2"
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

# --- cost_slice_rows: added in cost-reporting-v0.3 S3 (see the doc block near
# the top of this file for what it sets and prints). A dedicated pass over
# the ledger, grouped by `slice` rather than `phase` -- a different bucketing
# dimension from cost_scan's, so it is its own function rather than a second
# thing cost_scan's single reduce would have to carry. Still degrades
# jq -> python3 -> a safe no-op, and still counts the three record shapes of
# E6 identically to cost_scan (cap_trip excluded; a start with no finish
# excluded; only a resolved, PRICED invocation contributes a token to a
# slice's total, per CV5). ---------------------------------------------------

_cost_slice_jq_program() {
  cat <<'JQ_EOF'
def to_rec: (try fromjson catch null);
(reduce (inputs | select(length > 0)) as $line
  ( {inv:{}}
  ; ($line | to_rec) as $r
  | if $r == null or ($r|type) != "object" then .
    elif (($r.event // "") == "start" or ($r.event // "") == "finish") then
      (($r.slug // "unknown")) as $slg
      | if ($slugfilter != "" and $slugfilter != $slg) then .
        else
          (($r.invocation_id // "noid")) as $id
          | (.inv[$id] // {start:false, finish:false, priced:false, tokens:null,
                           slice:null, phase_detail:null}) as $e
          | ( $e
              | if $r.event == "start" then (.start = true) | (.slice = ($r.slice // .slice)) else . end
              | if $r.event == "finish" then
                  (.finish = true)
                  | (.slice = ($r.slice // .slice))
                  | (.phase_detail = ($r.phase_detail // .phase_detail))
                  | (if (($r|has("total_tokens")) and ($r.total_tokens != null)) then
                       (.priced = true) | (.tokens = $r.total_tokens)
                     else
                       (.priced = false)
                     end)
                else . end
            ) as $ne
          | .inv[$id] = $ne
        end
    else . end
  )
) as $acc
| ($acc.inv | to_entries | map(select(.value.finish and .value.priced))) as $priced
| (reduce $priced[] as $e (
     {unknown:0, slices:{}}
   ;
     if (($e.value.slice // "") == "") then
       (.unknown += 1)
     else
       ($e.value.slice) as $s
       | (.slices[$s].tokens = ((.slices[$s].tokens // 0) + $e.value.tokens))
       | (.slices[$s].inv = ((.slices[$s].inv // 0) + 1))
       | (if $e.value.phase_detail == "rework" then
            (.slices[$s].rtokens = ((.slices[$s].rtokens // 0) + $e.value.tokens))
            | (.slices[$s].rinv = ((.slices[$s].rinv // 0) + 1))
          else . end)
     end
   )) as $sagg
| "META\tCOST_SLICE_UNKNOWN_PRICED\t\($sagg.unknown)",
  ( $sagg.slices | to_entries
    | sort_by([-(.value.tokens), .key])
    | .[]
    | "SLICEROW\t\(.key)\t\(.value.tokens)\t\(.value.inv)\t\(.value.rtokens // 0)\t\(.value.rinv // 0)"
  )
JQ_EOF
}

_cost_slice_py_program() {
  cat <<'PY_EOF'
import sys, json

slugfilter = sys.argv[1] if len(sys.argv) > 1 else ""
inv = {}

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
    event = r.get("event") or ""
    if event not in ("start", "finish"):
        continue
    slg = r.get("slug") or "unknown"
    if slugfilter != "" and slugfilter != slg:
        continue
    invid = r.get("invocation_id") or "noid"
    e = inv.get(invid) or {"start": False, "finish": False, "priced": False,
                            "tokens": None, "slice": None, "phase_detail": None}
    if event == "start":
        e["start"] = True
        e["slice"] = r.get("slice") or e["slice"]
    if event == "finish":
        e["finish"] = True
        e["slice"] = r.get("slice") or e["slice"]
        e["phase_detail"] = r.get("phase_detail") or e["phase_detail"]
        if "total_tokens" in r and r.get("total_tokens") is not None:
            e["priced"] = True
            e["tokens"] = r.get("total_tokens")
        else:
            e["priced"] = False
    inv[invid] = e

unknown = 0
slices = {}
for e in inv.values():
    if not (e["finish"] and e["priced"]):
        continue
    s = e["slice"] or ""
    if s == "":
        unknown += 1
        continue
    d = slices.setdefault(s, {"tokens": 0, "inv": 0, "rtokens": 0, "rinv": 0})
    d["tokens"] += e["tokens"]
    d["inv"] += 1
    if e["phase_detail"] == "rework":
        d["rtokens"] += e["tokens"]
        d["rinv"] += 1

out = [f"META\tCOST_SLICE_UNKNOWN_PRICED\t{unknown}"]
for s, d in sorted(slices.items(), key=lambda kv: (-kv[1]["tokens"], kv[0])):
    out.append(f"SLICEROW\t{s}\t{d['tokens']}\t{d['inv']}\t{d['rtokens']}\t{d['rinv']}")
print("\n".join(out))
PY_EOF
}

cost_slice_rows() {
  # Also sets COST_SLICE_ROWS as a global (the same TSV rows this prints to
  # stdout, newline-joined) precisely so a caller does not have to invoke
  # this through command substitution to read them -- command substitution
  # runs in a subshell, and COST_SLICE_UNKNOWN_PRICED (the side effect a
  # caller actually needs, for CO7) would never escape it. Read
  # COST_SLICE_ROWS / COST_SLICE_UNKNOWN_PRICED after calling this directly
  # (`cost_slice_rows ...`, not `x="$(cost_slice_rows ...)"`), the same way
  # cost_scan is called.
  local ledger="${1:-}" slug="${2:-}"
  COST_SLICE_UNKNOWN_PRICED=0
  COST_SLICE_ROWS=""

  [ -n "$ledger" ] && [ -f "$ledger" ] && [ -s "$ledger" ] || return 0

  local have_jq=0 have_py=0
  command -v jq >/dev/null 2>&1 && have_jq=1
  [ "$have_jq" -eq 0 ] && command -v python3 >/dev/null 2>&1 && have_py=1
  if [ "$have_jq" -eq 0 ] && [ "$have_py" -eq 0 ]; then
    return 0
  fi

  local out=""
  if [ "$have_jq" -eq 1 ]; then
    out="$(jq -Rn -r --arg slugfilter "$slug" "$(_cost_slice_jq_program)" < "$ledger" 2>/dev/null)"
  else
    out="$(python3 -c "$(_cost_slice_py_program)" "$slug" < "$ledger" 2>/dev/null)"
  fi

  local tag a b c d e row
  while IFS=$'\t' read -r tag a b c d e; do
    [ -z "$tag" ] && continue
    if [ "$tag" = "META" ] && [ "$a" = "COST_SLICE_UNKNOWN_PRICED" ]; then
      COST_SLICE_UNKNOWN_PRICED="$b"
    elif [ "$tag" = "SLICEROW" ]; then
      row="$(printf '%s\t%s\t%s\t%s\t%s' "$a" "$b" "$c" "$d" "$e")"
      printf '%s\n' "$row"
      if [ -z "$COST_SLICE_ROWS" ]; then
        COST_SLICE_ROWS="$row"
      else
        COST_SLICE_ROWS="$COST_SLICE_ROWS
$row"
      fi
    fi
  done <<EOF
$out
EOF
  return 0
}

# --- cost_slice_unranked: added in recovered-figure-drops-slice-and-model S1
# (see the doc block near the top of this file, next to cost_slice_rows's own,
# for exactly what this sets and why). Shell arithmetic only, over globals
# cost_scan and cost_slice_rows already set for the caller's own ledger/slug --
# this never opens the ledger itself and never re-implements either parser
# program (both are on this slice's Do NOT list). Summed with a here-string
# loop, deliberately never `printf | while`: bash 3.2 has no `lastpipe`, so a
# pipeline loop's body runs in a subshell and any sum it accumulates is lost
# the moment the pipeline exits -- cost-report.sh:392's own loop has exactly
# this shape and only ever prints, never accumulates, for the same reason. ---
cost_slice_unranked() {
  local ranked_inv=0 ranked_tokens=0 slice tokens inv _rtokens _rinv
  COST_SLICE_OUTSIDE_N=0
  COST_SLICE_OUTSIDE_TOKENS=0
  COST_SLICE_OUTSIDE_UNRECONCILED=0

  if [ -n "${COST_SLICE_ROWS:-}" ]; then
    while IFS=$'\t' read -r slice tokens inv _rtokens _rinv; do
      [ -z "$slice" ] && continue
      ranked_tokens=$((ranked_tokens + tokens))
      ranked_inv=$((ranked_inv + inv))
    done <<EOF
${COST_SLICE_ROWS}
EOF
  fi

  local n=$(( ${COST_N_PRICED:-0} - ranked_inv ))
  local t=$(( ${COST_TOKENS_PRICED:-0} - ranked_tokens ))

  if [ "$n" -lt 0 ] || [ "$t" -lt 0 ]; then
    COST_SLICE_OUTSIDE_UNRECONCILED=1
  else
    COST_SLICE_OUTSIDE_N="$n"
    COST_SLICE_OUTSIDE_TOKENS="$t"
  fi
  return 0
}

# --- cost_invocation_lookup: added in cost-ledger-blind-to-background-agents
# S9 (see the doc block near the top of this file for what it sets). A
# dedicated single-pass scan, same shape as cost_scan/cost_list_slugs/
# cost_slice_rows above: read every line once, degrade jq -> python3 -> a
# safe no-op, never a third bespoke parser living inside a caller. -----------

_cost_lookup_jq_program() {
  cat <<'JQ_EOF'
def to_rec: (try fromjson catch null);
(reduce (inputs | select(length > 0)) as $line
  ( {found:false, slug:""}
  ; ($line | to_rec) as $r
  | if $r == null or ($r|type) != "object" then .
    elif ($target == "") then .
    elif (($r.event // "") == "start" or ($r.event // "") == "finish")
         and (($r.invocation_id // "") == $target) then
      (.found = true) | (.slug = ($r.slug // .slug))
    else . end
  )
) as $acc
| "FOUND\t\(if $acc.found then "1" else "0" end)",
  "SLUG\t\($acc.slug)"
JQ_EOF
}

_cost_lookup_py_program() {
  cat <<'PY_EOF'
import sys, json

target = sys.argv[1] if len(sys.argv) > 1 else ""
found = False
slug = ""

for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "" or target == "":
        continue
    try:
        r = json.loads(line)
        if not isinstance(r, dict):
            raise ValueError()
    except Exception:
        continue
    event = r.get("event") or ""
    if event in ("start", "finish") and (r.get("invocation_id") or "") == target:
        found = True
        slug = r.get("slug") or slug

print(f"FOUND\t{'1' if found else '0'}")
print(f"SLUG\t{slug}")
PY_EOF
}

cost_invocation_lookup() {
  local ledger="${1:-}" target="${2:-}"
  COST_INVOCATION_FOUND=0
  COST_INVOCATION_SLUG=""

  [ -n "$ledger" ] && [ -f "$ledger" ] && [ -s "$ledger" ] && [ -n "$target" ] || return 0

  local have_jq=0 have_py=0
  command -v jq >/dev/null 2>&1 && have_jq=1
  [ "$have_jq" -eq 0 ] && command -v python3 >/dev/null 2>&1 && have_py=1
  if [ "$have_jq" -eq 0 ] && [ "$have_py" -eq 0 ]; then
    return 0
  fi

  local out=""
  if [ "$have_jq" -eq 1 ]; then
    out="$(jq -Rn -r --arg target "$target" "$(_cost_lookup_jq_program)" < "$ledger" 2>/dev/null)"
  else
    out="$(python3 -c "$(_cost_lookup_py_program)" "$target" < "$ledger" 2>/dev/null)"
  fi

  local tag v
  while IFS=$'\t' read -r tag v; do
    [ -z "$tag" ] && continue
    case "$tag" in
      FOUND) [ "$v" = "1" ] && COST_INVOCATION_FOUND=1 ;;
      SLUG) COST_INVOCATION_SLUG="$v" ;;
      *) : ;;
    esac
  done <<EOF
$out
EOF
  return 0
}
