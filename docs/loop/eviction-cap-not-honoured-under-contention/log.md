# Log — eviction-cap-not-honoured-under-contention

**Closed 2026-08-18.** Verdict at G2: **CONCERNS**, on two recorded findings rather than on a
criterion. All nine criteria (`E1`–`E9`) are met, `E2` included, on a real pushed commit — and the
verdict is still not a PASS, which this log says in the same breath as the green run.

The unit that stopped the project arguing about a word. "Hard cap" split three ways, the repository
stated none of them, and that is how a test case and a codebase disagreed about the same
`LARAVEL_LOOP_COST_MAX_LINES` for two releases.

---

## Where it came from

`harness-fails-only-on-linux` closed and its close triggered the first push in that unit's history.
CI run `32112900121`, commit `9f37a5b`, 2026-08-18T07:44Z, failed exactly one case — **its own new
convergence case** — identically on `guardrails` (`ubuntu-latest`) and `guardrails-macos`
(`macos-latest`): `total: 426 passed, 1 failed`, against `427 passed, 0 failed` on the maintainer's
host.

Two things were observed rather than argued, and both are why this unit exists at all:

1. **The failure is not platform-specific.** The macOS runner's `Bash 3.2.57(1)-release` and arm64
   architecture exactly match the maintainer's host, and it fails there too. What the two failing
   environments share is being contended CI runners. `spike-case-a.md`'s `H1` was refuted a second
   time, and its open `H2` — that a runner's resource profile produces an arrival rate a sandbox does
   not — was confirmed by the thing it had named as what would settle it.
2. **The two failures that preceded it are genuinely gone** from both jobs. This is a different
   failure exposed by resolving them, exactly as that unit's floor-is-a-lower-bound record
   anticipated.

Captured with `/observe` as `intent.md` (`bb3c23b`). It recorded whether the defect is in
`append_and_evict()` or in what the case asserts as `unknown`, and recorded the maintainer's instinct
— *the cap should be a hard bound and the code should be fixed* — as **input to G0, explicitly not a
decision**, together with the tension it runs into.

## Phase 1 — Spec (G0)

**Artifact:** `spec.md` — `E1`–`E9`, twelve non-goals, five open questions.

**The framing that mattered.** "Hard cap" is ambiguous, and at least three properties hide inside it:
at every instant, at rest once the last append of a run has landed, or eventually once some later
invocation happens to run. The repository states **none** of them. The failing case asserts property
2; the script's own header accepts *"a ledger that sits slightly over cap for a moment"*, which is
property 3. Neither `S5` nor the orchestrator that shipped it had ever asked which one the cap was
supposed to mean.

The spec also made the **proof problem** a set of criteria rather than a caveat: a real pushed run on
both platforms (`E2`), something red-before/green-after (`E3`), and one green run recorded as one
sample and never as a rate (`E4`). The prior Docker evidence is why: 20 trials across two Ubuntu
versions, two bash versions, and two CPU allocations all settled at cap while CI was red.

**Gate G0 decisions** (`56bbe13`):

