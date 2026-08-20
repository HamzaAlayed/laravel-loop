# guardrail-suite-runtime-doubled

**Status: G0 held 2026-08-20.** Approved with all four open questions decided — see
*G0 decisions* below, which records the cost each decision accepts. Criteria are prefixed `RT`.
The approved scope is **option (a) only**: the fork-per-entry removed, the build-once redesign
deferred to its own unit with its own gate.

Captured as an intent 2026-08-19T21:11:25Z. Specified 2026-08-20, and the specification pass took the
four measurements the intent recorded as **not established** — they are in §1, labelled, with their
sample counts. Nothing in this document infers a cause from a coincidence of timing.

## Problem

`tests/guardrails.test.sh` takes **3m38s** on the maintainer's host. It took **1m28s** 47 cases
earlier. The case count rose 10.1 %; the wall clock rose 147 %, and the *system* time — the part
spent in the kernel rather than evaluating assertions — nearly tripled.

Three things make this worth a unit rather than a shrug:

1. **It is paid on every push, on both guarding platforms, and on every local validate.** CI's own
   job durations roughly doubled over the same span (§1.2). Every future slice in every future unit
   pays this before it can be believed green.
2. **It already changed how the suite can be run.** A full run no longer fits a 2-minute tool
   timeout. That is not a preference; it is a builder having to reach for a different invocation, and
   it is how a suite starts being run less often.
3. **Nothing guards it, so nothing failed.** No criterion in any unit covers suite runtime. The
   increase arrived silently across three merges in one day and was noticed by a timeout, not by a
   check.

**What this is not.** The suite is green — 513 passed, 0 failed, on both platforms. Nothing here
suggests a case is wrong, and no case is a candidate for removal. This is a unit about the *cost* of
proof, not about the proof.

## Users

- **The builder validating a slice.** Runs the suite several times per slice, and pays the full cost
  each time. This is the user whose behaviour changes first when a suite gets slow.
- **CI, on every push, twice.** `ubuntu-latest` and `macos-latest` both run the full suite; the cost
  is paid twice per push and gates every merge.
- **The maintainer reading a red.** A 3m38s feedback loop between a hypothesis and its answer is the
  real cost, and it compounds with the refine cap: three passes is now eleven minutes of waiting.

## 1. What the record establishes — measured in this pass, not inferred

Every figure below was taken on 2026-08-20 on `Darwin 25.6.0` arm64, bash 3.2.57, except §1.2 which
is read from CI's own job records. **Counts and samples, never rates.**

### 1.1 The before and after, paired, same host, back to back

| Commit | Cases | Wall clock | User | System |
|---|---|---|---|---|
| `18289f2` | 466 | **1m28.53s** | 32.70s | 38.83s |
| `HEAD` (`1bd510b`) | 513 | **3m38.79s** | 68.13s | 105.63s |

Two runs, one sample each, taken minutes apart on an otherwise idle host. `18289f2` was measured from
a disposable `git archive` copy, never a checkout of the working tree. **The intent recorded the
earlier figure as a bound rather than a measurement; this replaces the bound with a measurement.**

+47 cases (+10.1 %) for +130.3s (+147 %). System time rose 172 %. Runtime is **not** tracking case
count, which is the first thing that had to be ruled out.

### 1.2 Both guarding platforms, read from CI's own job records

| Commit | Cases | `guardrails` (ubuntu) | `guardrails-macos` |
|---|---|---|---|
| `e59215c` | — | 84s | 100s |
| `5e833bc` | — | 86s | 114s |
| `18289f2` | 466 | 112s | 129s |
| `f31bc1f` | — | 181s | 218s |
| `1bd510b` | 513 | 212s | 223s |

Five runs, one sample per job per commit. Job duration includes checkout, `shellcheck`, the
script-mode check, and on macOS a Homebrew install of `shellcheck`, so these are **upper bounds on
the suite's own share** and are not comparable to §1.1's figures. The trend is the point, and it is
present on both platforms. **The intent recorded CI runtime as `unknown`; this establishes it.**

### 1.3 What one `PATH`-fixture build costs

Three helpers build an isolated `PATH` by symlinking every resolvable entry of `/usr/bin`, `/bin`,
`/usr/sbin`, `/sbin`, `/opt/homebrew/bin` and `/usr/local/bin` into a fresh `mktemp -d`. On this host
that is **2002 symlinks** from **2043 candidate entries**.

