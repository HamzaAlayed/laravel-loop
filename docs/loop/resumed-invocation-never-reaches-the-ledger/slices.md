# Slices — resumed-invocation-never-reaches-the-ledger

Phase: Slice (G1). Cut from `spec.md` in this directory, **approved at G0 on 2026-08-19 and
committed as `dea7408`**. Every row of that spec's *Decided at G0* table is treated here as a
decision taken, not a recommendation, and nothing below reopens one.

## What this pass cuts, and what it deliberately does not

**Cut: `RV` (S1–S4) and `SP` (S5). Not cut: `RS` and `RB`.**

Stage 3 is left uncut on purpose and is scoped — not blank — in *Stage 3 — NOT CUT* below. In one
line: **an `RS` slice written now would commit this repository to a capture design against a
mechanism the spec records as unestablished in both directions, and G0 makes that a G1 defect
rather than an optimisation** — a slice envelope names files, outputs and tests, so writing one
*is* the design commitment the gate withheld.

This is the third consecutive unit cut in that shape (`cost-ledger-blind-to-background-agents` left
the RC group behind `S6`'s spike; `eviction-cap-not-honoured-under-contention` left its fix group
behind `S1`–`S3`), and the shape is not being re-argued here.

## The seam

**S1.** The smallest change that delivers observable value is the sentence that closes RE11: the
repository's own documentation of what the ledger can and cannot see does not mention resumes at
all, and `docs/loop/ship-gate-blind-to-ci/log.md` prints `100 % coverage` forty lines from a
statement that a failed attempt's tokens are reported nowhere. One paragraph in README's
`## Cost ledger`, beside the X5 background-launch paragraph that is already there, and a reader who
finds the coverage figure can now find its limit. It is grep-provable, needs no hook, needs no
spike answer, and it is the one slice in this pass with a genuine red-before.

Everything else in `RV` is a **lock**: an assertion placed now so that Stage 3 — whichever arm — can
only append, and cannot silently move output a reader is used to. Locks are labelled as locks
throughout this file rather than dressed up as behavioural fixes, on CL7's precedent.

## Field evidence gathered at this gate (read-only, nothing written)

Every claim a slice below rests on was checked against the tree at `dea7408`, not inferred.

1. **A fully-priced fixture's output already claims no completeness.**
   `CLAUDE_PROJECT_DIR=<tmp> bash scripts/cost-report.sh <slug>` on a 1-invocation, 100 %-priced
   ledger → exit 0, prints `-- 100 % coverage`, and `grep -inE
   'complete|full|verified|accurate|exhaustive|everything'` over the whole report → **no match**.
   So `RV2`'s output half is *already true* and its slice is a lock, not a fix.
2. **README's coverage lines carry no completeness vocabulary either.** 4 lines mention coverage;
   none also carries `complete|full|verified|exhaustive|guaranteed|proven`. `RV2`'s documentation
   half is a lock too — and it must be scoped to *lines mentioning coverage*, because a blanket
   grep for `full` matches "fully standalone" and would fail for the wrong reason.
3. **A well-formed ledger line whose `event` the reader does not recognise moves no figure, exits
   0, and is reported as `malformed or truncated, not JSON`.** Verified by adding one
   `{"event":"some_unrecognised_event",…}` line to the fixture above: the whole diff against the
   baseline report is one added line —
   `1 ledger line(s) skipped -- malformed or truncated, not JSON (never silently dropped from this
   count).` — and every figure is identical. **Two consequences, both load-bearing:** `RV3`'s
   byte-identity is honest over the *figures it enumerates* and is **not** a whole-output diff; and
   the misclassification is **Arm A's to fix, in both parser programs**, because `RS10` forbids a
   record being reclassified into a category it cannot support. `RS10` does not currently name this.
   Recorded here so Arm A inherits a discovered red rather than finding it at G2.
4. **Three frozen full-report blocks exist; the other two surfaces `RV4` names have none.**
   `tests/guardrails.test.sh:1696`, `:4294`, `:4563` each diff `cost-report.sh` output against a
   literal block. **Nothing freezes the budget gate's output, and nothing freezes `log.md`'s
   `## Cost` section** — the log section is only self-diffed for idempotency (`:3736`). That gap is
   S3's real work.
5. **The coverage sentence has seven call sites across three scripts.**
   `cost-report.sh:202,246,472`; `check-budget-gate.sh:356,368,434`;
   `write-cost-log-section.sh:79`. Its own header (`cost-ledger-lib.sh:285-337`) already records
   that the prefix is kept literal because a `grep -qF` depends on it, and that both prior
   extensions were appended. `RV9` is that rule made assertable.
6. **`README.md:169` reads `466 cases`** — matching `spec.md`'s `RV5`. The harness's own last case
   (`docs (case count)`) asserts that literal equals the live `PASS + FAIL + 1` tally.
7. **The spike has a target that exists.** The installed build (`2.1.235`) carries `SendMessageTool`
   and `SendMessagePreconditionError` in its string table. **This is neutral: it is evidence that a
   tool by that name exists, and evidence of nothing whatever about whether a `hooks.json` matcher
   reaches it or what its payload carries.** It is recorded only so S5's probe has a named target,
   and S5 must not read it as leaning either way.

## Pinned contracts for this unit

A slice that believes one of these is wrong returns `needs-decision` rather than changing it.

| Contract | Value | Who holds it | Why pinned |
|---|---|---|---|
| **No script changes in this pass** | `RV` and `SP` touch nothing under `scripts/`. Zero lines. | S1–S5 | `spec.md`: "Groups `RV` and `SP` name no file, field, or function to change". Both neighbouring units land first in `record-cost-event.sh` and `cost-ledger-lib.sh`; a script edit here rebases onto work that has not landed |
| **Neither parser program is touched** | `_cost_scan_*` and `_cost_slice_*`, jq and python3 both, are out of bounds | S1–S5 | `RS10` is Arm A's and it rebases onto `cost-log-section-parse-error-on-macos-ci`'s landed diff. Also the repo's most dangerous file |
| **`hooks/hooks.json` is unchanged at the end of every slice** | S1–S4 never open it. S5 may register a matcher **temporarily and outside this repository's copy**, and leaves nothing half-registered | S5 owns the cleanup step | `SP4`, `RB3`, and the standing rule that every script named there exists and is executable |
| **The coverage sentence's prefix** | `based on <p> of <n> invocations that carry a token figure (<u> unpriced, not counted)` — byte-identical, and it **begins** the sentence | S3 asserts; Stage 3 appends after it | `RV9`, `OQ-R2`. Two prior extensions already appended; a third that rewords breaks `BG3` at a distance from its own diff |
| **`RV7` on every slice** | Nothing added may block, delay, reorder or steer a spawn, a tool return, or a run; every new path exits 0, asserted per case, never in aggregate | every slice's `Do NOT` | `L7`/`RC7`/`X4`, settled 2026-08-19. It is an invariant, not one slice's deliverable |
| **No token figure, from any source** | Nothing estimates, imputes, apportions, halves, doubles, averages or inherits a figure for a resumed run or a killed attempt | every slice | `RE4`: there is no number to record. `RV3`, `RS9` |
| **No fixture line proposes Arm A's record shape** | Where a slice needs a ledger line the reader does not recognise, the event name is deliberately not a candidate name, and the case comment says so | S2 | A fixture line is a shape commitment if it is allowed to look like one. Arm A is uncut |
| **No threshold, default, or suggested value** | All five fields stay unset; the 30 % concentration figure is untouched | every slice | `spec.md` non-goal, `G0-D1`, and the repo's standing rule |
| **No coverage claim** | No slice is justified, in its diff, its comments, or its return, by an expectation that coverage rises | every slice | `RV8`, `RE4`, and the routing item's revisit condition, which this unit does **not** satisfy |
| **Case-count arbiter** | The harness's own last case (`docs (case count)`) is the arbiter of README's literal; new cases append **before** it | every case-adding slice | It computes `PASS + FAIL + 1` and is only a grand total if it runs last |

