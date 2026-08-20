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
