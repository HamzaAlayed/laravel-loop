# Intent — guardrail-suite-runtime-doubled

Captured: 2026-08-19T21:11:25Z

## What was observed

`tests/guardrails.test.sh` now takes **3m38s** wall clock on the maintainer's host, measured
by `time`:

```
bash tests/guardrails.test.sh  68.16s user 110.96s system 82% cpu 3:38.13 total
```

Earlier in the same session the suite completed inside a 2-minute tool timeout; it now exceeds
that timeout and has to be run with an extended one. The case count went `466 → 513` across
the day, an increase of 47 cases.

The system time (110.96s) exceeds the user time (68.16s), which is consistent with the run
being dominated by filesystem work rather than by the shell evaluating assertions. Several
cases added today build isolated `PATH` directories by symlinking every resolvable entry of
`/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`, `/opt/homebrew/bin` and `/usr/local/bin` into a fresh
`mktemp -d` — `new_jq_absent_path()` (pre-existing), and `new_grep_absent_path()` and
`new_stub_parser_path()` (added today). Whether those helpers account for the increase is
**not established**; no per-case timing was taken.

No criterion in any unit covers suite runtime, so nothing failed and nothing warned.

## Where it surfaced

The maintainer's host — `Darwin 25.6.0` arm64, bash 3.2.57. Also paid by CI on every push, on
both `ubuntu-latest` and `macos-latest`, where the runtime is `unknown` — CI run
`32288259463` passed on both platforms but its per-job duration was not recorded here.

## When

2026-08-19, first noticed when a full-suite run exceeded a 2-minute timeout while validating
`cost-log-section-parse-error-on-macos-ci`'s `S2`–`S4`.

## What was already tried

- **Measured once** with `time`, giving the figure above. One host, one sample.
- **Counted the growth**: 466 → 513 cases across three units merged today.
- **Read the helpers** that manipulate `PATH` by symlinking whole `bin` directories, and noted
  that two of the three were added today.
- **Not tried:** any per-case or per-helper timing; a comparison run against an earlier commit
  such as `18289f2` (466 cases) to establish the before figure rather than inferring it from a
  tool timeout; any measurement on Linux or in CI; any attempt to reduce it.

The earlier figure is **not** established — "completed inside a 2-minute timeout" is a bound,
not a measurement.

## Suspected unit or commit

`unknown` as a cause.

Three units merged today added cases: `docs/loop/cost-log-section-parse-error-on-macos-ci/`
(+21, including two of the `PATH`-building helpers),
`docs/loop/stale-evict-lock-permanently-defeats-the-cap/` (+11), and
`docs/loop/resumed-invocation-never-reaches-the-ledger/` (+15). No per-unit timing was taken,
so apportioning the increase between them would be a guess.

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance
criteria, no non-goals, and no slices**; nothing builds from it directly.
