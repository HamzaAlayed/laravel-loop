# Log — resumed-invocation-never-reaches-the-ledger

**Stage 1 of three is complete. The gap is stated; nothing is claimed.** A run resumed with
`SendMessage` is not recorded as an invocation, its tokens are in no total, and a killed attempt's
tokens are recorded nowhere by anything. This unit made the repository say that accurately, and
made it a red for any surface to start implying otherwise. It did **not** capture a resume, did not
raise pricing coverage, and produced no token figure for one — because `RE4` establishes there is no
figure to be had.

**Still open, and deliberately so:** `S5`, the spike that asks whether a `hooks.json` matcher on
`SendMessage` fires at all, has not run. Stage 3 (group `RS`) is uncut, and cutting it before that
answer exists would be a G1 defect rather than an optimisation.

## Where it came from

The ledger's coverage was already documented for background launches — `X5` put that statement in
`README.md`. Resumption was the hole beside it: `hooks/hooks.json` matches `Agent|Task` on
`PreToolUse` and `PostToolUse`, and a `SendMessage` that resumes an existing agent is neither. So the
resumed run's tokens land in no total, and nothing in the repository said so.

`RE4` is the finding that shaped the whole unit: **capturing a resume yields no token figure.** The
resume's own usage is not exposed to anything this repository can read, so even a perfect capture
would record a *record*, never a *number*. That is why Stage 1 is documentation and freezes rather
than instrumentation, and why the unit cannot be the thing that satisfies the "background pricing
coverage rises materially" condition an earlier backlog gate attached to a dropped routing item.

## Phase 1 — Spec (G0), 2026-08-19

Nine criteria, `RV1`–`RV9`, every one provable from fixtures and greps with no live hook — which is
precisely what let Stage 1 land while the mechanism question stayed open. `RE12`, the question of
whether the matcher fires, is recorded as **UNKNOWN and deliberately unasserted in both directions**.

The structural decision was the three-stage shape: Stage 1 (`RV1`–`RV9`, fully provable), Stage 2
(the spike), Stage 3 (group `RS`, branching on the spike's answer). **Stage 2 gates Stage 3
absolutely** — and the spike's deliverable is three-valued, not two: the matcher fires *with* the
target agent id, fires *without* it, or does not fire. The middle answer collapses to the same arm as
the last one but for a different recorded reason, and both negatives are recorded distinctly.

**"Does not fire" is a success.** It closes group `RS` with a real answer. A spike returning it has
succeeded and is not retried, worked around, or re-briefed.

## Phase 2 — Slice (G1), 2026-08-19

Five slices cut, and the pass **stopped at five on purpose**. `S1`–`S4` are Stage 1; `S5` is the
spike; Stage 3 was left uncut with the reason written down rather than implied — a slice envelope
names files, outputs, tests and a record shape, so writing one now would commit the repository to a
capture design chosen against a mechanism the spec records as unestablished in both directions. That
is the design decision the gate withheld, arriving from a slicer instead of from evidence.

## Phase 3 — Build, 2026-08-19

| Slice | Commit | What it settled |
|---|---|---|
| S1 | `28a4a09` | `README.md` states, beside the existing background-launch statement, that a resumed run is not an invocation and that a killed attempt's tokens are recorded nowhere. Three cases, including one asserting the paragraph carries **no forthcoming-figure vocabulary** — it does not promise a number later |
| S2 | `c8d796d` | Locked what output and documentation may never claim: a **100 %-priced** fixture's whole report carries no completeness vocabulary, and no README line mentioning coverage does either. Plus `RV3`'s byte-identity — every figure identical with and without an unrecognised-event line — and `RV6`'s rework count and share unchanged |
| S3 | `df25b34` | Froze two surfaces against a literal block (the budget gate's breach output, `log.md`'s `## Cost` section) and pinned the coverage sentence's prefix as the start of the sentence in **all three** consumers |
| S4 | `099eed0` | Recorded in `decisions.md`, dated and with its evidence, that this unit **cannot** raise pricing coverage — a record, never a number — while leaving the existing routing bullet byte-identical with no superseded marker attached |

Merged at `a30010a`. Three files changed in the whole unit: `README.md`, `docs/loop/decisions.md`,
`tests/guardrails.test.sh`. No script, no hook.

Two build-time diagnoses are worth keeping, both about the harness rather than the product:
`read -r -d ''` strips **all** leading blank lines from a heredoc, so a frozen block's leading newline
needs `IFS=` on the read to survive; and a frozen block's trailing newline has to be matched exactly
or the diff is a false red. Both cost a pass to find.

## Phase 4 — Verify (G2), 2026-08-20 — **PASS, on a declared partial scope**

`verify.md` carries the pass: all nine criteria met, suite green at `513 passed, 0 failed`, both CI
jobs on pushed commit `1bd510b` reporting the identical total.

The claim worth re-reading is `RV4`/`RV9`'s. Rewording the frozen coverage prefix by a single word —
`based on` → `derived from` — reddens **fourteen cases across five units**, three of them this unit's
own. The frozen surface is genuinely pinned, not nominally pinned, which is what makes an append-only
rule enforceable at all.

One scope fact is recorded rather than left to be discovered: `RV3`'s fixture uses an
unrecognised-event line as the stand-in for "whatever this unit records for a resume", because what
this unit records is nothing. That is the closest constructible fixture and the honest reading of a
criterion written before the answer was settled.

## What this unit foreclosed

- **Any token figure for a resume or a killed attempt.** Not from the launch's figure, not from a
  duration, not by halving or doubling, not from an average of priced invocations. `RV3` makes each of
  those a red.
- **Calling any coverage figure complete, full, or verified while the gap is open** — in output *or*
  documentation, and asserted against the 100 %-priced fixture specifically.
- **Reporting a resumed run as a refine pass**, and reopening per-pass token granularity. A restart is
  a run, not a pass.
- **Retiring the standing routing decision by implication.** A new entry may not attach a superseded
  marker to it, and a case checks that.
- **Cutting Stage 3 on a guess.** The gate withheld it and this build did not take it back.

## What this unit did not close

- **Whether the `SendMessage` matcher fires.** `S5` has not run. Still `UNKNOWN`, still unasserted in
  both directions, and a green suite is never evidence about hook registration.
- **Stage 3, and therefore capture itself.** Uncut, pending the spike.
- **Pricing coverage.** Cannot be raised by this unit. `RV8` is the record of that, not a step
  toward it.
- **An independent G2.** Same-session backfill, written the day after the merge.

## Cost

No records for this unit ("resumed-invocation-never-reaches-the-ledger") in the cost ledger. Not evidence the unit was free --
the ledger simply has nothing filed under this slug.

