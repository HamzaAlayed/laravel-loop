# Intent — ship-gate-blind-to-ci

Captured: 2026-08-17T09:31:20Z

## What was observed

CI has concluded `failure` on every run visible in the run history — 12 consecutive runs,
the earliest at 2026-08-13T11:36Z — including the tag and `main` pushes for v0.2.0, v0.3.0,
v0.3.1, v0.4.0, v0.5.0, and v0.6.0. Every release so far has shipped with red CI.

The failing step is `scripts are executable` in the `guardrails` job of
`.github/workflows/ci.yml`, which iterates `scripts/*.sh tests/*.sh` and exits 1 on the first
file without the executable bit. Its output on the v0.6.0 run:

```
not executable: scripts/cost-ledger-lib.sh
```

`git ls-files -s scripts/*.sh` reports `scripts/cost-ledger-lib.sh` at mode `100644`; the
other nine scripts are all `100755`.

Separately and in the same event: `bash scripts/ship-check.sh` returned `verdict: go` on the
v0.6.0 release commit, with all three of its gates reading `passed`, while CI on that same
commit read `failure`. The two gate sets are not the same set — CI runs a
`scripts are executable` step that ship-check's three declared gates do not include — so a
`go` at G3 does not currently imply CI will agree.

## Where it surfaced

GitHub Actions, repository `HamzaAlayed/laravel-loop`, workflow `.github/workflows/ci.yml`,
job `guardrails`, step `scripts are executable`. Triggered on `push` (both `main` and tag
refs). Most recent occurrence: run `32014743116` (`main`) and run `32014759781` (`v0.6.0`).

Not reproduced locally: `bash scripts/ship-check.sh` and `bash tests/guardrails.test.sh` both
pass on the maintainer's macOS host, which runs neither the executable-bit step nor CI's
`shellcheck -S warning` invocation.

## When

First observed failure in the surviving run history: 2026-08-13T11:36Z (run `31696279581`,
v0.2.0). Most recent: 2026-08-17T09:20Z (run `32014743116`, v0.6.0). Noticed 2026-08-17,
immediately after the v0.6.0 tag and push.

## What was already tried

- Ran `bash scripts/ship-check.sh` before releasing: gates 1–3 all `passed`, `verdict: go`.
- Read `.github/workflows/ci.yml` and confirmed the `guardrails` job has three steps —
  `shellcheck`, `scripts are executable`, `guardrail tests` — and that the middle one has no
  counterpart among ship-check's three declared gates.
- Compared committed file modes with `git ls-files -s scripts/*.sh`: one file at `100644`,
  nine at `100755`.
- Confirmed the same `not executable: scripts/cost-ledger-lib.sh` output on run
  `31779081999` (2026-08-14, v0.3.0) as on today's run.
- Attempted to identify which file failed the same step on the earliest run
  (`31696279581`, v0.2.0, before `cost-ledger-lib.sh` existed). The surviving log does not
  yield a filename; that run's specific cause is `unknown`.
- No fix applied. No file mode changed, no workflow edited, no gate added.

## Suspected unit or commit

Two followable references, one per half of the observation:

- File mode: commit `7992321` — "Add /cost: coverage-first cost report over the ledger (S2,
  cost-reporting-v0.3)", which added `scripts/cost-ledger-lib.sh`. CI's first confirmed
  failure on this filename is the v0.3.0 cycle.
- Gate set: `docs/loop/ship-observe-automation/` — the unit that specified and built
  `/ship` and `scripts/ship-check.sh` with its three hardcoded gates.

Whether the earliest (v0.2.0) failure shares either cause is `unknown`.

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance
criteria, no non-goals, and no slices**; nothing builds from it directly.
