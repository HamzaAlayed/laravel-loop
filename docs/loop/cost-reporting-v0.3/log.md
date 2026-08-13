# Log — cost-reporting-v0.3

## G0 — Spec
Source: `docs/loop/laravel-loop-cost-requirements.md`'s v0.3 row (R5.1/R5.2, R2.1/R2.2, R4.4). `loop-spec` recommended re-cutting the row (ship R5+R4.4 now, defer R2/budgets until measurement coverage improves) because the source doc's own "two weeks of baseline" gate binds R2 alone, not R5 or R4.4. **The human explicitly overruled this recommendation** and chose to ship all three components now (G0-D1), with `unset = disabled` enforced as testable behavior rather than documentation. G0-D2: per-phase expectations (R2.2) ship as a documented mechanism with no numbers, diverging from the source doc's literal "documented defaults" wording.
**Decision:** Approved as written — all three components, both G0-D1 and G0-D2 as recorded.

## G1 — Slice
`loop-slice` cut 8 slices: S1 (independent) and S2 (the seam) parallel at t0; S2→S3→S4 a real dependency chain (R2 needs R5's arithmetic); S5/S6 parallel after S4; S7 after S6; S8 last. Riskiest: S2 — "its failure mode is invisible to every test that could be written for it" (a report that reads as complete when it isn't).
**Decision:** Approved — proceed to build.

## Build
All 8 slices built and merged in order: S1+S2 (parallel) → S3 → S4 → S5+S6 (parallel) → S7 → S8.
- Docs-not-committed gap recurred (same as both prior units this session) — fixed immediately after S1 merged.
- S7 correctly retired a stale test case S6 had left behind (a commit-specific snapshot check that was expected to become obsolete once S7 legitimately edited the same file).
- S3's builder flagged an intermittent flake in S1's full-suite-guard tests (~1/15 runs) — reproduced independently, not a regression, filed as follow-up rather than chased.
- After S8, a pre-existing bug in `scripts/ship-check.sh` (from the *ship-observe-automation* unit) surfaced: gate 2 ran bare `shellcheck` instead of `-S warning`, inconsistent with CI. Fixed directly as a small out-of-band correction (not part of this unit's scope) since it blocked getting a clean `/ship` verdict.
- Harness grew from 121 to 329 cases across the unit.

## G2 — Verify
**First pass: FAIL.** `check-budget-gate.sh`'s disable messages leaked numeric examples adjacent to the budget env var names, violating G0-D1 — the one decision this unit exists to get right, since the human explicitly chose it against `loop-spec`'s recommendation. Routed back to `loop-build` as a single re-brief (not re-litigated, not argued down).
**Second pass: PASS.** Fix confirmed independently — wording corrected, regression-guard case added, no scope creep, no other criterion regressed.
**Decision:** Accepted (2026-08-13).

## Conventions / decisions carried forward
No corrections to `docs/loop/conventions.md`. Nothing added to `docs/loop/decisions.md` — the G0-D1 violation was a build defect against an already-made decision, not a new approach tried and rejected.

## Follow-up (not yet scheduled, not part of this unit)
- The intermittent FS1 flake in `warn-full-suite.sh`'s test suite (~1/15 runs).
- DC2/DC3 (this unit): watch `/cost` and the budget gate against a real `/loop` run — specifically, does a synchronous run price its `loop-build` invocations, which determines how much of a threshold's job a threshold can do.
- v0.2's DC1 remains open, unaffected by this unit.
- The stale header comment in `check-budget-gate.sh` about read-order (cosmetic, non-blocking).
