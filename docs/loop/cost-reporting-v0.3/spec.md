# cost-reporting-v0.3

**Slug:** `cost-reporting-v0.3` — continuing `cost-measurement-v0.2`'s naming. Kept after the
G0 decision widened the unit to budgets as well, because reporting is what the rest of it
rests on: every budget figure in here is a figure the reader produces.

Implements the **v0.3 row** of `docs/loop/laravel-loop-cost-requirements.md` §9 **in full**:
R5.1 (`/cost`), R5.2 (cost in the delivery log), R2.1 (per-unit budget with a gate), R2.2
(per-phase expectations), R4.4 (no full-suite runs per slice).

That requirements document is human-authored and is the source of truth for **what** each
release row contains. `cost-measurement-v0.2/spec.md` is the source of truth for the record
shape this unit reads and for decisions **D1–D5**, which are settled inputs, not revisitable.
What this spec adds is the part neither could do from a desk: it checks the v0.3 row against
**what the ledger this repo actually shipped can and cannot see**, and that measurement
constrains almost every criterion below.

**Status: G0 decided — see `G0-D1`.** The row ships whole, with **no threshold defaults
anywhere**. One open question, non-blocking, at the end.

---

## Problem

Someone finishes a unit of work and still cannot answer what it cost.

v0.2 built the record — every agent invocation now appends a line to a local file with its
tokens, its duration, its phase, its unit of work, and whether it was rework. Nothing reads
that file. The person who wanted to know whether the expensive framing phases earned their
cost, or whether one badly-cut slice consumed a third of the unit, went from having no data
to having a file of several hundred JSON lines and no way to total it that they would trust.
Totalling it by eye is exactly the failure the record was built to prevent: a number
assembled by hand, by someone who wants a particular answer, is not evidence.

There is a second, worse problem hiding inside the first. **Nobody knows how much of their
spend the record can see.** v0.2 predicted (its E5, D4) that asynchronously-launched
invocations report no tokens, and accepted shipping anyway on the condition that the gap be
made *visible* rather than estimated around. Making it visible was deferred to the reporting
work — this unit. Until that happens, every number anyone derives from the file is of unknown
completeness, and a number of unknown completeness read as a total is worse than no number,
because it retires the question. Somebody sees "38k tokens" for a unit whose largest phase was
never observed, concludes the loop is cheap, and stops asking.

And there is a third problem, which is what a reader alone does not solve: **an unattended
agent loop is the shape of spend that surprises people.** Four agents, some spawning
repeatedly, some concurrently, each retrying up to three times, with nothing anywhere that
notices the total climbing and nothing that stops to ask. A report answers *what did that
cost* after the fact. It does not answer *should this keep going*, and by the time the report
exists the money is spent. Nothing in the loop today can decline to spawn the next agent, so
the only available cost control is a human watching, which is the control that fails exactly
when it matters — overnight, on a long unit, when nobody is watching.

Two consequences follow from nobody being able to read the file, and both are already blocking
work the requirements document schedules:

- The v0.2 work is **not finished** and cannot be. Its own completion condition (DC1) asks a
  human to judge whether the numbers are believable across five or more real units. There is
  no way to do that today except by reading raw JSON. The reader is the instrument that closes
  DC1.
- The **routing change** the requirements document calls its largest single lever (R3.1, v0.4)
  is conditioned on a rework baseline, and must be reverted if rework rises more than 20%
  against it. No baseline can be established from an unreadable file.

A fourth, unrelated problem rides along, in this release row because it is cheap and needs
none of the above: a builder working one slice runs the whole test suite instead of the part
that covers the slice. The prescribed practice already says filtered per slice, full once at
integration. It is advice, and advice loses to an agent that is unsure and reruns everything.
The cost is wall-clock, on every slice, forever, and it is trivially preventable.

## Users

- **The person who just finished a unit of work**, at the moment `/loop` closes — a few times
  a week. Today: nothing tells them what it cost, and the file that could is not something
  anyone reads voluntarily. What they need first is not a total; it is to know whether the
  total means anything.
- **The person who starts a long unit and walks away.** Today: no control except returning to
  find out. They are who R2.1 exists for, and they are also who it can fail most quietly —
  which is why nothing in this unit ever lets an unfired gate read as "within budget."
- **The person deciding what threshold to set**, once, when they first enable it. Today: the
  only number available to them is the illustrative one in the requirements document, with
  nothing to tell them their ledger cannot see most of their spend. Everything in R2's criteria
  below is shaped by the fact that this person deserves to be told what they are configuring
  against — because after the G0 decision, this is the user carrying the risk.
- **Whoever decides whether the loop's design bets still hold** — the expensive framing
  phases, three refine passes, full re-verification. Today: argues from intuition. They are the
  reason a per-phase breakdown exists, and the reason it must state its coverage: a breakdown
  that omits the build phase invisibly makes the framing phases look like the problem.
- **Whoever cuts the slices.** Today: learns a slice was mis-cut when its refine cap trips. A
  concentration figure is the same signal earlier — and a *process* fix, not a spend fix. At a
  budget breach it is the recommended move, per the requirements document's own note.
- **The builder waiting on a test suite** they did not need to run, once per slice. Today:
  waits, or does not notice they are waiting. Distinct user, distinct fix, no cost data
  involved.
- **The person who installed this plugin and did not ask for telemetry.** Their interest is
  unchanged from v0.2: whatever is recorded stays local, stays out of commits, stays bounded,
  deletable without breaking anything — and now also that reading it involves no account and
  no network call, and that nothing starts refusing to work because of a number they never set.

---

## What the evidence already settles

Gathered from this repository before writing any criterion, because the v0.3 row's stated gate
turns on facts nobody had checked. Every figure below is reproducible from files in this repo.

**E1 — The ledger does not exist. There is no baseline, not a short one.**
`.claude/loop-cost.jsonl` is absent from this working tree. Not sparse — absent. v0.2's hooks
were registered and released (`git log`: `a1ea07a Release v0.2.0`) but no `/loop` run has
produced a record since. So the v0.3 row's stated gate ("two weeks of baseline rework rate
recorded") stands at zero days and zero records, and v0.2's own completion condition (DC1,
believable numbers across 5+ real units) is equally unmet. **This unit ships with both its
entry gate and its exit gate unsatisfied**, by the deliberate decision recorded in G0-D1, and
that fact is what every "no default" criterion below is enforcing.

