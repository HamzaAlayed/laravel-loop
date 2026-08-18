# Spike — OQ5: can a scenario on the maintainer's own host go red against today's HEAD?

Unit: `eviction-cap-not-honoured-under-contention`, Slice S2. Read-only spike — no code, no test,
no fix. Every scenario below is a runnable markdown snippet; none is a harness case and none edits
`tests/guardrails.test.sh`.

## Answer: **YES.**

A scenario runnable on the maintainer's own host leaves the ledger over cap **at rest** against
today's HEAD, with the stale evict lock verified absent both before and after every trial. It is
**not** case (f)'s own raw-writer scenario re-run harder — every raw-writer / real-hook-invocation
variant tried stayed green (below). The red comes from a third, distinct arm: a real hook invocation
that is forced to be the run's **last** appender while the evict lock is genuinely (not staleily)
held by a concurrent evictor for longer than L7's poll budget.

## Provenance

- **HEAD**: `d24e2ce500ad00f241e17ffd6b2d04fc1910b98e` (`G1: three read-only spike slices for
  eviction-cap, fix group left uncut`), confirmed against local `main` (identical) before any trial.
- **`scripts/record-cost-event.sh` at HEAD**: unmodified, sha256
  `6c22fbc55ab1f6fca2f3348cd7a212389d98ec54dbe48612ec8f426b258f3dda`. Last touched by `22779f8`
  (S9, the mv-break fix) — nothing in this spike edits it.
- **Pre-S5 version**, obtained read-only: `git show 68ece94^:scripts/record-cost-event.sh` (commit
  `f64174a810247e0552dfa500a4696262d94a39b1`) into a throwaway file — never `git checkout`, never a
  branch, never a stash.
- **Host**: `Darwin 25.6.0`, `ProductVersion 26.6.1`, `arm64`, `GNU bash, version 3.2.57(1)-release
  (arm64-apple-darwin25)` — exact match to the recorded maintainer's host (macOS 26.6.1, arm64, bash
  3.2.57(1)-release). This is a real run on that host, not a container or VM — nothing here is
  investigation-grade.
- Every trial ran inside its own `mktemp -d` directory, with its own `CLAUDE_PROJECT_DIR` and
  `.claude/`. This repository's own `.claude/loop-cost.jsonl`, finished-marker directory, and evict
  lock were never touched — confirmed clean (`git status --short` empty, no `.claude/` created here)
  after every trial batch below.

## Test set, in order (per the envelope)

### Step 1 — reproduce the baseline (case (f)'s own scenario), K=5, against HEAD

Case (f)'s own parameters, run standalone (not via `tests/guardrails.test.sh` — this reimplements
its two helpers, `finish_json` and the append loop, so the snippet needs nothing sourced from the
suite):

```bash
#!/usr/bin/env bash
# baseline: CAP=15 WRITER_LINES=20000, one raw >> writer, one real hook invocation.
# Arm label: raw-writer (writer) + real-hook-invocation (evictor-attempt).
set -uo pipefail
REPO_ROOT=/path/to/laravel-loop-repo   # <- set this
SCRIPT="$REPO_ROOT/scripts/record-cost-event.sh"

finish_json() { python3 - "$1" "$2" <<'PY'
import json, sys
tid, session = sys.argv[1:3]
print(json.dumps({"hook_event_name":"PostToolUse","session_id":session,"tool_name":"Agent",
  "tool_use_id":tid,"tool_input":{"subagent_type":"loop-build","description":"d"},
  "tool_response":{"status":"completed","totalTokens":1,"totalDurationMs":1}}))
PY
}
run_hook() { printf '%s' "$2" | CLAUDE_PROJECT_DIR="$1" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$SCRIPT" >/dev/null 2>&1; }

for trial in 1 2 3 4 5; do
  dir="$(mktemp -d)"; mkdir -p "$dir/.claude"; ledger="$dir/.claude/loop-cost.jsonl"
  [ -d "$dir/.claude/loop-cost-evict.lock" ] && { echo "LOCK PRESENT AT START"; continue; }
  ( n=0; while [ "$n" -lt 20000 ]; do printf '{"raw":%d}\n' "$n" >> "$ledger"; n=$((n+1)); done ) &
  wpid=$!
  LARAVEL_LOOP_COST_MAX_LINES=15 run_hook "$dir" "$(finish_json toolu-conv-1 sess-conv)"
  wait "$wpid" 2>/dev/null
  count="$(wc -l < "$ledger" | tr -d ' ')"
  [ "$count" -le 15 ] && echo "trial $trial: green ($count)" || echo "trial $trial: RED ($count)"
  rm -rf "$dir"
done
```

**Result: 0/5 red against HEAD (`d24e2ce`).** Matches the existing 5/5-green record — the baseline
reproduces cleanly rather than being trusted on citation alone.

