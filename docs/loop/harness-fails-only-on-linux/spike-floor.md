# Spike — the floor, from the completed run's own record

**S1, `harness-fails-only-on-linux`.** Read-only against GitHub. No push, re-run, cancel, or
dispatch was performed. This finding is a read of `gh run view --log` / `gh api` output, not a
harness case — no fixture in `tests/guardrails.test.sh` can observe what happened on the runner,
and the two falsifiable checks below are stated as arithmetic over the log's own numbers rather
than as anything this suite could assert.

## The run being read

- **Run id:** `32026220384`
- **Commit:** `a528f6a` (full: `a528f6a00567df06b9965f22f17fdad52e7f84a7`) — confirmed via
  `gh run view 32026220384 --json headSha`.
- **Workflow:** `.github/workflows/ci.yml`
- **Job:** `guardrails` (job id `95376079676`)
- **Step:** `guardrail tests` (step number 5, command `bash tests/guardrails.test.sh`), conclusion
  `failure`, ran 2026-08-17T11:42:45Z–11:43:34Z.
- **Runner:** `ubuntu-latest` → resolved to image `ubuntu-24.04`, OS `Ubuntu 24.04.4 LTS`, confirmed
  from the job's own `Set up job` step log.

For context, not re-derived here as evidence: the earlier run `32014743116`'s `guardrail tests`
step is confirmed `skipped` (`gh run view 32014743116 --json jobs`, step conclusion field read
directly) — the step stopped at a preceding step on that run, so `32026220384` is the first
completed execution of the suite on this runner, exactly as `intent.md` states.

## Every case that failed on this run, quoted verbatim, traced to a line at `a528f6a`

Two `FAIL` lines appear in the step's full log (`gh run view --job 95376079676 --log`), and only
two:

1. **Line `guardrail tests` timestamp `2026-08-17T11:43:01.6614855Z`:**
   ```
   FAIL eviction under concurrency: settles at or under cap (expected exit yes, got no)
   ```
   Traced to `tests/guardrails.test.sh:429` at commit `a528f6a` (confirmed via
   `git show a528f6a:tests/guardrails.test.sh | sed -n '425,432p'`):
   ```
   429: expect "eviction under concurrency: settles at or under cap" "yes" \
   430:   "$([ "$(wc -l < "$LEDGER" | tr -d ' ')" -le "$EVICT_CAP" ] && echo yes || echo no)"
   ```

2. **Line `guardrail tests` timestamp `2026-08-17T11:43:12.6536599Z`:**
   ```
   FAIL ship: shellcheck absent from PATH reads not-run, verdict hold (expected exit yes yes 1, got no no 0)
   ```
   Traced to `tests/guardrails.test.sh:2520` at commit `a528f6a` (confirmed via
   `git show a528f6a:tests/guardrails.test.sh | sed -n '2515,2523p'`):
   ```
   2520: expect "ship: shellcheck absent from PATH reads not-run, verdict hold" "yes yes 1" \
   2521:   "$G2_NOTRUN $VERDICT_HOLD $([ "$SHIP_EXIT" -ne 0 ] && echo 1 || echo 0)"
   ```

No other `FAIL` string, `not ok`, or non-`ok`/`FAIL` case-result line appears anywhere in the
step's 599-line log between the harness's start banner (`enforce-refine-cap.sh (inner-loop refine
cap)`) and its closing tally.

## The run's reported totals

The step's own closing lines (verbatim):

```
docs (case count)
  ok   docs: README's Development section case count equals the harness's actual total

----------------------------------------
total: 419 passed, 2 failed
FAILURES PRESENT
```

`##[error]Process completed with exit code 2.` follows immediately — matching `FAIL` count 2, per
`tests/guardrails.test.sh`'s `exit "$FAIL"`.

## Reconciliation against the suite's case count at `a528f6a`

`tests/guardrails.test.sh`'s final case (`docs (case count)`, S8) is deliberately the **last** case
in the file precisely so that `PASS + FAIL + 1`, tallied at the moment that case itself runs, *is*
the suite's grand total — a static `grep -c 'expect "'` over the source undercounts because some
cases fire inside loops. That case's own assertion is `EXPECTED_TOTAL` (`PASS+FAIL+1`, counted
**before** it runs) against `README.md`'s `## Development` literal, read fresh from the checked-out
tree at `a528f6a` (`git show a528f6a:README.md` → `421 cases`, unchanged at the current commit
too, per this unit's pinned contract).

That case is reported `ok` on this run (see the excerpt above), which means, on the runner:
`EXPECTED_TOTAL (421) == README_CASE_COUNT (421)` held — i.e. **420 cases had executed and been
tallied before the final case ran**, and the final case itself is the 421st, bringing the printed
close to `419 passed, 2 failed` (419 + 2 = 421).

**Both falsifiable checks this slice's `Test set` names are satisfied:**

1. Count of enumerated `FAIL` lines above = **2**. The run's own `total: 419 passed, 2 failed` line
   has `M = 2`. **2 = 2.** ✓
2. `N + M` = `419 + 2` = **421**. The suite's case count at `a528f6a`, read from the harness's own
   last case's tally plus itself, is **421** (confirmed independently two ways: the static
   `README.md` literal at that commit, and the fact that the harness's own final case passed on
   this run, which it can only do if the count of cases executed ahead of it matches that literal
   exactly). **421 = 421 — every case executed; none is missing.** ✓

No shortfall exists to name. The runner ran the whole file, top to bottom, and every case in it
produced a result (`ok` or `FAIL`); none is absent, timed out, or silently skipped inside the step.

## The figure is a lower bound, not a count

**Two** is the number of cases observed failing on the guarding machine, and it is recorded here as
a **lower bound against run `32026220384` specifically** — not as a count for the resolved tree,
and not as a claim that no other case could fail once these two are addressed.

The reason, per `spec.md`'s *Limits on evidence* and A2: `32026220384` is **the only run in this
project's surviving history in which the `guardrail tests` step ever completed** — every one of the
twelve prior runs stopped at a preceding step (`scripts are executable`) and the suite step was
`skipped`, confirmed above for run `32014743116`. Resolving one of these two failing cases could
change ledger state, timing, or code paths that a case currently sitting *behind* it in the same
file has never been exercised past on this platform — the suite's own execution order (each `expect`
mutating shared `PASS`/`FAIL` counters and, in several sections, shared fixture state) means a case
that ran and passed today ran *after* two cases that failed, not independently of them. No inference
is drawn here about whether that risk materializes; it is named as the reason a second, larger
number cannot yet be ruled out, not as a prediction that one exists.

The proof-grade count for the **resolved tree** can only come from a future real run on the guarding
machine, after whatever fix each case's own recorded decision produces (A1, A2 — the human's,
post-merge). This document does not attempt that count and does not estimate one.

## What this document is not

- Not a diagnosis of either case's cause — that is S2's and S3's job, per case, separately.
- Not a claim that these are the only two cases that will ever fail here — see *lower bound* above.
- Not evidence produced by a container, VM, or any simulated Linux — none was used. Every figure
  above is read directly from `gh run view --log` / `gh api` output against the real guarding
  machine's real completed run.
