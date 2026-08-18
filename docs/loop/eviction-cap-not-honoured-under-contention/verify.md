# Verify — eviction-cap-not-honoured-under-contention (fix group, S4–S7)

**Verdict: CONCERNS** — all nine criteria are now met, `E2` included (second pass below, on a real
pushed commit), and every figure reproduces. The verdict stays CONCERNS on two recorded findings, not
on a criterion: one case in `S5`'s set is green against the pre-change script where its brief forecast
red, and `E8`'s cross-document comparison is inconclusive by its own admission.

**Scope, declared rather than implied:**

- **Changed surface:** `scripts/record-cost-event.sh`, `tests/guardrails.test.sh` (eviction section
  and one case in the rework section), `README.md` (`## Development` literal + the ledger paragraph),
  `docs/loop/eviction-cap-not-honoured-under-contention/measure-e8-after.md`, `docs/loop/decisions.md`.
  Derived from `git show --name-only` over `3079ab9` (S4), `6c38cbf` (S5), `ecad22e` (S6), `d5d55e2` (S7).
- **Full suite reproduced green** at `2c6a497`: `total: 464 passed, 0 failed`. `shellcheck -S warning
  scripts/*.sh` clean.
- ⚠ **Independence limit.** This pass was run inline by the same session that built `S5`–`S7`, not by
  an independent `loop-verify` agent. Every figure below was re-derived here rather than taken from a
  build report, and the red-before was re-reproduced against the merged cases — but a verifier who did
  not write the code would be stronger evidence, and this verdict does not pretend otherwise.

---

## Criteria, one row each

| Criterion | Verdict | Proven by, and does it run |
|---|---|---|
| **E1** — the cap's property is written down, with the moment it holds at | **MET** | `S4`'s conjoined docs case (`S4: eviction header states the cap's property …`) — runs, green, flattens the header first so the multi-line sentence is greppable. Independently checked: `grep -rn "hard cap"` finds the phrase only in the **budget gate's** unrelated wording (`scripts/check-budget-gate.sh:417`, `commands/loop.md:63`) and in this unit's own docs — never in the ledger mechanism, which is `E1`'s actual scope |
| **E2** — green on both guarding platforms, on a real pushed commit | **MET — see the second pass below** | Run `32173406965` on `55f1822`: `guardrails` (`ubuntu-latest`) and `guardrails-macos` both report the eviction convergence case `ok` and both report `total: 465 passed, 0 failed` — identical, which is `A4`'s shape. It was unmet at the first pass, when nothing had been pushed; no local run was ever offered as a substitute |
| **E3** — the change is falsified before it is believed | **MET, re-reproduced here** | The **merged** case (f) run against `git show d883886:scripts/record-cost-event.sh` in an isolated tree copy: **red** (`expected yes yes, got yes no` — the hole constructed, no convergence), and green in the merged tree. The Bash-arrival case is red the same way (`got 20 no 0` against cap 15). Trial counts and shas in `S5`'s commit message; `S2`'s independent 5/5 remains the prior falsification of the hole itself |
| **E4** — no green run read as a rate | **MET** | `measure-e8-after.md` contains **zero** `%` characters; `decisions.md` carries `one green run is one sample` verbatim. Every trial figure is `N/M` or an ms count with `n=20` stated |
| **E5** — `L7` is not traded silently | **MET (first branch — `L7` unrevised)** | Case (g)'s whole block is **byte-identical** pre-`S4` vs `HEAD` (md5 `f1067344…` both sides) and green. `diff` of the `L7`-guarantee and `L9`-precedence lines shows exactly one changed line, and it is the duplicate-finish **discard comment** `S5` legitimately extended — not the guarantee, not the precedence. `E5`'s second branch never opened |
| **E6** — nothing already guaranteed regresses | **MET** | Every pre-existing eviction case name survives at `HEAD` — (a), (b), the poll case, the `mv`-failure case (h), and all three non-numeric-cap cases — with (f) replaced **in place**, keeping its letter and position. `git show … -- tests/ \| grep '^-'` returns exactly one removed assertion: (f)'s old single-token `expect`, replaced by a two-token one that asserts strictly more. Suite total rose (440 → 464), never dropped |
| **E7** — no new threshold, default, or suggested value | **MET** | The group's script diff introduces **no** `LARAVEL_LOOP_*` name; the only numeric literals added are `=0` and `=1` (the `CAP_TRIP_EMITTED` flag). Nothing configurable, nothing suggested |
| **E8** — cost measured where it is paid, not asserted | **MET, with a limitation the record already states** | `measure-e8-after.md`: three arms plus the second obliged arrival site, each with n, mean, median, min, max, and a same-driver interleaved before/after control. See finding 2 |
| **E9** — the `L7` answer recorded so it is not re-litigated | **MET** | `decisions.md`'s second-G1 entry (property 3, class 3, five obligation classes foreclosed) plus `S7`'s build-out entry (seven placement foreclosures, each with its reason and `S6`'s figures) |

No criterion is collapsed into another, and none is claimed on "the code looks right".

## Findings

**1. `S5`'s case (i) is green against the pre-change script, where its brief forecast red. (CONCERNS)**
The envelope said cases 1–3 "have no code path at all" today. Reproduced: case (f) is red and the
Bash-arrival case is red, but **`arrival trim never waits` passes against `d883886`** — with no
arrival trim at all, "returns fast" and "leaves the over-cap ledger untrimmed" are both trivially
true. It is still a legitimate guard rather than an assertion that cannot fail: a polling arrival
trips its elapsed-time token, and one that trimmed while the lock was held trips
`NOWAIT_STILL_OVER`. But it guards a regression, it does not prove the fix, and the brief's forecast
was wrong for that one case. Worth a line in the unit's record so a future reader does not cite it
as red-before evidence.

**2. `E8`'s cross-document comparison is inconclusive, as `measure-e8-after.md` §4 states. (CONCERNS,
already disclosed)** Arms (a) and (b) measured here sit **below** `spike-oq2-bound-at-rest.md` §4's
observed min for the same arms, in the same direction — `S1` records *that* wall clock was taken, not
with what. The same-driver control substituted for it is the falsifiable comparison, and the
substitution is stated in the file rather than smoothed over. Closing this needs `S1`'s instrument
reconstructed; it does not change any verdict above.