## Case-count deltas — pinned as DELTAS, never as an absolute

`README.md:169` reads **466 cases** today, **and no slice below may use that number.** Two
neighbouring units are in flight and both will move it, so an absolute pinned here is wrong the
moment either merges, and the loser's merge leaves the suite red on a case its diff never touched.

| Slice | Δ cases |
|---|---|
| S1 | +3 |
| S2 | +6 |
| S3 | +4 |
| S4 | +2 |
| S5 | **+0** — its proof is an experiment, not a case. Stated, not disguised |

**Group delta +15.** Build-time rule, per lane, in this order:

1. Merge `main` into your branch before writing anything (`conventions.md`).
2. Read the literal you actually have:
   `sed -n '/^## Development/,/^## /p' README.md | grep -oE '[0-9]+ cases'`.
3. Add **your own delta** to what you read — never to a number in this file.
4. The harness's own last case is the arbiter. Run the suite.
5. If your honest delta differs from the table, say so in your return.

Either landing order against either neighbour survives **because of** this rule, not because of
scheduling luck.

## Slices

Five cut. Envelopes are verbatim build briefs.

### S1 — Say, where the ledger's limits are already documented, that a resumed run is recorded nowhere
```
Owner:       loop-build
Unit:  resumed-invocation-never-reaches-the-ledger
Slice: S1
Context:     - spec.md RV1, RE11, and the file's opening note. The reference case is
               docs/loop/ship-gate-blind-to-ci/log.md, which prints `7 of 7 ... 100 %
               coverage` and, forty lines earlier, that the failed first attempt's tokens
               are "reported nowhere at all, by anything".
             - README.md `## Cost ledger`. The new paragraph goes in that section, after
               the three that are already there: the X5 background-launch paragraph
               ("Background-launched invocations are the majority of a /loop run ..."),
               the record-recovered-cost.sh paragraph, and "A recovered record carries
               exactly one dimension ...". Same place, same manner as X5's statement.
             - README.md is ONE LINE PER PARAGRAPH. tests/guardrails.test.sh:4822 relies
               on it to isolate a paragraph with a single grep -F.
             - The house case pattern for a README statement: tests/guardrails.test.sh
               :4825-4840 (isolate the paragraph once, then grep -qF per required
               substring, several packed into one expect) and :3374 (the negative form --
               "README does not claim the background gap is closed").
             - docs/loop/conventions.md already carries "A resumed invocation is a
               different invocation to the ledger". That entry is the source of the
               wording and is NOT edited or restated there.
Constraints: - Three facts, in README's own voice, in one paragraph: a run resumed with
               SendMessage is not recorded as an invocation at all; its tokens are in no
               total; and a killed attempt's tokens are recorded nowhere, by anything.
             - State plainly why: hooks.json matches `Agent|Task`, and a SendMessage is
               neither.
             - No wording that implies a figure is forthcoming, in progress, planned, or
               recoverable later -- no "not yet", "currently", "until", "will be". RE4
               settles that no figure can arrive; a reader must not be left waiting for
               one.
             - Do not state or imply which of the three spike answers is true, and do not
               describe capture as forthcoming. S5 has not run.
             - Nothing about coverage rising, anywhere, in any form.
             - Append new cases BEFORE the final `docs (case count)` case. Compute
               README's literal with the five-step build-time rule in slices.md; do not
               use a number from this file.
Output:      README.md (`## Cost ledger`: one added paragraph, plus the case-count literal
             in `## Development`), tests/guardrails.test.sh (+3).
Done when:   grep on README finds a paragraph stating all three facts; removing or
             rewording any one of them turns a named case red; and no line of that
             paragraph implies a figure is coming.
Test set:    3 cases. Selection rule: one per fact-group that can independently go
             missing, in the :4825 house shape.
               1. The paragraph states the run is not recorded as an invocation AND that
                  its tokens are in no total AND names the Agent|Task matcher as the
                  reason.
               2. The paragraph states a killed attempt's tokens are recorded nowhere by
                  anything.
               3. Negative: no forthcoming-figure vocabulary on that paragraph's line
                  (no "not yet"/"currently"/"planned"/"will be"/"pending").
             Fails now: all three greps fail against today's README -- the paragraph does
             not exist. This is the only slice in this pass with a genuine red-before, and
             that is said here rather than claimed for the others.
