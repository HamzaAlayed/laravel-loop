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