### Step 2 — vary one pressure dimension at a time from case (f)'s parameters

Every arm below launches its writer(s) and hook invocation(s) as backgrounded raw `>>` streams and
real `record-cost-event.sh` invocations respectively (never sourcing the suite), each in its own
throwaway `mktemp -d`, with the lock verified absent (`[ -d .../loop-cost-evict.lock ]`) before every
trial in every arm. **Arm label: raw-writer + real-hook-invocation, one dimension changed from case
(f)'s own values; all others held at case (f)'s baseline** (`CAP=15 WRITER_LINES=20000
WRITER_COUNT=1 HOOK_COUNT=1`, no arrival delay) unless the row's own dimension says otherwise.

| Dimension varied | Value(s) | N/M red against HEAD (`d24e2ce`) |
|---|---|---|
| (baseline, step 1) | as above | 0/5 |
| cap | 2 | 0/5 |
| writer line count | 300000 | 0/5 |
| writer count | 4 concurrent raw writers | 0/5 |
| concurrent real hook invocations | 8 (writer_count=1, writer_lines=20000) | 0/10 |
| concurrent real hook invocations, no writer | 50 | 0/10 |
| concurrent real hook invocations, no writer | 200 | 0/10 |
| arrival interleaving | 5 hook invocations staggered 50/100/150/200/250ms into the writer stream | 0/5 |
| filesystem | **not varied** — no second writable volume is mounted on this host (`df -h` shows one
  APFS container only) and this harness's own worktree-isolation guard refused the disk-image
  (`hdiutil`) command needed to create a ramdisk from inside this session. Recorded as untried,
  not as tried-and-negative. |

*Exploratory only, not part of the one-at-a-time ladder above (multiple dimensions changed at once,
so a result here cannot be attributed to any single one): 4 raw writers × 50000 lines, cap=5, 30 real
hook invocations staggered 20ms apart — 0/15 red. Included for completeness; not evidence either way
about a single dimension.*

None of the raw-writer / real-hook-invocation arms — the two arm types case (f) itself mixes —
produced a red at any tried extreme. **Whether the raw-writer arm's `>>` stream faithfully models a
real appender is OQ3, S3's question; this lane cites it and does not answer it.**

### Step 3 — the red that was found, re-run with the lock verifiably absent, and against pre-S5

The red is **not** a raw-writer or multi-hook-invocation scaling effect. It is a direct, deterministic
construction of the structural hole `spec.md` names: *"an invocation that loses [the evict-lock] race
makes no second attempt... so some invocation always appends last, after the final trim, with no
later appender obliged to re-evict."*

