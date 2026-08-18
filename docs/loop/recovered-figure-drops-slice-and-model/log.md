# Log — recovered-figure-drops-slice-and-model

**Closed 2026-08-18.** Verdict at G2: **CONCERNS**, with three findings named. `RD1`–`RD11` and
`OQ2` are all met and each carries the case that proves it — and two of the three findings were then
fixed rather than filed (`55f1822`, `3624102`), which is recorded below with the mutation test each
was proven by.

The unit that made a hand-typed token figure carry more than a number. It also turned up a defect
nobody had reported: a report that could **mislead**, not merely omit.

---

## Where it came from

Not a spec anyone wanted — the by-hand check another unit's `DC5` had asked for, doing exactly what it
was asked to do. On 2026-08-17, between roughly 12:58Z and 13:05Z, while closing
`ship-gate-blind-to-ci`, all seven of that unit's backgrounded invocations were transcribed with
`scripts/record-recovered-cost.sh` and the report was read by eye. It printed 100 % coverage, the
restored total, and **correct per-phase resolution** — then, lower in the same output, `unavailable`
for all four phases' model and `no slice attributed to any priced invocation`, though four of the
seven are build invocations whose `start`/`finish` records carry `"slice":"S1"` through `"S4"` and all
seven carry `"model":"opus"` with `"model_source":"derived"`.

**The asymmetry was the observation**: the reader evidently joins a `recovered` record to its
`start`/`finish` records by `invocation_id` to report the phase, yet model and slice — which sit in
those same joined records — come back unavailable.

