# Verify — recovered-figure-drops-slice-and-model (S1–S6, the whole cut)

**Verdict: CONCERNS** — every one of `RD1`–`RD11` and `OQ2` has a named covering case, all of them
run, and the full suite reproduces green. Three findings worth a human's eye, none of them blocking:
a parity gap on exactly the path `S5` added, a case from an earlier unit replaced with a weaker
assertion (justified in writing), and the `S1`/`S5` fixture clash whose G1 defect is now on record.

**Scope, declared rather than implied:**

- **Changed surface:** `scripts/cost-ledger-lib.sh` (both `_cost_scan_*` and both `_cost_slice_*`
  programs), `scripts/cost-report.sh`, `scripts/check-budget-gate.sh`, `tests/guardrails.test.sh`,
  `README.md`, `docs/loop/decisions.md`. Derived per commit: `8cf57b6` (S1), `f9043b5` (S2),
  `9f0dcfd` (S3), `0639f60` (S4), `e9e0d56` (S5), `5b6ef6a` (S6).
- **Full suite reproduced green** at `2c6a497`: `total: 464 passed, 0 failed`. `shellcheck -S warning
  scripts/*.sh` clean.
- ⚠ **Independence limit.** `S4`, `S5` and `S6` were built by the same session running this pass;
  `S1`, `S2` and `S3` were not. Every claim below was re-derived here — the red-before runs were
  re-executed against `main`'s library in an isolated tree copy — but an independent `loop-verify`
  pass would be stronger evidence for the last three slices, and this verdict does not pretend
  otherwise.

---

## Criteria, one row each

| Criterion | Verdict | Proven by, and does it run |
|---|---|---|
| **RD1** — all-transcribed unit names the model its own records carry | **MET** | `(S3-1)` reads `opus (derived)` where it read `unavailable`; `(S3-3)` holds a mixed phase where an observed model **and** `unavailable` both appear. Both run, both green |
| **RD2** — a transcribed figure's tokens land against the slice its records name | **MET** | `(S5-1)` ranks a transcribed-only invocation under the real-world range label `S1–S4`, asserted whole so a byte-level mangling of the en-dash fails; `(S5-2)` holds both rows of the mixed fixture. Red against `main`'s library, re-reproduced here |
| **RD3** — no ranking presented as complete while priced tokens sit outside it | **MET** | `(S1-2)` asserts the unattributed count and token total equal `COST_N_PRICED`/`COST_TOKENS_PRICED`; `(S1-6)` asserts the gate says the same rather than naming a largest share |
| **RD4** — a concentration statement only over an equal population | **MET, both directions** | `(S1-3)` — the string `concentration threshold` is absent while a priced invocation sits outside the ranking; `(S5-2)` — the 83 % flag **does** fire once the population is complete. Both directions asserted, which is what this criterion needs |
| **RD5** — no slice, no model → unattributed / `unavailable`, never guessed | **MET** | `(S3-2)` (transcribed, no model → `unavailable`, nothing fabricated); `(S5-3)` (counted in `COST_SLICE_UNKNOWN_PRICED`, no name invented); `(S5-4)` (a `recovered` record with no `start`/`finish` anywhere is neither ranked **nor** counted priced, exit 0) |
| **RD6** — two `recovered` records for one id still yield one of everything | **MET** | `(S3-4)` (output identical to the single-line fixture) and `(S5-5)` (every per-slice row identical, via `diff`) |
| **RD7** — observed/transcribed conflict keeps today's behaviour | **MET** | `(S5-6)` asserts the slice row carries `12102`, not `11035` and not their sum; the pre-existing `(S8-1)`/`(S8-2)` conflict cases are **unmodified** and green |
| **RD8** — a recovery-free ledger produces byte-identical output | **MET** | `(S1-5)`, `(S3-5)` and `(S5-7)` each diff a recovery-free, fully-sliced fixture against a frozen literal block. See finding 2 for the one byte-identity property that is no longer asserted |
| **RD9** — a transcribed figure stays labelled transcribed | **MET** | `(S6-4)`, both halves: the coverage sentence still reads `transcribed rather than host-observed` on a live report, and README's new restored-dimension paragraph contains **zero** occurrences of `observed` |
| **RD10** — two consumers never print different figures for one unit | **MET** | `(S1-7)` (report and gate state the same unattributed count) and `(S5-7)` (report and gate name the same top slice on the now-complete mixed fixture). Structurally underwritten by the single `cost_slice_unranked()` helper, asserted rather than left to construction |
| **RD11** — degraded environment still exits 0 and fabricates nothing | **MET** | `(S3-6)` runs the report with neither `jq` nor `python3` on `PATH` against a ledger holding recovered records: exit 0, says so, no partial report |
| **OQ2** (in scope at G0) — the rework count and share stop contradicting each other | **MET** | `(S4-1)` a real share prints, labelled a share; `(S4-2)` the false sentence is absent while the count is non-zero; `(S4-3)` the same through `write-cost-log-section.sh`, the consumer that reaches committed `log.md`; `(S4-4)` guards the two CO5 states. 1–3 verified red against `main`'s library |

