# Log — ship-observe-automation

## G0 — Spec
`loop-spec` wrote `spec.md`. D1–D5 recorded: Ship scoped to laravel-loop's own release readiness only (guardrail harness, shellcheck, version consistency across 3 manifests) — explicitly not downstream-Laravel gates, not gate discovery. Observe = documented procedure + one thin command, no new script.
**Decision:** Approved as framed.

## G1 — Slice
`loop-slice` cut 7 slices: S1 (runner) → S2 (version gate) → S3 (timeouts) → S4 (release context) → S7 (close-out), with S5 (`/ship` surface) and S6 (Observe) running independently. Riskiest: S1 (fan-out to 5 other slices).
**Decision:** Approved — proceed to build.

## Build
All 7 slices built via `loop-build`, one per invocation, merged in dependency order:
- S6 (Observe) — merged first, independent of the Ship chain.
- S1 (runner) — merged; flagged a genuine spec tension (gate 3 hardcoded `not-run` in this slice vs. a Done-when case implying an end-to-end `go`), resolved by testing the verdict-aggregation function in isolation.
- S5 (`/ship` command) — merged, parallel to S2–S4.
- S2 (version gate) — merged; made gate 3 real, resolving S1's flagged tension (confirmed end-to-end `go` now reachable).
- S3 (timeouts) — merged; bash-only fallback for hosts without GNU `timeout`.
- S4 (release context) — merged; dirty-tree and unit-contract reporting, verdict unaffected.
- S7 (close-out) — merged; README and `loop-protocol` updated to match what shipped.

Note: builders for S1, S2, and S4 initially returned without committing their work in-worktree (validated but uncommitted); the conductor committed and merged each after re-verifying tests/shellcheck in place. S6, S5, S3, S7 committed their own work correctly.

Harness grew from 22 → 57 cases across the unit. Final state: 57/57 passed, shellcheck clean.

## G2 — Verify
`loop-verify` returned **CONCERNS** — see `verify.md`. All load-bearing acceptance criteria (D2's not-run-never-go guarantee, non-mutation, determinism, version-gate correctness) independently reproduced. Concerns are 3 test-coverage gaps on already-correct prose/doc content.
**Decision:** Accepted as-is (2026-08-13). The 3 gaps are filed as a follow-up, not built now.

## Follow-up (not yet scheduled)
- Add a harness case asserting Ship's own-repo-only disclaimer against `ship-check.sh`'s stdout, not just `commands/ship.md`'s prose.
- Add harness cases for Observe's O4 (attribution link), O5 (no credentials/telemetry), O6 (project-agnostic).
- Add a harness case checking `skills/loop-protocol/SKILL.md`'s `↺`/G3 wording, not just README's.

## Conventions / decisions carried forward
No corrections to `docs/loop/conventions.md`. No rejected approaches significant enough for `docs/loop/decisions.md` — S1's builder's resolution of the not-run/go tension is documented above and in `verify.md` rather than as a rejected-approach entry, since nothing was tried and discarded, only interpreted.
