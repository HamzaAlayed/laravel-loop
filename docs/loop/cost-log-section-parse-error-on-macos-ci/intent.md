# Intent — cost-log-section-parse-error-on-macos-ci

Captured: 2026-08-18T19:10:00Z

## What was observed

`tests/guardrails.test.sh`'s case **`(b) the file is byte-identical across the second run (DL4,
CV7)`** failed on the `guardrails-macos` job while every other case in that run passed
(`total: 464 passed, 1 failed`).

The case runs `scripts/write-cost-log-section.sh` twice against one fixture and diffs the file.
The first run wrote the full `## Cost` section. The **second** run replaced it with:

```
Could not read the cost ledger (parse error). Nothing recorded for this unit -- not
evidence it was free.
```

so the reported diff is `17,27c17,18` — eleven lines of coverage / tokens / rework replaced by that
two-line statement. The fixture's ledger is written by the case itself and holds four records with
fixed `ts` values, so nothing in its input changed between the two invocations.

The script's own behaviour on that path looks correct as observed: it degraded, said so, and exited
0. What is not established is why the parse succeeded on the first invocation and not on the second.

## Where it surfaced

GitHub Actions, `CI` workflow, job `guardrails-macos` (`macos-latest`), step `guardrail tests
(macos)` — run `32174044661`, job `95831706325`, on commit `c32daf0` (`Release 0.6.1`).

Not observed on `ubuntu-latest` in any run to date. Not observed on the maintainer's host.

## When

2026-08-18T19:00:29Z (the failing assertion's own log timestamp). First and so far only
occurrence: the same commit `c32daf0` ran fully green on both platforms in run `32174053652`
(tag `v0.6.1`, `total: 465 passed, 0 failed`), and `55f1822` — identical harness and scripts —
ran green on both platforms in run `32173406965`.

## What was already tried

- **Isolated local reproduction, 150 iterations**: the case's fixture built from scratch,
  `write-cost-log-section.sh` run twice, files diffed, each iteration in a fresh
  `CLAUDE_PROJECT_DIR`. **0/150 diverged** on `Darwin 25.6.0` arm64, bash 3.2.57. Script at
  `/private/tmp/.../scratchpad/dl4-repro.sh` (session scratch, not committed).
- **Read the failing job's log** to establish what the second run actually wrote, rather than
  inferring it from the diff's line numbers.
- **Checked the repository's own records** for a prior sighting: no `verify.md` or `log.md`
  mentions this case failing, and the one flake already on record
  (`docs/loop/cost-reporting-v0.3/verify.md`, `FS1: unfiltered 'php artisan test' …`) is a
  different case with a different mechanism.
- **Re-ran the failed job** for a further sample on the same commit: run `32174044661` re-run
  reports `total: 465 passed, 0 failed` on **both** platforms. So on commit `c32daf0` the macOS
  job now stands at **1 red in 3 samples**, and the red one is the only sighting anywhere.
- **Not tried:** anything that would establish which parser ran on each invocation, whether
  `jq` or `python3` was the one that failed, or whether runner resource pressure was involved.
  No cause is assigned here.

## Suspected unit or commit

`unknown`.

The case, the script and the library it reads are all touched by recent work — `0639f60`
(`docs/loop/recovered-figure-drops-slice-and-model/`, S4, which changed the rework figures this
section prints) and `e9e0d56` (S5) — and `(S4-3)` in that unit asserts this same script's output.
But the identical tree ran green on both platforms twice, including once on this very commit, so
attributing it to either commit would be a guess. Recorded as unknown deliberately.

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance criteria, no
non-goals, and no slices**; nothing builds from it directly.
