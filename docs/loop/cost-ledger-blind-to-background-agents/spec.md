# cost-ledger-blind-to-background-agents

Successor to `cost-measurement-v0.2` (built the ledger) and `cost-reporting-v0.3` (built `/cost`
and the budget gate on top of it, and named this unit as the recommended successor in its own
non-goals). Written against `intent.md`'s **"Measured after the restart"** section, which
supersedes that file's original framing.

**Status: awaiting G0.** Five open questions, three of them scope-deciding. The recommended
answers are at the end, numbered. Nothing here is settled.

---

## Problem

A person finishes a unit of work, runs `/cost`, and is shown a number that omits most of what
they spent — while the missing figures were measured, arrived on their screen during the run,
and were then discarded.

The ledger works. It records every invocation it is handed, honestly, and it says how much of
the unit it can see. What it cannot see is any invocation launched in the background — and the
loop's own design runs its most expensive phase that way, several lanes at a time. So the
report's coverage sentence is true and its total is real, and together they describe a minority
of the work: the phase that spends the most is the phase that appears cheapest, because it does
not appear at all.

Two things follow, and the second is the one that costs money.

**The reader is misinformed by omission.** Somebody reads a per-phase breakdown in which the
framing phases carry every observed token and the build phase carries none, and concludes the
expensive framing phases are the problem. That is the opposite of what the requirements document
predicts, and the report gives them no way to notice. Worse, the report currently offers no
reason for the gap — an invocation is simply "unpriced", which reads as *unknowable*. It is not
unknowable. It was measured.

**A control is armed against a number it cannot see.** A threshold set today is compared against
the observed subset. It can therefore stay quietly below its limit through a run that spent ten
times it, and nothing is wrong from the tooling's point of view — silence is not reassurance,
which is stated, but silence is also indistinguishable from a run that was genuinely cheap.

The question this unit exists to answer is not "how do we log more". It is: **what may these
tools legitimately claim when they can observe only a minority of real spend — and, given the
missing figure demonstrably exists, should they be claiming so little at all?**

## Users

- **The person who runs `/cost` after a unit closes** — a few times a week. Today: gets a
  coverage sentence they believe and a total they should not, with no statement of which phases
  the total omits or why. They cannot compare two units, because coverage differs between them
  in ways nothing surfaces.
- **The person who set a threshold, or is deciding whether to.** Today: told the comparison is
  partial, not told that "partial" here means roughly one invocation in twenty-five, nor that the
  unobserved ones are the expensive ones. They are carrying `cost-reporting-v0.3`'s G0-D1
  residual risk personally, and this is the unit that either shrinks it or names its true size.
- **Whoever is deciding whether the loop's design bets still hold** — Opus on framing, three
  refine passes, full re-verification. Today: has a breakdown in which one side of the comparison
  is structurally empty, which is worse than no breakdown, because it looks like an answer.
- **Whoever cuts the slices.** Today: rework is reported as invocation counts (correct, per E4 of
  v0.3) and never as a token share, because rework lives in build and build is unobserved. The
  earliest quantified signal on slice quality is the one permanently unavailable.
- **Whoever closes `cost-measurement-v0.2`'s DC1** — believable numbers across five or more real
  units. Today: cannot, and could not even with fifty runs, because believability is exactly what
  minority coverage removes. DC1 is blocked on this unit, not on more runs.
- **The person who installed this plugin and did not ask for telemetry.** Unchanged interest, and
  it constrains any recovery route: whatever gets recorded stays local, stays out of commits,
  stays bounded, and deleting it breaks nothing.

---

## What the evidence already settles

Every figure below is reproducible from files in this repository or from the two controlled
probes recorded in `intent.md`. Gathered before any criterion was written.

**E1 — The registration gap is closed. The hook is live and correct.** `.claude/loop-cost.jsonl`
exists and carries a correct `start`/`finish` pair from this session. `record-cost-event.sh`
fires. **No part of this unit is a fix for the ledger not running**, and any slice that proposes
one is out of bounds.

**E2 — The cause is launch mode, established by controlled experiment, not correlation.** Two
probes, identical agent type, identical model, identical trivial task, differing only in launch
mode:

| Launch mode | Terminal record written | Tokens in ledger | Real cost |
|---|---|---|---|
| Foreground | `status: "completed"` | 12,102 | 12,102 |
| Background | `status: "async_launched"` | *null* | **11,035** |

The background probe's 11,035 is not an estimate. It was delivered to the main thread in the
agent's completion notification. **The figure exists, is exact, and arrives.** It simply never
reaches the hook: the `PostToolUse` payload for a backgrounded launch carries `async_launched`
and no usage block, and no hook subscribes to the channel the real figure travels on.

**E3 — Registering `SubagentStop` is not the fix, and this is measured rather than assumed.**
This repo's `hooks/hooks.json` deliberately does not register it. Guild's `emit-agent-events.sh`
*does*, in this same environment, and across 79 terminal records in one working session its 41
`subagent_stop` records carried **zero** token figures. A later lifecycle signal is not where the
number is. Anything proposing that registration as the remedy is re-treading measured ground.

**E4 — Coverage in real conditions is 4%, concentrated exactly where it hurts.** Of those 79
terminal records, 3 were priced — the three foreground `loop-spec` invocations. `loop-build`: 56
terminal records, **0 priced**. Because `/loop`'s design runs 2–3 independent build lanes
concurrently, **`loop-build` is structurally 100% unpriced**, and the requirements document names
it the largest spender.

**E5 — Today's report is honest about the size of the gap and silent about its nature.** Run
against a fixture ledger of one priced `loop-spec` invocation and two `async_launched`
`loop-build` invocations, `scripts/cost-report.sh` prints its coverage first (correct, CV1),
labels the total as the priced subset (correct, CV3), and then:

- reports `2 unpriced` with **no reason attached** — a reader cannot tell an invocation that was
  backgrounded from one that was malformed, truncated, or launched with no parser available;
- reports **`0 invocation(s) started with no finish recorded yet -- in flight`**, while both
  backgrounded invocations were in fact still running. An `async_launched` record is treated as a
  terminal outcome. It is not one: it says the launch happened, and nothing about the finish;
- prints a headline total at 33% coverage with no statement stronger than the label. There is no
  coverage level, other than zero (CV6), at which the tooling declines to state a figure.

**E6 — `decisions.md` carries one bullet that E2 supersedes, and it must be corrected rather
than quietly contradicted.** Its entry *"Pricing a unit of work from subagent token totals"*
closes with: *"Closing the gap needs a token figure for backgrounded invocations from the harness
itself. That is upstream of this plugin, not a slice inside it."* E2 shows the harness already
produces the figure and already delivers it into the session. The rejection of a **spend control
built on 4% coverage** stands untouched and is not reopened anywhere in this spec. The claim
about where the number lives does not.

**E7 — Whether any hook can reach the channel the figure arrives on is UNKNOWN.** Not
established in either direction by anything in this repository, and deliberately not asserted
here. It is **OQ2**, and the scope of this unit depends on its answer.

**E8 — The harness is at 334 cases, zero dependencies, fixture-driven.** It pipes synthetic
payloads to scripts directly. It can prove what a script writes given a payload and what a
reader prints given a ledger. Per `decisions.md`, it **cannot** prove a hook is registered or
that a live session behaves as expected — which is why the completion conditions below are field
conditions, not G2 criteria.

---

## Acceptance criteria

Group **CL** holds whichever route G0 chooses. Group **RC** applies only if G0 admits recovery
(OQ1/OQ2). Every criterion is stated as behaviour observable from a fixture ledger plus the
tooling's own output, so `tests/guardrails.test.sh` can prove it without a live session.

### CL — What the tooling may claim (unconditional)

- [ ] **CL1** Every unpriced invocation is reported **with the reason it is unpriced**, taken
      from what its record says and never guessed. Backgrounded-at-launch is a distinct, named
      reason, separate from malformed, truncated, no-parser, and still-running. Today all of
      these render as one undifferentiated count (E5).
- [ ] **CL2** An invocation recorded only as launched-in-background is **never presented as an
      invocation whose outcome was observed**. It appears in its own category, and the report's
      in-flight statement does not claim zero when such invocations exist and were never
      subsequently observed (E5). A launch is not a finish.
- [ ] **CL3** The report states, in its own output, **why** the gap exists: the figure for a
      backgrounded invocation is measured by the host and delivered into the session, and is not
      captured here. A reader who never opens a spec must not be able to conclude the number is
      unknowable. If G0 chooses recovery and recovery lands, this text describes the residue that
      remains, not a gap that no longer exists.
