# Slices — recovered-figure-drops-slice-and-model

Phase: Slice (G1). Cut from `spec.md` in this directory, APPROVED at G0 with OQ2 (in scope), OQ4
(the 21 existing records must benefit without being re-typed) and OQ5 (resumed-invocation gap out
of scope) settled there. **OQ1 and OQ3 are not settled here** — they are costed at the end of this
file and carried to G1.

## The cut is reader-side, and this says so on purpose

Every slice below is a **reader** fix (OQ1 answer **(b)**). `scripts/record-recovered-cost.sh` is
untouched, the pinned `recovered` record shape keeps its "no other field, ever" wording, and
`hooks/hooks.json` and `scripts/record-cost-event.sh` are on every slice's `Do NOT`.

Cut on that basis because **G0 settled OQ4 yes**, and the field evidence makes the consequence
concrete rather than theoretical. Measured against the maintainer's local ledger on 2026-08-18
(read-only, nothing edited):

- 21 `recovered` records across two units, 104 ledger lines.
- All 21 join to `start`/`finish` records carrying `"model":"opus"` or `"sonnet"` with
  `"model_source":"derived"` — so **RD1 is satisfiable for every existing record** by reading.
- **16 of 21** join to records carrying a `slice` field; **5** (spec/slice/verify-phase
  invocations, which have no `Slice:` line by protocol) carry none — so RD2 restores 16 and RD5
  must report the other 5 as unattributed rather than guessing.
- `bash scripts/cost-report.sh harness-fails-only-on-linux` today prints 100 % coverage,
  1,650,438 priced tokens, `spec/slice/build/verify` all `unavailable`, `no slice attributed to
  any priced invocation`, and `Flags: (no flags raised)`. That is the whole defect, reproducible on
  a real unit, with no fixture.

A writer answer (a) does not avoid the work it looks like it avoids: all 21 records are the old
shape, so under (a) the reader must accept **both** shapes anyway, or a backfill mechanism must
exist — a new script and a new consent question about rewriting ledger lines, which the spec's
non-goals push against. No criterion RD1–RD11 is satisfied by (a) that (b) does not satisfy.
**If the human answers OQ1 (a) or split at G1, S3 and S5 are replaced, not amended; S1, S2 and S6
survive unchanged.** No slice below quietly assumes the writer question is closed forever — it
assumes the answer G0's own OQ4 decision forces, and says so here so it can be overturned in one
place.

## Pinned contracts for this unit

A slice that believes one of these is wrong returns `needs-decision` rather than changing it.

| Contract | Value | Who sets / who reads | Why pinned |
|---|---|---|---|
| Record shape | `{"ts","event":"recovered","invocation_id","slug","total_tokens","token_source":"transcribed"}` — **unchanged** | `record-recovered-cost.sh` writes; `cost_scan` and (after S5) `cost_slice_rows` read | The pin is documented twice (`record-recovered-cost.sh:47-53`, `cost-ledger-lib.sh:131-137`). Only a human may overturn it (OQ1) |
| Observed-wins precedence | An invocation with a host-observed figure is never displaced by a transcribed one, in **either** pass | `cost_scan` `:429`/`:434` today; S5 mirrors it into the slice pass | RC3/RD7. A second pass that resolves precedence differently is two truths from one ledger |
| Exactly-once | Two `recovered` lines for one `invocation_id` yield one invocation, one attribution, one model entry | every pass | RC1/RD6 |
| `unavailable` sentinel | The literal string `unavailable`, never `0`, never a fabricated model name | `format_models()`; S3 keeps the key shape `<model>::<model_source>` | CO4/RD5 |
| `SLICEROW` column contract | **5 tab-separated columns** — `slice, tokens, inv, rtokens, rinv` — unchanged by every slice below | `_cost_slice_*_program` emits; `cost-report.sh:392` and `check-budget-gate.sh:382` both `read` exactly 5 | Both consumers read positionally. A 6th column silently lands in the gate's `top_rinv` and corrupts its rework share. Growing this is **S7's** business (OQ3(b)), never a side effect |
| New shared helper | `cost_slice_unranked` in `cost-ledger-lib.sh` — sets `COST_SLICE_OUTSIDE_N`, `COST_SLICE_OUTSIDE_TOKENS`, `COST_SLICE_OUTSIDE_UNRECONCILED` | S1 adds; `cost-report.sh` and `check-budget-gate.sh` both call | CV7/CV8: one arithmetic, two surfaces. Two copies of this subtraction is exactly the failure the lib exists to prevent |
| Unreconciled guard | If the subtraction would go negative, both figures clamp to 0 and `COST_SLICE_OUTSIDE_UNRECONCILED=1`; consumers then say the ranking could not be reconciled and print **no** percentage | S1 | A negative token count printed in a report is worse than the gap it describes |
| Both parsers, always | Any change inside `_cost_scan_*` or `_cost_slice_*` lands in **both** the jq and the python program in the same commit | S3, S4, S5 | The two disagree by construction otherwise. S2 exists so the suite can tell |
| `noid` asymmetry | `cost_scan` keys a record with no `invocation_id` as `noid-<line>` (unique); the slice pass keys it `noid` (collapsing). **Left as is** | — | It is pre-existing, not this defect, and the two passes' populations can legitimately differ there. S1's reconciliation must *state* the gap; S5 must not "fix" the keying. Either lane finding it bites returns `needs-decision` |
| No threshold ships | The 30 % concentration figure is neither raised, lowered, nor made configurable; no coverage floor, budget or per-phase value ships set, commented out, or suggested | every slice | spec.md non-goal, and the repo's standing rule |
| Case-count arbiter | The harness's own **last** case (`docs (case count)`) is the arbiter of `README.md:167` | every case-adding slice | A lane whose honest delta differs from the table below states it in its return and computes the literal from its own base |

