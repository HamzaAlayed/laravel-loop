# Intent — harness-fails-only-on-linux

Captured: 2026-08-17T11:50:49Z

## What was observed

The guardrail harness passes completely on the maintainer's machine and fails on the CI runner.

CI run `32026220384`, commit `a528f6a`, job `guardrails`, step `guardrail tests`:

```
FAIL eviction under concurrency: settles at or under cap (expected exit yes, got no)
FAIL ship: shellcheck absent from PATH reads not-run, verdict hold (expected exit yes yes 1, got no no 0)
total: 419 passed, 2 failed
FAILURES PRESENT
```

The same suite on the maintainer's host reports `total: 421 passed, 0 failed`, and both of those
cases print `ok` there.

**The step had never run before.** On all twelve prior runs in the surviving history,
`guardrail tests` did not fail — it was **skipped**, because the preceding step
`scripts are executable` failed first and the job stopped there. Confirmed via the Actions jobs
API: on run `32014743116` (v0.6.0) the step's conclusion is `skipped`; on run `32026220384` it is
`failure`. So the harness had never once executed on `ubuntu-latest` in the surviving history, and
these two failures were latent behind that blockage rather than newly introduced.

Because the step has only ever completed once, it is not established that these two are the only
cases that fail on Linux — only that they are the two that failed on the first run that got that
far.

## Where it surfaced

GitHub Actions, repository `HamzaAlayed/laravel-loop`, workflow `.github/workflows/ci.yml`, job
`guardrails`, step `guardrail tests` (`bash tests/guardrails.test.sh`), runner `ubuntu-latest`.

The two cases:

- `tests/guardrails.test.sh:429` — `eviction under concurrency: settles at or under cap`
- `tests/guardrails.test.sh:2520` — `ship: shellcheck absent from PATH reads not-run, verdict hold`

Not reproducible locally. The maintainer's host is macOS 26.6.1 on arm64 with
`GNU bash, version 3.2.57(1)-release`; the runner is `ubuntu-latest` with a modern bash. Note the
`shellcheck` step installs shellcheck via `apt-get` on the runner, which is not the case locally.

## When

2026-08-17T11:42:29Z — run `32026220384`, on commit `a528f6a`, the first push after
`ship-gate-blind-to-ci` unblocked the `scripts are executable` step. Noticed immediately, while
confirming H1 (A1) for that unit.

## What was already tried

- Ran `bash tests/guardrails.test.sh` on the maintainer's host: `421 passed, 0 failed`, with both
  named cases printing `ok`.
- Read the CI failure output and extracted both failing case names with their expected-versus-got
  strings, quoted above verbatim.
- Queried the Actions jobs API for step conclusions on run `32014743116` and run `32026220384`,
  which established that `guardrail tests` was `skipped` on the earlier run and had therefore
  never executed on the runner before.
- Located both cases by line number in the harness.
- Traced which commit introduced each case (see below).
- Recorded the outcome in `docs/loop/ship-gate-blind-to-ci/log.md` as H1 attempted and A1 left
  open.
- **No fix attempted. No cause assigned.** Neither case has been read for why it might behave
  differently on Linux, and no hypothesis is recorded here.

## Suspected unit or commit

No cause is established, so no unit is blamed. Two followable references, one per case, being the
commit that introduced each:

- `eviction under concurrency: settles at or under cap` — commit `5799d86`, "S4: bound the cost
  ledger, evict oldest-first, keep it out of git".
- `ship: shellcheck absent from PATH reads not-run, verdict hold` — commit `1813cb0`, "Add Ship
  gate runner with three declared gates (S1)", the unit at
  `docs/loop/ship-observe-automation/`.

Whether either case, or the code it exercises, is the thing that is wrong is `unknown`. The two
cases are unrelated to each other as far as anything observed here shows.

`docs/loop/ship-gate-blind-to-ci/` is the unit that revealed this by unblocking the step. It did
not cause it — its own step concluded `success` on the same run.

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance
criteria, no non-goals, and no slices**; nothing builds from it directly.
