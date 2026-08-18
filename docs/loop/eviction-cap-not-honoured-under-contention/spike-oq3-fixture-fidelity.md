# Spike — OQ3: does case (f)'s fixture faithfully model a real appender?

**Read-only.** No file other than this one is touched. No case, fixture, or assertion in
`tests/guardrails.test.sh` is edited or proposed for edit. Method: reading `append_and_evict()`
and the two real call sites side by side with the fixture's writer, corroborated by exactly one
real hook invocation in a throwaway directory (never a pressure trial — those are `S2`'s).

Commit read against: `d24e2ce` (this worktree's merged base, `main`). Host for the one
corroborating observation: Darwin 25.6.0, arm64.

## OQ3, verbatim (spec.md)

> **OQ3 — does the failing case's fixture faithfully model a real appender?** *Unestablished.*
> Its writer streams lines directly with `>>` and never once attempts eviction, whereas every
> real appender attempts the lock exactly once. The answer may well be **yes, faithful** — a
> lock-loser's single attempt is a no-op, so a stream of losers is behaviourally a stream of raw
> writes. Raised because if the answer is no, the question of what the case should assert belongs
> to the human at G0 alongside `OQ1`, with `spike-case-a.md`'s recorded cost attached — not to a
> builder, and not as a route to green.

## Answer: NO — the writer does not faithfully model a real appender

Its **per-write mechanism** matches a real lock-loser exactly (this corroborates the narrow half
of spec.md's own candidate answer — see below). Its **arrival rate / pressure profile** does not,
and that mismatch is what a "sustained stream of losers" fixture exists to model, because volume
within a bounded time is the entire point of 20000 iterations. The writer can inject far more
lines per unit wall-clock time than any real population of concurrently-arriving `record-cost-
event.sh` invocations could produce, because it skips every cost a real invocation pays before its
own line lands. The fixture therefore constructs a **harsher** world than production, not an
equivalent one.

## Difference-by-difference comparison

Every row traces the real appender's behaviour to a line in `scripts/record-cost-event.sh` at
`d24e2ce`. "Fixture" cites `tests/guardrails.test.sh`.

| # | What differs | Fixture's writer | Real appender (line cite) | Mark | Observation that would flip it |
|---|---|---|---|---|---|
| 1 | The append primitive itself | `printf '{"raw":%d}\n' "$n" >> "$LEDGER"` (`tests/guardrails.test.sh:456`) | `printf '%s\n' "$line" >> "$OUT" 2>/dev/null` (`:263`) | **IDENTICAL** | Any future change making the real append go through a second write, a lock, or a buffer the fixture's write skips — none exists today; reading `:263` shows one `printf` writing one line, same as the fixture. |
| 2 | The lock-loser's `mkdir "$EVICT_LOCK"` attempt and its aftermath | Never issues the syscall — no `mkdir` call anywhere in the writer's loop | Every appender attempts it exactly once: `if mkdir "$EVICT_LOCK" 2>/dev/null; then ... fi` (`:265`); on failure nothing else runs before the function returns (`:287`) — confirmed by `spike-case-a.md` §1's read of this exact path ("An invocation that loses the `mkdir` race does not retry... no second attempt, no queuing, and no signal") | **IDENTICAL in effect** | A measurement showing concurrent `mkdir` contention on one lock name is itself slow enough to matter (many-way concurrent attempts) would move this toward GENTLER-for-fixture. Not observed; `mkdir` is a single atomic POSIX syscall regardless of outcome. |
| 3 | Poll-then-append backoff before the write lands | No check of `$EVICT_LOCK` at all, ever, across all 20000 writes | `while [ -d "$EVICT_LOCK" ] && [ "$backoff" -lt 5 ]; do sleep 0.02; backoff=$((backoff+1)); done` (`:257-260`) — up to 100ms of throttling before the write, specifically while eviction is running. Header: "Appenders never contend for that lock and never block on it (L7) — they poll briefly for it to clear, then append regardless" (`:96-98`) | **HARSHER** (fixture) | A measurement of how long the real winner actually holds `$EVICT_LOCK` during a comparable run. If the hold time is near zero (the loop converges in a handful of `wc -l`/`tail`/`mv` calls), the throttle window this row protects against is rarely engaged and the mark moves toward IDENTICAL. Not measured here — it is `S1`'s `E8` baseline, not this lane's. |
| 4 | Per-invocation process/script startup and subprocess forking | Loop body is bash builtins only (`printf`, `n=$((n+1))`) — zero process forks per line | Every appender is a fresh `bash record-cost-event.sh` invocation from stdin (`:178`) that forks roughly 15 subprocesses for field extraction and assembly before ever reaching the append at `:782`: `extract()`/`extract_num()` (`:217-230`, `:235-248`) called for `hook_event_name`/`tool_name` (`:518-519`), `session_id`/`subagent_type`/`description`/`prompt`/`tool_use_id` (`:547-551`), and on a finish event `status`/`totalDurationMs`/`totalTokens`/`input_tokens`/`output_tokens`/`cache_read_tokens`/`model` (`:604-611`), plus the final `jq -nc` line assembly (`:651-681`) | **HARSHER** (fixture) | Corroborated below: one uncontended real invocation measured at **137.7ms** wall clock. A raw-builtin loop pays no such cost per iteration. If a future measurement showed the raw writer's own throughput was no faster than a real invocation's fork chain, this would flip toward IDENTICAL — not attempted here; that comparison is a rate/throughput trial and belongs to `S2`. |
| 5 | Finished-marker `mkdir` and open-invocation bookkeeping before the append | Performs none of this | On a finish event only: `mkdir -p "$FINISHED_DIR"` then `mkdir "$FINISHED_DIR/$SAFE_ID"` (`:767-768`), plus `resolve_rework_for_invocation()` (`:309-326`, called at `:598`) — a file read and two `rm`s — all before `append_and_evict` is called at `:782` | **HARSHER** (fixture) | Confirmed present by the corroborating observation below, which left exactly one `loop-cost-finished/toolu-spike-1` directory behind. Folds into row 4's flip condition rather than having its own: it only stops mattering if row 4's fork overhead turns out to be cheap, which the 137.7ms measurement argues against. |
| 6 | Line size and content shape | Fixed `{"raw":42}\n` shape, 12-14 bytes/line (`:456`) | A full JSON record via `jq -nc`/python (`:651-681` / `:682-728`) — measured at **242 bytes** for one finish record, capped by the oversize-truncation branch at `:736` (`if [ "${#LINE}" -ge 4096 ]`), which rewrites to a short fallback (`:739-758`) | **GENTLER** (fixture), narrowly | An observation of a record built from maximally-truncated fields (`slug` 200 chars at `:563`, `slice` 50 at `:567`, `status` 200 at `:612`, `invocation_id` 200 at `:765`) approaching 4096 bytes would matter more for this specific row. Not observed; it doesn't bear on the convergence loop this fixture targets. |
| 7 | Which side ever reaches `append_and_evict()`'s convergence loop | Never calls it — bypasses the hook and the eviction mechanism (`:253-288`) entirely | The single real hook invocation is the only participant that calls it (via `:782`), and — because nothing else in this fixture ever attempts `mkdir "$EVICT_LOCK"` — is effectively guaranteed to win the race and run the loop's four break paths (`:274-284`: non-numeric `wc -l` at `:276`, converged at `:277`, `mktemp` failure at `:278`, `tail` failure/empty at `:279-282`, `mv` failure at `:283`) | **IDENTICAL** (structural role, not a fidelity gap) | None needed — this describes the test's own architecture, matching its comment at `tests/guardrails.test.sh:441-448` ("the single real hook invocation below is what exercises `append_and_evict()`'s own convergence loop under test"), not a claim that could be wrong. |

## The contrast fixture — section (b), `tests/guardrails.test.sh:407-435`

60 real hook invocations (`cost(finish_json(...)) &`, 60 times), **no raw writer at all**. Every
line that lands in this section's ledger pays rows 2-5's full real-appender cost. This is the
control case OQ3 is implicitly measured against: it is populated exclusively by the mechanism the
fixture in (f) is trying to stand in for, with none of rows 3-5's overhead removed.

## spec.md's own candidate answer — quoted, then examined

> "a lock-loser's single attempt is a no-op, so a stream of losers is behaviourally a stream of
> raw writes."

**Corroborated on the narrow claim, refuted as an account of fidelity overall.**

Corroborated: row 2 confirms, by line citation, that a lock-loser's `mkdir` attempt is exactly a
no-op — it changes nothing about what that invocation does next, and its write is indistinguishable
in *mechanism* from a raw `>>`. On this point alone, spec.md's candidate answer reads the code
correctly.

Refuted as the whole answer: the candidate answer says nothing about **arrival rate**, and rate is
what a "stream of losers" fixture exists to construct — 20000 lines in a bounded run is a claim
about volume-over-time, not merely about what each individual write looks like. Rows 3, 4, and 5
show that a real "stream of losers" cannot arrive at anywhere near the rate the fixture's writer
does: each real invocation pays a poll-and-backoff of up to 100ms specifically while eviction is
running (row 3), a full script invocation plus roughly 15 subprocess forks before its line lands
(row 4, measured here at 137.7ms for one, uncontended), and finished-marker/bookkeeping filesystem
work on top of that (row 5) — none of which the fixture's bash-builtin-only loop pays at all. "A
lock-loser's single attempt is a no-op" is true; "so a stream of losers is behaviourally a stream
of raw writes" does not follow from it, because the *aggregate pressure* a real stream of losers
could apply in the same wall-clock window is bounded by costs the fixture's writer has entirely
removed. The specific reason the candidate answer is incomplete, not merely restated: it reasons
about one write in isolation and silently generalises to a stream, where the thing that changes
between "one write" and "a stream of writes in bounded time" is exactly the per-write overhead the
candidate answer never mentions.

## What this does to the meaning of "the cap is broken"

The fixture models a harsher world than production, as established above by structural reading and
one corroborating measurement, not by whether the case passes. This changes what the failing
case's red demonstrates: it shows that `append_and_evict()`'s convergence loop has no guarantee
against an arrival rate of raw appends that the writer can produce but that this reading gives no
reason to believe a real population of concurrently-arriving `record-cost-event.sh` invocations —
each paying the process-startup, poll-backoff, and bookkeeping costs in rows 3-5 — could themselves
generate. It is evidence of a rate-independent gap in the algorithm's design (there is no bound on
how much unconditioned append volume can land inside one evictor's convergence window, regardless
of what produces that volume), established by construction rather than by observing a real
population reach that volume. It is not, on this reading alone, evidence that genuine concurrent
hook invocations — at any realistic population size — arrive fast enough to reproduce the same
overage. What should therefore happen to the case or its assertion is not decided here; that
question is the human's, at the second G1, with `spike-case-a.md`'s recorded cost attached.

## Corroborating observation (one, as permitted — never a substitute for the read above)

Ran a single real hook invocation against `scripts/record-cost-event.sh` at `d24e2ce`, in a
throwaway directory (`CLAUDE_PROJECT_DIR` pointed at a scratch path outside this repository's own
`.claude/`), with a synthetic `PostToolUse` "finish" payload shaped like `finish_json`'s output
(`subagent_type:"loop-build"`, `tool_use_id:"toolu-spike-1"`, `status:"completed"`,
`totalTokens:1`, `totalDurationMs:1`):

- **Exit code:** `0`.
- **Wall clock, one invocation, uncontended:** `137.7ms` (`137672000ns`), measured with
  `date +%s%N` immediately before and after the `bash scripts/record-cost-event.sh` call. One
  sample — sized to corroborate row 4's structural claim, not a rate or a trial.
- **Ledger line produced:** `242` bytes (before the trailing newline) —
  `{"ts":1787053264,"event":"finish","invocation_id":"toolu-spike-1","session_id":"sess-spike",
  "slug":"unknown","phase":"build","agent":"loop-build","model":"sonnet","model_source":"derived",
  "status":"completed","duration_ms":1,"total_tokens":1}` — cited in row 6.
- **What it left behind under `.claude/`:** `loop-cost.jsonl` (the one line above) and
  `loop-cost-finished/toolu-spike-1/` — an empty directory, the finish-dedup marker created by the
  `mkdir "$FINISHED_DIR/$SAFE_ID"` at `:768` — cited in row 5.
- **Host tooling used:** `jq` present (`/opt/homebrew/bin/jq`), so the extraction path taken was
  the `jq`-fork branch of `extract()`/`extract_num()`, not the `python3` fallback.

This is one observation of one uncontended invocation. It does not establish a rate, a trial count,
or anything about concurrent behaviour — those are `S2`'s question (`OQ5`) — and it is not treated
here as more than a number that sizes the structural claim in row 4.

## Unknowns, named rather than assumed

- Whether `mkdir` contention itself measurably slows down a lock-loser's attempt (row 2's flip
  condition) under many concurrent losers is not measured here — no pressure trial was run to check
  it, and the structural read gives no reason to expect it does.
- What the raw writer's own throughput actually is (lines/second) was deliberately not measured —
  timing it would be a second observation and edges toward the throughput/rate trials this lane is
  constrained from running. The comparison rests on the structural fact (builtin loop vs. per-line
  fork chain) plus the one real-invocation timing above, not on racing the two against each other.
