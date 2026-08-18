# Verify — cost-reporting-v0.3

**First pass: FAIL.** `scripts/check-budget-gate.sh`'s `LARAVEL_LOOP_BUDGET_WARN`/`_HARD` disable messages embedded numeric examples ("e.g. 150000" / "e.g. 400000") immediately adjacent to the variable names — a default dressed up as a suggested value, violating **G0-D1** (the decision the human explicitly overruled `loop-spec`'s recommendation to defer, in order to ship). No harness case caught it because the existing digit-adjacency negative case (from S8) scanned README only, never the script itself. Everything else in the first pass was proven clean by independent reproduction (see below).

**Fix:** removed the numeric examples, matched S5's own `--phase` mode wording ("Accepted form: digits only." — no example), added a harness case scoped to the script's own source, corrected a now-stale case count.

**Second pass: PASS.** Fix confirmed directly (not on the builder's report): both messages now read identically to the correct pre-existing pattern, the new regression-guard case is scoped correctly, no scope creep in the diff (`README.md`/`CHANGELOG.md` touched only for case-count corrections), no new violation introduced, no test weakened or removed.

## Independently reproduced (not taken on faith), across both passes

- **BG1** — with both budget env vars unset, a run against a ledger far over any plausible threshold produces zero bytes of output and exits 0. Verified live, not just via test assertion.
- **BG2** — the actual parsing logic (not just the message) was already correct: `400k`, `4e5`, `-1`, `1.5`, `" 100"` all disable loudly and never arm the gate.
- **X4/BG13** — `scripts/record-cost-event.sh` byte-identical to its pre-unit state across the entire unit, confirmed via `git diff`.
- **CV1/CV6** — `Coverage:` genuinely appears before any token total in real `/cost` output against hand-built fixtures, not just harness fixtures.
- **BG6** — project-wide grep for reassurance strings ("within budget", "under budget", `✓`) as *emitted* output: none found.
- **S6/S7 file-region boundary** — read `commands/loop.md` directly; step 3/4 (S6) and step 5 (S7) regions are genuinely disjoint.
- **DC1/DC2/DC3** — none claimed satisfied anywhere; all three explicitly stated as open, human-owned conditions in CHANGELOG.
- All three `/ship` gates green throughout (harness, shellcheck -S warning, version consistency).

## Known non-blocking flake

`FS1: unfiltered 'php artisan test' from loop-build warns on stderr` fails intermittently (~1/15 runs), first flagged by S3's builder, reproduced independently by both verify passes and the conductor. Not a regression from any slice — reproduces against the unmerged S2 baseline too. Filed as follow-up, not investigated further this unit.

## Concerns noted, not blocking

- A stale header comment in `check-budget-gate.sh` claims BG1's unset-check happens "before it reads the hook payload," but the code reads stdin first — functionally harmless (output is still zero bytes either way), just an inaccurate comment for a future reader.

---

## Both concerns closed 2026-08-18

**The stale header comment in `check-budget-gate.sh` — fixed, in 0.3.1.** `scripts/check-budget-gate.sh:14-18`
now reads *"With both `LARAVEL_LOOP_BUDGET_WARN` and `LARAVEL_LOOP_BUDGET_HARD` unset or empty, this
reads stdin (`INPUT="$(cat)"`) and then exits on the very next check"* — which is what the code does.
`CHANGELOG.md`'s 0.3.1 entry records it. Nothing outstanding.

**`FS1`'s intermittent failure — fixed in 0.3.1, and re-checked today.** The flake was root-caused
there to the case's own doubly-nested capture pattern racing under bash 3.2, not to
`warn-full-suite.sh`, which provably wrote its warning on every run; the fix collapsed each case to a
single invocation with one flat capture. The comment above the case
(`tests/guardrails.test.sh`, the `R4.4` section) records 1,000 consecutive clean runs at the time.

Re-checked here rather than trusted from that record: **10 consecutive full-suite runs** on a frozen
snapshot of `e59215c`, `Darwin 25.6.0` arm64, bash 3.2.57.

- Every run: `total: 460 passed, 5 failed` — **identical, run to run, with zero variance**. A flake
  is variance; there is none across ~4,650 case executions.
- **No `FS`-numbered case failed in any run**, and neither did the `(b) … byte-identical across the
  second run (DL4, CV7)` case that went red once on CI (see
  `docs/loop/cost-log-section-parse-error-on-macos-ci/intent.md`).
- The 5 failures are artifacts of running from a **copy** rather than the working tree: the two `H4`
  cases need a git repository, the two `check-script-modes` cases need committed file modes, and the
  `(e)` step-region case reads the repo's own history. All five pass in the real tree, where the same
  commit reports `466 passed, 0 failed`.

The verdict above stays as history. What changed is that neither follow-up is open, and the flake
note should no longer be cited as a live risk.
