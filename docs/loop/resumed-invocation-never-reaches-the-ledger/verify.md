# Verify — resumed-invocation-never-reaches-the-ledger (S1–S4 only; Stage 1 of three)

**Verdict: PASS, on a declared partial scope.** All nine criteria `RV1`–`RV9` are met, each with at
least one case that can fail, and the suite reproduces green at `513 passed, 0 failed` on both
guarding platforms. **This pass covers Stage 1 (`S1`–`S4`) and nothing else.** `S5`, the spike, has
not run; Stage 3 (group `RS`) is deliberately uncut. Neither is a finding against this pass — they
are the unit's own design, and this verdict does not reach them.

**What Stage 1 was for, stated so the PASS is not misread:** the gap is *stated*, nothing is
*claimed*. This unit does not capture a resumed invocation, does not raise pricing coverage, and does
not produce a token figure for a resume. A PASS here means the repository now says so accurately and
cannot quietly start implying otherwise — not that the gap is addressed.

**Scope, declared rather than implied:**

- **Changed surface:** `README.md`, `docs/loop/decisions.md`, `tests/guardrails.test.sh`.
  Commits: `28a4a09` (S1), `c8d796d` (S2), `df25b34` (S3), `099eed0` (S4), merged at `a30010a`.
  No script under `scripts/` was changed by this unit, and `hooks/hooks.json` was not touched.
- **Full suite reproduced green** on this host: `total: 513 passed, 0 failed`; `shellcheck` clean.
- **Both guarding platforms:** run `32366734933` on pushed commit `1bd510b`, jobs `96417752555`
  (`guardrails`) and `96417752188` (`guardrails-macos`), each `total: 513 passed, 0 failed`.
- ⚠ **Backfilled gate.** `a30010a` merged 2026-08-19; this pass was written 2026-08-20. It reports on
  merged code and did not gate the merge.
- ⚠ **Same-session limit.** `RV4`/`RV9`'s byte-identity claims were re-reproduced here by mutation
  rather than accepted from the commit messages; the pass is still not an independent one.

---

## Criteria, one row each

| Criterion | Verdict | Proven by, and does it run |
|---|---|---|
| **RV1** — the repository states plainly that a resumed run is not recorded, its tokens are in no total, and a killed attempt's tokens are recorded nowhere | **MET, three cases** | `docs: README states a SendMessage-resumed run is not an invocation, its tokens are in no total, and names hooks.json's Agent|Task matcher as the reason`; `docs: README states a killed attempt's own tokens are recorded nowhere, by anything`; and a third asserting the paragraph carries **no forthcoming-figure vocabulary** — i.e. it does not promise a number later. All three green, all grep-provable, none needing a live hook |
| **RV2** — nothing is described as complete, full, or verified while the gap is open | **MET, both surfaces** | `RV2 (live output)`: a **100 %-priced** fixture's whole report carries no completeness vocabulary — the strongest form, since that is the fixture most tempting to call complete. `RV2 (documentation)`: no README line mentioning coverage also carries completeness vocabulary. Follows `docs/loop/checks.md:79`'s precedent for refusing "covered, verified, guaranteed, proven" |
| **RV3** — no token figure is fabricated, estimated, imputed, or apportioned | **MET** | `RV3`: the priced total, the coverage sentence including its share, and every per-phase and per-slice figure are **byte-identical** whether or not an unrecognised-event line is present. **Named rather than glossed:** the fixture uses an unrecognised-event line as the stand-in for "whatever this unit records for a resume", because what this unit records is *nothing* — the honest reading of a criterion written before that was settled, and the closest constructible fixture |
| **RV4** — a resume-free ledger reads and reports byte-identically to today | **MET, reproduced** | `(2)` the budget gate's own breach output and `(3)` `log.md`'s `## Cost` section are each diffed against a frozen block for one resume-free fixture. Both re-proven capable of failing in this pass: rewording the coverage prefix by one word reddens both. See Reproduction |
| **RV5** — every existing coverage, budget and reporting criterion holds, no case edited | **MET** | Case total is **513**, far above the 466 the criterion names as the floor, and `git diff 099eed0~4 a30010a -- tests/guardrails.test.sh` removes **no** `expect` or assertion line at all. CV1–CV8, BG1–BG14, PE1–PE6, CL1–CL9, RC1–RC7, RD1–RD11 all still carry their original cases, unmodified and green |
| **RV6** — a resumed run is never reported as a refine pass, and no per-pass token figure appears | **MET, both halves** | `RV6`: the rework count and the rework token share are unchanged by an unrecognised-event line; and the "no per-pass token figure anywhere" assertion passes **unmodified** over the same fixture. Per-pass granularity stays dropped; a restart is a run, not a pass, and nothing here reopens it |
| **RV7** — nothing added can block, delay, reorder, or steer anything | **MET, with its reasoning stated** | `RV3: both the recognised-only and the unrecognised-line ledger exit 0 (RV7)` asserts exit 0 per fixture rather than in aggregate. This unit adds **no new executable path** — its diff is `README.md`, `decisions.md` and cases — so "every new path" is satisfied by there being none, which is stronger than a passing assertion. The neither-`jq`-nor-`python3` clause is carried by inherited cases (`PATH stripped of jq+python3 still exits 0`, and `(j)` CO13), green and unmodified, rather than by a new case of this unit's |
| **RV8** — the RE4 finding is recorded in `decisions.md` with date and evidence | **MET, both directions** | `(1)` the entry exists, is dated, and names a **record-never-a-number** plus the routing condition it does **not** satisfy — i.e. this unit is not the thing that makes "background pricing coverage rises materially" true. `(2)` the pre-existing routing bullet stands **byte-identical with no superseded or revisited marker attached**, which is the half that stops a new entry silently retiring an old decision |
| **RV9** — the coverage sentence's prefix stays byte-identical; new wording is appended | **MET, reproduced** | `(1)` the prefix begins the sentence in **all three** consumers for one resume-free fixture. `cost_coverage_sentence()` carries the rule in its own header, and appending is how that sentence has already been extended twice. Re-proven capable of failing: see Reproduction |

