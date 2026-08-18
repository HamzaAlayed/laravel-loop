# eviction-cap-not-honoured-under-contention

Source: `docs/loop/eviction-cap-not-honoured-under-contention/intent.md` (captured
2026-08-18T08:39:05Z). Prior art: `docs/loop/harness-fails-only-on-linux/` in full —
`spike-case-a.md` (H1 refuted, H2 now confirmed), both G2 verdicts in `verify.md`'s git history,
and `log.md`'s "A1 — attempted, and FAILED".

This document names no cause and licenses no fix. Two questions in it are the human's at G0, and a
builder inheriting it is not licensed to pick either.

## Problem

The cost ledger holds more lines than the cap it declares, once appends arrive under real
contention — and the one check that says so disagrees with the maintainer's machine, so the project
cannot currently tell "the cap is broken" from "the check is wrong."

## Users

- **Whoever's `.claude/` the ledger grows in.** Every `/loop` run appends to it. The declared bound
  is what keeps a file nobody reads from growing without limit. Today they do nothing, because the
  overage is silent: no error, no warning, nothing in any output — the file is simply larger than
  the repository says it can be. Nobody has reported noticing, and at real invocation rates
  (seconds apart, not thousands per second) the overage in ordinary use is unmeasured.
- **Whoever reads a CI result on this repository.** Both guarding jobs are red on the same case, so
  every push from here on produces a red run that has to be hand-compared against this known one to
  tell whether it is new. Today they read the failure list by eye. This is the acute cost right now,
  and it is a cost of the *disagreement*, not of the overage.
- **Whoever later trusts `/cost` or the budget gate.** Both read this file. Neither is known to
  misread an over-cap ledger, and no such misreading is claimed here — but the cap is a stated
  property of their input, and a property that silently does not hold is worth exactly nothing to
  them.

## The two things that make this hard, both first-class

Neither of these is an aside. A spec that files them as caveats produces a slice list that stalls.

### 1. `L7` and the last appender

`L7` is deliberate, documented in `scripts/record-cost-event.sh`'s own header, given explicit
precedence over `L9` there, and carries its own regression guard in the harness (case (g),
`tests/guardrails.test.sh` — an append lands its line while the evict lock is held, and its wall
clock does not scale with the hold). It says: **appenders never block on the evict lock.** They poll
briefly, then append regardless.

The consequence is structural, not incidental. Every append is unconditional; only one invocation at
a time may hold the evict lock; an invocation that loses that race makes no second attempt and
signals nothing to anyone. So **some invocation always appends last, after the final trim, with no
later appender obliged to re-evict.** Reducing that window — which is what the previous unit's S5
did, successfully — is not the same as closing it.

This means the phrase "hard cap" is ambiguous in a way the repository has never resolved, and at
least three different properties hide inside it:

1. **At every instant** — no reader, at any moment, ever observes the file over cap. Already
   incompatible with `L7` as written and as documented: an appender's `>>` puts the file at cap+1
   before anything could trim it, and the header explicitly accepts "a ledger that sits slightly
   over cap for a moment."
2. **At rest** — once the last append of a run has landed and its invocation has returned, the file
   is at or under cap. This is what the failing case asserts, and the closest reading of the
   maintainer's instinct.
3. **Eventually** — the file is at or under cap once some later invocation happens to run, and may
   sit over cap indefinitely if none ever does.

**Which of these the cap is, is not decided in this document.** It is `OQ1`, the G0 decision. What
is established is that the repository currently states none of the three, which is why a case and a
codebase could disagree about the same word for two releases.

### 2. The proof problem

The failure has never been reproduced anywhere a person can watch it.

