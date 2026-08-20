# Measurement — RT5: what removing the fork per entry bought, at suite level

Slice `S1`. This file plus three one-line edits to `tests/guardrails.test.sh` is the slice's whole
diff. Follows `docs/loop/stale-evict-lock-permanently-defeats-the-cap/measure-sl6-append-cost.md`'s
shape: interleaved arms, `n` stated, mean **and** median, min and max, one host named.

**Counts and samples, never rates.** Six runs, one host, one day.

## 1. What was changed, exactly

Three lines, one per `PATH`-farm helper, inside the per-entry loop:

```
-      base="$(basename "$f")"
+      base="${f##*/}"
```

at `tests/guardrails.test.sh:3089` (`new_jq_absent_path`), `:3114` (`new_grep_absent_path`) and
`:3141` (`new_stub_parser_path`). `git diff` on the file is exactly those three hunks and nothing
else — no bin-directory list, skip condition, `[ -e ]` guard, `ln -s`, or `mktemp -d` touched.

**Two `basename` calls remain in the file and were deliberately left:** `:3554`
(`basename "$f" .md`, the two-argument suffix-stripping form, which `${f##*/}` does not replace) and
`:5876` (inside the claim-word guard's loop over a handful of named files, where the fork count is
small). Both are outside the three helpers, and `slices.md`'s `Do NOT` places a repo-wide fork audit
out of scope.

## 2. Method

One host: `Darwin 25.6.0` arm64, bash 3.2.57, the maintainer's machine. One driver script, alternating
**pre / post / pre / post / pre / post** rather than running two blocks — so a drift in machine load
lands on both arms rather than on one. Each run is a full `bash tests/guardrails.test.sh` from the
repository root, timed wall-clock around the whole invocation, with the suite file swapped between
runs and nothing else changed.

**The host was not idle**, and that is why interleaving is the method rather than a nicety: load
average was in the 28–42 range across the window. The absolute numbers below are therefore higher
than `spec.md` §1.1's 218.8s baseline, which was taken on a quieter host. **Pairs are comparable to
each other; neither arm here is comparable to §1.1.**

## 3. Results

| Arm | n | Trials (ms) | Mean | Median | Min | Max |
|---|---|---|---|---|---|---|
| **pre** — `basename` fork per entry | 3 | 285028, 247506, 240448 | **257.66s** | **247.51s** | 240.45s | 285.03s |
| **post** — `${f##*/}` builtin | 3 | 172866, 158353, 150958 | **160.73s** | **158.35s** | 150.96s | 172.87s |

**Delta: mean 96.94s, median 89.15s.** Per-pair deltas, in run order: **112.16s, 89.15s, 89.49s** —
every pair the same sign, none straddling zero. Reduction on the means: **37.6 %**.

All six runs reported `total: 513 passed, 0 failed`.

### The observed saving exceeds the projection, and that is stated rather than smoothed

`spec.md` §1.3 projected ~65s (5.4s per build × 12 builds) from an isolated per-build benchmark. The
suite-level arms show 89–112s. **The projection under-predicted by roughly a third, and this file does
not claim to know why.** The candidate explanation — that §1.3's benchmark ran on an idle host while
these arms ran on a loaded one, and per-fork cost rises with load — is **consistent with the system
time in §1.1 and unverified here**. It was not tested, because testing it means re-running the whole
interleaved set on an idle host, which is a measurement this slice does not owe.

What can be said from these six runs: the saving is real, is the same sign in every pair, and is
**larger** than the number G0 accepted the scope on.

## 4. RT3 — no case's outcome changed

The ordered list of every case title and its result was captured from all six runs and compared.

| Run | Lines | SHA-1 of the ordered list |
|---|---|---|
| pre 1, post 1, pre 2, post 2, pre 3, post 3 | 513 each | `6e90cf1f95d7` — **identical across all six** |

`diff` between each pair's pre and post list is **empty**. Not merely the same count and the same
colour: the same titles, the same results, in the same order, byte for byte, in every run. This is
the criterion that makes a cost change believable, and it is the strongest form of it available.

## 5. What this does not establish

- **That the runtime problem is settled.** It is **reduced, not settled**. Option (b) — building each
  of the three distinct farm shapes once instead of twelve times — was left on the table at G0 with
  its own ~92s, and is captured as its own intent by `S2`.
- **The figure on either guarding platform.** `RT7` is owed by a real pushed run reading both jobs'
  durations. Everything above is one host. Per-fork cost differs between bash 3.2 on macOS and
  bash 5.x on Linux, so the local delta cannot stand in for either job's.
- **A new baseline for the suite.** 160.73s is a mean of three runs on a loaded host, not the suite's
  runtime. Nobody should quote it as one.
- **Why the projection under-predicted.** See §3. Unverified, and labelled as such.
