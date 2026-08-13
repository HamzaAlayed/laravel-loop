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
