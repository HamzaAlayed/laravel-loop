# Verify — cost-log-section-parse-error-on-macos-ci (S1–S4, the whole cut)

**Verdict: PASS** — all fifteen criteria `PF1`–`PF15` have named covering cases, every one of them
runs, the full suite reproduces green at `513 passed, 0 failed`, and the two claims that a build
report could only assert (`PF14`'s red-before-green and `PF13`'s relocation) were **re-reproduced in
this pass** against mutated libraries rather than taken from the commit messages.

**No cause is assigned for the macOS red.** This pass verifies the fix to the one verified route of
`spec.md` §4 and nothing else. It does not claim that route is what happened on `c32daf0`.

**Scope, declared rather than implied:**

- **Changed surface:** `scripts/cost-ledger-lib.sh`, `scripts/cost-report.sh`,
  `scripts/write-cost-log-section.sh`, `scripts/record-cost-event.sh`,
  `scripts/record-recovered-cost.sh`, `tests/guardrails.test.sh`, `README.md`. Derived from the
  range `b43fb20..a6f90a5`: `9ada646` (S1), `0b1a452` (S2), `281a468` (S3), `ab717f5` (S4), with
  merges `9bb5494` and `a6f90a5`. 766 insertions, 20 deletions across 7 files.
- **Full suite reproduced green** on this host (`Darwin 25.6.0` arm64, bash 3.2.57):
  `total: 513 passed, 0 failed`. That total is the tree as it stands today, not the unit in
  isolation — three later units have landed on top of it.
- ⚠ **This gate ran after the merge, not before it.** `a6f90a5` was merged 2026-08-19; this pass was
  written 2026-08-20 as a backfill. It can report what is true of the merged code; it could not and
  did not gate the merge. Nothing below is phrased as if it had.
- ⚠ **No CI run ever existed for this unit's own commits.** `9bb5494` and `a6f90a5` were unpushed
  until 2026-08-20, so `gh run list --commit` returns nothing for either. `PF14`'s
  real-run half is therefore satisfied by run `32366734933` on `1bd510b` — a pushed commit that
  *contains* this unit — green on **both** `guardrails` and `guardrails-macos`. That is a weaker
  attribution than a run of the unit's own head, and is recorded as such rather than smoothed over.

---

## Criteria, one row each