Do NOT:      - Do not touch anything under scripts/. Zero lines.
             - Do not touch hooks/hooks.json (S5's temporary business, and it leaves none
               behind).
             - Do not edit docs/loop/conventions.md -- the resumed-invocation entry stands
               as taught.
             - Do not touch docs/loop/decisions.md (S4's file) or CHANGELOG.md (the close
               step's).
             - Do not touch any other docs/loop/<unit>/ directory. Two are in flight.
             - Do not edit, renumber, skip, weaken or delete an existing harness case.
             - Do not add or suggest a number for any of the five threshold fields.
             - RV7 standing: nothing added may block, delay, reorder or steer anything,
               and every path exits 0.
Depends on:  nothing
```

### S2 — Pin what the output and the docs may never claim: no completeness, no invented figure, no refine pass
```
Owner:       loop-build
Unit:  resumed-invocation-never-reaches-the-ledger
Slice: S2
Context:     - spec.md RV2, RV3, RV6.
             - docs/loop/checks.md:79 -- "Neither platform above is described as covered,
               verified, guaranteed, or proven." That is the house precedent RV2 names,
               applied to a token total instead of a platform.
             - tests/guardrails.test.sh:1077 -- BG6's reassurance-token case
               (`within budget|under budget|✓`). Extend the discipline in a NEW case; do
               not edit BG6's own case or its token list.
             - tests/guardrails.test.sh:1131-1145 -- `cl1_check`, the direct-lib pattern:
               source cost-ledger-lib.sh, call cost_scan, assert the counters, rather than
               inferring them from prose. RV3's figure set is asserted that way.
             - slices.md's field evidence items 1, 2 and 3. Read item 3 before writing a
               single assertion: an unrecognised well-formed ledger line moves no figure
               and exits 0, AND is reported as "malformed or truncated, not JSON". The
               first half is what this slice pins. The second half is Arm A's (RS10) and
               is explicitly out of bounds here.
Constraints: - RV2, live output: a fully-priced (100 % coverage) fixture's whole output
               carries none of `complete`, `full`, `verified`, `exhaustive`, `guaranteed`,
               `proven`, `all invocations`, `every invocation`. Verified green today, so
               label the case a lock in its comment.
             - RV2, documentation: scope it the way the existing no-digit guards are
               scoped -- no line that MENTIONS COVERAGE may also carry one of those words.
               A blanket grep for `full` matches "fully standalone" and is a case that
               fails for the wrong reason.
             - RV3: compare exactly the figures RV3 enumerates -- priced total, coverage
               share, every per-phase figure, every per-slice row -- between one fixture
               and the same fixture with one extra unrecognised line, using the direct-lib
               pattern. NOT a whole-output diff: today that diff is non-empty for the
               reason in field evidence item 3, and a whole-output assertion here would
               either go red or quietly encode the misclassification as correct.
             - The extra line's event name is deliberately NOT a candidate name for Arm
               A's record, and the case comment says so in one sentence. A fixture line is
               a shape commitment if it is allowed to look like one, and Arm A is uncut.
             - RV6: on that same fixture the rework count and the rework token share do
               not move, and no per-pass token figure appears anywhere in its output. The
               existing "no per-pass token figure anywhere" assertion is re-run
               unmodified, not replaced.
             - Every new path exits 0 (RV7), asserted per case, not in aggregate.
             - PROVE EACH LOCK BY MUTATION. For each lock case, make the one-line local
               mutation that should turn it red, record the failing assertion, revert, and
               report both in VERIFIED. A lock nobody has seen fail is a claim.
Output:      tests/guardrails.test.sh (+6), README.md's case-count literal only.
Done when:   A fully-priced fixture provably contains no word claiming its coverage is
             complete; a ledger line the reader does not recognise moves none of the
             figures RV3 names and the report still exits 0; the rework figures do not
             move; and each of those properties has been demonstrated to fail under a
             named mutation.
Test set:    6 cases. Selection rule: 2 surfaces for the completeness vocabulary (live
             output, documentation) x 1 case each; RV3's enumerated figure set as one
             packed direct-lib case plus one exit-code case; RV6 as two (rework count and
             share unchanged; no per-pass figure).
               Cases 3-6 fail now in the sense that matters: no case anywhere reads a
               ledger holding an event class the reader does not know, so the property is
               unenforced. Cases 1-2 are locks, green on first run, labelled as such --
               their value is that Stage 3 cannot introduce a completeness claim without
               turning them red, and the mutation step above is what proves they can.
Do NOT:      - Do not touch anything under scripts/. In particular not
               scripts/cost-ledger-lib.sh: both parser programs are out of bounds, the
               neighbours land first, and RS10 rebases onto them.
             - Do not fix the "malformed or truncated" misclassification. It is recorded
               as a finding for Arm A. Fixing it here is a parser change in the file this
               repo calls its most dangerous, in a pass whose contract is zero script
               lines.
             - Do not edit BG6's case, its token list, or any existing case.
             - Do not add a whole-output frozen diff -- that is S3's, on the surfaces that
               lack one.
             - Do not touch hooks/hooks.json, docs/loop/decisions.md, CHANGELOG.md, or any
               other docs/loop/<unit>/ directory.
             - Do not name, invent, or reserve a record shape, field name, or event name
               for Arm A.
             - RV7 standing, as S1.
Depends on:  nothing logically. TEXTUAL: run after S1 -- both append harness cases and
             both bump README's case-count literal, and two lanes collide on that one
             number by construction. Not a missed parallel lane; a shared literal.
```

### S3 — Lock the coverage sentence's prefix, and freeze the two surfaces no frozen block covers
```
Owner:       loop-build
Unit:  resumed-invocation-never-reaches-the-ledger
Slice: S3
Context:     - spec.md RV9 (OQ-R2's decision: append, prefix byte-identical) and RV4.
             - scripts/cost-ledger-lib.sh:285-337 -- cost_coverage_sentence(), whose own
               header already records that the prefix is kept literal because a grep -qF
               depends on it, and that both prior extensions (the coverage share and
               wholly-unobserved phases; then the transcribed clause) were APPENDED.
             - Its seven call sites: cost-report.sh:202,246,472;
               check-budget-gate.sh:356,368,434; write-cost-log-section.sh:79.
             - tests/guardrails.test.sh:2070 and :2086 -- BG3's verbatim prefix grep in
               the gate's breach message. It proves PRESENCE. Nothing today proves
               POSITION, and "appended after it" is the criterion.
             - tests/guardrails.test.sh:2191 -- CV7/CV8's report-vs-gate identity case.
             - The three existing frozen report blocks: :1696, :4294, :4563. ALL THREE ARE
               cost-report.sh OUTPUT. The budget gate's output and log.md's `## Cost`
               section have no frozen block; the log section is only self-diffed for
               idempotency at :3736. RV4 names all three surfaces.
Constraints: - Assert the prefix as a PREFIX: for one fixture, each consumer's sentence
               BEGINS with `based on <p> of <n> invocations that carry a token figure
               (<u> unpriced, not counted)`. Use a prefix test (case-glob or an anchored
               grep), not a bare substring search.
             - Add the frozen blocks RV4 is missing -- the budget gate's own output, and
               log.md's `## Cost` section -- for one RESUME-FREE fixture, in the house
               `read -r -d '' ... <<'FROZEN'` shape, diffed against the live output.
             - ONE fixture, three surfaces, ONE cost_scan. Never a second fixture per
               surface, or the identity claim is about two ledgers rather than one
               (CV7/CV8).
             - Above each frozen block, one comment sentence saying it is a LOCK, not a
               description: a later stage that changes output must update it
               deliberately, and a stage that changes output without noticing has a bug.
             - Generate each frozen block from a real run on the lane's own machine with
               both jq and python3 present, and confirm the same fixture produces the same
               block under `PATH` stripped to the python3 arm. A block captured from a
               degraded run encodes a bug as the contract.
             - Do not touch cost_coverage_sentence or any script. This slice adds no
               wording; it makes wording added later provable.
             - Every new path exits 0 (RV7).
             - PROVE EACH LOCK BY MUTATION, as S2: mutate, record the failing assertion,
               revert, report both.
Output:      tests/guardrails.test.sh (+4), README.md's case-count literal.
Done when:   Reordering or rewording the coverage sentence's prefix turns a named case
             red; and changing a single byte of the budget gate's output or of log.md's
             `## Cost` section, for a resume-free ledger, turns a named case red. Each
             demonstrated by mutation, not asserted.
Test set:    4 cases, one per unproven surface. Selection rule: the criterion names three
             surfaces and one positional property, and today's suite covers neither the
             position nor two of the three surfaces.
               1. Prefix-as-prefix, every consumer of the sentence, one fixture.
               2. The budget gate's output, frozen.
               3. log.md's `## Cost` section, frozen.
               4. The three surfaces print identical numbers and identical sentence text
                  for that one fixture.
             All four are locks and none has a red-before in the ordinary sense: the
             property is unenforced today, which is why the mutation step is a constraint
             and not a nicety.
Do NOT:      - Do not touch anything under scripts/, and specifically not
               cost_coverage_sentence(). Appending to it is Stage 3's, under whichever arm
               SP opens.
             - Do not append any resume wording to the coverage sentence in this pass. See
               "RV9 has no unconditional append" below: RV4 forbids it, because every
               ledger that exists today is resume-free.
             - Do not edit BG3's case, CV7/CV8's case, or any of the three existing frozen
               blocks.
             - Do not freeze a fourth surface nobody asked for, and do not freeze a report
               block -- three already exist.
             - Do not touch hooks/hooks.json, docs/loop/decisions.md, CHANGELOG.md, or any
               other docs/loop/<unit>/ directory.
             - RV7 standing, as S1.
Depends on:  nothing logically. TEXTUAL: run after S2, same shared literal and same file.
```

### S4 — Record that this unit cannot raise pricing coverage, and leave the routing decision standing
```
Owner:       loop-build
Unit:  resumed-invocation-never-reaches-the-ledger
Slice: S4
Context:     - spec.md RV8, RE4, RE6, and the note at the top of that file.
             - docs/loop/decisions.md's 2026-08-19 backlog-gate section: the routing item
               (cost R3.1/R3.2) is dropped, with its revisit condition "background pricing
               coverage rises materially", and the queue that puts this unit third.
             - The house pattern for a decisions.md case: tests/guardrails.test.sh
               :4847-4855 (a `local bad=0 dec=...` helper, one packed expect) and
               :3380-3389, which also asserts that OTHER entries stand untouched.
             - decisions.md's end-of-file is a live collision surface: two neighbouring
               units' closing slices append to the same place.
Constraints: - One dated entry, appended at the end, in the file's existing bullet voice.
             - It states: capturing a resumed run yields a RECORD and never a NUMBER (RE4
               -- 20 of 20 joinable results carried no token field of any kind, and the
               sample was independently re-parsed and corrected downward from 24 to 20);
               that this unit is therefore NOT the thing that satisfies the routing item's
               revisit condition; and that the resumes already in this repository's
               history stay unattachable, because no ledger record written before this
               unit holds an agent id and there is no backfill (RE6, OQ-R4).
             - The existing routing bullet is left BYTE-IDENTICAL. No edit, no annotation,
               no "superseded" marker, no cross-reference inserted into it.
             - The entry records NOTHING about the spike's answer. That is SP5's entry,
               whichever way it goes, and this one must not read as anticipating it.
             - Re-read the end of decisions.md immediately before appending, and merge
               main first. If a neighbour has appended since this brief was written, your
               entry goes after theirs and you say so in your return.
Output:      docs/loop/decisions.md (one appended entry), tests/guardrails.test.sh (+2),
             README.md's case-count literal.
Done when:   A reader of decisions.md alone finds the finding, its date, and its evidence,
             and cannot read this unit's completion as satisfying the routing condition;
             and the routing bullet is unchanged.
Test set:    2 cases. Selection rule: one for the new entry's required content, one for
             the neighbouring text it must not disturb -- the :3380 pattern exactly.
               1. The entry exists, carries its date, names that a resume yields a record
                  and never a number, and names that this unit does not satisfy the
                  coverage-rise condition.
               2. The routing decision's own bullet stands verbatim, and no
                  "superseded"/"revisited" marker has been attached to it.
             Fails now: no such entry exists, so case 1's greps fail against today's file.
Do NOT:      - Do not touch anything under scripts/, tests beyond the two cases,
               hooks/hooks.json, or CHANGELOG.md.
             - Do not edit any existing decisions.md entry, in any way, for any reason.
               An in-place correction is a different act with a different precedent (X6)
               and is not licensed here.
             - Do not record, predict, hedge, or hint at the spike's answer.
             - Do not touch any other docs/loop/<unit>/ directory.
             - Do not write any number for any threshold field.
             - RV7 standing, as S1.
Depends on:  nothing logically. TEXTUAL, twice: after S3 for the shared case-count
             literal, and against whichever neighbour last appended to decisions.md. It is
             ordered LAST of S1-S4 on purpose -- so the seam (S1) never waits on a
             collision surface two other units are also writing to.
```

### S5 — SPIKE: establish which of three answers is true for a `hooks.json` matcher on `SendMessage`
```
Owner:       loop-build
Unit:  resumed-invocation-never-reaches-the-ledger
Slice: S5
Context:     - spec.md SP1-SP5, RE12 (the question, UNKNOWN and deliberately not asserted
               in either direction), RE1 (a SendMessage's tool_input keys), RE3
               (resumedAgentId present on all 20 joinable results), RE5/RE6 (agentId
               arrives on an Agent/Task tool_response and is discarded at
               scripts/record-cost-event.sh:661-667).
             - docs/loop/conventions.md: a green harness NEVER proves a hook is live; a
               hooks.json change needs a plugin reinstall AND a restart; an agent killed
               mid-response may have written nothing.
             - The precedent probe: docs/loop/cost-ledger-blind-to-background-agents/
               log.md, "What S6 settled" -- every exposed hook event registered against a
               THROWAWAY project dir, identical foreground and backgrounded subagents
               launched, and the answer corroborated by grepping the installed binary's
               own string table for every hook_event_name literal. Reuse that method.
             - slices.md field evidence item 7: the installed build carries
               `SendMessageTool` in its string table. That is a target's existence and
               NOTHING ELSE. Do not read it as leaning either way.
             - hooks/hooks.json as it stands: PreToolUse `Agent|Task` and `Bash`,
               PostToolUse `Agent|Task` and `Bash`. Every entry has a live consumer.
Constraints: - THE ONLY DELIVERABLE IS THE ANSWER: which ONE of the three is true. (a) the
               matcher fires AND the payload carries the target agent id; (b) it fires
               WITHOUT it; (c) it does not fire. No design, no record type, no reader
               change, no prototype that stays. A spike that returns a design has exceeded
               its brief (SP1).
             - "DOES NOT FIRE" IS A SUCCESS (SP2). It closes RS permanently and the unit
               continues into Arm B. Do not retry it, work around it, add a second
               matcher, ask to be re-briefed, or report STATUS: blocked for it.
             - (a) requires BOTH halves and they are recorded separately: that the hook
               ran at all, and that the payload the hook received on stdin carried the
               target agent id (`to`/`recipient` on the input, or `resumedAgentId` on the
               response). "Fires without the payload" is answer (b), collapses to Arm B
               for a DIFFERENT recorded reason -- RS2's exact-match is unachievable without
               the id -- and SP5 records the two negatives distinctly.
             - EVIDENCE IS STATE ON DISK AFTER A REAL RUN (SP3). Cite a file's contents,
               or its provable absence, and quote it. The harness is not evidence about
               this question and a green suite is not cited, ever.
             - The probe is SELF-CONTAINED AND OUTSIDE THIS REPOSITORY: a throwaway project
               dir, its own settings registering a probe script that lives in that dir,
               dumps its stdin to a file in that dir, and exits 0. Drive it with a FRESH
               session in that dir so registration is loaded at that session's own start
               -- that is the only route an agent can take, because you cannot restart the
               session you are running inside.
             - NEVER touch this repository's hooks/hooks.json, and never reinstall or
               modify the plugin snapshot the maintainer's live session is running. A probe
               that perturbs the live install perturbs the lanes running beside it.
             - CLEANUP IS AN EXPLICIT STEP, NOT AN INTENTION (SP4). Before returning, in
               this order: (1) delete the throwaway dir and the probe script; (2) run
               `git status --porcelain` and paste it into your return; (3) run
               `git diff -- hooks/hooks.json` and paste it (expected: empty); (4) confirm
               every script named in hooks/hooks.json still exists and is executable. All
               four run whichever answer you got.
             - The corroborating read is second, never first, and never sufficient on its
               own for a POSITIVE answer: grep the installed build's string table for the
               hook-event and tool-name literals, the way S6 did. It can support (c). It
               cannot establish (a).
             - IF YOU CANNOT CONSTRUCT A REAL RESUME AT ALL, return `needs-decision`
               naming exactly what you could not construct and what you tried. Do not
               report one of the three answers from a run that did not contain a resume.
               "Could not construct one" is NOT one of the three answers, and dressing it
               as one is the single worst outcome available to this slice.
Output:      docs/loop/decisions.md -- one appended dated entry naming exactly ONE of the
             three answers, the probe another person can re-run, the file whose contents
             are the evidence (quoted), and, for a negative, which of the two negatives it
             was. Plus the standard return, carrying the four cleanup outputs above.
             NO harness cases (+0), and that is stated rather than disguised: the suite
             cannot exercise registration, so a fixture case here would prove nothing
             about the question asked.
Done when:   decisions.md carries a dated entry naming exactly one of the three answers,
             with on-disk evidence quoted and a probe a second person can re-run to reach
             the same answer; git status is clean; hooks/hooks.json is unchanged.
Test set:    THIS SLICE'S PROOF IS AN EXPERIMENT, NOT A HARNESS CASE. The named
             experiment, in order:
               1. Throwaway project dir + probe script + registration for SendMessage on
                  both PreToolUse and PostToolUse. Confirm the probe fires AT ALL by
                  triggering a tool the existing matchers already cover -- a control arm,
                  so a silent probe cannot be mistaken for a silent hook.
               2. In a fresh session in that dir: launch a background subagent, let it
                  finish or stop it, then resume it with SendMessage.
               3. Read the dump file. Answer (c) if it holds nothing for the resume;
                  (a) or (b) according to whether the recorded payload carries the target
                  agent id. Quote the bytes either way.
               4. Corroborate a (c) by the string-table read. Do not corroborate an (a)
                  that way -- it cannot.
             Fails now: spec.md records RE12 as UNKNOWN and deliberately unasserted, and
             nothing in this repository has ever exercised a matcher on this tool.
             Passes after: exactly one of the three answers is recorded with on-disk
             evidence and a re-runnable probe.
             THE CONTROL ARM IN STEP 1 IS THE POINT. Without it, a probe that never ran
             and a hook that never fires are the same observation.
Do NOT:      - Do not design, prototype, or land any capture mechanism, not even behind a
               flag, not even as a comment. G0 forbids committing to a design before this
               returns.
             - Do not modify hooks/hooks.json, any script, any test, or README in the
               returned diff. The diff is one markdown file.
             - Do not write to this repository's .claude/ directory or its real ledger.
             - Do not reinstall, upgrade, or reconfigure the plugin in the maintainer's
               live install. If the answer turns out to be reachable ONLY that way, return
               `needs-decision` -- it is a human-scheduled action, not a build step.
             - Do not re-test SubagentStop registration. Closed by measurement (E3).
             - Do not read, scrape, or parse session transcripts. Declined permanently on
               2026-08-19; this spec's transcript figures are evidence and never a data
               source.
             - Do not read Laravel Guild's .claude/agents-board.jsonl, as input or as a
               cross-check.
             - Do not phrase the entry toward an answer you did not establish, and do not
               recommend an arm. Recording the answer is your job; choosing what to build
               on it is not.
             - RV7 standing: the probe may not block, delay, or steer anything, and every
               path exits 0.
Depends on:  nothing. It shares no file with S1-S3. It shares decisions.md's end-of-file
             with S4 -- whichever lands second re-reads the end of the file and appends
             after the other.
```

## Stage 3 — NOT CUT, and why cutting it now would be a defect

**Not cut, deliberately, and this is the whole reason the pass stops at five slices.** `spec.md`
states it in terms this gate does not soften: *"No slice in group `RS` may be written, cut, or
started until the spike's answer exists. A slice list that contains an `RS` slice before `SP` has
returned is a G1 defect, not an optimisation."*

**The one-line reason:** a slice envelope names files, outputs, tests and a record shape, so writing
one now would commit this repository to a capture design chosen against a mechanism the spec records
as unestablished in **both** directions — which is not efficiency, it is the design decision the
gate withheld, arriving from a slicer instead of from evidence.

**Which arm owns which criteria, so whoever returns knows the work is scoped and not blank:**

| If `SP` returns | Arm | Criteria that arm owns |
|---|---|---|
| **fires AND carries the target agent id** | **A** | `RS1`–`RS11`. Plus `DC-R1` (a field condition, the human's, after a real run) |
| **fires WITHOUT the payload** | **B** | `RB1`–`RB3`, with `RB1`'s recorded reason being *exact-match resolution is unachievable without the id* — distinct from the answer below |
| **does not fire** | **B** | `RB1`–`RB3`, with `RB1`'s recorded reason being *the matcher does not fire*. `RS` closes **permanently**, and that is a success |

`DC-R2` is reachable under either arm and is the human's, on a real unit that had a resume;
`ship-gate-blind-to-ci`'s `log.md` is its reference case.

**What is already known about the shape of that second cut, so the deferral is not a blank:**

- **`RB1`'s first half is already discharged by `SP5`.** The spike's entry *is* the record of the
  answer. Arm B's remaining work is the two things `spec.md` says are easy to skip: marking `RS`
  **closed, not deferred**, so other units stop carrying it as a coupling; and wording the appended
  clause as a **standing limitation** (`RB2`), with no vocabulary implying a figure is forthcoming.
  Arm B is small, and it is small in exactly the two places where "small" turns into "skipped".
- **Arm A's first act is a read, not a slice.** `RS10` needs both parser programs in
  `cost-ledger-lib.sh`, which `cost-log-section-parse-error-on-macos-ci` will have changed, and the
  writer half sits in `record-cost-event.sh`, which `stale-evict-lock-permanently-defeats-the-cap`
  will have changed. **Whoever cuts Arm A reads both units' landed diffs before writing an
  envelope**, not after.
- **Arm A inherits a discovered red.** Field evidence item 3: a well-formed record whose event the
  reader does not recognise is reported as *"malformed or truncated, not JSON"*. `RS10` forbids a
  record being reclassified into a category it cannot support, so this is Arm A's to fix, in **both**
  parser programs in one commit, and it is the case that goes red before Arm A's own record type
  exists. `RS10` does not currently name it.
- **`RS11`'s mechanical constraint decides the writer's shape before anyone chooses one.** `agentId`
  arrives on `tool_response`, so it can only reach the **finish** record — never the start.
- **Expect Arm A to be largely sequential.** Every case-adding slice touches README's literal, and
  the harness's last case is the arbiter. Pin per-slice **deltas**, never an absolute, for as long as
  any neighbour is in flight.
- **`RS2` is not a licence for a selector.** No `--agent-id` flag, no new way for a human to
  nominate which invocation a figure belongs to. That rejection is extended, not reopened.
- **A resume record consumes ledger lines against the cap.** More records means more pressure on the
  mechanism the second neighbour repairs, which is exactly why this unit lands third.

## RU3 — settled as far as it can be settled, and the residue named precisely

`spec.md` hands this to G1: under Arm A, a unit with **one attached and one unattached resume** has
two facts to state in one appended clause that must not grow into a paragraph. Here is the honest
answer, in two halves.

**Settled here: the wording RULE, which is shape-independent.** Three constraints, each assertable
without knowing anything about Arm A's record:

1. **One clause, `; `-delimited, appended after every existing suffix.** The sentence stays **one
   line**. This is the grammar the sentence already uses — it has been extended twice that way (the
   coverage share and wholly-unobserved phases, then the transcribed clause), and both extensions
   are parenthetical-count clauses, not sentences.
2. **Both facts ride in one clause via a parenthetical split**, not two clauses and not two
   sentences. Candidate literal, in the sentence's own established grammar and offered as a
   candidate rather than a pin:
   `; 2 resumed run(s), none carrying a token figure (1 attached to a recorded invocation, 1 unattached)`
3. **No per-run figure, no `0` standing in for "unavailable", no dash.** `L3` and `RV3` both bite
   here, and `RB2`/`RS9`'s discipline applies to the wording under Arm A too: nothing in the clause
   may imply a figure is forthcoming.

Assertable at Arm A time without freezing the literal: the prefix is byte-identical; the sentence is
one line; the number of `; `-delimited clauses grows by exactly one; the clause contains both the
attached and the unattached count; the clause contains no token figure.

**Not settled here, and the reason is not shyness.** `spec.md` recommends settling it *against a
real fixture*. **A fixture is a literal JSONL line, so writing one is proposing Arm A's record
shape** — the exact commitment this pass withholds. Rendering it instead from the library's globals
(`COST_N_RESUMED`, `COST_N_RESUMED_ATTACHED`) avoids the record shape but pins **variable names**,
which is a lighter commitment and still a commitment made before the arm exists, and it would be
unreachable anyway under Arm B, where there are no such globals at all.

So: **the rule is settled, the literal is a candidate, and the freeze happens in the arm.** If the
human would rather pin the literal now, option 2 at the gate names it — it costs one line here and
one design commitment nobody can yet check.

## Order and concurrency

```
lane 1:  S1 ──► S2 ──► S3 ──► S4
lane 2:  S5  (independent; gates Stage 3)
```

**Critical path: S1 → S2 → S3 → S4.** **Parallel: 2 lanes** — the S1→S4 chain, and S5 alongside it
from the start.

**Why lane 1 is sequential and calling it parallel would be dishonest.** All four append harness
cases and all four bump README's one case-count literal, whose value the harness's own last case
asserts. Two such lanes collide on that number by construction and the loser's merge leaves the suite
red on a case its diff never touched. That is a **textual** dependency and every envelope says so
with the reason attached, because `Depends on: S2` with no reason reads as a missed lane.

**Why S5 genuinely is a lane.** It touches no script, no test, no README — its whole diff is one
appended `decisions.md` entry, and its work happens in a throwaway dir outside the repository. Its
only overlap is `decisions.md`'s end-of-file, shared with S4 and with both neighbouring units'
closing slices; whichever lands second re-reads the end of the file and appends after.

**On the spec's `RV` → `SP` ordering.** `spec.md` orders Stage 1 first "always", and the reason it
gives is that the unit then delivers value even if the spike returns the worst answer. That is a
**priority** rationale, not a file dependency — and running S5 concurrently honours it, because a
parallel spike delays nothing in lane 1. Starting S5 early matters: it is the long pole (a fresh
session, a constructed resume, possibly a human-scheduled action), and it is the only thing Stage 3
waits on. **The rule the concurrency does not relax:** an early answer from S5 does not license
cutting `RS` before lane 1 has shipped — Stage 1 ships first regardless, and Stage 3 is cut at a
second G1.

## Self-audit against the five-point G1 test

Run on my own bench before this reached the gate. Two things went back and are recorded below the
table.

| Test | S1 | S2 | S3 | S4 | S5 |
|---|---|---|---|---|---|
| **1. One owning agent** | `loop-build` | `loop-build` | `loop-build` | `loop-build` | `loop-build`, one question |
| **2. One commit's worth** | One README paragraph + 3 cases | Tests only, +6 | Tests only, +4 | One `decisions.md` entry + 2 cases | One `decisions.md` entry, no cases |
| **3. Independently testable** | 3 cases, all three red today against today's README | 6 cases; 4 exercise a fixture class nothing reads today, 2 are locks proven by mutation | 4 locks, each with its named mutation and the surface it covers | 2 cases; case 1 red today | An experiment with a control arm; the answer is recorded in neither direction today |
| **4. Criteria as observable behaviour** | A paragraph a grep finds, stating three facts | Absence in output and docs; figures that do not move; exit 0 | A red under a named one-line mutation | An entry a reader of `decisions.md` alone can act on | A file's quoted contents, or its provable absence |
| **5. Dependencies explicit** | `nothing` | `nothing` logically; textual on S1, with the reason | `nothing` logically; textual on S2 | `nothing` logically; textual on S3 and on the neighbours | `nothing`; `decisions.md` overlap with S4 named |

**Set sizes: 3, 6, 4, 2, experiment.** All inside `test-design`'s healthy band. `S2`'s six is the
largest and it is three criteria that share one mechanism (assert an absence over a fixture), not
three behaviours — a set of eleven would have been the signal to cut again.

**Sent back to myself during this pass, and re-cut:**

1. **An earlier version folded `RV8`'s `decisions.md` entry into `S1`**, on the house precedent
   that documents `README` + `decisions.md` in one slice (`BG` S5, `RD` S6). **Rejected**, for a
   dependency reason rather than a size one: `decisions.md`'s end-of-file is being written by two
   in-flight neighbours, and folding it into the seam would make the one slice that closes RE11 wait
   on both of them. S4 is last for that reason and says so.
2. **An earlier version gave `S2` a whole-output byte-identity assertion for a fixture holding an
   unrecognised record.** **Rejected on evidence:** that diff is non-empty today (field evidence
   item 3), so the case would either land red or quietly ratify a report calling a well-formed
   record "malformed". `RV3` enumerates figures, so the case asserts figures, and the residue is
   handed to Arm A as a finding.

## Criterion traceability — assigned, cross-cutting, or explicitly not yet assignable

| Criterion | Where it stands after this pass |
|---|---|
| **RV1** | **S1** |
| **RV2** | **S2**, both halves (live output, documentation). A lock: verified already true today, and its value is that Stage 3 cannot break it silently |
| **RV3** | **S2**, for the figure set it enumerates, against a fixture holding a record class the reader does not know. **Its arm-dependent half — the same assertion against Arm A's real record — belongs to the arm**, because no such record exists to write a fixture for. Split, and both halves named |
| **RV4** | **S3**, and specifically the two surfaces no frozen block covers (the budget gate's output, `log.md`'s `## Cost` section). The report is already frozen three times. **Its own assertion, never folded into a behavioural case**, per the gate brief |
| **RV5** | **Cross-cutting, per-slice gate.** Every slice returns `bash tests/guardrails.test.sh` green at a count above its own base, with no existing case edited, renumbered, skipped or weakened, and `shellcheck -S warning scripts/*.sh` clean |
| **RV6** | **S2** |
| **RV7** | **Cross-cutting, and structurally live this pass:** four of five slices have a markdown-or-tests-only diff and the fifth touches nothing in the repository at all, so no code path exists that could block, delay or steer. It is on every slice's `Do NOT` regardless, because it binds Stage 3 next |
| **RV8** | **S4** |
| **RV9** | **S3**, as a lock on the prefix's position and identity. **There is no unconditional append in Stage 1** — see the flagged reading below. The append itself belongs to whichever arm `SP` opens |
| **SP1–SP5** | **S5**, all five, one slice. `SP4`'s cleanup is four numbered outputs in the return, not an intention |
| **RS1–RS11** | **Arm A, at the second G1.** Not assignable now, by G0 decision |
| **RB1–RB3** | **Arm B, at the second G1.** `RB1`'s first half is discharged by `SP5`'s entry; the closure marking and `RB2`'s wording are not |
| **DC-R1** | **Arm A only, and the human's** — a real run, proven by state on disk. Not a G2 criterion and not any builder's |
| **DC-R2** | **The human's, either arm** — recognised by someone who watched the run, against `ship-gate-blind-to-ci`'s `log.md`. `cost-measurement-v0.2`'s DC1 and `cost-reporting-v0.3`'s DC2/DC3 stay open and separate; do not let any of these be reported as another |
| **RU1** | **Not this pass's, and not a slice.** It is `RS3`'s evidence note under Arm A; the safe rule (record only where the marker is present) needs no evidence about the negative branch |
| **RU2** | **Nobody's slice, by the spec's own costing.** Worth checking opportunistically at the next real resume |
| **RU3** | **Settled as a rule here, literal offered as a candidate, freeze deferred to the arm.** Reasoned above |

### The one reading of an approved criterion this pass makes — flagged, not buried

**`RV9` has no unconditional append in Stage 1, and that follows from `RV4`.** `RV9` says the
prefix stays byte-identical and *"any new wording is appended after it"*. `RV4` says a ledger with
**no resume information** reports **byte-identically to today**. Every ledger that exists today is
resume-free — nothing anywhere writes a resume record — so any clause appended unconditionally in
Stage 1 would appear in every report and break `RV4` on the spot, taking the three existing frozen
report blocks red with it.

Read here as: **`RV9` in Stage 1 is a lock (S3), and the append is the arm's.** `RV1`'s statement
therefore lands in README (documentation), not in the coverage sentence (output). That is consistent
with `RV1`'s own check, which names README and grep.

**If the human intended the coverage sentence itself to carry an unconditional resume clause from
Stage 1, that conflicts with `RV4` and is theirs to resolve, not a builder's.** Option 2 at the gate
names it. The weaker alternative, if they want it: append the clause **conditionally on a resume
being present** — which cannot be built or tested until a resume record exists, i.e. it is the arm's
work either way.

## Cross-unit collisions and landing order

Both other approved units are **specced and being cut concurrently**; neither has a `slices.md` yet.
`spec.md` fixes the order: `cost-log-section-parse-error-on-macos-ci` first, then
`stale-evict-lock-permanently-defeats-the-cap`, then this unit.

| Surface | Shared with | Resolution |
|---|---|---|
| `README.md`'s case-count literal (`## Development`) | both neighbours | **Deltas only, never an absolute.** Five-step build-time rule above; the harness's last case is the arbiter; a lane whose honest delta differs states it |
| `tests/guardrails.test.sh` | both neighbours | Append **before** the final `docs (case count)` case. Different sections in practice; the literal is the real collision |
| `docs/loop/decisions.md`'s end-of-file | both neighbours (their closing slices) **and** S4 ∥ S5 | Re-read the end of the file immediately before appending; append after whatever is there; never edit an existing entry |
| `scripts/record-cost-event.sh` | `stale-evict-lock-permanently-defeats-the-cap` | **Zero collision this pass** — no slice here touches it. Arm A's writer half does, and reads that unit's landed diff first |
| `scripts/cost-ledger-lib.sh`, both parser programs | `cost-log-section-parse-error-on-macos-ci` | **Zero collision this pass.** `RS10` rebases onto it at the second G1 |
| `hooks/hooks.json` | nobody | Unchanged by S1–S4; S5 never touches this repository's copy |

**Recommendation:** this pass is markdown-and-tests only, so it can land alongside either neighbour
*provided* the delta rule is honoured. If a neighbour is mid-merge, land its harness-touching slices
first — that is a preference for a quieter merge, not a correctness requirement, and the delta rule
is what makes either order survive.

## Riskiest slice: **S5**

**Not the locks, and not for the reason a spike usually gets nominated.** `S5` is not the riskiest
because its answer is unknown — the whole `RV` → `SP` ordering exists to contain that, and an
`unknown` or a `does not fire` lands back at a gate with S1–S4 already shipped and the unit
complete rather than failed.

**`S5` is riskiest because it is the only slice that can return a positive result that is wrong,
and its positive answer is the only thing that opens the most expensive arm in this unit.** Three
specific ways it can be wrong, and nothing in this repository can tell them apart from the right
answer once the entry is written:

1. **A fused observation.** Answer (a) has two halves — *it fired* and *the payload carried the
   agent id* — and they are one sentence apart. A lane that observes a hook running and then finds
   an agent id **anywhere** in what it dumped (its own scaffolding, an `Agent` launch's response
   that the resume also triggered, the probe's own arguments) records (a) when the truth is (b). Arm
   A is then built on an exact-match join against a field that will not be there, and `RS2`'s
   fixtures will pass because fixtures are written to the shape the entry claimed.
2. **A silent probe read as a silent hook.** If the probe script never ran at all — wrong path, not
   executable, registration not loaded by that session — the dump file is empty, which is
   *indistinguishable* from answer (c). And (c) is the answer that **closes `RS` permanently**. A
   wrong (c) forecloses the whole capture route on the strength of a typo. **This is what the
   control arm in step 1 of the test set is for, and it is the line in that envelope worth reading
   twice at this gate.**
3. **The wrong bus.** A `SendMessage` may trigger a nested tool call that the *existing*
   `Agent|Task` matchers already cover. A lane that sees `record-cost-event.sh`-shaped activity and
   concludes the matcher fired has observed a different hook firing for a different tool.

The negative direction carries its own quieter risk: a lane that cannot construct a resume and
softens that into "does not appear to fire" hands the human a **permanent foreclosure** dressed as
a measurement. The envelope's answer to that is a hard one: `needs-decision`, naming what could not
be constructed. "Could not construct one" is not one of the three answers.

**Runner-up: `S3`.** A frozen block captured from the wrong baseline encodes a bug as the contract,
and it does so *invisibly* — the case is green forever and every future change is measured against
it. Two ways that happens here: generating a block from a run with `jq` absent, and generating it
before merging `main` when a neighbour has already changed the output. Both are named as constraints,
and both are why the block-generating step is required to be a real run on a merged base with both
parsers present.

**Not nominated, and worth saying why: `S1`.** It is the slice the whole unit's value rests on, and
its worst failure is a paragraph a human disagrees with at G2 — visible, cheap, one sentence to fix.

## Questions for the human at this gate

Recorded here because the gate brief forbids asking directly, and surfaced in the return.

1. **`RV9`'s append (the flagged reading above).** Confirmed as a Stage-1 **lock**, with the append
   belonging to the arm? Or did you intend an unconditional clause in the coverage sentence now — in
   which case `RV4` needs amending, and three existing frozen blocks change.
2. **`RU3`'s literal.** Rule settled and literal left as a candidate, as cut? Or pin
   `; N resumed run(s), none carrying a token figure (A attached to a recorded invocation, U
   unattached)` now, accepting that it is a design commitment nobody can check until the arm exists.
3. **`S5`'s reach.** If the answer proves reachable only by registering a matcher in your **live**
   install (a reinstall and a restart you perform), that is a human-scheduled action and the lane
   will return `needs-decision` rather than doing it. Confirm that is the boundary you want.

## G1

```
# Slices — resumed-invocation-never-reaches-the-ledger

Slices: 5 cut (RV + SP)  ·  Parallel: 2 lanes (S1→S4 chain ∥ S5)  ·  Critical path: S1 → S2 → S3 → S4
Riskiest: S5 — the only slice that can return a wrong POSITIVE: a fused observation records
          "fires and carries the id" when only the first half is true and opens the most
          expensive arm on a join key that is not there; an empty dump from a probe that never
          ran is indistinguishable from "does not fire", which closes RS permanently.

S1 · README states a resumed run is recorded nowhere and a killed attempt's tokens nowhere at all
     (RV1) — the seam, the only red-before in the pass          · depends on nothing
S2 · locks what output and docs may never claim: no completeness, no invented figure, no refine
     pass (RV2, RV3, RV6)                                        · nothing (textual: S1)
S3 · locks the coverage sentence's prefix as a PREFIX, and freezes the gate's output and log.md's
     cost section — the two surfaces RV4 names that nothing covers (RV9, RV4) · nothing (textual: S2)
S4 · decisions.md records that this unit cannot raise pricing coverage; routing bullet untouched
     (RV8)                                                       · nothing (textual: S3, neighbours)
S5 · SPIKE: which of three answers is true for a matcher on SendMessage (SP1–SP5), +0 cases,
     proof is an experiment with a control arm                    · depends on nothing

Stage 3: NOT CUT. An RS envelope now would commit the repo to a capture design against a
         mechanism unestablished in both directions — G0 calls that a G1 defect. Arm A owns
         RS1–RS11; Arm B owns RB1–RB3 (RB1's first half already falls out of SP5). Cut at a
         second G1 off S5's answer.

1. Approve — brief S1 first, S5 in parallel from the start  (recommended)
2. Re-slice — most likely targets: RV9's Stage-1 reading (lock vs unconditional append), or
   pinning RU3's literal now instead of at the arm
3. Spec is wrong — back to loop-spec
```