Captured with `/observe` (`f7361ef`), cause left `unknown` and deliberately not inferred from the
symptom: neither `cost-report.sh` nor `cost-ledger-lib.sh` had been read at capture time, and whether
`S7`'s reader or `S9`'s writer was the defect was recorded as unknown. The same commit updated the
originating unit rather than editing its history: **`DC5` exercised, not asserted satisfied** (the
notifications were read by the orchestrating agent, not the maintainer, and whether that counts is the
maintainer's call); **`DC4` unchanged**; and **`S11`'s revisit condition met and now arguing against
building it as-is**, because automating transcription over a record shape that drops two dimensions
multiplies the defect once per lane.

## Phase 1 — Spec (G0)

**Artifact:** `spec.md` — `RD1`–`RD11`, ten non-goals, five open questions.

**The spec read the reader instead of inferring from the symptom**, and found the two dimensions fail
for **two different reasons in two different code paths**:

1. **Model — one omitted write inside a join that already carries it.** `cost_scan` merges a
   `recovered` record into the same per-invocation entry as its `start`/`finish` records, and that
   entry already holds `.model` / `.model_source`. But the per-phase model set is written **only** in
   the host-observed branch (`cost-ledger-lib.sh:417` in the jq program, `:617` in the python one);
   the transcribed-only branch below it (`:434-442`, `:634-646`) increments counts and tokens and
   writes no model.
2. **Slice — a separate second pass that never sees a `recovered` record.** `cost_slice_rows` filters
   events to `start`/`finish` (`:982`, `:1050`), so a `recovered` record is discarded before any join
   — not ranked, and **not counted** into its unattributed tally either.

**That second half produced a third defect nobody had found.** Because the unattributed tally stays at
zero, the Flags section skips the "concentration could not be assessed" caveat its own comment says
exists for this case and prints `(no flags raised)`. On a mixed fixture — one host-observed
invocation on `S2` with 10,000 tokens, one transcribed on `S1` with 50,000 — the report ranks `S2`
alone at 10,000, raises no flag, and never mentions that the invocation holding 83 % of the priced
total was left out. **The ranking's population and the total it is compared against are two different
sets.** A fourth, adjacent statement is false by the same mechanism: the rework token share is also
computed only in the host-observed branch, so the report can print `count: 1 of 2 invocation(s)
marked rework` and, two lines later, `token share: unavailable (no priced invocations are marked
rework)` — a sentence that reaches committed `log.md` through
`scripts/write-cost-log-section.sh`.

The spec also settled what the intent left `unknown`: **the record's minimality is deliberate and
documented twice** — *"nothing about phase, status, model, duration, or slice is ever copied
forward… No other field, ever"* — so a writer fix would overturn a documented pin rather than just
add a field.

**Gate G0 decisions** (`dd21eb6`):

| Question | Decision |
|---|---|
| Framing and the ten non-goals | **Approved.** |
| OQ4 — must the 21 already-transcribed records benefit without re-typing? | **YES.** This narrows OQ1 toward a reader fix without deciding it outright: records stay minimal, and the figures already on disk gain the restored dimensions for free. |
| OQ5 — the `SendMessage`-resumed-invocation gap | **OUT of scope**, on the spec's own reasoning: it is a *capture* gap needing the hook matcher `RC7` forbids, not a reporting gap. |
| OQ2 — the self-contradictory Rework output | **IN scope.** Same transcribed branch as the model omission; splitting it would put two units in the same lines of the most dangerous file in this area. |
| OQ1 (writer or reader) and OQ3 (per-row transcribed marking) | **Left for G1.** |

Recorded at the same gate: the cost sections already committed to two units' `log.md` are **not**
affected by the misleading-ranking defect, because both were wholly transcribed (7/7 and 14/14), so
their ranking is empty and says "no slice attributed" — unhelpful but accurate. The misleading case
requires a mix.

## Phase 2 — Slice (G1)

**Artifact:** `slices.md` (`623e416` / `4cc9aed`) — six slices cut, one (`S7`) deliberately **not**
cut, **parallel set empty**, riskiest `S5`.

**Cut reader-side (OQ1 answer (b)), and the file says so on purpose** rather than leaving the
inference to a reader. G0's `OQ4` forces it, and the field evidence made the consequence concrete
rather than theoretical — measured read-only against the maintainer's local ledger on 2026-08-18:

- **21 `recovered` records across two units, 104 ledger lines.**
- All 21 join to `start`/`finish` records carrying `"model":"opus"` or `"sonnet"` with
  `"model_source":"derived"` — so `RD1` is satisfiable for every existing record by reading.
- **16 of 21** join to records carrying a `slice`; **5** (spec / slice / verify-phase invocations,
  which have no `Slice:` line by protocol) carry none — so `RD2` restores 16 and `RD5` must report the
  other 5 as unattributed rather than guessing.
- `bash scripts/cost-report.sh harness-fails-only-on-linux` printed 100 % coverage, 1,650,438 priced
  tokens, all four phases `unavailable`, `no slice attributed to any priced invocation`, and
  `Flags: (no flags raised)` — the whole defect, reproducible on a real unit with no fixture.

A writer answer does not avoid the work it looks like it avoids: all 21 records are the old shape, so
the reader must accept both shapes anyway or a backfill mechanism must exist. The cut says
explicitly that if the human answered (a) or split, `S3` and `S5` would be **replaced, not amended**,
while `S1`, `S2` and `S6` survive — so the assumption sits in one overturnable place.

**The one reading of an approved criterion this pass made, flagged rather than buried:** `RD3` and
`RD8` collide on a recovery-free ledger holding a priced invocation with no `slice`. Read as
**`RD8`'s purpose is `RC6`** — that the transcription *feature* leaves no trace on a run that used
none — not a freeze on the report. Making the report's honesty conditional on a `recovered` record
being present is exactly the coupling this unit removes. `RD8`'s letter (gating the new line on
`COST_N_PRICED_TRANSCRIBED > 0`) was offered at the gate and declined.

**Riskiest is `S5`:** it changes what the second pass considers priced, in two mirrored parser
programs, and silently re-aims the budget gate's "re-slice this" recommendation. `S2` was therefore
cut to land **early** — the jq and python programs had never been tested against each other, in the
file this unit calls the most dangerous in the repository.

**A process note that belongs in the record:** the slicing agent stalled in bookkeeping *after*
writing the complete list, and the file was **verified well-formed rather than assumed** — the
existing convention that an agent's last words are not evidence about its output, applied rather than
re-learned.

## Phase 3 — Build

Six slices, six `--no-ff` merges, full suite green after each. The README literal walked
427 → 434 → 439 → (445 on its own base) → 453 → 460 → **464**, each lane computing from its own base
because the neighbouring `eviction-cap` group was moving the same number concurrently.

