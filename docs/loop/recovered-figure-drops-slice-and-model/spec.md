# recovered-figure-drops-slice-and-model

Phase: Spec (G0). Written from `intent.md` in this directory, which records the capture.

## Problem

When a unit's token figure was typed in by hand rather than measured by the host, the cost report
can still say which phase spent it, but not which slice or which model — and where only part of a
unit's spend was typed in, the report's per-slice ranking and its concentration line describe only
the measured part while presenting themselves as if they described all of it.

## Users

The maintainer closing a unit of work, and any agent reading `/cost` output for that unit. Today,
after transcribing a backgrounded unit's figures, they get a restored total and a restored coverage
percentage, and then read `unavailable` for every phase's model and `no slice attributed to any
priced invocation` — so the two questions the per-slice view exists to answer ("which slice cost
the most", "is spend concentrated") cannot be answered for any unit whose lanes ran in the
background, which is every unit `/loop` runs. What they do instead: read the raw
`<subagent_tokens>` figures back out of their own notifications by eye, or skip the question.

This is not a fault in transcription. Transcription works: coverage moved 0 % → 100 % on two real
units (`ship-gate-blind-to-ci`, 7 figures; `harness-fails-only-on-linux`, 14 figures), 21 figures
total, every one permanently marked `transcribed rather than host-observed` as OQ5 required. The
defect is in what a transcribed figure *carries* into the report, not in whether it arrives.

## What is established, by reading the reader

The intent left the cause `unknown` and asked that it not be inferred from the symptom. It was read.
The two dimensions fail for **two different reasons, in two different code paths** — they are not
one bug with two symptoms:

1. **Model — same code path, one omitted write.** `cost_scan` merges a `recovered` record into the
   *same* per-invocation entry as its `start`/`finish` records, keyed by `invocation_id`
   (`scripts/cost-ledger-lib.sh:334`, `:540`). That entry already holds `.model` and
   `.model_source`, copied off those joined records (`:349-350`, `:356-357`). This is the join the
   intent deduced from correct phase resolution, and it carries model too. But the per-phase model
   set is written **only inside the host-observed branch** (`:417` in the jq program, `:617` in the
   python one). The transcribed-only branch immediately below (`:434-442`, `:634-646`) increments
   the priced count and the token totals and does not write a model. So the dimension is present on
   the joined entry and dropped at the point of aggregation.

2. **Slice — a genuinely separate second pass that never sees a `recovered` record at all.**
   `cost_slice_rows` is its own scan, documented as such (`:965-973`, "A dedicated pass over the
   ledger, grouped by `slice` rather than `phase`"). It filters events to `start`/`finish` only
   (`:982`, `:1050`), so a `recovered` record is discarded before any join happens, and its notion
   of priced comes solely from a finish record's `total_tokens`. A transcribed-only invocation is
   therefore invisible to it — not ranked, and **not counted** into its unattributed tally
   (`:1012`, `:1079`) either.

Consequence of (2), observed and worse than a missing row: because the unattributed tally stays at
zero, `cost-report.sh`'s Flags section skips the "concentration could not be assessed" caveat that
its own comment says exists for this case (`scripts/cost-report.sh:368-372`, `:400-402`) and prints
`(no flags raised)`. On a mixed fixture — one host-observed invocation on `S2` with 10,000 tokens,
one transcribed invocation on `S1` with 50,000 — the report ranks `S2` alone at 10,000, prints
`(no flags raised)`, and does not mention that the invocation holding **83 % of the priced total**
was left out. The ranking's population and the total it is compared against are two different sets.

A third, adjacent statement is false by the same mechanism: Rework's token share is also computed
only in the host-observed branch (`:422`, `:623-624`), so on that same fixture the report prints
`count: 1 of 2 invocation(s) marked rework (refine passes: 2)` and, two lines later,
`token share: unavailable (no priced invocations are marked rework)`. That sentence reaches
committed documentation — `scripts/write-cost-log-section.sh` prints it into `docs/loop/<slug>/log.md`
(`:70`). Whether it is in scope is **OQ2**, not assumed here.

**The record's minimality is deliberate and documented**, in two places, and both are quoted rather
than paraphrased because a writer change would have to overturn them:

- `scripts/record-recovered-cost.sh:47-53` — "The slug this script writes is always the one the
  ledger already holds for that invocation; nothing about phase, status, model, duration, or slice
  is ever copied forward or inferred, per the RC group's pinned record shape: … No other field,
  ever".
- `scripts/cost-ledger-lib.sh:131-137` — "pinned shape: {"ts", "event":"recovered",
  "invocation_id", "slug", "total_tokens", "token_source":"transcribed"} — no other field … It
  never carries `phase`, so it never overrides the phase the invocation's own start/finish already
  set."

Note the stated *reason* for the pin, in `docs/loop/cost-ledger-blind-to-background-agents/slices.md`'s
"Pinned contracts for the RC group" table: it argues against reusing `event:"finish"` (last-wins
token assignment could silently overwrite an observed figure). It does not argue against a
`recovered` record carrying additional descriptive fields. Note also that `slug` **is** already
copied forward from the ledger by that writer, via `cost_invocation_lookup`. Both facts belong to
whoever answers OQ1; neither settles it.

## Acceptance criteria

Each names what would be checked. None names a file, function, or field to change — the
writer-versus-reader choice (OQ1) is not settled here, and every criterion below must be provable
under either answer.

- [ ] **RD1** For a unit whose priced figures are all transcribed, the per-phase model line names
      the model that unit's own `start`/`finish` records carry. Checked by: a fixture where every
      priced figure is transcribed and the underlying records carry `model`/`model_source`; the
      Phases block names that model and marks it derived where the records say derived, instead of
      reading `unavailable` for every phase. Reproducible today against the two real units in the
      maintainer's local ledger: `bash scripts/cost-report.sh ship-gate-blind-to-ci`.
- [ ] **RD2** A transcribed figure's tokens are attributed to the slice its own `start`/`finish`
      records name. Checked by: a fixture with a transcribed build-phase invocation whose records
      carry `"slice":"S1"`; the per-slice view shows `S1` with that token figure, where today it
      shows `no slice attributed to any priced invocation`.
- [ ] **RD3** No per-slice ranking is presented as complete when priced tokens exist outside it.
      Checked by: the mixed fixture (observed `S2` 10,000 + transcribed `S1` 50,000); the output
      either attributes `S1` or states in the same section how many priced invocations are
      unattributed and how many tokens they hold. A bare ranking of `S2` alone, with nothing said,
      fails this.
- [ ] **RD4** A concentration statement is printed only when the tokens ranked and the total they
      are compared against cover the same set of invocations. Checked by: the same mixed fixture —
      either the concentration flag fires for the 83 % holder, or the report says concentration
      could not be assessed. `(no flags raised)` fails this criterion, because it asserts an
      assessment that was not made.
- [ ] **RD5** Where the joined `start`/`finish` records carry no slice (or no model), that is
      reported as unattributed or `unavailable` — never guessed, never attributed to the
      nearest, most recent, or only other slice present. Checked by: a fixture with a `recovered`
      record whose invocation's records carry no `slice` field; the invocation appears in an
      unattributed count and no slice name is invented for it.
- [ ] **RD6** Two `recovered` records naming one `invocation_id` still yield one invocation, one
      slice attribution, and one model entry. Checked by: a fixture with the recovered line
      duplicated; every count, token total, and per-slice row is identical to the single-line
      fixture (RC1's exactly-once, extended to the dimensions this unit restores).
- [ ] **RD7** An invocation with both a host-observed figure and a disagreeing transcribed one
      keeps today's behaviour exactly: both figures printed, each attributed to its source, the
      observed figure the one summed into the total. Checked by: the existing conflict fixture —
      its output is unchanged except for the dimensions this unit restores (RC3, S8).
- [ ] **RD8** A ledger holding no `recovered` record produces byte-identical report output to
      today. Checked by: diffing the full report for a recovery-free fixture before and after the
      change (RC6, asserted per slice throughout the RC group).
- [ ] **RD9** A transcribed figure stays labelled transcribed. Checked by: the coverage sentence's
      "transcribed rather than host-observed" clause is present and unchanged wherever it is today,
      and no restored dimension is rendered in a way that implies the figure was host-observed
      (RC2, OQ5 — permanent, not this unit's to relax). Whether the restored dimensions need
      their own per-row marking is **OQ3**.
- [ ] **RD10** Two consumers of the same ledger never print different figures for the same unit.
      Checked by: for one fixture, the report's coverage sentence and priced total and the budget
      gate's own are identical strings/numbers, before and after the change (CV7/CV8).
- [ ] **RD11** Every path still exits 0 and fabricates nothing when the environment is degraded.
      Checked by: the report run with neither `jq` nor `python3` on `PATH`, against a ledger
      holding recovered records — same message as today, exit 0, no partial or invented figure
      (CO3, CO13).

## Non-goals

Read out loud at G0. Each one is something a reasonable slice could drift into from here.

- **Not hook-wiring anything.** `scripts/record-recovered-cost.sh` stays out of
  `hooks/hooks.json`, never runs unless typed, and `scripts/record-cost-event.sh` stays
  byte-identical. RC7 is binding and is not reopened by this unit.
- **No selector for `--invocation-id`.** No nearest-by-time, most-recently-launched, per-slug, or
  any other guess at which invocation a figure belongs to. Rejected on 2026-08-17 and standing.
- **S11 is not decided or built here.** Automatic transcription wiring stays held. See Couplings.
- **Transcript scraping is not scoped in, designed, prototyped, or rejected here.** Its rejection
  of 2026-08-17 stands untouched; it has its own captured intent and its own first question, which
  is a consent question.
- **The `SendMessage`-resumed invocation gap is out of scope** — see Couplings for the decision and
  its reason.
- **Not changing the observed-wins precedence** (RC3/S8), the coverage sentence's arithmetic, the
  unit total, or what counts as priced. This unit is about which dimensions a priced figure
  carries, not about the number itself.
- **No threshold, default, or suggested value ships anywhere** — not for the coverage floor
  (`LARAVEL_LOOP_COST_MIN_COVERAGE`), not for either budget field, not for the four per-phase
  fields, not commented out, not as "a reasonable starting point". The 30 % concentration
  threshold that already exists is neither raised, lowered, nor made configurable.
- **Not hand-editing `.claude/loop-cost.jsonl`** to make the report look right. It is gitignored
  local state; every acceptance criterion above is provable from a fixture. (Whether a mechanical
  backfill is *needed at all* is OQ4's business, not a non-goal.)
- **Not fixing the other known report gaps**: cache-read share `unavailable` on every transcribed
  record, and elapsed wall-clock. Neither is this defect and neither is silently absorbed.
- **No new runtime dependency.** The jq → python3 → safe-no-op ladder stands; nothing here may
  require a tool the repo does not already degrade past.

## Failure modes

| When | Expected behaviour |
|---|---|
| A recovered figure's invocation carries no `slice` on its own records | Counted as unattributed and said so, in the same section as the ranking. Never guessed (RD5) |
| A recovered figure's invocation carries no `model` on its own records | `unavailable` for that phase, never a fabricated or inherited model name (RD5) |
| Only part of a unit's priced tokens are attributable to a slice | The ranking states its own incompleteness; no concentration verdict is printed against a different population (RD3, RD4) |
| An observed and a transcribed figure disagree for one invocation | Unchanged from today: both shown, observed counted, no average/max/min/overwrite (RD7) |
| Two recovered records name one invocation | One invocation, one attribution, one model; every figure identical to the single-record fixture (RD6) |
| No recovered records in the ledger at all | Output byte-identical to today (RD8) |
| A recovered record hand-written into the ledger for an invocation with no `start`/`finish` record | Reported without slice or model, nothing fabricated. (The CLI refuses to write one — RC4 — so this arrives only by hand-editing) |
| Neither `jq` nor `python3` on `PATH` | Today's message, exit 0, no figure printed (RD11) |
| A malformed or truncated ledger line | Counted in the skipped tally as today; never silently dropped, never made to look like an invocation |

## Constraints

Existing behaviour that must not change:

- **RC1** exactly-once; **RC2** a transcribed figure is permanently distinguishable from an
  observed one (OQ5's answer, and not relaxable); **RC3** disagreement is visible, never resolved
  silently; **RC5** a recovered figure counts as priced everywhere coverage is stated; **RC6** a run
  with no transcription is indistinguishable from before the feature existed; **RC7** observe-only,
  nothing wired into a spawn path.
- **CV1** coverage is stated before any total. **CV5** an unpriced invocation is never added as a
  zero. **CV7/CV8** one implementation of the total, shared by every consumer. **CO3/CO13** the
  reporting path always exits 0 and never crashes. **CO4** a phase with no priced invocation of its
  own reads `unavailable`, never `0`.
- The pinned `recovered` record shape and its "no other field, ever" wording are **currently
  binding**; changing them is precisely what OQ1 would authorise, and only a human can.
- Any change to `scripts/cost-ledger-lib.sh` lands in **both** parser programs, jq and python, or
  the two disagree by construction. The pinned-contracts table calls this the most dangerous file
  in this area for exactly that reason.
- Evidence discipline: `.claude/loop-cost.jsonl` is gitignored local state, and the test harness
  invokes scripts directly over stdin — a green suite is never evidence that a hook is live
  (`docs/loop/conventions.md`). Nothing in this unit needs a live hook, and no criterion above
  depends on one.
- The two real units already transcribed (21 records) are the only field evidence that exists;
  they are read-only inputs to this work, not fixtures to edit.

## Couplings — named, not decided

- **S11 (automatic transcription wiring), held in
  `docs/loop/cost-ledger-blind-to-background-agents/`.** Its stated revisit condition — "after one
  transcription has been done by hand and checked by eye" — is now met, and this defect is what the
  check found. Automating transcription over a record shape that drops two dimensions would
  multiply this defect once per lane rather than settle it, which is the ground on which S11's
  revisit was already argued against. **This unit does not decide S11**, does not schedule it, and
  does not treat "fix this first" as approval of it afterwards. If OQ1 is answered on the writer
  side, S11's subject changes shape, so the order matters and belongs to the human.
- **`docs/loop/transcript-scraping-as-a-recovery-path/` (captured, unspecced).** A scraping design
  that produced records in today's shape would inherit this defect wholesale. That is a reason to
  settle this unit on its own merits before that one is specced — **not** an argument for or
  against scraping, whose first question is a consent question about reading files outside this
  repository. Its rejection stands and is not touched here.
- **The `SendMessage`-resumed invocation gap (`docs/loop/conventions.md`): OUT OF SCOPE for this
  unit.** A resumed run carries a tool-use id the ledger never saw, because the cost hook matches
  `Agent|Task` and a `SendMessage` is neither; the resumed figure must be attributed to the
  original launch's id, and the killed attempt's tokens are reported nowhere by anything. That is a
  *capture* gap — an invocation the ledger has no record of — upstream of and independent from this
  unit's *dimension* gap, which is about records the ledger does hold. Fixing it would mean
  touching the hook matcher, which RC7 puts out of bounds here. It needs its own intent and its own
  G0, and this spec deliberately does not absorb it. Confirm or overturn at G0 (**OQ5**).

## Open questions

None is guessed at below. **OQ1 and OQ4 are the two that would stall slicing**, so they are raised
now rather than discovered at G1.

- **OQ1 — Writer or reader? Not settled here, by instruction.** Two answers, different costs and
  different blast radii:
  - **(a) Writer** — the `recovered` record carries `slice` and `model` (and `model_source`),
    copied forward from the ledger the way `slug` already is. Cost: it overturns a pinned,
    twice-documented "no other field, ever"; it duplicates data that already exists on the
    `start`/`finish` records, creating a second copy that can disagree with the first; it touches
    the transcription CLI and its refusal-path test set; and every one of the 21 records already
    written is the old shape, so the reader must tolerate both shapes anyway — or the records must
    be backfilled (see OQ4). It leaves both reader passes untouched.
  - **(b) Reader** — the report resolves both dimensions from the joined `start`/`finish` records,
    as it already does for phase. Cost: it touches `scripts/cost-ledger-lib.sh`, in both parser
    programs, including the second pass that today ignores `recovered` records entirely — the file
    the RC group's own notes call the most dangerous here. It leaves the record minimal and every
    already-written record benefits with nothing re-typed.
  - Note the asymmetry established above: the model half is a one-line omission inside an existing
    join, while the slice half needs a second pass taught about a record type it currently
    discards. **A split answer is a third option** — reader for model, writer for slice, or the
    reverse — and is not ruled out here.
- **OQ2 — Is the false Rework token-share statement in scope?** Same branch, same mechanism, and it
  reaches committed `log.md` output via `scripts/write-cost-log-section.sh`. The intent named only
  slice and model, so folding it in silently would be scope creep; leaving it out means shipping a
  known-false sentence for one more release. In, out, or its own unit — the human's call.
- **OQ3 — Does a restored dimension need its own transcription marking?** RD9 keeps the coverage
  sentence's global marking. Unresolved: whether a slice row or a phase's model whose figure came
  only from a transcribed record must itself say so at that row, or whether the once-per-report
  statement is sufficient. Bears directly on RC2's "never indistinguishable".
- **OQ4 — Must the 21 already-transcribed records benefit without re-typing?** If yes, that
  constrains OQ1 (a pure writer change would need a backfill path, which is a new mechanism and a
  new consent question about rewriting ledger lines). If it is merely nice to have, both OQ1
  answers stay open. Answering this first may be the cheapest way to narrow OQ1.
- **OQ5 — Confirm the resumed-invocation gap is out of scope**, as Couplings states, or overturn
  that and it returns to a fresh intent rather than being absorbed into this one.
