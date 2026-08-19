# Intent — guardrail-suite-transient-red-after-merge

Captured: 2026-08-19T21:11:25Z

## What was observed

`tests/guardrails.test.sh` reported `total: 512 passed, 1 failed` / `FAILURES PRESENT` on one
run, immediately after merging `resumed-invocation-never-reaches-the-ledger`'s `RV` group into
`main`. Four subsequent runs of the identical committed tree reported `total: 513 passed, 0
failed` / `ALL GREEN`.

**Which case failed is not known.** The failing run's output was piped through `tail -2`, so
the `  FAIL <desc> (expected exit …, got …)` line was discarded before it could be read. That
is a gap in the record, not a property of the fault, and it is the reason this capture cannot
say more.

Standing at **1 red in 5 samples** on commit `a30010a`, all five on the same host.

The lane that produced the four merged commits reported `513 passed, 0 failed` in its own
worktree before the merge.

## Where it surfaced

The maintainer's host — `Darwin 25.6.0` arm64, bash 3.2.57, `jq` and `python3` and `grep` all
present, per the suite's own `environment:` line. Run from
`/Users/developer/Downloads/laravel-loop-repo` on `main` at `a30010a`, in the same shell
invocation that had just run `git merge --no-ff` and `git worktree remove --force`.

Not observed in CI. Run `32288259463` on the preceding commit `f31bc1f` passed on both
`ubuntu-latest` and `macos-latest`.

## When

2026-08-19, immediately after the `RV`-group merge and before the worktree branch was deleted.

## What was already tried

- **Four further full-suite runs** on the same committed tree: all `513 passed, 0 failed`.
- **Checked the working tree**: `git status --short` empty, `git worktree list` shows only the
  main tree, so no uncommitted state and no leftover worktree.
- **Considered a known false-red**: `(S9-7) RC7` asserts `git diff -- scripts/record-cost-event.sh`
  is empty and is documented to go red against an uncommitted tree. Whether it was the failing
  case here is `unknown`, because the output was lost; the tree was committed at the time,
  which does not fit that pattern.
- **Not tried:** re-running under the same conditions as the failing run (immediately after a
  merge and a `git worktree remove --force` in one shell invocation); any per-case isolation;
  any repetition count beyond five; anything on Linux.

## Suspected unit or commit

`unknown`.

The run followed the merge of `docs/loop/resumed-invocation-never-reaches-the-ledger/`'s `RV`
group (commit `a30010a`, merging `28a4a09`, `c8d796d`, `df25b34`, `099eed0`), and today's work
also added cases from `docs/loop/cost-log-section-parse-error-on-macos-ci/` and
`docs/loop/stale-evict-lock-permanently-defeats-the-cap/`. Attributing it to any of them would
be a guess: the same tree has since run green four times, and the failing case was never
identified.

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance
criteria, no non-goals, and no slices**; nothing builds from it directly.