- [ ] **CL4** Coverage is stated as a **share as well as a count**, and the phases that are
      *wholly* unobserved are named. "1 of 25" and "1 of 3" are not equivalent claims, and a
      breakdown missing an entire phase must say which phase.
- [ ] **CL5** Below a coverage level (**OQ3**), no unit-level token total is printed at all — the
      unit's cost is stated as not established, with the observed subset shown as a subset and
      never as a headline. Above it, the total prints as it does today. The level is a number a
      human sets at G0; it is not derived, inferred, or defaulted by any code in this unit.
- [ ] **CL6** The budget gate's coverage notice carries the same share and the same
      wholly-unobserved phase names as CL4. A threshold armed against a minority subset says how
      small the minority is, at the point of use, in the message that arms it.
- [ ] **CL7** No figure anywhere is imputed, extrapolated, scaled, averaged, or reconciled to
      fill the gap. An unobserved invocation contributes nothing to any numerator and nothing to
      any denominator, and no code in this unit derives a token figure from a count, a duration,
      an average of priced invocations, or a per-phase ratio. Provable by a test asserting that a
      ledger with two priced and twenty unpriced invocations produces a total identical to the
      same ledger with the twenty removed.
- [ ] **CL8** `cost-reporting-v0.3`'s coverage-honesty spine (CV1–CV8) and budget discipline
      (BG1–BG14, PE1–PE6) continue to hold unchanged. Their existing harness cases pass
      unmodified. This unit sharpens what is claimed; it removes no existing honesty.
- [ ] **CL9** A ledger written before this unit — records lacking any field this unit introduces
      — is read without error and reported with its coverage stated. No record is dropped, and no
      historical record is retroactively reclassified into a category it cannot support.

### RC — Recovering the figure (only if admitted at G0)

Written mechanism-agnostically on purpose. Each is provable from a fixture ledger containing a
recovered figure, whatever wrote it.

- [ ] **RC1** An invocation whose real token figure is recovered ends with **exactly one** finish
      record carrying that figure. Not two records, not a second invocation, not a duplicate in
      the invocation count. v0.2's L1/L9 exactly-once property extends to a late-arriving figure.
- [ ] **RC2** A recovered figure is **distinguishable in the report from a host-observed one**. A
      reader can tell which numbers the hook was handed and which came from elsewhere, following
      the `model_source` precedent (v0.2 L11): a derived value presented as an observed one makes
      every later comparison a lie.
- [ ] **RC3** Where a recovered figure and an observed figure exist for the same invocation and
      disagree, **both are shown and neither silently wins**. No averaging, no precedence rule
      applied invisibly.
- [ ] **RC4** Recovery failing — no figure arrives, it arrives unparseable, it arrives for an
      invocation the ledger has no record of — leaves that invocation exactly as CL1 describes it
      today, and **blocks, delays, and alters nothing**. Asserted per case, not in aggregate.
- [ ] **RC5** A recovered invocation counts as priced in every coverage figure, so coverage rises
      and CL5's behaviour changes accordingly. Provable by one fixture with and without the
      recovered figure.
- [ ] **RC6** A run in which recovery does not happen at all is **indistinguishable in
      correctness** from today: no error, no warning about a record that never arrived, no
      incomplete state, no claim that a figure is pending. Recovery is best-effort by
      construction.
