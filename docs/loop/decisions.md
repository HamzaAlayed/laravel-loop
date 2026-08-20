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

## G2 follow-up: break the eviction loop on a failed `mv` (2026-08-18)

Decided after G2 returned **CONCERNS** on `harness-fails-only-on-linux`: S5's convergence fix
replaced a fixed 5-attempt bound with `while :;` and left `mv -f ... || rm -f "$tmp"` without a
break, so a persistently failing `mv` loops forever. Reproduced twice independently (209 iterations
under `chflags uchg`, 501 in a separate re-check) and confirmed **new** — the pre-fix bounded loop
always terminated.

The decision is the one-line form: `mv -f "$tmp" "$OUT" 2>/dev/null || { rm -f "$tmp"; break; }`.
This is not a new design; it makes the fourth I/O failure behave like its three siblings, which the
loop's own comment already prescribes — *"every other break below is a real I/O condition, never an
arbitrary attempt cap."*

This forecloses:
- **Re-adding an attempt bound or iteration counter** — that is the arbitrary cap S5 removed for a
  reason, and re-adding it would restore the convergence gap the whole unit exists to close.
- **A no-progress guard** (exit when a trim fails to reduce the count) — considered and not taken.
  It catches the same path plus hypothetical future ones, at the cost of more state and a subtler
  invariant to test. Available later if a second non-progressing path ever appears.
- **Both guards together** — rejected as more surface for a test that cannot fail, for a defect
  with one known route.
- **Fixing the stale lock in the same slice** — rejected. It is confirmed pre-existing rather than
  introduced, a prior decision deliberately scoped it out, and riding it along here would change a
  recorded decision without its own gate. The verifier's point that the two failure paths *compound*
  stands as a named, open gap.

Instead: one line, one new case with a portable failing-`mv` trigger, falsified against today's HEAD
so it cannot be a test that never could have failed — which is exactly how the regression got
through a 426-case green suite in the first place.

## G1: recovered-figure is fixed reader-side, and RD8 is read by purpose (2026-08-18)

Decided: cut the fix reader-side — six slices in `cost-ledger-lib.sh` and `cost-report.sh`, with
`record-recovered-cost.sh` and the record shape untouched. G0's OQ4 forces it: the 21 recovered
records already in the ledger must benefit without being re-typed, and only a reader fix delivers
that.

**RD3 versus RD8 collide on one fixture class** — a recovery-free ledger holding a priced
invocation with no `slice`. RD3 wants the count *and* the tokens in the ranking's own section; RD8
wants recovery-free output byte-identical. **Read as: RD8's purpose is RC6** — that the
transcription *feature* leaves no trace on a run that used none — not a freeze on the report.
Making the report's honesty conditional on a `recovered` record being present is precisely the
coupling this unit removes.

This forecloses:
- **A writer-side fix** — adding `slice` and `model` to the recovered record. It would overturn
  `record-recovered-cost.sh`'s documented pin ("nothing about phase, status, model, duration, or
  slice is ever copied forward… No other field, ever"), leave two record shapes in one ledger, and
  strand the 21 existing records unless they were re-typed.
- **A split writer/reader fix** — considered as a real third option at G0 and not taken, for the
  same reason: OQ4's answer makes the reader path the only one that helps what is already recorded.
- **RD8's letter over its purpose** — gating the new line on `COST_N_PRICED_TRANSCRIBED > 0`. It
  freezes recovery-free output exactly, at the cost of making honesty depend on a record type.
  Offered at the gate and declined.
- **Fixing the resumed-invocation gap here** — out by G0's OQ5; it is a capture gap needing the
  hook matcher RC7 forbids.
- **Deciding S11** — automatic transcription wiring stays held. Automating over a record shape is
  a different question from what the reader does with the shape it has.

Instead: six sequential reader-side slices, one held behind OQ3 (whether a restored dimension needs
its own per-row transcribed marking). Parser parity between the jq and python programs gets its
own slice and lands early — the two have never been tested against each other, in the file this
unit calls the most dangerous in the repository.

## Second G1: the ledger promises convergence, and a later invocation is obliged to trim (2026-08-18)

Decided after three read-only spikes, with `OQ1` held from G0 precisely so this could be decided on
evidence rather than instinct.

**The cap property is `E1`'s property 3 — eventual convergence — stated explicitly**, plus
obligation **class 3**: a later invocation checks and trims on arrival unconditionally, regardless
of what its own append needs. The failing case's assertion is replaced with S2's deterministic
lock-hold construction.

**Why, in one line each:**
- `record-cost-event.sh`'s header already documented the accepted cost as *"a ledger that sits
  slightly over cap for a moment"* — which **is** property 3. The test asserted property 2. The case
  disagreed with the documented design, not with the code, and nobody had asked which of the three
  readings of "cap" was meant.
- S1 established property 2 is **not achievable** alongside `L7`: no invocation can tell from inside
  its own event whether it is a run's last append — a run is only over in hindsight — so any
  unconditional guarantee needs the returning invocation to wait on the lock, which is the literal
  thing `L7` rules out.
- Class 3 is the only obligation class S1 rated **fully `L7`-compatible at zero cost to any
  appending invocation**, and it tightens convergence rather than merely redefining it.