| Question | Decision |
|---|---|
| Framing and the twelve non-goals | **Approved.** |
| OQ1 — hard bound at rest, or eventual convergence? | **HELD**, for read-only spikes answering OQ2 (is a bound at rest achievable without giving up `L7`, and at what cost) and OQ5 (can a harsher local scenario go red against today's HEAD). Holding it does not contradict the maintainer's instinct — it establishes whether the instinct is buildable before G1 slices a mechanism nobody has shown is reachable, which is the condition that produced `S5`'s insufficient fix. |
| OQ4 — the stale evict lock | **OUT of scope.** Pre-existing, scoped out twice already, same observable by a different mechanism. It deserves its own intent rather than making one unit answer two causes. |
| OQ3 — does the failing case's fixture model a real appender? | **Folded into the spike**, not answered at G0. |

## Phase 2 — Slice (G1, twice)

**First pass** (`d24e2ce`): three read-only spike slices, **three genuinely parallel lanes**, one
markdown file each, and the **fix group deliberately left uncut** — the third time this repository has
used that pattern (`cost-ledger-blind-to-background-agents` behind its `S6`,
`harness-fails-only-on-linux` behind `S1`–`S4`) and the third time it was right. An envelope names
files, outputs and tests, so writing one would have pre-empted the `OQ1` decision G0 had just held.
The suite was pinned at **427 cases** and `README.md`'s literal untouched by every lane.

**Riskiest was `S2`, for a subtle reason:** it is the only lane that could return a *persuasive wrong
positive*. A red sourced from the out-of-scope stale evict lock has an observable identical to the
convergence gap, so "OQ5: reproducible locally" against the wrong cause would have sent G1 slicing a
fix for the wrong defect. The pinned contracts required every trial to check the lock's absence, and
`S2` did — before and after every trial in every arm.

**What the spikes found:**

| Slice | Finding |
|---|---|
| `S1` (`549a58d`) | **OQ2: not achievable.** Property 2 cannot be *guaranteed* alongside `L7` as documented and as guarded: a run's last appender is a race outcome no invocation can know from inside its own event, and discharging the guarantee needs the returning invocation to wait on the evict lock — the literal thing `L7`'s header rules out. Five obligation classes tabled with their costs; no row occupies "delivers property 2 and keeps `L7`". Carries `E8`'s **before-half**: n=20 per ledger state, under cap mean 148.0 ms / median 144.5 (min 136, max 216), over cap mean 153.2 / median 149.5 (min 145, max 180) — about 5 ms mean attributable to a real 5000 → 15 eviction on that host. |
| `S2` (`05b6762`) | **OQ5: YES — but not by re-running case (f) harder.** Case (f)'s own scenario reproduced 0/5 red at baseline, and every single-dimension variant stayed green: cap 2 (0/5), 300000 writer lines (0/5), 4 concurrent writers (0/5), 8 / 50 / 200 concurrent real hook invocations (0/10 each), staggered arrivals (0/5), plus an exploratory multi-dimension arm (0/15). The red came from a third construction: a real hook invocation forced to be the run's **last** appender while the evict lock is genuinely held past `L7`'s ~0.1 s poll budget — **5/5 red against HEAD `d24e2ce`** and **5/5 red against the pre-`S5` script** (`68ece94^`, `f64174a`), with a sanity control at `HOLD_SECONDS=0.02` staying **0/5**. The 5/5 against pre-`S5` is load-bearing: the hole predates `S5` and is not its regression. The filesystem dimension is recorded **untried** (one APFS container; the worktree guard refused `hdiutil`), not tried-and-negative. |
| `S3` (`1302a3e`) | **OQ3: NO.** The fixture's per-write mechanism matches a real lock-loser exactly, so `spec.md`'s candidate answer reads the code correctly on that narrow point — but its **arrival rate** does not, and rate is the whole point of a 20000-line stream. A real appender pays up to 100 ms of poll backoff, a fresh script invocation with roughly 15 subprocess forks, and finished-marker bookkeeping before its line lands (one uncontended real invocation measured at **137.7 ms**, producing a **242-byte** record). The fixture constructs a **harsher** world than production, so its red is evidence of a rate-independent gap in the algorithm, not evidence that real concurrent invocations reach that volume. |

**Second pass** (`8ccd635` / `86b9363`), cut against those three answers and the second G1's decision:
four slices, **parallel set EMPTY and stated as a finding**, critical path `S4 → S5 → S6 → S7`.
`S4 → S5` share the header block and both move `README.md`'s case-count literal; `S5 → S6` and
`S6 → S7` are logical (there is nothing to measure before `S5`, and `S7`'s entry carries `S6`'s
number).

**Gate G1 (second) decisions** (`decisions.md`, *Second G1: the ledger promises convergence…*):

- **The cap promises `E1`'s property 3 — eventual convergence — stated explicitly**, and obligation
  **class 3**: a later invocation checks and trims on arrival unconditionally. The slicer refined the
  class further than the brief did — not "a later invocation" but *an arrival that appends nothing* —
  which is what keeps `L7` genuinely untouched, since the trimming invocation is not an appender.
- **Case (f) is replaced, not weakened**, with `S2`'s construction, using a **synchronous** lock
  release rather than a timed hold: a timed hold can release inside `L7`'s 0.1 s budget on a loaded
  runner and go green for the wrong reason, which is exactly how this unit's original failure hid.
- **Case counts pinned as deltas only** (+1 / +3 / 0 / 0), with a five-step build-time computation
  rule and no absolute literal anywhere — because `recovered-figure-drops-slice-and-model` was
  concurrently walking the same `README.md` literal from 427 toward 460. Two further cross-unit
  collisions were named at the same gate: README's cost-ledger paragraph and `decisions.md`'s
  end-of-file insertion point.
- **Riskiest is `S5`**, and the hazard is real: an unbounded trim loop lands on `PostToolUse`/`Bash`,
  the most frequent hook arrival in the repository. Class 3 costs appenders nothing but moves work
  onto the hottest path in the system. That trade is what `OQ1`'s answer bought, and it was surfaced
  before it shipped rather than after.
- **Residuals nobody closes:** `S2`'s filesystem dimension stays untried, and `E9` was already met by
  the gate entry itself, so `S7` adds only the placement variants rejected at this gate.

## Phase 3 — Build

Four slices, four `--no-ff` merges (`df16f6d`, `487c09e`, `a340b84`, `6863d81`), full suite green
after each. The literal moved 439 → **440** (`S4`) → **449** (`S5`, computed at build time as
446 + 3 with the neighbour unit's cases already merged in between); `S6` and `S7` are markdown-only,
delta 0.

| Slice | Delivered |
|---|---|
| `S4` (`3079ab9`) | The eviction header and README's ledger paragraph now name property 3, the moment it holds at (a later invocation having arrived and discharged the trim), and that a bound at rest is not achievable while `L7` stands. Documentation only — property 3 was already true, so no commit ever leaves the header describing behaviour the script does not have. One conjoined docs case. |
| `S5` (`6c38cbf`) | The trim loop factored out of `append_and_evict()` into `converge_ledger()` — **one implementation, called by both paths** — and the two arrival paths that end without appending (the `Bash` rework branch that emits no `cap_trip`, and the deduped duplicate-finish discard) call `trim_on_arrival()`: one `mkdir` attempt, no poll, no retry, no `sleep`, so `L6` and `L7` stand unamended. `CAP_TRIP_EMITTED` guarantees one trim per invocation — unfalsifiable by a case, so it was written to be *read* at G2 and labelled as such. Case (f) replaced in place, asserting strictly more (the hole constructed, the ledger observed over cap **at rest**, then observed converged), both tokens in one `expect` so it cannot pass vacuously. **`E3`: 5/5 red / 5/5 green** against `git show d883886:scripts/record-cost-event.sh`. |
| `S6` (`ecad22e`) | `measure-e8-after.md` — `E8`'s after-half. n=20 per arm per version, interleaved same-driver control. The appending path did not move (arm (a) −0.5 ms mean / +0.9 ms median; arm (b) −2.6 / +4.6; ranges overlapping both ways). The newly obliged arrival pays **+16.1 ms mean / +15.7 ms median** over cap and **+6.7 / +7.1** under cap, and the over-cap arrival arms are where the pre-change script left the ledger at **5000** lines and the post-change one left it at **15** — the cost buys exactly that. |
| `S7` (`d5d55e2`) | `decisions.md` gains a build-out entry beneath the gate entry, not a rewrite of it: **seven placement foreclosures**, each with its reason, carrying `S6`'s figures as numbers rather than adjectives. |

One thing to name rather than praise, from the verifier's own `Do NOT` check: `S5`'s commit also did
the `converge_ledger()` factoring *and* both arrival call sites in one commit — which is what its
envelope specified, so it was checked rather than assumed.

## Phase 4 — Verify (G2)

**Artifact:** `verify.md` (`abebd5b`). **Verdict: CONCERNS.**

Every criterion carries the case that proves it and whether that case runs. `E3` was **re-reproduced
by the pass** rather than taken from the build report: the merged case (f) is red against
`git show d883886:scripts/record-cost-event.sh` in an isolated tree copy and green in the merged
tree. `E1` was checked independently — `grep -rn "hard cap"` finds the phrase only in the **budget
gate's** unrelated wording and in this unit's own docs, never in the ledger mechanism. `E5` was
checked by byte-comparison: case (g)'s whole block is identical pre-`S4` and at `HEAD` (md5
`f1067344…` both sides). `E6` confirmed one removed assertion in `tests/` — case (f)'s old
single-token `expect`, replaced by a two-token one asserting more.

⚠ **Independence limit, stated in the file rather than implied:** the pass ran inline in the same
session that built `S5`–`S7`, not as an independent `loop-verify` agent. Every figure was
re-derived, and the file says a verifier who did not write the code would be stronger evidence.

**`E2`, on a real pushed commit.** `main` was pushed at `55f1822` (36 commits, the first push since
`bb3c23b`). CI run **`32173406965`**: `guardrails` (`ubuntu-latest`) and `guardrails-macos`
(`macos-latest`) both report the eviction convergence case `ok`, both report the three arrival cases
`ok`, and both report an identical **`total: 465 passed, 0 failed`** — which is `A4`'s cross-job
shape. `shellcheck` and `scripts are executable` passed on both runners.

**Read that as one sample per platform, because that is what it is.** One green run on each platform
is one observation per platform. It is not a rate, and it is not the failure class being gone. The
case it exercises is deterministic — it constructs the lock hold rather than racing for it — which is
the only reason a single green run means anything here at all; a timing-dependent case would need
many. The two prior pushed runs (`32117525156`, `32113202275`) are red in this history and **stay**
red: the first is the observation that opened this unit, the second is the previous unit's recorded
`A1` failure. Neither is retroactively fixed by this run.

**The two findings the verdict rests on, carried forward by name:**

1. **`S5`'s case (i) — `arrival trim never waits` — is green against the pre-change script, where
   its brief forecast red.** The envelope said cases 1–3 "have no code path at all" today.
   Reproduced: case (f) is red and the Bash-arrival case is red, but case (i) **passes** against
   `d883886`, because with no arrival trim at all "returns fast" and "leaves the over-cap ledger
   untrimmed" are both trivially true. It is still a legitimate guard rather than an assertion that
   cannot fail — a polling arrival trips its elapsed-time token, and one that trimmed while the lock
   was held trips `NOWAIT_STILL_OVER` — but **it guards a regression, it does not prove the fix, and
   it must never be cited as red-before evidence.** Open.
2. **`E8`'s cross-document comparison is inconclusive**, as `measure-e8-after.md` §4 already states.
   Arms (a) and (b) measured for the after-half sit **below** `spike-oq2-bound-at-rest.md` §4's
   observed min for the same arms (a: 113–133 here vs 136–216 there; b: 123–164 vs 145–180), in the
   same direction — which points at the timing instrument (`S1` recorded *that* wall clock was taken,
   not with what) and host load rather than at the code. The literal min-max spread check `S6` asks
   for therefore answers **no**, and that answer is not evidence about the code. The same-driver
   interleaved control was substituted for it, and the substitution is stated rather than smoothed
   over. Closing this needs `S1`'s instrument reconstructed. Open.

A third item is recorded in `verify.md` and belongs to the neighbouring unit, not this one: the
`recovered-figure` `S1`/`S5` fixture clash, a G1 defect the human ruled on.

**Gate G2: CONCERNS is the human's to act on.** Both fixes shipped in release `0.6.1` (`c32daf0`),
whose own commit records `ship-check.sh`'s three gates passing, verdict `go`, and `E2` met on
`55f1822` with one-green-run-is-one-sample said in the release commit itself. `CHANGELOG` carries
both open items rather than presenting the release as closing them.

## What this unit foreclosed

Recorded so none of it is re-litigated. From the second G1 entry:

- **Property 2 / a hard bound at rest** — the maintainer's own recorded instinct, tested by `S1`'s
  spike and declined **on its evidence**, not on preference. It needs obligation class 1 or 2, both of
  which give up `L7`: unbounded waiting on the appending path against a measured ~148 ms baseline, and
  class 2 cascades across concurrently spawned invocations.
- **Classes 1 and 2** (the appender guarantees before returning; a lock-loser retries), and **classes
  4 and 5** (a sweep at the run's end; a detached continuation) — property 3 at best, each with an
  unestablished reliability question or a per-append process spawn.
- **Leaving case (f)'s assertion as it stood**, and **deleting or weakening it without replacement** —
  `S2`'s construction means the guard could be kept *and* made reproducible.
- **Amending `L7` itself.** If the never-block guarantee is the thing to question, that is a
  spec-level question deserving its own unit at G0, never a side effect of this decision.

From `S7`'s build-out entry, seven placement foreclosures with their reasons: arrival-trimming on
every invocation including appenders; a second copy of the trim loop; extending the obligation to
`record-recovered-cost.sh`; obliging the two unregistered early exits (`SubagentStop`, the unmatched
`*)`); `S2`'s timed lock release inside the replaced case; keeping the 20000-line raw-writer arm
(with cases (a) and (b) named as where its cover now lives); and an attempt bound / iteration counter
/ no-progress guard — restated because the arrival path is a fresh place to re-propose one, and
re-adding a bound would restore the very convergence gap `S5` removed.

## What this unit did not close

- **`OQ4` — the stale evict lock. Still out of scope, still open, and it still needs its own intent.**
  An evictor killed mid-loop never reaches its `rmdir`, and every later appender then polls, gives up,
  and appends without evicting — the same observable as this unit's hole, permanently, by a second
  route. Scoped out at G0, cut nowhere, no position recorded by any slice, and not folded in by
  `S5`'s arrival trim.
- **Finding 1** (case (i) green against the pre-change script) and **finding 2** (`E8`'s
  cross-document comparison inconclusive) — both open, both named above, both in `CHANGELOG` for
  `0.6.1`.
- **Case (f)'s original CI-shaped scenario was never reproduced locally**, at any dimension `S2`
  tried. What reproduces is a different, more direct construction of the same *named* structural
  hole. The two findings stay separate in the record.
- **`S2`'s filesystem dimension stays untried** — recorded as untried, not as tried-and-negative.
- **Nothing is claimed about CI's cost.** Every `E8` figure is one host, serial, n=20. No rate, no
  percentage, no extrapolation.
- **The independence limit stands.** `S5`–`S7` were verified by the session that built them.

## The ledger measuring this unit

The cost ledger holds **8 invocations** for this slug — spec, both slicing passes, and builds `S1`,
`S2`, `S3`, `S4`, `S5`. Every one was launched backgrounded, so `record-cost-event.sh` wrote a
`finish` record with `status: "async_launched"` seconds after each launch while the agent ran for
minutes; all eight landed **unpriced**, and none has been transcribed with
`scripts/record-recovered-cost.sh`. `S6` and `S7` have no ledger record at all — that work did not run
as a separate agent invocation, and the hook only ever sees `Agent|Task`.

So the `## Cost` section below reports **0 % coverage** and prints no token total. That is honest
output from the same blind spot `cost-ledger-blind-to-background-agents` shipped `v0.6.0` to describe,
reproduced again here — not a bug in the section, and not evidence this unit was free. No token figure
for this unit is stated anywhere in this log, because the ledger does not hold one.

## Cost

Coverage: based on 0 of 8 invocations that carry a token figure (8 unpriced, not counted) -- 0 % coverage; wholly unobserved: spec, slice, build

Tokens: nothing about this unit's token cost is observable -- 0 of 8 invocation(s)
carry a token figure. No total is printed here (unmeasured, never zero).

Rework: this figure counts whole invocations that needed at least one refine pass, at
whole-invocation granularity -- deliberately over-attributing rather than estimating a
per-pass split, and NOT the cost of retrying. It is not comparable to the requirements
document's <15% target (Sec.10), which was calibrated against a narrower, per-pass
definition. No pass/fail verdict against that target is printed here.
  count: 0 of 8 invocation(s) marked rework
  token share: unavailable (no priced invocations are marked rework)


---

## The open items above, at the backlog gate (2026-08-19)

- **`L7` stands, and it is now settled rather than merely unexamined.** The never-block guarantee is
  the reason cost accounting never delays a real tool return, and this unit tightened convergence
  without touching it — which is the strongest evidence available that the guarantee and a useful cap
  are compatible. Recorded so it stops being re-litigated at every eviction gate; new evidence can
  still reopen it.
- **`OQ4`, the stale evict lock, is captured as its own intent** —
  `docs/loop/stale-evict-lock-permanently-defeats-the-cap/` — after being declined by three units in
  a row. It is queued **second** at `G0`, behind the macOS parse-error observation. It is no longer an
  aside in this unit's records, and this unit is not waiting on it: the fix here is complete on its own
  terms, and a stale lock defeats it by a different route that was always out of scope.
- **`E8`'s comparison limitation stays as recorded.** The instrument is now written down in
  `measure-e8-after.md` §6, so the next append measurement is like-for-like; the earlier baseline's
  instrument cannot be recovered, and no figure here pretends otherwise.

**This unit is closed.** Its verdict stays CONCERNS — the two findings are recorded, not resolved
away — and `E2` is met on a real pushed commit, one sample per platform.
