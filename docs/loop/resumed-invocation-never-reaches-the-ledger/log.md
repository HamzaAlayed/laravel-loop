# Log — resumed-invocation-never-reaches-the-ledger

**Stage 1 of three is complete. The gap is stated; nothing is claimed.** A run resumed with
`SendMessage` is not recorded as an invocation, its tokens are in no total, and a killed attempt's
tokens are recorded nowhere by anything. This unit made the repository say that accurately, and
made it a red for any surface to start implying otherwise. It did **not** capture a resume, did not
raise pricing coverage, and produced no token figure for one — because `RE4` establishes there is no
figure to be had.

**Stage 2 and Stage 3 have since landed (2026-08-20).** `S5` ran and returned **(a)**: the matcher
fires and the payload carries the target agent id. Arm A was cut on that answer and built as `S6`–`S9`.
Arm B is closed permanently. The paragraph above stands as the record of what was true when Stage 1
closed; the sections at the end of this file carry what happened next.

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

## Phase 2 — the spike (S5), 2026-08-20 — answer **(a)**

Driven by the maintainer, on a probe kit built for the purpose and left outside the repository. A
throwaway project registered the matcher on both events plus two control matchers, and a fresh session
launched a subagent and resumed it.

**The control fired 6 times; `SendMessage` fired 4 — twice on each event, across two sessions.** `to`
and `recipient` were present on 4 of 4 payloads (the *input*); `resumedAgentId` on 2 of 2
`PostToolUse` payloads (the *response*), and where both existed the two ids matched. That is answer
**(a)**, both halves, recorded separately as `SP5` required.

One finding kept because it would have wasted the next person's run: Claude Code's *"Ignoring N
`permissions.allow` entries … this workspace has not been trusted"* warning covers `permissions.allow`
**only** — the hooks in the same file still fire. An untrusted workspace is not a reason to discard a
run; the control arm is what settles whether a run counted.

`SP4`'s four cleanup steps all ran. `hooks/hooks.json` was untouched by the spike and the live plugin
install was never reinstalled or reconfigured.

## Phase 3 — Stage 3 cut (G1) and built, 2026-08-20

**The cut discharged its couplings rather than assuming them.** `spec.md` made this unit third of
three and required whoever cuts Arm A to read the two earlier units' *landed* diffs first. Both had
landed and both were verified at G2 the same day: the parse-error unit left **both parser program
bodies byte-identical**, so `RS10`'s rebase was additive; the evict-lock unit meant Arm A adds records
to a **working** cap rather than a defeated one.

**Two design questions were settled by evidence rather than chosen** — the return on having run the
spike instead of guessing:

- **The event is `PostToolUse`.** `resumedAgentId` lives only on the response, and it *is* `RS3`'s
  resumed-agent marker. A `PreToolUse` record could neither satisfy `RS3` nor know the resume
  succeeded.
- **The idempotency key already existed:** `tool_use_id`, distinct per resume event in both observed
  payloads. `RS4`'s "per resume, not per agent" needed nothing invented.

Also corrected against the spec's own text: `agentId` was discarded **by omission**, not at
`record-cost-event.sh:661-667`. There was no discard to delete, only a field to start reading.

| Slice | Commit | What it did | Cases |
|---|---|---|---|
| **S6** | `2332a5b` | Read `agentId` onto finish records, forward-only. Field **absent** when the payload lacks it — the same choice every other optional field already makes, so no consumer sees a schema change | 513 → 521 |
| **S7** | `9a94816` | The `resume` record, referencing the agent, counted as an invocation nowhere. One 9-line `hooks.json` entry | 521 → 529 |
| **S8** | `99ca292` | Reader-side resolution, exact match, both parser programs. `agent_id → slug` map populated **before** the slug filter, so "another unit" and "nothing at all" stay distinguishable | 529 → 537 |
| **S9** | `2685351` | The appended clause, conditional and figure-free, plus the two counters `RS6` needs | 537 → 544 |

A deliberate behaviour change, recorded rather than discovered later: a `resume` line used to land in
`COST_N_SKIPPED` as an unrecognised event and no longer does. `RV3`'s fixture was built with an event
name chosen specifically to *stay* unrecognised, so that unit had already anticipated this.

## Phase 4 — Verify (G2), 2026-08-20 — **CONCERNS**

All eleven `RS` criteria met, suite green at `544 passed, 0 failed`, `shellcheck` clean. `verify.md`
carries the row-by-row pass.

**The concern is the precondition, and it is the maintainer's.** `(S7-8)` proves the matcher is
*registered*; liveness needs a plugin reinstall and a restart, and `conventions.md` is explicit that a
green harness never proves a hook is live. So the honest status is **the writer behaves correctly on
payloads we constructed** — not *resumes are being captured*. One real resume observed landing in
`.claude/loop-cost.jsonl` closes it.

One existing case was changed and it was **tightened**: `(S7-1)` had demanded an identical coverage
sentence, while `RS1` permits exactly one difference and `S9` made it live. The replacement pins
prefix byte-identity and confines the addition to the resume clause — mutation-tested, not assumed.

## What Stage 3 foreclosed

- **Inventing a second invocation.** `RS1`, asserted over every count, figure and row.
- **Guessing the reference.** Exact match only, with the two-invocation fixture there to kill
  nearest-by-time, most-recent, and only-other-invocation.
- **Reading attribution out of a resume's prose.** The record stores no unit and no message, so there
  is nothing to read.
- **A figure for a resumed run.** Asserted over record keys, so a zero or a null placeholder fails.
- **Backfilling the join key.** Forward-only, asserted over the whole file.
- **Arm B.** Closed by the spike's answer; `RB1`–`RB4` will not be cut.

## What Stage 3 did not close

- **Liveness.** The G2 precondition above. Registered, not observed.
- **A resumed run's cost.** Not knowable — `RE4` stands. `agent_id` is a handle, never a figure.
- **Both platforms' colours on this work.** Unpushed at the time of writing.
- **An independent G2.** Same-session build and verify.
