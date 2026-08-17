# Log — ship-gate-blind-to-ci

Closed 2026-08-17. Verdict at G2: **PASS**, scoped to S1–S4, with A1 held out and assigned to
the maintainer as H1.

The unit that made the release gate and the pushed-commit checks stop disagreeing in silence.

---

## Where it came from

Not a spec someone wanted. A fault noticed while shipping v0.6.0: `/ship` returned
`verdict: go`, the tag went out, and CI on that same commit failed — as it had on **all twelve
runs in the surviving history**, back to v0.2.0 on 2026-08-13. Six releases, every one red.

Captured with `/observe` as `intent.md`, which recorded what was observed, where, when, what was
tried, and the suspected commit — and recorded the earliest run's cause as `unknown` rather than
inferring it from a later run's.

`docs/loop/ship-observe-automation/spec.md` had already predicted this unit: it said a new intent
would be required before an executable-bit check could enter the G3 gate set. It also *declined*
such a gate at the time, reasoning CI already covered it. That premise is what this fault
falsified.

## Phase 1 — Spec (G0)

**Artifact:** `spec.md` — A1–A9, eleven non-goals, three open questions.

The framing that mattered: the gap is **bidirectional**. `ship-check` verifies version agreement
that CI never checks; CI verifies the executable bit that `ship-check` never checks. A green
result on either side was being read as "this is fine" when it can only ever mean "the part I
look at is fine."

The immediate trigger was one file — `scripts/cost-ledger-lib.sh`, committed `100644`, existing
only to be sourced, failing a check that expected every `.sh` under `scripts/` to be runnable.
Whether the file or the expectation was wrong was left to G0.

**Gate G0 decisions:**

| Question | Decision |
|---|---|
| OQ1 — mark the library executable, or narrow the check? | **Narrow it, via a marker comment inside the file.** `chmod +x` rejected: it would assert a never-run file is runnable and leave A5 unsatisfiable, making the next library folklore. |
| OQ2 — should the release action gate on agreeing with CI? | **No. The parity check lives in the harness; the gate set stays exactly three.** A fourth gate rejected, and "make ship-check state its blind spot" rejected. |
| OQ3 — account for the earliest failure? | **A6 as written.** Name the six versions, leave run `31696279581`'s cause `unknown`, no archaeology. |

A1 was identified at G0 as not closable by any agent: its only proof is a real Actions run on a
real pushed commit.

## Phase 2 — Slice (G1)

**Artifact:** `slices.md` — four builder slices, one human action, **zero parallel lanes**.

The seam it found: the smallest valuable change is neither the file mode nor the document, but *a
command that fails on this tree today and names the offending file*. So S1 lands the rule and its
checker while the tree is still non-conforming — the check correctly reports the tree as wrong
before anything is fixed. S2 conforms it, S3 points CI at the same rule, S4 writes down what the
two sets are.

**Zero parallelism was a finding, not an omission.** README hard-codes the harness total and the
suite's own final case asserts that number matches the live tally, so every slice edits one
shared literal. Two lanes would conflict by construction, and the loser's merge would leave the
suite red on a case nobody touched.

**Gate G1 decisions:** approved as cut, single lane, S1 first. Two slicer-chosen shapes accepted
explicitly rather than by default:

- **The shared checker** — `scripts/check-script-modes.sh`, one program both CI and the harness
  call, so A4 is true by construction rather than by promise. Follows this repository's own
  precedent in `cost-ledger-lib.sh`'s header, which refuses a second implementation for the same
  reason. Cost accepted and recorded: `scripts/` gains a twelfth file, so A5's "eleven files"
  reads as twelve on the resolved tree.
- **The marker and its anchor** — `# laravel-loop:sourced-library`, exact full line, no leading
  whitespace, within the first 20 lines. The anchor exists because the checker and the harness
  must both *contain* the literal and would otherwise classify themselves as libraries.

## Phase 3 — Build

Four slices, four `--no-ff` merges, full suite green after **each** merge rather than only the
last. Harness 404 → 421 cases (+17).

| Slice | What it delivered |
|---|---|
| S1 | `scripts/check-script-modes.sh` and the rule verbatim in its header. Landed green while the tree was still non-conforming. 7 cases. |
| S2 | The marker in `cost-ledger-lib.sh` — one comment line, mode untouched at `100644`. The tree conforms. 2 cases. |
| S3 | CI's `scripts are executable` step now runs the shared checker and nothing else. Parity cases execute `ci.yml`'s **extracted** `run:` body, never a retyped copy. 4 cases. |
| S4 | `docs/loop/checks.md` — both sets, both deltas, the red release history. 4 cases. |
| H1 | **The maintainer, post-merge.** A1. No slice claims it. |

