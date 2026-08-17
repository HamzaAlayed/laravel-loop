# Spike — Case A only

**Case:** `tests/guardrails.test.sh:429`, section (b) (`:407-435`), `eviction under concurrency:
settles at or under cap` (expected exit `yes`, got `no` on the CI runner; `ok` on the maintainer's
host). Commit that introduced the case: `5799d86`. Code exercised: `scripts/record-cost-event.sh`'s
`append_and_evict()` (roughly lines 250-279), invoked via `cost()` in the test file.

This file is a read-only finding. It names no fix, proposes no patch, and touches no file other
than itself. Case B is out of scope for this file and is not read, discussed, or assumed to share a
cause.

## 1. Mechanisms named from reading section (b) and its code path

Section (b) launches 60 background invocations of `record-cost-event.sh` (`EVICT_N=60`) against a
ledger capped at 15 lines (`EVICT_CAP=15`) via `LARAVEL_LOOP_COST_MAX_LINES`, then asserts the final
line count is `<= 15`.

`append_and_evict()`'s design, read literally:

- Appenders never block: each invocation appends its own line with a single `>>` write regardless of
  lock state (`L7`, "never block a spawn" — documented in the script's own header).
- Exactly one invocation at a time may become the evictor: `mkdir "$EVICT_LOCK"` is the mutex: it can
  only succeed for one process.
- **An invocation that loses the `mkdir` race does not retry.** The `if mkdir ...; then ... fi` block
  is skipped entirely on failure, and the function returns. There is no second attempt, no queuing,
  and no signal to any other process that trimming is still owed.
- The one invocation that wins the race loops **at most 5 times**, re-checking `wc -l` and trimming
  with `tail -n $MAX_LINES | mv` each time, then releases the lock unconditionally, whether or not the
  file is at-or-under cap at that point.

Read this way, the mechanism is a **bounded-retry, single-current-evictor race with no guaranteed
convergence**: if concurrent appends land faster, or in a larger burst, than the current lock-holder's
5 iterations can drain, the loop exhausts its bound, releases the lock, and nothing else in the
design revisits the file — the 59 other invocations already made their one eviction attempt (win or
lose) earlier in their own lifecycle and do not get a second chance. This is a property of the
**algorithm's fixed retry bound versus the arrival rate of concurrent appends**, not, on its face, a
platform-dialect detail.

Candidates checked for an actual shell-or-coreutils divergence in this exact path, and ruled out:

| Primitive used here | macOS bash 3.2 / BSD-family tools | Linux bash 5.x / GNU coreutils | Verdict |
|---|---|---|---|
| `mkdir DIR` (lock) | atomic, POSIX | atomic, POSIX | same |
| `wc -l < FILE \| tr -d ' '` | leading-space output, stripped | no leading space, stripped | same after strip |
| `mktemp "$OUT.evict.XXXXXX"` | accepts trailing-X template | accepts trailing-X template | same |
| `tail -n N FILE` | same semantics for positive N | same semantics for positive N | same |
| `mv -f tmp OUT` | atomic rename, same filesystem | atomic rename, same filesystem | same |
| `sleep 0.02` (backoff) | **confirmed accepts fractional seconds** — measured `0.024s` wall time on this host | accepts fractional seconds | same |
| `printf ... >> FILE` atomicity | POSIX `O_APPEND` write, atomic under `PIPE_BUF` | same POSIX guarantee | same |

No mechanism in this table differs between the two platforms in a way that would explain the CI
result. This weighs against OQ1 answer 1 in its narrow form ("it asserts something only true of one
platform's tool behaviour") — nothing checked here is tool-version-sensitive.

## 2. Investigation-grade observation under Linux bash

**Labelled investigation-grade. Not cited as proof of A1, A2, or A5 — per this unit's pinned
contract.**

Ran the exact section-(b) sequence (same 60-invocation / cap-15 shape, same unmodified
`scripts/record-cost-event.sh` from this worktree, same `finish_json`/`valid_jsonl_lines` helpers
copied verbatim from `tests/guardrails.test.sh`) in throwaway Docker containers, not committed to
this repository and not required to run the suite:

- `ubuntu:22.04`, `GNU bash, version 5.1.16(1)-release (aarch64)`, 10 vCPUs available: 5 trials, all
  settled at exactly 15 lines.
- `ubuntu:24.04`, `GNU bash, version 5.2.21(1)-release (aarch64)`, 10 vCPUs available: 5 trials, all
  settled at exactly 15 lines.
- `ubuntu:24.04`, same bash, **`--cpus=2`** (closer to a hosted-runner's typical allocation): 15
  trials, all settled at exactly 15 lines.
- Maintainer-shape baseline on this host (macOS, `GNU bash, version 3.2.57(1)-release`, arm64): 5
  trials, all settled at exactly 15 lines — matching the suite's own `421 passed, 0 failed`.

**20/20 Linux trials across two Ubuntu versions, two bash versions, and two CPU allocations settled
at or under cap.** The one CI failure was not reproduced directly. `valid_jsonl_lines` and the
never-empty poll (`zero_observed`) also read `yes`/`no` identically to the maintainer's host in every
trial — nothing about JSON validity or transient emptiness diverged either.

This container setup is investigation-grade only: it does not reproduce GitHub's exact
`ubuntu-latest` image, kernel, cgroup contention from a shared host, or the load already on the
runner from the two preceding steps in the same job. It is not evidence for A1, A2's resolved-tree
count, or A5, and is not cited as such here.

## 3. Falsifiable hypotheses

**H1 — a deterministic bash-version or coreutils-version semantic difference in `append_and_evict()`
causes the divergence.**
Refuting observation: run the identical code under real GNU bash + real GNU coreutils on Linux and
see whether it reproduces reliably. **Observed:** it did not reproduce once in 20 trials across two
Linux distributions and two bash versions. **H1 is refuted** by this observation — a deterministic
per-platform code-path difference would be expected to reproduce on any real Linux bash, and none of
the 20 trials did.

**H2 — the eviction loop's fixed 5-attempt bound has no convergence guarantee under a sufficiently
high concurrent-append arrival rate, and the CI runner's specific resource profile (shared/contended
CPU, virtualization/cgroup scheduling latency) produced that rate once, where this sandbox's Docker
containers did not.**
Refuting observation: reproduce the CI runner's exact contention profile (not merely a CPU-count
limit) and show the loop still converges — this was **not attempted** here, because that profile is
not something a local container can be a stand-in for without becoming exactly the "simulated Linux
cited as proof" this unit's pinned contracts forbid. **H2 is neither confirmed nor refuted here.** It
remains open, and what would settle it is named below.

**What would settle it:** a second real, isolated run of section (b) alone on the actual guarding
machine (`ubuntu-latest`), repeated a handful of times back-to-back, would show whether the failure
recurs at any material rate on that specific infrastructure — the single observed failure is one
sample, and OQ4/A2 already treat one sample as a lower bound, not a rate.

## Answer for Case A

**OQ1: answer 2** — the evidence favours "the thing it exercises is wrong" over "the case is wrong,"
but with a qualification that matters for A3: the defect established by reading is a **real
convergence gap in `append_and_evict()`'s bounded-retry design** (H1, the narrower "shell/coreutils
dialect" reading of answer 2, is refuted). The case is not asserting an arbitrary, platform-specific
detail; it is asserting a substantive concurrency-safety property (the ledger stays at or under its
declared cap) that this exact code, read literally, does not guarantee once a lock-loser is given up
on rather than retried.

**Is the guarded behaviour genuinely platform-dependent?** **Not established, and the evidence leans
against a deterministic macOS-vs-Linux reading specifically.** Twenty direct-observation trials under
real Linux bash (two distributions, two bash versions, two CPU allocations) did not reproduce the
divergence; the maintainer's host and this investigation-grade Linux behaved identically (settled at
cap, every trial). What is established is a genuine defect in the algorithm's convergence guarantee
under concurrency in general — not shown here to be tied to which OS or shell runs it, only to how
much concurrent append pressure lands within one evictor's 5-attempt window. Whether the CI runner's
specific, non-reproduced resource profile is what supplies that pressure is `unknown`, per the
falsifiable-hypotheses section above; H2 is open, not confirmed.

**Cost of each candidate resolution (artifact only, no design offered):**
- **Answer 1 (the case is wrong):** the change would live in `tests/guardrails.test.sh`, at the
  assertion for `eviction under concurrency: settles at or under cap` (`:429`) and/or the section-(b)
  setup around it. Cost, per spec.md's own framing and confirmed by §1 above: the case is guarding a
  real, non-platform-specific correctness property (bounded eviction under concurrency), not a
  platform quirk — weakening or removing this assertion would discard the only warning that this
  property can be violated at all, independent of whether Linux specifically is implicated.
- **Answer 2 (the thing it exercises is wrong):** the change would live in
  `scripts/record-cost-event.sh`, inside `append_and_evict()`. Cost, per spec.md's non-goal ("Not a
  redesign of the cost ledger"): any change here touches the S4 eviction mechanism this unit
  otherwise declares out of bounds beyond exactly what a recorded decision requires, and must not
  regress the deliberate, documented guarantee that appenders never block on the evict lock (`L7`) —
  a wider change than the single failing assertion suggests.