| Arm | n | Trials | Mean |
|---|---|---|---|
| As the suite builds it — `base="$(basename "$f")"` | 3 | 10454, 10008, 10047 ms | **10.17s** |
| Identical, `base="${f##*/}"` (bash builtin) | 3 | 4748, 4744, 4752 ms | **4.75s** |

Both arms produce **2002 links**, so the arms are comparable. `basename` is a **fork per entry**:
~2043 process spawns per build, which is what puts the cost in system time rather than user time.
The remaining 4.75s is `stat` and `symlink` syscalls, and is not attributable to the shell.

### 1.4 How many builds a suite run performs, and how many are distinct

| Helper | Call sites | Base shape it needs |
|---|---|---|
| `new_stub_parser_path` | **10** | every entry except `jq` **and** `python3`, then one stub planted |
| `new_grep_absent_path` | 1 | every entry except `grep` |
| `new_jq_absent_path` | 1 | every entry except `jq` |

**Twelve builds; three distinct base shapes.** The ten `new_stub_parser_path` calls perform a
**byte-identical symlink pass** and differ only in which single stub file is written afterwards — read
from the helper, which takes the stub's body as a parameter and plants it after the loop.

12 × 10.17s ≈ **122s** of the 218.8s run. Eleven of those twelve builds are new since `18289f2`
(`new_jq_absent_path` is pre-existing): 11 × 10.17s ≈ **112s**, against a measured increase of
130.3s. **The `PATH` farms account for roughly 86 % of the increase.** Stated as an accounting of one
paired sample, not as a rate, and the residual ~18s is not attributed to anything.

### 1.5 Why the farms are shaped the way they are — and what may not be traded away

The helpers symlink *everything* rather than a curated list on purpose, and the reason is a finding
this repository already owns, recorded at `tests/guardrails.test.sh:2770-2775` on 2026-08-18: **a
sparser `PATH` missing `grep`/`sed` made the library report a parse error** rather than falling
through to `python3`. A curated allow-list makes a fixture pass for the wrong reason. Any change here
that reintroduces one re-opens the exact defect
`cost-log-section-parse-error-on-macos-ci` closed, so the cost in §1.3 is **not waste** — it is what
the fixtures were priced at when the alternative was a false green.

The two properties that must survive any change: each fixture presents the **genuine absence** its
case depends on, and each fixture's own self-check case (`(S1-1)`, `(S2-1)`, and
`(S2-1) new_jq_absent_path resolves python3 and not jq`) still passes **unmodified**.

## Acceptance criteria

`RT1`–`RT3` are what must not be traded. `RT4`–`RT6` are the measurement discipline. `RT7`–`RT8` are
the outcome, and they are deliberately last, because a number reached by weakening a fixture is worse
than the current runtime.

- [ ] **RT1 — no case is removed, weakened, skipped, renumbered, or made conditional.** The case
      total does not drop, no assertion line is deleted, and no case gains a guard that lets it not
      run. *Checked by:* the diff against the case list, the before and after `total:` lines from both
      platforms, and a grep of the diff for new skip/conditional constructs around `expect`.
- [ ] **RT2 — every `PATH` fixture still presents the genuine absence its case depends on, proven by
      that fixture's own self-check.** `(S1-1)`, `(S2-1)` and `new_jq_absent_path`'s self-check pass
      **unmodified**. No curated allow-list is introduced anywhere, per §1.5. *Checked by:* those
      three cases unmodified and green, plus a read of each helper for the set it excludes.
- [ ] **RT3 — no case's outcome changes.** Every one of the 513 cases reports the identical result
      before and after. A faster suite that changes what a case proves has failed this criterion
      regardless of its colour. *Checked by:* capturing the full ordered list of case titles and
      results before and after and diffing it — byte-identical, including order.
- [ ] **RT4 — the before figure is a measurement, not a bound.** Already satisfied by §1.1 and
      recorded there; any slice that re-measures states its host, its sample count, and whether the
      arms were interleaved. *Checked by:* reading the recorded figures for those three facts.
- [ ] **RT5 — the improvement is measured where it is paid, in interleaved arms, and stated as
      numbers.** Before and after, same host, same driver, arms interleaved rather than run in two
      blocks, n stated, mean **and** median given. The `stale-evict-lock` unit's `S8`
      (`measure-sl6-append-cost.md`) is the shape to follow. Never a claim that the saving is
      "significant". *Checked by:* that measurement file existing with those fields.
- [ ] **RT6 — one green run is one sample, and CI's figures are labelled as upper bounds.** No
      sentence treats a single fast run as the suite's new runtime, and no §1.2-style job duration is
      compared directly against a §1.1-style suite timing. *Checked by:* the wording of the record.
