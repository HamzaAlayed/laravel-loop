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
- **Corrected 2026-08-14 — superseded by E2:** closing the gap does *not* need a token figure
  from the harness; the harness already produces one and already delivers it. A controlled probe
  (`cost-ledger-blind-to-background-agents` spec.md **E2**) shows a backgrounded invocation's real
  token total arrives, exact, in the agent's own completion notification the moment it finishes.
  The gap is inside this plugin's own hook registration, not somewhere the harness has yet to
  build: no registered hook subscribes to the channel that notification arrives on (see this
  file's own OQ2 spike entry, below).

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

## OQ2 spike: can a hook reach the channel a backgrounded invocation's real token figure
## arrives on? (2026-08-14)

Tried: registered every hook event this Claude Code build (2.1.232) exposes except
`SubagentStop` (closed by E3, not retested) — `PreToolUse`/`PostToolUse` on `Agent|Task`,
`Notification`, `MessageDisplay`, `PostToolBatch`, `SubagentStart`, `TaskCompleted`,
`TaskCreated`, `Stop` — against a throwaway `CLAUDE_PROJECT_DIR`, then live-launched one
trivial `general-purpose` subagent in the foreground and a second, identical one with
`run_in_background: true`, and watched which registered hook fired what payload for each.

**Answer: 2 — no hook can reach it; only the main thread's own context sees it.** Both probes
reproduced E2 exactly (foreground finish payload carries `totalTokens`; background finish
payload is `async_launched` with none). The background task then completed for real, but
**no hook of any of the eight registered types fired a second time for it** — the sleep
between launch and completion shows nothing in the hook log at all. The figure instead
arrived as a `<task-notification>` block — `origin.kind:"task-notification"` — injected
straight into the session transcript as a queued synthetic user turn (`type:"attachment"`,
`attachment.type:"queued_command"`, `commandMode:"task-notification"`), containing
`<usage><subagent_tokens>7961</subagent_tokens>...</usage>`. This delivery path is structurally
separate from the `hook_event_name` dispatch pattern shared by every one of the binary's
literal hook events (confirmed by grepping the installed `claude` binary's own string table
for every `hook_event_name:"..."` and `notificationType:"..."` literal — the same evidentiary
method this script's own header already used for `tool_use_id`) — it is a queue operation on
the conversation itself, not an event on the hook bus, so there is no channel name a
`hooks.json` entry could ever name to subscribe to it.

Probe, reproducible by a second person: throwaway project dir, `.claude/settings.json`
registering the above events against a logging hook `script.sh EVENT_NAME` that appends
`{"probe_event_label":..., "payload":...}` for whatever it's handed; run
`claude -p` from inside that directory with `--allowedTools "Task,Bash(sleep*)"` and a prompt
instructing exactly two `Task` calls (one foreground, one `run_in_background: true`) on the
same trivial subagent prompt, followed by repeated `sleep 5` calls until new context proves
the background one finished. Inspect the probe log for anything carrying a token figure
between the launch and the "seen" reply (there is nothing), then grep the session's own
`~/.claude/projects/.../*.jsonl` transcript for `task-notification` to find where the figure
actually lands.

This forecloses building recovery as a hook. It does **not** foreclose recovery outright: the
figure is real, exact, and visible to the main thread that launched the invocation, so a
recovery mechanism would have to be the orchestrating agent itself reading the
`<task-notification>` block from its own context and writing (or asking to write) a ledger
line — a model-transcribed figure, not a host-observed one, exactly OQ2 answer 2's own
description. Whether that is acceptable in a ledger whose whole value is observed-not-reported
numbers is the human decision OQ5/the second G1 was already deferring this to, not a builder's
call, and no such mechanism is designed, prototyped, or landed here.