**Two process faults hit during build, both recorded as conventions below.** The slicing agent
was killed mid-response by a machine sleep event and had to be resumed; and every one of the four
builders found its worktree base behind `main` and merged it in before writing code, which is the
existing convention working as intended rather than a new fault.

## Phase 4 — Verify (G2)

**Artifact:** `verify.md`. **Verdict: PASS**, scoped to S1–S4.

The verifier took nothing on trust. It rebuilt a scratch-clone revert ladder across all five
commits — 404, 411, 413, 417, 421 — confirming red-before-green was real at each step rather than
claimed. It attacked A4's tautology risk directly by probing the CI-step extractor with a
nonexistent step name, proving it fails closed (rc=1, empty) instead of silently skipping. It ran
`ship-check.sh` twice on an unchanged tree to confirm A9's determinism. It confirmed
`git diff -- tests/` has zero removed lines, so no assertion was weakened to reach green. And it
checked that the two "declared count" grep hits it found both pre-date this diff before reporting
them.

**A1 was held out of the PASS**, on the same precedent as DC4/DC5 in
`cost-ledger-blind-to-background-agents`. A verifier willing to fold A1 in would have been
reproducing this unit's own bug inside its own verification.

**Gate G2 decision:** approved, close the unit.

---

## What this unit did not close

- **A1 / H1** — the only proof is a real Actions run concluding success on a pushed commit. Open
  until that run exists, and its run id belongs in this file when it does.
- **The v0.2.0 run's cause** (`31696279581`) stays `unknown`, by decision, not by omission.
- **No CHANGELOG entry, no version bump.** S4's `Do NOT` kept `CHANGELOG.md` untouched
  deliberately: no release is amended to have been green, and anything touching a published
  artifact is G4.

## The ledger measuring this unit

Every one of the seven agent invocations in this unit was launched **backgrounded**, so
`record-cost-event.sh` wrote a `finish` record with `status: "async_launched"` seconds after each
launch while the agent ran for minutes. All seven landed unpriced: the exact blind spot
`cost-ledger-blind-to-background-agents` shipped v0.6.0 to describe, reproduced on the unit that
followed it.

All seven were then **transcribed by hand** with `scripts/record-recovered-cost.sh`, from the
figures in their own completion notifications — the first real exercise of that entry point, and
the by-hand check DC5 asks for. Coverage moved 0 % → 100 %, and the report labels all seven as
`transcribed rather than host-observed`, permanently, as OQ5 required.

**Two findings from doing it by eye**, which is what DC5 was for:

1. **A resumed invocation is unreachable.** The slicing agent was resumed via `SendMessage` after
   the sleep event, and that resumed run carries a *different* tool-use id — one the ledger has
   no record of, because the cost hook matches `Agent|Task` and never sees a `SendMessage`. Its
   figure had to be attributed to the original launch's id. The tokens spent on the *failed first
   attempt* are reported nowhere at all, by anything.
2. **A transcribed figure silently drops dimensions.** The recovered record carries only
   `invocation_id`, `slug`, `total_tokens`, `token_source`. The report joins on `invocation_id` to
   recover the **phase** — per-phase counts are correct — but model-per-phase then reads
   `unavailable` for all four phases, and the Slices table reads `no slice attributed to any
   priced invocation`, even though `slice: S1`–`S4` sit in the very start records it just joined
   against. Restoring the total costs the slice and model dimensions. This is a defect in v0.6.0's
   shipped reporting, found only by transcribing and looking, and it is the first thing S11 should
   answer rather than automate around.

## Cost

Coverage: based on 7 of 7 invocations that carry a token figure (0 unpriced, not counted) -- 100 % coverage; 7 of 7 priced figure(s) transcribed rather than host-observed (667094 of 667094 priced token(s), 100 %)

Tokens: 667094 (priced subset only, partial -- 0 unpriced invocation(s) not counted)

Rework: this figure counts whole invocations that needed at least one refine pass, at
whole-invocation granularity -- deliberately over-attributing rather than estimating a
per-pass split, and NOT the cost of retrying. It is not comparable to the requirements
document's <15% target (Sec.10), which was calibrated against a narrower, per-pass
definition. No pass/fail verdict against that target is printed here.
  count: 0 of 7 invocation(s) marked rework
  token share: unavailable (no priced invocations are marked rework)