| Slice | Delivered |
|---|---|
| `S1` (`8cf57b6`) | `cost_slice_unranked()` in `cost-ledger-lib.sh` — shell arithmetic over `COST_N_PRICED`/`COST_TOKENS_PRICED` and the `SLICEROW` rows both passes already publish — so `cost-report.sh` **and** `check-budget-gate.sh` state how many priced invocations and tokens sit outside the ranking instead of printing an empty ranking or a false concentration verdict. Both incompleteness routes covered. +7 cases. |
| `S2` (`f9043b5`) | `new_jq_absent_path` (symlinks every entry of the standard bin dirs, skipping `jq`, so `python3` and its supporting tools still resolve) plus 5 parity cases across the `S7` recovered, `S8` conflict and `(d)` concentration fixtures. No script touched. **Falsified rather than asserted:** the python recovered-tokens assignment was corrupted, two parity cases went red, and it was reverted. +5 cases. |
| `S3` (`9f0dcfd`) | The by-phase model write mirrored **verbatim key expression** from the host-observed branch into the transcribed-only branch of both parser programs. +6 cases on its own base. |
| `S4` (`0639f60`) | `OQ2`: `rework_priced_n` and `rework_tokens` now increment in the transcribed-only branch too, in both programs, using the transcribed figure that priced the invocation. **Neither consumer needed an edit** — `print_rework()` and `write-cost-log-section.sh` simply became true, as the slice forecast. `cache_read` deliberately **not** extended (a named separate gap and a non-goal). Red before green: `S4-1`, `S4-2`, `S4-3` fail against `main`'s library, `S4-4` (the CO5 guard) stays green. +4 cases. |
| `S5` (`e9e0d56`) | Both `_cost_slice_*` programs accept `recovered` records, so an invocation whose only figure is transcribed is ranked against the slice its own records name. A `recovered` record contributes **tokens and nothing else**; precedence is mirrored from `cost_scan` rather than re-invented (observed wins; never a sum, average, max or min); an id with a `recovered` record but no `start`/`finish` is left unranked **and** uncounted, so the two passes' populations still reconcile. `SLICEROW` keeps its 5 columns. Red-before verified against `git show main:scripts/cost-ledger-lib.sh` for `S5-1`, `S5-2`, `S5-3` and `S5-7`'s `RD10` half; `S5-4`, `S5-5`, `S5-6` are guards, green both sides, as their comments say. +7 cases. |
| `S6` (`5b6ef6a`) | README gains one paragraph — a recovered record carries exactly one dimension, and every other dimension comes from the invocation's own `start`/`finish` records — including the honest failure mode (nothing is guessed). `decisions.md` gains the gate entry with the fact that decided it (21 records already on disk, which a writer-side field would strand) and everything it forecloses. `S6-1`–`S6-3` red against `main`'s README and `decisions.md`; `S6-4` is the `RD9` guard. +4 cases. |

**A G1 defect hit during `S5`, and the human ruled on it.** `S1`'s cases (`S1-2`, `S1-3`, `S1-6`,
`S1-7`) encoded the pre-`S5` state as their expected value, and `(S1-3)` forbade the string
`concentration threshold` on the **very fixture** `S5`'s own *Done when* requires the 83 % flag to
fire on. The unit's pinned contract says no lane edits an existing case, so the `S5` lane stopped at
**`needs-decision`** rather than editing another slice's guards. The human ruled to re-point them
here rather than cut a migration slice: `S1`'s two fixtures drop the `slice` label from their
transcribed invocations, moving each case to a population that is still genuinely incomplete after
`S5`, with the now-complete shape asserted in `S5`'s own section instead. Each fixture comment records
that it is a re-point and why. **The lesson, recorded in `decisions.md` for the next cut:** when one
slice's guards assert the absence of a symptom a later slice must produce, the cut owes a migration
step rather than a pin forbidding one.

A second defect was fixed in passing while writing `S5`'s helpers: `cost_slice_rows` **prints** the
rows as well as publishing `COST_SLICE_ROWS`, so a helper that echoed the variable reported every row
twice. Both new helpers redirect, and say so.

## Phase 4 — Verify (G2)

**Artifact:** `verify.md` (`abebd5b`). **Verdict: CONCERNS.** Full suite reproduced green at
`2c6a497`: `total: 464 passed, 0 failed`; `shellcheck -S warning scripts/*.sh` clean.

Every criterion carries a named covering case and whether it runs, and `RD4` is asserted in **both**
directions (the flag stays silent on an incomplete population, and fires on the complete one). The
`Do NOT` check confirmed `SLICEROW` still emits exactly 5 columns — checked, because a 6th would
silently corrupt the gate's `top_rinv` — the `noid` keying untouched in both passes, and no threshold
shipped.

