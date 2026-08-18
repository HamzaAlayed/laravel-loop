# Verify — cost-ledger-blind-to-background-agents

**Unit:** cost-ledger-blind-to-background-agents  **Slice:** S1–S10 (S11 approved-but-held, not built — out of scope, and confirmed not built)

**Verdict:** PASS — scoped to the changed surface (7 files: `README.md`, `docs/loop/decisions.md`, `docs/loop/cost-ledger-blind-to-background-agents/slices.md`, `scripts/cost-ledger-lib.sh`, `scripts/cost-report.sh`, `scripts/record-recovered-cost.sh` (new), `tests/guardrails.test.sh`), full harness reproduced green (404 cases, up from 334 at unit start), two independent spot-checks confirm red-before-green was real rather than claimed.

## Acceptance criteria

| Criterion | Proven by | Status |
|---|---|---|
| CL1 (reason per unpriced invocation, from `status` only) | `tests/guardrails.test.sh` S1 cases (1)(2)(3), `~L950-970`: async_launched→"launched in background, outcome never observed", completed+no tokens→"observed, no usage figure", line_too_long→"truncated" | Proven |
| CL2 (a launch is not a finish; in-flight statement never a bare 0 when backgrounded invocations exist) | S1 case (5): in-flight line names the 2 backgrounded invocations inline, never printed as bare "... unpriced." | Proven |
| CL3 (report states why the gap exists) | S3 cases 1–3 (`~L1345+`): statement appears only with a backgrounded invocation present, absent otherwise, appears exactly once for three such invocations | Proven |
| CL4 (coverage as a share + wholly-unobserved phases named) | S2 cases (S2-1)(S2-2)(S2-3): percentage in `cost_coverage_sentence()`, build named when it has invocations and zero priced, a phase with zero invocations not named | Proven |
| CL5 (human-set coverage floor; below it, no total) | S4 cases 1–6 (`~L1441+`): unset byte-identical, above-floor suppresses total and states "not established", at/below prints as today, unparseable disables loudly naming field+value, no interaction with CV6's all-unpriced case | Proven |
| CL6 (gate's notice carries the same share/phase names) | S2 case (S2-4): gate's partial-coverage notice carries the identical 50%/build clause via the shared `cost_coverage_sentence()` formatter | Proven |
| CL7 (no imputation — a ledger with 2 priced + 20 unpriced totals identically to 2 priced alone) | Characterisation case, `~L1410-1439`: `total priced tokens` and `COST_N_PRICED`/`COST_TOKENS_PRICED` identical with and without the 20 unpriced records | Proven |
| CL8 (v0.3's CV1–CV8/BG1–14/PE1–6 continue to hold, existing cases pass unmodified) | `git diff 841fc54..HEAD -- tests/` shows **0 deleted lines** in `tests/guardrails.test.sh`; full suite 404/404 green | Proven |
| CL9 (pre-v0.4 records read without error, not reclassified) | S1 case (6): finish with no `status` field → "reason not stated", never folded into "backgrounded"; S7 case 5: pre-existing ledger with no `recovered`-shaped record reads unchanged | Proven |
| RC1 (exactly-once; count property + write property) | Count: S7 cases 2 & 6 (two `recovered` records for one id → one invocation, one figure); Write: S9 cases 1 & 2 (`mkdir` marker refuses a second write) | Proven |
| RC2 (recovered figure permanently distinguishable) | S7 case 3 (report labels the figure transcribed, distinguishable from host-observed) + `token_source:"transcribed"` field pinned in the record shape (never on any other record) + README §"Cost ledger" states "model-transcribed, not host-observed" | Proven |
| RC3 (disagreement: both shown, neither silently wins) | S8 cases 1–4 (`~L1131+`): both figures + source + stated rule on disagreement; equality is not a disagreement; total unaffected by conflict presence | Proven |
| RC4 (recovery failing changes nothing, asserted per case) | S9 cases 3–6 (`~L1228+`): unknown invocation_id, non-numeric tokens, missing argument, `LARAVEL_LOOP_COST_LEDGER=0` — each refuses, writes nothing, exits 0 | Proven |
| RC5 (a recovered invocation counts as priced everywhere) | S7 cases 1 & 4: figure enters `COST_TOKENS_PRICED`, coverage share and wholly-unobserved phase list both shift accordingly | Proven |
| RC6 (no-recovery run is indistinguishable from today) | S7 case 5, S8 case 4, S9 cases 3–6 all assert byte-identical / zero-counter output with no recovery activity | Proven |
| RC7 (ledger writer's observe-only contract unchanged) | `git diff 841fc54..HEAD -- scripts/record-cost-event.sh hooks/hooks.json` is **empty** (0 lines) — neither file appears anywhere in the unit's diff; `record-recovered-cost.sh` is not referenced in `hooks/hooks.json` (read directly, confirmed) | Proven |
| X1 (harness green above 334, shellcheck clean, executable bits) | `bash tests/guardrails.test.sh` → 404 passed, 0 failed; `shellcheck -S warning scripts/*.sh` → exit 0; `record-recovered-cost.sh` is `-rwxr-xr-x` | Proven |
| X2 (three existing guards unchanged) | Full suite includes all `block-untested-commit.sh`/`enforce-refine-cap.sh`/`warn-full-suite.sh` (FS-prefixed) cases, all green, none modified (0 deletions in test diff) | Proven |
| X3 (zero new dependency, jq→python3→no-op) | Read `cost-ledger-lib.sh` (`cost_scan`, `cost_invocation_lookup`) and `record-recovered-cost.sh`: both degrade `jq` → `python3` → refuse/no-op, no other dependency introduced | Proven |
| X4 (every script in hooks.json exists and is executable) | `hooks/hooks.json` names `block-untested-commit.sh`, `warn-full-suite.sh`, `record-cost-event.sh`, `check-budget-gate.sh`, `enforce-refine-cap.sh` — all present, all `+x`. `record-recovered-cost.sh` is deliberately absent from `hooks.json` (RC7) | Proven |
| X5 (README states what the ledger can/cannot see) | README lines 96–98, 112 (read directly): background-launched invocations named as "the majority of a `/loop` run", `LARAVEL_LOOP_COST_MIN_COVERAGE` named with "unset means today's behaviour", the recovery CLI named with its two arguments, no digit adjacent to the variable name | Proven |
| X6 (decisions.md's superseded bullet corrected in place) | `docs/loop/decisions.md` lines 42-48: the superseded sentence carries a dated correction citing E2, and the 4%-coverage rejection paragraph above it is untouched, word for word | Proven |
| DC4, DC5 | Explicitly **not G2 criteria** per spec.md ("harness cannot exercise the live hook path") — not verified here, and correctly out of this gate's scope | Not applicable to G2 |

## Spot-checks: red-before-green, reverted and confirmed

Reverted `scripts/cost-ledger-lib.sh` and `scripts/cost-report.sh` to their pre-unit state (commit `841fc54`) inside an isolated scratch copy of the repo (never touching the tracked working tree — `git checkout` against the real repo was correctly blocked by the sandbox's read-only enforcement), kept `tests/guardrails.test.sh` at HEAD, and reran the full harness:

- **373 passed, 31 failed.** Every failure maps exactly onto a CL/RC criterion from S1, S2, S3, S4, S7, S8, S9 (`CL1`, `CL2`, `CL4`, `CL5`, `CL6`, `CL8`-adjacent bound, `CL9`, `RC1`, `RC2`, `RC3`, `RC4`, `RC5`, `RC6` — the named cases in the table above). Nothing unrelated broke, which is itself evidence the new tests are precise rather than coupled to incidental behaviour.
- Explicitly called out, as the two required: **S1** (`CL1`/`CL2`/`CL9` reason-categorisation cases (1)(2)(3)(6) and the in-flight case (5) all failed against the reverted lib) and **S9** (`RC1`/`RC4` cases 1, 2, 3 all failed — no writer existed to produce a `recovered` line). Both slices' "confirmed red before green" claims reproduce.

## The S4/S5 "no number ships" guard — confirmed it holds and confirmed it can fail

- **Holds today:** `grep -h 'LARAVEL_LOOP_COST_MIN_COVERAGE' scripts/*.sh README.md docs/loop/*.md | grep -cE '[0-9]'` → `0`, matching the harness's own guard case at `tests/guardrails.test.sh:1569` and the README-specific guard at `:2991`.
- **Can fail:** injected a digit onto the same line as `LARAVEL_LOOP_COST_MIN_COVERAGE` in an isolated scratch copy of `README.md` and reran the guard case alone — it failed (`expected exit 0, got 1`), confirming the assertion is not tautological.

## Blocking

None.

## Concerns (fix now or file as a slice)

None. `scripts/cost-ledger-lib.sh` (the shared library) is not executable (`-rw-r--r--`), but it is sourced, never executed directly, is not named in `hooks/hooks.json`, and was already non-executable before this unit (pre-existing state, not a regression) — noted, not a finding.

## Out-of-bounds touched

None. The diff's file set (`README.md`, `docs/loop/decisions.md`, this unit's own `slices.md`, `scripts/cost-ledger-lib.sh`, `scripts/cost-report.sh`, `scripts/record-recovered-cost.sh`, `tests/guardrails.test.sh`) matches exactly what S1–S10's `Context`/`Output` sections name. Confirmed absent from the diff: `scripts/record-cost-event.sh`, `hooks/hooks.json`, `commands/loop.md`, `agents/`, `skills/loop-protocol/` — all zero-line diffs, which is also the direct evidence that **S11 was not built**: no orchestrator instruction to auto-transcribe exists anywhere in the diff.

## Evidence

```
$ git diff 841fc54..HEAD --name-only
README.md
docs/loop/cost-ledger-blind-to-background-agents/slices.md
docs/loop/decisions.md
scripts/cost-ledger-lib.sh
scripts/cost-report.sh
scripts/record-recovered-cost.sh
tests/guardrails.test.sh

$ git diff 841fc54..HEAD -- scripts/record-cost-event.sh hooks/hooks.json | wc -l
0

$ bash tests/guardrails.test.sh 2>&1 | tail -3
total: 404 passed, 0 failed
ALL GREEN

$ shellcheck -S warning scripts/*.sh; echo $?
0

$ git diff 841fc54..HEAD -- tests/guardrails.test.sh | grep -E '^-' | grep -vE '^---' | wc -l
0        # no deleted/weakened assertions anywhere in the test diff

$ ls -la scripts/record-recovered-cost.sh
-rwxr-xr-x ... scripts/record-recovered-cost.sh

# Spot-check (isolated scratch copy, repo working tree never touched):
# lib+report reverted to 841fc54, tests kept at HEAD
$ bash tests/guardrails.test.sh 2>&1 | tail -3
total: 373 passed, 31 failed
FAILURES PRESENT
# all 31 failures map to CL1/CL2/CL3/CL4/CL5/CL6/CL9/RC1/RC2/RC3/RC4/RC5/RC6
# cases from S1, S2, S3, S4, S7, S8, S9 -- confirms red-before-green

# Guard non-tautology check (isolated scratch copy):
$ grep -n LARAVEL_LOOP_COST_MIN_COVERAGE README.md   # after injecting a digit
... e.g. 40 ...
$ bash tests/guardrails.test.sh 2>&1 | grep 'guard) no digit'
FAIL (guard) no digit shares a line with LARAVEL_LOOP_COST_MIN_COVERAGE ... (expected exit 0, got 1)

$ bash scripts/check-budget-gate.sh --phase verify --unit cost-ledger-blind-to-background-agents
(no output — LARAVEL_LOOP_BUDGET_PHASE_VERIFY unset, per protocol no flag is ever printed in that case)
```

## Scope declared

Verified: the full CL/RC/X criteria set against fixtures, via the harness reproduced directly (not accepted from the build report); the `Do NOT` lists of all ten slices via diff inspection; two independent red-before-green spot-checks (S1, S9) beyond the two requested, in an isolated scratch copy that never mutated the tracked working tree; the `LARAVEL_LOOP_COST_MIN_COVERAGE` no-number guard's genuineness.

Not verified (explicitly out of scope per spec.md, not a gap in this pass): DC4 and DC5, which require a real `/loop` run with background lanes and a human's own eye — the harness cannot exercise the live hook or transcript path, and the spec says so itself. S11 was confirmed *not built* (correct — it was held, not approved) rather than evaluated against criteria, since none apply to it. `cost-measurement-v0.2`'s DC1 and `cost-reporting-v0.3`'s DC2/DC3 remain open per the spec and are not addressed by this verify pass.

---

## DC4 and DC5 — confirmed by the maintainer 2026-08-17, after this verdict was written

The note above records `DC4` and `DC5` as "not verified (explicitly out of scope per spec.md)". That
is no longer the state of the record and this file should not be read as though it were: `spec.md`
now carries both as `[x]` with maintainer confirmations dated **2026-08-17**, which postdate this
verdict.

- **`DC4`** — confirmed against the `ship-gate-blind-to-ci` run: seven backgrounded invocations, all
  recorded `async_launched` and unpriced, with the coverage output accounting for them at every
  point.
- **`DC5`** — confirmed with seven of seven figures transcribed by hand from their own completion
  notifications, coverage moving 0 % → 100 % for that unit, every figure permanently labelled
  `transcribed rather than host-observed`. The maintainer accepted an orchestrating agent's reading
  of the notifications as satisfying "the human saw" for that check.

Two things worth carrying forward rather than treating as closed by those ticks:

1. **`DC5`'s comparand is not on disk.** Completion notifications live in a session, not in the
   repository, so a correctly transcribed figure and an invented one are indistinguishable from the
   ledger alone. The 21 recovered records were written in three batches (7 within one second, 14
   across two), which is consistent with one agent writing them from its own context — exactly what
   `spec.md` records the maintainer accepting. Anyone wanting `DC5` as machine-checkable evidence
   needs a run where the notification figures are captured independently at the time.
2. **The run `DC4` was confirmed against no longer reproduces that state.** `ship-gate-blind-to-ci`
   now reads 100 % covered, because recovery records were appended at 2026-08-17T11:38:13 — after
   the check. Two other real units (`eviction-cap-not-honoured-under-contention`, 8 invocations, and
   `recovered-figure-drops-slice-and-model`, 6) still sit at 0 % coverage, so the `DC4` output can be
   re-read against a genuinely backgrounded run without new instrumentation.
