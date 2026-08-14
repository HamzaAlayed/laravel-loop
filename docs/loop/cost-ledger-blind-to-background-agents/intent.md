# Intent — cost-ledger-blind-to-background-agents

Captured: 2026-08-14T14:09:34Z

## What was observed

Two separate findings, one causing the other to have gone unnoticed.

**1. The cost ledger has never run.** `.claude/loop-cost.jsonl` does not exist, after a full
day of loop work across three units. `record-cost-event.sh` has never fired in a live
session. The installed plugin at `~/.claude/plugins/cache/laravel-loop/laravel-loop/0.1.0/`
is a frozen **v0.1.0** snapshot taken 2026-08-12 22:19, and its `hooks/hooks.json` registers
only `block-untested-commit.sh` and `enforce-refine-cap.sh`. Every hook added in v0.2.0
through v0.4.0 — `record-cost-event.sh`, `warn-full-suite.sh`, `check-budget-gate.sh` — is
absent from the loaded copy. Corroborating: `.claude/loop-refine-passes.tsv` (written by a
v0.1.0 hook) carries today's writes, while `loop-cost.jsonl` was never created.

**2. Background invocations carry no token figure at all.** Measured against Laravel Guild's
independent feed (`.claude/agents-board.jsonl`), which *was* registered and did record this
session: 79 terminal records, of which **3 carry a token figure — 4% priced.**

| Agent | Terminal records | Priced | Observable tokens |
|---|---|---|---|
| `loop-build` | 56 | **0** | 0 |
| `loop-spec` | 9 | 3 | 265,540 |
| `loop-verify` | 8 | **0** | 0 |
| `loop-slice` | 6 | **0** | 0 |

The mechanism is exact, not probabilistic. Grouped by terminal status:

| Status | Records | Priced |
|---|---|---|
| `completed` | 3 | **3** |
| `async_launched` | 35 | 0 |
| `subagent_stop` | 41 | 0 |

The three priced records are precisely the three invocations run in the **foreground**
(`run_in_background: false`) — the `loop-spec` calls for `ship-observe-automation`,
`cost-measurement-v0.2`, and `cost-reporting-v0.3`, at 60,787 / 99,124 / 105,629 tokens.
Every backgrounded invocation produced `async_launched` with null tokens, followed later by
`subagent_stop`, also null.

This answers the single open question `cost-reporting-v0.3`'s spec left unresolved
("does a synchronous run price its `loop-build` invocations?") and shows the question was
mis-framed: pricing tracks **each invocation's launch mode**, not the run's. Because `/loop`'s
design requires backgrounded parallel lanes (2–3 in flight), `loop-build` is structurally
100% unpriced — 28 `async_launched` records, 0 priced — and it is the phase the source
requirements document names as the largest spender.

## Where it surfaced

Local development, this repository, while attempting to close DC1 (v0.2.0), DC2 and DC3
(v0.3.0) — the post-merge conditions that ask whether the ledger's numbers are believable
against real runs. Surfaced by inspecting `.claude/` for the ledger, then reading Guild's
feed once the ledger was found absent. Not a production fault; a fault in the
instrumentation built to observe production-shaped questions.

## When

2026-08-14T14:09:34Z. The ledger's absence dates from `cost-measurement-v0.2`'s S2 merge
(2026-08-13, commit `a7fbfa2`) — the hook existed in the repo from that point and was never
loaded by a running session. The coverage finding spans this session's 79 terminal records.

## What was already tried

- Checked for `.claude/loop-cost.jsonl` — absent.
- Confirmed other hook state *is* being written (`loop-refine-passes.tsv`, today) — so hooks
  fire in general; these specific ones do not.
- Located the installed plugin and read its `hooks/hooks.json` — v0.1.0, two hooks only.
- Measured real coverage from Guild's independent feed: 3/79 terminal records priced.
- Correlated token presence against terminal status and against known launch mode — exact
  match, `completed` only.
- Confirmed the scripts themselves are not at fault: all 334 harness cases pass against them
  directly, including the ledger, gate, and rework cases. The gap is registration, not code.
- **Not tried:** updating the installed plugin to v0.4.0 and restarting Claude Code, which is
  the step that would actually put the hook in the loop. Not tried because a restart is the
  human's action, not this session's.

## Suspected unit or commit

Two references, both followable:

- `docs/loop/cost-measurement-v0.2/` — built the ledger and its `Agent|Task` registrations;
  its DC1 remains open and this is why.
- `docs/loop/cost-reporting-v0.3/` — built `/cost` and the budget gate on top of it, and
  recorded the coverage risk as G0-D1's accepted residual. Its own `verify.md` notes the gate
  was shipped against `loop-spec`'s recommendation to defer.

Not suspected, and stated so rather than left implied: no script defect. The registration is
correct in the repository's `hooks/hooks.json` at v0.4.0; only the loaded snapshot is stale.

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance
criteria, no non-goals, and no slices**; nothing builds from it directly.