### The one reading of an approved criterion this pass makes — flagged, not buried

**RD3 vs RD8 collide on one fixture class**: a *recovery-free* ledger that holds a priced
invocation with no `slice`. Today that prints, in **Flags** only, `concentration could not be
assessed -- 1 priced invocation(s) carry no slice attribution` and no token figure. RD3 wants the
count **and the tokens**, in the ranking's own section. RD8 wants recovery-free output
byte-identical.

Read here as: **RD8's purpose is RC6** — that the *transcription feature* leaves no trace on a run
that used none — not a freeze on the report. Making honesty conditional on the presence of a
`recovered` record is the very coupling this unit removes. So S1 adds the token figure for that
class too, leaving the existing Flags sentence byte-identical, and RD8 is asserted on a
recovery-free fixture whose priced invocations all carry a slice.

Checked before proposing it: no existing case freezes a full report as a literal string. The two
`(i) CV7` cases diff a report against a **re-run of itself**, and `(d) CO7`'s unassessable case
greps for the sentence S1 preserves verbatim — so no existing case turns red. If the human prefers
RD8's letter, option 2 at the gate is: gate S1's new line on `COST_N_PRICED_TRANSCRIBED > 0`
(weaker, and it makes the report's honesty depend on a record type).

## Case-count delta table

`README.md:167` reads **427 cases** today. Planned deltas, each lane bumping the literal itself:

| Slice | Δ cases | Literal after |
|---|---|---|
| S1 | +7 | 434 |
| S2 | +5 | 439 |
| S3 | +6 | 445 |
| S4 | +4 | 449 |
| S5 | +7 | 456 |
| S6 | +4 | **460** |

New cases append **before** the final `docs (case count)` case, which stays last in the file. No
lane edits, skips, weakens or renumbers an existing case; the count never goes down.

## Slices

Six cut, one (**S7**) deliberately left uncut behind OQ3. Envelopes are verbatim build briefs.

### S1 — Make an incomplete slice ranking say so, and gate the concentration verdict on population equality
```
Owner:       loop-build
Unit:  recovered-figure-drops-slice-and-model
Slice: S1
Context:     - docs/loop/recovered-figure-drops-slice-and-model/spec.md — RD3, RD4, and the
               "RD3 vs RD8" reading above.
             - scripts/cost-report.sh:370-411 (print_slices_and_flags) — the three-branch
               Flags logic and the `(no flags raised)` fall-through this slice fixes.
             - scripts/check-budget-gate.sh:365-400 (print_breach_message) — the SECOND
               consumer of the same ranking, with its own three-branch caveat and its own
               "re-slice the largest share" recommendation.
             - scripts/cost-ledger-lib.sh — cost_slice_rows sets COST_SLICE_ROWS /
               COST_SLICE_UNKNOWN_PRICED as globals; cost_scan sets COST_N_PRICED /
               COST_TOKENS_PRICED. Both are already called by both consumers.
             - Live reproduction, no fixture needed:
               `bash scripts/cost-report.sh harness-fails-only-on-linux` → 1,650,438 priced
               tokens, empty ranking, `Flags: (no flags raised)`.
Constraints: - Add ONE shared helper, `cost_slice_unranked`, to scripts/cost-ledger-lib.sh:
               COST_SLICE_OUTSIDE_N = COST_N_PRICED − Σ(ranked inv), COST_SLICE_OUTSIDE_TOKENS
               = COST_TOKENS_PRICED − Σ(ranked tokens), and COST_SLICE_OUTSIDE_UNRECONCILED=1
               with both clamped to 0 if either subtraction goes negative. Both consumers call
               it; neither re-implements the subtraction (CV7/CV8).
             - Do NOT touch either parser program (`_cost_scan_*`, `_cost_slice_*`). This slice
               is shell arithmetic over values both passes already publish, which is why it can
               land first and why it costs nothing in the dangerous region.
             - Sum the rows with a here-doc/here-string loop, never `printf | while` —
               bash 3.2 has no `lastpipe`, and cost-report.sh:392's existing pipeline loop
               cannot export a sum. Both bash 3.2 and the runner's bash.
             - Keep the existing `COST_SLICE_UNKNOWN_PRICED > 0` Flags sentence in
               cost-report.sh byte-identical, wording and section; only the new
               unattributed-tokens line in the Slices section is added for that path.
             - A concentration percentage prints only when COST_SLICE_OUTSIDE_N is 0 and
               UNRECONCILED is 0. No threshold value changes; the 30 % figure is untouched.
             - The gate's breach message must not recommend re-slicing a top slice as "the
               largest share" while priced tokens sit outside the ranking — it says how many
               and how much instead.
             - shellcheck -S warning scripts/*.sh clean; every path still exits 0.
Output:      scripts/cost-ledger-lib.sh (new helper only), scripts/cost-report.sh,
             scripts/check-budget-gate.sh, tests/guardrails.test.sh (+7), README.md:167 → 434.
Done when:   On any ledger where priced tokens sit outside the per-slice ranking, both the
             report and the budget gate say how many invocations and how many tokens are
             unattributed, and neither prints a concentration verdict.
Test set:    7 cases. Selection rule: 3 population states (complete / incomplete-by-missing-
             slice / incomplete-because-the-pass-never-saw-it) × 2 consumers = 6 pairwise,
             reduced to 5 by making the third state's case an agreement assertion across both
             consumers, plus 2 no-change guards.
             1. all-transcribed fixture (real shape: start+finish carrying model+slice,
                finish `async_launched` with no total_tokens, plus a `recovered` line):
                `(no flags raised)` does NOT appear.  FAILS TODAY — today prints exactly that.
             2. same fixture: the Slices section names the unattributed count and token total,
                and they equal COST_N_PRICED / COST_TOKENS_PRICED.  FAILS TODAY.
             3. mixed fixture (observed S2 10,000 + transcribed S1 50,000): no `concentration
                threshold` string anywhere.  FAILS TODAY.
             4. guard: the `(d) CO7` unassessable shape still prints
                `could not be assessed -- 1 priced invocation(s) carry no slice attribution`
                verbatim.
             5. guard, RD8: recovery-free fixture with every priced invocation carrying a
                slice → report output byte-identical to a frozen expected block.
             6. gate breach message on the mixed fixture (LARAVEL_LOOP_BUDGET_HARD set): names
                no top slice as the largest share without stating what sits outside.
                FAILS TODAY.
             7. RD10: report and gate state the SAME unattributed count for one fixture.
             Assertions 1-3 and 6 are falsified by construction (today's output is quoted in
             spec.md); the lane states in its return which it saw red before writing code.
Do NOT:      Do not edit `_cost_scan_jq_program`, `_cost_scan_py_program`,
             `_cost_slice_jq_program`, `_cost_slice_py_program`, `scripts/record-cost-event.sh`,
             `scripts/record-recovered-cost.sh`, `hooks/hooks.json`, or
             `scripts/write-cost-log-section.sh`. Do not change the SLICEROW column count. Do
             not change the 30 % threshold or add any configurable threshold. Do not touch
             `.claude/loop-cost.jsonl`. Do not edit any file under
             `docs/loop/eviction-cap-not-honoured-under-contention/`.
Depends on:  nothing.
```

### S2 — Give the suite a way to tell whether the two parser programs still agree
```
Owner:       loop-build
Unit:  recovered-figure-drops-slice-and-model
Slice: S2
Context:     - scripts/cost-ledger-lib.sh — every reader ships TWICE, once in jq and once in
               python3 (`_cost_scan_jq_program` / `_cost_scan_py_program`,
               `_cost_slice_jq_program` / `_cost_slice_py_program`). spec.md's Constraints:
               "Any change lands in BOTH parser programs, or the two disagree by construction."
             - tests/guardrails.test.sh — established finding: NO case exercises the python
               programs. `grep -n 'PATH=' tests/guardrails.test.sh` shows only jq+python3-BOTH-
               absent fixtures (`:969`, `:2074`) and the shellcheck-absent helper (`:2636`,
               `new_shellcheck_absent_path`) — nothing that keeps python3 while removing jq.
             - Working technique, verified 2026-08-18 on this host: symlink every entry of
               /usr/bin /bin /usr/sbin /sbin /opt/homebrew/bin /usr/local/bin into a temp dir,
               skipping `jq`. `bash scripts/cost-report.sh harness-fails-only-on-linux` then
               ran through the python path and was byte-identical to the jq run. A sparser
               PATH is NOT sufficient — the lib shells out to grep/sed and reports a parse
               error, which would make a parity case pass for the wrong reason.
Constraints: - Add one helper (`new_jq_absent_path`, same shape as `new_shellcheck_absent_path`)
               and a self-check case that under it `command -v python3` succeeds and
               `command -v jq` fails — a parity case over a broken PATH proves nothing.
             - Parity is asserted on EXISTING fixtures only. This slice adds no product
               behaviour and changes no script under scripts/.
             - Falsification is mandatory and reported: temporarily break one arm of one parser
               program in the working tree, watch a parity case go red, revert, and state that
               in the return. A parity case that has never been seen red is a description.
Output:      tests/guardrails.test.sh (+5), README.md:167 → 439.
Done when:   Editing one parser program without its twin turns the suite red, and the return
             shows that happening.
Test set:    5 cases. Rule: one self-check of the fixture, then one parity case per reader the
             later slices touch (cost_scan via the full report, cost_slice_rows via its rows),
             over the two fixture shapes that already exercise recovered records.
             1. `new_jq_absent_path` resolves python3 and not jq.  FAILS TODAY (no helper).
             2. full report byte-identical jq vs python3 on the S7 recovered fixture (:1114).
             3. same on the S8 observed/transcribed conflict fixture (:1243).
             4. same on the `(d) CO7` concentration fixture (:1760).
             5. cost_slice_rows' rows byte-identical jq vs python3 on the concentration fixture.
Do NOT:      Do not edit any file under scripts/ — if a parity case goes red on today's HEAD,
               that is a found defect: report it as `needs-decision`, do not fix it here. Do
               not modify or renumber an existing case. Do not touch
               `.claude/loop-cost.jsonl`, `hooks/hooks.json`, or any other unit's artifacts.
Depends on:  nothing logically. Textual only: land after S1 so the README literal moves once
             per merge (S1 → 434, this → 439).
```

### S3 — Restore the per-phase model for a figure that is transcribed-only
```
Owner:       loop-build
Unit:  recovered-figure-drops-slice-and-model
Slice: S3
Context:     - spec.md RD1, RD5 (model half), RD6, RD11.
             - scripts/cost-ledger-lib.sh:417 (jq) and :617 (python) — the ONLY place the
               per-phase model set is written, inside the host-observed branch.
             - :434-442 (jq) / :634-646 (python) — the transcribed-only branch immediately
               below: increments priced and tokens, writes no model. That omission is the whole
               defect. The joined entry already holds `.model` / `.model_source` (:349-350,
               :356-357) because cost_scan merges `recovered` into the same entry by
               invocation_id.
             - scripts/cost-report.sh:301-320 `format_models()` — the consumer. Key shape is
               `<model>::<model_source>`; `derived` renders as `opus (derived)`; an empty set
               renders `unavailable`.
             - Field shape: real records carry `"model":"opus","model_source":"derived"` on
               both start and finish (verified 2026-08-18 against all 21 recovered records).
Constraints: - One added write per parser program, reusing the existing key expression
               verbatim so the two branches cannot drift in how they spell a model.
             - `(.model // "unavailable")` behaviour is retained: no model on the joined
               records → the literal `unavailable`, never a fabricated or inherited name, never
               borrowed from another phase or another invocation (RD5).
             - A phase holding both an observed invocation with a model and a transcribed one
               with none prints both entries; it never suppresses either.
             - Both parser programs in this commit (S2's parity cases enforce it).
             - No new field, no new counter, no output outside the Phases block.
Output:      scripts/cost-ledger-lib.sh (both `_cost_scan_*` programs),
             tests/guardrails.test.sh (+6), README.md:167 → 445.
Done when:   On a unit whose priced figures are all transcribed, the Phases block names the
             model those invocations' own start/finish records carry, marked `(derived)` where
             the records say derived — and `bash scripts/cost-report.sh ship-gate-blind-to-ci`
             no longer reads `unavailable` for a phase whose records carry a model.
Test set:    6 cases. Rule: happy path, then each boundary RD5/RD6/RD8/RD11 names, plus the
               parser-parity arm S2 made possible.
             1. all-transcribed fixture whose records carry model+model_source: the phase line
                reads `opus (derived)`.  FAILS TODAY — reads `unavailable`.
             2. RD5: a transcribed-only invocation whose records carry NO model → that phase
                reads `unavailable`; the output contains no model name absent from the ledger.
             3. mixed phase: observed(model X) + transcribed(no model) → both entries named,
                neither dropped.
             4. RD6: the recovered line duplicated → identical phase model line and identical
                counters to the single-line fixture.
             5. RD8: recovery-free fixture → report output byte-identical to a frozen block.
             6. RD11: PATH stripped of BOTH jq and python3 against a ledger holding recovered
                records → today's `neither jq nor python3` message, exit 0, no partial figure.
             Plus S2's parity cases must stay green, which is what proves the python arm.
Do NOT:      Do not touch `_cost_slice_*` (that is S5), the Rework branch (that is S4),
               `scripts/record-recovered-cost.sh`, `scripts/record-cost-event.sh`,
               `hooks/hooks.json`, or the `recovered` record shape. Do not add a per-row
               transcribed marker to the model line — that is S7, behind OQ3. Do not touch
               `.claude/loop-cost.jsonl` or any other unit's artifacts.
Depends on:  S2 — not textually but for evidence: S3 is the first change inside a parser
             program, and S2's parity cases are what prove the python arm was edited too.
             Landing S3 first would ship an unverifiable half of the constraint spec.md calls
             "disagree by construction".
```

### S4 — Stop the report contradicting itself about rework token share (OQ2, in scope at G0)
```
Owner:       loop-build
Unit:  recovered-figure-drops-slice-and-model
Slice: S4
Context:     - spec.md's third established statement: on a mixed fixture the report prints
               `count: 1 of 2 invocation(s) marked rework (refine passes: 2)` and, two lines
               later, `token share: unavailable (no priced invocations are marked rework)`.
             - scripts/cost-ledger-lib.sh:422 (jq) / :623-624 (python) — rework_priced_n and
               rework_tokens are incremented ONLY in the host-observed branch, same branch as
               S3's omission.
             - scripts/cost-report.sh:340-365 `print_rework()` — the consumer; expected to
               need NO edit, its sentence simply becomes true.
             - scripts/write-cost-log-section.sh:70 — the second consumer; this false sentence
               reaches committed `docs/loop/<slug>/log.md` through it.
Constraints: - Increment the rework counters in the transcribed-only branch using the
               transcribed token figure, mirroring the observed branch exactly. Both parser
               programs.
             - CO5/CO6 wording is untouched: counts stay labelled counts, the share stays
               labelled a share, the not-comparable-to-<15 % statement and the no-verdict rule
               stand.
             - `rework_attribution: ambiguous` still shows as ambiguous.
             - cache_read is explicitly NOT extended to transcribed records — spec.md names
               that as a separate known gap and a non-goal.
             - If print_rework or write-cost-log-section.sh needs an edit to make the sentence
               true, say so in the return; do not restructure either consumer's output.
Output:      scripts/cost-ledger-lib.sh (both `_cost_scan_*` programs),
             tests/guardrails.test.sh (+4), README.md:167 → 449.
Done when:   No report can print a non-zero rework count beside
             `token share: unavailable (no priced invocations are marked rework)`.
Test set:    4 cases. Rule: the contradiction itself, its mirror in the second consumer, and
               the two states the existing CO5 cases already pin (all-unpriced, all-observed)
               kept intact.
             1. transcribed-rework fixture (`phase_detail":"rework"` on the finish record, no
                total_tokens, a recovered line supplying the figure): a real token share prints,
                labelled as a share.  FAILS TODAY — reads `unavailable`.
             2. same fixture: the words `no priced invocations are marked rework` do not appear
                anywhere while the rework count is non-zero.  FAILS TODAY.
             3. the same fixture through scripts/write-cost-log-section.sh: the log section
                carries the same figure as the report, not the false sentence.  FAILS TODAY.
             4. guard: the existing all-unpriced rework fixture (:1712) still reads
                `token share: unavailable`, and the priced fixture (:1738) still reads `25%`.
Do NOT:      Do not touch `_cost_slice_*`, the model write (S3's, already landed), the cache-read
               share, the <15 % wording, or any threshold. Do not edit
               `scripts/record-cost-event.sh`, `scripts/record-recovered-cost.sh`,
               `hooks/hooks.json`, `.claude/loop-cost.jsonl`, or any other unit's artifacts.
Depends on:  S3 — textual and unavoidable: the same 8-line branch in the same two parser
             programs. Two lanes editing it in parallel conflict by construction.
```

### S5 — Teach the per-slice pass that a `recovered` record prices an invocation
```
Owner:       loop-build
Unit:  recovered-figure-drops-slice-and-model
Slice: S5
Context:     - spec.md RD2, RD5 (slice half), RD6, RD7, RD8, RD10.
             - scripts/cost-ledger-lib.sh:965-973 — the doc block declaring cost_slice_rows a
               dedicated second pass; it must be updated to say what it now reads.
             - :982 (jq) / :1050 (python) — the `start|finish` event filter that discards every
               `recovered` record before any join happens. This is the whole defect: a
               transcribed-only invocation is neither ranked NOR counted into
               COST_SLICE_UNKNOWN_PRICED (:1012 / :1079).
             - cost_scan's precedence, to be mirrored not re-invented: observed wins
               (:429/:434 jq, :628/:634 python); `recovered` never creates a second invocation.
             - Field shape, verified 2026-08-18: 16 of the 21 real recovered records join to a
               `slice`; 5 do not. Two real slice labels are RANGES containing a multi-byte
               en-dash — `S1–S4`, `S5–S9` — so a fixture must include one.
Constraints: - Accept `recovered` in both event filters; carry transcribed tokens onto the
               joined entry; an invocation whose ONLY figure is transcribed counts as priced in
               this pass, with observed-wins precedence identical to cost_scan's. Never sum an
               observed and a transcribed figure for one invocation, never average, max or min.
             - The population must reconcile with cost_scan: every invocation cost_scan counts
               priced is either ranked here or counted in COST_SLICE_UNKNOWN_PRICED. A
               transcribed record whose invocation has no start/finish at all (hand-written,
               RD5's row) is unattributed, never assigned a slice name.
             - SLICEROW keeps exactly 5 columns. No new field, no new global.
             - Both parser programs in this commit; S2's parity cases prove it.
             - Do not touch the `noid` keying in either pass (pinned above). If a fixture makes
               the two populations diverge for that reason, S1's reconciliation line states it —
               return `needs-decision` rather than changing the keying.
             - The budget gate's breach message changes behaviour as a consequence (it can now
               name a top slice on a transcribed unit). That is intended and must be asserted,
               not discovered.
Output:      scripts/cost-ledger-lib.sh (both `_cost_slice_*` programs + the doc block),
             tests/guardrails.test.sh (+7), README.md:167 → 456.
Done when:   A transcribed figure's tokens appear against the slice its own start/finish records
             name; on the mixed fixture the ranking holds S1 50,000 and S2 10,000 and the
             concentration flag fires for the 83 % holder; and
             `bash scripts/cost-report.sh harness-fails-only-on-linux` ranks 9 build
             invocations while reporting the 5 slice-less ones as unattributed.
Test set:    7 cases. Rule: happy path, then one case per boundary the criteria name (RD5's two
             shapes, RD6, RD7), the two no-change guards (RD8, RD10), and the real-world label
             shape folded into the happy path rather than given its own case.
             The dial in `test-design` calls 7 a re-slice conversation; kept as one slice
             because cases 2-7 are all boundaries and guards on ONE ~15-line change mirrored in
             two programs — splitting it yields a code slice plus a test-only slice for the same
             code, which is the worse shape.
             1. transcribed-only invocation whose records carry `"slice":"S1–S4"` (en-dash, as
                the real ledger holds): that row is ranked with that token figure and the label
                is not mangled.  FAILS TODAY — `no slice attributed to any priced invocation`.
             2. mixed fixture: ranking holds both rows and the 83 % concentration flag fires.
                FAILS TODAY — ranks S2 alone, `(no flags raised)`.
             3. RD5: transcribed record whose invocation carries no slice → counted in
                COST_SLICE_UNKNOWN_PRICED, no slice name invented.  FAILS TODAY (counted
                nowhere).
             4. RD5 boundary: `recovered` record with NO start/finish record for that id →
                unattributed, nothing fabricated, exit 0.
             5. RD6: duplicated recovered line → every per-slice row identical to the
                single-line fixture.
             6. RD7: the existing conflict fixture (:1243) — the OBSERVED figure is the one in
                the slice row; the transcribed one is not added to it.
             7. RD8 + RD10: recovery-free fixture byte-identical to a frozen block, and the
                report and gate name the same top slice on the mixed fixture.
Do NOT:      Do not touch `_cost_scan_*` (S3/S4 own it), the SLICEROW column count, the 30 %
               threshold, `scripts/record-recovered-cost.sh`, `scripts/record-cost-event.sh`,
               `hooks/hooks.json`, or the `recovered` record shape. Do not add a per-slice
               transcribed marker or column — that is S7, behind OQ3. Do not hand-edit
               `.claude/loop-cost.jsonl`. Do not touch any other unit's artifacts.
Depends on:  S1 (safety ordering, not file overlap — say so to the lane): after S5 the ranking
             is populated but still incomplete on real units (5 of 21 records have no slice), so
             the incompleteness statement must already exist or this slice ships a ranking that
             looks complete for a whole commit. S1 also catches the specific way this slice can
             go wrong — per-slice totals exceeding the unit total.
             S4 (textual): same file.
             S2 (evidence): the python arm of this edit is otherwise unproven.
```

### S6 — Document what a restored dimension is, and record this gate's decisions
```
Owner:       loop-build
Unit:  recovered-figure-drops-slice-and-model
Slice: S6
Context:     - The precedent to copy: `cost-ledger-blind-to-background-agents` S10 and its
               README/decisions cases (tests/guardrails.test.sh:3146-3190).
             - docs/loop/decisions.md — the entry records: OQ1 answered reader-side and why
               (OQ4 + the 21 records), OQ2 in scope, OQ5 out of scope, S11 still held, OQ3's
               answer as given at G1, and the RD3-vs-RD8 reading above.
             - README.md — the cost/recovery section that already states a recovered figure is
               model-transcribed rather than host-observed.
Constraints: - README must say WHICH dimensions a transcribed figure carries and where they
               come from (the invocation's own start/finish records, not the recovered record),
               and that a slice-less invocation is reported unattributed rather than guessed.
             - RD9: the coverage sentence's `transcribed rather than host-observed` clause is
               unchanged, and no restored dimension is described as host-observed.
             - The decisions entry names what this pass forecloses: no writer-side field, no
               fuzzy selector, no hook wiring, no transcript scraping, no hand-editing the
               ledger, no threshold shipped.
             - Documentation only — no script under scripts/ is edited by this slice.
Output:      README.md (prose + `:167` → 460), docs/loop/decisions.md,
             tests/guardrails.test.sh (+4).
Done when:   A reader who has never seen this unit can tell from README alone why a slice row
             can exist for a figure nobody measured, and decisions.md records the reader-side
             choice with its reason.
Test set:    4 cases, all doc-assertion cases in the established grep style.
             1. README states the restored dimensions come from the invocation's own
                start/finish records.  FAILS TODAY (no such text).
             2. README states a priced invocation with no slice is reported unattributed, never
                guessed.  FAILS TODAY.
             3. decisions.md holds an entry naming the reader-side answer and the 21 records as
                its reason.  FAILS TODAY.
             4. RD9 guard: `transcribed rather than host-observed` still appears in the report's
                coverage sentence, and README never describes a restored dimension as observed.
Do NOT:      Do not edit any file under scripts/. Do not restate or amend spec.md. Do not
               record a decision on OQ3 that the human did not make at G1, and do not decide
               S11 or transcript scraping. Do not touch `.claude/loop-cost.jsonl` or any other
               unit's artifacts.
Depends on:  S1, S3, S4, S5 — it documents their behaviour and carries the final case-count
             literal.
```

### S7 — NOT CUT: per-row transcribed marking (behind OQ3)
No envelope is written, deliberately. A slice envelope names files, outputs and tests, so writing
one would pre-empt the human's answer to OQ3 and make the question ceremonial. Costed below.

## Dependency order, and why the parallel set is empty

```
S1 ──► S5 ──► S6
S2 ──► S3 ──► S4 ──► S5
```

Critical path: **S1 → S2 → S3 → S4 → S5 → S6** — the whole list, in order.

**Parallel: 0. There is no parallel lane, and inventing one would be dishonest.** Two independent
reasons, either enough on its own:

1. Five of the six slices append harness cases, and the suite's own **last** case asserts
   `README.md:167`'s literal equals `PASS + FAIL + 1`. Two lanes adding cases collide on that one
   number by construction, and the loser's merge leaves the suite red on a case its diff never
   touched.
2. S3, S4 and S5 all edit `scripts/cost-ledger-lib.sh`; S3 and S4 edit the **same eight-line
   branch** in both parser programs.

S1 and S2 are the only pair with no logical dependency between them, and they still share the
literal. Run them sequentially in one worktree rather than pretending they are lanes.

## The third defect: one slice or two — decided, two, with the reason

Restoring slice attribution (S5) and making an incomplete ranking say so (S1) are **two
requirements**, cut as two slices:

- **They fail independently, today.** S1's cases go red on a fixture with no `recovered` record in
  it at all: a priced invocation carrying no slice already produces a ranking whose population
  differs from the total it is compared against, and today nothing says so. S5's cases go red only
  where a `recovered` record exists.
- **They stay independently true.** After S5, the real units still leave 5 of 21 invocations
  unattributed — measured, not hypothetical — so S1's statement is load-bearing forever, not a
  transitional message. Conversely S1 alone leaves RD2 unfixed.
- **Different files, different danger.** S1 is shell arithmetic in two consumers plus one shared
  helper, no parser edit. S5 changes what a parser considers priced. Bundling them puts a
  presentation change and a semantic change in one diff, in the file this repo calls the most
  dangerous.
- **Order is not arbitrary.** S1 first is what stops S5 shipping a ranking that *looks* complete,
  and S1 is the check that catches S5's worst failure mode (per-slice totals exceeding the unit
  total).

## Five-test audit — every slice, stated

| Slice | 1 owner | 2 one commit | 3 named failing test | 4 observable AC | 5 explicit deps |
|---|---|---|---|---|---|
| S1 | loop-build | 3 scripts, one rule, no parser edit | cases 1-3, 6 — today's output quoted in spec.md and reproduced live | "both surfaces say how many invocations and tokens are unattributed; no verdict printed" | `nothing` |
| S2 | loop-build | tests only | case 1 — no `new_jq_absent_path` exists | "editing one parser without its twin turns the suite red" | `nothing`; textual note on the literal |
| S3 | loop-build | one added write ×2 programs | case 1 — phase reads `unavailable` today on a real unit | "the Phases block names the model the records carry" | S2, with the evidence reason |
| S4 | loop-build | one added increment ×2 programs | cases 1-3 — the self-contradiction is in today's output | "no non-zero rework count beside `no priced invocations are marked rework`" | S3, textual, same 8 lines |
| S5 | loop-build | one filter + join ×2 programs | cases 1-3 — `no slice attributed…` / `(no flags raised)` today | "tokens appear against the slice the records name; 83 % holder flagged" | S1 (safety), S4 (textual), S2 (evidence) |
| S6 | loop-build | docs + 4 cases | cases 1-3 — the text does not exist | "a reader can tell why a slice row exists for an unmeasured figure" | S1, S3, S4, S5 |

Sent back to myself and re-cut during this pass: an earlier version bundled S3 and S4 (one branch,
two writes) — rejected because S4 has a second consumer, `write-cost-log-section.sh`, whose
committed `log.md` output is the reason OQ2 was asked at all, and a title with "and also" in it.
An earlier version also had a seventh test-only slice collecting RD7/RD8/RD11 guards — rejected as
a test slice for another slice's code; those cases are distributed to the slices that can break
them.

## Riskiest slice: S5

Not because it is the largest, but because it is the only slice where a wrong answer is **quiet and
authoritative**:

- It changes what the second pass considers priced, in two mirrored programs, in
  `cost-ledger-lib.sh`. A precedence mistake (summing an observed and a transcribed figure instead
  of preferring the observed one) produces a per-slice total that is *plausible* and wrong, while
  the unit total stays right — nothing in today's suite would notice.
- Its blast radius includes a surface nobody reads while testing the report: the budget gate's
  breach message recommends "re-slice `<top slice>` — it is the largest share of this unit's
  observed spend". A misattribution there sends a human to re-slice the wrong slice, with a figure
  that looks measured.
- Its python arm is, before S2, untestable by this suite.

Mitigations already in the cut: S2 lands first so the python arm is provable; S1 lands first so a
population that does not reconcile is stated rather than printed as a verdict; observed-wins and
exactly-once are pinned contracts with their own cases (5, 6); the `noid` keying is explicitly out
of bounds with `needs-decision` as the exit.

Runner-up, for the record: S1, because it is the one slice that changes output on ledgers holding
no `recovered` record at all — the RD3/RD8 reading above is the thing most worth overruling at this
gate if the human disagrees.

## Cross-unit collision and landing order

`eviction-cap-not-honoured-under-contention` is the live neighbour (`intent.md`, `spec.md`,
`slices.md`, no `log.md`). Read at 2026-08-18, its cut pass is **three parallel read-only spikes,
markdown-only**, which state as a pinned contract: "The suite stays at **427 cases** and
`README.md:167` is untouched by every lane." Its fix group — which will touch
`scripts/record-cost-event.sh` and the harness — is **not cut yet**; it is held for that unit's
second G1.

| Surface | This unit | Neighbour, current pass | Collision |
|---|---|---|---|
| `README.md:167` literal | S1-S6, every slice | untouched | **None now**; certain at the neighbour's second G1 |
| `tests/guardrails.test.sh` | +33 cases, appended before the final case | no case added | **None now** |
| `scripts/cost-ledger-lib.sh` | S1, S3, S4, S5 | not touched | None |
| `scripts/record-cost-event.sh` | on every `Do NOT` | its fix group will own it | None |
| `docs/loop/decisions.md` | S6 appends one entry | its second G1 will append one | Different sections; keep both |

**Landing order: this unit's harness-touching slices land first.** The neighbour's live pass cannot
collide (markdown only, 427 pinned), so this unit is free to move the literal to 460 now. Whoever
cuts the neighbour's fix group afterwards computes its delta table from the literal as it then
stands — not from 427 — and must re-read `README.md:167` rather than trusting its own spike-pass
table. If the neighbour's fix group is instead approved and started **before** this unit lands,
reverse it: this unit's S1 recomputes from that base and every later slice follows, because the
neighbour's fix is a convergence guarantee under contention and is the more time-sensitive of the
two.

## Traceability — RD1-RD11 and OQ2

| Criterion | Assigned | Note |
|---|---|---|
| **RD1** per-phase model on a transcribed figure | **S3** (cases 1-3) | Verified satisfiable: all 21 real records join to `model`/`model_source` |
| **RD2** tokens attributed to the slice the records name | **S5** (cases 1-2) | 16 of 21 real records gain a slice |
| **RD3** no ranking presented as complete | **S1** (cases 1-3), reinforced by **S5** (case 2) | Both halves of RD3's "either/or" are covered: S1 states the gap, S5 closes it where the data allows |
| **RD4** concentration printed only on equal populations | **S1** (cases 3, 6) + **S5** (case 2) | Gate condition is `COST_SLICE_OUTSIDE_N == 0 && UNRECONCILED == 0` |
| **RD5** never guessed, reported unattributed / `unavailable` | model half **S3** (case 2), slice half **S5** (cases 3-4) | |
| **RD6** two recovered records → one of everything | **S3** (case 4), **S5** (case 5) | Extends the existing RC1 case (:1209) to both restored dimensions |
| **RD7** observed/transcribed disagreement unchanged | **S5** (case 6) | The existing S8 conflict fixture is reused, not edited |
| **RD8** recovery-free output byte-identical | **S1** (case 5), **S3** (case 5), **S5** (case 7) | Asserted per slice, as the RC group does. **One reading declared** — see the RD3-vs-RD8 section; the human may overrule at G1 |
| **RD9** a transcribed figure stays labelled transcribed | **S6** (case 4) + guards in S3/S5 | The per-row marking half is **OQ3 — human-owned**, not assigned |
| **RD10** two consumers never disagree | **S1** (case 7), **S5** (case 7) | Structurally, not only by test: `cost_slice_unranked` is one implementation called by both |
| **RD11** degraded environment exits 0, fabricates nothing | **S3** (case 6) | Extends the existing `(j) CO13` shape to a ledger holding recovered records. Not re-asserted per slice: no slice below adds a runtime dependency, and the ladder is unchanged |
| **OQ2** false rework token share (in scope at G0) | **S4** (cases 1-4) | Includes the `log.md` consumer, which is why it is its own slice |

Nothing in RD1-RD11 is vacuous this pass. Two things are **human-owned rather than assigned**:
RD9's per-row marking half (OQ3), and the RD3/RD8 reading S1 acts on.

## OQ1 and OQ3 — costed, carried, not settled

### OQ1 — writer or reader
Cut on **(b) reader**, because G0 settled OQ4 yes. Stated plainly rather than assumed, and
reversible in one place.

| Answer | What it costs here | What it buys |
|---|---|---|
| **(b) reader** — cut above | 4 script slices; 3 visits to `cost-ledger-lib.sh` (S3, S4, S5), mitigated by S2's parity capability; ~33 harness cases | All 21 existing records gain their dimensions with nothing re-typed; the pinned record shape and RC7 stand untouched; `record-recovered-cost.sh` is not reopened |
| **(a) writer** | Overturns a twice-documented "no other field, ever"; edits the transcription CLI and its refusal-path cases; creates a second copy of `slice`/`model` that can disagree with the first; **and still needs reader work**, because all 21 records are the old shape — or a backfill mechanism, which is a new script and a new consent question about rewriting ledger lines | Nothing RD1-RD11 asks for that (b) does not already give |
| **split** (reader for model, writer for slice, or the reverse) | The union of both blast radii, plus a reader that must tolerate two record shapes for one dimension | Nothing measured |
| **If overruled at G1** | S3 and S5 are **replaced**, not amended; S1, S2, S4 and S6 survive as written; the delta table is recomputed | — |

### OQ3 — does a restored dimension need its own transcribed marking
Costed both ways. The slice list above is complete under (a) and gains **S7** under (b).

| Answer | Cost | Consequence |
|---|---|---|
| **(a) the once-per-report marking suffices** | ~0. S6 adds one sentence and case 4 already written | A reader sees `S1–S4  850000 tokens` with the coverage sentence eight lines above saying `14 of 14 priced figure(s) transcribed`. Unambiguous on a 100 %-transcribed unit — which is both real units — weaker on a mixed one |
| **(b) per-row marking required** | A seventh slice, roughly S5-sized and landing after it: `SLICEROW` grows to 7 columns (transcribed tokens + invocations per slice) in **both** `_cost_slice_*` programs, **and both consumers' 5-field positional `read` must be updated in the same commit** (`cost-report.sh:392`, `check-budget-gate.sh:382`) or the gate prints a corrupted rework share; the Phases model line needs its own marker, which reopens `_cost_scan_*` for a fourth visit; ~6-8 cases | Every row carries its own provenance; RC2 holds per-row as well as per-report |

Deliberately **not** pre-built: S5 keeps `SLICEROW` at five columns rather than emitting two
columns nobody reads. Emitting an unread field to make a held question cheaper later is the shape
this repo has refused before, and it would put the column-contract risk into the riskiest slice for
a decision that may never be taken.

A lean, clearly labelled as a lean and freely overrulable: **(a)**, because RC2's
"never indistinguishable" is already satisfied once per report, both field units are 100 %
transcribed, and (b) spends an S5-sized change plus a fourth visit to the dangerous file on
precision that only a mixed unit can use — and no mixed unit exists yet.

Neither question is answered by any slice above, and no slice's `Done when` depends on an answer.

## Explicitly not cut, not scoped, not decided

- **S11** (automatic transcription wiring, held in `cost-ledger-blind-to-background-agents`) — named
  as a coupling only. Fixing this defect is not approval of it, and if OQ1 were ever answered on
  the writer side its subject changes shape.
- **`transcript-scraping-as-a-recovery-path`** — a scraping design producing records in today's
  shape would inherit this defect; that is a reason to settle this unit first, not an argument
  about scraping. Its rejection stands untouched.
- **The `SendMessage`-resumed-invocation gap** — out of scope per G0's OQ5. It is a capture gap
  needing the hook matcher RC7 forbids.
- **`scripts/record-cost-event.sh`, `hooks/hooks.json`, `scripts/record-recovered-cost.sh`** — on
  every slice's `Do NOT`.
- **`.claude/loop-cost.jsonl`** — read-only field evidence. No slice writes, backfills or
  hand-edits it.

## G1

```
# Slices — recovered-figure-drops-slice-and-model

Slices: 6 cut (+1 uncut behind OQ3)  ·  Parallel: 0  ·  Critical path: S1 → S2 → S3 → S4 → S5 → S6
Riskiest: S5 — changes what the second pass considers priced, in two mirrored parser programs,
          and silently re-aims the budget gate's "re-slice this" recommendation.

S1 · an incomplete ranking says so; no concentration verdict across unequal populations · nothing
S2 · the suite can tell whether the jq and python parsers still agree · nothing (textual: S1)
S3 · the per-phase model comes back for a transcribed-only figure (RD1) · S2
S4 · the rework token share stops contradicting the rework count (OQ2) · S3
S5 · the per-slice pass learns that a recovered record prices an invocation (RD2) · S1, S4, S2
S6 · README + decisions.md record the reader-side choice and what it forecloses · S1, S3, S4, S5

1. Approve — proceed to build, S1 first  (recommended)
2. Re-slice — most likely target: S1's RD3-vs-RD8 reading, or S5's 7-case set
3. Spec is wrong — back to loop-spec

Also yours at this gate, costed above and settled by nobody else:
  OQ1 — reader-side is what OQ4 forces; overruling replaces S3 and S5
  OQ3 — (a) costs ~0 and the list is unchanged; (b) adds S7, S5-sized, after S5
```