| Criterion | Verdict | Proven by, and does it run |
|---|---|---|
| **PF1** — a degraded read records parser, exit status, bounded stderr | **MET** | `(S2-2)` jq stub exits 3 → `scan-error`/`jq`/`3`/`parser-failed` with stderr captured; `(S2-5)` the bound holds at ≤200 chars, first chunk not last; `(S4-5)` a stub's unique stderr token reaches the degraded section and appears nowhere under `docs/loop/` |
| **PF2** — "parse error" stops being one bucket | **MET, per route** | One case per forceable route: `(S2-2)` parser-failed, `(S2-3)` parser-output-unrecognised, `(S2-4)` parser-no-output (signal-killed, nothing on either stream). `(S3-1)` reads the route back off the body. The `*)` arm was read directly: `write-cost-log-section.sh` no longer prints `scan-error`'s sentence for an unrecognised state |
| **PF3** — a degraded write is visible to whoever ran it | **MET, both directions** | `(S3-2)` degraded: stderr names the slug and the route, exit still 0. `(S3-3)` ok: stderr silent, exit 0, section byte-identical to the pre-change script's rendering. Both directions asserted, which is what this criterion needs |
| **PF4** — degraded-correctly vs degraded-wrongly | **MET, both directions** | `(S4-2)` an unparseable-in-part ledger still writes the section, counts the unrecognised lines as skipped, fabricates no total, exits 0. `(S4-3)` over the *valid* mixed fixture the degraded sentence is absent from **both** runs. The negative direction is the half that makes this criterion mean anything, and it is present |
| **PF5** — when case (b) goes red its own output carries the evidence | **MET** | `(S4-4)` asserts captured stderr plus the run's own body together name parser, exit status and route. The `s4_case_b_evidence()` helper prints run 1 and run 2's exit, stderr and full body, and fires only on failure — read at `tests/guardrails.test.sh`, and gated by `if [ -n "$S4_DIFF_B" ]` |
| **PF6** — the next occurrence is diagnosable from the run's output alone | **MET** | Same `(S4-4)`, plus `(S3-1)`: parser identity, exit status and route are all text in the output. Verified by reading the mutant runs' own output in this pass — the three questions were answerable from `mutA.out` without re-running anything |
| **PF7** — the two parser programs still agree | **MET** | Neither program changed at all (see `PF15`), so parity cannot have been broken by this unit. `new_jq_absent_path()` survives at `tests/guardrails.test.sh:3082` and `(S2-3)` exercises the real `python3` fallback with `jq` absent |
| **PF8** — nothing already guaranteed regresses | **MET** | Suite green at 513/0 with every prior case unmodified. `(S1-5)` a broken parser still yields the parse-error body and still exits 0; `(S4-2)` the four route variables stay empty on an ok read; `(S4-5)` no ledger content under `docs/loop/` (DL7/H1); case (b)'s byte-identity and `## Budget events` survival assertions both still present and green (DL4) |
| **PF9** — no case weakened, total does not go down | **MET** | README's case-count literal: **466** at `b43fb20` → **473** after S1 → **489** after S2–S4. Never down. The one `expect` line the diff removes is case (b)'s byte-identity assertion **relocated verbatim** (same title, same empty expectation) 30 lines down so the evidence helper can run first — and `(S4-1)` was **added** asserting run 2's own body directly. Strengthened, exactly as `OQ4`/`PF9` require. Checked by reading the diff, not by trusting the commit message |
| **PF10** — nothing ships set; an unchanged path is byte-identical | **MET, with one thing named** | `(S3-3)` and `(S3-5)` assert the ok body and `/cost`'s ok output byte-identical to the pre-change script's rendering. `(S4-2)` asserts the four route variables are empty on an ok read. No configurable was introduced at all: `grep -rE '\$\{COST_SCAN_[A-Z_]+:-' scripts/ tests/` returns only reader-side fallbacks to the literal `unavailable`, never a knob a human sets. **Named rather than glossed:** the stderr bound is the hard-coded literal `200`, the only numeric literal the diff adds to `scripts/`. `PF1` requires a bound, so a constant is the honest form; there is no threshold shipping set because there is no threshold |
| **PF11** — the fix is never written up as an explanation of the CI sighting | **MET** | Commit messages `b43fb20..a6f90a5` searched for every claim-shape (`fix(es) the macos`, `resolves/closes the macos`, `macos parse error is fixed`): zero hits. Same search over `README.md` and `CHANGELOG.md`: zero hits. This file and `log.md` are written to the same rule and say so in their own first lines |
| **PF12** — the state test no longer reports a parse error over input it never examined | **MET, reproduced** | `(S1-2)`: under `new_grep_absent_path()` the mixed fixture writes the **ok** body — coverage sentence, partial total, rework count — and never the parse-error sentence. Re-reproduced red in this pass: see Reproduction below |
| **PF13** — the failure is not relocated to the slug test | **MET, reproduced, both directions** | `(S1-3)` the present slug is never reported `no-slug` and its own figure is present; `(S1-4)` the negative direction — absent, strict-substring, and glob-metacharacter slugs are **all** `no-slug`, so the replacement has not become unconditionally true. `PF13`'s demand that this be shown red against a `:976`-only fix was re-executed here, not accepted on the commit message's word |
| **PF14** — the fix has a reproduced red before it | **MET locally, CI half attributed to a later commit** | Red-before re-reproduced in this pass against a mutated library (below). The real-run half rests on run `32366734933` / `1bd510b`, both jobs green — not on a run of this unit's own head, which never existed. Stated in Scope above |
| **PF15** — the fix does not edit either parser program | **MET, preferred outcome** | Both program bodies are **byte-identical** across the unit. Extracted by line range at both revisions and hashed: `_cost_scan_jq_program` 201 lines, `da280d5ff512` at `b43fb20` and at `a6f90a5`; `_cost_scan_py_program` 217 lines, `d69209aa7c5b` at both. The only diff at the call sites is `2>/dev/null` → `2>"$stderr_file"` |