⚠ **Independence limit, stated rather than implied:** `S4`, `S5` and `S6` were built by the session
that ran this pass; `S1`, `S2` and `S3` were not. Every claim was re-derived and the red-before runs
re-executed against `main`'s library in an isolated tree copy.

**The three findings, and what happened to each:**

1. **Parity was not asserted on the one path `S5` added.** `S2-2`/`S2-3` compare full reports on
   ledgers holding `recovered` records, but **neither fixture carries a `slice` label**, and `S2-5` —
   the only case that diffs `cost_slice_rows`' rows directly — runs on the **recovery-free** fixture.
   So the `SLICEROW` emission path for a transcribed figure was exercised by each program and compared
   by **neither**; agreement there had been checked by hand in the `S5` lane, and a hand check is not a
   case. **Fixed rather than filed, in `55f1822`:** `(S2-6)` runs the rows parity on a fixture where a
   transcribed figure *is* the thing being ranked (one transcribed-only invocation labelled with an
   en-dash range `S1–S4`, one host-observed, one transcribed with no slice), asserting the row count
   next to the agreement so identical-and-empty cannot pass. **Mutation-tested:** with the python
   slice program reverted to ignoring transcribed figures and jq left intact, `(S2-6)` fails while
   `(S2-5)` still passes — precisely the gap the finding named. Suite 464 → **465**.
2. **An earlier unit's case was replaced with a weaker assertion.** `S1` removed
   `cost-ledger-blind-to-background-agents`' `(S4-1)`, which diffed the report against
   `git show HEAD:scripts/cost-report.sh` — self-referential, and meaningless the moment `S1`
   legitimately changed that file's output. The replacement asserts the floor's opt-in property
   directly, which is correct but **weaker in kind**: no case then asserted that the coverage floor
   unset leaves output byte-identical. The unit's own pinned contract ("no lane edits, skips, weakens
   or renumbers an existing case") was crossed, with the reason written down. **Restored in
   `3624102`:** `(S4-1b)` uses the instrument this suite already uses for the job — a frozen literal
   block, as `RD8`'s blocks do — which cannot decay silently, because a slice that legitimately
   changes the output has to update the block deliberately. **Mutation-tested:** with `cache-read
   share: unavailable` changed to `not available` in `cost-report.sh`, `(S4-1b)` fails. Suite 465 →
   **466**.
3. **The `S1`/`S5` fixture clash — a G1 defect, ruled on, recorded.** Verified as executed exactly as
   the human ruled: the only assertion line removed in `e9e0d56` is `(S1-3)`'s `expect` **description**,
   its expected value (`"no"`) unchanged, and the two fixtures lost only their `"slice"` fields. All
   four cases still run, still green, and still green against `main`'s library — which is correct for
   guards. `decisions.md` carries the defect and the lesson. **The residue for the next cut is that
   lesson, not this diff.** Not "fixed", because there is nothing here left to fix.

**A fourth item, since recorded as accepted rather than left unnoticed:** two distinct case families
are labelled `(S4-n)` — this unit's `S4` and `cost-ledger-blind-to-background-agents`' coverage-floor
`S4` (which has since gained `(S4-1b)`). Descriptions disambiguate them and nothing greps the labels,
so nothing is broken. `verify.md`'s addendum records the decision **not** to rename either family:
that would edit case descriptions inside a closed unit's section for a cosmetic gain, against the
pinned contract whose point is that existing cases are left alone. The forward rule instead: a *new*
unit prefixes its case labels with the unit rather than the slice number.

**Gate G2: CONCERNS is the human's to act on.** Two of the three findings were closed on the same day
by the two commits above; the third is a recorded lesson. Both this unit's fix and `eviction-cap`'s
shipped in release `0.6.1` (`c32daf0`), whose `CHANGELOG` carries the two open items rather than
presenting the release as closing them.

## What this unit foreclosed

From `decisions.md`'s G1 entry, so none of it is re-litigated:

- **A writer-side fix** — adding `slice` and `model` to the recovered record. It would overturn
  `record-recovered-cost.sh`'s documented pin, leave two record shapes in one ledger, and strand the
  21 existing records unless they were re-typed.
- **A split writer/reader fix** — considered as a real third option at G0 and not taken, for the same
  reason: `OQ4`'s answer makes the reader path the only one that helps what is already recorded.