- [ ] **RT7 — the measured saving is real on both guarding platforms.** The after figure is read from
      **both** jobs on a real pushed commit, not inferred from the local host. The `basename`-fork
      cost in particular is a per-fork cost that differs between bash 3.2 on macOS and bash 5.x on
      Linux, so a local-only figure cannot stand in. *Checked by:* both jobs' durations on the
      pushed commit, beside §1.2's table.
- [ ] **RT8 — nothing new ships set.** No threshold, timeout, budget, or suggested runtime appears
      anywhere. If a runtime figure is recorded, it is **recorded**, not asserted against — see
      `OQ-RT2`. *Checked by:* a grep of the diff for new environment names and numeric literals.

## Non-goals

- **Making the suite fast.** The goal is to stop paying ~112s for eleven rebuilds of a fixture that
  is built twelve times and differs three ways. It is not a performance project, and there is no
  target runtime in this document.
- **Parallelising the suite.** Out of scope entirely. The suite's cases share fixtures, a working
  directory, and an append-ordered ledger; parallelism is a different unit with a different risk
  profile, and it would make a flaky red possible where none is possible today.
- **A CI-only remedy.** Caching, a matrix split, or a runner upgrade leaves the local 3m38s exactly
  where it is, and the local run is where a builder's loop actually lives.
- **Reducing what any fixture proves.** §1.5 is the reason. This is the non-goal most likely to be
  breached by a builder chasing `RT7`.
- **Touching `.github/workflows/ci.yml`.** No job, matrix, or timeout change.
- **Deleting the `basename` calls elsewhere in the repository.** This unit's scope is the three
  `PATH`-farm helpers. A repo-wide fork audit is a separate intent, and a worthwhile one.

## Failure modes this unit must not produce

- **A curated allow-list creeping back in** under the name of an optimisation, re-opening the
  2026-08-18 false-green route.
- **A shared fixture that leaks between cases.** If a base farm is built once and reused, a case that
  writes into it — a stub, a chmod, a removal — contaminates every later case using it. Any
  build-once design has to make the shared base read-only in practice, and `RT3` is what catches a
  failure here.
- **A runtime assertion that goes red on a loaded runner.** A wall-clock threshold in the suite would
  be flaky by construction, on shared CI hardware, and a flaky guard is worse than no guard.
- **Measuring the fix on the host that motivated it and calling it done.** `RT7` exists for this.

## Constraints