- S2 established a **local red is constructible** (5/5 against HEAD, and 5/5 against pre-S5 — so the
  property never held and this was never S5's regression), which means the replacement assertion is
  reproducible where the current one is not (case (f)'s own scenario: 0/N across 8 arms).

This forecloses:
- **Property 2 / a hard bound at rest.** The maintainer's own recorded instinct, tested by the spike
  and declined on its evidence. It needs obligation class 1 or 2, both of which **give up `L7`**:
  unbounded waiting on the appending path against a measured 148 ms baseline, and class 2 cascades
  across concurrently spawned invocations. `L7`'s header rejects exactly this trade.
- **Class 1** (the appender guarantees before returning) and **class 2** (a lock-loser retries) — the
  two that could deliver property 2, both giving up `L7`.
- **Class 4** (a sweep at the run's end) and **class 5** (a detached continuation) — property 3 at
  best, and each carries an unestablished reliability question or a per-append process spawn.
- **Leaving the assertion as it stands.** It asserts a property that is not achievable and that the
  file's own header contradicts.
- **Deleting or weakening the case without replacing it.** S2's construction means the guard can be
  kept and made reproducible, so losing it is not the price of correctness.
- **Amending `L7` itself.** If the never-block guarantee is the thing that should be questioned, that
  is a spec-level question deserving its own unit at G0 — not a side effect of this decision.

Instead: say which property the cap actually promises, oblige a later invocation to trim so
convergence is not merely contingent on one happening to run, and replace an assertion nothing could
reproduce locally with one that goes red 5/5 on demand.

## Build-out of that decision: where the arrival trim was placed, and what the placement foreclosed (2026-08-18)

A follow-up to the entry above, not a revision of it. The gate decided the **property** (`E1`'s
property 3) and the **obligation class** (class 3). Everything below is a placement choice made at
G1 and carried out in S5, recorded because a future reader would otherwise have to re-derive it —
or re-propose something already declined.

**What was chosen.** Exactly one trim loop exists in `record-cost-event.sh`: the existing loop,
factored out of `append_and_evict()` into `converge_ledger()` and called by both paths. The
obligation sits on the two arrival paths that end **without appending** — the `Bash` rework branch
when it emits no `cap_trip`, and the deduped duplicate-finish discard — each via `trim_on_arrival()`,
which makes **one** `mkdir` attempt on the evict lock and returns 0 if it loses. No invocation ever
performs both an arrival trim and an append-path trim; that is unfalsifiable by a test (a double
trim and a single trim leave the same file), so it is written to be read, and was read at merge.

**What that forecloses:**
- **Arrival-trimming on every invocation, appenders included.** Rejected: it puts new work on an
  appending invocation's own path, which is the single property class 3 was chosen for avoiding. It
  would also make S6's measurement meaningless as a check on the decision.
- **A second copy of the trim loop for the arrival path.** Rejected: two copies of one rule can only
  *promise* agreement, while one shared program makes it structural. This repository's own precedent,
  twice — `cost-ledger-lib.sh`'s two parser programs (whose drift is exactly what
  `recovered-figure-drops-slice-and-model` is fixing) and `check-script-modes.sh`'s G0 entry above.
- **Extending the obligation to `scripts/record-recovered-cost.sh`.** Rejected: it is a deliberate,
  human-typed CLI with no contention, and its independent `append_and_evict` copy is documented as
  deliberate. Widening the diff there buys no convergence.
- **Obliging the two unregistered early exits** — `SubagentStop` and the unmatched-event `*)`.
  Rejected: neither is registered in `hooks/hooks.json`, so a filesystem read there is unreachable in
  practice and only widens the diff.
- **S2's *timed* lock release in the replaced case.** Rejected in favour of a synchronous release
  (hold the lock, run the real finish hook, assert over cap, `rmdir`, deliver one arrival, assert
  converged) on S2's own evidence: its 0/5 control at `HOLD=0.02s` shows a hold shorter than `L7`'s
  poll budget flips the arm's colour, so a timed hold on a loaded runner could release early and make
  the case green for the wrong reason. The replaced case now depends on no timing beyond `L7`'s own
  bounded poll.
- **Keeping the 20000-line raw-writer arm as a case.** Dropped with its cover named rather than
  assumed: case (a) (80 sequential events, cap 50, newest-in-order) and case (b) (60 concurrent real
  hook invocations settle at or under cap, never empty, every line parseable) still guard the
  sustained-pressure dimension it stood for. Neither was modified.
- **An attempt bound, an iteration counter, or a no-progress guard.** Already foreclosed by the
  `G2 follow-up: break the eviction loop on a failed mv` entry above; restated here because the
  arrival path is a fresh place to re-propose one. The loop keeps its `while :;` shape and its I/O
  breaks, including S9's `mv` break.

**What it cost, as a number** (`measure-e8-after.md`, n=20 per arm per version, interleaved
before/after on one host, sha `13d3407`, pre-change script `d883886`):
- The **appending** path did not move: arm (a) -0.5 ms mean / +0.9 ms median, arm (b) -2.6 ms mean /
  +4.6 ms median, both versions' min-max ranges overlapping.
- The **newly obliged arrival** pays **+16.1 ms mean / +15.7 ms median** when the ledger is over cap
  and **+6.7 ms mean / +7.1 ms median** when it is not; the duplicate-finish arrival pays +21.3 /
  +21.7 and +9.2 / +6.2 respectively. In both over-cap arms the pre-change script left the ledger at
  5000 lines and the post-change one left it at 15.
- Recorded with it: the absolute figures for the appending arms sit **below**
  `spike-oq2-bound-at-rest.md` §4's observed min for the same arms, so the cross-document spread
  check is inconclusive and the same-driver control stands in its place. That substitution is stated
  in `measure-e8-after.md` §4 rather than smoothed over.

**`E3` is met, and here is how.** S5 reproduced its own red before green: the replaced case's
construction, extracted standalone, is red 5/5 against `git show d883886:scripts/record-cost-event.sh`
(`yes no` — the hole constructed, no convergence) and green 5/5 against the changed script
(`yes yes`), host `Darwin 25.6.0` arm64, bash 3.2.57. S2's independent 5/5 against HEAD and 5/5
against pre-S5 remains the prior falsification of the hole itself — the property never held, so this
was never S5-the-earlier-slice's regression.

**`E2` is outstanding, and it is the human's.** No lane pushed, dispatched, re-ran, cancelled or
tagged anything. A real pushed run on both guarding platforms is the only evidence about the guarding
checks, and merging this group did not produce it. When it happens, **one green run is one sample** —
not a rate, and not a claim that the cap now holds on CI.

**`OQ4`, the stale evict lock:** still out of scope, still compounds with this mechanism, still needs
its own intent. No lane tripped over it, and no position on it is recorded here.

## G1 + build-out: a recovered figure's other dimensions are restored reader-side (2026-08-18)

`recovered-figure-drops-slice-and-model`, decided at G1 and recorded here after the slices landed.

**The answer is reader-side.** A `recovered` record keeps the shape it already has — `ts`, `event`,
`invocation_id`, `slug`, `total_tokens`, `token_source` — and every other dimension a report shows
for that invocation (its phase, its model, its slice) is read from the invocation's **own
`start`/`finish` records**, which the hook already wrote. Nothing new is written; the readers stop
discarding what is already on disk.

**Why, and the number that decided it:** **21 recovered records already exist** in this repository's
own ledger. A writer-side answer — adding fields to the record shape — helps only records written
after it ships and would strand all 21 unless a human re-typed them. A split writer/reader fix was
considered as a real third option at G0 and declined for the same reason. The reader is where the
figures already are.

**This pass forecloses:**
- **A writer-side field** on the `recovered` record. Pinned shape, documented twice
  (`record-recovered-cost.sh:47-53`, `cost-ledger-lib.sh:131-137`); only a human may overturn it.
- **A fuzzy selector** on `record-recovered-cost.sh` (no slug, slice, agent or recency matching) —
  one explicit `invocation_id`, typed by a human, stays the only way in.
- **Hook wiring / automatic transcription** (`S11`). Still held: automating over a record shape is a
  different question from what the reader does with the shape it has.
- **Transcript scraping** as a recovery path. Its own intent exists; it is not decided here.
- **Hand-editing `.claude/loop-cost.jsonl`.** No slice did, and no slice may.
- **Any threshold.** The 30 % concentration figure is neither raised, lowered, nor made
  configurable, and no coverage floor, budget or per-phase value ships set, commented out, or
  suggested.
- **`OQ5`'s resumed-invocation capture gap** — out at G0: it needs a hook matcher `RC7` forbids.
- **`RD8`'s letter over its purpose.** `RD8` is read as `RC6` — the transcription feature leaves no
  trace on a run that used none — not as a freeze on the report. So the unattributed count and its
  token total are stated for a recovery-free ledger too, with the pre-existing Flags sentence kept
  byte-identical, and `RD8` is asserted on a recovery-free fixture whose priced invocations all carry
  a slice. If the letter is preferred, the alternative was to gate the new line on
  `COST_N_PRICED_TRANSCRIBED > 0` — weaker, because it makes the report's honesty depend on a record
  type. Offered at the gate and declined.
- **`OQ3`, per-row transcribed marking**, stays uncut behind the human's answer at G1 — `S7` was
  never cut, and this entry records no position on it.

**A G1 defect this pass hit, recorded rather than smoothed over.** `S1` was sequenced before `S5`,
and four of `S1`'s cases (`S1-2`, `S1-3`, `S1-6`, `S1-7`) encoded the pre-`S5` state as their
expected value. `(S1-3)` forbade the string `concentration threshold` on a mixed fixture that `S5`'s
own *Done when* requires the 83 % concentration flag to fire on — two briefs from one gate,
contradicting each other on one fixture. The unit's pinned contracts say no lane edits an existing
case and that a lane which believes a pin is wrong returns `needs-decision`, so the `S5` lane stopped
and the human ruled: **re-point the four cases inside `S5`** rather than cut a migration slice. The
two fixtures drop the `slice` label from their transcribed invocations, which moves each case to a
population that is still genuinely incomplete after `S5`, leaving all four assertions byte-identical
and still able to go red; the now-complete mixed shape is asserted in `S5`'s own section instead.
Each fixture comment says it is a re-point and why. The lesson for the next cut: when one slice's
guards assert the absence of a symptom a later slice is required to produce, the cut owes a migration
step, not a pin forbidding one.

## Backlog gate: one queue, four drops, and six questions closed (2026-08-19)

Taken in one sitting after a full inventory of open items. Twelve decisions, recorded together
because several only make sense against each other. Nothing here is a slice; this is the frame the
next several units are cut inside.

### The frame

- **One merged, evidence-ordered queue. Both sequencing tables are retired.**
  `laravel-loop-cost-requirements.md` §9 and `laravel-loop-agentic-levels-requirements.md` §8 no
  longer schedule anything. The requirements themselves survive as a **backlog**, and each item
  enters `G0` on its own merits. Reason: the cost doc's target band (v0.2 → v0.4) is spent with its
  v0.4 row unshipped, the agentic doc was already a release behind its own table at 0 of 12 built,
  and the last four units all came from `/observe` intents rather than from either document. Version
  numbers should stop implying a plan nobody is following.
- **The planning checkers come before the eval harness**, inverting the agentic doc's stated order.
  `spec-check.sh` and `slice-check.sh` first; the eval harness then scores **against them** instead
  of re-implementing the same G0/G1 rules a second time. Reason: two implementations of one rule can
  only promise agreement — the failure `cost-ledger-lib.sh` exists to prevent, and the one this
  repository has already been bitten by in `_cost_scan_*` vs `_cost_slice_*`. The checkers also
  deliver value alone if the harness slips.
- **`spec-check.sh` is structural only — no quality judgement.** It checks presence and shape:
  acceptance criteria exist, non-goals are present, each criterion names what would check it, open
  questions are marked. No vague-adjective greps, no minimum counts, no taste encoded as a rule. It
  stays `L0`: no model call, deterministic, and nothing gameable that was not already required.
  Its own open question — whether a checker can be strict without being gameable — is answered by
  keeping it structural rather than by tuning heuristics.

### Four things dropped, not deferred

- **Routing to a cheaper model (cost `R3.1`/`R3.2`).** Dropped. Its own safety detector is rework
  rate, and this file already establishes that the rework token share is not derivable while
  `loop-build` is structurally unpriced. Shipping the largest quality-affecting change in the plan
  with its detector provably blind is the exact trade the cost doc itself forbids: *"never silently
  switch to a cheaper model … that trades a visible cost for an invisible quality loss."* Revisit
  only if background pricing coverage rises materially.
- **Autonomous triggering (agentic `R4.2`).** Cancelled, taking the branch its own `R4.3` offers
  rather than carrying it indefinitely as "later". Coverage is a small fraction by hook and only
  reaches complete where a human types figures in by hand. `R4.1` — persistent, session-independent
  state — survives: state without triggering is useful and safe.
- **Artifact-size reporting (cost `R6`'s third criterion).** Dropped. A byte count for a handful of
  markdown files that nobody would act on, at the price of a second writer in the close step — the
  most collision-prone path in the repo — and a new figure in `cost-ledger-lib.sh`. `R6`'s
  stale-worktree half stays in the backlog.
- **Per-pass rework granularity (cost `R1.3`).** Dropped as satisfied by substitution.
  Whole-invocation attribution is deliberate, documented in `README.md`, and *asserted* by the
  harness ("no per-pass token figure anywhere"). Reopening it needs a token channel the `OQ2` spike
  established does not exist.

### Six questions closed

- **`OQ3` (per-row transcribed marking) — once per report suffices. `S7` is dropped, and
  `recovered-figure-drops-slice-and-model` is closed complete.** `RC2`'s "never indistinguishable"
  is satisfied by the coverage sentence; `S7` would have grown `SLICEROW` from 5 to 7 columns in both
  parser programs, required both consumers' positional reads to change in the same commit or corrupt
  the gate's rework share, and reopened the most dangerous file in the repository — for precision only
  a mixed unit can use, and no mixed unit exists.
- **`S11` (automatic transcription wiring) — cancelled.** Automating over a record shape is a
  different question from what the reader does with the shape it has, and the deliberate human-typed
  CLI is part of what keeps a transcribed figure honestly labelled: automation removes the person who
  currently vouches for each figure. It stops being a coupling named in two units' records.
- **Transcript scraping — declined permanently.** `docs/loop/transcript-scraping-as-a-recovery-path/`
  stays as a record of the question, marked declined. A plugin reading files outside the repository it
  is installed in is a different trust posture from anything shipped so far, and the same figures are
  already reachable through a human-invoked CLI. The consent question its own intent names is
  answered *no* rather than left open.
- **`L7` stands. Settled, not merely unexamined.** The never-block guarantee is why cost accounting
  never delays a real tool return, and the arrival trim tightened convergence without touching it.
  Recorded so it stops being re-litigated at every eviction gate; new evidence can still reopen it.
- **All five threshold variables stay unset**, and none ships a default. At the current unpriced
  share a budget gate would fire against a fraction of real spend — this file already calls it an
  instrument, not a control. Setting a number now would gate on a figure that misses most of what a
  unit costs.
- **The cost doc's success targets are withdrawn** — rework share, cache-read share, and tokens per
  unit. None is computable today. A target nobody can compute is worse than none, because it invites
  a fabricated number to satisfy it. **Any future target must name the figure that computes it and
  where that figure comes from**, as a condition of being written down.

### Two consequences for work already queued

- **`ship-check` stays at exactly three gates.** The earlier rejection is upheld. Verify's
  full-reproduction mode becomes an explicit flag a human passes at `G3`, and the eval change gate
  lives in `CONTRIBUTING` plus a `G2` finding — neither becomes a fourth gate. So the "exactly three,
  hard-coded" claim, `README`, and `ship-observe-automation`'s `S1`/`S6` cases all stand unedited.
- **`docs/loop/cost-log-section-parse-error-on-macos-ci/` enters `G0` first**, ahead of the backlog.
  It is the newest and least understood fault (1 red in 3 samples on one commit, not reproducible in
  150 local iterations), and it touches `write-cost-log-section.sh` and `cost-ledger-lib.sh` — files
  two backlog units also touch. Understanding it first avoids building on an unexplained fault. The
  other two captured intents (`stale-evict-lock-permanently-defeats-the-cap`,
  `resumed-invocation-never-reaches-the-ledger`) queue behind it, in that order.

## Staleness answer, on the record: no steal, ever (2026-08-19)

`stale-evict-lock-permanently-defeats-the-cap`, `OQ1` at G0 (`SL2`). The question of whether a lock
can be declared stale has now been asked in three units' records — this one, the eviction
convergence entries above, and `harness-fails-only-on-linux`'s second G2 verdict — and this is the
entry that answers it, so it stops being re-derived from scratch each time it comes up.

**The decision: no steal, ever.** A lock cannot be declared stale with the signals this repository
has available. Not by a pid, not by `kill -0` on a recorded pid, not by any age inference this
project's own code performs, and nothing is ever written inside the lock directory to make one
possible later. Staleness can only be inferred here, never proved, and every inference this project
could reach for either fails unsafely or needs a threshold nobody is entitled to choose.

**Every candidate weighed, by name, with the reason it was taken or declined:**

- **Identity in the lock (a pid, or a pid plus a timestamp) written inside the directory, read back
  with `kill -0`.** Declined outright. `rmdir` fails on a non-empty directory
  (`record-cost-event.sh:320`, `record-cost-event.sh:339`, `record-recovered-cost.sh:251`), so
  anything written inside the lock breaks all three release sites at once and converts a leak that
  needs a kill to trigger into a leak on every ordinary invocation — this, not `kill -0`'s own
  weakness, is the reason the whole design is rejected. `kill -0` also fails unsafely in the
  direction that matters on its own terms: a pid observed across a namespace boundary or by a second
  uid can read a live holder as dead, and `mkdir` plus writing an identity into what it created
  cannot be one atomic act, so an observer can always catch the lock carrying no identity yet —
  which must be read as live-or-unknown, never as stale.
- **Age-based expiry.** Declined, and wrong in principle rather than merely untuned. `converge_ledger()`
  is `while :;` (`record-cost-event.sh:290`), with breaks only on real I/O conditions, deliberately —
  so legitimate hold time is unbounded by design. No finite age threshold can therefore be correct for
  every real workload, and shipping one would be a sixth tunable whose correctness the design leans
  on, against the standing decision (this file, `2026-08-19`) that all five existing threshold
  variables stay unset with no defaults shipped.
- **Two-phase claim / heartbeat (liveness read as observed progress).** Declined. It needs a path
  licensed to wait, and none exists: an appending invocation may not (`L7`), and the arrival trim
  explicitly may not (case (i)). Only a human-invoked path could host one, and it would still need
  the identity write the first candidate above already rules out.
- **Detect and report only.** Taken, in part. It leaves the cap unenforced until a human acts, so it
  is not the whole answer by itself, but it is honest about what it does not do, and it is what a
  discoverable route is built from.
- **Release on catchable signals (a trap while the lock is held).** Taken, in part. It covers
  `INT`/`TERM`/`HUP`; it does not cover `KILL`, an OOM kill, or a power loss, and it narrows the
  window a leak can start in without closing it.
- **Bound the leak by uptime (relocate the lock to a per-boot location).** Taken, in part — the only
  candidate in this table that attacks the permanence directly, with no staleness criterion and no
  new threshold of its own.
- **Write the limit down and do nothing else.** The cheapest honest option on the table. Not taken
  alone, but kept as part of the answer: naming the limit is owed regardless of which of the above
  also ships.

**Why nothing is ever written inside the lock, said once on its own because it is the sharpest reason
here and the one most likely to be re-proposed by someone who has not read this entry.** Release is
`rmdir`, at three sites — `record-cost-event.sh:320` (the append path), `record-cost-event.sh:339`
(the arrival trim), and `record-recovered-cost.sh:251` — and `rmdir` fails on a non-empty directory.
A pid file, a timestamp, a heartbeat, or a note left for a human, dropped inside the lock directory,
breaks every one of those three releases at once, turning a kill-only leak into a leak that happens
on every ordinary run. That is why identity-in-the-lock is rejected as a design, not as a detail of
one particular shape of it.

**Both writers are in scope, and here is why the earlier rejection does not transfer (`SL8`).**
`record-cost-event.sh:214` and `record-recovered-cost.sh:106` derive the identical `EVICT_LOCK` path
independently, so a lock orphaned by either writer permanently defeats the other's cap. The
"Build-out of that decision" entry above declined extending the *arrival-trim obligation* to
`record-recovered-cost.sh`, on the grounds that it is a deliberate, human-typed CLI with no
contention — and that rejection stands, for what it was about. It does not transfer to lock hygiene:
a leak needs an interruption, not contention, and a human sitting at that CLI's own prompt with
`Ctrl-C` in hand is precisely where interruptions happen. Nothing about the earlier reasoning was
wrong; it was answering a different question.

**What this unit's answer is not.** The orphaned-lock leak is not fixed by any of this decision, not
closed, not resolved, and not prevented -- only made discoverable, and nothing recorded here claims
otherwise. A kill class this repository cannot catch remains, and the one kill it has actually
recorded -- a machine sleep, named in `docs/loop/conventions.md`'s "A resumed invocation is a
different invocation to the ledger" entry -- is not established to be in the catchable class.

## Relocation declined on evidence: the base is cleared by age, not at boot (2026-08-19)

Taken at `S4`'s evidence gate in
`docs/loop/stale-evict-lock-permanently-defeats-the-cap/`, after
`spike-sl11-base-clearing.md` observed what actually clears the candidate base. `SL11` and `SL13`
are **declined on evidence** — not satisfied, and not deferred to a later unit.

**What was observed, read from the maintainer's host rather than from documentation.** Both candidate
bases sit on the APFS Data volume and the machine has zero memory-backed filesystems, so the one
clearing mechanism establishable without a reboot does not apply. What clears them is age, at **3
days**, from two configurations on that machine: `com.apple.bsd.dirhelper.plist` carries
`CLEAN_FILES_OLDER_THAN_DAYS => "3"`, and `/usr/libexec/tmp_cleaner` carries
`daily_clean_tmps_days="3"` with `dargs="-empty -mtime +3"` — and an evict lock is an empty `mkdir`
marker, which is exactly what that argument targets. `dirhelper` does run at boot
(`RunAtLoad => true`), but with the same age filter, so a lock created minutes before a reboot
survives the reboot. `ubuntu-latest` is `unknown` in every row: a runner cannot be rebooted, a
container is investigation-grade only, and gathering it inside CI would need a workflow edit the
slice forbids.

**Why that reverses the decision rather than qualifying it.** Relocation was approved at G0 to
convert a permanent cap defeat into one bounded by uptime. It cannot deliver that. It delivers
bounding at 3 days by a threshold this project did not choose, cannot see from its own code, and
cannot test — the age-based staleness rule this file already rejected in principle, with the removal
performed by the OS instead of by this project's code. Worse, the filter reads
`atime`/`mtime`/`ctime` on a directory that is **held rather than written**, so holding never
refreshes it, and legitimate hold time is unbounded by design (`converge_ledger()`'s `while :;` with
I/O-only breaks). A holder legitimately holding past 3 days would have its lock deleted while alive.
That is the wrong side of this unit's founding asymmetry: a lock taken from a live holder is a torn
ledger, which is worse than a ledger over cap. Trading a permanent-but-safe failure for a
bounded-but-unsafe one is not the trade that was approved.

**What survives, and what the unit now claims.** The lock stays beside the ledger. `S1`'s header
claim, `S2`'s staleness record and `S3`'s trap hygiene are landed; `S6` reports a present lock where
a human already looks, `S7` narrows to asserting the two writers derive the same path, `S8` measures
what the hygiene costs an appending invocation, and `S9` closes the record. No sentence anywhere may
claim uptime bounding, because uptime bounding was never obtained.

**What this decision is not.** The orphaned-lock leak is not fixed by declining relocation, not
closed, not resolved, and not prevented. It is narrowed to uncatchable kills by `S3`'s hygiene and
made discoverable by `S6`, and that is the whole of it. `SIGKILL` is uncatchable by definition, and
the one kill this repository has actually recorded — the machine sleep named in
`docs/loop/conventions.md` — is not established to be in the catchable class.

**What would reopen it.** A base observed, on a real host of each guarding platform, to be cleared at
boot rather than by age — `findmnt /tmp`, `/usr/lib/tmpfiles.d/tmp.conf` and `/etc/tmpfiles.d/`, and
`printenv TMPDIR`, read from that machine. Absent that, a third base is not proposed here.

## S8 close: the measured cost, and what remains the human's (2026-08-19)

`S8`/`S9` of `stale-evict-lock-permanently-defeats-the-cap`, appended beneath "Relocation declined on
evidence" above rather than rewriting it — that entry already carries `S4`'s numbers (3 days, both
`com.apple.bsd.dirhelper.plist`'s `CLEAN_FILES_OLDER_THAN_DAYS => "3"` and `tmp_cleaner`'s
`daily_clean_tmps_days="3"`, and that `dirhelper` runs at boot with `RunAtLoad => true` under the same
age filter, so a lock created minutes before a reboot survives it), states `SL11` and `SL13` as
declined on evidence rather than satisfied or deferred, and names what survives. This entry adds only
what the build learned after that gate.

**`S8`'s number.** Four arms — `record-cost-event.sh` appending under cap; appending over cap with a
full convergence; a duplicate-finish arrival over cap; `record-recovered-cost.sh` appending over cap
(the other writer `S3` also changed, timed in place of the original envelope's relocation-degradation
arm, which was never built) — n=20 each, interleaved before/after `S3`'s trap on one host (pre
`27b4133`, post `d7cdc40`). Every mean delta is within 0.7 ms and every median delta within 2.7 ms on
65-150 ms baselines, straddling zero. `S3`'s actual diff on the append path is one `trap` registration
and two in-memory flag assignments — no loop, no subprocess, no I/O — and the measurement is
consistent with that: an appending invocation's own cost did not move. Full figures, the falsifiable
spread check, and the method live in `measure-sl6-append-cost.md`; this entry does not repeat the
table.

**The leak is narrowed by `S3`'s hygiene rather than closed.** `SIGKILL` is uncatchable by
definition, and the one kill this repository has actually recorded — the machine sleep named in
`docs/loop/conventions.md` — has an unestablished signal class. Nothing built in `S6`, `S7`, or `S8`
changes that: `S6` only reports a present lock, `S7` only guards the two writers' agreement, and `S8`
only measures a cost that did not move.

**What this unit foreclosed.** The "Staleness answer" entry above already forecloses pid-in-lock, age
expiry as a criterion this project's own code would apply, and two-phase claim/heartbeat, for `OQ1`.
This gate forecloses one more, on evidence rather than by design: relocating the lock to convert
permanence into a uptime bound, absent a base actually observed to clear at boot on a guarding
platform. It is declined pending that evidence, not ruled out for all time — "What would reopen it,"
above, names exactly what would.

**`SL10` is the human's, and this record does not claim it.** A real pushed run on both guarding
platforms, with `guardrails` and `guardrails-macos` reporting an identical `total: N passed, M
failed`, has not happened from this build — merging this group is not that run. One green run, when
it happens, is one sample, never a rate and never a claim that the hygiene holds on CI. `SL11`'s
reboot half is the same shape and is also outstanding: the two marker paths `spike-sl11-base-
clearing.md` left on the maintainer's host, and the single `ls` the human runs after the next reboot,
before `2026-08-22T15:30:39Z` per that file's own validity window.

**The Handoff stays unopened.** The append-versus-trim loss window (a line landing between a
trimmer's `tail` and its `mv`) is a different fault, with a different mechanism, unreproduced, and
this build did not touch it.

## resumed-invocation-never-reaches-the-ledger S4: cannot raise pricing coverage (2026-08-19)

- **Capturing a resumed run yields a record, never a number.** `RE4`, independently corroborated:
  20 of 20 joinable `SendMessage` results carried no token field of any kind (`totalTokens`,
  `input_tokens`, `output_tokens`, `usage`, `totalDurationMs`, `cache_*` — none present), and the
  sample was re-parsed independently and corrected downward from an earlier claim of 24 to the
  corroborated 20. There is no channel by which a hook could observe a resumed run's cost; the
  figure, if it exists at all, arrives only in the run's own completion notification, reachable
  only by a human typing it in.
- **This unit therefore does not satisfy the routing item's revisit condition.** The bullet below
  ("Routing to a cheaper model") is dropped pending "background pricing coverage rises
  materially" — this unit cannot raise that coverage, by the fact above, and its completion must
  not be read as progress toward that condition. The routing decision itself stands unedited;
  nothing here supersedes, revisits, or annotates it.
- **The resumes already in this repository's history stay unattachable.** No ledger record
  written before this unit carries an agent id (`RE6`) — only `agentId` on a `tool_response`
  does — and there is no backfill of that field into existing lines (`OQ-R4`). Whatever this
  unit's Stage 3 ships, past resumes remain outside anything it can attach.

## SL10 satisfied, and SL11's reboot observation contradicts the reading it was predicted from (2026-08-20)

Both halves the `stale-evict-lock-permanently-defeats-the-cap` record named as the human's have now
happened. Appended beneath the two entries above rather than editing either: neither is superseded,
neither is annotated, and the relocation decline still stands as written.

**`SL10` is satisfied, as two samples and not as a rate.** Run `32366734933` on pushed commit
`1bd510b`, job `96417752555` (`guardrails`, `ubuntu-latest`) and job `96417752188`
(`guardrails-macos`, `macos-latest`), each reporting an identical `total: 513 passed, 0 failed`.
That is one sample per platform. It is not evidence that the signal hygiene holds on CI in general,
and the record does not read it that way.

**`SL11`'s reboot observation was taken, and it does not match the prediction.** The host rebooted
2026-08-20 at 14:22 local — inside the validity window
`spike-sl11-base-clearing.md` set, with the two markers roughly 20.5 hours old against a 3-day age
filter. Both were **absent**:

```
ls: /private/tmp/loop-evict-sl11-reboot-marker: No such file or directory
ls: /var/folders/65/fwmwydjj2ml5rwf5x45x6mc80000gn/T/loop-evict-sl11-reboot-marker: No such file or directory
```

The spike stated the decision rule for this branch in advance: *"Either absent → contradicts the
configuration reading and is worth investigating rather than believing immediately."* This entry does
that and no more.

- **Age cannot account for it.** 20.5 hours against `CLEAN_FILES_OLDER_THAN_DAYS => "3"` and
  `daily_clean_tmps_days="3"`.
- **Nothing in this repository removed them.** `grep -rl loop-evict .` matches only the spike file;
  no script, case, or workflow names either path.
- **It does not establish boot-clearing.** One host, one sample. A cleanup tool, an OS update's own
  wipe of `/var/folders`, or boot behaviour differing from the two plists all fit the same
  observation. **No mechanism is named here**, because none was observed — only an absence.

**Why it is recorded rather than acted on.** The decline rested on two legs, and they are entangled:
leg one is that the base has no per-boot property and only a 3-day age rule, which this observation
contradicts; leg two is that an age filter reading `atime`/`mtime`/`ctime` on a directory that is
*held* would reap a long-held marker while its holder is alive. Leg two argues **about the age rule
specifically** — if boot-clearing turns out to be the mechanism, it does not carry, because a reboot
ends the holder too.

So this is live input to "What would reopen it" above, and it is **not** a reopening. One host and
one sample should not move a decision two configuration files argued for, and the leak this unit
narrowed is not narrowed any differently by it.

**Next sample.** Both markers were re-planted 2026-08-20, empty, at the same two paths, so the next
reboot yields a second sample. The observation is valid only if that reboot happens before
2026-08-23T14:01:07Z; after that the 3-day filter can remove them on its own and absence stops
distinguishing the two mechanisms. If the reboot comes later, delete both and re-plant first.

## guardrail-suite-runtime-doubled: the fork per entry is gone, the rebuild is deferred (2026-08-20)

Appended at end-of-file. Nothing above is edited, superseded, annotated, or marked revisited.

**Option (a) taken: `basename "$f"` → `${f##*/}` in the three `PATH`-farm helpers.** Three one-line
edits, no fixture redesign, no shared state. Measured at suite level with interleaved arms on one
host, n=3 per arm: **mean 257.66s → 160.73s, median 247.51s → 158.35s**, every pair the same sign,
none straddling zero. All six runs `total: 513 passed, 0 failed`, and the ordered list of all 513 case
titles and results is **byte-identical across all six runs** (`6e90cf1f95d7`) — the same cases
proving the same things, faster. Figures and method in
`docs/loop/guardrail-suite-runtime-doubled/measure-rt5-suite-runtime.md`.

The observed saving **exceeds** the ~65s the scope was accepted on. The projection came from an
isolated per-build benchmark on an idle host; the arms ran on a loaded one. That explanation is
consistent with the evidence and **unverified**, and is recorded as unverified rather than asserted.

**Option (b) deferred, with its number named: ~92s.** The suite builds a `PATH` farm **twelve times**
across **three distinct shapes**, and ten of those twelve perform a byte-identical symlink pass,
differing only in one file planted afterwards. Building each shape once would collapse nine of the
twelve. That was deliberately **not** bundled into a one-line fix: it is a design change to a fixture
whose entire value is that it cannot lie, and bundling it is the cost
`cost-log-section-parse-error-on-macos-ci`'s `OQ1` already recorded paying. Captured as its own
intent at `docs/loop/suite-path-farms-rebuilt-twelve-times/` so the 92s is not carried as a comment,
with `OQ-RT3` — whether the ten stub fixtures' absence property may be satisfied by a shared base
plus a per-case override rather than literally — as the question a human owns before any build.

**The runtime problem is reduced, not settled.** 160.73s is a mean of three runs on a loaded host, is
not a new baseline, and should not be quoted as one. The suite remains well above the 88.5s it
measured at `18289f2`.

**No guard was added, and that cost is accepted knowingly (`OQ-RT2`).** No threshold, no wall-clock
assertion, no case-count-to-runtime ratio: on shared CI hardware a wall-clock assertion is flaky by
construction, and a flaky guard spends more trust than it buys. The consequence, stated rather than
hidden: **the next silent runtime increase will again be caught by a person noticing, not by a
check** — which is exactly how this one arrived. No check was added, removed, or renamed, so
`docs/loop/checks.md` gains no row.

**`RT7` is outstanding and this entry does not claim it.** The saving is read from one host. Both
guarding platforms' figures need a real pushed run, and per-fork cost differs between bash 3.2 on
macOS and bash 5.x on Linux, so the local delta cannot stand in for either job's.

## resumed-invocation-never-reaches-the-ledger S5: the SendMessage matcher fires, WITH the target agent id (2026-08-20)

`SP1`–`SP5`. The spike's only deliverable is which one of three answers is true. **The answer is (a):
a `hooks.json` matcher on `SendMessage` fires, and the payload carries the target agent id.** Both
halves, recorded separately as `SP5` requires, and neither inferred from the other.

`RE12` was recorded as UNKNOWN and deliberately unasserted in both directions. It is now answered by
observation. **This entry records the answer and nothing else: no arm is recommended, no record type
is proposed, and no capture mechanism is designed.** Choosing what to build on this is the next gate's
business, not this spike's.

**Half one — the hook ran.** Registered on both `PreToolUse` and `PostToolUse` for `SendMessage` in a
throwaway project outside this repository, with two control matchers (`Bash`, `Agent|Task`) so a
silent probe could not be mistaken for a silent hook. The control fired **6 times**; `SendMessage`
fired **4 times** — `PreToolUse` twice, `PostToolUse` twice — across **two distinct sessions**
(`e69a5789`, `73631088`), each resuming a different agent.

**Half two — the payload carries the id.** `to` and `recipient` are present on **4 of 4** payloads,
i.e. on the *input*, available at `PreToolUse`. `resumedAgentId` is present on **2 of 2**
`PostToolUse` payloads (and correctly absent from the `PreToolUse` ones, which carry no
`tool_response`). Where both exist, **the input id equals the response id** in every sample.

Evidence, one `PostToolUse` payload quoted from disk verbatim, whitespace as written:

```json
{"session_id":"e69a5789-416f-4416-82f2-9f2e9ee413ad","cwd":"/private/var/folders/65/fwmwydjj2ml5rwf5x45x6mc80000gn/T/s5-sendmessage-probe","hook_event_name":"PostToolUse","tool_name":"SendMessage","tool_input":{"to":"ae91f4afba4f056cd","summary":"ask probe agent to reply BETA","message":"Now reply with the single word BETA. Do nothing else.","type":"message","recipient":"ae91f4afba4f056cd"},"tool_response":{"success":true,"message":"Resuming agent ae91f4a","resumedAgentId":"ae91f4afba4f056cd","pin":{"id":"ae91f4afba4f056cd","name":"ae91f4afba4f056cd","ref":"0c0087"}},"tool_use_id":"toolu_01Q4PWnxAg6PRJLCUt1yzd7x","duration_ms":6}
```

The second sample is identical in shape with `a5bdfe80c71ac2258` throughout and
`tool_use_id: toolu_01Xauns5zdXgXxNe1wdWPS3g`.

**The probe, re-runnable by a second person.** Scripts at `~/s5-kit/` (`1-setup.sh`, `2-read.sh`,
`3-cleanup.sh`), not in this repository. `1-setup.sh` builds a throwaway project dir, writes a probe
that dumps its stdin verbatim and exits 0, and registers it on both events for `SendMessage` plus the
two controls. A fresh session in that dir is then driven with the prompt the script writes: run one
Bash command, launch one subagent, then resume that agent with `SendMessage`. `2-read.sh` prints the
label counts and the raw payload bytes, and **refuses to report an answer when the control arm did not
fire** — a probe that never ran and a hook that never fires are the same observation.

**One finding worth carrying, because it would waste the next person's run.** Claude Code warns
`Ignoring N permissions.allow entries from .claude/settings.json: this workspace has not been
trusted`. That warning covers **`permissions.allow` only — the hooks in the same file still fire**,
which is what these payloads are. An untrusted workspace is therefore not a reason to discard a run;
the control arm is what settles whether a run counted.

**Cleanup (`SP4`), all four steps run, whichever answer came back.** Throwaway dir and probe script
deleted; `git status --porcelain` clean apart from this unit's own work; `git diff -- hooks/hooks.json`
**empty**; every script named in `hooks/hooks.json` still present and executable. This repository's
`hooks/hooks.json` was never touched and the maintainer's live plugin install was never reinstalled,
modified, or reconfigured.

**What this does not establish.** That a resumed run's *cost* is observable — it is not, and `RE4`
stands unchanged: the id is a handle, never a token figure. Two samples on one host, one platform;
no rate is claimed. And nothing here says what should be built.
