# Slices — cost-ledger-blind-to-background-agents

Cuts `spec.md` (G0 approved, five decisions taken: **OQ1 = both, claim first**; **OQ2 = a spike
answers it before any recovery design**; **OQ3 = a human-set coverage floor, unset means today**;
**OQ4 = out of bounds**; **OQ5 = yes, permanently**) into six slices, plus a **second G1** for the
RC group that cannot honestly be cut yet.

**6 slices · 2 genuinely parallel at t0 (S1 ∥ S6) · critical path S1 → S2 → S3 → S4 → S5 (5 deep)**

Every CL, X, RC and DC criterion is assigned below to exactly one slice, or named as cross-cutting,
as deferred to the second G1, or as a field condition. Nothing is dropped.

---

## The seam

The smallest change that delivers observable value is **`/cost` naming, for each invocation it
cannot price, the reason its own record gives — with "launched in background, outcome never
observed" as a category of its own** (S1). Today a reader sees `2 unpriced` and `0 invocation(s)
... in flight` for a unit whose two build lanes were still running (E5), and cannot tell a
backgrounded launch from a malformed line. After S1 they can. That is the whole problem statement
in one section of one report, and it is the spine everything else in group CL hangs off: S2 sizes
the gap, S3 explains it, S4 decides when it is too large to print a total through, S5 documents it.

Deliberately **not** the seam:

- **The coverage floor (S4).** It is the only slice that can suppress a figure a reader is used to
  seeing. It must sit on top of a share that is already correct (S2) and a gap that is already
  explained (S3), or it suppresses a total and offers nothing in its place.
- **The recovery mechanism.** OQ2's answer is unknown and the G0 decision forbids designing
  against it. S6 buys the answer; the design is cut afterwards.
- **A classification helper in `cost-ledger-lib.sh` on its own.** A library with no caller is a
  refactor, and refactors are their own slices. The scan-program change ships inside S1, with the
  variables it adds pinned below so S2, S3 and S4 consume them without re-deriving them.

---

## Order and concurrency

```
t0  ├── S1  Reason per unpriced invocation; a launch is not a finish   ← critical path
    │        │
    │        └─→ S2  Coverage as a share, wholly-unobserved phases named (report + gate)
    │                 │
    │                 └─→ S3  The report says why the gap exists
    │                          │
    │                          └─→ S4  Human-set coverage floor; below it, no unit total
    │                                   │
    └── S6  SPIKE: can a hook reach the channel? (OQ2) ───────────────┐│
                                                                      ▼▼
                                                              S5  README + decisions.md
                                                                   │
                                                                   └─→ SECOND G1: RC group
```

- **Genuinely parallel at t0: S1 and S6.** Two builders, two worktrees, zero shared files. S1 is
  `scripts/cost-ledger-lib.sh` + `scripts/cost-report.sh` + `tests/`. S6 writes one appended entry
  to `docs/loop/decisions.md` and touches no script and no test.
- **Nothing else parallelises, and that is the honest graph, not a missed opportunity.** S2, S3 and
  S4 all rewrite the same twenty lines of `cost-report.sh`'s Coverage/Tokens region. Running any
  two concurrently produces a conflict in a file the graph would have called independent — a G1
  defect by the worktree-merge rule — so they are sequenced. Two in flight at t0, one thereafter.
- **S1 → S2 is sequencing, not arithmetic.** S2's share and wholly-unobserved phase names are
  computable from variables that already exist today. It is sequenced behind S1 because both edit
  `cost-ledger-lib.sh` and the same report section. If the human wants more parallelism, this is
  the edge to challenge — but the cost of that conflict lands on whoever merges second.
- **S3 → S4 is a real chain.** CL5 requires the suppressed-total case to still state the cost as
  *not established* rather than absent; that statement is only intelligible next to S3's
  explanation of why the gap exists. Shipping S4 first prints a refusal with no reason.
- **S5 depends on S4 and on S6, both for real reasons.** On S4, because S4 lands a guard asserting
  no number for the coverage floor appears anywhere including README, and S5 is what writes README;
  S5 must keep that guard green. On S6, because S5 records the spike's answer in `decisions.md`
  alongside X6's in-place correction of the superseded bullet — the same file S6 appends to. S5
  merges later and therefore owns any overlap there. This is an *expected*, owned overlap, not an
  independence claim.

---

## Pinned contracts, so no two slices derive the same thing twice

These are decided here, at G1, because discovering them at build time costs a rewrite.

| Contract | Value | Why it is pinned |
|---|---|---|
| `COST_N_UNPRICED` | Keeps its present meaning and value — the **total** of all unpriced invocations | Existing case (g) at `tests/guardrails.test.sh:736` asserts it equals 2 for a fixture holding one `async_launched` and one `line_too_long` invocation. CL8 requires that case to pass **unmodified**. S1's categories are *additional* counters, never a redefinition. |
| S1's new counters | `COST_N_UNPRICED_<REASON>`, and per phase where the report needs it | Same naming shape as the existing `COST_N_*_<PHASE>` family, so `print_phase_row`'s indirect expansion pattern works unchanged. |
| The reason set | Taken from the finish record's own `status` field and nothing else: `async_launched` → launched in background; `completed` with no `total_tokens` → observed, no usage figure; `line_too_long` → truncated; absent/empty `status` → not stated. Never inferred from phase, agent, or duration. | CL1's "taken from what its record says and never guessed". Every one of these values is already written today by `record-cost-event.sh`; **no new field is written by group CL.** |
| `cost_coverage_sentence()` | Its current text stays a **literal prefix**. Additions are **appended**, never reworded, and the result stays **one line**. | `tests/guardrails.test.sh:1123` greps the breach message for the current sentence with `grep -qF` — a substring match that survives an append and dies on a rewrite. CL8 is only satisfiable this way. The one-line rule protects the `--phase` FLAG line, which is pasted verbatim into a return bound to ≤10 lines. |
| The floor's variable | `LARAVEL_LOOP_COST_MIN_COVERAGE`, a percentage 0–100, **unset by default and no number anywhere** | Pinning the *name* keeps S4's implementation and S5's README from diverging. Pinning a name is not shipping a number. |
| Floor comparison | Against the coverage **share**, not the count | CL4: "1 of 25" and "1 of 3" are not equivalent claims, so the floor cannot be a count. |

---

## Slices

### S1 — Report the reason each unpriced invocation is unpriced, and stop presenting a launch as a finish
```
Owner:       loop-build
Context:     scripts/cost-ledger-lib.sh (_cost_scan_jq_program, _cost_scan_py_program,
             _cost_reset_scan_vars, _cost_apply_scan_line — the two parser programs are
             behaviourally identical and must stay so); scripts/cost-report.sh
             (print_coverage_and_tokens, print_phase_row); tests/guardrails.test.sh
             (the existing mixed fixture near line 672 and case (g) near 720 are the
             prior art — extend that pattern, do not invent a second one);
             spec.md CL1, CL2, CL9, E5.