## Findings

**None blocking, none non-blocking.** The two things a reader should carry away are scope facts rather
than defects: this verdict covers Stage 1 only, and `RV3`'s fixture uses an unrecognised-event line as
a proxy for a record this unit deliberately never writes. Both are stated in the rows above rather
than left for someone to discover.

## `Do NOT` check — clean

No token figure invented for a resume or a killed attempt, by any route — not from the launch's
figure, a duration, a halving, or an average. No existing case edited or renumbered. The routing
decision left standing and unmarked. `hooks/hooks.json` untouched — confirmed by
`git diff 099eed0~4 a30010a --name-only`, which lists three files, none of them a script or a hook.
No `RS`-group slice was written, cut, or started: `slices.md` stops at `S5` and says in its own words
why cutting Stage 3 now would be a G1 defect.

## Reproduction

Run in a disposable copy (`git archive HEAD | tar -x`), pristine control first.

```
# Control, pristine:                                        total: 513 passed, 0 failed
# RV4/RV9 — the frozen coverage prefix reworded, one word:
#   printf 'based on %s of %s invocations ...'  ->  'derived from %s of %s invocations ...'
#                                                             total: 499 passed, 14 failed
#   FAIL (1) RV9: the coverage sentence's prefix begins the sentence in all three consumers
#   FAIL (2) RV4: the budget gate's own breach output is byte-identical to a frozen block
#   FAIL (3) RV4: log.md's '## Cost' section is byte-identical to a frozen block
#   + 11 more from earlier units (BG3's CV8 breach case, CL4/CL5/CL6/CL8, RD8, PF8/PF10)
```

Fourteen cases across five units fire on a single reworded word. That is the frozen surface being
genuinely pinned rather than nominally pinned, and it is the reason `RV9`'s append-only rule is
enforceable at all.

## What this pass cannot tell you

- **Anything about `S5`'s question.** Whether a `hooks.json` matcher on `SendMessage` fires, and
  whether its payload carries the target agent id, is `UNKNOWN` and deliberately unasserted in both
  directions. `spec.md` records it as `RE12`; nothing here leans either way, and a green suite is
  never evidence about hook registration.
- **Anything about Stage 3.** Uncut on purpose. A slice envelope naming files, outputs and a record
  shape would commit the repository to a capture design chosen against an unestablished mechanism —
  which `spec.md` calls a G1 defect rather than an optimisation.
- **Whether pricing coverage can be raised.** It cannot, by this unit, and `RV8` is the record of
  that rather than a step toward it.
- **Independence.** Same-session backfill, as declared in Scope.

---

# Verify — Stage 3, Arm A (S6–S9), 2026-08-20

**Verdict: CONCERNS** — all eleven `RS` criteria are met, each with at least one case that can fail,
and the suite is green at `544 passed, 0 failed`. The concern is the precondition `slices.md` named
at G1 and reserved for the maintainer: **no real resume has been observed landing in the ledger**, so
the honest status of this arm is *the writer behaves correctly on payloads we constructed* — **not**
*resumes are being captured*.

Same shape as `guardrail-suite-runtime-doubled`'s `RT7` earlier today: nothing is wrong with the diff,
and one piece of evidence only a human can produce is outstanding.

**What closes it.** Reinstall the plugin, restart, run one real resume, and confirm a `resume` record
appears in `.claude/loop-cost.jsonl`. `S5`'s probe is the precedent for making that observation and
its control-arm discipline is the precedent for reading it.

**Scope:**

- **Changed surface:** `scripts/record-cost-event.sh` (S6, S7), `hooks/hooks.json` (S7, one 9-line
  entry), `scripts/cost-ledger-lib.sh` (S8, S9 — both parser programs and the sentence helper),
  `tests/guardrails.test.sh`, `README.md`. Commits `2332a5b` (S6), `9a94816` (S7), `99ca292` (S8),
  `2685351` (S9).
