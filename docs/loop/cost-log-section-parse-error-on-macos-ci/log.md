# Log — cost-log-section-parse-error-on-macos-ci

**No cause is assigned for the macOS red.** This unit closed on `spec.md` §4's route landing green
plus the instrumentation criteria, per `OQ7` — never on the CI fault's absence, which is not a
closing condition and never becomes one. The sample counts stand where `spec.md` §1 left them:
**1 red in 3 samples** on `c32daf0`, **0 divergences in 150 local iterations**. Samples, never a
rate. The green suites recorded below are further samples, not a closure.

If the fault recurs, that is a **new sighting against an instrumented library** — the parser, its
exit status and the route will be in the job log — not a regression of this unit.

## Where it came from

`guardrails-macos` went red on run `32174044661`, job `95831706325`, commit `c32daf0`
(`Release 0.6.1`), writing a `## Cost` section that reported a parse error. The same commit ran
fully green on both platforms in run `32174053652`, and a third sample was green — leaving 1 red in
3 samples, the red one being the only sighting anywhere. Never seen on `ubuntu-latest`, never on the
maintainer's host, and 0/150 local iterations diverged.

The reframe that made the unit tractable is `spec.md` §1's: the observed sentence is **one bucket
for several unrelated causes**, with every piece of evidence about which one fired discarded at
`scripts/cost-ledger-lib.sh:971`/`:973`. That reframe is independent of the sighting, and so is the
fix in §4.

## Phase 1 — Spec (G0), approved 2026-08-19 · `dea7408`

Specified in parallel with two other units and decided in one gate. Seven open questions, all
decided; `spec.md` records the cost each decision accepts.

The consequential one is **`OQ1`, decided against the spec's own recommendation**: the human chose
instrumentation **and** a fix in one unit, rather than gating remediation on a second sighting. That
is workable only because §4's route is already verified in this repository, reaches the observed
state from non-corrupt input, and is reproducible — so it has a real red-before-green. The accepted
cost is that two diffs arrive together and must stay legible separately at `G2`; the mitigation was
structural and pushed to `G1` (fix and instrumentation as **separate slices with separate tests**),
with `PF11` holding the line against a backfilled cause.

`spec.md` names that joint as the weakest in the unit rather than smoothing it over. At `G2` it held:
`PF1`–`PF6` and `PF12`–`PF15` were verified from separate evidence, and neither was read as evidence
for the other.

## Phase 2 — Slice (G1), 2026-08-19 · `b43fb20`

Cut alongside two other units: three cuts, 18 slices, two evidence gates reserved for a human.
Four slices here, ordered so the fix and the instrumentation never share a test:

- **S1** — the fix. Close `cost_scan`'s two `grep` dependencies (`:976` marker recognition, `:990`
  slug presence) with bash-3.2 builtins. `PF12`–`PF15`.
- **S2** — `cost_scan` publishes parser identity, exit status, bounded stderr, and route. `PF1`,
  `PF2`, `PF10`.
- **S3** — both reader surfaces name the route, and the `*)` arm stops borrowing `scan-error`'s
  sentence. `PF2`, `PF3`.
- **S4** — the harness stops discarding stderr and can tell degraded-correctly from
  degraded-wrongly. `PF4`–`PF6`, `OQ6`.

One open question left at `G1`, and it belonged to the builder, not the human: **`R1` — can the fix
be made without touching either parser program?** Expected yes on evidence, not asserted.

## Phase 3 — Build, 2026-08-19

| Slice | Commit | Cases | What it settled |
|---|---|---|---|
| S1 | `9ada646` | 466 → 471 → 473 | **`R1` answered yes.** Both replacements are bash 3.2 builtins: `case "$out" in *COST_N_LINES*)` for marker recognition, and a newline-sentinelled `case` for slug presence — sentinels unquoted so they stay wildcards, `"$slug"` quoted so its own glob metacharacters match literally, preserving `grep -qxF`'s exact-line fixed-string semantics |
| S2 | `0b1a452` | → ~483 | Parser identity, exit status, a 200-char bounded stderr capture, and a route, published as `COST_SCAN_*`. Route priority ordered so a signal-killed parser is not confused with an ordinary failure: no-output → failed → output-unrecognised |
| S3 | `281a468` | → ~486 | Both reader surfaces name the route; `cost-report.sh:496` was the only other line touched |
| S4 | `ab717f5` | → 489 | `writelog_run` stops discarding stderr; case (b) **strengthened** per `OQ4` — its byte-identity assertion kept verbatim and a direct assertion of run 2's own body added beside it |

Merged at `9bb5494` (S1) and `a6f90a5` (S2–S4). Neither merge commit was pushed on the day it was
made, which is why no CI run exists for either — see `verify.md`'s scope note.

**Closing `:976` alone was never an option.** It relocates the failure to `:990`, whose `no-slug`
message is a *positive claim about the ledger's contents* rather than an admission that something
could not be read — an honest degradation replaced by a confident wrong answer. `PF13` exists for
that, and both sites closed in the same commit.

## Phase 4 — Verify (G2), 2026-08-20 — **PASS**

`verify.md` carries the full pass. In short: all fifteen criteria met, suite green at
`513 passed, 0 failed`, and the two claims a build report can only assert were **re-reproduced**
against mutated libraries in a disposable copy of the tree —

- both `grep` dependencies restored → `(S1-2)`, `(S1-3)`, `(S1-4)` red;
- the marker site fixed but the slug site left grep-dependent → `(S1-3)` red with `got yes no`, i.e.
  the "no records for this unit" body printed for a slug the ledger holds. `PF13`'s confident wrong
  answer, observed rather than believed.

`PF15` held the cheap way: both parser program bodies are byte-identical across the unit,
`da280d5ff512` and `d69209aa7c5b` at `b43fb20` and at `a6f90a5` alike.

**Two limits, both about when the gate ran rather than about the code:** this pass is a **backfill**
written the day after the merge, so it reports on merged code instead of gating it; and because the
unit's own commits were never pushed, `PF14`'s real-run half is attributed to run `32366734933` on
`1bd510b` — green on both `guardrails` and `guardrails-macos` — a commit that *contains* this unit
rather than the unit's own head.

## What this unit foreclosed

- **A cause for the macOS sighting.** Not named, not nameable from this repository, and `PF11` fails
  any sentence that names one — even if the fault never recurs.
- **Retry, fallback or self-heal around a *failed* parser.** Removing a dependency from the test that
  *classifies* the parser's result is not the same thing, and `PF12` says so.
- **Reaching green by weakening a case.** `PF9` pins the case total's direction; the README literal
  rose 466 → 473 → 489 and no assertion was deleted.
- **A configurable.** Nothing shipped set, because nothing shippable was introduced: the stderr bound
  is the hard-coded literal `200`, the only numeric literal the diff adds to `scripts/`.

## What this unit did not close

- **Whether the macOS sighting recurs.** Out of scope by construction, and not a closing condition.
- **Whether §4's route is the route that fired on `c32daf0`.** Not established and not claimed.
- **An independent `G2`.** The backfill pass was run by the session that wrote this log. Reproducing
  the reds from mutated libraries is the strongest form available to a same-session pass; it is not
  an independent one.

## Cost

No records for this unit ("cost-log-section-parse-error-on-macos-ci") in the cost ledger. Not evidence the unit was free --
the ledger simply has nothing filed under this slug.