Constraints: - COST_N_UNPRICED keeps its current meaning and value (pinned table above).
             - Reasons come only from the finish record's `status` field. Nothing is
               inferred from phase, agent, duration, or absence.
             - jq and python3 scan programs stay behaviourally identical; both updated.
             - Zero new dependency; jq -> python3 -> safe no-op (X3).
             - shellcheck -S warning clean; existing 334 cases pass unmodified (CL8, X1).
Output:      Updated cost-ledger-lib.sh + cost-report.sh + new harness cases.
Done when:   /cost on a fixture holding one priced spec invocation and two finish records
             with status "async_launched" prints those two in their own named category
             ("launched in background, outcome never observed" or equivalent wording that
             names backgrounding), separately from truncated, no-usage-figure, and
             in-flight; and the in-flight statement no longer stands as a bare "0" while
             such invocations exist.
Test set:    6 cases. Rule: one per reason CL1 enumerates (status is the only input that
             selects the category, so a cross-product buys nothing), plus the one boundary
             CL2 names, plus CL9's pre-existing-record case.
               1. async_launched + null tokens -> named as backgrounded          [CL1]
               2. completed + null tokens      -> named as observed-without-usage [CL1]
               3. status "line_too_long"       -> named as truncated             [CL1]
               4. start with no finish         -> still in flight, not a reason  [CL1]
               5. two async_launched present   -> in-flight statement does not
                  read as a bare 0 (E5's exact defect)                           [CL2]
               6. a finish record with no `status` field at all -> read without
                  error, not reclassified as backgrounded                        [CL9]
             Plus one characterisation case, honestly labelled as such: a ledger with
             2 priced + 20 unpriced totals identically to the same ledger with the 20
             removed (CL7). It is green before and after — it exists to hold S2/S4 and
             the RC group to CL7, not to prove S1.
Fails today: no case asserts any reason string; `grep` for a backgrounding reason in
             /cost output returns nothing, and the in-flight line prints 0 for the
             two-async_launched fixture.
Do NOT:      - Do not touch scripts/record-cost-event.sh. Group CL writes no new field
               and changes no record shape; every value it needs is already recorded.
             - Do not touch hooks/hooks.json.
             - Do not change any total, any share, or COST_N_UNPRICED's value.
             - Do not add the coverage floor, the share, or the gap explanation — S2/S3/S4.
             - Do not modify any existing harness case.
Depends on:  nothing
```

### S2 — State coverage as a share, and name the phases that are wholly unobserved
```
Owner:       loop-build
Context:     scripts/cost-ledger-lib.sh (cost_coverage_sentence — the single shared
             formatter both the report and the gate call, by CV7/CV8 design);
             scripts/cost-report.sh; scripts/check-budget-gate.sh (the partial-coverage
             notice near line 354, the breach message near 368, the --phase check near
             421); tests/guardrails.test.sh:1109-1124 (the verbatim-substring case);
             spec.md CL4, CL6.
Constraints: - The current sentence stays a literal prefix; additions are appended and
               it stays ONE line (pinned table above). This is what makes CL8 possible
               and what keeps the --phase FLAG line inside the ≤10-line return shape.
             - "Wholly unobserved" means a phase with at least one invocation and zero
               priced. A phase with no invocations at all is NOT wholly unobserved and
               is not named — absence is not a gap.
             - Computed from the per-phase variables cost_scan already sets. No second
               parse, no second implementation of the arithmetic (CV7).
             - shellcheck clean; existing 334 + S1's cases pass unmodified.
Output:      Updated cost-ledger-lib.sh, check-budget-gate.sh if needed, harness cases.
Done when:   The coverage sentence carries a percentage share as well as the counts, and
             names each wholly-unobserved phase; and the budget gate's partial-coverage
             notice carries the identical share and the identical phase names, because
             both call the same formatter.
Test set:    5 cases. Rule: one per claim CL4 makes (share; named phases) at each of the
             two call sites CL6 names, plus the two boundaries the criteria imply.
               1. report: sentence carries the share as a percentage            [CL4]
               2. report: build has invocations and zero priced -> named        [CL4]
               3. report: a phase with zero invocations is not named            [CL4 bound]
               4. gate: the partial-coverage notice carries the identical share
                  and identical phase names as the report's                     [CL6]
               5. zero invocations / zero priced -> no division by zero, no
                  malformed share, and the existing verbatim-substring case at
                  line 1123 still passes untouched                              [CL8 bound]
Fails today: `/cost` prints "based on 1 of 3 invocations that carry a token figure" with
             no percentage and no phase name; grepping its output for `%` in the coverage
             sentence, or for a wholly-unobserved phase name, returns nothing.
Do NOT:      - Do not reword or reorder the existing sentence text. Append only.
             - Do not make the sentence multi-line, and do not add a second sentence to
               the --phase check's single output line.
             - Do not change what the gate compares, when it fires, or its exit codes.
               G0-D1 is not reopened here (spec.md, Non-goals).
             - Do not add the floor (S4) or the explanation (S3).
             - Do not modify any existing harness case.
Depends on:  S1
```

### S3 — Say, in the report's own output, why the gap exists
```
Owner:       loop-build
Context:     scripts/cost-report.sh (print_coverage_and_tokens); spec.md CL3, E2,
             intent.md "Measured after the restart" — the source of the claim that the
             figure is measured by the host and delivered into the session.
Constraints: - The text describes a measured fact (E2's two probes), never a promise.
             - It is printed only where the report actually holds a backgrounded
               invocation. A fully foreground unit must not be told about a gap it
               does not have.
             - Printed once per report, not once per invocation.
             - Worded so it survives recovery landing later: it describes the residue,
               not a gap that no longer exists (CL3's own last sentence).
Output:      Updated cost-report.sh + harness cases.
Done when:   A report over a fixture containing a backgrounded invocation states that the
             figure for such an invocation is measured by the host and delivered into the
             session and is not captured here — so a reader who never opens a spec cannot
             conclude the number is unknowable.
Test set:    3 cases. Rule: happy path, its negation, and the one boundary (frequency).
               1. fixture with a backgrounded invocation -> the statement appears  [CL3]
               2. fixture with only foreground invocations -> it does not appear   [CL3]
               3. fixture with three backgrounded invocations -> it appears exactly
                  once, not three times                                           [CL3 bound]
Fails today: the report offers no reason at all for an unpriced invocation (E5); grepping
             its output for any statement about where the figure is measured returns
             nothing.
Do NOT:      - Do not state or imply that recovery is coming, planned, or possible. OQ2
               is unanswered until S6 returns, and a report is not the place to bet.
             - Do not restate what S1's categories already say, per invocation.
             - Do not touch cost-ledger-lib.sh or check-budget-gate.sh.
             - Do not modify any existing harness case.
Depends on:  S2
```

### S4 — Below a human-set coverage floor, print no unit total
```
Owner:       loop-build
Context:     scripts/cost-report.sh (print_coverage_and_tokens's Tokens branch);
             scripts/check-budget-gate.sh's existing threshold parser (the prior art for
             "unparseable disables loudly, naming field and value" — reuse the
             discipline, do not write a second parser with different manners);
             tests/guardrails.test.sh:2222 (the existing "no number in README" guard, the
             pattern to copy); spec.md CL5, CV6, and Non-goals' G0-D1 paragraph.
Constraints: - LARAVEL_LOOP_COST_MIN_COVERAGE, percentage 0-100, unset by default.
             - NO NUMBER SHIPS. Not in code, not as a comment, not as a suggested
               starting value, not in a code fence, not in README (S5 keeps this green).
             - Unset means today's behaviour, byte for byte.
             - The floor governs what is PRINTED. It does not change what the budget gate
               compares, whether it fires, or its exit codes. G0-D1 is not reopened.
             - Below the floor the cost is stated as not established and the observed
               subset is still shown, as a subset, never as a headline.
Output:      Updated cost-report.sh + harness cases.
Done when:   With the variable unset the report is byte-identical to before this slice;
             with it set above the fixture's coverage share, no unit-level token total is
             printed and the cost reads as not established; with it set at or below that
             share, the total prints as it does today.
Test set:    6 cases. Rule: one per state of the single input (unset / below / at / above
             / unparseable), plus the one interaction CV6 already owns.
               1. unset -> output byte-identical to pre-slice                     [CL5]
               2. set above coverage -> no total; "not established"; subset shown [CL5]
               3. set below coverage -> total prints as today                     [CL5]
               4. set exactly at coverage -> at-or-above prints (boundary pinned) [CL5]
               5. unparseable value -> disabled loudly, naming the field and the
                  value, and today's behaviour holds. Never silently disabled and
                  never silently enabled.                                         [CL5]
               6. zero priced invocations -> CV6's existing behaviour is unchanged;
                  the floor adds no second, contradicting statement               [CL8]
             Plus the guard case: no digit appears adjacent to
             LARAVEL_LOOP_COST_MIN_COVERAGE anywhere in scripts/, README, or docs.
Fails today: the variable does not exist; setting it to any value changes nothing, so
             case 2 (no total below the floor) fails.
Do NOT:      - Do not ship, comment out, or suggest a default value. Not one.
             - Do not derive, infer, or compute the floor from the ledger.
             - Do not write a second threshold parser with different failure manners.
             - Do not touch check-budget-gate.sh, LARAVEL_LOOP_BUDGET_WARN, or
               LARAVEL_LOOP_BUDGET_HARD.
             - Do not modify any existing harness case.
Depends on:  S3
```

### S5 — Document what the ledger can and cannot see, and correct the superseded decision
```
Owner:       loop-build
Context:     README.md's "Cost ledger" and "Cost reporting and the budget gate" sections;
             docs/loop/decisions.md — the bullet "Closing the gap needs a token figure ...
             That is upstream of this plugin, not a slice inside it"; S6's returned answer
             and its appended entry; tests/guardrails.test.sh:2140-2230 (the docs section
             — README claims are asserted by grep, so this slice is harness-testable);
             spec.md X5, X6, E2, E6.
Constraints: - X6 corrects the superseded bullet IN PLACE, with its date and the evidence
               that superseded it (E2). The rejection of a spend control at 4% coverage is
               left standing, unedited, in the same entry.
             - README says plainly that background-launched invocations are the majority
               of a /loop run and how they are treated.
             - README names LARAVEL_LOOP_COST_MIN_COVERAGE and states that unset means
               today's behaviour — with no number, keeping S4's guard green.
             - S6's answer is recorded as fact plus evidence, whichever of the three it is,
               including "unbuildable".
Output:      Updated README.md, docs/loop/decisions.md, harness cases in the docs section.
Done when:   The harness's docs cases assert README names the backgrounding gap, the floor
             variable, and "unset means today's behaviour", carrying no number; and
             decisions.md's superseded claim is corrected in place with its date and
             evidence while the 4%-coverage rejection stands untouched.
Test set:    4 cases. Rule: one per documentation claim X5 and X6 name, in the existing
             docs-section grep style.
               1. README states background-launched invocations are the majority of a
                  /loop run and how they are treated                              [X5]
               2. README names LARAVEL_LOOP_COST_MIN_COVERAGE and "unset"          [X5]
               3. no digit adjacent to that variable anywhere in README            [X5/CL5]
               4. decisions.md no longer claims the figure is upstream of this plugin,
                  AND still carries the 4%-coverage rejection verbatim              [X6]
Fails today: README says nothing about backgrounding, launch mode, or the floor variable;
             decisions.md still carries the superseded sentence. All four greps fail.
Do NOT:      - Do not edit the 4%-coverage rejection itself, or any other decisions.md
               entry. In-place correction of one bullet, nothing else.
             - Do not bump the version, write a CHANGELOG release entry, or tag. No
               criterion asks for it and /ship owns G3.
             - Do not edit spec.md or this file.
             - Do not touch any script.
             - Do not modify any existing harness case.
Depends on:  S4, S6
```

### S6 — SPIKE: establish whether a hook can reach the channel the real figure arrives on
```
Owner:       loop-build
Context:     spec.md E7 and OQ2 (the three candidate answers); intent.md "Measured after
             the restart" (the 11,035-token background probe, and that the figure arrives
             on the task-notification channel); scripts/record-cost-event.sh:509-521 (the
             hook-event switch, including the deliberate SubagentStop exit); spec.md E3
             (SubagentStop measured empty across 41 records — do not re-run that
             experiment as if it were open); docs/loop/decisions.md's rule that a hook is
             proven live by the state it writes, never by its tests passing.
Constraints: - THE ONLY DELIVERABLE IS THE ANSWER: which of OQ2's three is true, plus
               reproducible evidence. Not a working recovery, not a design, not a
               prototype that stays.
             - Probe against a throwaway CLAUDE_PROJECT_DIR. The repository's own
               .claude/ is never written to, and no probe artifact is left behind.
             - Any candidate hook registration is temporary and local to the probe.
               hooks/hooks.json is returned unmodified.
             - Evidence is state written (or provably not written) during a controlled
               live probe — this repository's own standard, per decisions.md.
             - Answer 3 ("neither") is a successful outcome of this slice, not a failure.
               Record it as such.
Output:      One appended entry in docs/loop/decisions.md stating the answer, the probe
             that established it, and what it forecloses. Plus the standard return.
Done when:   docs/loop/decisions.md carries a dated entry naming exactly one of OQ2's
             three answers, with a probe another person can re-run to reach the same
             answer.
Test set:    THIS SLICE'S PROOF IS AN EXPERIMENT, NOT A HARNESS CASE, and that is stated
             rather than disguised. The harness cannot exercise the live hook path
             (spec.md E8, decisions.md), so a fixture case here would prove nothing about
             the question asked. The named experiment:
               Launch one identical trivial agent task twice — once foreground, once
               backgrounded — with each candidate channel registered in turn against a
               throwaway project dir, and inspect that dir's ledger for a real token
               figure attributable to the backgrounded invocation.
               Fails now: the answer is not established in either direction (E7).
               Passes after: exactly one of the three answers is recorded with evidence
               a second person can reproduce.
             SubagentStop is NOT a candidate to re-test. E3 closed it by measurement.
Do NOT:      - Do not design, prototype, or land any recovery mechanism. Not even behind
               a flag. The G0 decision forbids committing to a design before this returns.
             - Do not modify hooks/hooks.json, any script, or any test, in the returned
               diff.
             - Do not write to the repository's .claude/ directory or its real ledger.
             - Do not re-test SubagentStop registration (E3).
             - Do not read or import Laravel Guild's .claude/agents-board.jsonl. It is
               evidence for the spec and must never become a data source (CO2).
             - Do not edit the superseded bullet — that is S5's X6 edit, in place.
Depends on:  nothing
```

---

## The second G1 — the RC group

**Not cut here, deliberately.** The G0 decision states that no recovery design may be committed to
before S6 returns, and a slice envelope *is* a design commitment: it names files, outputs and tests.
Writing RC slices now would be exactly the failure OQ2's recommendation warns about.

After S6 returns, re-invoke `loop-slice` on this unit for RC1–RC7 (and the remainder of CL9, whose
real red-then-green case only exists once a record field is introduced). The shape of that second
cut is already constrained by G0:

- **OQ5 = yes, permanently.** A recovered figure declares itself recovered in the record shape,
  following `model_source`'s precedent (v0.2 L11). Expect a `token_source` field, or equivalent.
- **RC must be able to fail without taking CL with it.** By then S1–S5 have merged, so it can.
- **If S6 returns answer 3**, OQ1 collapses to claim-only, the RC group is closed rather than
  built, and this unit is S1–S5. That is a complete unit, not a failed one.
- **If S6 returns answer 2** (only the main thread sees it), whether a model-transcribed figure is
  acceptable in this ledger at all is a **human decision at that second G1**, not a builder's.

---

## Criterion assignment — nothing dropped

| Criteria | Where |
|---|---|
| CL1, CL2 | S1 |
| CL4, CL6 | S2 |
| CL3 | S3 |
| CL5 | S4 |
| X5, X6 | S5 |
| OQ2 | S6 |
| CL7 | Cross-cutting. Characterisation case added in S1 (honestly labelled: green before and after), held green by S2–S5 and by the RC group. |
| CL8 | Cross-cutting. Every slice's `Do NOT` forbids modifying an existing harness case; the pinned contracts above are what make it achievable rather than aspirational. |
| CL9 | Split. Its "record with no `status` field" case is S1's case 6; its "record lacking a field this unit introduces" case belongs to the RC group, because no such field exists until then. |
| X1, X2, X3, X4 | Per-slice gates. Every slice returns green `tests/guardrails.test.sh` with a case count above the previous slice's, clean `shellcheck -S warning`, zero new dependency, and every script in `hooks/hooks.json` present and executable. |
| RC1–RC7 | Second G1, after S6. |
| DC4, DC5 | Field conditions, not G2 criteria. They need a real `/loop` run with background lanes and a human who watched it. `cost-measurement-v0.2`'s DC1 and `cost-reporting-v0.3`'s DC2/DC3 remain open and separate — do not let any of these five be reported as another. |

---

## Riskiest slice: **S2**

Not S6, and the distinction matters. **S6 has the highest uncertainty and the lowest project
risk** — its answer is genuinely unknown, but the G0 "claim first" ordering means every outcome
including "unbuildable" leaves S1–S5 intact. Uncertainty that has been deliberately contained is
not the risk to nominate.

**S2 is the riskiest** because it has the largest blast radius per line changed. It edits
`cost_coverage_sentence()`, a single formatter consumed at six call sites across two scripts: the
report's Coverage section, the report's Tokens section, the report's no-slug list mode, the gate's
once-per-unit partial-coverage notice, the gate's breach message, and the `--phase` check whose
output is pasted verbatim into an agent return bound to ≤10 lines. Two of those consumers are
constrained by things outside this unit's own criteria — an existing case greps the breach message
for the sentence **verbatim** (`tests/guardrails.test.sh:1123`), and the return-shape limit lives in
the protocol, not in `spec.md`. So S2 is the slice most likely to break a criterion it is not about:
a builder who rewords the sentence rather than appending to it satisfies CL4 and CL6 perfectly and
fails CL8, and the failure surfaces in the budget-gate section of the harness, nowhere near the
diff. The pinned contract above exists precisely to defuse this, and if one thing in this document
is worth reading twice at G1, it is that row.

Runner-up: **S4**, the only slice that removes a figure a reader is used to seeing. Its risk is
scope drift into the budget gate — a builder who reads "coverage floor" as "the gate should also
refuse to compare" reopens G0-D1, which is explicitly not reopened. Its `Do NOT` names that.

---
---

# The second G1 — the RC group (S7–S11)

**Appended after S6 returned.** S1–S6 are built, merged and green at **379 cases**; nothing above
this line is re-cut, renumbered, or edited. Slices continue the same numbering (**S7 onward**)
rather than reusing `RC`, which belongs to the spec's criteria — `RC1` is a criterion, `S9` is a
slice, and the two are never the same thing in this document.

**5 slices · 0 genuinely parallel · critical path S7 → S8 → S9 → S10 (→ S11) — strictly linear,
and that is the honest graph.**

## What S6 settled, and what it therefore makes this pass

`decisions.md`, 2026-08-14: **OQ2 answer 2.** Every hook event this build exposes except
`SubagentStop` (closed by E3) was registered and live-probed; none fired for a background
completion. The figure arrives as a `<task-notification>` block injected into the session
transcript as a queued synthetic user turn — a queue operation on the conversation, not an event
on the hook bus. **There is no channel name a `hooks.json` entry could subscribe to.**

So recovery, as approved by the human at this gate, is **the orchestrating agent transcribing a
figure from its own context into a ledger line**: a model-reported number entering a file whose
entire value is that its numbers were host-observed. **OQ5 is answered yes, permanently** — that
figure declares itself transcribed, in the record shape, forever. RC2 owns it and it is not
negotiable.

That single sentence dictates the whole shape of this cut, and it is why the order below is linear
rather than convenient: **the marker that distinguishes a transcribed figure lands two slices
before anything can write one.** S7 teaches the reader the record and labels it; S8 makes a
disagreement between a transcribed and an observed figure visible; only then, in S9, does a writer
exist at all. At no point can a transcribed figure sit in a real ledger that cannot yet say what
it is.

## The seam

The smallest change that delivers observable value is **the reader recognising an
`event:"recovered"` line: counting that invocation once, counting it priced, and saying in the
report how much of the total was transcribed rather than observed** (S7). It is provable entirely
from a fixture ledger — per the spec's own framing of group RC, *"provable from a fixture ledger
containing a recovered figure, whatever wrote it"* — so it needs no writer, no live session, and
no agent behaviour. And it is the marker: after S7, a transcribed figure is legible as transcribed
the first instant one could exist.

Deliberately **not** the seam:

- **The writer (S9).** Shipping the entry point first would put the first transcribed figure into
  a ledger that renders it identically to an observed one — the exact failure RC2 exists to
  prevent, and the risk this gate was briefed to slice against.
- **A `token_source` field stamped onto every host-written record.** It would mean editing
  `record-cost-event.sh`, which RC7 wants provably untouched, and it would make *absence* of the
  field the thing a reader has to interpret on every pre-existing record — precisely what OQ5
  warns about. The pinned table below takes the other route: the **record that carries the figure**
  declares its own origin, so there is no absence to misread.
- **Reading the figure out of the session transcript.** Technically the most faithful recovery —
  it would be host-observed rather than model-reported — and it is out of bounds here: it means
  reading the user's conversation logs outside the project directory, and the human approved
  *agent transcription* at this gate, not transcript scraping. Named in `FLAGS` as its own intent,
  not smuggled in as an implementation detail of S9.

## Pinned contracts for the RC group

Decided here, at G1, because discovering any of them at build time costs a rewrite. A builder that
believes one is wrong returns `needs-decision` rather than changing it.

| Contract | Value | Why it is pinned |
|---|---|---|
| The recovery record | Its own event type: `{"ts":<int>,"event":"recovered","invocation_id":"<id>","slug":"<slug>","total_tokens":<int>,"token_source":"transcribed"}`. No other field. | Reusing `event:"finish"` is unsafe by inspection: the scan's finish branch (`cost-ledger-lib.sh`, both parser programs) assigns `.priced`/`.tokens` **last-wins**, so a second finish record would let a transcribed figure silently overwrite an observed one — RC3's forbidden "precedence rule applied invisibly", arriving as a one-line accident. A distinct event type leaves that branch untouched (smallest blast radius on the file S2 already proved is the most dangerous here) and makes the origin readable in the raw JSONL line by eye. |
| `token_source` | The literal `"transcribed"`, written on the recovery record and on **no other record**. `record-cost-event.sh` is not touched by this group at all. | RC2 follows `model_source`'s precedent — a field that declares a value's origin (v0.2 L11). Keeping it exclusive to the recovery record is what makes RC7 provable by "the writer did not move" and what makes CL9 trivial: the reader keys on the **event type**, never on a field's absence. |
| What the reader keys on | The record carrying the figure: a `finish` record's `total_tokens` is **host-observed**; a `recovered` record's is **transcribed**. Never inferred from phase, agent, status, or a missing key. | OQ5's own wording — a reader comparing old and new records must not be able to mistake absence for observation. Under this rule there is no absence to interpret. |
| Precedence when both exist | **Visible, never silent.** The *observed* figure stays the one summed into `COST_TOKENS_PRICED`; the transcribed figure is carried alongside, and both numbers are printed with the disagreement named and the rule stated in the output. No averaging, no max, no min, no last-wins. | RC3 forbids an *invisible* rule, not a rule. The observed figure keeps the total meaning what it means today; S8 is the slice whose whole job is making that choice visible at the point it applies. |
| Counting | An invocation with a transcribed figure and no observed one is **priced**: it enters `COST_N_PRICED`, `COST_TOKENS_PRICED`, and every coverage share. One invocation, never two, however many `recovered` records name it. | RC5, plus RC1's "not a duplicate in the invocation count". |
| Where the transcribed share is stated | Wherever a total or a coverage figure that includes a transcribed figure is printed: the report's Tokens section, and the shared `cost_coverage_sentence()` — **appended**, never reworded, staying **one line**. | S2's pinned contract still binds: `tests/guardrails.test.sh:1123` greps that sentence with `grep -qF` verbatim (CL8), and the `--phase` check's output is pasted into a return bound to ≤10 lines. The shared formatter is also why the budget gate inherits the clause without a second formatting site — the gate must never compare a threshold against a partly-transcribed total while saying nothing. |
| Percentage formatting | Any new share uses the `N %` spacing S2 established. | `CV4`'s existing case asserts the literal `0%` appears nowhere in a fully-priced fixture, and a tight `100%` contains it as its own last two characters. |
| The CLI | `scripts/record-recovered-cost.sh --invocation-id <tool_use_id> --total-tokens <n>`. Standalone; never in `hooks/hooks.json`; never invoked by a hook; exits 0 on every path. | **Both values are transcribable from the one notification block**, which removes the selector-heuristic risk entirely. A real `<task-notification>` on this machine carries `<tool-use-id>toolu_01P6…</tool-use-id>` alongside `<usage><subagent_tokens>63977</subagent_tokens>…</usage>`, and `record-cost-event.sh:576` uses `tool_use_id` **as** `invocation_id`. So there is no matching by slug, slice, agent, or recency — no fuzzy join, no guessing which lane a figure belongs to. (Established by inspecting a real session transcript, 2026-08-14 — the same evidentiary method S6 used, and it is why this pass needs no second spike.) |
| Exactly-once marker | `mkdir "$FINISHED_DIR/_recovered/<sanitised id>"` — same atomic primitive as the finish marker, in its own namespace. | The finish marker for that invocation is **already taken** by the `async_launched` write, so reusing it would refuse every recovery. `.gitignore` already covers the whole `loop-cost-finished/` subtree (S5-era note in `record-cost-event.sh`), so no new ignore entry. And the notification block's own `<note>` says *"the same task-id may notify more than once"* — a second transcription is expected, not hypothetical. |
| Unknown invocation | A `recovered` record is written **only** for an `invocation_id` already present in the ledger. No match → nothing written, exit 0, one line on stderr. | RC4: nothing fabricated, no orphan record inflating any count, and "the arrival is not reported as a pending record". |
| `LARAVEL_LOOP_COST_LEDGER=0` | Disables the CLI exactly as it disables the hook writer. | v0.2's switch means *the ledger is off*, not "off except when an agent types". |

## Order and concurrency

```
S7  Reader knows a recovered figure: counted once, counted priced, labelled transcribed
     │
     └─→ S8  Observed vs transcribed disagreement: both shown, the rule stated
              │
              └─→ S9  scripts/record-recovered-cost.sh — the only writer
                       │
                       └─→ S10  README + decisions.md
                                 │
                                 └─→ S11  (OPTIONAL) instruct the orchestrator in commands/loop.md
```

**Genuinely parallel: nothing.** Stated plainly rather than padded, and each edge has its own
reason — the lesson from S2/S3/S4 is applied here, not repeated:

- **S7 → S8** is a file dependency of exactly the S2/S3/S4 kind: both rewrite the same scan entry
  in `cost-ledger-lib.sh` and the same Tokens region of `cost-report.sh`. Running them
  concurrently produces a conflict in a file the graph would have called independent — a G1 defect
  by the worktree-merge rule.
- **S8 → S9** is the **safety ordering this gate was briefed to enforce**, not a file dependency.
  S9 is the first slice that can put a transcribed figure into a real ledger; it lands only after
  the reader can label one (S7) and after a disagreement with an observed figure is visible (S8).
- **S9 → S10** is real: S10's README names the CLI by path, and documenting a script that does not
  exist yet puts a false claim on `main` for the length of a merge.
- **S10 → S11** is real for the same reason in reverse: S11 instructs an agent to run a command
  that S10 is what documents.

**The one edge worth challenging at this gate:** S10 is two things in one file pair — a README
section (which genuinely needs S9) and a `decisions.md` entry recording this second G1's decision
(which needs nothing and could run at t0 alongside S7, in the S1 ∥ S6 shape). I judged one merge
cheaper than two for a slice this small, and it is a judgement, not a constraint. If the human
wants a parallel lane at t0, split S10 and that is the seam.

## Slices

### S7 — Teach the reader a recovered figure, and say how much of the total was transcribed
```
Owner:       loop-build
Context:     scripts/cost-ledger-lib.sh — _cost_scan_jq_program and _cost_scan_py_program
             (the reduce currently branches on event "cap_trip" / "start" / "finish" and
             counts everything else as COST_N_SKIPPED; a third branch goes here),
             _cost_reset_scan_vars, _cost_apply_scan_line, cost_coverage_sentence (whose
             existing text is a literal prefix — read S2's comment block in it first);
             scripts/cost-report.sh (print_coverage_and_tokens's Tokens branch, and
             print_unpriced_reasons as the prior art for a conditional addendum);
             tests/guardrails.test.sh (S1's mixed-fixture cases are the pattern to extend);
             spec.md RC1, RC2, RC5, RC6, CL7, CL9; the pinned table above.
Constraints: - The recovery record's shape is PINNED above and is not redesigned here.
             - jq and python3 scan programs stay behaviourally identical; both updated.
             - A recovered figure never creates a second invocation and never increments
               COST_N_INVOCATIONS twice. Two recovered records naming one invocation
               resolve to one invocation and one figure.
             - cost_coverage_sentence()'s current text stays a literal prefix. The
               transcribed clause is APPENDED, only when at least one transcribed figure
               is counted, and the sentence stays ONE line. The budget gate inherits it
               through the same shared formatter — that is the point of the shared
               formatter and no second formatting site is added.
             - CL7 is untouched: nothing is imputed, extrapolated, scaled or averaged. A
               transcribed figure is a real measurement someone copied, not a derived one.
             - Any new percentage uses the "N %" spacing (CV4's 0% trap).
             - Zero new dependency; shellcheck -S warning clean; all 379 existing cases
               pass unmodified (CL8, X1).
Output:      Updated cost-ledger-lib.sh + cost-report.sh + new harness cases.
Done when:   A fixture ledger holding a start, an "async_launched" finish, and one
             event:"recovered" line for the same invocation_id reports that invocation as
             priced with its figure in the total, as ONE invocation not two, with coverage
             risen accordingly — and the report states how many of the priced figures, and
             how many of the tokens in the total, were transcribed rather than
             host-observed.
Test set:    6 cases. Rule: one per claim the criteria make about a SINGLE recovered
             figure (counted once, counted priced, labelled, coverage risen), plus the two
             boundaries the criteria name (zero recovered records; two for one
             invocation). The observed-vs-transcribed conflict is S8's case and is
             deliberately not asserted here — siblings do not re-assert each other's cases
             (test-design).
               1. recovered record on an unpriced backgrounded invocation -> priced, its
                  tokens in COST_TOKENS_PRICED                                      [RC5]
               2. same fixture -> COST_N_INVOCATIONS identical to the same ledger with
                  the recovered line removed; no duplicate invocation               [RC1]
               3. same fixture -> the report names that figure as transcribed /
                  model-reported, distinguishable from a host-observed one, and states
                  how much of the total is transcribed                              [RC2]
               4. coverage share (and the wholly-unobserved phase list) differ between
                  the same fixture with and without the recovered line               [RC5]
               5. a ledger with NO recovered record -> output byte-identical to
                  pre-slice, and no word about transcription appears anywhere   [RC6, CL9]
               6. TWO recovered records for one invocation_id -> one invocation, one
                  figure, no double count                                     [RC1 bound]
             S1's CL7 characterisation case stays green, unmodified.
Fails today: event:"recovered" is an unrecognised shape — it lands in COST_N_SKIPPED, the
             invocation stays unpriced, and grepping the report for any statement about a
             transcribed figure returns nothing.
Do NOT:      - Do not touch scripts/record-cost-event.sh or hooks/hooks.json. This group
               adds no field to any host-written record, by design (pinned table).
             - Do not write a recovery record from anywhere. S9 owns the only writer, and
               no transcribed figure may exist in a real ledger before this marker lands.
             - Do not reword, reorder or split cost_coverage_sentence()'s existing text,
               and do not make it multi-line.
             - Do not implement the observed-vs-transcribed disagreement output — S8.
             - Do not change what the budget gate compares, when it fires, or its exit
               codes. G0-D1 is not reopened.
             - Do not modify any existing harness case.
Depends on:  nothing (S1-S6 are merged)
```

### S8 — When an observed and a transcribed figure disagree, print both and state the rule
```
Owner:       loop-build
Context:     scripts/cost-ledger-lib.sh (after S7 the scan entry carries both figures for
             such an invocation; expose the disagreement as scan output in the existing
             COST_* namespace — e.g. a count plus deterministic TSV rows, following
             COST_SLICE_ROWS's shape, never a second parse); scripts/cost-report.sh
             (the Tokens section); spec.md RC3 and its failure-mode row; the pinned
             precedence row above.
Constraints: - Both numbers appear, each attributed to its source, with the difference
               visible. No averaging, no max, no min, no silent last-wins.
             - The precedence rule is STATED IN THE OUTPUT where it applies: the observed
               figure is the one in the total, and the report says so.
             - Printed only when a disagreement actually exists.
             - Conflict rows are ordered deterministically — invocation_id ascending,
               byte order, never hash-iteration order (CV7).
             - Equal figures are not a disagreement and print nothing.
             - shellcheck clean; every case from S7 and before passes unmodified.
Output:      Updated cost-ledger-lib.sh + cost-report.sh + new harness cases.
Done when:   A fixture where one invocation has a finish record with total_tokens 12102
             and a recovered record with 11035 prints both figures, attributes each to its
             source, states which one the total uses — and the printed total is identical
             to the same ledger with the recovered line removed.
Test set:    4 cases. Rule: happy path, its negation, the equality boundary, and the
             arithmetic invariant the criterion implies.
               1. observed 12102 + transcribed 11035 -> both numbers appear, each
                  attributed to its source, the rule stated                         [RC3]
               2. same fixture -> COST_TOKENS_PRICED identical to the same ledger with
                  the recovered line removed: no average, no max, no overwrite       [RC3]
               3. observed 12102 + transcribed 12102 -> no disagreement reported
                  (equality is not disagreement)                              [RC3 bound]
               4. no recovered records at all -> output byte-identical to post-S7  [RC6]
Fails today: after S7 the transcribed figure on an already-priced invocation is carried
             but never printed; grepping one report for both numbers returns only one.
Do NOT:      - Do not change WHICH figure enters the total. The rule is pinned; making it
               visible is this slice's job, changing it is not.
             - Do not touch check-budget-gate.sh, record-cost-event.sh, or hooks/hooks.json.
             - Do not add the writer — S9.
             - Do not print a disagreement for an invocation that has only one figure.
             - Do not modify any existing harness case.
Depends on:  S7
```

### S9 — The transcription entry point: one recovered figure, written deliberately
```
Owner:       loop-build
Context:     scripts/record-cost-event.sh — READ ONLY, as prior art to mirror:
             append_and_evict() (bounded atomic append), the mkdir exactly-once marker,
             num_or_null(), the jq -> python3 -> safe-no-op degradation, the
             LARAVEL_LOOP_COST_LEDGER=0 switch, and the header convention of explaining
             WHY the script is wired the way it is;
             scripts/cost-ledger-lib.sh (to answer "does this invocation_id exist in the
             ledger" through the existing reader, never a third parse of the file);
             spec.md RC1, RC4, RC7 and every recovery row of the failure-mode table;
             the pinned CLI, marker, and unknown-invocation rows above.
Constraints: - Standalone CLI. NOT registered in hooks/hooks.json, never invoked by a
               hook, never reachable from a tool payload. RC7's proof is that
               hooks/hooks.json and record-cost-event.sh are byte-identical after this
               slice.
             - Exits 0 on EVERY path, including its own internal errors, and writes
               nothing at all on any refusal.
             - At most one recovered record per invocation_id, deduped by
               mkdir "$FINISHED_DIR/_recovered/<sanitised id>".
             - Refuses — nothing written, exit 0, one stderr line — on: a token figure
               that is absent, non-numeric or negative; an invocation_id absent from the
               ledger; a missing required argument; no parser available;
               LARAVEL_LOOP_COST_LEDGER=0.
             - The record carries exactly the pinned fields. No status, model, phase,
               duration or slice is copied forward from the finish record and nothing is
               inferred. The slug is the one the ledger already holds for that invocation.
             - Same bounded-append discipline as the ledger writer: one atomic write, the
               line cap honoured.
             - Executable bit set; shellcheck -S warning clean; zero new dependency.
Output:      New scripts/record-recovered-cost.sh + new harness cases.
Done when:   Run against a fixture ledger with an invocation_id it contains and a numeric
             figure, it appends exactly one event:"recovered" line carrying that figure
             and token_source:"transcribed"; run a second time with the same id it appends
             nothing; and every refusal above leaves the ledger byte-identical and exits 0.
Test set:    7 cases. Rule: the happy path, one per failure mode RC4 names, plus RC1's
             exactly-once boundary. Seven is above the healthy dial and is defended rather
             than hidden: they are one-line invocations of one script against one shared
             fixture arrangement, and RC4's own wording — "asserted per case, not in
             aggregate" — forbids collapsing them. Splitting the slice would strand half
             the refusals in a slice with no writer to refuse.
               1. valid id + valid figure -> exactly one recovered line, pinned fields
                  present, token_source "transcribed"                               [RC1]
               2. the same command run twice -> still exactly one line        [RC1 bound]
               3. invocation_id absent from the ledger -> nothing written, exit 0  [RC4]
               4. non-numeric token figure -> nothing written, exit 0              [RC4]
               5. missing/empty required argument -> nothing written, exit 0       [RC4]
               6. LARAVEL_LOOP_COST_LEDGER=0 -> nothing written, exit 0       [RC4, v0.2]
               7. guard: hooks/hooks.json names no recovery script, and
                  record-cost-event.sh is unchanged by this slice                   [RC7]
Fails today: the script does not exist; case 1's grep for a recovered event in the fixture
             ledger finds nothing.
Do NOT:      - Do not edit scripts/record-cost-event.sh. Not to extract a shared helper,
               not to refactor: RC7's proof is that this file did not move.
             - Do not register anything in hooks/hooks.json.
             - Do not read, parse, or import the session transcript, ~/.claude/projects,
               or anything outside the project's own .claude/. The figure arrives as an
               argument somebody typed; a script that goes looking for it is a different
               unit and a different consent conversation (see FLAGS at this gate).
             - Do not read Laravel Guild's .claude/agents-board.jsonl (CO2).
             - Do not accept a slug, slice, agent, or recency selector, or any other fuzzy
               match. Exactly one invocation_id, or nothing.
             - Do not add a retry, a queue, a pending state, or any record of a refusal.
             - Do not modify any existing harness case.
Depends on:  S8 — not for files, but because the marker (S7) and the disagreement output
             (S8) must both exist before anything can write a transcribed figure. This is
             the ordering this gate was explicitly briefed to enforce.
```

### S10 — Document what a transcribed figure is, and record this gate's decision
```
Owner:       loop-build
Context:     README.md — the "Cost ledger" and "Cost reporting and the budget gate"
             sections, where S5 already documents the backgrounding gap and the coverage
             floor; docs/loop/decisions.md — S6's OQ2 spike entry (a NEW entry goes after
             it, nothing inside it is edited); tests/guardrails.test.sh's docs section
             (~2140-2230, README claims asserted by grep — the pattern to extend);
             spec.md X5, RC2, RC6, CL3.
Constraints: - README states plainly: a recovered figure is MODEL-TRANSCRIBED, not
               host-observed; how one is written (the CLI and its two arguments); that
               nothing writes one automatically; and that skipping it changes nothing
               (RC6).
             - README does not claim the gap is closed. S3's residue wording still holds:
               recovery narrows the gap for invocations somebody transcribed, and for no
               others.
             - decisions.md gains ONE new dated entry recording this second G1's decision
               and what it forecloses — hook-based recovery (closed by S6), transcript
               scraping, and any fuzzy selector.
             - No digit adjacent to LARAVEL_LOOP_COST_MIN_COVERAGE anywhere: S4's guard
               stays green.
Output:      Updated README.md, docs/loop/decisions.md, new harness cases in the docs
             section.
Done when:   The docs-section cases assert README names the transcribed nature of a
             recovered figure, names the CLI, and says skipping it changes nothing; and
             decisions.md carries the new dated entry while S6's spike entry and the
             4%-coverage rejection stand untouched.
Test set:    4 cases. Rule: one per documentation claim, in the existing docs-section grep
             style — a documentation slice's set is its claims, no more.
               1. README states a recovered figure is model-transcribed, not
                  host-observed                                                [X5, RC2]
               2. README names scripts/record-recovered-cost.sh and its two arguments [X5]
               3. README does not claim the background gap is closed — S3's residue
                  wording survives                                                  [CL3]
               4. decisions.md carries the second-G1 entry AND still carries S6's spike
                  entry and the 4%-coverage rejection verbatim                       [X6]
Fails today: README says nothing about recovery; decisions.md has no second-G1 entry. All
             four greps fail.
Do NOT:      - Do not edit S6's spike entry, the 4%-coverage rejection, or any other
               existing decisions.md entry. Append one entry, nothing else.
             - Do not edit spec.md or this file.
             - Do not touch any script.
             - Do not bump the version, write a CHANGELOG release entry, or tag — /ship
               owns G3.
             - Do not document S11's automatic wiring unless S11 is approved and landed.
             - Do not modify any existing harness case.
Depends on:  S9
```

### S11 — (OPTIONAL, the human's call at this gate) Instruct the orchestrator to transcribe
```
Owner:       loop-build
Context:     commands/loop.md — the section describing background build lanes; spec.md
             DC5 and RC6; S10's README text as the wording to stay consistent with.
             NOTE: this slice serves NO RC criterion. It exists only so DC5 is reachable
             without a human typing the command by hand after every lane. Approving it
             makes model-transcription routine rather than deliberate; dropping it leaves
             every RC criterion satisfied and DC5 reachable manually. That is the whole
             decision, and it belongs to the human, not to a builder.
Constraints: - Instruction only. After a background lane's completion notification
               arrives, the orchestrator runs the CLI once with the <tool-use-id> and
               <subagent_tokens> from that same block.
             - Best-effort and explicitly so: skipping it, forgetting it, or failing it
               changes nothing (RC6). No retry, no record of which lanes were transcribed,
               no check that recovery happened.
             - Nothing blocks, delays, or reorders a lane. No lane waits on a
               transcription (RC7's spirit, at the orchestration layer).
             - No change to /loop's concurrency, lane count, or launch mode — OQ4 stays
               out of bounds.
             - The instruction tells the orchestrator plainly that the figure is
               model-transcribed and will be recorded as such.
Output:      Updated commands/loop.md + harness cases.
Done when:   commands/loop.md carries the instruction naming the CLI and the best-effort
             wording, and no wording anywhere in it makes a missing transcription an
             error.
Test set:    2 cases. Rule: one claim, one negation. THE HARNESS CAN PROVE THE WORDS
             EXIST AND CANNOT PROVE AN AGENT FOLLOWS THEM — stated rather than disguised,
             exactly as S6's envelope stated its own limit. The real proof is DC5, a field
             condition on one real run, and it is not a G2 criterion.
               1. commands/loop.md names scripts/record-recovered-cost.sh and the
                  best-effort wording                                       [DC5 enabler]
               2. commands/loop.md instructs no lane to wait for, retry, or verify a
                  transcription                                                 [RC6/RC7]
Fails today: commands/loop.md says nothing about recovery; both greps fail.
Do NOT:      - Do not change /loop's concurrency, lane count, or launch mode (OQ4).
             - Do not add any check, retry, or reconciliation that would surface a missing
               transcription as an error or a warning (RC6).
             - Do not touch skills/loop-protocol/SKILL.md, any agent file, or any script.
             - Do not make the transcription a gate, a precondition, or a blocker for
               closing a slice.
             - Do not modify any existing harness case.
Depends on:  S10
```

## Criterion assignment — nothing dropped

| Criteria | Where |
|---|---|
| RC1 | Split by side, deliberately: the **count** property (one invocation, never a duplicate, however many recovered records) is S7 cases 2 and 6; the **write** property (at most one record ever appended) is S9 cases 1 and 2. Both halves are needed — a reader-side guarantee protects a hand-edited ledger, a writer-side one protects the ledger from a notification that fires twice. |
| RC2 | S7 (case 3), reinforced by S10 case 1 in README. The pinned record shape is what makes it structural rather than cosmetic. |
| RC3 | S8, all four cases. |
| RC4 | S9, cases 3–6 — one per failure mode, per the criterion's own "asserted per case, not in aggregate". |
| RC5 | S7 (cases 1 and 4). CL5's floor behaviour changes through the same coverage share, with no second implementation. |
| RC6 | Cross-cutting, asserted per slice: S7 case 5, S8 case 4, S9 cases 3–6, S11 case 2. Every slice owes a "no recovery happened" case that is byte-identical to before it. |
| RC7 | S9 case 7, as a guard: `hooks/hooks.json` and `record-cost-event.sh` byte-identical after the group. Every RC slice's `Do NOT` names both files. |
| CL9's remaining half | S7 case 5 — the pre-existing ledger, holding no record of the shape this group introduces, is read without error and nothing in it is reclassified. |
| CL7, CL8 | Cross-cutting, unchanged. S1's characterisation case stays green through the whole group; no slice modifies an existing harness case. |
| X1–X4 | Per-slice gates: green `tests/guardrails.test.sh` with a case count above the previous slice's (**379** at the start of this group), clean `shellcheck -S warning`, zero new dependency, executable bit set, every script in `hooks/hooks.json` present and executable. |
| X5 | S10. X6 was landed by S5 and is not reopened; S10 appends, it does not edit. |
| DC5 | Field condition, not a G2 criterion — one real `/loop` run where a transcribed figure matches the number the human saw in that agent's completion notification. S11 is what makes it reachable without manual typing. `cost-measurement-v0.2`'s DC1, `cost-reporting-v0.3`'s DC2/DC3, and this unit's DC4 all remain open and separate; do not let any of them be reported as another. |

## Riskiest slice: **S11**

**Not S9**, and the distinction is the same one S6 forced last time. S9 has the most moving parts —
a new writer, exactly-once, five refusal paths — but every one of them is fixture-testable, its
blast radius is one new file, and its `Do NOT` list is enforceable by a guard case. Mechanical
risk that a test can catch is not the risk to nominate.

**S11 is the riskiest because it is the only slice that changes what the ledger *is*.** S7–S10
make a transcribed figure legible, countable, and writable *on purpose*: somebody decides, per
invocation, to copy a number in, and the record says forever that they did. S11 turns that into
the default path of every `/loop` run — after which most figures in a file whose entire value is
that its numbers were host-observed will be numbers a model read off its own context and retyped.
Nothing in the RC criteria asks for that. It is licensed only by DC5's convenience.

Two properties make it worse than its small diff suggests. First, **its correctness is not
harness-provable**: a grep shows the instruction exists, never that an agent followed it, never
that the id and the figure it copied belong to each other. A transcription that pairs lane A's
`tool-use-id` with lane B's token figure produces a ledger line that is well-formed, in-bounds,
counted, labelled `transcribed` — and wrong, with no test anywhere that can fail. Second, it is
the one slice whose failure mode is **silent and cumulative**: every subsequent run adds more of
them, and `/cost`'s coverage share *rises* as its trustworthiness falls, which is precisely the
inversion this whole unit exists to remove.

The recommendation is therefore to **approve S7–S10 and hold S11 as its own decision** once at
least one transcription has been done by hand and checked by eye (which is exactly what DC5 asks
for anyway). Holding it costs one manual command per lane. Approving it early costs the ability to
tell, later, which numbers anyone actually checked.

Runner-up: **S7**, for the S2 reason, one more time — it is the slice that touches
`cost_coverage_sentence()`, the single formatter consumed by the report, the budget gate's notice,
its breach message, and the `--phase` check whose one line is pasted into a ≤10-line return. A
builder who rewords that sentence instead of appending to it satisfies RC2 perfectly and fails CL8
in the budget-gate section of the harness, nowhere near the diff. The pinned row exists to defuse
exactly that, and it is the row to read twice.