- bash 3.2.57 is the floor (macOS's `/bin/bash`); `${f##*/}` is available there, and was verified
  available in §1.3's own measurement, which ran on it.
- The suite is one file, run identically by both jobs with no platform conditional
  (`docs/loop/checks.md`). Anything added here is paid twice per push.
- `docs/loop/checks.md` must gain a row if a check is added, removed, or renamed on either side.
- The standing all-five-unset rule governs thresholds, defaults, and suggested values (`RT8`).

## Open questions — all four decided at G0, kept here for the costs they carry

**All four are answered in *G0 decisions* below.** They stay written out because the option table
holds the measured costs of the roads not taken, and a later unit re-opening (b) should start from
these numbers rather than re-derive them.

- **OQ-RT1 — how far to go?** Four options, with §1's measured costs attached. **Decided: (a).**

  | Option | Mechanism | Measured saving | Risk |
  |---|---|---|---|
  | **(a)** | `basename` → `${f##*/}` in the three helpers | ~5.4s × 12 ≈ **65s** | Lowest available. Three one-line edits, no design change, no shared state. `${f##*/}` and `basename` differ only on trailing slashes, which a `bin` entry cannot have |
  | **(b)** | Build each of the three distinct bases **once**, reuse across call sites | 9 fewer builds ≈ **92s** | Introduces shared fixture state — the leak in Failure modes. Needs `RT3` to be believed |
  | **(c)** | Both | ≈ **108s** of a 218.8s run | (a)'s risk plus (b)'s |
  | **(d)** | Change nothing; record the figures and add no guard | 0 | The runtime keeps growing silently, which is how this arrived |

  *The reading this document offered, and the one the gate took:* **(a) alone is the honest first unit.**
  It is three lines, carries no shared-state risk, and its saving is measured rather than projected.
  (b)'s 92s is the larger prize but it is a design change to a fixture whose whole value is that it
  cannot lie, and it should be its own unit with its own gate — not bundled into a one-line fix, for
  exactly the reason `cost-log-section-parse-error-on-macos-ci`'s `OQ1` records about bundling two
  diffs into one unit.

- **OQ-RT2 — should suite runtime be guarded at all, and if so how?** A guard is what would have
  caught this. But an asserting case needs a threshold, which `RT8` and the standing unset rule
  resist, and a wall-clock assertion on shared CI hardware is flaky by construction. Options: record
  the figure in `docs/loop/checks.md` and re-read it by eye; assert a case-count-to-runtime ratio;
  assert nothing. **Decided: record, do not assert** — a flaky guard would be spent to buy a thing
  a human can read off two job durations.

- **OQ-RT3 — does "genuine absence" have to be literal for the ten stub-parser cases?** This is the
  question that decides whether option (b) can collapse ten builds into one. Today the real `jq` and
  `python3` are *never symlinked* into a stub fixture. A shared base excluding both, with a small
  per-case directory ahead of it on `PATH` holding only the stub, gives identical resolution — but the
  real binaries would be absent from the base rather than absent from the *system*, which is already
  true today. **Decided: moot at this scope**, and deferred with (b) — the helper's own comment states the
  stricter property, and with (b) out of scope no builder is asked to reinterpret it.

- **OQ-RT4 — is the residual ~18s worth attributing?** §1.4 accounts for ~112s of a 130.3s increase
  and deliberately attributes nothing to the rest. Chasing it means per-case timing instrumentation,
  which is its own build. **Decided: leave it unattributed** and say so, which is what §1.4 does.

## G0 decisions — held 2026-08-20

All four questions decided, each recorded with the cost it accepts so none is re-litigated and no
foreclosed alternative has to be rediscovered.

- **OQ-RT1 — option (a) only.** `basename "$f"` → `${f##*/}` in the three `PATH`-farm helpers.
  Measured saving ~5.4s per build × 12 builds ≈ **65s** of a 218.8s run. Three one-line edits, no
  shared state, no fixture redesign.
  **Cost accepted, and it is the larger number:** option (b)'s ~92s is **left on the table**. This
  unit will not collapse twelve builds into three, so the suite stays well above where it was at
  `18289f2` and the runtime problem is *reduced, not settled*. That is deliberate — (b) is a design
  change to a fixture whose entire value is that it cannot lie, and bundling it with a one-line fix
  is the failure `cost-log-section-parse-error-on-macos-ci`'s `OQ1` records the cost of. (b) is
  **captured as its own intent** by this unit rather than left as a comment, so the 92s is not
  quietly forgotten.
- **OQ-RT2 — record, do not assert.** No runtime threshold, no case asserting a wall clock, no ratio
  check. The figures live in this unit's measurement file and `log.md`, and a human re-reads two job
  durations when they want to know.
  **Cost accepted:** the next silent runtime increase will again be caught by a person noticing, not
  by a check — which is exactly how this one arrived. That cost is taken knowingly, because a
  wall-clock assertion on shared CI hardware is flaky by construction, and a flaky guard spends more
  trust than it buys. No check is added, so `docs/loop/checks.md` gains no row.
- **OQ-RT3 — moot at this scope, and deferred with (b).** The question only exists to decide whether
  ten builds can collapse into one. With option (b) out of scope, no fixture's absence property is
  reinterpreted and no helper's stated contract is touched. It travels with (b)'s intent, where a
  human answers it before any build, rather than being answered here by nobody.
- **OQ-RT4 — the residual stays unattributed.** §1.4 accounts for ~112s of a 130.3s increase and
  attributes nothing to the rest. Chasing ~18s means per-case timing instrumentation, which is its
  own build and is not worth it against a 65s saving already in hand.

## G0 — held and approved

Approved 2026-08-20. What was approved:

1. **The problem framing and every figure in §1**, read as counts and samples rather than rates —
   including that runtime is not tracking case count, which is what makes this a fixture-cost
   problem rather than a "the suite got bigger" observation.
2. **§1.5 read out loud and unchanged**: the farms symlink everything on purpose, a curated
   allow-list makes a fixture pass for the wrong reason, and the 2026-08-18 finding is why. The
   measured 10.17s is what the fixtures were priced at when the alternative was a false green.
3. **The non-goals unchanged**, with the load-bearing ones being: **no case removed, weakened, or
   made conditional**; **no fixture proves less than it proves today**; and **no parallelism**.

Approval is approval of the problem, of §1's evidence, and of option (a) as the mechanism. It is not
approval of a runtime target — there is none in this document, and `RT8` keeps it that way.

Next step is `/slice`.
