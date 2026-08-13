# Log — cost-measurement-v0.2

## G0 — Spec
Source: `docs/loop/laravel-loop-cost-requirements.md` (human-authored), scoped by `loop-spec` to exactly the v0.2 row of its own sequencing table (R1.1-R1.4, R4.1). Five open questions raised and resolved as recommended (D1-D5): combined-token-only ledger acceptable; R4.1 ships on rationale alone; rework priced at whole-invocation granularity (not divided across refine passes); ship even with partial null-token coverage; `{{args}}` in command titles is not an ordering violation.
**Decision:** Approved as recommended (all 5 open questions).

## G1 — Slice
`loop-slice` cut 7 slices: S1/S2/S7 parallel at t0, then S3→S4→S5→S6 serial (shared file). Pinned a contract table (script name, env vars, `invocation_id` field, null-never-zero rule) so parallel builders couldn't diverge. Riskiest: S2 — the entire ledger's usefulness rests on the hook payload actually carrying the invocation prompt, unconfirmable by static inspection alone.
**Decision:** Approved — proceed to build.

## Build
7 slices built and merged in order: S1, S2, S7 (parallel) → S3 → S4 → S5 → S6.
- Multiple build worktrees branched from a stale point in git history (before this session's work existed) and needed `git merge main` before they could safely land — recurring pattern across both units built this session.
- S2 resolved its own early-exit rule empirically (inspected real session transcripts to confirm `tool_input.prompt` carries the envelope) rather than guessing or stalling.
- S3 found SubagentStop payloads carry no `tool_use_id`, sidestepping the one weaker piece of S2's evidence by simply never writing a line for that event type.
- Harness grew from 22 → 121 cases across the unit.

## G2 — Verify
`loop-verify` returned **PASS** — see `verify.md`. All 37 acceptance criteria proven, no concerns, no out-of-bounds touches.
**Decision:** Accepted (2026-08-13).

## Conventions / decisions carried forward
No corrections to `docs/loop/conventions.md`. No rejected approaches for `docs/loop/decisions.md` — every judgment call in this unit (S2's field-path resolution, S3's SubagentStop handling, S5's ambiguous-attribution rule) was accepted as proposed, not reversed.

## Follow-up (not yet scheduled, not part of this unit)
- DC1: watch the ledger across 5+ real `/loop` runs for believable numbers and the share of unpriced (null-token) records.
- v0.3 scope (R2 budgets, R5 reporting incl. `/cost`, R4.4) explicitly deferred per the source doc's own sequencing.
