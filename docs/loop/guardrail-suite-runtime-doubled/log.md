# Log — guardrail-suite-runtime-doubled

**What this unit did:** removed a fork per entry from the three `PATH`-farm helpers — three lines —
and measured what it bought. At suite level, on one loaded host with interleaved arms, n=3 per arm:
**mean 257.66s → 160.73s**, proving byte-identically the same 513 cases in the same order.

**The runtime problem is reduced, not settled.** Option (b) — building each of the three distinct farm
shapes once instead of twelve times — was knowingly left on the table at G0 and is now a captured
intent with its own open question, not a comment.

## Where it came from

The suite took 3m38s on the maintainer's host and had stopped fitting a 2-minute tool timeout. Nothing
guarded runtime, so nothing failed and nothing warned: the increase arrived silently across three
merges in one day and was noticed by a timeout.

The intent recorded three figures as **not established** — the before figure ("completed inside a
2-minute timeout" is a bound, not a measurement), CI's runtime on either platform, and whether the
`PATH`-building helpers accounted for the increase at all. The specification pass took all three
rather than reasoning from the coincidence of timing.

## Phase 1 — Spec (G0), held 2026-08-20

`spec.md` §1 is the whole evidence base, and it is measurement rather than inference:

- **§1.1, the paired before/after**, same host, back to back: **88.53s at 466 cases → 218.79s at 513**.
  +10.1 % cases for +147 % wall clock, system time up 172 %. **Runtime is not tracking case count** —
  the first thing that had to be ruled out, and ruling it out is what made this a fixture-cost problem
  rather than a "the suite got bigger" observation.
- **§1.2, both platforms**, read from CI's own job records across five runs: 112s → 212s on
  `ubuntu-latest`, 129s → 223s on `macos-latest`. Labelled **upper bounds** on the suite's own share,
  because job duration includes checkout, `shellcheck`, the script-mode check, and a Homebrew install
  on macOS.
- **§1.3, what one farm build costs**, n=3 per arm: **10.17s** with `base="$(basename "$f")"`,
  **4.75s** with `base="${f##*/}"`, both producing 2002 links from 2043 candidate entries. `basename`
  is a **fork per entry** — ~2043 process spawns per build — which is what puts the cost in system
  time rather than in the shell evaluating assertions.
- **§1.4, twelve builds, three distinct shapes.** `new_stub_parser_path` is called **ten times** and
  its ten symlink passes are **byte-identical**, differing only in one file planted afterwards.
  Eleven of the twelve builds are new since `18289f2`: 11 × 10.17s ≈ 112s against a measured increase
  of 130.3s, so the farms account for **roughly 86 %** of it. The residual ~18s is deliberately
  attributed to nothing.
- **§1.5, why the farms are shaped this way, and what may not be traded.** They symlink *everything*
  on purpose: a curated allow-list makes a fixture pass for the wrong reason, recorded at
  `tests/guardrails.test.sh:2770-2775` on 2026-08-18, when a sparser `PATH` missing `grep`/`sed` made
  the library report a parse error. **The 10.17s is not waste — it is what the fixtures were priced at
  when the alternative was a false green.**

Four decisions taken at G0, each with the cost it accepts:

| Question | Decided | Cost accepted |
|---|---|---|
| **OQ-RT1** how far | **(a) only** — the fork removed | Option (b)'s ~92s **left on the table**; the problem is reduced, not settled |
| **OQ-RT2** guard it? | **Record, do not assert** | The next silent increase is again caught by a person, not a check — which is how this one arrived |
| **OQ-RT3** literal absence? | **Moot at this scope**, deferred with (b) | Travels with (b)'s intent, where a human answers it before any build |
| **OQ-RT4** the residual ~18s | **Leave unattributed** | Not chased; attributing it means per-case instrumentation, its own build |

The reasoning behind (a)-alone is the one worth keeping: (b) is a design change to a fixture whose
entire value is that it cannot lie, and bundling it with a one-line fix is the exact cost
`cost-log-section-parse-error-on-macos-ci`'s `OQ1` already recorded paying.

## Phase 2 — Slice (G1), 2026-08-20

Two slices, `S1 → S2`, sharing no file. Seven pieces of field evidence written into `slices.md` so no
slice re-derives them. Nothing was cut for option (b), deliberately, and `slices.md` says why in its
own "Not cut" section.

The notable thing about `S1`'s envelope: **it has no red-before-green, and says so rather than
inventing one.** Nothing fails today — the suite is green and this is a cost change, not a defect fix.
So `RT3`, the ordered case-title-and-result list, is what makes the slice believable, and the
measurement is the deliverable.

## Phase 3 — Build, 2026-08-20

| Slice | What it changed | Result |
|---|---|---|
| **S1** | `base="$(basename "$f")"` → `base="${f##*/}"` at `tests/guardrails.test.sh:3089`, `:3114`, `:3141`. Nothing else in the three helpers | Six interleaved runs, all `total: 513 passed, 0 failed`. Mean 257.66s → 160.73s, median 247.51s → 158.35s, per-pair deltas 112.16 / 89.15 / 89.49s. Ordered case list `6e90cf1f95d7` on **all six** |
| **S2** | One appended entry in `docs/loop/decisions.md`; new captured intent at `docs/loop/suite-path-farms-rebuilt-twelve-times/` | Suite still green at 513. No case, no script, no README change |

Two `basename` calls were **deliberately left**: `:3554`'s two-argument suffix-stripping form, which
`${f##*/}` does not replace, and `:5876`'s loop over a handful of named files inside the claim-word
guard, where the fork count is small. Both are outside the three helpers, and a repo-wide fork audit
is a separate intent — a worthwhile one, named in `spec.md`'s non-goals.

**The saving came in larger than the scope was accepted on.** G0 took (a) against a projected ~65s;
the arms show 89–112s. The measurement file states the discrepancy and labels the candidate
explanation — idle-host benchmark versus loaded-host arms, per-fork cost rising under load — as
consistent with the evidence and **unverified**, rather than presenting it as the reason.

## Phase 4 — Verify (G2), 2026-08-20 — **CONCERNS**

`verify.md` carries the pass. Seven of eight criteria met, `RT3` in the strongest form available: all
513 case titles and results, in order, byte-identical across both arms and all three trials.

**`RT7` is unmet and it is the whole of the concern.** It requires both guarding platforms' figures
from a real pushed commit, and nothing has been pushed. That is not substitutable by a local run, by
this criterion's own terms: the thing removed is a fork, and per-fork cost differs between bash 3.2 on
macOS and bash 5.x on Linux. `spec.md` §1.2 already holds five runs of before-figures on both
platforms, so the comparison is ready to be made the moment a run exists — nothing needs re-measuring
locally.

## What this unit foreclosed

- **The fork per entry**, in all three farm helpers. Measured, not assumed.
- **A runtime threshold, timeout, or wall-clock assertion.** `OQ-RT2` decided record-don't-assert, and
  `RT8` holds it: no script changed at all, so nothing could ship set.
- **Bundling the build-once redesign into a one-line fix.** Declined at G0 with the reason recorded.
- **Losing the deferred 92s to a comment.** `S2` made it an intent with `OQ-RT3` attached.
- **Any reduction in what a fixture proves.** `RT2`'s three self-checks pass unmodified; the
  bin-directory list and every skip condition are byte-identical.

## What this unit did not close

- **`RT7`.** Both platforms, from a pushed run. Outstanding.
- **The runtime problem.** Reduced, not settled. 160.73s is a loaded-host mean of three runs and is
  **not** a new baseline; the suite remains well above `18289f2`'s 88.53s.
- **Option (b).** Deferred, and its ~92s is now stale — computed against a per-build rate that no
  longer applies. The captured intent re-states it as roughly 43s at the post-fix rate, **unmeasured**.
- **Why the projection under-predicted.** Unverified by design.
- **An independent G2.** Same-session pass.

## Cost

No records for this unit ("guardrail-suite-runtime-doubled") in the cost ledger. Not evidence the unit was free --
the ledger simply has nothing filed under this slug.

