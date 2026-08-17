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

## Second G1: land model-transcribed recovery, hold automatic wiring (2026-08-17)

Decided: approve S7-S10 of the RC recovery group — teaching the reader a recovered figure
exists (S7), printing both figures when an observed and a transcribed one disagree (S8), the
transcription entry point `scripts/record-recovered-cost.sh` (S9), and documenting all of it in
README and here (S10). **Hold S11** — instructing the orchestrator to run that CLI
automatically after every backgrounded lane completes — as its own decision, not approved in
this pass.

This forecloses, for this pass:
- **Hook-based recovery** — already closed by S6's OQ2 spike above: no registered hook event can
  reach the channel a backgrounded invocation's real token figure arrives on; only the main
  thread's own context ever sees it.
- **Transcript scraping** — reading `~/.claude/projects/.../*.jsonl` after the fact to recover a
  figure nobody deliberately transcribed. Rejected because it would give the ledger a second,
  undeclared input path outside RC7's observe-only contract, turning a deliberate, typed act into
  a silent background scan.
- **Any fuzzy selector** for `--invocation-id` — nearest-by-time, most-recently-launched, or any
  other guess at which invocation a figure belongs to. RC1's exactly-once guarantee and RC4's
  refusal to fabricate both depend on the id being named exactly, by whoever read it off the
  `<task-notification>` block, never inferred.

Instead: a human or an orchestrating agent transcribes a figure by hand, one invocation at a
time, or does not — RC6 makes both outcomes equally correct, and a run with zero transcriptions
looks exactly as it always has. S11's automatic wiring stays a live, separate question for a
future gate.

## G0: narrow the mode check, keep ship-check's gate set at three (2026-08-17)

Decided: fix the twelve-run CI failure by **narrowing** the executable-bit check rather than by
satisfying it. A file matched by `scripts/*.sh` or `tests/*.sh` is a library if one of its first
20 lines is exactly `# laravel-loop:sourced-library`; libraries are committed `100644`, programs
`100755`. Parity between the two check sets is guaranteed by both calling one shared program,
`scripts/check-script-modes.sh`, and asserted by harness cases that execute `ci.yml`'s own
extracted `run:` body. `scripts/ship-check.sh` is untouched.

This forecloses:
- **`chmod +x` on a sourced library** — the one-line fix. Rejected because it makes the
  repository assert that a file which must never be run directly is runnable, and leaves the rule
  unstated, so the next library added is classified by imitation. A fast close bought with
  folklore.
- **A fourth `ship-check` gate for the mode rule** — rejected: the declared count would grow
  every time a CI step is added, and the header's "exactly three, hard-coded" claim, README, and
  `ship-observe-automation`'s S1/S6 would all need restating. The mode rule reaches the G3 verdict
  anyway, indirectly, through gate 1's harness — the same file CI runs.
- **Making `ship-check` merely state its blind spot** — rejected as a documentation fix to
  something six releases had already read past.
- **Keeping the rule inline in `ci.yml`** with the harness extracting and executing it, adding no
  twelfth script — rejected because two copies of a rule can only *promise* agreement, while one
  shared program makes it structural. This repository's own precedent, stated in
  `cost-ledger-lib.sh`'s header for the same reason.
- **Establishing the earliest (v0.2.0) run's cause** — scoped out, not attempted. Its surviving
  log yields no filename and it predates the file that failed every later run. Recorded as
  `unknown`, never inferred from a later run's cause.

Instead: one rule, written once, read by both sides, with a twelfth file under `scripts/`
accepted as its price. Note that `ship-observe-automation` had *declined* an executable-bit gate
on the grounds that CI already covered it — the premise this unit's twelve red runs falsified,
which is the only reason the question was reopened.

## Second G1: close the eviction convergence gap, fix case B's fixture, add a macOS job (2026-08-17)

Decided after four read-only spikes, one recorded decision per case as A3 requires:

- **Case A** — close the convergence gap in `scripts/record-cost-event.sh`'s `append_and_evict()`.
  The spike **refuted** a platform cause (20/20 trials settled at cap across Ubuntu 22.04/24.04,
  bash 5.1/5.2, and 10 vs 2 vCPUs, matching macOS), and established by *reading* that a lock-loser
  never retries while the winner gives up after five attempts — so the ledger's declared cap has no
  convergence guarantee under enough concurrent append pressure. The test caught a real defect;
  CI's contention merely exposed it once.
- **Case B** — the case is wrong, not the code. Fix the fixture to force shellcheck's absence
  portably (discover where it actually resolves and exclude that directory) instead of allow-listing
  `/usr/bin:/bin:/usr/sbin:/sbin`, which is precisely where apt installs it. `ship-check.sh` unchanged.
- **The contract** — two-directional, enforced by adding `macos-latest` (arm64) as a second job.
  `Bash 3.2.57(1)-release` and arm64 both exact-match the maintainer's host, per an
  `actions/runner-images` manifest read at a pinned commit.

This forecloses:
- **Loosening or removing case A's assertion.** It guards a real, non-platform-specific property —
  the ledger stays at or under its declared cap — so weakening it discards the only warning that the
  property can be violated at all.
- **Changing `ship-check.sh` for case B.** No observation shows a defect in `gate2_shellcheck`: with
  shellcheck genuinely removed it reads `not-run` and the verdict holds, corroborated on the *real*
  runner by the sibling gate-1 case passing on the same run that failed case B.
- **Treating case B's red as evidence against the not-run/hold safety property.** The property was
  checked separately from the case precisely to prevent that conflation, and it holds on Linux.
- **Reading S4's citation as coverage.** A manifest documents what an image ships, not that the suite
  passes there. Only a real run is evidence, and the images roll, so the OS point-version is a moving
  target.
- **Establishing case A's failure rate before fixing it** — considered, not taken. The defect is
  established by reading; a rate would say how often it bites, not whether the code is wrong.
- **Deferring the platform job until after the two fixes** — considered, not taken. The contract was
  approved at G0 contingent on feasibility, and feasibility cleared.

Instead: two fixes in two different artifacts, one per case, plus a second job whose citation's own
limit is recorded alongside it.