## Findings

**None blocking. None non-blocking either.** Every criterion carries a case that can fail, and the
two criteria whose evidence is an experiment rather than a case were re-run here. The two limits
worth a human's eye are both in Scope and both are properties of *when this pass ran*, not of the
code: the gate is a backfill, and the CI attribution is to a commit that contains the unit rather
than to the unit's own head.

## `Do NOT` check — clean

Read against all four slices' `Do NOT` lists: neither parser program edited (`PF15`, hashed above);
no threshold or configurable shipped set; no case relaxed, skipped, quarantined or renumbered
(`PF9`, README literal rose 466 → 473 → 489); no ledger content written under `docs/loop/`
(`(S4-5)` asserts it); no cause assigned for the macOS sighting anywhere in the diff or its
messages.

## Reproduction

Everything below was run in this pass, in a disposable copy of the tree at
`git archive HEAD | tar -x` — never in a checkout of the working tree, and never by editing the
repository.

```
# Control arm first, in the same disposable copy, pristine library:
#   total: 513 passed, 0 failed   ALL GREEN
# (the control matters: before `git init` in the copy, 7 unrelated cases failed on
#  `not a git repository` alone. Without the control those would have been misread
#  as mutation damage.)

# Mutant A — both grep dependencies restored (pre-change equivalent), S2-S4 instrumentation intact:
#   marker test  -> grep -c 'COST_N_LINES'
#   slug test    -> grep -qxF "$slug"
#   total: 510 passed, 3 failed
#     FAIL (S1-2) grep-less PATH: ... never the parse-error sentence
#     FAIL (S1-3) grep-less PATH: the present slug is never reported no-slug ...
#     FAIL (S1-4) grep-less PATH: absent / substring / glob-metacharacter slugs are ALL no-slug
#   -> PF12 and PF14's red-before, reproduced rather than asserted.

# Mutant B — marker test left FIXED, slug test alone grep-dependent (a ":976-only fix"):
#   total: 511 passed, 2 failed
#     FAIL (S1-2)
#     FAIL (S1-3) ... (expected exit `no yes`, got `yes no`)
#   -> the "no records for this unit" body WAS printed for a slug the ledger holds,
#      and that slug's figure was absent. PF13's confident wrong answer, reproduced.
```

`(S1-1)`, the PATH-fixture self-check, and `(S1-5)`, the broken-parser-still-degrades case, stay
**green under both mutants** — as their own comments predict. A mutation that reddened those two as
well would have meant the fixture was broken rather than the mechanism demonstrated.

## What this pass cannot tell you

- **Whether the macOS sighting recurs.** Nothing here bears on that. `spec.md` §1's sample counts
  stand unchanged: **1 red in 3 samples** on `c32daf0`, **0 divergences in 150 local iterations** —
  samples, never a rate. The green suite reproduced above is one more sample, not a closure.
- **Whether the fixed route is the route that fired on `c32daf0`.** Not established, not claimed,
  and not establishable from anything in this repository.
- **Anything about `ubuntu-latest`'s behaviour under a grep-less PATH beyond the run's own colour.**
  `32366734933`'s `guardrails` job is green, which says the cases pass there; it does not
  independently observe the mechanism on that platform.
- **Independence.** This pass was run by the session that also wrote `log.md` beside it. The
  red-before-green runs were re-executed from mutated libraries rather than believed, which is the
  strongest form available to a same-session pass, but it is not an independent one.

If the CI fault recurs, that is a **new sighting against an instrumented library** — the parser, its
exit status and the route will be in the job log — not a regression of this unit.