- **`RD8`'s letter over its purpose** — freezing recovery-free output exactly, at the cost of making
  honesty depend on a record type. Offered at the gate and declined, with the weaker alternative
  named.
- **A fuzzy selector** on `record-recovered-cost.sh` (nearest-by-time, most-recently-launched,
  per-slug) — rejected 2026-08-17 and standing.
- **Hook wiring / automatic transcription (`S11`)** — automating over a record shape is a different
  question from what the reader does with the shape it has.
- **Transcript scraping**, **hand-editing `.claude/loop-cost.jsonl`**, **any threshold** (the 30 %
  concentration figure is neither raised, lowered, nor made configurable), and **fixing the
  resumed-invocation capture gap here** (out by `OQ5`; it needs the hook matcher `RC7` forbids).

## What this unit did not close

- **`OQ3` and `S7` are uncut, with no position taken in code or docs.** Whether a restored dimension
  needs its own per-row transcribed marking is unanswered; verified at G2 by the fact that `SLICEROW`
  did not grow and `decisions.md` records no answer. The recorded *lean* is that once-per-report
  marking suffices — and it is untested, because **both real units are wholly transcribed, so no mixed
  unit exists to test it against**. When one does, finding 1's parity case and `OQ3` both want
  revisiting.
- **`S11` is still held.** Its revisit condition is met, and this defect is what the check found; the
  order (fix first, then decide) is the human's and "fix this first" is not approval of it afterwards.
- **`DC5` stays exercised-but-not-asserted-satisfied, and `DC4` stays open** — both need a human's own
  judgement, and neither was given by this unit.
- **The two named non-goal gaps stay open:** cache-read share reads `unavailable` on every transcribed
  record, and elapsed wall clock. Neither is this defect and neither was silently absorbed.
- **The `(S4-n)` label collision** across two units — accepted with its reason in `verify.md`'s
  addendum, not renamed; the forward rule is unit-prefixed labels on the next unit that needs them.
- **A new observation landed after the release and is not this unit's to close:**
  `docs/loop/cost-log-section-parse-error-on-macos-ci/intent.md` (`e59215c`) records `DL4`'s
  byte-identical case going red on run `32174044661`'s macOS job — the first
  `write-cost-log-section.sh` run wrote the full section and the second replaced it with `Could not
  read the cost ledger (parse error)`, eleven lines becoming two, on a fixture whose records carry
  fixed `ts` values. 150 isolated local iterations diverged 0/150; the job re-run is green on both
  platforms, putting that commit's macOS job at **1 red in 3 samples**. The suspected unit is recorded
  as **`unknown`** deliberately: this unit's `0639f60` and `e9e0d56` are in the neighbourhood, but the
  identical tree ran green on both platforms twice, so naming either commit would be a guess.

## The ledger measuring this unit

The cost ledger holds **6 invocations** for this slug — spec, slice, and builds `S1`, `S2`, `S3`,
`S4`. Every one was launched backgrounded, so each carries a `finish` record with
`status: "async_launched"` written seconds after launch while the agent ran for minutes; all six
landed **unpriced**, and none has been transcribed. `S5` and `S6` have no ledger record at all — they
were built by the orchestrating session rather than as separate agent invocations, and the cost hook
only ever sees `Agent|Task`.

So the `## Cost` section below reports **0 % coverage** and prints no token total. That is the exact
blind spot this unit's own subject matter comes from, honest output rather than a bug, and it is not
evidence the unit was free. No token figure for this unit is stated anywhere in this log, because the
ledger does not hold one — and, pointedly, the dimensions this unit restored are only visible once a
figure has been transcribed, which for this unit has not been done.

## Cost

Coverage: based on 0 of 6 invocations that carry a token figure (6 unpriced, not counted) -- 0 % coverage; wholly unobserved: spec, slice, build

Tokens: nothing about this unit's token cost is observable -- 0 of 6 invocation(s)
carry a token figure. No total is printed here (unmeasured, never zero).

Rework: this figure counts whole invocations that needed at least one refine pass, at
whole-invocation granularity -- deliberately over-attributing rather than estimating a
per-pass split, and NOT the cost of retrying. It is not comparable to the requirements
document's <15% target (Sec.10), which was calibrated against a narrower, per-pass
definition. No pass/fail verdict against that target is printed here.
  count: 0 of 6 invocation(s) marked rework
  token share: unavailable (no priced invocations are marked rework)

