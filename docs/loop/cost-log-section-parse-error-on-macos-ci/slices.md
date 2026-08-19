# Slices — cost-log-section-parse-error-on-macos-ci

Cuts `spec.md` (G0 held and approved 2026-08-19, commit `dea7408`) into **four code slices**, cut so
that **the fix and the instrumentation are separate slices with separate tests** — `OQ1`'s accepted
cost, and the one thing G0 said this gate owes that the spec could not do for itself.

**4 slices · parallel set: EMPTY (a finding, not an omission) · critical path S1 → S2 → S3 → S4**

`S1` is the fix (`PF12`–`PF15`). `S2`–`S4` are the instrumentation (`PF1`–`PF6`). They never share a
commit, and no lane's evidence is admissible for the other's criteria.

## The G0 decisions this pass is cut against

Restated so no slice re-derives them and no slice reopens them.

| Question | G0 decision (not reopened by any slice here) |
|---|---|
| **OQ1** — instrumentation only, or a fix as well? | **Both, in one unit**, decided against the spec's own recommendation. The accepted cost is that two diffs arrive together; the mitigation is **structural and belongs to this gate** — separate slices, separate tests, separate evidence ledgers. `S1` is the fix and owns nothing else; `S2`–`S4` own no part of it. |
| **OQ2** — always-on, or configurable? | **Always-on, degraded path only.** No new environment variable anywhere in this unit (pinned below), so `PF10`'s "ships unset" clause is **vacuous here and said so** rather than left looking unmet. |
| **OQ3** — library or harness? | **Both**, and neither presumes where the fault is. `S2`/`S3` are the library-and-reader half; `S4` is the harness half. |
| **OQ4** — new harness cases, and run 2's body asserted directly? | **Yes to both.** `S4`. Strengthening is permitted by `PF9`; weakening is not, under any colour. |
| **OQ5** — how much of `PF2`'s route set must be forced? | **Force what a stub parser on `PATH` can force; record the rest as unforced, naming what was tried.** `S2` carries this, and it is load-bearing twice over — see *The three readings* below. |
| **OQ6** — one environment line at suite start | **Yes**, identical in shape on both platforms, and it must not change either job's case totals (`A4`). `S4`. |
| **OQ7** — superseded by `OQ1` | The unit closes on §4's route landing green plus the instrumentation criteria. **The CI fault's absence is not a closing condition and never becomes one** (`PF11`). |
| **R1** — can the fix avoid both parser programs? | **The builder's, at the start of `S1`.** Expected yes. The *no* branch is written into `S1`'s envelope as an explicit stop, not a footnote — see the third reading below. |

---

## The three readings this pass makes — flagged, not buried

Each is a place where a builder reading a criterion literally would produce something worse than
what the criterion is for. Each is stated here so the human can overturn it in one place.

### 1. The parser's stderr must never be written into `log.md` — `PF1` vs `H1`/`DL7`

`PF1` wants "a bounded capture of what [the parser] wrote to its own stderr" available as evidence.
**`jq` and `python3` both quote the offending input in their error messages.** So a stderr capture
rendered into the `## Cost` section body would put **ledger content under `docs/loop/`** — which
`PF8` forbids outright (`DL7`/`H1`, asserted today by case (d) at `tests/guardrails.test.sh:3775-3781`).

Read here as: the **section body** carries the parser identity, the parser's exit status and the
route — never the captured stderr text. The **stderr capture surfaces on streams only**: the
script's own stderr (`PF3`) and the harness's output (`PF5`/`PF6`). `PF1`'s own wording supports
this ("the evidence available", not "the section"), and `PF3` names *slug and route* for the write
that announces itself, not the parser's stderr.

This is the single easiest way for a green `S2`+`S3` to break a criterion `S1` never touched, so
`S4` carries a case that asserts it directly: a stub parser whose stderr contains a unique token
must leave that token absent from every file under `docs/loop/`.

### 2. "The input was genuinely unparseable" is distinguishable **by the captured stderr**, not by its own label

`PF2` names five routes, one of which is *the input was genuinely unparseable*. Reading the parser
programs: unrecognised lines are **counted** (`COST_N_SKIPPED`, `cost-ledger-lib.sh:95`) rather than
failed on, and `jq -Rn` reads raw lines — so garbage in the ledger produces `ok` **with a skipped
count**, not `scan-error`. An "unparseable ledger" fixture therefore does not reach the degraded
path at all on today's parsers.

Read here as: the library's route vocabulary describes **what was observed** — which parser ran,
what status it exited with, whether its output carried the marker — and never infers **whose fault**
it was. An input that genuinely defeats a parser arrives as `parser-failed`, and the captured
stderr is what tells a reader the input was at fault. `PF4`'s unparseable-ledger case is written
against that: it establishes by reading whether *any* portable input makes both parsers exit
non-zero, and if none does, it records the route as **unforced under `OQ5`** and asserts the honest
alternative (garbage lines are counted as skipped and the read is `ok`) rather than inventing a
label nothing can reach.

**If the human disagrees**, option 2 at the gate is: `S2` ships a fifth route value that only a
human-typed fixture can ever produce, and `S4` records it as unforced. That is strictly more code
for strictly less evidence, which is why it is not the recommendation.

### 3. `S1` closes the caller-recognition route rather than labelling it

`PF2`'s fourth route is *the caller's own recognition step could not run* — today forcible, by the
`grep`-less `PATH` of `tests/guardrails.test.sh:2770-2775`. **`S1` removes that forcing condition:**
after it, the recognition is a bash builtin `case`, with no pipe and no external tool, and no
portable way to make it fail is known.

Read here as: the route is satisfied **by elimination plus the unrecognised-state arm**. `S2` ships
no label for it; `S2`'s finding states that `S1` closed it, what was tried to force it afterwards,
and that any state the caller does not recognise is now caught by `build_section_body`'s `*)` arm
saying *so* (`S3`) rather than by a route value nothing can produce.

**This is also the whole reason the fix goes first** — see *The seam*.

---

## The seam — the fix, and why it is first

**`S1` — stop reporting a parse error over input nobody examined.** Smallest change that delivers
observable value: on any machine whose `PATH` cannot resolve `grep`, a valid ledger and a present
parser stop producing a false parse error and produce the unit's real figures. That is value to a
reader on every platform, on the one route in this unit that has a **reproduced red before it**
(`PF14`), and it is deliverable with or without `S2`–`S4`.

Three reasons the order is fix-first rather than instrument-first, and the second is decisive:

1. **The fix's evidence needs no instrumentation.** `PF14`'s red is "the section says parse error
   where it should say the figures". Legible with today's output.
2. **Instrument-first would ship a case the fix must then delete, and `PF9` forbids that.** The only
   forcing condition for `PF2`'s caller-recognition route is a `grep`-less `PATH` — exactly what
   `S1` closes. An `S2` that landed first would add a case forcing that route, and `S1` would then
   have to weaken or remove it one commit later. Ordering the other way is not a preference; it is
   the difference between a route recorded as **closed** and a case recorded as **retired**.
3. **`S2`'s route vocabulary is honest only once the route set is settled.** Naming a route in one
   commit and eliminating its only cause in the next is how a vocabulary ends up describing a
   library that no longer exists.

The alternative order (instrumentation first, so the fix's red is observed *with* the instruments in
place) was considered and not taken: it buys a richer red for a red that is already unambiguous, and
pays for it with a retired case in the file `decisions.md` calls the most dangerous in the
repository.

**Not a layer habit.** Every dependency below is stated with its type — *textual* (same region, same
literal) or *semantic* (this slice renders or asserts what that one produced). A `Depends on` with no
type attached reads as a missed parallel lane, and there is exactly one place in this cut where the
dependency is only textual: it is named as such.

---

## Order and concurrency

```
S1  the fix: neither :976 nor :990 depends on grep          ← riskiest
    lib + harness (+5)
 └─→ S2  the library captures parser identity, status, bounded stderr, route
     │   lib + harness (+6)
     └─→ S3  both reader surfaces name the route; a degraded write says so on stderr
         │   write-cost-log-section.sh + cost-report.sh:496 + harness (+5)
         └─→ S4  the harness carries the evidence into its own failure output
                 harness only (+5), incl. OQ6's environment line
```

**Parallel set: empty.** Four reasons, each of which alone forces the sequence:

- **`S1` → `S2`** is *semantic* (reading 3: `S2`'s vocabulary is written against the post-fix route
  set, and instrument-first would ship a case `S1` must retire) **and textual** (both edit
  `cost_scan`'s `:968-996` region and both move `README.md`'s case-count literal).
