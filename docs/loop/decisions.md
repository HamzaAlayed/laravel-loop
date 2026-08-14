# Decisions

Approaches tried and rejected, with why. This is what stops a future session from re-proposing a design that already failed here.

Add one entry per rejected approach: what was tried, why it was rejected, and what to do instead.

<!-- Example:
## Queueing analysis jobs per-row
Tried: dispatching one job per screener row for parallelism.
Rejected: queue overhead dominated at typical batch sizes (10-50 rows); serial processing in one job was faster and simpler.
Instead: batch rows into a single job, chunked at 50.
-->

## Pricing a unit of work from subagent token totals (2026-08-14)

Tried: recording `totalTokens` per `Agent|Task` invocation and totalling it per unit, as the
basis for `/cost` (v0.2.0) and for the budget gate's threshold comparison (v0.3.0).

Rejected as a **spend control**: only invocations run in the **foreground** return a payload
carrying tokens. Measured over 79 real terminal records in one working session — 3 priced,
**4%**. By terminal status: `completed` 3/3 priced, `async_launched` 0/35, `subagent_stop`
0/41. Because `/loop` requires backgrounded parallel lanes (2–3 in flight), `loop-build` is
structurally 100% unpriced (0 of 56 terminal records) — and it is the largest spender. A
threshold compared against 4% of spend is not a control; it is a number that cannot fire on
the phase it exists to bound.

The measurement itself is still worth keeping: the ledger is honest about what it cannot see
(v0.2.0's L3 — `null` means unavailable, never a measured zero; v0.3.0's CV1 — coverage
stated before any total), so it under-reports visibly rather than misleading. Keep it as an
instrument; do not build a control on top of it at this coverage.

Instead:
- **Do not set `LARAVEL_LOOP_BUDGET_HARD` expecting it to bound a `/loop` run.** It can only
  see foreground spend. Both variables ship unset for exactly this reason (G0-D1); this is the
  evidence behind that decision, which `loop-spec` recommended and was overruled on.
- **Do not derive a rework share from token totals** while build is unpriced — v0.2.0's D3
  already prices rework at whole-invocation granularity, and 0% of those invocations carry
  tokens. Rework as an **invocation count** is computable and is what `/cost` reports.
- **Do not "fix" this by summing elapsed time as a proxy for cost.** v0.3.0's CO11 already
  refuses it: overlapping backgrounded invocations make an elapsed-time total meaningless,
  and a fabricated denominator is worse than a stated gap.
- Closing the gap needs a **token figure for backgrounded invocations** from the harness
  itself. That is upstream of this plugin, not a slice inside it — see
  `docs/loop/cost-ledger-blind-to-background-agents/intent.md`.

## Verifying the plugin's hooks by running the repository's test harness (2026-08-14)

Tried: treating a green harness (334 cases, including ledger, gate, and rework cases) as
evidence that the hooks work.

Rejected: the harness invokes each script **directly**, piping a synthetic payload to stdin.
It never exercises the Claude Code hook path, so it cannot detect that a hook is not
registered in the loaded plugin. Three hooks added across v0.2.0–v0.4.0 passed every test
while having never fired once in a live session — the installed copy was a frozen v0.1.0
snapshot with only the two original registrations.

Instead: a hook is proven live by the **state it writes**, not by its tests passing. Check for
the artifact (`.claude/loop-cost.jsonl` and friends) after a real run. Treat "tests green" and
"hook active" as independent claims, and note that installing from a marketplace snapshots the
plugin — a repo-side `hooks.json` change requires reinstalling *and* restarting before it is
in the loop.