**3. A G1 defect in the neighbouring unit, surfaced by this group's landing order. (recorded, not
this group's fault)** Noted here only because it is where a reader will look: the
`recovered-figure` unit's `S1` cases and its `S5` envelope contradicted each other on one fixture.
Ruled on by the human at that lane and recorded in `decisions.md`; it is that unit's finding, not
this one's.

## `Do NOT` check — clean

Diffed per commit against `S4`–`S7`'s out-of-bounds lists. **No** change to
`scripts/record-recovered-cost.sh`, `scripts/ship-check.sh`, `.github/`, `hooks/hooks.json`,
`docs/loop/checks.md`, `spec.md`, the three `spike-*.md` files, or
`docs/loop/recovered-figure-drops-slice-and-model/`. `S6` and `S7` are markdown-only, exactly as
their envelopes state. No case was weakened, deleted, skipped, relettered, renumbered or reordered.
No absolute case count was pinned from `slices.md` — each lane recomputed the literal from `main`
(446 → 449 for `S5`), and the harness's own last case is green on it.

One thing to name rather than praise: `S5`'s commit also fixed the `converge_ledger()` factoring
*and* the two arrival call sites in one commit. That is what its envelope specified, so it is not
scope creep — checked, not assumed.

## Reproduction

```bash
# full suite, merged tree
bash tests/guardrails.test.sh                     # total: 464 passed, 0 failed
shellcheck -S warning scripts/*.sh

# E3, red-before, in an isolated copy (never git checkout of the tree)
cp -R scripts tests hooks commands agents skills docs README.md "$TMP/"
git show d883886:scripts/record-cost-event.sh > "$TMP/scripts/record-cost-event.sh"
cd "$TMP" && bash tests/guardrails.test.sh       # eviction convergence: FAIL (yes no)
                                                  # arrival trim (Bash): FAIL (20 no 0)
```
The same copied tree reports **12 further failures** that are artifacts of the copy, not of the diff:
it is not a git repository (`check-ignore`, `git status` cases), has no `.github/` (ci.yml extraction
and checks.md parity cases), and carries no committed file modes (`check-script-modes.sh` cases).
Established by the isolation ladder — they fail identically with the **unchanged** script in place, so
they are outside the diff's blast radius and are **not** this group's red.

## What this pass cannot tell you

It cannot tell you `E2` will be green. The mechanism converges on this host, by construction and by
measurement; the guarding platforms have said nothing yet, and one green run from them will be one
sample.

---

## Second pass — `E2` met on a real pushed commit

`main` was pushed at `55f1822` (36 commits, the first push since `bb3c23b`). CI run
**`32173406965`**, both jobs green:

| Job | Runner | Eviction convergence case | Arrival cases | Total line |
|---|---|---|---|---|
| `guardrails` | `ubuntu-latest` | `ok  eviction convergence: a lock-losing last appender leaves the ledger over cap at rest, and it converges as soon as ANY later arrival appends nothing` | `arrival trim never waits`, `arrival trim boundary`, `arrival trim: a passing Bash event over cap` — all `ok` | `total: 465 passed, 0 failed` |
| `guardrails-macos` | `macos-latest` | same case, `ok` | same three, all `ok` | `total: 465 passed, 0 failed` |

The two `total:` lines are **identical**, which is what `A4`'s cross-job comparison asks for, and
`shellcheck` plus `scripts are executable` passed on both runners.

**Read this as one sample, because that is what it is (`E4`).** One green run on each platform is one
observation per platform, not a rate and not proof that the failure class is gone. The case it
exercises is deterministic — it constructs the lock-hold rather than racing for it — which is why a
single green run is meaningful here at all; a timing-dependent case would need many.

The prior two pushed runs (`32117525156`, `32113202275`) are red in this history and stay red: the
first is the observation that opened this unit, the second is `A1`'s recorded failure from the unit
before it. Neither is retroactively fixed by this run, and this record does not present them as
resolved.

**Unchanged by the push:** findings 1 and 2 above. They are why this verdict reads CONCERNS rather
than PASS.