## Findings

**1. Parity is not asserted on the one path `S5` added. (CONCERNS)**
`S2` exists so the suite can tell whether the two parser programs still agree, and `S2-2`/`S2-3` do
compare full reports on ledgers holding `recovered` records — but **neither of those fixtures carries
a `slice` label** (checked: their records hold only `invocation_id`, no `slice`), and `S2-5`, the only
case that diffs `cost_slice_rows`' rows directly, runs on the **recovery-free** concentration fixture.
Its own comment says as much: "the reader `S5` will teach to recognise a recovered record". So the
`SLICEROW` emission path for a transcribed figure — the code `S5` added — is exercised by each
program separately and compared by **neither**. I verified jq/python3 agreement by hand in the `S5`
lane on a mixed en-dash fixture (identical rows, `UNKNOWN=1` both), and that hand check is not a case.
Cheapest fix: one more case in `S2`'s section diffing `cost_slice_rows` jq vs python3 on `S5`'s mixed
fixture.

**2. An earlier unit's case was replaced with a weaker assertion. (CONCERNS, justified in writing)**
`S1` removed `(S4-1) CL5: … unset -> byte-identical to the pre-slice script`, which diffed the report
against `git show HEAD:scripts/cost-report.sh`. `S1`'s commit message explains it: that case was
self-referential and only ever proved the floor was a no-op "as long as nobody else ever touched
cost-report.sh again" — false the moment `S1` legitimately changed that file's output on the same
fixture. It was replaced in place, same `(S4-1)` label, with a direct assertion (the total still
prints, `not established` never appears). That reasoning holds and it is written down, so this is not
a FAIL — but the replacement is **weaker in kind**: no case now asserts that the coverage floor unset
leaves output byte-identical. If that property still matters, the durable form is a frozen literal
block, not a `git show HEAD` comparison. The unit's own pinned contract ("no lane edits, skips,
weakens or renumbers an existing case") was crossed here, which is worth a human's eye even with the
reason attached.

**3. The `S1`/`S5` fixture clash — a G1 defect, ruled on, recorded. (CONCERNS)**
`S1`'s cases encoded the pre-`S5` state as their expected value, and `(S1-3)` forbade the string
`concentration threshold` on the very fixture `S5`'s *Done when* requires the 83 % flag to fire on.
The `S5` lane stopped at `needs-decision` rather than editing another slice's guards; the human ruled
to re-point. Verified as executed: the only assertion line removed in `e9e0d56` is `(S1-3)`'s `expect`
**description**, with its expected value (`"no"`) unchanged, and the two fixtures lost only their
`"slice"` fields. All four cases still run, still green, and — checked against `main`'s library —
still green there too, which is correct for guards. Each fixture comment states it is a re-point and
why, and `decisions.md` carries the defect plus the lesson. The residue for the next cut is that
lesson, not this diff.

**4. Minor: label collision across units. (noted, no action implied)** Two distinct case families are
labelled `(S4-n)` — this unit's `S4` and `cost-ledger-blind-to-background-agents`' coverage-floor
`S4`. Descriptions disambiguate them and nothing greps the labels, so nothing is broken; it will
mislead a reader eventually.

## `Do NOT` check — clean