- [ ] **RC7** Nothing that can pause, delay, or steer a spawn is added to the ledger writer. Its
      observe-only contract (v0.2, and v0.3's BG13/X4) is unchanged, including under its own
      failure.

### X — This repository's own gates

- [ ] **X1** `bash tests/guardrails.test.sh` green with a case count above the current **334**;
      `shellcheck -S warning scripts/*.sh` clean; executable bit set on anything new.
- [ ] **X2** All three existing guards behave exactly as they do now — same exit codes, same
      `LARAVEL_LOOP_REFINE_CAP` / `LARAVEL_LOOP_ALLOW_UNTESTED` / `LARAVEL_LOOP_ALLOW_FULL_SUITE`
      handling, same subagent scoping — and their existing cases pass unmodified.
- [ ] **X3** Zero new runtime dependency: `jq` → `python3` → a safe no-op, matching all existing
      scripts.
- [ ] **X4** Every script named in `hooks/hooks.json` exists and is executable.
- [ ] **X5** README states plainly what the ledger can and cannot see, in the same place it
      already documents the ledger — including that background-launched invocations are the
      majority of a `/loop` run and how they are treated.
- [ ] **X6** `docs/loop/decisions.md`'s superseded bullet is corrected in place with its date and
      the evidence that superseded it (E6). The rejection of a spend control at 4% coverage is
      left standing and is not edited.

### The conditions for calling this done

- [ ] **DC4** On one real `/loop` run that used background lanes, the coverage `/cost` prints —
      the share, the reasons, and the wholly-unobserved phases — matches what a human who watched
      that run believes. Recognised, not merely executed.
- [ ] **DC5** If recovery ships: on one real run, a backgrounded invocation's recorded figure
      matches the figure the human saw in that agent's completion notification, for at least one
      invocation, checked by eye.

**Neither is a G2 criterion**, for the reason `decisions.md` already records: the harness cannot
exercise the live hook path. Verify proves the code does what this spec says against fixtures.
**`cost-measurement-v0.2`'s DC1 and `cost-reporting-v0.3`'s DC2/DC3 all remain open** and are not
superseded by this unit. Do not let any of these five be reported as another.

---

## Non-goals

**Read these out loud at G0.**

**Not in this unit, because the evidence forbids it:**

- **No estimated, imputed, extrapolated, or modelled token figure for an unobserved
  invocation** — not from an average of priced ones, not from a per-phase ratio, not from a
  count, not from history. This is the single most tempting thing in the unit and it defeats the
  ledger's entire purpose (CL7).
- **No elapsed wall-clock used as a proxy for cost.** Already rejected in `decisions.md` and in
  v0.3's CO11: overlapping background lanes make an elapsed total meaningless.
- **No `SubagentStop` registration offered as the remedy.** Closed by measurement (E3).
- **No reading of Guild's `.claude/agents-board.jsonl` as an input.** It is evidence for this
  spec and must never become a data source (v0.3 CO2). A reader whose numbers improve because
  another plugin is installed produces reports nobody can reproduce.
- **No retroactive backfill** of past runs, from any source, including git history.

**Not in this unit, because it is settled and not being reopened:**

- **`cost-reporting-v0.3`'s G0-D1 is not reopened.** No threshold default ships, anywhere, for
  anything; the gate stays inert until a human sets a number; the decision to ship the gate at
  partial coverage stands. CL5's coverage floor is about **what may be printed**, not about
  whether the gate exists — and it is a number a human sets, never one derived here.
- **No change to what "rework" means** (v0.2 D3), to the refine cap, or to
  `.claude/loop-refine-passes.tsv`'s semantics.
- **No fix for plugin-install staleness.** `intent.md`'s finding 1 is closed (E1).
- **No model or routing change** (R3, v0.4). No `model:` line is touched.

**Not in this unit, though adjacent enough to name:**

- **No change to `/loop`'s concurrency by default.** Trading background lanes for foreground
  launches to buy coverage is a real option, and it is **OQ4** — it is not assumed, and it is not
  in scope unless G0 puts it there.
- **No new agent.** The team is four.
- **No new artifact under `docs/loop/<slug>/`** beyond this unit's own spec, slices, verify, and
  the existing `log.md` cost section (v0.2 H1, v0.3 DL7).

**Not at any point, per §8 of the requirements document:**

- **No pricing.** Tokens, counts, and durations only. No currency, no rate card, no per-invocation
  dollar estimate.
- **No SaaS, hosted dashboard, network call, account, or export.** Local files only.
- **No cost-based auto-degradation.** Nothing switches to a cheaper model, trims context, skips a
  phase, or reduces verification because spend is high.
- **No kill.** Nothing terminates an invocation in flight.

**Raised while framing and deliberately not adopted.** Building any of these is out of bounds;
adding one later is a new intent, so it stays a decision someone makes rather than one that
accretes: a per-unit coverage trend across units; a `/cost --json` mode; alerting on a coverage
figure; a reconciliation report comparing this ledger against Guild's feed; and a `.claude/`
state-file cleanup command spanning all state files at once, declined twice already.

---

## Failure modes

| When | Expected behaviour |
|---|---|
| An invocation is launched in the background and never observed again | Reported in its own category with its reason named, never counted as an observed outcome, never as an unpriced zero (CL1, CL2) |
| A report is produced for a unit whose build phase is wholly unobserved | The phase is named as wholly unobserved, alongside the coverage share (CL4) |
| Coverage falls below the level set at G0 | No unit total is printed; the cost is stated as not established, and the observed subset is shown as a subset (CL5) |
| Coverage is above that level | Behaves as today, with CL1–CL4's additions |
| Every invocation for a unit is unpriced | v0.3's CV6 still holds: no token table at all, reason given, no zeros, no dashes |
| A threshold is armed while coverage is a minority | The message states the share and names the wholly-unobserved phases, once per unit, at the point of use (CL6) |
| No threshold fires during a run | Nothing is said about being within budget. v0.3's BG6 is unchanged — silence is never reassurance |
| Somebody asks for the unobserved spend to be estimated from the priced average | Refused. No such figure is produced by any path (CL7) |
| A recovered figure arrives for an invocation already priced by the host | Both shown, neither silently wins (RC3) |
| A recovered figure arrives for an invocation with no ledger record | Best-effort: nothing errors, nothing is fabricated, the arrival is not reported as a pending record (RC4) |
| A recovered figure arrives twice | One finish record for that invocation. Exactly-once holds (RC1) |
| Recovery never happens on a run | Indistinguishable from today. No error, no warning, no incomplete state (RC6) |
| A recovered figure is unparseable | Treated as not arrived. The invocation stays unpriced with its reason (RC4) |
| A recovery path errors internally | Exits 0, writes nothing corrupt, the run is unaffected (RC4, RC7) |
| A slice proposes putting recovery logic inside the ledger writer's spawn path such that it could delay a spawn | Out of bounds. Observe-only is unchanged (RC7) |
| A pre-existing ledger is read after this unit ships | Read without error; historical records are not reclassified into categories they cannot support (CL9) |
| Neither `jq` nor `python3` is present | Says so and exits 0. Never a partial report that looks complete (X3) |
| The same ledger is read twice | Identical report and identical verdict. v0.3's CV7 is unchanged |
| Someone compares two units' totals whose coverage differs | Each total carries its own coverage share adjacent to it, so the comparison is visibly not like-for-like (CL4, CL5) |
| Someone reads `4% coverage` as `the run was cheap` | The report names the wholly-unobserved phases and states the cause of the gap (CL3, CL4) |
| A commit is prepared after a run | No ledger and nothing new under `.claude/` in the diff |

---

## Constraints

**Settled inputs, not decisions to revisit at slice time.** Reopening any is a new intent.

- **From `cost-measurement-v0.2`:** D1–D5 and L1–L11, in particular **L3** (null means
  unavailable; zero means measured), **L9** (exactly once), **L11** (a derived value declares
  itself derived), and the ledger's location, shape, line cap, and `LARAVEL_LOOP_COST_LEDGER=0`
  disable switch.
- **From `cost-reporting-v0.3`:** **G0-D1** (no threshold default anywhere; the gate ships inert
  and provably so), **G0-D2** (per-phase fields documented, numbers not), CV1–CV8, BG1–BG14,
  PE1–PE6, CO1–CO13, DL1–DL7. This unit extends them; it weakens none.
- **From `docs/loop/decisions.md`:** the rejection of a spend control built on 4% coverage; the
  refusal of a rework token share while build is unpriced; the refusal of elapsed time as a cost
  proxy; and the rule that a hook is proven live by the state it writes, never by its tests
  passing. One bullet in that file is superseded by E2 and is corrected by **X6**, not ignored.

**Existing behaviour that must not change:**

- The ledger writer observes and never steers — no blocking, delaying, reordering, or altering a
  spawn, under any condition including its own failure.
- All three existing guards: exit codes, env-var overrides, subagent-only scoping, and the fact
  that a human on the main thread is never blocked.
- `hooks/hooks.json`'s existing entries, which every current script depends on.
- The four-agent team, and README's and CHANGELOG's claim that it is four.
- The protocol's **≤10-line return shape**. Nothing this unit adds may push a return past it.
- Standalone from Laravel Guild: separate agents, skills, env vars, state files; no collision
  when both are installed; no reading of Guild's feed.
- `/loop`'s existing concurrency, unless G0 rules otherwise via OQ4.

**Repo conventions:**

- Zero-dependency bash plus coreutils, degrading `jq` → `python3` → a safe no-op. Clean under
  `shellcheck -S warning`, executable bit set, covered by `tests/guardrails.test.sh`. CI runs
  exactly these. No PHP, no composer, no artisan in this repository.
- Hook scripts carry a header comment explaining *why* they are wired to the event they are
  wired to.
- `docs/loop/conventions.md` is an empty template — no taught rule constrains this unit.

**Hard limits:**

- Nothing leaves the machine. No network call, no credential, no account.
- A budget is denominated in tokens, never in money.
- Report and threshold arithmetic stay deterministic (CV7). Judgement belongs to the reader.
- G4 is not crossed. Nothing touches live infrastructure.

---

## Open questions

Five. **OQ1, OQ2, and OQ3 must be answered before slicing** — G1 stalls on each of them.
Recommended answers are given, and each is a recommendation, not a decision taken.

**OQ1 — What does this unit owe: a narrower claim, a recovered figure, or both?** (Scope.)

1. **Claim only.** Ship group CL. `/cost` and the gate become precise about what they cannot see;
   coverage stays at roughly 4%. Cheap, entirely provable by the harness, and leaves the largest
   spender permanently unmeasured.
2. **Recovery only.** Attempt group RC. If it works, coverage approaches 100% and most of CL
   stops mattering. If it does not, the unit delivers nothing.
3. **Both, claim first.** *(recommended)* CL lands independently of whether recovery is
   reachable, so the unit cannot deliver nothing; RC follows and is allowed to fail without
   taking CL with it. This is the only ordering in which OQ2's unknown is not a project risk.

**OQ2 — Can a hook reach the channel the real figure arrives on?** **Unknown, and deliberately
not asserted in either direction** (E7). It has three possible answers and they lead to different
units:

1. **Yes, a hook can subscribe.** RC is a hook change and stays entirely on the deterministic
   side of the protocol's boundary. Best outcome.
2. **No — only the main thread sees it**, so a ledger line would be written by an agent
   transcribing a number from its own context. This works, and it puts a *model-transcribed*
   figure into a file whose whole value is that its numbers were observed rather than reported.
   **RC2 exists precisely so that such a figure is never indistinguishable from an observed
   one** — but whether it is acceptable at all is a human's call, not this spec's.
3. **Neither.** RC is unbuildable, OQ1 collapses to option 1, and CL is the whole unit.

**Recommended:** treat OQ2 as a question a slice **answers by experiment before any recovery
work is designed** — a spike whose only deliverable is which of the three answers is true.
Committing to a recovery design before that is answered is how this unit fails.

**OQ3 — Is there a coverage floor below which `/cost` prints no total, and what is it?**
(CL5.) Today the only such level is zero. A total at 4% coverage is arithmetically correct and
practically misleading. Options: no floor (label harder, as today); a floor the human sets, unset
meaning no floor; or a floor with a shipped number.

**Recommended:** a floor the human sets, **unset meaning today's behaviour** — consistent with
G0-D1's discipline that no number nobody chose ever ships in this repository. **This does not
reopen G0-D1**: it governs what may be *printed*, not whether the gate exists or what it is
compared against.

**OQ4 — Is trading `/loop`'s background lanes for foreground launches in bounds?** Foreground
invocations are priced (E2). Running build lanes serially would buy near-total coverage at the
cost of the parallelism `/loop` was designed around. Currently a **non-goal**.

**Recommended:** keep it out of bounds. Paying wall-clock permanently to measure is the wrong
trade while OQ2 is unanswered, and it can be revisited as its own intent if OQ2's answer is 3.

**OQ5 — Must a recovered figure stay distinguishable from an observed one permanently?** (RC2.)
Saying yes means the record shape changes, and every record written before this unit lacks the
distinction — CL9 covers reading them, but a reader comparing old and new records must not be
able to mistake absence for observation.

**Recommended:** yes, permanently and explicitly, following `model_source`'s precedent. The
ledger's only asset is that its numbers can be trusted about their own origin.