**E2 — Roughly nine out of ten agent invocations in this repo's real history carried no token
figure at all, and the build phase carried none whatsoever.**
`.claude/agents-board.jsonl` — written by Guild's `emit-agent-events.sh`, which is installed in
this environment and observes the same host signals through the same `Agent|Task` matchers —
holds 63 records spanning about sixteen hours of this repo's own work: 21 invocation starts, 42
finish signals (two per invocation, per v0.2's E4). Of those 21 invocations, **2 carried
tokens.** Both were `loop-spec`, synchronous, `status: "completed"`, at 60,787 and 99,124
tokens.

| Agent | Invocations | Priced | Finish status on the unpriced |
|---|---|---|---|
| `loop-build` | 14 | **0** | `async_launched`, null tokens, null duration |
| `loop-spec` | 3 | 2 | 1 still open at capture time |
| `loop-verify` | 2 | 0 | `async_launched` |
| `loop-slice` | 2 | 0 | `async_launched` |

v0.2's E5 raised this as a risk and its D4 accepted shipping into it. It is no longer a risk;
it is the majority case, and it lands on **the phase the requirements document names as the
largest spender**. Two thirds of all invocations were `loop-build`, and not one of them was
priceable. **This is the fact a budget threshold will be compared against**, and the reason
R2's criteria are written the way they are.

**E3 — What that does and does not license as a conclusion.** The observed 0-of-14 for
`loop-build` was recorded during a session whose agents were launched in the background. The
`/loop` command's own design runs independent build slices concurrently, capped at 2–3 in
flight (`commands/loop.md`), which is a structural reason to expect async launching for exactly
that phase — but `loop-slice` and `loop-verify` also came back `async_launched` here and those
are not run concurrently, so how these particular invocations were launched is plainly part of
the explanation. **Whether a synchronous `/loop` run prices its build invocations is therefore
not settled by this evidence.** It is the one open question below, deliberately not
load-bearing: every criterion is written to be correct whether coverage turns out to be 10% or
100%, and the report is what will answer it.

**E4 — Rework share *as a share of tokens* is not computable today; rework as a count of
invocations is.** `phase_detail: "rework"` and `refine_passes` are derived by
`record-cost-event.sh` from its own Bash-hook counter, independent of any token field, so they
are recorded for every invocation including unpriced ones. Token *shares* of rework are not,
and rework lives overwhelmingly in `loop-build` (E2), the phase with zero coverage. This is the
precise point where the missing baseline bites: §10 makes "rework share of tokens < 15%" its
first success metric, and that quantity is currently unavailable at any granularity, on top of
v0.2's D3 already having made it non-comparable to that threshold by definition.

**E5 — Elapsed wall-clock is derivable for every invocation from the ledger's own records;
billed agent time is not.** Both start and finish records carry `ts` and share an
`invocation_id` (`scripts/record-cost-event.sh`), so an elapsed figure exists even where tokens
are null. It is not the same quantity as agent time: the finish payload's `totalDurationMs` is
present only on priced records, and concurrent slices overlap in wall-clock, so summing elapsed
across them over-counts — the requirements document's mock report headline of "18m agent time"
is not something this ledger can honestly produce.

**E6 — The record shapes a reader must handle are more varied than the field list suggests.**
`record-cost-event.sh` emits three shapes, not one: the ordinary lifecycle record
(`event: "start"` / a finish, carrying `phase`, `model`, `model_source`, `status`,
`duration_ms`, `total_tokens`, `input_tokens`, `output_tokens`, `cache_read_tokens`,
`phase_detail`, `refine_passes`, `rework_attribution`); an **`event: "cap_trip"`** terminal
record with no `phase`, no `invocation_id` and no token fields at all; and a truncation
fallback carrying `status: "line_too_long"` and no token fields. A reader that treats every
line as an invocation will over-count invocations and mis-count coverage.

**E7 — No full-suite guardrail exists in any form.** No `LARAVEL_LOOP_ALLOW_FULL_SUITE`, no
unfiltered-suite detection, nothing in `scripts/`, `hooks/hooks.json`, or the skills. R4.4 is
greenfield, and it depends on no figure in any of the above.

**E8 — The two existing guards establish the shape a third one should take, and one thing a
budget gate must not copy.** `block-untested-commit.sh` scopes itself to subagents by requiring
a non-empty `agent_type`, so a human on the main thread is never affected; it takes a
single-purpose escape-hatch env var; it exits 0 wherever it cannot be sure; and it can block a
tool call by exiting 2. `record-cost-event.sh`, by contrast, is bound by v0.2's spec to
**observe and never steer** — so budget enforcement, which must be able to interrupt, cannot
live in it. `guardrails.test.sh` is at **121 passing cases**, zero dependencies.

**E9 — The ledger's own numeric-config precedent is the opposite of what R2 needs.**
`record-cost-event.sh` parses `LARAVEL_LOOP_COST_MAX_LINES` and falls back to 5,000 on a
non-numeric value — correct there, because a bound that fails open is worse than a bound at a
slightly wrong number. **A budget threshold must not follow that pattern**: falling back to a
number nobody chose is precisely the guessed default this unit is forbidden to ship. Named here
because the pattern is sitting in the adjacent script, in the same repo, and a builder will
reasonably copy it.

---

## The decision taken at G0

### G0-D1 — Ship the whole v0.3 row now, with no threshold default anywhere

**Decided by the human at G0, as an informed choice, and not to be re-litigated.** All five
components ship in this unit: R5.1, R5.2, R2.1, R2.2, R4.4.

The condition attached to it, which is what most of R2's criteria below encode: **`unset =
disabled`, everywhere a number would otherwise be guessed, enforced in behaviour rather than
described in documentation.** Specifically, as directed:

- `LARAVEL_LOOP_BUDGET_WARN` and `LARAVEL_LOOP_BUDGET_HARD` ship with **no default value baked
  in anywhere**. Unset means the gate does nothing — not "falls back to a number." True in the
  code, provable by a test, not merely stated in the README.
- **No threshold is derived from the two priced observations** (60,787 / 99,124 tokens, E2) or
  from any other guess dressed as a default. Still rejected, unchanged.
- R2.2's per-phase expectations take the same discipline, plus one addition: **any flag they
  raise prints the coverage caveat alongside it**, because ~90% of `loop-build` invocations are
  currently unpriced (E2) and a phase comparison drawn from that is not self-explanatory.
- Every R2 criterion states the gate as **existing and configurable but inert until a human
  sets it** — never as something with a working default.

**What was recommended instead, and overruled.** The alternative was to ship R5 and R4.4 now
and defer R2 to a successor unit gated on measurement coverage rather than elapsed time, on the
argument that a spend control which appears armed and cannot fire is worse than none, because
it retires the vigilance its absence would preserve. The human read that argument and chose
otherwise. Recorded, not smoothed over, so nobody re-runs the debate — and so the residual risk
is visible to whoever reads this next: **a threshold set today is compared against a total that
may omit most of the spend it is meant to control.** The criteria below are the mitigation, and
the mitigation is honesty at the point of use, not a deferral:

- **CV8** and **BG6** — no unfired gate ever reads as "within budget."
- **BG5** — a breach message states the coverage of the total that triggered it.
- **BG9** — a threshold set while coverage is partial is told so, once, at the point of use.
- **X6** — the README states that no defaults ship, and why.

**Also rejected at G0, and still rejected:** deriving a threshold from E2's two observations
(two invocations, one phase, one sixteen-hour session, on a repo that builds a plugin rather
than a Laravel application — not a baseline, and dressing it as one is the fabricated number
v0.2's D3 refused); and shipping a commented-out or README-suggested starting value, which is
the same guess with an extra step, since a number in a repo acquires authority purely by being
written down.

### G0-D2 — R2.2 ships its **fields** documented, not its **numbers**

R2.2's source acceptance criterion says "Documented defaults per phase in `loop-protocol`."
Read literally that requires shipping per-phase numbers, which G0-D1 forbids and which no
evidence in this repo supports (E1, E2, E4). Resolved by documenting the **mechanism** in
`loop-protocol` — the per-phase fields, how to set them, that nothing is set by default, and
why not — rather than a table of guessed figures.

This is a deliberate divergence from the source document's literal wording, recorded in the
traceability table below rather than quietly absorbed, and it is the one thing in this spec a
human might want to reverse at G0. Reversing it means choosing per-phase numbers by hand; it
does not mean the numbers become derivable.

---

## Acceptance criteria

### Coverage honesty — the spine of the unit (from v0.2 D1, D4, L3)

Not a section of the report. The rule every other criterion is subordinate to, budgets
included. A ledger built to be believed produces tooling that never states a figure more
confident than its input.

- [ ] **CV1** The report states its coverage **before any total**: how many invocations the
      ledger holds for the unit, how many carry a token figure, how many do not, broken down by
      phase. A reader who stops after the first section has not been misled.
- [ ] **CV2** No token-derived figure is ever printed as a number when the invocations it
      summarises are unpriced. It reads `unavailable`, with the count that made it so. Never
      `0`, never blank, never silently omitted so the surrounding table looks complete.
- [ ] **CV3** A partial total is never presented as the unit's cost. It is labelled as covering
      only the priced invocations, with the unpriced count adjacent to it, in the same visual
      unit — not in a footnote and not in a legend.
- [ ] **CV4** Cache-read share reads `unavailable` when the field is absent from every record.
      Never `0%`. v0.2's D1 makes this field best-effort and §10 sets a >40% target against it;
      a target compared against a fabricated zero reads as a catastrophic miss of something
      never measured.
- [ ] **CV5** Every share is computed over priced invocations only and says so. No unpriced
      invocation is ever counted as zero tokens in a numerator or a denominator.
- [ ] **CV6** Where **no** invocation for a unit is priced, no token table is printed at all —
      not a table of `unavailable` rows, not a table of zeros. The report says plainly that
      nothing about this unit's token cost is observable, and why.
- [ ] **CV7** The identical ledger produces the identical report and the identical budget
      verdict. Every figure is arithmetic over the file, not an estimate or a judgement — per
      the protocol's determinism boundary, reporting and threshold arithmetic sit on the
      repeatable side. Tooling that could produce two different totals for one file destroys
      the property the ledger exists for.
- [ ] **CV8** **Every budget comparison inherits CV1–CV7.** A threshold is only ever compared
      against the priced subset, that subset's coverage is stated wherever the comparison is
      surfaced, and no comparison is ever performed by treating an unpriced invocation as zero
      tokens. A gate that quietly counts unobserved spend as free is the failure mode G0-D1
      accepted the risk of; this is where that risk is contained.

### The `/cost` command (source R5.1)

- [ ] **CO1** `/cost <slug>` reports that unit. `/cost` with no argument lists one line per
      unit present in the ledger, most recent first, each carrying its coverage.
- [ ] **CO2** Cost figures come from `.claude/loop-cost.jsonl` and nothing else. No network
      call, no account, no third-party service, no reading of Guild's
      `.claude/agents-board.jsonl` — that file's existence and richer coverage (E2) is evidence
      cited by this spec, never an input to the tooling.
- [ ] **CO3** Three distinguishable messages, not one: ledger file absent (naming the likely
      cause — hooks not wired, or `LARAVEL_LOOP_COST_LEDGER=0`); ledger present but empty;
      ledger present with no records for the requested slug (listing the slugs it does have,
      because a typo and an unrun unit are different problems). None crashes. None prints a
      zeroed table.
- [ ] **CO4** A per-phase breakdown — spec, slice, build, verify — of priced invocations, with
      the model recorded per phase, and `model_source` shown wherever the model was derived
      rather than observed (v0.2 L11). A derived model presented as observed makes every future
      routing comparison a lie.
- [ ] **CO5** Rework is reported as **invocation counts** — n of m invocations marked rework,
      with their refine-pass counts — and as a token share **only** where those invocations are
      priced, each figure labelled as which it is (E4). The count is never presented as the
      share, and neither is captioned in a way that lets a reader take one for the other.
- [ ] **CO6** The report states, in its own output, what its rework figure measures: the cost of
      slices that were not right first time, at whole-invocation granularity, deliberately
      over-attributing, **not** the cost of retrying, and **not** comparable to the <15% target
      in §10 (v0.2 D3, W4). No pass/fail against that target is printed. A reader who never
      opens the README must not be able to misread it.
- [ ] **CO7** Top slices by cost, and the flag for any single slice exceeding 30% of the unit's
      total — printed only where slice-level coverage supports the comparison. Otherwise the
      flags section states that concentration could not be assessed, and what was missing. An
      unassessable check must never render as a passed one.
- [ ] **CO8** Malformed, truncated, or unparseable lines are skipped, counted, and the skipped
      count reported. Never a crash; never a silent drop that quietly shrinks a total.
- [ ] **CO9** Records with `slug: "unknown"` (v0.2 L4) appear as their own bucket. Never merged
      into a named unit, never hidden — an unattributed invocation is a finding about the
      briefing, and the symptom v0.2's P4 exists to catch.
- [ ] **CO10** The three record shapes of E6 are each handled correctly: a `cap_trip` record
      contributes its rework and slice information without being counted as an invocation or as
      unpriced; a `line_too_long` record counts as an invocation whose tokens are unavailable; a
      start record with no matching finish counts as in-flight, not as unpriced-zero.
- [ ] **CO11** Any time figure is labelled as elapsed wall-clock derived from start and finish
      timestamps, and elapsed times of overlapping invocations are never summed into an "agent
      time" total (E5). Where `duration_ms` is present it may be reported as the distinct
      quantity it is.
- [ ] **CO12** The report states the budget configuration it can see: the thresholds currently
      set, or — when none are set — that no budget is configured and therefore nothing will
      gate. Someone who believes they set a limit must be able to discover from the report that
      they did not, and someone who set one must be able to see it was read.
- [ ] **CO13** Zero new runtime dependency. Works where `jq` is present, degrades to `python3`,
      and with neither says so and exits 0 rather than printing a partial or wrong report —
      matching all three existing scripts.

### Per-unit budget with a gate, not a kill (source R2.1)

Every criterion here describes a gate that **exists, is configurable, and does nothing at all
until a human sets a number** (G0-D1).

- [ ] **BG1** `LARAVEL_LOOP_BUDGET_WARN` and `LARAVEL_LOOP_BUDGET_HARD` have **no default value
      anywhere in the code**. Unset or empty means no evaluation, no gate, no warning, no FLAG,
      and no output of any kind about spend. Proven by a test that runs a ledger far above any
      plausible threshold with both variables unset and asserts **zero** budget behaviour — not
      by reading the source and agreeing it looks absent.
- [ ] **BG2** A threshold set to something unparseable — `400k`, `4e5`, a negative, a decimal,
      a stray space — **disables the gate and says so loudly**, naming the variable and the
      value it could not use. It never falls back to a number, and it never fails silently. The
      accepted form is documented. Deliberately unlike `LARAVEL_LOOP_COST_MAX_LINES`, which
      falls back to 5,000 (E9): a bound that fails open is fine, a spend gate that fails open
      *quietly* is the false-safety case, and a typo in a threshold is the likeliest way anyone
      reaches it.
- [ ] **BG3** At the hard threshold, the loop **stops and presents numbered options with a
      recommended default**. Never silently continues; never silently aborts. The recommended
      option is re-slicing the most expensive slice rather than raising the cap, per the
      requirements document's own note that the useful move at a budget gate is usually fixing
      the slicing.
- [ ] **BG4** A slice already in flight **completes**. The gate is evaluated before the next
      spawn and never interrupts, kills, or abandons an invocation in progress — a half-built
      worktree wastes everything already spent, which is a worse cost outcome than finishing.
- [ ] **BG5** The breach message names the most expensive slice and its rework share **and the
      coverage of the total that triggered the breach** (CV8). Where coverage cannot support
      identifying the most expensive slice, it says so instead of naming the most expensive
      *observed* slice as though it were the most expensive one.
- [ ] **BG6** **An unfired gate is never reported as "within budget," anywhere.** Not in the
      report, not in a return, not in `log.md`. Silence from the gate means either no threshold
      was set or the observed total stayed under it — and those two are distinguishable in the
      output (CO12). This is the single criterion carrying G0-D1's accepted risk: a gate that
      cannot see most spend must never be able to issue reassurance.
- [ ] **BG7** The warn threshold surfaces **once** per unit when crossed, does not gate, and
      does not repeat on every subsequent spawn. A warning repeated per spawn is a warning
      nobody reads.
- [ ] **BG8** `WARN` set above `HARD` is a misconfiguration: it is reported plainly rather than
      resolved by picking one, and it never causes the hard gate to be skipped.
- [ ] **BG9** The first time a unit's budget is evaluated with a threshold set **and coverage
      partial**, the human is told once that the threshold is being compared against a total
      that omits unpriced invocations, with the count. Once per unit, not per spawn (BG7's
      discipline).
- [ ] **BG10** Budget evaluation cannot break the loop. A failure inside it — unreadable
      ledger, missing parser, its own internal error — leaves the run proceeding as if no
      threshold were set, and says so. The gate may pause work by design; a *bug* in the gate
      may never stop work.
- [ ] **BG11** Where the presented options include raising the cap and continuing, choosing it
      continues within that unit and **does not silently persist** the new value beyond it. A
      cap raised under pressure at 2am must not become the standing configuration.
- [ ] **BG12** With no human available to answer — an unattended or non-interactive run — the
      hard gate **stops and keeps the artifacts and the log**. It never silently continues past
      a breach on the grounds that nobody answered, and never deadlocks waiting forever.
- [ ] **BG13** `record-cost-event.sh` remains observe-only (E8, X4). Budget evaluation lives
      outside it; nothing that can pause a spawn is added to the ledger writer, whose v0.2 spec
      forbids it from steering under any condition including its own failure.
- [ ] **BG14** Tests, in all four directions: a simulated ledger over the hard threshold
      produces the gate; under it does not; **unset produces nothing at all** (BG1); an
      unparseable value produces the loud disabled path (BG2). Plus: warn fires once, and a
      breach message carries its coverage statement.

### Per-phase expectations (source R2.2, as read by G0-D2)

- [ ] **PE1** No per-phase expectation number is shipped or defaulted. Unset means no
      comparison and no flag, ever — same discipline and same proof obligation as BG1.
- [ ] **PE2** `loop-protocol` documents the per-phase **fields**, how to set them, that nothing
      is set by default, and why not (no baseline exists — E1, E2, E4). It documents no
      numbers (G0-D2).
- [ ] **PE3** A configured overrun appears in that phase's return `FLAGS`, and **never blocks**
      anything.
- [ ] **PE4** Any flag raised carries the coverage caveat alongside it, in the flag itself
      (G0-D1). A phase comparison drawn from a ledger that cannot see most of `loop-build` is
      not self-explanatory to whoever reads the return.
- [ ] **PE5** A phase whose invocations are all unpriced can never raise an overrun flag — you
      cannot overrun an unobserved total — and the absence of a flag is never evidence that a
      phase was within expectation (BG6's rule, applied per phase).
- [ ] **PE6** The flag fits inside the protocol's ≤10-line return shape. It does not extend it.

### Cost in the delivery log (source R5.2)

- [ ] **DL1** `/loop`'s close step appends the cost summary to `docs/loop/<slug>/log.md`,
      alongside the phase-by-phase record already written there.
- [ ] **DL2** The appended summary carries its coverage statement (CV1). A logged total without
      its coverage becomes, within a month, a historical figure someone trusts and cannot
      re-derive.
- [ ] **DL3** Rework is recorded per unit so the trend is visible across units without
      re-deriving it, **with its definition and coverage recorded alongside** — a bare
      percentage in a log will be compared against other bare percentages by someone who was
      not there, and D3's definition is not the obvious one.
- [ ] **DL4** Written under its own heading. Re-running the close step replaces that section
      rather than appending a second one, and never disturbs any other content in `log.md`.
- [ ] **DL5** Where the ledger holds no data for the unit, the section is written saying so.
      Omitting it is not acceptable: a missing cost section and a cheap unit look identical in a
      log, and the first is a wiring bug.
- [ ] **DL6** Any budget event that occurred during the unit — warn crossed, hard gate fired,
      cap raised, gate disabled by an unparseable value — is recorded in the log with the
      threshold in force at the time. A gate that fired and left no trace cannot be learned
      from, and a raised cap that left no trace is how the next threshold gets set wrong.
- [ ] **DL7** `log.md` is the only file written under `docs/loop/`. The ledger is never copied,
      moved, or mirrored there (v0.2 H1), and no new artifact type is introduced.

### No full-suite runs per slice (source R4.4)

- [ ] **FS1** A guardrail warns — stderr, **exit 0**, never a block — when a mid-slice builder
      runs an unfiltered test suite. This is the one guard in the repo that advises rather than
      refuses, and the difference is deliberate: a wrong block costs more than the suite run it
      prevented.
- [ ] **FS2** Integration-time and verification-time full runs are not warned on. The
      discriminator is the caller: only `loop-build` invocations are warned. A human on the main
      thread is never warned (following `block-untested-commit.sh`'s `agent_type` scoping, E8),
      and `loop-verify` is never warned — it re-runs broadly by design, and narrowing that is
      R4.5, out of scope here.
- [ ] **FS3** `LARAVEL_LOOP_ALLOW_FULL_SUITE=1` silences it, and the message names that escape
      hatch inline, in the warning, where somebody reading the warning will see it.
- [ ] **FS4** Recognises the runners the `laravel-validate` skill actually prescribes, including
      the Sail-prefixed forms, and treats a command carrying a filter or a path argument as
      filtered.
- [ ] **FS5** Does not warn on a command that merely mentions tests — a path containing
      `tests/`, a grep, an `ls`, a git command touching a test file. False positives on a
      warn-only guard are how a warning becomes something people learn to ignore, which costs
      more than the guard was worth.
- [ ] **FS6** Exits 0 on every path: malformed payload, empty payload, no parser available, its
      own internal error. Asserted per case, not in aggregate.
- [ ] **FS7** Guardrail cases discriminate in both directions: an unfiltered run by `loop-build`
      warns; a filtered run does not; an unfiltered run by `loop-verify` or from the main thread
      does not; the escape hatch silences it; and the warning goes to stderr with exit 0,
      asserted separately.

### This repository's own gates

- [ ] **X1** `bash tests/guardrails.test.sh` green with a case count above the current 121;
      `shellcheck -S warning scripts/*.sh` clean; executable bit set on anything new.
- [ ] **X2** Both existing guards behave exactly as they do now — same exit codes, same
      `LARAVEL_LOOP_REFINE_CAP` / `LARAVEL_LOOP_ALLOW_UNTESTED` handling, same subagent scoping
      — and their existing cases pass unmodified.
- [ ] **X3** The refine cap's behaviour and `.claude/loop-refine-passes.tsv`'s semantics are
      unchanged. Budget work may read cost state; it may not repurpose refine state.
- [ ] **X4** `record-cost-event.sh` is **unchanged**: same record shape, same fields, same
      rework semantics, same registrations, still observe-only (BG13). This unit reads the
      ledger and does not rewrite it. A slice that believes it needs a new ledger field returns
      `needs-decision` rather than adding one, because a field added mid-unit makes every record
      written before it structurally different from every record after it, and nothing in the
      file says so.
- [ ] **X5** Every script named in `hooks/hooks.json` exists and is executable, so the harness's
      structure check still passes with any new registration in place.
- [ ] **X6** README documents `/cost`, the budget gate, and the full-suite guard the way it
      already documents the ledger and the other two guards: what is read, that coverage is
      printed rather than assumed, that no currency figure is ever produced, **that no threshold
      default ships and why** (no baseline exists), and that a threshold should be set from your
      own observed data rather than from any number in a document.
- [ ] **X7** CHANGELOG and version metadata stay consistent across `VERSION`,
      `.claude-plugin/plugin.json`, and `.claude-plugin/marketplace.json`, per the checks
      `ship-check.sh` already performs.

### The condition for calling this done

- [ ] **DC2** `/cost` has been run against at least one **real** `/loop` unit, and the coverage
      figure it prints matches what a human who watched that run believes about which
      invocations were observed. Not "the report ran" — the report was *recognised*.
- [ ] **DC3** The budget gate has been observed doing nothing on a real run with both variables
      unset (BG1 in the field, not in a fixture), and — separately, whenever someone first sets
      a threshold — observed firing on a total whose coverage they were shown (BG5, BG9).

**Neither DC2 nor DC3 is a G2 criterion**, for the same reason v0.2's DC1 was not: verify can
prove the code does what this spec says against fixtures, and cannot prove a number is
believable or that a gate behaved sensibly in the field. **v0.2's DC1 also remains open and is
not superseded** — this unit builds the instrument DC1 needs, which is not the same as
satisfying it. Passing G2 means it is built. DC2/DC3 mean it is trusted. DC1 means the ledger
underneath it is. Do not let any of the three be reported as another.

---

## Traceability

Every acceptance checkbox in the source document under R2.1, R2.2, R4.4, R5.1, R5.2, and where
it went. Nothing dropped silently.

| Source AC | Here | Note |
|---|---|---|
| R2.1 · thresholds configurable, unset = disabled | BG1, BG2 | Sharpened by G0-D1: no baked-in default, provable by test; unparseable disables *loudly* rather than falling back (E9) |
| R2.1 · numbered options, recommended default, never silent | BG3, BG12 | BG12 added: what happens when nobody is there to answer |
| R2.1 · message names most expensive slice + rework share | BG5 | Conditioned on coverage — must not name the most expensive *observed* slice as the most expensive one |
| R2.1 · in-flight slice completes; gate before next spawn | BG4 | |
| R2.1 · test over/under threshold | BG14 | Widened to four directions: over, under, unset, unparseable |
| R2.2 · documented defaults per phase in `loop-protocol` | PE1, PE2 | **Divergence, see G0-D2.** Fields and mechanism documented; numbers not shipped, because none are derivable (E1, E2, E4) |
| R2.2 · overrun in the phase's return FLAGS | PE3, PE4, PE6 | PE4 adds the coverage caveat per G0-D1; PE6 keeps it inside the ≤10-line return |
| R2.2 · never blocks | PE3 | |
| R4.4 · warns (exit 0 + stderr), not a block | FS1, FS6 | |
| R4.4 · integration-time full run not warned | FS2 | Discriminator pinned to the caller: only `loop-build` warned |
| R4.4 · `LARAVEL_LOOP_ALLOW_FULL_SUITE=1`, named in message | FS3 | |
| R5.1 · reads only the ledger, no network, no account | CO2, CO13 | Extended: never reads Guild's feed either |
| R5.1 · rework share, cache-read share, top slices | CO5, CV4, CO7 | Each conditioned on coverage; rework as counts where tokens are unavailable (E4) |
| R5.1 · flags any slice >30% of unit total | CO7 | An unassessable check never renders as a passed one |
| R5.1 · empty/missing ledger → clear message, no crash, no zeroed table | CO3 | Split into three distinguishable cases |
| R5.2 · close step appends summary to `log.md` | DL1, DL4, DL7 | |
| R5.2 · rework % per unit, trend visible | DL3 | Definition and coverage recorded alongside it |
| §10 · rework < 15% target | CO6 | **No verdict printed against it.** Not comparable by definition (v0.2 D3), and not computable as a token share today (E4) |
| §10 · cache-read share > 40% | CV4 | `unavailable`, never 0% |
| v0.2 D4 · unpriced share surfaced in a report | CV1, CV6 | The promise v0.2 deferred to this unit, now kept |
| v0.2 C4 · report shows cache hit rate | CV4 | Second half of C4, deferred from v0.2 |

---

## Non-goals

Read these out loud at G0.

**Not in this unit, because no evidence supports them and G0-D1 forbids them:**

- **No default threshold number anywhere, for anything.** Not baked in, not commented out, not
  in a README example, not as a "suggested starting value," not derived from E2's two priced
  observations. A number in a repo acquires authority purely by being written down.
- **No fallback-to-a-number on a bad threshold value.** Unlike the ledger's line cap (E9).
- **No per-phase expectation figures** in `loop-protocol` or anywhere else (G0-D2).
- **No inference of a threshold from history** — no "we noticed your last five units averaged
  N, shall we set the cap there." That is a default with extra steps, and it would be computed
  from a ledger that cannot see most spend.

**Not in this unit because §9 assigns them to v0.4:**

- **No model or routing change** (R3.1, R3.2). No `model:` line is touched. This unit exists to
  make that change judgeable later; it does not anticipate it.
- **No context budget in the envelope** (R4.2), **no bounded memory files** (R4.3) — including
  no per-invocation cost figure for `conventions.md` / `decisions.md`, tempting as it is once a
  reader exists — **no scoped verification** (R4.5), **no storage hygiene, worktree cleanup, or
  artifact-size reporting** (R6).

**Not in this unit, though adjacent enough to name:**

- **Closing the unpriced-invocation gap.** This unit *reveals* it (CV1, CV6) and does not fix
  it. Fixing it means changing what the ledger observes, which is v0.2's territory and X4's
  boundary — foreseen by v0.2's D4 as "its own intent," and now warranted by E2. It remains the
  recommended successor unit, and after G0-D1 it is also what makes a threshold worth trusting.
- **Deriving anything from Guild's `.claude/agents-board.jsonl`.** Its richer coverage (E2) is
  evidence for this spec and must never become an input (CO2). A reader that silently improves
  its numbers by reading another plugin's file produces reports that change depending on what
  else is installed.
- **No new agent, and no change to what the four agents do** beyond adding a phase FLAG (PE3)
  and honouring a gate that pauses before a spawn. The team is four.

**Not at any point, per §8 of the requirements document:**

- **No pricing.** Tokens, counts, and durations only. No dollar figure, no rate card, no
  currency, no per-invocation estimate from a hard-coded rate table. **A budget is denominated
  in tokens, never in money.**
- **No hosted dashboard, no SaaS, no network call, no account, no export.** Local files only.
- **No semantic caching. No gateway, proxy, or provider fallback chain.**
- **No cost-based auto-degradation.** Nothing ever switches to a cheaper model, trims context,
  skips a phase, or reduces verification because spend is high. At the gate a human chooses;
  the loop never quietly does less work for less money.
- **No kill.** Nothing terminates an invocation in flight (BG4). Gate, don't kill.

**Raised while framing and deliberately not adopted.** Building any of these is out of bounds;
adding one later is a new intent: a cost trend chart or sparkline across units; a
`/cost --json` machine-readable mode; alerting or notification on a cost figure; a budget
denominated in wall-clock rather than tokens; auto-re-slicing at a breach without a human
choosing it; a `.claude/` state-file cleanup command spanning all state files at once (declined
once already in v0.2); and backfilling historical cost from Guild's feed or from git history.

---

## Failure modes

| When | Expected behaviour |
|---|---|
| Both budget variables unset — the default state (BG1) | Nothing. No evaluation, no message, no FLAG, no mention of spend anywhere. Not "no budget configured ✓" — silence |
| A threshold is set to `400k`, `4e5`, or a negative | Gate disabled **and said so loudly**, naming the variable and the value. Never a fallback number, never silent (BG2) |
| `WARN` is set above `HARD` | Reported plainly as a misconfiguration; the hard gate is not skipped because of it (BG8) |
| The hard threshold is breached | Loop stops before the next spawn, presents numbered options, recommends re-slicing the most expensive slice over raising the cap (BG3) |
| A breach fires on a total that omits most of the spend (the E2 case) | The message states the coverage of the total that triggered it, and declines to name a "most expensive slice" it cannot see (BG5, CV8) |
| A threshold is set while coverage is partial | Told once, at the point of use, that the comparison omits unpriced invocations, with the count (BG9) |
| No threshold was breached | **Nothing is said about being within budget** — not in the report, not in a return, not in the log. Silence is not reassurance (BG6) |
| A slice is mid-flight when the threshold is crossed | It completes. The gate fires before the next spawn. Nothing is killed or abandoned (BG4) |
| Nobody is available to answer the gate (unattended run) | Stops, keeps artifacts and the log. Never continues on the grounds that nobody answered; never waits forever (BG12) |
| The cap is raised at the gate to finish the unit | Applies to that unit and is not silently persisted beyond it (BG11) |
| Budget evaluation itself errors — unreadable ledger, no parser, internal bug | The run proceeds as if no threshold were set, and says so. A bug in the gate never stops work (BG10) |
| A builder tries to add budget logic to `record-cost-event.sh` | Out of bounds. The ledger writer stays observe-only; nothing that can pause a spawn goes in it (BG13, X4) |
| A phase has an expectation set and overruns it | A FLAG in that phase's return, carrying the coverage caveat, blocking nothing (PE3, PE4) |
| A phase's invocations are all unpriced | No overrun flag is possible, and the absence of one is not evidence the phase was fine (PE5) |
| The ledger file does not exist (E1, today's state) | A message naming the likely causes — hooks not wired, or `LARAVEL_LOOP_COST_LEDGER=0` — and how to check. Never a crash, never an empty table (CO3) |
| The ledger exists but holds no record for the requested slug | A distinct message, listing the slugs present. A typo and an unrun unit are different problems (CO3) |
| Every invocation for a unit is unpriced (the E2 case) | Coverage stated, no token table printed at all, reason given. Not a table of zeros, not a table of dashes (CV6) |
| Some invocations are priced and some are not (the likely case) | Totals labelled as covering the priced subset, unpriced count adjacent, every share over that subset only and saying so (CV3, CV5) |
| `cache_read_tokens` absent from every record (v0.2 D1/E6) | `unavailable`. Never `0%`, which would read as a total miss of §10's >40% target rather than a thing never measured (CV4) |
| The input/output split is absent | Combined total reported; split reads unavailable. No arithmetic invents a split |
| Rework sits entirely in unpriced build invocations (E4) | Invocation counts reported and labelled as counts; token share reads unavailable. The count is never dressed as the share (CO5) |
| Someone compares this unit's rework figure to the <15% target | The report states they are not comparable and why, and prints no verdict against it (CO6) |
| Slice concentration cannot be settled from the available coverage | Flags section says concentration could not be assessed, and what was missing. Never rendered as a passed check (CO7) |
| A `cap_trip` record is read (E6) | Its rework and slice information is used; not counted as an invocation, and its missing token fields are not counted as unpriced coverage (CO10) |
| A `line_too_long` record is read (E6) | Counted as an invocation whose tokens are unavailable (CO10) |
| A start record has no matching finish — in progress, or crashed | Counted as in-flight and reported as such. Never an unpriced zero, never dropped (CO10) |
| A record carries `rework_attribution: "ambiguous"` (v0.2 S5) | Shown as ambiguous. Never silently counted as definite attribution |
| A record carries `slug: "unknown"` | Its own bucket, visible. Never merged into a named unit, never hidden (CO9) |
| A line is malformed or truncated | Skipped, counted, and the skipped count reported (CO8) |
| Concurrent build slices overlap in wall-clock | Elapsed times are not summed into an agent-time total. Labelled as elapsed, per invocation (CO11) |
| The model was derived rather than observed | Shown with its `model_source`, so a future routing comparison is not made against an assumed value (CO4) |
| Neither `jq` nor `python3` is available | Says so and exits 0. Never a partial report, never one that looks complete (CO13) |
| The same ledger is read twice | Identical report and identical budget verdict (CV7) |
| The close step runs twice on one unit | One cost section in `log.md`, replaced not duplicated, other content untouched (DL4) |
| A unit closes with no cost data at all | The section is written anyway, saying so. A missing section and a cheap unit must not look identical (DL5) |
| A gate fired, or a cap was raised, during the unit | Recorded in `log.md` with the threshold in force at the time (DL6) |
| `loop-build` runs an unfiltered suite mid-slice | One warning on stderr, exit 0, escape hatch named in the message. The command still runs (FS1, FS3) |
| `loop-verify`, or a human on the main thread, runs the full suite | No warning. Both are legitimate (FS2) |
| `loop-build` runs a filtered test | No warning (FS4) |
| A builder runs `ls tests/` or greps a test file | No warning. A warn-only guard that cries wolf gets tuned out, and then the real warning is free (FS5) |
| The full-suite guard's payload is malformed, or no parser is present | Exit 0, no warning, the command unaffected (FS6) |
| A slice concludes the report or the gate needs a ledger field that does not exist | `needs-decision`, not a ledger change (X4) |
| Guild is installed and writing its own feed | Both files exist, neither is read by the other's tooling, nothing collides (CO2) |
| A commit is prepared after running `/cost` | No ledger, no cost artifact, and nothing new under `.claude/` in the diff |

---

## Constraints

**Given and settled — inputs, not decisions to revisit at slice time.** Reopening any of these
is a new intent, not a mid-build adjustment.

- From the requirements document: the ledger is the only source; `/cost [slug]` is the reporting
  surface; the report covers rework share, cache-read share, and top slices by cost; a single
  slice over 30% of the unit total is flagged; the budget gate warns soft and gates hard,
  configurable via `LARAVEL_LOOP_BUDGET_WARN` / `_HARD` with unset meaning disabled; per-phase
  overruns FLAG and never block; R4.4 warns rather than blocks and takes
  `LARAVEL_LOOP_ALLOW_FULL_SUITE=1`.
- From this unit's G0: **G0-D1** (whole row ships; no default threshold anywhere, enforced in
  behaviour) and **G0-D2** (R2.2 documents fields, not numbers).
- From `cost-measurement-v0.2/spec.md`, all still binding: **D1** (combined tokens only; split
  and cache-reads best-effort, and §10's cache-read target consequently unmeasurable), **D2**,
  **D3** (rework at whole-invocation granularity; over-attributes; not the cost of retrying;
  not comparable to <15%), **D4** (unpriced invocations surfaced loudly, never estimated around
  — this unit is where that promise is kept), **D5**. Plus **L3**: a null means unavailable, a
  zero means measured — a rule this unit's tooling inherits and must not collapse.
- The ledger's record shape and location: `.claude/loop-cost.jsonl`, the field list in E6,
  written by `record-cost-event.sh`, bounded by `LARAVEL_LOOP_COST_MAX_LINES`, disabled by
  `LARAVEL_LOOP_COST_LEDGER=0`.

**Existing behaviour that must not change:**

- `record-cost-event.sh`: record shape, fields, rework semantics, hook registrations,
  exactly-once and eviction behaviour, and its observe-only contract (X4, BG13).
- Both existing guards: exit codes, env-var overrides, subagent-only scoping, and the fact that
  a human on the main thread is never blocked (X2).
- `.claude/loop-refine-passes.tsv`'s format and meaning, and the refine cap's behaviour (X3).
- `hooks/hooks.json`'s existing entries, which all three current scripts depend on.
- The four-agent team, and the README's and CHANGELOG's claim that it is four.
- The protocol's ≤10-line return shape. Neither a phase FLAG nor a budget note may push a
  return past it (PE6).
- Standalone from Laravel Guild: separate agents, skills, env vars, and state files, no
  collision when both are installed, and no reading of Guild's feed.
- `/loop`'s existing close step and the rest of `log.md`'s content and structure.
- **The loop's existing behaviour when no threshold is set.** With both variables unset, a
  `/loop` run must be indistinguishable from today's — no extra pause, no extra output, no
  extra latency (BG1).

**Repo conventions this lives inside:**

- Zero-dependency bash plus coreutils for anything executable, degrading `jq` → `python3` → a
  safe no-op, matching all three existing scripts. Clean under `shellcheck -S warning`,
  executable bit set, covered by `tests/guardrails.test.sh`. CI runs exactly these.
- This repo has no PHP, no composer, no artisan. Commands and agents are markdown; the testable
  surface is bash.
- Hook scripts carry a header comment explaining *why* they are wired to the event they are
  wired to. All three existing scripts do.
- `docs/loop/conventions.md` and `docs/loop/decisions.md` exist and remain **empty templates** —
  nothing here relies on a taught rule, and nothing proposed here has been previously rejected.
  Checked, per protocol, before proposing anything.

**Hard limits:**

- **The reader only reads.** Nothing in this unit writes to, prunes, reshapes, or takes
  ownership of the ledger.
- **The gate pauses; it never kills** (BG4), never terminates work of its own accord (BG10,
  BG12), and never degrades the work to save money (§8).
- Report and threshold arithmetic are deterministic (CV7). Judgement belongs to whoever reads
  the output.
- A budget is denominated in tokens. Never in money.
- Nothing leaves the machine. No network call, no credential, no account.
- G4 is not crossed. Nothing touches live infrastructure.

---

## Open questions

**One, and it does not block this unit.**

1. **Does a synchronous `/loop` run price its `loop-build` invocations?** E2 observed 0 of 14
   build invocations carrying tokens, all `async_launched`; E3 explains why that sample cannot
   settle whether the cause is `/loop`'s concurrent-slice design, the way this session launched
   its agents, or both. The answer sets how much of a unit's cost is observable, and therefore
   **how much of a threshold's job a threshold can actually do** — which after G0-D1 is the
   residual risk this unit carries rather than a reason to wait.

   **Why it does not block:** every criterion is written to be correct at any coverage level.
   CV1–CV8 make the tooling state the answer rather than depend on it, BG5/BG6/BG9 keep a
   threshold honest about what it can see, and BG1 means an unconfigured gate behaves
   identically either way. Nothing to resolve before slicing. What resolves it is one real
   `/loop` run followed by `/cost` — which is DC2, and the reason DC2 is worded as recognition
   rather than execution.

Everything else that was open at the start of this unit was closed against evidence in this
repository and is recorded in **E1–E9**, **G0-D1**, and **G0-D2** rather than left for someone
to rediscover.