**Arm label: real-hook-invocation is the sole appender and the run's last invocation; the pressure is
a directly-manipulated evict-lock directory representing a genuine, cleanly-released concurrent
evictor's hold** — the identical primitive `tests/guardrails.test.sh` case (g) already uses to
simulate "the evict lock is held by another process" (`mkdir "$L7_LOCK"`, a backgrounded
`sleep N; rmdir`). This is not a new technique; it is case (g)'s own established method, extended past
what case (g) checks (that the append still lands and the wait doesn't scale) to what it doesn't
check (whether the ledger converges once the hold ends).

```bash
#!/usr/bin/env bash
# Deterministic construction of "the last appender is a lock loser."
# Arm label: real-hook-invocation (sole appender, run's last event) +
# directly-held evict lock (simulated concurrent evictor, cleanly released --
# NOT a stale/stuck lock; its absence is checked before AND after).
set -uo pipefail
REPO_ROOT=/path/to/laravel-loop-repo   # <- set this; or a git-show temp dir for the pre-S5 version
SCRIPT="$REPO_ROOT/scripts/record-cost-event.sh"
CAP=15
HOLD_SECONDS=0.5   # > L7's ~0.1s poll budget (5 x sleep 0.02)

finish_json() { python3 - "$1" "$2" <<'PY'
import json, sys
tid, session = sys.argv[1:3]
print(json.dumps({"hook_event_name":"PostToolUse","session_id":session,"tool_name":"Agent",
  "tool_use_id":tid,"tool_input":{"subagent_type":"loop-build","description":"d"},
  "tool_response":{"status":"completed","totalTokens":1,"totalDurationMs":1}}))
PY
}
run_hook() { printf '%s' "$2" | CLAUDE_PROJECT_DIR="$1" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$SCRIPT" >/dev/null 2>&1; }

for trial in 1 2 3 4 5; do
  dir="$(mktemp -d)"; mkdir -p "$dir/.claude"
  ledger="$dir/.claude/loop-cost.jsonl"; lock="$dir/.claude/loop-cost-evict.lock"

  [ -d "$lock" ] && { echo "LOCK PRESENT AT START -- would be OQ4's route, not this arm"; continue; }

  n=1; while [ "$n" -le "$CAP" ]; do printf '{"seed":%d}\n' "$n" >> "$ledger"; n=$((n+1)); done

  mkdir "$lock"                                   # simulate a concurrent evictor holding it
  ( sleep "$HOLD_SECONDS"; rmdir "$lock" 2>/dev/null ) &
  holder=$!

  LARAVEL_LOOP_COST_MAX_LINES=$CAP run_hook "$dir" "$(finish_json toolu-last sess-last)"  # the run's LAST appender
  wait "$holder" 2>/dev/null

  [ -d "$lock" ] && { echo "trial $trial: LOCK STILL PRESENT AT END -- discard, this would be OQ4"; rm -rf "$dir"; continue; }
  count="$(wc -l < "$ledger" | tr -d ' ')"
  [ "$count" -le "$CAP" ] && echo "trial $trial: green ($count)" || echo "trial $trial: RED ($count)"
  rm -rf "$dir"
done
```

**Results:**

- **Against HEAD (`d24e2ce`, `scripts/record-cost-event.sh` sha256 `6c22fbc5…8f426b258f3dda`): 5/5
  red** (`count=16 cap=15` every trial). Lock confirmed **absent at the start** of all 5 trials and
  confirmed **absent again at the end** of all 5 — this is not the stale-lock route (OQ4): the
  simulated evictor released the lock inside the trial, well before the check, exactly as case (g)'s
  own holder does.
- **Against the pre-S5 version** (`git show 68ece94^:scripts/record-cost-event.sh`, commit
  `f64174a810247e0552dfa500a4696262d94a39b1`, sha256
  `987a71a12b64f56deb0be4719bcd7b127826266df22075c636c27a9236a22e9a`): **5/5 red** as well
  (`count=16 cap=15` every trial), lock absent at start and end of all 5. This places the red against
  version history rather than asserting it: it shows the hole is **not** the convergence-gap S5
  closed (that gap was about the winner giving up after a fixed number of trim attempts while still
  over cap; this hole is about the loser never getting a second attempt at all) — it predates S5 and
  survives it unchanged.
- **Sanity control, same construction, `HOLD_SECONDS=0.02`** (below L7's ~0.1s poll budget), against
  HEAD: **0/5 red** (`count=15` every trial) — lock absent at start of all 5. This confirms the red
  above tracks L7's own documented poll window precisely rather than being an artifact of the harness:
  a hold shorter than the budget lets the appender itself win the now-free lock and evict its own
  line; a hold longer than the budget is exactly the case the header names as accepted ("a ledger that
  sits slightly over cap for a moment") but which persists **at rest** here because nothing else ever
  runs afterward.

### Step 4 — not applicable

The answer is **yes**, so `E3` unmet does not apply. (Every negative arm from step 2 is still reported
above, in full, per `E4`'s discipline that a negative arm is also a count, not silence.)

## E4 — counts, never rates, restated per arm

Every number above is `N/M red`, one trial = one sample, exactly the shape of the existing 5/5
records this unit already cites. No arm's result is described as a percentage, an expectation, or a
rate. The two 5/5 positive results (HEAD and pre-S5) are five independent trials each, not one
observation multiplied; the 0/5, 0/10, 0/15 negative arms are reported with their own trial counts,
not implied to be exhaustive.

## What this does and does not establish

- It establishes that `OQ1`'s structural claim — some invocation is always the last appender, and if
  that invocation loses the evict-lock race, nothing later is obliged to re-evict — is not merely a
  theoretical reading of the code. It is mechanically reproducible on this host, deterministically,
  under a lock hold longer than L7's own poll budget, with zero reliance on process death, timing
  luck across many concurrent processes, or a container.
- It does **not** establish that CI's specific red (case (f), the raw-writer + single-hook-invocation
  scenario) is caused by this same mechanism — every attempt to reproduce **that exact shape** of
  pressure, at every dimension tried, stayed green on this host. The two findings are separate: case
  (f)'s own scenario remains unreproduced locally at any tried extreme (consistent with the
  intent's recorded asymmetry — CI is known only to apply *more* pressure than that fixture does),
  while a different, more direct construction of the same *named* structural hole (`OQ1`) does
  reproduce, deterministically, from the code as written.
- It does not pick between `OQ1`'s two answers, and it does not say what should be built. Per the
  pinned contract, that stays the human's call at the second G1, now with a concrete, reproducible
  local red in hand for whichever answer is chosen.
- It is not `OQ4`. Every trial — positive and negative — checked the lock's absence before it began,
  and the positive arm also checked it again after the trial ended, specifically to keep this red
  from being attributable to a stale, never-released lock.