- **Maintainer's host** (macOS 26.6.1, arm64, `bash 3.2.57(1)-release`): full suite `427 passed,
  0 failed`. The failing case is green here, 5/5 when it was written.
- **Docker, investigation-grade:** 20/20 trials across Ubuntu 22.04/24.04, bash 5.1/5.2, and 10 vs
  2 vCPUs all settled at cap.
- **Both CI runners**, run `32112900121`, commit `9f37a5b`: red, identically, `426 passed, 1 failed`
  on each. The macOS runner's bash and architecture exactly match the maintainer's host, so this is
  **contention, not platform** — the platform reading is now refuted twice.

And one factual asymmetry, which is a real lead rather than a curiosity: the case's own constructed
scenario **was** red 5/5 locally against the pre-fix script. Constructed local pressure could expose
the *old* bug. Post-fix it is green locally and red on CI, which establishes only that **CI applies
more pressure than that constructed scenario does**. Whether a harsher local scenario can expose the
remaining gap is **unestablished** — it is not asserted here in either direction, and it is `OQ5`.

Two consequences for the acceptance criteria below, and they are why `E2`, `E3`, and `E4` are worded
the way they are:

- Per `docs/loop/conventions.md` and this repository's standing discipline, **only a real run proves
  a claim about the guarding checks.** A locally-green suite is not evidence that CI will pass.
- One green CI run after a change is **one sample**, and the failure's rate is unknown (one run, two
  jobs). A single green run cannot by itself distinguish "closed" from "did not happen to fire that
  time." Something has to be red before the change and green after it, or the absence of that has to
  be recorded as an unmet condition rather than papered over.

## Acceptance criteria

Each is observable, and each names what would be checked to prove it. `E1` is deliberately first:
until the property is stated, none of the others can be checked against anything.

- [ ] **E1 — the cap's property is written down, in the words the code is held to.** The repository
      states which of the three properties above `LARAVEL_LOOP_COST_MAX_LINES` guarantees, where a
      reader of the ledger's own mechanism finds it (alongside the `L7` note that constrains it), and
      states the moment it holds at. *Checked by:* reading that note — it names the property and its
      limit, and the phrase "hard cap" does not appear anywhere without saying at what moment it
      holds.
- [ ] **E2 — the case is green on both guarding platforms, on a real pushed commit.** *Checked by:*
      that run's own output for `guardrails` and `guardrails-macos` — both report the eviction
      convergence case passing, and both report an identical `total: N passed, M failed` line (`A4`'s
      shape, from `docs/loop/checks.md`). No local run, container, or simulation substitutes for this,
      however convincing.
- [ ] **E3 — the change is falsified before it is believed.** An observation exists, reproducible by a
      second person, that is **red against the pre-change script and green against the changed one**,
      with the script versions and the trial count at each recorded. *Checked by:* running it against
      both versions and reading the recorded evidence — the pre-change red is reproduced, not
      asserted. If no such observation can be constructed, that is recorded as an **unmet condition**
      naming what was tried, and `E2` is never presented as covering for it.
- [ ] **E4 — no green run is read as a rate.** The record states how many real runs were observed and
      treats one green run as one sample, not as the failure being gone. *Checked by:* the wording of
      the record — the same lower-bound-not-a-rate discipline `A2` of the previous unit already
      applied to the failure count.
- [ ] **E5 — `L7` is not traded silently.** Either an append still lands its line without waiting on
      the evict lock and its wall clock still does not scale with the hold — case (g) unchanged and
      green — **or** `L7` is deliberately revised, in which case its header note, its stated
      precedence over `L9`, its regression guard, and a `decisions.md` entry are all updated in the
      same change. *Checked by:* case (g)'s result, plus a read of the header and `decisions.md`.
- [ ] **E6 — nothing the ledger already guarantees regresses.** After the change: the ledger is never
      observed empty or torn during eviction and every retained line is complete, parseable JSON, the
      newest N in order (`H3`); one finish record per invocation (`L9`); the hook exits 0 on every
      path including its own errors (`L6`); a deleted ledger is recreated by the next append (`H5`);
      a non-numeric cap still falls back to 5000 rather than disabling the bound; and the suite's
      case total does not drop. *Checked by:* the existing cases for each, unmodified, plus the
      before/after `total:` line.
- [ ] **E7 — no new threshold, default, or suggested value ships.** The cap stays
      `LARAVEL_LOOP_COST_MAX_LINES` at its existing default. Anything new introduced is **unset by
      default** and provably does nothing until a human sets it. *Checked by:* grepping the diff for
      new environment names and numeric literals, plus a case asserting zero output and zero
      behaviour change with it unset.
- [ ] **E8 — the cost of the closing mechanism is measured where it is paid, not asserted.**
      Whatever closes the gap, the work it adds to an appending invocation is stated as an
      observation with numbers. *Checked by:* a timing observation of an append before and after the
      change, recorded — not a claim that the added work is negligible.
- [ ] **E9 — the `L7` answer is recorded so it is not re-litigated.** Whichever way `OQ1` and `OQ2`
      go, `decisions.md` carries an entry naming what was foreclosed and why, including any approach
      considered and not taken. *Checked by:* that entry existing and naming the alternative it
      closed.

## Non-goals

Read these out loud at G0. Each is a direction this could plausibly wander, and several are
directions the previous unit already had to be pulled back from.

- **Not a redesign of the cost ledger.** The record shape, the field set, the JSONL format, the
  oldest-first eviction order, the file's location under `.claude/`, the `mkdir`-based dedup, rework
  bookkeeping, `/cost`'s output, the budget gate, recovered figures, and the held question of
  automatic transcription wiring (`S11`) are all out of bounds beyond exactly what the recorded `OQ1`
  decision requires.
- **Not a change to the cap's value, its default, or its configurability.** No new threshold, no
  suggested number anywhere in the repository, no second knob, and the 5000 default is not tuned as
  a way of making the overage smaller.
- **Not a portability fix.** The platform reading is refuted twice over. No `flock`, no vendored
  coreutils, no compatibility shim, no raising the minimum shell above bash 3.2, and the
  bash-plus-coreutils, zero-dependency constraint is not relaxed as a way of closing this.
- **Not a CI change.** No new job, no matrix expansion, no caching, no retry, no re-run-on-failure,
  no scheduled runs, no artifact upload, and no change to either job's three steps or their
  identical invocation of the suite.
- **Not making red acceptable.** `continue-on-error`, a known-failures list, marking the step
  advisory, quarantining the case, or moving the suite off the guarding checks are all out of bounds.
  The problem is the ledger's bound and the disagreement about it, not the colour.
- **No case weakened, deleted, skipped, or renumbered** as a route to green. If relaxing the failing
  assertion is genuinely the right answer it is `OQ1`'s answer 2, decided by a human at G0 with its
  cost on the table, and it lands as a recorded decision — never as a quiet edit that turns a suite
  green.
- **Not a reopening of the two fixed cases.** `tests/guardrails.test.sh:429` and `:2520` are
  confirmed resolved on both platforms. Their causes are settled, and this is not a continuation of
  either.
- **Not a change to `scripts/ship-check.sh`, its three gates, or the shellcheck policy.** Untouched,
  as they were in the previous unit.
- **Not a general concurrency-hardening pass.** Only the cap property is in scope. `L5`'s append
  atomicity, `L9`'s dedup, and the rework markers are not revisited because eviction is being
  looked at.
- **No new agent, command, hook, state file, phase, or release gate.**
- **No status badge and no CI-health section.** Still a different intent, as it was for the two
  previous units.
- **Not a diagnosis delivered as a spec.** This document establishes the tension and the proof
  problem. It names no cause for the remaining gap and no mechanism for closing it.

## Failure modes

| When | Expected behaviour |
|---|---|
| An append lands while the file is already at cap | The line lands, unconditionally and immediately. Whether the resulting overage is permitted, and until when, is `E1`'s stated property — never a dropped line and never a delayed spawn |
| The evict lock is held by another process | The append still lands and its wall clock does not scale with the hold (`L7`, case (g)) |
| An invocation loses the evict-lock race and is the last to append in the run | **This is the hole.** Today: nothing re-evicts and the file stays over cap at rest. What *should* happen is exactly what `OQ1` decides, and it must be observable which |
| The evictor is killed mid-loop, leaving `.claude/loop-cost-evict.lock` behind | Today: every later appender polls, gives up, appends, and never evicts — a permanent cap violation by a second route. Confirmed pre-existing and twice deliberately scoped out. In scope or not is `OQ4`; not asserted here |
| `mv -f` fails persistently during a trim | The loop breaks, the lock is released, the hook exits 0 (`S9`'s behaviour, unchanged) |
| `wc -l` returns nothing or something non-numeric | Break, no trim, no crash, exit 0 |
| The ledger is deleted mid-run | The next append recreates it; no run fails because it was gone (`H5`) |
| The cap is set to a non-numeric value | Falls back to the existing default rather than disabling the bound or crashing |
| The suite is green locally and red on CI | The CI result is authoritative for a claim about the guarding checks. The local green is not evidence against it, and is not reported as though it were |
| A change makes the case green but nothing was ever red locally | `E3` is recorded as unmet, with what was tried. The change is not described as verified |

## Constraints

**Existing behaviour that must not change** (each has a guard today; a change that regresses one is
a failure of `E6`, not a trade):

- `L7` — appenders never block on the evict lock, and its documented precedence over `L9`. Guarded
  by case (g). Revisable only under `E5`'s conditions, by a recorded human decision, never as a
  side effect.
- `L6` — the hook exits 0 on every path. Cost accounting never blocks, delays, or alters a spawn.
- `L5` — concurrent finishes land as intact lines; no interleaving or tearing.
- `L9` — one finish record per invocation, via the `mkdir` marker.
- `H3` — eviction never truncates the file to empty, not even transiently; retained lines are
  complete, parseable, and the newest N in order.
- `H5` — an absent ledger is normal; the next append recreates it.
- Both CI jobs run the identical suite file with the identical invocation and no platform
  conditional. `docs/loop/checks.md` stays a true map of both check sets.

**Environment:** bash 3.2 and coreutils only, zero dependencies, no `flock` (absent on macOS by
default). The maintainer's host is macOS/arm64/bash 3.2; the guarding platforms are
`ubuntu-latest` and `macos-latest`, and `macos-latest` is a rolling image whose point version is not
a fixed contract.

**Configurability:** `LARAVEL_LOOP_COST_MAX_LINES` already exists and **is** the cap. No new
threshold, default, or suggested value ships anywhere in this repository, and any configurable
introduced ships unset and does nothing until a human sets it.

**Already rejected, and reaching for one owes an argument.** `docs/loop/decisions.md`'s G2-follow-up
entry rejected an **attempt bound**, an **iteration counter**, and a **no-progress guard** — and the
second-G1 entry rejected loosening case A's assertion. Those rejections were about `S9`'s shape and
do **not** automatically bind this unit; a proposal that reaches for one of them is not forbidden,
but it must argue against the recorded reasoning explicitly rather than arrive as if the reasoning
were not there. Re-adding a bound in particular would restore the very convergence gap `S5` removed.

**Also foreclosed, by `spike-case-a.md`:** a deterministic platform or shell-dialect cause (`H1`,
refuted 20/20, and refuted again by the macOS job failing identically). No slice should spend time
re-testing it.

## Open questions

None of these is guessed at below, and two of them are the G0 decision itself.

- **OQ1 — is the cap a hard bound at rest, or eventual convergence?** *Unresolved, and the human's.*
  The maintainer's instinct, recorded at capture and repeated in `intent.md`'s final section, is
  that **the cap should be a hard bound and the code should be fixed** rather than the case's
  expectation being relaxed. That instinct is weighed here and is input, not a decision: the intent
  explicitly does not foreclose the alternative, and the alternative stays live with its cost. The
  cost of each, on the record rather than argued:
  - **Bound at rest (fix the code).** Cost: `OQ2` is unanswered, so the size of the change is
    unknown, and it lands in the one function the previous unit's non-goals declared out of bounds
    beyond a recorded decision. It may require moving eviction responsibility onto the appending
    path, which `E8` then has to measure.
  - **Eventual convergence (relax the assertion).** Cost, recorded by `spike-case-a.md` and by the
    second-G1 decision: the case guards a real, non-platform-specific property, so weakening it
    discards the only warning that the property can be violated at all — and the ledger would then
    declare a bound it does not hold at rest, which `E1` would have to state plainly rather than
    hide. This option is presented for the human because the intent says it is not foreclosed; it is
    not recommended here and it is not framed as the way out.
- **OQ2 — is a bound at rest achievable at all without giving up `L7`, and what would a genuine
  closing mechanism cost?** *Unestablished, in both directions.* It is not assumed achievable and it
  is not assumed impossible. The structural fact is only that *something* must be obliged to trim
  after the last append; nothing here says what, and no mechanism is designed, named, or preferred.
  If the honest answer is that `L7` and a bound at rest cannot both hold, that is itself an answer
  and `E1`/`E9` are where it gets written down.
- **OQ3 — does the failing case's fixture faithfully model a real appender?** *Unestablished.* Its
  writer streams lines directly with `>>` and never once attempts eviction, whereas every real
  appender attempts the lock exactly once. The answer may well be **yes, faithful** — a lock-loser's
  single attempt is a no-op, so a stream of losers is behaviourally a stream of raw writes. Raised
  because if the answer is no, the question of what the case should assert belongs to the human at
  G0 alongside `OQ1`, with `spike-case-a.md`'s recorded cost attached — not to a builder, and not as
  a route to green.
- **OQ4 — is the stale evict lock in scope?** An evictor killed mid-loop never reaches its `rmdir`,
  and every later appender then polls, gives up, and appends without evicting — the same observable
  as `OQ1`'s hole, permanently. It is confirmed **pre-existing**, was deliberately scoped out by a
  prior decision, and the second G2 verdict named it as an open gap that **compounds** with this one.
  In or out is the human's; it is not silently folded in and not silently dropped.
- **OQ5 — can a harsher local scenario expose the remaining gap against today's HEAD?**
  *Unestablished — asserted in neither direction.* The lead is real: the same fixture was red 5/5
  locally against the pre-fix script, so constructed pressure has exposed a version of this bug
  before, and CI is only known to apply *more* pressure than that fixture does. If the answer is no,
  `E3` cannot be met and the human has to decide whether a CI-only proof is acceptable for this unit
  — which is a G0 question, not something a builder discovers on its third refine pass.

## G0 — what the human is deciding

Not a solution, and not permission to build. Two things:

1. **Is the problem framed right** — specifically, is the three-way split of "hard cap" (`E1`) the
   right frame, and are `OQ3`'s and `OQ4`'s scope questions answered the way you want?
2. **Are the non-goals right** — read out loud, above.

`OQ1` is the decision this unit cannot proceed without. Everything else can be sliced around.