Per-commit diffs against each slice's out-of-bounds list. **No** change to
`scripts/record-cost-event.sh`, `scripts/record-recovered-cost.sh`, `hooks/hooks.json`,
`.claude/loop-cost.jsonl`, `.github/`, `spec.md`, or the neighbouring unit's artifacts.
`SLICEROW` still emits exactly 5 columns — checked, because a 6th would silently corrupt the gate's
`top_rinv`. The `noid` keying is untouched in both passes. No threshold shipped: no `LARAVEL_LOOP_*`
name added, the 30 % concentration figure unchanged, nothing set, commented out, or suggested.
`S6` edits nothing under `scripts/`, exactly as its envelope requires.

`OQ3` (per-row transcribed marking) and `S7` remain uncut, with no position taken in code or docs —
verified: `SLICEROW` did not grow, and `decisions.md` records no answer to `OQ3`.

## Reproduction

```bash
bash tests/guardrails.test.sh                    # total: 464 passed, 0 failed
shellcheck -S warning scripts/*.sh

# red-before for S5 and S6, in an isolated copy (never a checkout of the tree)
cp -R scripts tests hooks commands agents skills docs README.md "$TMP/"
git show main:scripts/cost-ledger-lib.sh > "$TMP/scripts/cost-ledger-lib.sh"   # pre-S5 library
cd "$TMP" && bash tests/guardrails.test.sh
#   (S5-1) FAIL (no no 1)   (S5-2) FAIL (yes no 2 no)   (S5-3) FAIL (0 0)
#   (S5-7) FAIL — RD10 half: the gate names no top slice on an incomplete population
#   (S5-4) (S5-5) (S5-6) ok — guards, green both sides, as their comments state
# with main's README.md + decisions.md in place instead:
#   (S6-1) (S6-2) (S6-3) FAIL   (S6-4) ok — the RD9 guard
```
The same copied tree reports 12 further failures that are artifacts of the copy (not a git
repository, no `.github/`, no committed file modes). They fail identically with the **unchanged**
library in place, so they sit outside the diff's blast radius and are not this unit's red.

## What this pass cannot tell you

It cannot tell you `OQ3` was answered correctly, because it was not answered — the recorded lean is
that once-per-report marking suffices, and both real units are wholly transcribed, so no mixed unit
exists yet to test that lean against. When one does, finding 1's parity case and `OQ3` both want
revisiting.

---

## Finding 4 (the `(S4-n)` label collision) — accepted, with the reason, 2026-08-18

Not fixed, and this is the decision rather than an omission. Two case families share the `(S4-n)`
prefix: this unit's `S4` and `cost-ledger-blind-to-background-agents`' coverage-floor `S4` (which has
since gained `(S4-1b)`). Renaming either family would edit case descriptions inside a **closed**
unit's section for a purely cosmetic gain, against a pinned contract whose whole point is that
existing cases are left alone. Nothing greps the labels, the descriptions disambiguate them on sight,
and the suite's own arbiter is the tally, not the naming.

What is worth doing instead, if it ever bites: any *new* unit prefixes its case labels with the unit
rather than the slice number. Recorded here so the next reader does not re-derive it, and so the
collision is on record as accepted rather than unnoticed.

## Findings 1 and 2 — closed 2026-08-18, both with a case that can fail

Recorded here so the verdict above is not read as still-open work.

- **Finding 1 (parity on `S5`'s path)** — closed by `(S2-6)` in `55f1822`: `cost_slice_rows`' rows
  **and** the unattributed count, diffed jq vs python3, on a fixture where a transcribed figure is
  the thing being ranked (one en-dash range label, one host-observed invocation, one transcribed
  invocation with no slice). Two tokens, because identical-and-empty would pass a bare diff while
  proving nothing. Mutation-tested: with the python slice program reverted to ignoring transcribed
  figures, `(S2-6)` fails while `(S2-5)` still passes — which is exactly the gap this finding named.
- **Finding 2 (byte-identity for the coverage floor's unset state)** — closed by `(S4-1b)` in
  `3624102`: a frozen literal block, the same instrument `RD8`'s cases already use, replacing the
  decaying `git show HEAD:` comparison rather than restoring it. Mutation-tested: changing
  `cache-read share: unavailable` to `not available` in `cost-report.sh` makes it fail. The pinned-
  contract crossing that finding flagged stands as recorded history; what is no longer true is that
  the property went unasserted.

**Finding 3** needs nothing further: the re-point was verified as executed, and its lesson is in
`decisions.md` for the next cut.