- **Suite:** `513 → 544` cases across the four slices, `0 failed`. `shellcheck -S warning` clean,
  script modes ok.
- ⚠ **This arm changes runtime behaviour once the plugin is reinstalled.** Every slice before it today
  was documentation, tests, or a cost change. This one starts writing a new record type.
- ⚠ **Same-session build and verify.**

## Criteria, one row each

| Criterion | Verdict | Proven by |
|---|---|---|
| **RS1** — recorded as a reference, counted as an invocation nowhere | **MET** | `(S7-1)`, tightened when S9 landed: every count, token total, both rework figures and every per-slice row identical with and without the record, **and** the coverage sentence's prior text surviving as a byte-identical prefix. Mutation-tested — making the clause replace rather than append reddens it. `(S8-4)` repeats the figure half at the reader |
| **RS2** — exact match on the identifier, and nothing else | **MET** | `(S8-1)` holds **two** invocations in two units, each with its own resume, so nearest-by-time, most-recently-launched and only-other-invocation all get one wrong. Each attaches to the unit whose `agent_id` it names. `(S8-2)` is the negative |
| **RS3** — a message to an already-running agent is not a resumed run | **MET** | `(S7-2)`: no `resumedAgentId` → nothing written, exit 0. Implemented as a **refusal** rather than a detection, because the negative branch is the uncorroborated part of the evidence base |
| **RS4** — two resumes are two; one delivered twice is one | **MET, both directions** | `(S7-3)`, deduped on `tool_use_id` — distinct per resume event in both of `S5`'s observed payloads, so the key was not invented |
| **RS5** — the unit comes from the referenced invocation, never the payload | **MET, structurally** | `(S8-5)` puts a resume whose **message text names a different unit** through the real writer and asserts the stored record holds no slug, no slice, and no trace of the misleading text — attribution cannot come from a payload that is not there. `(S8-3)`: an unattached resume is not folded into `unknown` |
| **RS6** — finished-vs-killed only where the referenced records support it | **MET** | `(S9-2)`: the statement differs between a referenced invocation with a priced `completed` finish and one with `async_launched` and no figure. Read from `COST_N_RESUMES_ON_PRICED`/`_ON_UNPRICED`, which come from that invocation's own records |
| **RS7** — a unit with no resumed run says nothing about them | **MET, by absence** | `(S9-1)`: the string `resum` appears nowhere in a resume-free sentence — no "0 resumed runs", no empty clause. `RV4`'s frozen blocks (`S3`'s three surfaces) still green, unmodified |
| **RS8** — an unattached resume is not dropped and errors nothing | **MET** | `(S8-2)` counts it; `(S9-7)` asserts it is counted **separately** and the unit's own clause still says 1, not 2 |
| **RS9** — the killed attempt is never given a figure | **MET, over keys** | `(S7-4)` asserts no resume record carries any token, duration or cost key — so a zero or a null-as-placeholder fails, where a rendering check would pass. `(S9-3)` asserts the clause says "unavailable and in no total" with no `pending`, no `to be determined`, no `0 tokens` |
| **RS10** — read without error in both directions, both programs or neither | **MET** | `(S6-5)`/`(S6-6)` and `(S8-6)` for the two directions; `(S6-8)`, `(S7-7)` and `(S8-7)` for parity — `(S8-7)` compares the **whole COUNT block**, so a divergence in any counter fails, not just the new ones |
| **RS11** — the join key is carried forward, never backfilled; resolution reader-side | **MET** | `(S6-3)` asserts every pre-existing line byte-identical over the **whole file** after an append; `(S6-4)` that none gained the key. `(S8-5)` that the record stores the raw identifier. Resolution lives in the reader by construction |

## Findings

**1. The G1-declared precondition is unmet. (CONCERNS — the maintainer's, not the builder's.)**

`(S7-8)` proves only that the matcher is **registered** in `hooks.json`. Liveness needs a plugin
reinstall and a restart, and `docs/loop/conventions.md` is explicit that a green harness never proves
a hook is live. No case here claims otherwise, and this verdict does not either.

**2. One existing case was changed, and it was tightened. (Recorded, not a concern.)**

`(S7-1)`. The old assertion demanded an identical coverage sentence; `RS1` permits exactly one
difference, and `S9` makes it live. The replacement is strictly stronger — prefix byte-identity, the
addition confined to the resume clause, and no figure or completeness word inside it — and it was
mutation-tested rather than assumed. Case total rose at every slice; nothing was weakened, skipped or
renumbered.

## What this pass cannot tell you

- **Whether resumes are actually being captured.** Finding 1. Registered, not observed live.
- **Whether a resumed run's cost can ever be known.** It cannot, by `RE4`. `agent_id` is a handle,
  never a figure, and no criterion here changes that.
- **How the arm behaves on `ubuntu-latest`.** Not pushed at the time of writing, so both jobs'
  colours on this work are unread.
- **Independence.** Same-session build and verify.