- **`S2` → `S3`** is *semantic*: `S3` renders variables `S2` sets. A reader surface cannot print a
  route the library does not publish.
- **`S3` → `S4`** is *semantic* for two of its five cases (they assert sentences `S3` introduces) and
  *textual* for the rest (same harness section, same literal).
- All four share `tests/guardrails.test.sh` and `README.md`'s `## Development` case-count literal,
  whose value the harness's own **last** case asserts. Two lanes moving that number conflict by
  construction, and the loser's merge leaves the suite red on a case its diff never touched.

Stating the empty parallel set plainly **is** the finding: this unit is four sequential merges, and
any plan promising otherwise is promising a rebase.

---

## Case-count deltas — pinned as DELTAS, never as an absolute

⚠ **A sibling unit is being sliced concurrently** (`resumed-invocation-never-reaches-the-ledger` and
`stale-evict-lock-permanently-defeats-the-cap` both hold an approved `spec.md` with no `slices.md`).
`README.md`'s literal reads **466 cases** as this is written, and the absolute at any lane's build
time is **not knowable here**. A pinned absolute would be wrong the moment a neighbour merges.

| Slice | Δ cases | What produces it |
|---|---|---|
| **S1** | **+5** | 1 `PATH`-fixture self-check + 4 behaviour cases (`PF14`'s red-before, `PF13`'s discriminator, the slug test's negative direction, the marker test can still fail) |
| **S2** | **+6** | 1 stub-parser fixture self-check + 3 route cases (pairwise over parser × route) + `ok`-path silence + the stderr bound |
| **S3** | **+5** | degraded body names the route · degraded write announces on stderr · `ok` write silent and byte-identical · the `*)` arm's own sentence (static, prove-it-can-fail) · `/cost`'s degraded sentence names the route |
| **S4** | **+5** | case (b) strengthened with run 2's body asserted directly · the unparseable-input case · the degraded-sentence-absent case · the evidence capture returns the three facts · `H1` under a stub parser whose stderr carries a ledger-like token |
| **group** | **+21** | |

**Build-time computation rule, binding on every lane:**

1. Merge local `main` in first (`docs/loop/conventions.md`, *Confirm a lane's base*).
2. Read the live literal from `main`, never from this document:
   `sed -n '/^## Development/,/^## /p' README.md | grep -oE '[0-9]+ cases'`.
3. Write `that number + this slice's delta` back into the same line. Nothing else in `README.md`
   changes — not the ledger paragraph, not the agent list, not the cost documentation.
4. The arbiter is the harness's own **last** case, `docs (case count)`
   (`tests/guardrails.test.sh:4877-4891`), whose `PASS + FAIL + 1` must equal the new literal. Green
   there is the proof; this table is only a forecast.
5. **New cases go before that last case**, which stays last in the file — its arithmetic is the
   grand total only if it runs last, as its own comment says.
6. A lane whose **honest delta differs** (a conjoined case split in two, a case that fires in a loop)
   states the real delta in its return and computes the literal from it. The table is not a licence
   to write the wrong number.

Either landing order against a neighbour survives **because of** this rule, not because of
scheduling luck. That is the property; the recommendation below is only a preference.

---

## Pinned contracts

Decided here because discovering any of them at build time costs a rewrite. **A builder that
believes one is wrong returns `needs-decision` rather than changing it.**

| Contract | Value | Why it is pinned |
|---|---|---|
| `COST_SCAN_STATE`'s value set is **frozen** | Exactly `ok`, `absent`, `empty`, `no-slug`, `no-parser`, `scan-error`. No slice adds, renames, or removes a value. The route is carried in **new variables**, never in the state | `scripts/check-budget-gate.sh:168` and `:342` both match the literal `no-parser\|scan-error` to **exit early and fail safe**. A new state value falls through both arms, and the gate would then read a degraded scan as a readable one and compute a total from zeroed variables — a confident wrong figure in the one surface that can print a breach |
| New variable names | `COST_SCAN_PARSER` (`jq`\|`python3`\|empty), `COST_SCAN_PARSER_STATUS` (the parser's exit status; empty when none ran), `COST_SCAN_PARSER_STDERR` (bounded, newline-collapsed; empty when it wrote nothing), `COST_SCAN_ROUTE` (empty on every non-degraded state). All reset by `_cost_reset_scan_vars` like every existing scan variable | Three consumers source this library. Two lanes inventing two names for one fact is the `_cost_scan_*` vs `_cost_slice_*` divergence class in a new costume |
| Route vocabulary | Exactly three values, plus empty: `parser-no-output` (produced nothing — did not start, was killed, or wrote nothing), `parser-failed` (exited non-zero), `parser-output-unrecognised` (exited zero, output lacked `COST_N_LINES`). **No `input-unparseable` value and no `caller-recognition-failed` value** — readings 2 and 3 | A label nothing can produce is dead code that reads as coverage |
| The vocabulary describes observations, never blame | A route names what was observed. Whether the *input* or the *parser* was at fault is read from the captured stderr, by a person | Reading 2. An inferred label is a claim this unit is not allowed to make |
| The stderr capture never reaches a file under `docs/loop/` | Section body: parser identity, exit status, route. Streams only (script stderr, harness output): the bounded stderr text | Reading 1 — `H1`/`DL7`, and `jq`/`python3` both quote the offending input |
| The capture bound | Hard-coded: newlines and tabs collapsed to single spaces, then truncated to the **first 200 characters**. Commented in place as *a capture bound, not a threshold*. **No environment variable, ever** | `PF10` greps the diff for new environment names and numeric literals, so the one literal in this unit has to arrive already explained |
| No new configurable, anywhere | Zero new environment variables in all four slices. `PF10`'s "ships unset and provably does nothing" clause is therefore **vacuous here**, and a lane says so rather than writing a case that cannot fail | `OQ2` (always-on) plus the standing all-five-unset rule, which governs thresholds and defaults — not diagnostics |
| Both parser programs stay byte-identical | `_cost_scan_jq_program` and `_cost_scan_py_program` are **not edited by any slice**. `git diff main -- scripts/cost-ledger-lib.sh` must show no line inside either function | `PF15`, and the build-order coupling: `resumed-invocation-never-reaches-the-ledger`'s `RS10` rebases onto a known state, not a half-moved one |
| The `R1` "no" branch stops the lane | If `S1` concludes a parser program must change, it writes `spike-r1-parser-programs.md` in this directory **first** and returns `needs-decision`. It does not proceed | Stricter than `PF15`'s letter, deliberately — see *Residual questions*. `PF15` states byte-identical as the **expected** outcome, and a builder editing that neighbourhood also changes what the next unit rebases onto |
| Exact-line, fixed-string slug matching is preserved | Whatever replaces `grep -qxF` at `:990` matches a **whole line, literally**. A slug that is a substring, prefix, suffix, or glob of a present slug is **not** present | `grep -qxF` is exact-line + fixed-string. A hand-rolled `*"$slug"*` is a silent widening, and its failure mode is `no-slug` never firing — a figure reported for a unit the ledger holds nothing for |
| `tr` at `cost-ledger-lib.sh:310` is out of bounds | Same class of dependency, named in the spec's non-goals so it is not a surprise, **not** so it is folded in. Every lane's `Do NOT`. It must stay *resolvable* in every fixture `PATH` below, because `cost_coverage_sentence` needs it for an `ok` body | A separate observation is the route for it. A lane that "also fixed `tr`" has widened the diff in the most dangerous file in the repository |
| `scripts/check-budget-gate.sh` is untouched | Not its two state arms, not its stderr message, not its thresholds | Its arms are the fail-safe above. No criterion names it, and its message prints only when a human has set a threshold — none is set |
| `PATH` fixtures are built by symlinking **everything resolvable**, minus one name | `new_grep_absent_path()` (`S1`) skips only `grep`; `new_stub_parser_path()` (`S2`) shadows only `jq` (or `python3`) with a stub. Both follow `new_jq_absent_path()`'s shape (`tests/guardrails.test.sh:2777-2792`) | The curated-allow-list version of this fixture is exactly what produced the finding at `:2770-2775`: a sparser `PATH` makes the library report a parse error and the case passes for the wrong reason |
| One helper, defined once | `S1` defines `new_grep_absent_path()`; `S2` defines `new_stub_parser_path()`; `S3` and `S4` **reuse** `S2`'s. No lane redefines, copies, or shadows another lane's helper | Two copies of a fixture can only promise agreement |
| Every path still exits 0 | Including every degraded path, in both scripts | The script's own header, and the spec's non-goal *not making the degraded path fail* |
| No retry, fallback, or self-heal | No re-invocation of the parser, no fall from `jq` to `python3` on a **failed** run (as opposed to an absent binary), no re-scan before printing. `S1` removes a dependency from the test that **classifies** the parser's result; that is not licence to re-run the parser | The spec's non-goal, restated because `PF12` is the one criterion a builder could misread as permission |
| Counts, never rates | Every trial figure is `N/M`, one trial is one sample. No percentages, no "usually", no "intermittent" | `PF11`, and the standing discipline this repository applies to the single sighting |
| No sentence claims the macOS cause | No commit message, code comment, case description, return, or markdown line says or implies that this unit's fix explains the red on `c32daf0` | `PF11`, which fails **even if the fault never recurs** |
| The repository's own `.claude/` | Never written to by any lane. Every fixture runs against a throwaway `CLAUDE_PROJECT_DIR` | The real ledger is other units' evidence |
| Pre-change library versions | Obtained read-only via `git show <rev>:scripts/cost-ledger-lib.sh > "$TMP/..."`. **No `git checkout`, no branch, no stash, no reset** of the working tree | A lane that moves the tree can lose another lane's work and silently change what "pre-change" means mid-experiment |
| Nobody pushes | No lane pushes, dispatches, re-runs, cancels, or tags. `PF14`'s second half — both jobs' output on a real pushed commit — is the **human's**, after the group merges | Only a real run on a guarding platform proves a claim about the guarding checks |

---

## Slices

Envelopes are verbatim build briefs.

### S1 — Stop `cost_scan` reporting a parse error over input it never examined, at both `grep` sites
```
Owner:       loop-build
Unit:  cost-log-section-parse-error-on-macos-ci
Slice: S1
Context:     - docs/loop/cost-log-section-parse-error-on-macos-ci/spec.md SS4 in full (the fix's
               entire evidence base), PF12, PF13, PF14, PF15, and the failure-mode rows for
               "grep cannot be resolved" (three of them, with three different expected answers).
             - scripts/cost-ledger-lib.sh cost_scan() (:954-997) in full. The two lines this
               slice closes and nothing else:
                 :976  if ! printf '%s' "$out" | grep -q 'COST_N_LINES'; then
                         COST_SCAN_STATE="scan-error"
                 :990  if ! printf '%s\n' "$COST_SLUGS_PRESENT" | grep -qxF "$slug"; then
                         COST_SCAN_STATE="no-slug"
               These are the ONLY two grep invocations in the file; cost_slice_rows and
               cost_lookup perform no recognition test of this kind.
             - tests/guardrails.test.sh:2769-2776 -- the comment recording this route as
               VERIFIED on 2026-08-18, and new_jq_absent_path() at :2777-2792, whose shape the
               new PATH helper follows.
             - tests/guardrails.test.sh:3674-3684 (writelog/writelog_exit/writelog_stderr) and
               the cost-log-fixture at :3686-3712 -- four records, one priced spec invocation
               marked rework, one unpriced build invocation. This is PF14's fixture; do not
               build a new one.
             - scripts/write-cost-log-section.sh print_ok_body (:78-92), print_no_slug_body
               (:105-108), print_scan_error_body (:113-116) -- the three bodies these cases
               distinguish between.
             - scripts/cost-ledger-lib.sh:310 -- the `tr` in cost_coverage_sentence. OUT OF
               BOUNDS, and the reason every fixture PATH below must still resolve `tr`: an ok
               body cannot be produced without it.
Constraints: - FIRST, ANSWER R1 BY READING, BEFORE WRITING ANYTHING: can both the marker
               recognition and the slug-presence test be expressed with bash 3.2 builtins
               only? Expected yes (`case "$out" in *COST_N_LINES*)` for the first; a case over
               a newline-sentinelled list, or a while-read loop, for the second).
               IF THE ANSWER IS NO: write
               docs/loop/cost-log-section-parse-error-on-macos-ci/spike-r1-parser-programs.md
               recording what you read and why the shell cannot carry it, and RETURN
               `needs-decision`. Do not edit either parser program. PF15 states byte-identical
               as the expected outcome and resumed-invocation-never-reaches-the-ledger rebases
               onto that state -- so that outcome is a human's call, not a builder's.
             - THE SLUG TEST KEEPS grep -qxF's EXACT SEMANTICS: whole line, literal string. A
               slug that is a substring, prefix, suffix, or glob pattern of a present slug is
               NOT present. Getting this wrong makes no-slug unreachable, and an unreachable
               no-slug means figures reported for a unit the ledger holds nothing for -- worse
               than the bug being fixed, and INVISIBLE to the two ok-asserting cases below.
               Case 4 exists for exactly this and is not optional.
             - CLOSE BOTH SITES IN ONE COMMIT. PF13: a fix at :976 alone relocates the failure
               to :990, whose `no-slug` message is a POSITIVE CLAIM about the ledger's contents
               ("the ledger simply has nothing filed under this slug") rather than an admission
               that something could not be read.
             - REMOVE A DEPENDENCY, DO NOT ADD A MECHANISM. No retry, no re-invocation, no
               fallback from a FAILED parser to the other one, no re-scan. PF12 is about the
               test that classifies the parser's result, never about the parser.
             - Do not touch _cost_scan_jq_program or _cost_scan_py_program. `git diff main --
               scripts/cost-ledger-lib.sh` shows no line inside either function (PF15).
             - Do not add a route variable, a state value, or any instrumentation. S2 owns all
               of it, and a G2 reader must be able to read this diff as the fix and nothing
               else (OQ1's accepted cost).
             - COST_SCAN_STATE's value set is unchanged. With `grep` present, every state this
               function can return is byte-identical to today's for every input.
             - PF7 IS CHECKED BEFORE THIS IS BELIEVED: run the full suite normally AND with
               `PATH="$(new_jq_absent_path)"` so the real python3 fallback is exercised, and
               report both `total:` lines in your return.
             - Case count: +5. Compute README's literal from `main` at build time per the rule
               in slices.md; never from a number written in any document.
             - bash 3.2 only; `shellcheck -S warning scripts/*.sh` clean; every path exits 0.
             - Commit on the worktree branch you are already on, and commit before returning.
Output:      scripts/cost-ledger-lib.sh (:976 and :990 only), tests/guardrails.test.sh (+5 cases
             and one new helper), README.md (the `## Development` case-count literal only).
Done when:   With a PATH that resolves the parser but not `grep`, the existing cost-log-fixture
             produces the SAME ok body it produces today with `grep` on PATH -- and a slug the
             ledger genuinely does not hold still produces `no-slug`, a ledger whose parser
             genuinely fails still produces a parse error, and a slug that is merely a
             substring of a present one is still absent.
Test set:    5 cases. Selection rule: one per way the two replaced tool calls can be got wrong,
             INCLUDING THE TWO DIRECTIONS EACH TEST MUST STILL DISCRIMINATE IN -- because every
             criterion-named case here asserts an `ok` body, and a fix that made both tests
             pass unconditionally would satisfy all of them. The set is not a re-slice signal:
             PF13 forbids splitting the two sites across commits, so its size is forced by the
             criterion rather than by the file.
               1. fixture self-check: new_grep_absent_path() resolves bash, awk, mktemp, mv,
                  tr and jq-or-python3, and does NOT resolve grep -- asserted directly, under
                  the exact PATH the cases below use. A PATH fixture that silently resolved
                  grep would make cases 2-5 pass for the wrong reason        [OQ5's discipline]
               2. PF14's RED-BEFORE-GREEN: the cost-log-fixture under that PATH writes the ok
                  body -- the coverage sentence, `60787 (priced subset only, partial -- 1
                  unpriced`, and the rework count -- and NOT the parse-error sentence
                                                                              [PF12, PF14]
               3. PF13's DISCRIMINATOR: the same run does not write the `No records for this
                  unit` body, and the slug-filtered figure is present. MUST BE SHOWN RED
                  AGAINST A :976-ONLY FIX (patch a temp copy of the pre-change library with
                  the :976 change only, run this case against it, record the red)      [PF13]
               4. the slug test still discriminates, three tokens in one expect: a slug absent
                  from the ledger -> no-slug; a slug that is a strict substring of a present
                  slug -> no-slug; a slug containing a glob metacharacter -> matched literally,
                  so no-slug. All three under the grep-less PATH               [PF13, DL5]
               5. the marker test can still fail: a stub parser on PATH that exits non-zero
                  with no output, under the same PATH shape -> still `scan-error`, the section
                  is still written, exit 0. Proves the replaced :976 has not become
                  unconditionally true                                     [PF12, PF8/DL5]
             Fails now, and FALSIFY IT RATHER THAN ASSUMING: obtain the pre-change library with
             `git show HEAD:scripts/cost-ledger-lib.sh > "$TMP/lib.sh"` (never checkout/stash),
             run cases 2-4 against it, and record N/M reds in your return with both shas. Case
             2 is red today because :976's own grep cannot resolve and the section says
             "Could not read the cost ledger (parse error)". Case 3 is ALSO red against the
             :976-only patch, for a different reason (`no-slug`), and both reds must be
             recorded separately -- they are two different defects, not one.
             Passes after: 1-5 green; the full suite green normally and under
             new_jq_absent_path(); the existing parity cases (S2-1..S2-7, :4361-4474)
             unmodified and green.
Do NOT:      - Do not edit _cost_scan_jq_program or _cost_scan_py_program. If you conclude you
               must, write spike-r1-parser-programs.md and return needs-decision.
             - Do not touch the `tr` at scripts/cost-ledger-lib.sh:310, and do not remove any
               other external-tool dependency in the library. Out of bounds by non-goal.
             - Do not add COST_SCAN_ROUTE, COST_SCAN_PARSER, a stderr capture, or any other
               instrumentation. That is S2, deliberately in a different commit.
             - Do not add, rename, or remove a COST_SCAN_STATE value.
             - Do not edit scripts/check-budget-gate.sh, scripts/cost-report.sh,
               scripts/write-cost-log-section.sh, scripts/record-cost-event.sh,
               scripts/record-recovered-cost.sh, hooks/hooks.json, .github/, or
               docs/loop/checks.md.
             - Do not weaken, delete, skip, reletter, renumber, or reorder any existing case,
               and do not modify case (b) -- S4 owns the only permitted change to it.
             - Do not introduce an environment variable, threshold, default, or suggested value.
             - Do not write a sentence -- in code, a case description, a commit message, or your
               return -- claiming or implying this fixes the macOS red on c32daf0 (PF11).
             - Do not touch any other docs/loop/<unit>/ directory; a sibling unit is being
               sliced concurrently.
             - Do not write to this repository's own .claude/. Throwaway CLAUDE_PROJECT_DIR only.
             - Do not `git checkout`, branch, stash, or reset to obtain the pre-change library.
             - Do not pin an absolute case count from any document; compute it from main.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  nothing
```

### S2 — Make `cost_scan` record which parser ran, what happened to it, and which route produced the state
```
Owner:       loop-build
Unit:  cost-log-section-parse-error-on-macos-ci
Slice: S2
Context:     - spec.md PF1, PF2, PF7, PF10, and SS1's enumeration of the routes that collapse
               into one state today. Read slices.md's readings 1-3 before writing anything --
               all three change what this slice ships.
             - scripts/cost-ledger-lib.sh: cost_scan() (:954-997) AS S1 LEFT IT, especially
               :968-975 -- the two parser invocations that discard stderr (`2>/dev/null` at
               :971 and :973) and capture no exit status -- and _cost_reset_scan_vars, which
               every new variable must reset.
             - The three consumers of COST_SCAN_STATE, none of which this slice edits:
               scripts/write-cost-log-section.sh:119, scripts/cost-report.sh:491,
               scripts/check-budget-gate.sh:168 and :342. The last one matches the literal
               `no-parser|scan-error` to exit early and FAIL SAFE -- which is why the state's
               value set is frozen and the route is a separate variable.
             - tests/guardrails.test.sh -- the many cases that source the library directly and
               assert scan variables (e.g. :1188, :1631, :4241) as the shape for this slice's
               library-level cases; new_jq_absent_path() at :2777-2792 as the shape for the new
               stub-parser helper.
             - docs/loop/decisions.md's `_cost_scan_*` vs `_cost_slice_*` divergence class.
Constraints: - PUBLISH FOUR VARIABLES, EXACTLY AS NAMED IN slices.md's pinned contracts:
               COST_SCAN_PARSER, COST_SCAN_PARSER_STATUS, COST_SCAN_PARSER_STDERR,
               COST_SCAN_ROUTE. All four reset by _cost_reset_scan_vars. All four EMPTY on
               every non-degraded state, including `ok`.
             - THE ROUTE VOCABULARY IS EXACTLY THREE VALUES: parser-no-output, parser-failed,
               parser-output-unrecognised. No input-unparseable value (reading 2) and no
               caller-recognition-failed value (reading 3). Your finding states, in one
               paragraph in your return, that S1 closed the caller-recognition route, what you
               tried in order to force it afterwards, and that it is therefore recorded as
               UNFORCED under OQ5 rather than labelled.
             - CAPTURE THE PARSER'S EXIT STATUS FOR REAL. `local out="$(...)"` returns
               `local`'s status, not the parser's -- declare and assign on separate lines, or
               shellcheck SC2155 and a wrong status are both waiting. `set -o pipefail` is in
               force in every consumer.
             - Capture stderr to a temp file (mktemp), read it, and REMOVE IT UNCONDITIONALLY
               before returning, on every path. cost_scan runs inside a hook process
               (check-budget-gate.sh), so a leaked temp file is a leak per tool call.
             - THE BOUND: collapse newlines and tabs to single spaces, then truncate to the
               first 200 characters. Hard-coded, commented in place as a capture bound and not
               a threshold, and NO environment variable. PF10 greps the diff for new
               environment names and numeric literals, so the comment is part of the change.
             - THE STDERR CAPTURE IS FOR STREAMS, NOT FILES (reading 1). This slice publishes
               it as a variable and writes it nowhere. S3 decides what reaches log.md, and the
               answer is already pinned: never this text.
             - PF10, ASSERTED NOT PROMISED: an `ok` scan adds no byte to any consumer's stdout
               or stderr. The always-on part is the capture; the OUTPUT is degraded-path only.
             - Do not touch _cost_scan_jq_program or _cost_scan_py_program (PF15). Do not
               change parser preference: jq first, then python3, then no-parser.
             - Do not change any state value, any figure, or any existing variable's meaning.
               CV7/CV8: no second implementation of anything.
             - PF7: run the full suite normally AND under new_jq_absent_path(); report both
               `total:` lines. The parity cases at :4361-4474 stay unmodified and green.
             - Case count: +6, computed from main at build time.
             - bash 3.2 only; shellcheck clean; every path exits 0.
             - Merge local main first; commit on your worktree branch before returning.
Output:      scripts/cost-ledger-lib.sh (cost_scan's parser-invocation and recognition region,
             plus _cost_reset_scan_vars), tests/guardrails.test.sh (+6 cases, one new helper
             new_stub_parser_path()), README.md (case-count literal only).
Done when:   A degraded scan publishes which parser was selected, that parser's exit status, a
             bounded single-line capture of its stderr, and one of three route values -- and an
             `ok` scan publishes all four as empty and changes no byte of any consumer's output.
Test set:    6 cases. Selection rule: PAIRWISE over parser (jq / python3) x route
             (no-output / failed / output-unrecognised) -- the full cross-product is 6 and
             pairwise is 3, with each route appearing once and both parsers appearing across
             the set -- plus the two boundaries PF1 and PF10 name explicitly, plus the fixture
             self-check this repository requires before any PATH-forced case is believed. NOT
             taken: a case per (parser, route) pair. The parser identity and the route are
             computed independently in the same function, and six cases to cover an
             interaction that does not exist would double this section for nothing.
               1. fixture self-check: new_stub_parser_path() resolves the STUB jq (not the real
                  one), still resolves tr/awk/mktemp/grep, and `command -v jq` points inside
                  the fixture dir                                          [OQ5's discipline]
               2. jq stub exits non-zero and writes to stderr -> COST_SCAN_STATE=scan-error,
                  COST_SCAN_PARSER=jq, COST_SCAN_PARSER_STATUS=<that status>,
                  COST_SCAN_ROUTE=parser-failed, and the stderr text is present in
                  COST_SCAN_PARSER_STDERR                                          [PF1, PF2]
               3. jq absent, python3 stub exits 0 with output lacking the marker ->
                  COST_SCAN_PARSER=python3, STATUS=0, ROUTE=parser-output-unrecognised, and
                  the captured stderr empty. This is the pairwise row that proves the parser
                  identity is READ rather than assumed                             [PF1, PF2]
               4. jq stub produces nothing at all (killed by a signal) -> ROUTE=
                  parser-no-output with the signal's status recorded, distinguishable from
                  case 2's                                                             [PF2]
               5. boundary, the bound: a stub writing many lines of stderr, longer than the
                  bound -> COST_SCAN_PARSER_STDERR is one line and at most 200 characters, and
                  contains the FIRST of them (a truncation that kept the tail would discard
                  the parser's actual error)                                           [PF1]
               6. boundary, the ok path: the cost-log-fixture with the real parser -> all four
                  variables empty, and `bash scripts/cost-report.sh <slug>` byte-identical to
                  its own pre-change output (captured from the pre-change library via
                  `git show`, not asserted from memory)                          [PF10, PF8]
             Fails now: no variable in this repository names the selected parser, its exit
             status, or its stderr -- all three are discarded at :971/:973 -- and
             COST_SCAN_ROUTE does not exist, so cases 1-5 have nothing to read. Case 6 passes
             trivially today and is the regression guard for what 2-5 add; say so in its
             comment rather than presenting it as a red-before.
             Passes after: 1-6 green; full suite green normally and under new_jq_absent_path();
             the parity cases untouched.
Do NOT:      - Do not add a fifth or sixth route value, and do not invent a label for a route
               nothing can produce (readings 2 and 3).
             - Do not add, rename or remove a COST_SCAN_STATE value -- check-budget-gate.sh's
               two arms fail safe on the literals it has today.
             - Do not edit scripts/check-budget-gate.sh, scripts/cost-report.sh, or
               scripts/write-cost-log-section.sh. S3 owns the reader surfaces; this slice
               publishes facts and renders nothing.
             - Do not write the captured stderr into any file, and do not print it from the
               library at all.
             - Do not touch _cost_scan_jq_program, _cost_scan_py_program, or the `tr` at :310.
             - Do not add a retry, a re-invocation, or a fallback from a failed parser.
             - Do not introduce an environment variable, threshold, default, or suggested value.
             - Do not modify or weaken any existing case, including case (b) (S4's).
             - Do not re-do S1's fix, re-test its cases, or extend them.
             - Do not claim or imply anything about the macOS red on c32daf0 (PF11).
             - Do not touch another docs/loop/<unit>/ directory, this repository's .claude/,
               .github/, hooks/hooks.json, or docs/loop/checks.md.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  S1 -- SEMANTIC: this slice's route vocabulary is written against the route set S1
             leaves behind, and instrumenting first would ship a case forcing the
             caller-recognition route via a grep-less PATH that S1 then makes unforcible, which
             PF9 forbids retiring. ALSO TEXTUAL: same cost_scan region, same README literal.
```

### S3 — Make both reader surfaces name the route, and make a degraded write announce itself
```
Owner:       loop-build
Unit:  cost-log-section-parse-error-on-macos-ci
Slice: S3
Context:     - spec.md PF2 (the `*)` fall-through clause), PF3, PF8's DL4/DL5/DL7 list, PF10,
               and the failure-mode rows for "a degraded section is written during a real close
               step", "an ok scan", and "COST_SCAN_STATE is unset or holds an unrecognised
               value". Read slices.md's reading 1 first -- it is the constraint that decides
               what this slice may print where.
             - scripts/write-cost-log-section.sh in full (179 lines): print_scan_error_body
               (:113-116), print_no_parser_body (:109-112), print_no_slug_body (:105-108),
               build_section_body (:118-127) and ESPECIALLY its `*)` arm at :126, which today
               calls print_scan_error_body -- so an unrecognised or unset state and a real parse
               error are indistinguishable to every reader. The script prints nothing on stderr
               today except the two early-exit messages at :30 and :41.
             - scripts/cost-report.sh:491-509, and specifically :496 -- the OTHER degraded-read
               sentence, `Could not read the cost ledger (parse error). Nothing is reported,
               rather than a partial or wrong total.` No harness case asserts either
               parse-error sentence today (verified by grep), so no existing case turns red on
               a route clause.
             - scripts/cost-ledger-lib.sh -- the four variables S2 publishes. Read them; do not
               change them.
             - tests/guardrails.test.sh:3674-3684 (writelog helpers, note writelog_stderr at
               :3681 already exists), the cost-log-fixture (:3686-3712), case (f)'s BG6 sweep
               at :3796-3800, and the `(g)` prove-it-can-fail idiom at :3802-3820 -- the house
               shape for a static assertion over a script's own text.
Constraints: - THE SECTION BODY CARRIES: which parser was selected, its exit status, and the
               route, in the degraded body's own sentences. IT NEVER CARRIES THE CAPTURED
               STDERR TEXT (reading 1) -- jq and python3 both quote the offending input in
               their errors, and DL7/H1 forbid ledger content under docs/loop/. This is not a
               style preference; it is the criterion S4 asserts with a unique token.
             - THE `*)` ARM STOPS BORROWING scan-error's SENTENCE. An unrecognised or unset
               COST_SCAN_STATE gets its own body, saying that the state itself was not
               recognised and naming the value. A reader must be able to tell "the scan failed"
               from "the caller did not understand the answer".
             - PF3: a degraded write says so ON STDERR, naming the slug and the route, and
               still exits 0. An `ok` write stays SILENT on stderr -- no byte, not even a
               "wrote section" line. The exit code stays 0 on every path, degraded or not.
             - /cost's degraded sentence at cost-report.sh:496 gains the route in the SAME
               clause shape. ONE LINE, that line only, and nothing else in cost-report.sh --
               this is the second surface a human reads a degraded ledger through, and leaving
               it saying only "parse error" would preserve the exact collapse this unit exists
               to remove. (If the human strikes this at G1, drop the line and the case; nothing
               else in this slice changes.)
             - PF10/DL4: an `ok` section's bytes are IDENTICAL to today's, and log.md's other
               bytes -- `## Budget events` included -- are undisturbed. Capture today's ok
               section from the pre-change scripts via `git show` and diff against it; do not
               assert byte-identity from reading.
             - EVERY SCAN STATE STILL PRODUCES A SECTION (DL5). No state, recognised or not,
               results in a missing section or a zeroed token table.
             - Do not change any figure, any arithmetic, or the ok body's wording. CV7/CV8: the
               figures still come from the library and /cost and this section still cannot
               disagree.
             - Do not edit scripts/cost-ledger-lib.sh at all. If a fact you need is not
               published, return needs-decision rather than adding it here -- a variable added
               in this slice is an S2 change in an S3 commit, and G2 has to read the two apart.
             - Case count: +5, computed from main at build time.
             - bash 3.2 only; shellcheck clean; both scripts exit 0 on every path.
             - Merge local main first; commit on your worktree branch before returning.
Output:      scripts/write-cost-log-section.sh (the degraded bodies, a new unrecognised-state
             body, the `*)` arm, and the stderr announcement), scripts/cost-report.sh (:496
             only), tests/guardrails.test.sh (+5 cases), README.md (case-count literal only).
Done when:   A degraded `## Cost` section names which parser ran, what status it exited with,
             and which route produced the state; the person who ran it is told on stderr with
             the slug and the route; an `ok` write is byte-identical to today's and silent; and
             an unrecognised state says it was unrecognised instead of borrowing the parse
             error's words.
Test set:    5 cases. Selection rule: one per reader surface x direction -- the section body and
             /cost both on the degraded side, the section body and stderr both on the ok side --
             plus the one arm that cannot be forced and is therefore asserted statically. Each
             uses S2's stub-parser helper; none re-asserts S2's variables (S2 owns those) and
             none re-asserts S1's fix (S1 owns that).
               1. degraded body (stub parser, exit non-zero): the section names the parser
                  (`jq`), its exit status, and the route -- and does NOT contain the stub's
                  stderr text                                                 [PF2, PF1, PF8]
               2. PF3, degraded: writelog_stderr on that same run is non-empty, contains the
                  slug and the route, and writelog_exit is 0                           [PF3]
               3. PF3/PF10, ok: on the cost-log-fixture with the real parser, writelog_stderr
                  is EMPTY, exit is 0, and the extracted `## Cost` section is byte-identical to
                  the pre-change scripts' output for the same fixture           [PF3, PF10]
               4. the `*)` arm: a static assertion that build_section_body's `*)` arm calls a
                  DIFFERENT body function than its scan-error arm, with a prove-it-can-fail run
                  against a stripped temp copy first (the `(g)` idiom at :3802-3820). Stated in
                  its comment as a read, not a forced route: no input can produce an
                  unrecognised state while the library and this script agree            [PF2]
               5. /cost's degraded read: `bash scripts/cost-report.sh <slug>` under the stub
                  parser names the route, and its ok output for the fixture is unchanged  [PF2]
             Fails now: the degraded body is two sentences that name nothing; the script writes
             nothing to stderr on a degraded run (so case 2 has no output to read); and the
             `*)` arm calls print_scan_error_body verbatim (:126), so case 4's assertion is
             false by construction today. Case 3's ok half passes today and is the regression
             guard for what 1, 2 and 5 add -- say so in its comment.
             Passes after: 1-5 green; cases (a)-(i) of the cost-log section and the whole /cost
             group unmodified and green; full suite green normally and under
             new_jq_absent_path().
Do NOT:      - Do not write the parser's captured stderr into log.md, into any file under
               docs/loop/, or into the section body in any form (reading 1, DL7/H1).
             - Do not edit scripts/cost-ledger-lib.sh -- not one line, not a new variable.
             - Do not change the ok body's wording, its figures, its coverage sentence, or the
               order coverage-before-total (CV1).
             - Do not print anything on stderr for an ok write, and do not make any path exit
               non-zero.
             - Do not change anything in scripts/cost-report.sh other than the single sentence
               at :496; not print_absent, not print_no_slug, not the ok branch.
             - Do not edit scripts/check-budget-gate.sh, scripts/record-cost-event.sh,
               hooks/hooks.json, .github/, or docs/loop/checks.md.
             - Do not add a heading to log.md, change `## Budget events`, or make this script
               create log.md.
             - Do not modify or weaken any existing case, including case (b) (S4's).
             - Do not introduce an environment variable, threshold, default, or suggested value.
             - Do not claim or imply anything about the macOS red on c32daf0 (PF11).
             - Do not touch another docs/loop/<unit>/ directory or this repository's .claude/.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  S2 -- SEMANTIC: this slice renders the four variables S2 publishes, and a reader
             surface cannot print a route the library does not set. ALSO TEXTUAL: same harness
             section, same README literal.
```

### S4 — Make the harness carry the evidence, and tell degraded-correctly from degraded-wrongly
```
Owner:       loop-build
Unit:  cost-log-section-parse-error-on-macos-ci
Slice: S4
Context:     - spec.md PF4, PF5, PF6, PF9, OQ4, OQ6, and SS3 in full ("the test case is
               implicated") -- the three things it establishes about the harness today.
             - intent.md -- what the one sighting actually left behind, and why a person had to
               read the raw job log to learn even that much. PF6 is the criterion this unit
               exists for; if it cannot be met, that is a finding to RECORD, not to route
               around.
             - tests/guardrails.test.sh:3674-3684 -- writelog() and writelog_exit() both
               discard stderr with `>/dev/null 2>&1`, which is what throws away the evidence
               before any assertion runs; writelog_stderr() at :3681 already exists and is the
               shape to build on.
             - The failing case itself: case (b) at :3728-3743, and specifically the
               byte-identity assertion at :3735-3736 -- THE ONE THAT WENT RED ON macos-latest
               at c32daf0, reporting a diff of two file bodies and nothing else. Case (a)
               (:3714-3726) asserts run 1's ok content; run 2's body is asserted
               only by byte-identity with run 1.
             - The cost-log-fixture (:3686-3712), case (c)'s no-slug fixture (:3745-3760),
               case (d)'s DL7/H1 checksum sweep (:3762-3781), case (f)'s BG6 sweep
               (:3796-3800), and the suite's header (:1-33) where OQ6's line lands.
             - S2's new_stub_parser_path() helper -- reuse it; do not write a second one.
Constraints: - writelog() AND writelog_exit() STOP DISCARDING STDERR. Capture it where an
               assertion or a failure diagnostic can read it. No existing case's expected value
               changes as a result -- if one would, you have changed behaviour rather than
               capture, and that is S3's territory.
             - CASE (b) IS STRENGTHENED, NOT WEAKENED OR REPLACED (PF9, OQ4). It keeps its
               letter, position and existing assertions -- including the byte-identity diff --
               and GAINS a direct assertion of run 2's OWN body (the coverage sentence, the
               partial-total line, the rework count), so that "run 2 degraded" is detectable as
               itself rather than only as a byte-diff against run 1.
             - PF5: WHEN CASE (b) FAILS, ITS OWN OUTPUT MUST CARRY THE EVIDENCE -- the parser
               identity, exit status and stderr of each invocation, and the body each run
               actually wrote. Print that block ONLY when the comparison fails; a green run's
               output gains nothing but OQ6's one line. Do not print it unconditionally, and do
               not fold it into the expected/got values of a passing assertion.
             - PF5/PF6 ARE VERIFIED BY A FORCED RED YOU RUN AND RECORD, NOT BY A SHIPPED RED
               CASE: force case (b) red by putting a stub parser on PATH for the SECOND
               invocation only, capture the harness's output verbatim into your return, and
               state explicitly which of PF6's three questions -- which parser ran, what it
               returned, which route produced the state -- that output answers. If it cannot
               answer one of them, SAY SO; PF6 says an unmet answer is a finding to record.
               The suite you commit is green.
             - PF4's FIRST CASE, AND ITS BRANCH: feed a ledger the parser genuinely cannot
               read, and assert the section is still written and names the route. ESTABLISH BY
               READING FIRST whether any portable input makes BOTH parsers exit non-zero:
               unrecognised lines are COUNTED (COST_N_SKIPPED), not failed on, so a "garbage"
               fixture most likely produces `ok` with a skipped count. IF NO SUCH INPUT EXISTS
               PORTABLY: record the route as UNFORCED under OQ5 in your return and in the
               case's own comment, and assert the honest alternative instead -- that a ledger
               of unrecognised lines yields `ok` with a skipped count and no fabricated total.
               Do not invent a fixture that "looks unparseable" and assert a route it never
               reaches.
             - PF4's SECOND CASE: over the valid mixed fixture, the degraded sentence is ABSENT
               from BOTH runs' output. This is the case that makes degraded-wrongly detectable
               at all, and it is the one that would have caught the c32daf0 sighting as a
               degradation rather than as a diff.
             - READING 1 IS ASSERTED HERE: with a stub parser whose stderr contains a unique
               token, that token must appear NOWHERE under docs/loop/ after a degraded write.
               This is the case that stops a future instrumentation change quietly breaking
               DL7/H1.
             - OQ6: ONE environment line at suite start, identical in SHAPE on both platforms --
               labelled fields (bash version, uname, and which of jq / python3 / grep resolve),
               values differing freely. It is an echo, not a case: it must not change either
               job's case total, and both jobs' `total:` lines must still match exactly (A4).
             - Do not edit scripts/ at all. This slice's diff is tests/guardrails.test.sh plus
               README.md's literal. If a case needs a script to say something it does not say,
               that is S3's and this lane returns needs-decision.
             - Do not weaken, delete, skip, reletter, renumber, or reorder any case. The suite's
               case total does not go down (PF9).
             - Case count: +5, computed from main at build time.
             - bash 3.2 only; the suite still runs with zero dependencies beyond jq-or-python3;
               shellcheck -S warning clean for scripts/*.sh (unchanged here) and no new
               external tool in the harness.
             - Merge local main first; commit on your worktree branch before returning.
Output:      tests/guardrails.test.sh (writelog helpers, case (b) strengthened, +5 cases, the
             environment line at suite start), README.md (case-count literal only).
Done when:   A person holding only a failing job's log can name which parser ran, what it
             returned, and which route produced the state, without access to the machine and
             without re-running anything -- and the suite can tell a section that degraded
             correctly over bad input from one that degraded wrongly over good input.
Test set:    5 cases. Selection rule: one per thing SS3 says the harness cannot presently do,
             plus the one property reading 1 introduces. The forced red that verifies PF5/PF6
             is a RECORDED DEMONSTRATION, not a case -- a shipped case cannot be red, and
             asserting the harness's own failure text inside the harness proves the formatter,
             not the diagnosis.
               1. case (b) strengthened: run 2's own body is asserted directly -- coverage
                  sentence, `60787 (priced subset only, partial`, rework count -- alongside the
                  existing byte-identity diff, which stays                        [OQ4, PF9]
               2. degraded-correctly: a ledger the parser genuinely cannot read (or, per the
                  branch above, one of unrecognised lines) -> the section is still written,
                  exit 0, and it names the route it degraded on -- or, if the route is
                  unforcible, `ok` with a skipped count and no fabricated total          [PF4]
               3. degraded-wrongly is detectable: over the valid mixed fixture, neither run's
                  output contains the degraded sentence                                  [PF4]
               4. the evidence capture works: for a forced degraded write, the harness's
                  captured stderr contains all three of parser identity, exit status, and
                  route -- the three facts PF6 requires a job log to answer            [PF5, PF6]
               5. reading 1 / DL7-H1 under instrumentation: a stub parser whose stderr contains
                  a unique token produces a degraded section, and `grep -r` for that token
                  finds it nowhere under docs/loop/                                 [PF8, PF1]
             Fails now: writelog() discards stderr (:3675), so case 4 has nothing to read; run
             2's body is asserted only via byte-identity with run 1, so case 1's assertion does
             not exist; no case anywhere feeds this script an unreadable ledger (case 2) or
             asserts the degraded sentence absent (case 3); and case 5's property is unguarded
             because no stderr reaches the section today. Falsify each against `git stash push
             -- tests/` or a pre-change copy and record the reds in your return.
             Passes after: 1-5 green; cases (a)-(i), the /cost group, the parity group and the
             final `docs (case count)` case all green; both jobs' `total:` lines identical
             (A4); the forced-red output for PF5/PF6 captured verbatim in your return with the
             three PF6 questions answered or explicitly recorded as unanswered.
Do NOT:      - Do not edit any file under scripts/. Not one line, including a "small" wording
               change that would make a case easier to write.
             - Do not weaken, relax, skip, quarantine, reletter, renumber, or reorder any case,
               and do not make case (b) tolerant of a degraded second write.
             - Do not reach for continue-on-error, a known-failures list, a platform skip, or
               an advisory step. Out of bounds by non-goal even when it is the fastest route to
               green -- return needs-decision instead.
             - Do not ship a case that is red, and do not commit the forced-red construction as
               a case. It is a recorded demonstration in your return.
             - Do not invent a fixture that merely looks unparseable and assert a route it does
               not reach. Record the route as unforced instead (OQ5).
             - Do not add a second environment line, a per-platform conditional, a timing
               figure, or anything else to the suite's header beyond OQ6's one line.
             - Do not change .github/workflows/ci.yml, docs/loop/checks.md, or either job's
               three steps. This unit makes no CI change.
             - Do not introduce an environment variable, threshold, default, or suggested value.
             - Do not claim or imply anything about the macOS red on c32daf0, and do not report
               a green suite as evidence the fault is gone -- it is one more sample (PF11).
             - Do not touch another docs/loop/<unit>/ directory or this repository's .claude/.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  S3 -- SEMANTIC for cases 2, 4 and 5, which assert sentences and stderr that S3
             introduces; a harness cannot capture evidence a script does not emit. TEXTUAL for
             the rest: same harness section, same README literal. Case 1 and OQ6's line are the
             only parts that could have run alongside S1-S3, and they cannot be split out
             without a second lane touching the same file and the same literal.
```

---

## Self-audit against the five-point G1 test

Run on my own bench before this reached the gate. Anything with two owners, no nameable test set,
obvious multi-commit scope, an empty `Do NOT`, or a dependency on something later in the list went
back.

| Test | S1 | S2 | S3 | S4 |
|---|---|---|---|---|
| **1. One owning agent** | `loop-build`, one lane | `loop-build`, one lane | `loop-build`, one lane | `loop-build`, one lane |
| **2. One commit's worth** | Two lines of `cost_scan` plus their cases. `PF13` **forbids** splitting the two `grep` sites, so the atomicity is the criterion's, not convenience | One region of one function plus its cases. The four variables are one fact set, not four features | Two reader surfaces, one behaviour: name the route where a human reads it. The `cost-report.sh` half is one line | Harness only. No script byte. The environment line is `OQ6`'s, not a second deliverable |
| **3. Independently testable** | 5 cases; 2 and 3 red against two *different* library versions, both recorded | 6 cases, pairwise rule stated; 1-5 have nothing to read today | 5 cases; the `*)` arm's assertion is false by construction today (`:126`) | 5 cases; `writelog` discards stderr today, so 4 has no input at all |
| **4. Criteria as observable behaviour** | "The same ok body a `grep`-ful PATH produces" — a body, not an implementation | Published variables a consumer reads, and a byte-identical `ok` path | What a reader sees in the section, on stderr, and in `/cost` | What a person holding only the job log can name |
| **5. Dependencies explicit** | `nothing` | `S1`, semantic **and** textual, both stated | `S2`, semantic + textual | `S3`, semantic for three cases, textual for the rest, and the part that *could* have been parallel is named |

**Set sizes: 5, 6, 5, 5.** All in `test-design`'s large-but-healthy band, none in re-slice territory,
and each set's size is explained by its selection rule rather than by its file count. The two I
argued with myself about:

- **`S1` at 5.** Three of its cases assert an `ok` result, and a fix that made both replaced tests
  pass *unconditionally* would satisfy all three. Cases 4 and 5 exist solely to hold the other
  direction, so the set cannot be trimmed without making the slice's own green meaningless.
- **`S2` at 6, not 9.** The full parser × route cross-product is 6 behaviour cases; pairwise is 3,
  because parser identity and route are computed independently in the same function. Stating that
  rule is what keeps the set from looking arbitrary.

**Four slices and not two.** `S1` + `S2` merged would put the fix and the instrumentation in one
commit — the precise cost `OQ1` accepted and asked this gate to mitigate. `S3` + `S4` merged would
put the product's rendering and the harness's diagnosis in one diff, so a G2 reader could not tell
an instrument that works from a case that asserts it does.

---

## Criterion traceability

Nothing is dropped, and nothing is claimed as assigned that is not.

| Criterion | Where it stands after this pass |
|---|---|
| **PF1** — a degraded read names parser, status, bounded stderr | **`S2`** publishes all three; **`S3`** renders the first two into the body and the third onto streams only (reading 1); **`S4`** asserts the token never reaches `docs/loop/`. The bound is pinned |
| **PF2** — "parse error" stops being one bucket | **Split and named.** `S2` owns the three-value route vocabulary and the `OQ5` record of what could not be forced; `S3` owns both reader surfaces and the `*)` arm. Two of the five listed routes are met by readings 2 and 3 rather than by labels — flagged, overturnable in one place |
| **PF3** — a degraded write is visible to whoever ran it | **`S3`**, cases 2 and 3 (non-empty stderr with slug and route on degraded; silent on `ok`; exit 0 both ways) |
| **PF4** — the harness tells degraded-correctly from degraded-wrongly | **`S4`**, cases 2 and 3, with the unforcible-input branch written into the envelope rather than left for a builder to improvise |
| **PF5** — case (b)'s red carries its own evidence | **`S4`**, case 4 for the capture, plus the **forced-red demonstration recorded in the return**. A shipped case cannot be red, and asserting the harness's failure text inside the harness would prove the formatter |
| **PF6** — the next occurrence is diagnosable from the run's output alone | **`S4`**, by reading that forced red. The envelope requires the three questions answered explicitly, or **recorded as unanswered** — the spec says an unmet `PF6` is a finding, not a thing to route around, and this gate does not pretend otherwise |
| **PF7** — the two parser programs still agree | **`S1` and `S2`, as a per-lane gate**: the existing parity cases (`:4361-4474`) unmodified and green, plus a full-suite run under `new_jq_absent_path()`, both `total:` lines reported. Structurally safe as well: no slice edits either program (pinned) |
| **PF8** — nothing already guaranteed regresses | **Every slice's per-lane gate**: full suite green normally and under `new_jq_absent_path()`, plus the byte-identity halves of `S2`'s case 6 and `S3`'s case 3. `S4`'s case 5 covers the one *new* way `DL7`/`H1` could break |
| **PF9** — no case weakened, total does not go down | **Every slice's `Do NOT`**; `S4` owns the only permitted change to an existing case and it is a **strengthening** (case (b) keeps every assertion and gains one) |
| **PF10** — nothing new ships set; unchanged paths byte-identical | **`S2` case 6 and `S3` case 3**, both diffed against pre-change output captured via `git show`. The *"ships unset"* half is **vacuous here and said so**: no slice introduces an environment variable, so a case asserting "zero output when unset" would be a case that cannot fail |
| **PF11** — the fix is never written up as an explanation | **Not a builder's slice.** Pinned as a constraint on every lane's commit messages, code comments, case descriptions and returns; the record itself lands in `verify.md` (**`loop-verify`, at G2**) and `log.md` (**the close step**). Named as unassignable here rather than parked in a slice that cannot write those files |
| **PF12** — the state test no longer reports a parse error over unexamined input | **`S1`**, cases 2 and 5 |
| **PF13** — the failure is not relocated to the slug test | **`S1`**, case 3 as the discriminator (**required red against a `:976`-only patch, recorded**) and case 4 as the other direction. Not splittable: `PF13` requires both sites in one change |
| **PF14** — a reproduced red before the fix, on both platforms | **`S1`** for the local half — case 2 red against the pre-change library, `N/M` and both shas recorded, forced by a bounded `PATH` and not by mocking. **The second half is the human's**: only a real pushed run establishes the guarding checks, and no lane pushes |
| **PF15** — the fix edits neither parser program | **`S1`**, structurally (pinned `Do NOT` + a `git diff` check) with the `R1` **no** branch written in as `spike-r1-parser-programs.md` **then stop** |
| **OQ6** — one environment line at suite start | **`S4`**, shape-identical on both platforms, an echo rather than a case, `A4` restated as the constraint |
| **R1** — can the fix avoid both parser programs? | **`S1`'s first act**, by reading. Expected yes; the *no* branch stops the lane at a human gate |

---

## Cross-unit collisions

Live neighbours, read from `docs/loop/` at this gate: **`resumed-invocation-never-reaches-the-ledger`**
and **`stale-evict-lock-permanently-defeats-the-cap`**, both approved at G0 and both queued behind
this unit. **Both acquired an uncommitted `slices.md` while this pass was running** — they are being
cut concurrently, so their contents are not read, quoted, or depended on here, and nothing in this
document was written against them. Everything else under `docs/loop/` is closed except
`transcript-scraping-as-a-recovery-path` (declined, intent only). **Whoever reads this at G1 should
read the three slice lists' case-count deltas together**: three units are now cut against one
literal, and the build-time rule below is the only thing that makes any landing order safe.

| Shared surface | Who touches it here | The landing rule |
|---|---|---|
| `tests/guardrails.test.sh` | all four slices | Every unit appends cases; highest textual-conflict risk in the repository. This unit's cases land in the existing cost-log and `/cost` sections, before the final `docs (case count)` case |
| `README.md`'s `## Development` case-count literal (`:169`, **466** today) | all four slices, **+21 total** | Deltas only, computed from `main` at build time. Never an absolute from this document |
| `scripts/cost-ledger-lib.sh` | `S1`, `S2` — the shell around the parser calls only | `resumed-invocation-never-reaches-the-ledger`'s `RS10` edits **both parser programs**. This unit leaves them **byte-identical** (`PF15`), which is precisely what makes that unit's diff legible as `RS10`'s change and nothing else |
| `scripts/cost-report.sh` | `S3`, line `:496` only | `recovered-figure-drops-slice-and-model` is closed; no live neighbour holds this file |
| `docs/loop/decisions.md`'s end-of-file | **nobody, in this pass** | Named because it is the easiest collision to miss: two units' closing records append to the same insertion point. If a `decisions.md` entry is wanted for this unit, it belongs to the close step, after the group merges |
| `scripts/record-cost-event.sh` | **nobody** | `stale-evict-lock-permanently-defeats-the-cap`'s neighbourhood. Out of bounds here, on every lane |

**Build-order recommendation, from `decisions.md`'s backlog gate (2026-08-19):** this unit lands
**first** of the three. The neighbours may be cut now — cutting collides with nothing — but neither
one's lanes should start until `S1`–`S4` have merged — its own spec records that `RS10` **rebases onto this
unit's landed change** rather than developing alongside it. Either order survives the case-count
literal *because of* the build-time rule, not because of scheduling; the rebase argument is what
makes the order load-bearing.

---

## Riskiest slice: **S1**

**Not `S2`**, and the distinction is the same one this repository has nominated on before: the risk
worth naming is the slice that can produce a **wrong result that is persuasive**, not the slice with
the most surface.

`S1` can, by one specific mechanism. Every criterion-named case in it — `PF14`'s and `PF13`'s — asserts
that a valid fixture produces the **`ok` body**. A replacement for `grep -qxF` at `:990` that is
subtly too permissive (`*"$slug"*` instead of whole-line-literal, or an unquoted pattern that lets a
slug's glob characters match) makes the slug test pass for **every** input. Both criterion cases then
go **green**, the suite goes green, `PF12`/`PF13`/`PF14` all read as satisfied — and `no-slug` has
become unreachable, so the script will report one unit's figures under another unit's slug, or
figures for a unit the ledger holds nothing for. That is a **confident wrong answer about the
ledger's contents**: the exact class `PF13` exists to prevent, arrived at through the fix rather than
through the relocation.

The mitigation is case 4 and the pinned exact-line/fixed-string contract, and case 4 is the line in
`S1`'s envelope worth reading twice at this gate. A second, quieter mitigation is case 5: the same
over-permissiveness at `:976` would make the marker test unconditionally true, and only a case that
forces a genuine parser failure can see it.

**Runner-up: `S2`**, for a different failure that also passes green — the stderr capture reaching a
file. `jq` and `python3` both quote the offending input in their errors, so a capture rendered into
`log.md` puts **ledger content under `docs/loop/`** and breaks `H1`/`DL7`, which no case asserts under
instrumentation today. Reading 1 pins the boundary, `S3` respects it, and `S4`'s case 5 is what turns
it into a guarded property rather than a paragraph in this document.

**Not nominated, and worth saying why: `S4`.** It carries the criterion the unit exists for (`PF6`)
and the one most likely to come back **unmet** — but an unmet `PF6` lands at G2 as a recorded finding,
which is the honest outcome the spec asks for. Uncertainty that has somewhere safe to land is not the
risk to nominate.

---

## Residual questions — recorded, because the human was not available to this pass

None blocks a build. Each is a place where this gate chose, and the choice is cheap to overturn.

1. **The `R1` "no" branch is stricter than `PF15`'s letter.** `PF15` permits a builder to change both
   parser programs symmetrically with the reason recorded; this cut requires it to write
   `spike-r1-parser-programs.md` and **stop** with `needs-decision`. Reason: `PF15` states
   byte-identical as the *expected* outcome, and the same change alters what
   `resumed-invocation-never-reaches-the-ledger` rebases onto — a build-order fact, not a code
   judgement. **To loosen it, strike the pinned contract and `S1`'s first constraint; nothing else
   changes.**
2. **`/cost`'s degraded sentence (`cost-report.sh:496`) is in scope, by one line.** No criterion names
   it. Included because leaving one of the two degraded-read sentences un-routed preserves the
   collapse this unit exists to remove, and because no harness case asserts either sentence today.
   **To strike it, drop `S3`'s case 5 and that one line; `S3` stays a valid slice.**
3. **`check-budget-gate.sh:344`'s degraded stderr message does not gain the route.** It is a third
   degraded-read surface, and the argument for (2) partly applies to it. Excluded because its two
   `case` arms are the **fail-safe** that stops a degraded scan being read as a total, and because it
   prints only when a human has set a threshold — none is set anywhere. **A candidate observation, not
   a gap to close here.**
4. **`tr` at `cost-ledger-lib.sh:310` stays open.** Same class of dependency as the two `grep` calls,
   out of bounds by non-goal, on every lane's `Do NOT`. It wants its own `/observe` intent; this
   document is not that intent.

---

# G1 — Slices — cost-log-section-parse-error-on-macos-ci

```
Slices: 4  ·  Parallel: 0 (a finding — four sequential merges)  ·  Critical path: S1 → S2 → S3 → S4
Riskiest: S1 — every criterion-named case in it asserts an `ok` body, so a replacement for
          `grep -qxF` that is subtly too permissive passes PF12/PF13/PF14 green while making
          `no-slug` unreachable: a confident wrong claim about the ledger's contents, which is
          the very thing PF13 exists to prevent. Case 4 is the guard; read it twice.

S1 · THE FIX: neither :976 nor :990 depends on grep; a valid ledger under a grep-less PATH
     reads ok, and both tests still discriminate      (PF12-PF15)   · depends on nothing
S2 · the library records which parser ran, its exit status, a bounded stderr capture, and one
     of three route values; ok path byte-identical    (PF1, PF2, PF10) · depends on S1
S3 · both reader surfaces name the route; a degraded write says so on stderr; the `*)` arm
     stops borrowing scan-error's words               (PF2, PF3)    · depends on S2
S4 · the harness stops discarding stderr, tells degraded-correctly from degraded-wrongly, and
     carries the evidence into its own failure output (PF4-PF6, OQ6) · depends on S3

Fix and instrumentation are SEPARATE SLICES with SEPARATE TESTS and separate evidence — OQ1's
accepted cost, mitigated structurally here as G0 asked. PF11 is not a builder's slice: it binds
every lane's wording and is discharged in verify.md (G2) and log.md (close).
PF14's second half — both jobs on a real pushed commit — is yours, after the group merges.

1. Approve — brief S1 first; S2 → S3 → S4 follow in order  (recommended)
2. Re-slice — say which, and why. The three cheapest levers are in *Residual questions*:
   loosen S1's R1 stop, strike /cost's one-line route clause (S3 case 5), or overturn a reading
3. Spec is wrong — back to loop-spec
```
