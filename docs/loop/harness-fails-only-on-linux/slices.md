# Slices — harness-fails-only-on-linux

Cuts `spec.md` (G0 approved, four decisions taken: **OQ1 = a read-only spike comes first, per case**;
**OQ4 = the spike also establishes the floor, and fix scope is decided after it returns**;
**OQ2 + OQ3 = the portability contract becomes two-directional, enforced by the guarding checks
covering both platforms — approved but CONTINGENT on the spike showing a hosted runner can actually
reproduce bash 3.2**) into **four read-only spike slices**, plus a **second G1** for the fix group
that cannot honestly be cut yet.

**4 slices · all 4 genuinely parallel at t0 · critical path depth 1 (S1 ∥ S2 ∥ S3 ∥ S4) → SECOND G1**

No slice in this pass writes code, a test, a workflow, or a file mode. Every one of them returns
evidence, and the whole point of the pass is that the fix is designed *after* that evidence exists.

---

## The seam — and why this pass does not have one

The usual first question ("what is the smallest change that delivers observable value?") has no
honest answer here yet, and saying so is more useful than inventing one. Both known failures are
**latent behaviour whose cause is `unknown`** (`intent.md`, deliberately), and the G0 decision buys
evidence before any fix. A slice that changed behaviour in this pass would be a guess wearing an
envelope.

So the value this pass delivers is a different kind, and it is real: **after it, the project knows
how many cases actually fail on the guarding machine, why each of the two known ones does, and
whether the two-directional contract the human approved is even buildable.** Three of those four
things are recorded nowhere today.

The fix group's seam — probably whichever case's resolution needs no other change first — is named
at the second G1, off S1–S4's answers. Naming it now would be picking a cause, which `spec.md`'s last
non-goal explicitly forbids a builder from doing.

Deliberately **not** in this pass:

- **Fix slices for the two known cases.** OQ4's decision is that scope is decided after the floor is
  established. An envelope *is* a design commitment — it names files, outputs and tests — so writing
  one for case A or case B now pre-empts A3's per-case human decision and makes the spike
  ceremonial. This is exactly the precedent set by `cost-ledger-blind-to-background-agents`, where
  the RC group was left uncut until S6's spike returned. See *The second G1* below.
- **The two-platform workflow change.** Its feasibility is S4's question. Cutting a slice for it now
  would commit the repository to a matrix whose premise — that a hosted runner can reproduce the
  maintainer's bash 3.2 — is unestablished, and `spec.md` warns that an option which only *appears*
  to give the older shell coverage is worse than none.
- **The A5 statement of claimed platforms.** It cannot be written before S4 says which platforms can
  have evidence behind them; A5 fails a platform claimed with nothing producing evidence for it.
- **Anything in `docs/loop/checks.md`.** A6 applies only if this unit changes what runs where. This
  pass changes nothing that runs anywhere.

---

## Order and concurrency

```
t0  ├── S1  Establish the floor from the completed run's own log        (read-only)
    ├── S2  Case A: which of OQ1's three, with evidence                 (read-only)
    ├── S3  Case B: which of OQ1's three, with evidence                 (read-only)
    └── S4  Can any hosted runner reproduce bash 3.2? (OQ2/OQ3 premise) (read-only)
             │
             └────────────→ SECOND G1: the fix group, scoped on S1-S4's answers
```

- **Genuinely parallel: all four.** Four builders, four worktrees, four distinct output files, zero
  shared files. No lane touches `tests/guardrails.test.sh`, `README.md`, `scripts/`, or
  `.github/workflows/`, which is what makes this the rare pass where the parallelism is real rather
  than asserted.
- **S1 is not a dependency of S2 or S3, and that is on purpose.** Both case slices already have
  their verbatim expected-versus-got strings from `intent.md`; neither needs the floor to read its
  own case. Sequencing them behind S1 would buy nothing and cost a merge.
- **S2 and S3 are separate slices because the spec says the two cases are unrelated.** One lane
  holding both questions is how two independent findings become one narrative with a shared cause —
  the thing `spec.md`'s failure-mode table and A3 both forbid. Structural separation is cheaper than
  a review that has to catch it.
- **S4 is separate because it is a different question about a different thing.** S2/S3 read two test
  cases; S4 reads what platforms this repository can obtain evidence on. Merging it into either case
  lane would put an "and also" in that lane's title.

**Why four lanes and not two.** A single "go read everything" lane would have three *and also*s in
its title and would fail the one-commit test. The cost of four is four envelopes and four small
merges into one directory; the benefit is that a lane returning `unknown` (a legitimate outcome for
any of the four) does not take the other three answers down with it. If the human would rather run
two lanes, the merge to make is **S1 + S4** (both read records rather than code) and **S2 + S3** is
the pairing to refuse, for the shared-narrative reason above.

---

## Pinned contracts, so no two lanes derive the same thing twice

Decided here, at G1, because discovering any of them at build time costs a rewrite. A builder that
believes one is wrong returns `needs-decision` rather than changing it.

| Contract | Value | Why it is pinned |
|---|---|---|
| Spike output paths | One file per lane: `docs/loop/harness-fails-only-on-linux/spike-floor.md` (S1), `spike-case-a.md` (S2), `spike-case-b.md` (S3), `spike-platforms.md` (S4) | Four lanes appending to one `spike.md` conflict at the same insertion point, every time. Distinct files make the parallelism structural. Consolidation, if wanted, is the second G1's call. |
| Every lane's diff | Markdown only, and exactly one file: `git diff --name-only main` returns that lane's own path and nothing else | This is what makes A7 and A8 trivially true for the whole pass, and it is the cheapest possible check that a read-only slice stayed read-only. |
| The suite's case count | **Unchanged by this pass.** No lane adds, removes, or edits a harness case, so no lane touches `README.md`'s `## Development` literal (`421 cases`) | The harness's own last case asserts `PASS + FAIL + 1` equals that literal, so any lane that "helpfully" added a case would turn the suite red on a case its diff never touched, in a lane whose entire value is not changing behaviour. |
| The floor's status | A **lower bound recorded against a run id**, never a prediction of what the resolved tree will do | `spec.md` A2 and its own "two is a lower bound, not a count". The proof-grade count for the resolved tree can only come from A1's post-merge run. |
| `unknown` as an answer | A complete, successful outcome for any of the four lanes, recorded with what was tried | `spec.md`'s failure-mode row: "the cause of a case's platform-dependence cannot be established → recorded as unknown, never inferred from the other case's cause". A lane that guesses to avoid returning `unknown` is the failure this pass exists to prevent. |
| Investigation vs proof | A container, VM, or otherwise simulated Linux may be used to **investigate** and must be labelled investigation-grade in the finding. It is never cited as evidence for A1, A2's resolved-tree count, or A5 | `spec.md`, *Limits on evidence*, and the standing convention that a green harness never proves a hook is live. |
| What "no fix" means, exactly | A lane may name **which artifact** a resolution would live in (the case, or the code the case exercises) — that is OQ1's own wording. It may not write a patch, a diff, a prototype, a branch, or a sentence beginning "the fix would be" | The line between evidence and design, drawn where the spec draws it. Crossing it re-creates the diagnosis-delivered-as-a-spec failure one phase later. |

---

## Slices

### S1 — Establish the floor from the completed run's own record, and record it as a lower bound
```
Owner:       loop-build
Context:     docs/loop/harness-fails-only-on-linux/intent.md (the two FAIL lines quoted
             verbatim, and its explicit refusal to claim they are the only ones); the run
             itself -- id 32026220384, commit a528f6a, workflow .github/workflows/ci.yml,
             job `guardrails`, step `guardrail tests`, runner ubuntu-latest; the earlier
             run 32014743116 whose same step concluded `skipped`;
             tests/guardrails.test.sh's final `docs (case count)` case, which establishes
             that PASS + FAIL + 1 is the suite's grand total and is therefore what the
             runner's `total: 419 passed, 2 failed` must reconcile against;
             spec.md A2, A7, and the *Limits on evidence* section.
Constraints: - READ-ONLY against GitHub: `gh run view --log`, `gh api` on the runs/jobs
               endpoints. No push, no re-run, no cancel, no workflow dispatch, no branch.
             - Every failing case is quoted VERBATIM with its expected-versus-got string,
               in exactly the shape intent.md used for the first two, and each is traced to
               a line number in tests/guardrails.test.sh as it stood at a528f6a.
             - Reconcile the run's reported totals against the suite's own case count at
               that commit, and state plainly whether every case executed or whether any
               did not. This is the difference between a floor and a guess.
             - The number is recorded as a LOWER BOUND against that run id, with the reason
               (resolving one case may expose another that was behind it). No count is
               inferred for the resolved tree.
             - If the log is not retrievable -- retention, auth, or no network -- that is
               the finding: record it, leave the floor at intent.md's two as unconfirmed,
               and do NOT substitute a local or containerised run for it.
Output:      docs/loop/harness-fails-only-on-linux/spike-floor.md
Done when:   That file names the run id, the commit, and the step, and states: every case
             that failed on it with expected-versus-got verbatim and its line number; the
             run's reported totals; whether those totals reconcile with the suite's case
             count at that commit (so, whether any case failed to execute); and that the
             figure is a lower bound for the resolved tree, with the reason.
Test set:    THE PROOF IS A READ OF A REAL RUN'S OWN RECORD, NOT A HARNESS CASE, and that
             is stated rather than disguised -- no fixture in this suite can observe what
             happened on the runner. Two falsifiable checks the finding must satisfy:
               1. the count of enumerated FAIL lines equals the `M` in that run's own
                  `total: N passed, M failed` line                                    [A2]
               2. N + M equals the suite's case count at a528f6a -- and if it does not,
                  the shortfall is named as cases that did not execute                 [A2]
             Fails today: nothing in this repository enumerates the runner's failures from
             the log itself. intent.md quotes two FAIL lines as read at the time and states
             outright that it is not established they are the only ones.
Do NOT:      - Do not push, re-run, cancel, or dispatch anything. Nothing about this slice
               touches the guarding checks' state.
             - Do not edit .github/workflows/ci.yml, scripts/, tests/, README.md,
               docs/loop/checks.md, spec.md, or this file.
             - Do not run the suite in a container and report those results as the floor.
               A simulated Linux is not evidence (spec.md, Limits on evidence).
             - Do not predict, extrapolate, or estimate a post-fix count.
             - Do not diagnose either case's cause. That is S2's and S3's job, per case,
               and pre-empting it here makes both ceremonial.
Depends on:  nothing
```

### S2 — Case A only: establish which of OQ1's three answers the evidence supports
```
Owner:       loop-build
Context:     tests/guardrails.test.sh:407-435 -- section (b), the case at :429
             `eviction under concurrency: settles at or under cap` (expected exit `yes`,
             got `no`) and the two sibling cases in the same section that PASSED on the
             runner; the code that case exercises, reachable from its own invocation path;
             intent.md's Case A record, including commit 5799d86 as the commit that
             introduced the case; spec.md OQ1's three candidate answers and their stated
             costs, the failure-mode row for an unestablishable cause, and the *Limits on
             evidence* section.
Constraints: - THE ONLY DELIVERABLE IS THE ANSWER FOR CASE A: which of OQ1's three, the
               mechanism named concretely enough for a second person to re-observe it, and
               what choosing answer 1 versus answer 2 would cost. Not a fix, not a patch,
               not a prototype, not a branch.
             - Read case A alone. Do not read, discuss, or reason about case B, and do not
               state or imply a shared cause. spec.md: the two are unrelated as far as
               anything observed shows.
             - State plainly whether the behaviour the case guards is genuinely
               platform-dependent, because that is the whole substance of answer 2 and the
               whole cost of answer 1 (changing the test discards the only warning anyone
               gets).
             - Every hypothesis is falsifiable and carries the observation that would
               refute it. A mechanism nobody could disconfirm is not a finding.
             - A simulated Linux may be used to investigate and MUST be labelled
               investigation-grade in the finding. It is never cited as proof.
             - `unknown` is a complete answer, recorded with what was tried and what would
               settle it.
Output:      docs/loop/harness-fails-only-on-linux/spike-case-a.md
Done when:   That file states, for case A alone: which of OQ1's 1 / 2 / 3 the evidence
             supports; the mechanism, with the observation that establishes it or the
             reason it cannot be established; whether the guarded behaviour is genuinely
             platform-dependent; and the cost of each candidate resolution, naming only
             WHICH artifact it would live in.
Test set:    THIS SLICE'S PROOF IS AN EXPERIMENT, NOT A HARNESS CASE. The case passes on
             the maintainer's bash 3.2 host and fails on the runner, so no fixture case in
             this suite can distinguish "the case is wrong" from "the thing it exercises is
             wrong" -- a harness case here would prove nothing about the question asked.
             The named experiment, in this order:
               1. read section (b)'s own commands and the code path they exercise, and name
                  every mechanism in it that could differ between two shells or two
                  coreutils                                            [OQ1 answers 1 vs 2]
               2. observe the differing behaviour directly under a Linux bash with the same
                  environment, labelled investigation-grade                    [mechanism]
               3. for the mechanism named, state the observation that would refute it
                                                                              [falsifiable]
             Fails now: no cause for case A is recorded anywhere in this repository;
             intent.md records `unknown` deliberately, and no hypothesis exists to prefer.
             Passes after: exactly one of OQ1's answers is recorded for case A with a
             reproducible observation, or `unknown` with what was tried.
Do NOT:      - Do not edit any test, script, workflow, file mode, or README. This lane's
               diff is one markdown file.
             - Do not propose, write, or prototype a fix, and do not make the case pass.
             - Do not read case B or assert anything about its cause.
             - Do not touch scripts/record-cost-event.sh, the cost ledger's format, its
               bound, its eviction order, /cost, or the budget gate. spec.md's non-goals
               put all of them out of bounds beyond what a recorded decision requires --
               and no decision exists yet.
             - Do not introduce a container runtime as a requirement for anyone running
               the suite. A throwaway one used to investigate is fine and is not committed.
             - Do not touch docs/loop/checks.md, spec.md, or this file.
Depends on:  nothing
```

### S3 — Case B only: establish which of OQ1's three answers the evidence supports, and what happens to the safety property either way
```
Owner:       loop-build
Context:     tests/guardrails.test.sh:2508-2522 -- the case at :2520 `ship: shellcheck
             absent from PATH reads not-run, verdict hold` (expected `yes yes 1`, got
             `no no 0`), its own inputs (the fixture builder, the pruned PATH it runs
             under, and the gate-line reader it asserts through), and the two neighbouring
             ship cases that PASSED on the runner, one of which asserts the same
             not-run-by-name / verdict-hold shape for a different gate;
             scripts/ship-check.sh -- the gate it exercises and that gate's not-run
             reporting path; intent.md's Case B record, including commit 1813cb0 and the
             unit at docs/loop/ship-observe-automation/, and its note that the runner
             installs shellcheck via apt-get where the maintainer's host does not;
             spec.md OQ1 case B including its note for the human, and A7.
Constraints: - THE ONLY DELIVERABLE IS THE ANSWER FOR CASE B: which of OQ1's three, the
               mechanism, and the cost either way. Not a fix.
             - Read case B alone. Do not read, discuss, or reason about case A, and do not
               state or imply a shared cause.
             - THE EXTRA THING THIS LANE OWES, AND IT IS THE REASON THE SLICE EXISTS
               SEPARATELY: the case's expectation encodes a safety property this project
               states deliberately -- a gate that cannot be run reads `not-run` and the
               verdict holds, never a quiet go. So the finding must state, separately from
               the answer, WHETHER THAT PROPERTY ITSELF HOLDS ON THE RUNNER. "The case
               asserts the property wrongly" and "the property does not hold there" are
               different findings with opposite consequences, and A3's human decision turns
               on which one it is.
             - Every hypothesis is falsifiable and carries the observation that would
               refute it.
             - A simulated Linux may be used to investigate and MUST be labelled
               investigation-grade. Never cited as proof.
             - `unknown` is a complete answer, recorded with what was tried.
Output:      docs/loop/harness-fails-only-on-linux/spike-case-b.md
Done when:   That file states, for case B alone: which of OQ1's 1 / 2 / 3 the evidence
             supports, with the mechanism and the observation behind it (or why it cannot
             be established); AND, as its own statement, whether a release check run on the
             runner could report a go while a gate did not run -- with the observation
             behind that answer too; AND the cost of each candidate resolution, naming only
             which artifact it would live in.
Test set:    THIS SLICE'S PROOF IS AN EXPERIMENT, NOT A HARNESS CASE, for the same reason
             as S2: the case is green on bash 3.2 and red on the runner, so no fixture in
             this suite can tell the two answers apart. The named experiment:
               1. read the case's own inputs and the gate's not-run path, and name every
                  mechanism that could make the same assertion read differently on the two
                  platforms                                             [OQ1 answers 1 vs 2]
               2. observe, under a Linux bash, what the gate actually reports and what
                  verdict follows -- investigation-grade                        [mechanism]
               3. separately, establish the safety property's own status there: does the
                  verdict hold when that gate cannot run?               [the A7-adjacent risk]
               4. for each mechanism named, state the observation that would refute it
                                                                              [falsifiable]
             Four steps, one question, one artifact -- step 3 is not a second slice's worth
             because it is the same observation read for a different claim, and separating
             it would put the answer and its consequence in two files nobody reads together.
             Fails now: no cause for case B is recorded anywhere, and nothing anywhere
             states whether the safety property holds on the runner.
             Passes after: exactly one of OQ1's answers for case B, plus the property's own
             status, both with reproducible observations -- or `unknown`, with what was tried.
Do NOT:      - Do not edit any test, script, workflow, file mode, or README. One markdown
               file.
             - Do not propose, write, or prototype a fix, and do not make the case pass.
             - Do not edit scripts/ship-check.sh, add a gate, remove a gate, or change what
               any gate reports. The three-gate set is settled by a prior decision and is
               not reopened (spec.md, Non-goals).
             - Do not change the shellcheck policy -- severity, file scope, or whether
               tests/*.sh is covered. Out of bounds by non-goal.
             - Do not read case A or assert anything about its cause.
             - Do not touch docs/loop/checks.md, spec.md, or this file.
Depends on:  nothing
```

### S4 — Establish whether the approved two-directional contract is buildable at all
```
Owner:       loop-build
Context:     spec.md OQ2 (its three answers, including answer 2's stated cost -- a claim
             with nothing producing evidence for it FAILS A5) and OQ3 (its three answers,
             including answer 2's explicit "unestablished, and it must be established
             before this option is costed rather than assumed ... whether any hosted runner
             can actually reproduce the maintainer's shell version is NOT KNOWN HERE");
             the G0 decision approving OQ2+OQ3 CONTINGENT on this answer; spec.md A5 and
             A1's evidence rule; .github/workflows/ci.yml (read-only, one job, three steps,
             ubuntu-latest); docs/loop/checks.md (read-only -- the enumeration a change here
             would later have to match, A6); intent.md's host record -- macOS 26.6.1 on
             arm64, `GNU bash, version 3.2.57(1)-release`.
Constraints: - READ-ONLY, and text is the whole deliverable. No workflow file is written,
               added, edited, commented out, or branched -- not even as a draft.
             - The answer is one of: a named hosted image/label that runs the suite on a
               bash matching the maintainer's stock 3.2, WITH a citable source for that
               bash version; or "not feasible", with what rules it out; or "not
               established", with what was tried.
             - "Feasible" may NOT rest on expectation, recollection, or this document.
               Name the source. And state, in the finding itself, that a citable image
               manifest is not proof: only a real run on that platform makes the claim
               evidence (A1, A5).
             - Report exactly what matches and what does not -- bash version, OS version,
               architecture -- because an option that only APPEARS to give the older shell
               coverage would be worse than none, in spec.md's own words.
             - Also record, for each of OQ3's three answers, what would produce evidence
               for the second direction under it (A5's "named way evidence is produced"),
               WITHOUT choosing between them. The choice is the human's at the second gate.
             - "Not established" returns OQ2/OQ3 to the human at the second G1. It is a
               complete outcome, not a failed slice, and it must NOT be softened into
               "convention will cover it" -- that is OQ2 answer 2, which A5 fails.
Output:      docs/loop/harness-fails-only-on-linux/spike-platforms.md
Done when:   That file states whether a hosted runner available to this repository can run
             the suite on a bash matching the maintainer's stock 3.2 -- naming the image or
             label and citing the source for its bash version, or recording "not feasible"
             or "not established" with what was tried; states precisely which of bash
             version / OS version / architecture match and which do not; states that only a
             real run on that platform is proof; and lists, per OQ3 answer, what would
             produce evidence for the second direction under it, choosing none.
Test set:    THE PROOF IS A CITATION, NOT A HARNESS CASE, and the citation's own limit is
             part of the finding. Three falsifiable checks:
               1. every platform named carries a source for its bash version that a second
                  person can open                                                     [A5]
               2. no platform is described as covered, verified, or proven -- only as
                  claimed, with the real run named as what would prove it          [A1, A5]
               3. each of OQ3's three answers has an evidence-producer named against it,
                  and none is recommended                                             [A5]
             Fails now: spec.md OQ3 records the question as not known here, and nothing in
             this repository names a platform the suite is claimed to hold on or anything
             that produces evidence for such a claim.
Do NOT:      - Do not create, edit, or draft .github/workflows/ci.yml or any other
               workflow, matrix, or job -- not in a comment, not in a fence, not on a
               branch.
             - Do not push a probe branch or dispatch a workflow run. Nothing about this
               slice touches the guarding checks' state.
             - Do not choose an OQ2 or OQ3 answer, and do not downgrade the approved
               decision to "enforced by convention" if feasibility comes back negative.
               Hand it back to the human.
             - Do not propose a compatibility shim, a vendored coreutils, a wrapper, or
               raising the minimum shell version. All four are non-goals.
             - Do not add caching, a linter, a coverage step, a scheduled run, an artifact
               upload, or a job restructure -- non-goal, and none of it is this question.
             - Do not edit docs/loop/checks.md, scripts/, tests/, README.md, spec.md, or
               this file.
Depends on:  nothing
```

---

## The second G1 — the fix group, left uncut on purpose

**Not cut here.** The G0 decision on OQ4 is that fix scope is decided *after* the spike returns, and
A3 requires a recorded human decision **per case** before any change is made. A slice envelope names
files, outputs and tests — it *is* a design commitment — so writing one for case A or case B now
would commit to a resolution the human has not chosen, against a cause nobody has established. That
is the precedent `cost-ledger-blind-to-background-agents` set when it left the RC group uncut behind
S6's spike, and it applies here without modification.

Three separate things block the cut, and each is a different lane's answer:

1. **How many cases** need fixing — S1. Two is a lower bound; the fix group's size is unknown until
   the floor is read off a run in which the suite completed.
2. **What each fix is** — S2 and S3, *plus* a human decision on each (A3). "The case is wrong" and
   "the code is wrong" produce entirely different slices in entirely different files.
3. **Whether the two-directional contract can be built** — S4. If it cannot, OQ2/OQ3 return to the
   human rather than quietly becoming a convention, and the A5 slice's shape changes completely.

What is already known about the shape of that second cut, so the human can see what they are
deferring rather than a blank:

- **One slice per case, always.** Even if both answers turn out identical, A3 fails "one decision
  applied to both cases as a group", and the two causes are unrelated as far as anything observed
  shows.
- **A7's baselines are pinned now**, so any fix slice can be checked against them without
  re-deriving: the maintainer's host reports `421 passed, 0 failed`; the runner's single completed
  run reported `419 passed, 2 failed`; `README.md`'s `## Development` section carries the literal
  `421 cases`, and the harness's own **last** case asserts `PASS + FAIL + 1` equals it. So any fix
  slice that changes the case count bumps that literal **in the same commit**, and new cases are
  appended **before** the final `docs (case count)` case, which stays last in the file. Two fix
  lanes both adding cases conflict by construction — expect the fix group to be largely sequential
  and do not promise parallelism it cannot have.
- **A5 and the contract statement are their own slice**, contingent on S4, and it is the slice that
  must not ship a claimed platform with nothing behind it.
- **`docs/loop/checks.md` is touched only if what runs where actually changes** (A6), and by the
  slice that changes it, in the same commit — its own rule is that an enumeration which drifts is
  worse than none.
- **Any fix slice that reaches for `continue-on-error`, a known-failures list, de-blocking the step,
  or skipping a case on a platform returns `needs-decision`.** That is out of bounds by non-goal and
  by A7, and it stays out of bounds even when it is the fastest route to green.
- **A1 is not a builder's slice at all.** It needs a real run on a real pushed commit, so it is the
  human's post-merge action; see the traceability table.

---

## Cross-unit collisions

`docs/loop/recovered-figure-drops-slice-and-model/` holds an `intent.md` and nothing else — captured,
not specced, not cut. When it is cut it will touch `scripts/cost-ledger-lib.sh`,
`scripts/cost-report.sh`, `tests/guardrails.test.sh` and `README.md`'s case-count literal.

- **This pass: zero collision.** No spike lane touches any of those files.
- **The second G1: name it again.** If case A's recorded decision lands in the ledger writer, the two
  units share `scripts/record-cost-event.sh`'s neighbourhood and both want the harness plus the
  README literal. Land one unit's harness-touching slices before starting the other's.

---

## Criterion traceability — assigned, human-owned, or explicitly not yet assignable

| Criterion | Where it stands after this pass |
|---|---|
| **A1** — real run, real pushed commit, step `success` | **The human's, post-merge.** Not assignable to any builder in any pass: a simulated Linux is not evidence, and a builder cannot push. The fix group makes it *reachable*; only the human's push makes it *true*. |
| **A2** — the floor established, not assumed | **Split, and both halves are named.** The floor *as observed on the completed run* is **S1**. The floor *on the resolved tree* can only be read off A1's own run, so it is the human's, after the fix group merges. Neither half is the other, and S1 says so in its own output. |
| **A3** — a per-case recorded human decision, and a change matching it | **Evidence: S2 (case A), S3 (case B). Decision: the human's, at the second G1. Change: the uncut fix group.** All three parts are needed and none of them is this pass's fix slice, because there is no fix slice this pass. |
| **A4** — no case silently absent on either platform | **Not yet assignable.** Its shape depends on S4 (is there a second platform at all?) and on whether any recorded decision changes what runs where. Cutting it now would presume the answer. |
| **A5** — states the claimed platforms, each with a named evidence producer | **Not yet assignable, and deliberately so.** S4 establishes what *can* have evidence behind it; the human chooses at the second G1; the statement is its own slice after that. A5 is the criterion OQ2 answer 2 fails, which is exactly why it cannot be written before S4 returns. |
| **A6** — `docs/loop/checks.md` matches both check sets | **Not yet assignable.** Conditional on this unit changing what runs where, which no slice in this pass does. Owned by whichever fix slice changes it, in the same commit. |
| **A7** — nothing made green by removing evidence | **Cross-cutting, and structurally satisfied this pass:** every lane's diff is one markdown file, so no case can be deleted, skipped, or weakened by it. The baselines it will be checked against are pinned above; S1 is what turns the runner-side baseline from a quotation into a record. |
| **A8** — everything already guaranteed still holds | **Per-slice gate.** Each lane returns `bash tests/guardrails.test.sh` green and `shellcheck -S warning scripts/*.sh` clean as evidence it changed nothing, plus `git diff --name-only main` showing exactly its own markdown file. |
| **A9** — any configurable ships unset, asserted by a test | **Not yet assignable, and may never be.** No spike slice introduces a configurable. If a recorded decision produces one, A9 belongs to that slice; if none does, A9 is vacuously satisfied and the second G1 says so rather than leaving it looking unmet. |
| **OQ1** (per case) | S2, S3 — evidence only. The answer chosen is the human's (A3). |
| **OQ4** (how much of the floor) | S1 supplies the number the decision needs; the scope decision is the second G1's. |
| **OQ2 + OQ3** (the contingent contract) | S4 establishes the premise. If it fails, the decision returns to the human — not downgraded, not silently held. |

Nothing is dropped, and nothing is claimed as assigned that is not.

---

## Riskiest slice: **S3**

**Not S4**, and the distinction is the same one the last unit's S6 forced. **S4 has the highest
uncertainty and comparatively contained risk**: its answer is genuinely unknown, but every outcome —
feasible, not feasible, not established — lands back at a human gate with the rest of the pass
intact, and its `Do NOT` list can be checked by looking at whether a workflow file moved. Uncertainty
that has been deliberately contained is not the risk to nominate.

**S3 is the riskiest because it is the only lane whose wrong answer can get ratified into a weakened
safety property.** Its case asserts that a gate which cannot run reads `not-run` and the verdict
**holds** — never a quiet go. That is not a test detail; it is the property that keeps the release
check from saying "go" about a gate nobody ran, and `spec.md` flags it as mattering more than case
A's *in both directions*.

Two things make it worse than its small, read-only diff suggests. First, **the two answers look
alike from the outside and have opposite consequences**: "the case asserts the property wrongly on
Linux" and "the property does not hold on Linux" both present as one red case with the same
expected-versus-got string. A lane that reports the first when the second is true hands the human an
A3 decision whose honest form is "edit the test", after which the suite is green, the fix is
recorded, every criterion in this unit reads satisfied — and the release check can report a go while
a gate did not run, with no test left anywhere that could fail. That is A7's failure with the
paperwork in order. Second, **its own correctness is not harness-provable**: the case is green on
bash 3.2 and red on the runner, so no fixture in this suite can distinguish the readings, and the
only defence is that the lane was told to report the property's status *separately from* the case's
status. That instruction is the whole mitigation, and it is the line in S3 worth reading twice at
this gate.

Runner-up: **S4**, for over-claiming. Its failure mode is quiet and specific — reading a published
image manifest, finding a bash version that matches, and reporting "feasible" in a way the second G1
reads as "covered". The spec's own warning is that an option which only *appears* to give the older
shell coverage is worse than none, and S4's constraints require the citation and its limit to travel
together for exactly that reason.

Not nominated, and worth saying why: **S1** and **S2** are the two lowest-risk slices in the pass.
S1's output is checkable arithmetic against a run's own totals, and S2's blast radius is one markdown
file about a case whose worst outcome is an honest `unknown`.

---
---

# Second pass — the fix group

**All four spike slices returned and merged.** This section is the second G1 the pass above deferred,
cut against the evidence that was missing then and against the four decisions recorded in
`docs/loop/decisions.md` → *"Second G1: close the eviction convergence gap, fix case B's fixture, add
a macOS job (2026-08-17)"*. It **extends** the first pass; every contract that pass pinned still
holds, and S-numbering continues at **S5**.

**4 slices · genuinely concurrent lanes: 1 (S7, buildable alongside S5/S6 — merged after them) ·
critical path S5 → S6 → S7 → S8 · then A1, which is the human's**

The four decisions this pass cuts against, restated so no slice re-derives them:

| Case / question | Decision (not reopened here) |
|---|---|
| **Case A** (`:429`) | The code is wrong. Close the convergence gap in `scripts/record-cost-event.sh`'s `append_and_evict()`. `L7` (appenders never block on the evict lock) must not regress; the change stays the minimum the decision authorises. Loosening or removing the assertion is REJECTED. |
| **Case B** (`:2520`) | The **case** is wrong. Fix the fixture to force shellcheck's absence portably — discover where it actually resolves and exclude that, never an allow-list. `ship-check.sh` untouched, no gate added or removed, shellcheck policy unchanged. Reading case B's red as evidence against the not-run/hold property is REJECTED; that property was checked separately and holds. |
| **The contract** (OQ2+OQ3) | Two-directional, enforced by adding **`macos-latest`** as a second job. The `ubuntu-latest` job keeps its one-job/three-step shape. S4's citation-is-not-proof limit must survive into the A5 statement. |
| **A5 / A6** | A5 is now cuttable and is its own slice. A6 is now in scope: a second job changes what runs where, so `docs/loop/checks.md` changes — in the same commit as the workflow. |

## The seam

The seam is **S5**, and it is the one slice in this whole unit that changes behaviour a user has.
Case A's decision is the only one of the four where the *product* is wrong rather than its test or its
coverage: today the cost ledger's declared cap has no convergence guarantee under enough concurrent
append pressure, on any platform, and the only thing that ever said so was one red case on one CI run.
Fixing it delivers observable value even if nothing else in this unit ever lands — the ledger starts
honouring the bound it documents. Everything after S5 is evidence machinery: S6 makes an existing
guard portable, S7 buys a second platform's evidence, S8 writes down what is claimed and what produces
the evidence for it.

That ordering is deliberate and is *not* layer habit. S6 does not depend on S5's code; S7 does not
depend on either. What orders them is stated per slice, and exactly one of the three orderings is a
textual collision rather than a logical dependency — said so, in the slice, rather than left to look
like a real edge.

## Pinned contracts — second pass

Extends the first pass's table; nothing there is revised. A builder that believes one of these is
wrong returns `needs-decision` rather than changing it.

| Contract | Value | Why it is pinned |
|---|---|---|
| Case-count deltas, per slice | **S5 +2 · S6 +1 · S7 0 · S8 +2** → `421` today, **`426`** once the group has landed | Two lanes both bumping `README.md:167`'s literal conflict *by construction*, and the loser's merge leaves the suite red on a case its diff never touched. Pinning the deltas at G1 is what lets each lane compute its own literal without asking. A lane whose honest delta differs states it in its return; the harness's own final `docs (case count)` case is the arbiter, never this table. |
| Where new cases go | Appended **before** the final `docs (case count)` case, which stays last in the file | That case's `PASS + FAIL + 1` arithmetic is only the grand total if it runs last. Its own comment says so. |
| The two assertions under repair | Case A's expected string stays `yes`; case B's stays `yes yes 1` | Both decisions fix the thing *around* the assertion. A changed expectation is the "made green by removing evidence" failure (A7), whichever side it is on. |
| `scripts/ship-check.sh` | **Not edited by any slice in this pass.** Not a line, not a gate, not a message | Case B's decision. No observation anywhere shows a defect in `gate2_shellcheck`, and the three-gate set is settled by a prior decision. |
| New configurables | **None, in any slice.** A slice that believes it needs one returns `needs-decision` | A9, and the standing rule that no threshold, default, or suggested value ships anywhere in this repository. This is what makes A9 vacuous for this unit rather than unmet — see the traceability table. |
| Making red acceptable | `continue-on-error`, an `if:` guard that skips a step or a platform, a known-failures list, de-blocking a step, and skipping a case on a platform are all out of bounds in every slice. Reaching for one returns `needs-decision` | Non-goal *"not making red acceptable"*, plus A7 outright. It stays out of bounds even when it is the fastest route to green. |
| A third failing case, if one appears | **Not this pass's to fix.** The floor is a lower bound (S1); a case that fails only once the two known ones are resolved needs its own recorded human decision (A3), so it returns `needs-decision` and does not get fixed inside whichever slice found it | A3 fails "one decision applied to more than one case as a group", and this pass's decisions authorise exactly two case-level changes. |
| Local green ≠ the claim | Every slice's local evidence is `bash tests/guardrails.test.sh` on the maintainer's bash 3.2 host plus `shellcheck -S warning scripts/*.sh`. **Neither is evidence for A1, A2's resolved-tree count, or A5.** A container may be used to observe a Linux-only red and must be labelled investigation-grade | Unchanged from the first pass, and it now binds harder: two of these slices have reds that are *not observable at all* on the maintainer's host, and that asymmetry is stated in the slice rather than papered over. |
| Nobody pushes | No slice pushes, dispatches, re-runs, tags, or re-tags anything. The push that produces A1's evidence is the human's, after the group merges | A1 and A2's resolved-tree half are the human's; see the traceability table. |

## Order and concurrency — and the honest answer about parallelism

```
merge order                                        files each lane owns
-----------------------------------------------------------------------------------
S5  eviction convergence gap in append_and_evict()   scripts/record-cost-event.sh
 |                                                   tests/ (section b)  README:167
 v
S6  case B's fixture forces absence portably         tests/ (case B)     README:167
 |
 v
S7  macos-latest job + checks.md, one commit         .github/ci.yml      checks.md
 |      ^-- may be BUILT concurrently with S5/S6: its two files are disjoint
 v          from theirs. Merged here for evidence hygiene, not conflict.
S8  claimed platforms + their evidence producers     checks.md  tests/   README:167
 |
 v
A1 / A2 (resolved tree) -- THE HUMAN's: push, then read both jobs' own run records
```

- **Genuinely concurrent: one lane, S7.** Not two, not three. S5, S6 and S8 all touch
  `tests/guardrails.test.sh` and `README.md:167`'s literal, and the harness's own last case asserts
  that literal equals the live tally — so any two of them in flight together conflict at the same
  number, every time, and the loser's merge leaves the suite red on a case its diff never touched.
  This is the same finding the first pass recorded; it is restated here because a fix group is exactly
  where the temptation to promise parallelism lands.
- **S6 `Depends on: S5` is a textual dependency and says so.** There is no logical ordering between
  the ledger's eviction and a ship-check fixture. What orders them is `README.md:167`. Either order
  works; pick one at G1 and keep it, because the second lane's literal is computed from the first's.
- **S7's merge order is an evidence-hygiene choice, not a file conflict.** Merged after S6, the first
  pushed run carrying the second job also carries both fixes — so a red on either job is attributable
  to a platform rather than to a fix that had not landed yet. Merged first, every red run needs a
  paragraph to explain.
- **S8 depends on S7 for a real reason:** A5 fails a platform claimed with nothing producing evidence
  for it. If the statement lands before the job exists, the slice ships precisely the failure A5 was
  written to catch, and its own new case would be asserting a claim about a job that is not there.

**If the human would rather run fewer lanes**, the merge to make is **S7 + S8** (one workflow change
and the statement about it, both about what runs where). The pairing to refuse is **S5 + S6**: two
unrelated causes, two separate recorded decisions, and A3 fails a single change covering both.

---

## Slices

### S5 — Close the convergence gap in `append_and_evict()` so the ledger honours its declared cap
```
Owner:       loop-build
Context:     scripts/record-cost-event.sh -- `append_and_evict()` (~L250-279) and the
             header notes that document L7 (never block a spawn) and its precedence over
             L9 (~L60-70, L96); spike-case-a.md, ALL of it, but especially §1's literal
             reading (a lock-loser never retries; the winner gives up after 5 attempts and
             releases regardless) and §3 (H1 -- a platform/dialect cause -- is REFUTED by
             20/20 trials; H2, the arrival-rate reading, is open);
             tests/guardrails.test.sh section (b) at :407-435, its three existing cases
             (:429 convergence, :431 valid JSON, :433 never-empty) and section (a)'s
             newest-N ordering case at :405; decisions.md's second-G1 entry, Case A bullet;
             spec.md A3, A7, A8, A9 and the "not a redesign of the cost ledger" non-goal;
             README.md:167's `421 cases` literal.
Constraints: - THE BEHAVIOUR TO ACHIEVE, stated as behaviour and not as an algorithm: once
               every concurrent appender has finished, the ledger is at or under the
               declared cap -- including when appenders lose the evict race at the moment
               the final lines land. HOW is the builder's, inside the two limits below.
               This envelope deliberately names no mechanism; picking one here would be
               designing the fix at G1.
             - HARD LIMIT 1, L7 must not regress: an appender's own line is written before
               anything is decided about the evict lock, and no appender's wall clock grows
               with how long another process holds that lock. Guarded by its own case
               below.
             - HARD LIMIT 2, the minimum the decision authorises: `append_and_evict()` and
               the harness. NOT the ledger's line format, NOT the retention order (newest-N
               -- :405 must still pass unmodified), NOT the cap's env var name or its
               non-numeric fallback (:475), NOT /cost, cost-report.sh, cost-ledger-lib.sh,
               record-recovered-cost.sh, or the budget gate. The spec's ledger non-goal
               binds everywhere beyond what this decision names.
             - NO NEW CONFIGURABLE of any kind (A9). If the fix appears to need one, return
               `needs-decision` -- do not ship one unset "harmlessly".
             - RED IS OBSERVED, NOT REASONED, and this is the slice's central discipline.
               spike-case-a.md §2 found 20/20 pre-fix trials PASSING under ordinary
               pressure, so a case built at ordinary pressure would be green before AND
               after and would prove nothing. Construct the scenario, then run the new
               case's own body against a COPY of the pre-fix script
               (`git show <base>:scripts/record-cost-event.sh` into a temp dir) and record
               5/5 consecutive FAILS there, then 5/5 consecutive passes against the fixed
               script. If no 5/5-red scenario can be constructed, return `needs-decision`
               with what was tried -- never a weaker case, and never a green slice carrying
               a test that could not have failed.
             - Existing cases :405, :429, :431, :433, :475 are not edited, and pass.
             - bash 3.2 (this host) and the runner's bash both; `shellcheck -S warning
               scripts/*.sh` clean; no jq/python3/GNU-only requirement introduced. Note
               fractional `sleep` is already established as portable here (spike-case-a §1).
             - README.md:167's literal is bumped to the harness's own new total IN THIS
               COMMIT (+2 expected, per the pinned deltas); new cases go before the final
               `docs (case count)` case, which stays last.
Output:      scripts/record-cost-event.sh; tests/guardrails.test.sh (new cases inside
             section (b) only); README.md (the one literal).
Done when:   With the cap set to C and N concurrent appenders run to completion, the ledger
             holds at most C lines -- in a scenario that is red 5/5 against the pre-fix
             script and green 5/5 after -- while an append still completes and lands its
             line while another process holds the evict lock, and the full suite is green
             on bash 3.2 with shellcheck clean.
Test set:    5 cases -- 2 new, 3 existing regressions. Selection rule: ONE input dimension
             actually matters here (who holds the evict lock at the moment the final appends
             land), so this is not a pairwise problem; it is the criterion, its named
             constraint, and the existing invariants that must not move.
               1. NEW, RED->GREEN, and the one that carries the slice: after all appenders
                  finish, `wc -l` <= cap, in a scenario chosen to defeat a fixed retry
                  bound. Falsification is mandatory and is the pre-fix-copy run above.
                                                                          [A3 case A, A7]
               2. NEW, REGRESSION GUARD, and labelled as one rather than disguised as
                  proof: with the evict lock held by another process, an append completes,
                  its line is present, and its wall clock does not scale with how long the
                  lock stays held. GREEN BEFORE AND AFTER -- it proves the fix did not cost
                  L7, not that the fix works.                                        [L7]
               3. :429 unmodified, same expected `yes`, still green on this host.  [A7, A8]
               4. :431 and :433 unmodified -- retained lines remain complete JSON and the
                  ledger is never observed empty. A convergence fix that trims harder must
                  not start being observed mid-rename.                            [A8, H3]
               5. :405 and :475 unmodified -- newest-N retention order and the non-numeric
                  cap fallback are both outside this decision.                       [A8]
             Fails now: case 1 fails against the pre-fix script by construction, and that
             is demonstrated rather than asserted. Nothing in this repository currently
             fails on the convergence gap on this host -- which is exactly why case 1 has
             to be built and falsified rather than borrowed from the runner.
Do NOT:      - Do not touch scripts/ship-check.sh, cost-ledger-lib.sh, cost-report.sh,
               record-recovered-cost.sh, check-budget-gate.sh, or any other script.
             - Do not touch tests/guardrails.test.sh:2508-2522 (case B and its fixture) --
               that region is S6's, and two lanes in one file at one literal is the
               conflict this plan is ordered to avoid.
             - Do not edit .github/workflows/ci.yml, docs/loop/checks.md, spec.md, any
               spike-*.md, or this file.
             - Do not modify, delete, skip, renumber, or weaken ANY existing case, and do
               not change case A's expected string. Loosening it is a rejected option.
             - Do not add an env var, threshold, default, or "suggested" value.
             - Do not change the ledger's schema, its retention order, or any other write
               path's semantics; do not touch /cost's output or the budget gate.
             - Do not reach for continue-on-error, a known-failures list, a platform skip,
               or de-blocking a step. Return `needs-decision` instead.
             - Do not push, dispatch, re-run, or tag anything.
             - Do not report a container run as evidence for A1 or A2's resolved-tree count.
Depends on:  nothing
```

### S6 — Make case B force shellcheck's absence portably, without touching the gate or its assertion
```
Owner:       loop-build
Context:     tests/guardrails.test.sh:2508-2522 -- case B, its `new_ship_fixture` call and
             its hard-coded `PATH="/usr/bin:/bin:/usr/sbin:/sbin"` trigger; the fixture
             builder at :2463-2480 and `gate_line` at :2482; the SIBLING case at :2536
             (`ship: a missing gate file reads not-run by name, verdict hold`) which
             exercises the same not-run -> hold pathway through a platform-independent
             trigger and PASSED on the runner; scripts/ship-check.sh's `gate2_shellcheck`
             (~:143) READ ONLY -- it is a `command -v` lookup and it is correct;
             spike-case-b.md §1 (the mechanism: apt's shellcheck installs to /usr/bin,
             inside the fixture's own allow-list) and §2 (the safety property HOLDS on
             Linux -- do not treat this red as evidence against it); decisions.md's
             second-G1 entry, Case B bullet; spec.md A3, A7, A8 and the "not a change to
             the shellcheck policy" non-goal; README.md:167.
Constraints: - The trigger must achieve GENUINE ABSENCE PORTABLY: discover where
               `shellcheck` actually resolves on whatever host is running the suite and
               exclude that, rather than allow-listing a fixed set of directories that
               happened to be right on one machine.
             - It must also be correct when shellcheck is absent ALTOGETHER (`command -v
               shellcheck` empty): the case still reads not-run / hold / non-zero and does
               not error, mis-expand, or silently pass for the wrong reason. This is not
               hypothetical -- the `macos-26-arm64` image manifest S4 cited lists NO
               shellcheck, so S7's platform may be one where absence is already the
               default.
             - The expected string stays `yes yes 1`. Only the way absence is produced
               changes. Loosening the assertion is a rejected option.
             - scripts/ship-check.sh is NOT edited; no gate is added or removed; no gate's
               output changes; the shellcheck policy (severity `-S warning`, `scripts/*.sh`
               scope, whether `tests/*.sh` is covered) is unchanged.
             - +1 case exactly, appended before the final `docs (case count)` case, with
               README.md:167 bumped to the harness's own new total in the same commit.
             - THE RED IS NOT OBSERVABLE ON THIS HOST, and the slice says so rather than
               implying otherwise: case B is green here today. Demonstrate the pre-fix red
               INVESTIGATION-GRADE, in a throwaway Linux container with apt's shellcheck at
               /usr/bin (spike-case-b §1 reproduces this in three commands), label it
               investigation-grade in the return, and name A1's real run as the only proof.
               The container is not committed and is not a requirement for running the suite.
Output:      tests/guardrails.test.sh (case B's own region plus one new case); README.md
             (the one literal).
Done when:   Under the environment case B runs ship-check in, `command -v shellcheck`
             resolves nothing on a host where shellcheck is installed anywhere at all, gate
             2 reads not-run, the verdict reads hold, the exit is non-zero, the sibling case
             at :2536 is untouched and green, and the full suite is green on bash 3.2 with
             shellcheck clean.
Test set:    3 cases -- 1 new, 2 existing. Selection rule: the defect is that the case's
             SETUP never asserted it had achieved its own precondition, so the new case is
             that missing assertion; the other two are the pair that must not move.
               1. NEW, RED->GREEN (on Linux): the case's own trigger achieves absence --
                  under the exact environment the case invokes ship-check in, a shellcheck
                  lookup resolves nothing. Red today wherever shellcheck lives inside the
                  old allow-list (`/usr/bin`, per spike-case-b §1's `dpkg -L` and its
                  PATH-scoped `command -v`); green after. On this host it is green both
                  sides -- STATE that asymmetry, do not hide it.       [A3 case B, A4-adjacent]
               2. :2520 unmodified in expectation (`yes yes 1`), green on both platforms
                  after the trigger changes.                                     [A3, A7]
               3. :2536 UNTOUCHED and green -- the platform-independent guard on the same
                  not-run -> hold property. It is the reason the property keeps a guard
                  that does not depend on PATH at all, which is what makes editing case B
                  safe rather than a quiet weakening.                        [A7, safety]
             Fails now: nothing in this repository asserts that case B's fixture actually
             produced the absence it assumes; that unasserted precondition IS the defect.
Do NOT:      - Do not edit scripts/ship-check.sh, add or remove a gate, or change what any
               gate prints. No observation supports a change there.
             - Do not change shellcheck's severity, file scope, or coverage of tests/*.sh.
             - Do not touch section (b) (:407-435) or scripts/record-cost-event.sh -- S5's.
             - Do not edit .github/workflows/ci.yml, docs/loop/checks.md, spec.md, any
               spike-*.md, or this file.
             - Do not make the case conditional on the platform, skip it anywhere, or gate
               it behind `uname`. A case absent on one platform is A4's own failure.
             - Do not "fix" this by arranging for shellcheck to be installed, moved, or
               shimmed anywhere, and do not touch other ship cases (:2604, :2685, :2717,
               :2719) that assume shellcheck IS present -- they are S7's concern.
             - Do not weaken, delete, or renumber any case; do not change case B's expected
               string.
             - Do not push, dispatch, re-run, or tag anything.
             - Do not cite the container as evidence for A1.
Depends on:  S5 -- README.md:167's literal ONLY, a textual collision by construction, not a
             logical dependency. If the human reorders the two, this line and S5's delta
             swap; nothing else changes.
```

### S7 — Add `macos-latest` as a second job, and update `docs/loop/checks.md` in the same commit
```
Owner:       loop-build
Context:     .github/workflows/ci.yml -- one job `guardrails` on ubuntu-latest, three
             steps (`shellcheck`, `scripts are executable`, `guardrail tests`);
             docs/loop/checks.md -- the enumeration, its own rule ("add a row here, on both
             sides, whenever a check is added, removed, or renamed"), and its deltas table;
             tests/guardrails.test.sh:3786-3800 -- the parity case that ITERATES every
             `^      - name: ` line in ci.yml and requires each to appear in checks.md, plus
             :3661-3720 (the cases that extract and execute ci.yml's own step body) and
             :3803-3820 (the doc's content cases); spike-platforms.md -- the four candidate
             labels with pinned manifest commits, the exact match/mismatch table
             (`macos-latest`/`macos-26` arm64: bash 3.2.57(1)-release exact, arm64 exact, OS
             point-version close and ROLLING), and its own statement that a manifest is not
             proof; decisions.md's second-G1 entry, the contract bullet; spec.md A4, A6, A7,
             A8 and the "not a general CI improvement" non-goal.
Constraints: - The `ubuntu-latest` job is UNCHANGED: same single job, same three step names,
               same run bodies, same order. Not restructured into a matrix, not renamed.
             - Add exactly ONE second job, `runs-on: macos-latest`, running the same suite
               file with the same invocation and NO platform conditionals. Nothing else:
               no caching, no linter, no coverage step, no scheduled run, no artifact
               upload, no new trigger, no permissions block.
             - The macOS job's `- name:` values are DISTINCT from the ubuntu job's, so the
               existing iterated parity case forces a real checks.md row for each instead
               of silently matching the ubuntu names. A parity case satisfied by a
               coincidence of names is a hollow one.
             - THE LANDMINE, named because it is knowable now and expensive to discover on
               a pushed run: four harness cases assume shellcheck is ON PATH -- :2604,
               :2685, :2717, :2719 -- and the `macos-26-arm64` manifest S4 cited lists no
               shellcheck. Install it in the macOS job's own shellcheck step, mirroring what
               the ubuntu step already does with apt. Installing a tool in a CI step is not
               a new dependency for anyone RUNNING the suite; the zero-dependency
               constraint is about the suite's own requirements and is not relaxed.
             - If the suite needs anything else to pass there, that is a NEW FAILING CASE:
               return `needs-decision` naming it with expected-versus-got. This pass's
               decisions authorise exactly two case-level changes (A's and B's) and A3
               forbids one decision covering a group.
             - docs/loop/checks.md is updated IN THE SAME COMMIT (A6): both jobs
               enumerated, which platform runs which steps, the deltas table extended, and
               A4's statement -- both jobs run the same file with the same invocation and
               no case is conditional on platform, so the two jobs' reported totals must
               match, and any case deliberately not run somewhere would have to be named
               there. Also record that the macOS image's OS point-version is a moving
               target. All four existing checks.md cases keep passing.
             - Adds NO harness case, so this slice does not touch README.md:167. If a case
               seems needed, it belongs to S8 -- return `needs-decision` rather than adding
               one here and colliding with S8's literal.
             - Guardrail exit codes, env-var overrides, subagent-only scoping, and
               ship-check.sh's three declared gates are all unchanged (A8).
Output:      .github/workflows/ci.yml; docs/loop/checks.md. Two files, one commit.
Done when:   ci.yml declares two jobs -- the untouched ubuntu one and a macos-latest one
             running the same suite -- docs/loop/checks.md enumerates both and states A4's
             equal-totals expectation, the iterated step-name parity case passes over the
             new YAML, and the full suite is green on this host with shellcheck clean.
Test set:    4 cases, all existing, and that is the point of the cut: selection rule --
             this repository ALREADY has iterated parity cases that read ci.yml itself
             rather than a retyped copy, so the slice's test is theirs and no new case is
             needed to prove it.
               1. RED->GREEN, LOCALLY OBSERVABLE WITHOUT A PUSH -- :3798 (`every ci.yml
                  guardrails step name appears in docs/loop/checks.md, iterated`) FAILS with
                  the new job's steps in ci.yml and the checks.md hunk absent, and PASSES
                  with both. Demonstrate both states in that order: add the YAML, run the
                  suite, see red, add the doc, see green.                        [A6, A4]
               2. :3716 and the extracted-run-body cases at :3661-3720 still green -- the
                  ubuntu job's step names and bodies were not disturbed.         [A8, A6]
               3. :3824 and :3834 still green -- the doc's existing content claims survive
                  the doc growing a platform dimension.                              [A6]
               4. Full suite green on this host (macOS arm64, bash 3.2) with shellcheck
                  clean. This is the NEAREST AVAILABLE approximation of the new job's
                  platform and is explicitly NOT proof for A1 or A5.                 [A8]
             Fails now: :3798 cannot fail today because ci.yml has exactly the three step
             names checks.md already lists; it becomes the slice's red the moment the second
             job's steps exist, which is what makes it a real test rather than a formality.
             NOT PROVABLE HERE, stated rather than implied: whether the suite passes on
             macos-latest is knowable only from A1's real run. This slice makes that run
             possible; it cannot make the claim.
Do NOT:      - Do not edit tests/, scripts/, README.md, spec.md, any spike-*.md, or this
               file.
             - Do not restructure the ubuntu job into a matrix, rename its steps, reorder
               them, or change their run bodies.
             - No continue-on-error, no `if:` guard skipping a step or a platform, no
               known-failures list, no `|| true`, no soft-fail of any kind. Return
               `needs-decision`.
             - Do not write the A5 platform-claim statement or name an evidence producer
               per platform -- S8 owns that. checks.md gains WHAT RUNS WHERE, not the claim.
             - Do not add a status badge or a CI-health section anywhere (still a non-goal).
             - Do not add any further job, step, trigger, schedule, cache, or permission.
             - Do not push, dispatch, or re-run anything -- the push is the human's, at A1.
Depends on:  nothing file-wise -- its two files are disjoint from S5's and S6's, which is
             what makes it the one lane that can genuinely be BUILT concurrently. MERGE it
             after S6 so the first pushed run carrying the second job also carries both
             fixes; that ordering is evidence hygiene, not a conflict.
```

### S8 — State which platforms the suite is claimed to hold on, each with a named evidence producer
```
Owner:       loop-build
Context:     docs/loop/checks.md as S7 leaves it; .github/workflows/ci.yml as S7 leaves it
             (two jobs, two `runs-on:` values); spike-platforms.md -- the candidate table,
             the pinned manifest commits, the exact statement that "a citable image
             manifest is not proof", and the rolling-image caveat; intent.md's host record
             (macOS 26.6.1, arm64, `GNU bash, version 3.2.57(1)-release`);
             tests/guardrails.test.sh:3780-3820 -- `CHECKSMD_FLAT`'s flattening helper and
             the `checked-some 1, missing 0` iterated-grep shape to copy; spec.md A5, A4,
             A1's evidence rule; README.md:167.
Constraints: - The statement names EXACTLY the platforms the suite is claimed to hold on,
               and for each one the named thing that produces the evidence:
               `ubuntu-latest` -> the `guardrails` job's own suite step; `macos-latest` ->
               the second job's own suite step. Nothing else is claimed.
             - S4's LIMIT SHIPS WITH THE CLAIM, in the same place, not as a footnote
               elsewhere: an image manifest documents what an image installed, not that the
               suite passes there; only a real run of the suite on that platform is
               evidence; and the images roll, so the OS point-version is a moving target. A
               platform claimed with nothing producing evidence FAILS A5 -- and so does one
               whose evidence is a citation.
             - The maintainer's own host is described as WHAT THE macOS JOB APPROXIMATES
               (bash exact, architecture exact, OS point-version close and moving), NOT as
               a third claimed platform. A third claim would have only a person's memory
               behind it -- that is OQ2 answer 2, which A5 fails by construction.
             - No platform is described as covered, verified, guaranteed, or proven.
               "Claimed, with this as the thing that produces evidence" is the vocabulary.
             - The claim is ITERATED by a case, not prose-checked, so a third `runs-on:`
               added later fails it rather than passing unnoticed.
             - +2 cases exactly, appended before the final `docs (case count)` case, with
               README.md:167 bumped to the harness's own new total in the same commit.
             - No configurable of any kind (A9).
Output:      docs/loop/checks.md (the claimed-platforms statement); tests/guardrails.test.sh
             (two new cases); README.md (the one literal).
Done when:   docs/loop/checks.md states the claimed platforms with a named evidence producer
             each and carries the citation-is-not-proof and rolling-image limits; two new
             iterated cases enforce both directions of that mapping; and the full suite is
             green on this host with shellcheck clean.
Test set:    3 cases -- 2 new, 1 existing. Selection rule: ONE CASE PER DIRECTION of the
             mapping, because a single case covering both would keep passing while half of
             it drifted -- the exact failure docs/loop/checks.md's own opening rule warns
             about.
               1. NEW, RED->GREEN: every `runs-on:` value in ci.yml appears in the
                  claimed-platforms statement, ITERATED over the YAML, with a non-zero
                  checked count (`checked-some 1, missing 0`, the shape :3798 already
                  uses). Red before the statement exists; green after; red again the day a
                  third platform lands without a row.                                [A5]
               2. NEW, RED->GREEN: the statement carries, per claimed platform, a named
                  evidence producer, AND carries the citation-is-not-proof limit AND the
                  rolling-image caveat -- greps over the flattened doc, in the conjoined
                  shape :3824 already uses. Red today: nothing in this repository states
                  any of it.                                                     [A5, A1]
               3. :3798 and the other three existing checks.md cases still green -- the
                  doc grew a section and did not lose one.                        [A6, A8]
             Fails now: `grep -ri "claimed" docs/loop/checks.md` finds nothing, and no file
             in this repository names a platform the suite is claimed to hold on. Both new
             cases therefore fail on the current tree by inspection, not by argument.
Do NOT:      - Do not edit .github/workflows/ci.yml, scripts/, spec.md, any spike-*.md, or
               this file. Do not touch tests/ beyond the two new cases.
             - Do not claim any platform that no job in ci.yml runs the suite on, and do
               not name the maintainer's host as a claimed platform.
             - Do not use the words covered, verified, proven, or guaranteed about any
               platform; do not present a manifest citation as evidence.
             - Do not add a badge or a CI-health section (still a non-goal).
             - Do not add a configurable, threshold, or default.
             - Do not touch S5's section (b), S6's case B region, or any other existing
               case; do not weaken, skip, or renumber anything.
             - Do not push, dispatch, re-run, or tag anything.
Depends on:  S7 -- a real dependency, not a textual one: the evidence producer must EXIST
             before it is claimed, or the slice ships exactly the A5 failure it is written
             to prevent, and its case 1 would assert a mapping to a job that is not there.
             ALSO S6, for README.md:167's literal.
```

---

## The human's two actions, named as the first pass named them

Neither is a builder's slice, and neither is left implied.

1. **A1 — push the resolved tree and read the run.** A builder cannot push, and a simulated Linux is
   not evidence. After S5–S8 merge: push, then read both jobs' own records — each suite step's
   conclusion must be `success` (not `skipped`, the distinction that hid this for twelve runs), and
   each job's `total: N passed, M failed` line must show `M = 0`.
2. **A2's resolved-tree half — read the floor again, off that run.** S1 established the floor as a
   **lower bound against run `32026220384`** and said outright that the proof-grade count for the
   resolved tree can only come from a real post-fix run. If that run names a third failing case, it is
   the expected outcome of an unknown floor, not a surprise: it enters the same per-case path (a
   recorded A3 decision first), and no slice in this pass is licensed to fix it.

While reading it, compare the two jobs' totals against each other — that comparison **is** A4's
proof, and S7's checks.md statement is what says the two must match.

---

## Cross-unit collisions — named again, with a landing order

`docs/loop/recovered-figure-drops-slice-and-model/` still holds an `intent.md` and nothing else:
captured, not specced, not cut. When it is cut it will want `scripts/cost-ledger-lib.sh`,
`scripts/cost-report.sh`, `tests/guardrails.test.sh`, and `README.md:167`'s literal.

- **The overlap is real this pass**, where the first pass had none. S5 edits
  `scripts/record-cost-event.sh` — the same ledger writer's neighbourhood — and S5, S6 and S8 all
  touch the harness and that literal.
- **Land THIS unit's harness-touching slices (S5, S6, S8) first**, and do not start that unit's
  harness-touching or README-touching slices until this unit's A1 run has been read. Two reasons, and
  the second is the load-bearing one: the case-count literal conflicts by construction, and A1's
  evidence must be attributable — a run carrying another unit's harness changes cannot tell anyone
  whether *these* two fixes closed *these* two cases.
- That unit's own script-only slices (`cost-report.sh`, `cost-ledger-lib.sh`, with no harness or
  README edit) are safe to run alongside anything here.

---

## Criterion traceability — every criterion now assigned, the human's, or explicitly vacuous

Replaces the first pass's table for the criteria it left as *"not yet assignable"*. Nothing is left in
that state.

| Criterion | Where it stands after this pass |
|---|---|
| **A1** — real run, real pushed commit, step `success` | **The human's, post-merge.** Unchanged from the first pass and unchangeable: a builder cannot push, and a simulated Linux is not evidence. S5–S8 make it reachable; the push makes it true. |
| **A2** — the floor established, not assumed | **Half done, half the human's.** The observed floor is recorded in `spike-floor.md` (run `32026220384`, 2 failures, all 421 cases executed, recorded as a lower bound). The resolved-tree count is read off A1's own run, by the human. |
| **A3** — a per-case recorded human decision, and a change matching it | **All three parts now named. Evidence:** `spike-case-a.md`, `spike-case-b.md`. **Decisions:** recorded per case in `decisions.md`, second-G1 entry, 2026-08-17. **Changes:** **S5** (case A → the code) and **S6** (case B → the case). One slice per case, never one change covering both. |
| **A4** — no case silently absent on either platform | **Assigned: S7**, structurally and in writing. Structurally: one suite file, both jobs, same invocation, no platform conditionals, and every slice's `Do NOT` forbids a platform skip. In writing: S7's `checks.md` update states that the two jobs' reported totals must match and that anything deliberately not run somewhere would have to be named there. The comparison itself is read at A1, by the human. |
| **A5** — claimed platforms, each with a named evidence producer | **Assigned: S8**, and it is the slice with the over-claim risk. Two claimed platforms, each with a CI job as its producer; S4's citation-is-not-proof limit and the rolling-image caveat ship in the same place as the claim; the maintainer's host is named as what the macOS job approximates, not as a third claim. Enforced by two iterated cases, not by prose. |
| **A6** — `docs/loop/checks.md` matches both check sets | **Assigned: S7**, in the same commit as the workflow change, because this unit now does change what runs where. Enforced by an existing case that iterates `ci.yml`'s own step names, so the commit cannot land half-done. |
| **A7** — nothing made green by removing evidence | **Cross-cutting, and pinned rather than trusted.** No assertion is loosened (both expected strings pinned above), no case is deleted, skipped, or weakened, the count never goes down, and the per-slice deltas are pinned (+2/+1/0/+2 → 426) with the harness's own final case as arbiter. Every slice's `Do NOT` forbids `continue-on-error`, a known-failures list, de-blocking a step, and a platform skip, and reaching for one returns `needs-decision`. |
| **A8** — everything already guaranteed still holds | **Per-slice gate.** Every slice returns `bash tests/guardrails.test.sh` green on the maintainer's bash 3.2 host and `shellcheck -S warning scripts/*.sh` clean; the guardrails keep their exit codes, env overrides, and subagent-only scoping; `ship-check.sh` is untouched by all four slices, so its three declared gates are unchanged by construction. |
| **A9** — any configurable ships unset, asserted by a test | **VACUOUS, with the reason, and made vacuous on purpose.** No slice in this group introduces a configurable: `record-cost-event.sh` already reads `LARAVEL_LOOP_COST_MAX_LINES` and S5 is forbidden from adding another, and none of S6–S8 introduces one. All four `Do NOT` lists forbid a threshold, default, or suggested value. If any slice returns `needs-decision` asking for one, A9 attaches to that slice and its test — asserting zero output and no behaviour change with the variable absent — becomes that slice's, not a later slice's. |
| **OQ1** (per case) | Answered per case by the spikes, decided per case in `decisions.md`: case A = answer 2 (the code), case B = answer 1 (the case). Closed. |
| **OQ2 + OQ3** (the contingent contract) | Contingency cleared by `spike-platforms.md` (a candidate named and cited, not proven). Decided: two-directional, enforced by a second job. Built by **S7**, claimed honestly by **S8**. Closed. |
| **OQ4** (how much of the floor) | The floor read as 2 on the only completed run, and both are cut. A third case, if A1's run reveals one, needs its own A3 decision and is not this pass's — pinned above. |

## Self-audit against the five-point G1 test

Run before this reached the gate; a slice failing any point went back on my own bench.

| | S5 | S6 | S7 | S8 |
|---|---|---|---|---|
| **1. One owning agent** | `loop-build` | `loop-build` | `loop-build` | `loop-build` |
| **2. One commit's worth** | One function + its cases | One case's trigger + one new case | One job + its doc row, one commit | One statement + its two cases |
| **3. Independently testable** | Named 5-case set; case 1 red 5/5 pre-fix by mandated falsification | Named 3-case set; case 1 red on Linux, and the asymmetry is stated | Named 4-case set; case 1 is red locally the moment the YAML lands without the doc | Named 3-case set; both new cases red on the current tree by inspection |
| **4. Behaviour, not implementation** | "the ledger is at or under cap once appenders finish" — no algorithm named | "the trigger resolves no shellcheck" — no fixture code named | "two jobs, both enumerated, totals must match" | "each claimed platform has a named producer" |
| **5. Dependencies explicit** | `nothing` | S5, and labelled textual-only | `nothing` file-wise; merge order stated with its reason | S7 (real) + S6 (textual) |
| **`Do NOT` non-empty** | 9 lines | 8 lines | 8 lines | 7 lines |

Two things this audit caught and changed, recorded so the gate can see the reasoning rather than the
result: an earlier cut had **one** slice for "both fixes" (killed — A3 fails one decision applied as a
group, and the two causes are unrelated), and an earlier cut had **S7 and S8 as one slice** (killed —
"add a job **and also** state the platform claim" is the `and also` tell, and it would have let the
claim land in the same commit as the thing it claims, with no moment where the A5 case could be seen
red).

---

## Riskiest slice: **S5**

**S5, and specifically its test — not its code.** S5 is the only slice in this unit that changes
behaviour in the path every single hook write takes, and it is the only one whose red is not
observable anywhere by default: `spike-case-a.md` §2 ran the failing scenario **20 times** on real
Linux bash across two distributions, two bash versions and two CPU allocations, and it settled at cap
every single time. The one CI failure remains the only observation of this defect that exists.

That produces a specific, quiet failure shape. A builder writes a convergence case at ordinary
pressure, it passes, the fix goes in, the suite is green, README's literal is bumped, A3's case-A
decision reads satisfied, and A1's next run is green — while **the new case could never have failed
and the convergence gap may still be there**, now with a test standing in front of it saying
otherwise. That is worse than the state this unit started in, because today at least one red case
knows the truth. It is the same shape as the first pass's S3 risk: paperwork in order, evidence gone.

The whole mitigation is one constraint, and it is the line to read twice at this gate: **the new case
is run against a copy of the pre-fix script and must fail 5/5 there before it may be trusted, and if
no such scenario can be constructed the slice returns `needs-decision` rather than shipping a green
test.** Nothing else in S5 defends this.

Second risk inside the same slice, worth naming separately: `L7`. Appenders never blocking on the
evict lock is a documented guarantee that outranks the cap itself in the script's own header, and the
most natural-looking convergence fixes — retry until you get the lock, wait for the holder — cost
exactly that. Hence case 2, labelled honestly as a regression guard that is green on both sides rather
than dressed up as proof of the fix.

**Runner-up: S7**, for a different reason — it is the slice that can discover a **new floor on a
second platform**. Four existing ship cases assume shellcheck is on `PATH` (`:2604`, `:2685`,
`:2717`, `:2719`) and the image manifest S4 cited lists none, which is why the install requirement is
pinned in the envelope rather than left to be found on a pushed run. If anything *else* fails there,
the pressure toward `continue-on-error` or "just skip it on macOS" is at its highest precisely because
the fix group otherwise looks finished — which is why every slice's `Do NOT` forbids it by name and
why `needs-decision` is the required answer.

**S8** carries the over-claim risk the first pass nominated for S4, now one phase later: reading a
manifest match and writing a statement the next reader takes as "covered". Its constraints keep the
citation and its limit in the same paragraph for exactly that reason. **S6** is the lowest-risk slice
here — its blast radius is one case's setup, the property that case guards keeps an independent guard
at `:2536` that does not depend on `PATH` at all, and its worst outcome is a case that still only
passes for the old reason.

---

# Third pass — S9, the regression S5 shipped

Cut by the orchestrator, not `loop-slice`: the fix and its test are fully determined by the G2
follow-up decision recorded in `docs/loop/decisions.md`, and `loop-protocol` warns that a full
slicing pass on a one-slice task is pure latency. Recorded here so the envelope is auditable.

### S9 — Break the eviction loop on a failed `mv`, like its three siblings
```
Owner:       loop-build
Context:     scripts/record-cost-event.sh -- `append_and_evict()`'s eviction loop as S5 left
             it (~:274-285). Its four failure paths: non-numeric `wc` -> break; converged ->
             break; `mktemp` failure -> break; `tail` failure-or-empty -> break; and
             `mv -f ... || rm -f "$tmp"` -> NO break, which is the defect.
             The loop's own comment already states the rule it violates: "every other break
             below is a real I/O condition, never an arbitrary attempt cap." A failing `mv`
             IS a real I/O condition.
             The script's header contract, unchanged by S5 and currently broken by it:
             "Exits 0 on every path, including its own internal errors: cost accounting must
             never block, delay, or alter a spawn."
             docs/loop/harness-fails-only-on-linux/verify.md -- finding (a), with two
             independent reproductions (209 iterations under `chflags uchg`; 501 in a
             separate re-check).
             scripts/ship-check.sh's `run_bounded()` -- the house pattern for bounding a
             command with bash job control, because GNU `timeout` is absent on the
             maintainer's macOS host.
             README.md:167's `426 cases` literal.
Constraints: - THE CHANGE IS ONE LINE, and it is named because the human chose it, not left
               open: `mv -f "$tmp" "$OUT" 2>/dev/null || { rm -f "$tmp"; break; }`. Do not
               reintroduce an attempt bound, a counter, or a no-progress guard -- those were
               the options NOT chosen. If the one-line form proves insufficient, return
               `needs-decision` rather than substituting another shape.
             - CONVERGENCE MUST NOT REGRESS: the loop still retries while trims succeed and
               the file is over cap. S5's own convergence case must stay green, unmodified.
             - THE NEW CASE MUST NOT HANG THE SUITE. A test that runs the pre-fix loop
               un-bounded would never return. Bound the observation with bash job control,
               following `run_bounded()`'s precedent -- never GNU `timeout`, absent on bash
               3.2 macOS.
             - A PORTABLE TRIGGER IS REQUIRED for a persistently failing `mv`. `chflags` is
               macOS-only and `chattr +i` needs root, so neither is portable. One approach
               that is, and needs no privileges: put a stub `mv` that exits non-zero early on
               `PATH`, since the script calls `mv` unqualified. Use that or anything else
               portable; if no portable trigger can be built, return `needs-decision` with
               what was tried rather than a macOS-only case.
             - FALSIFY IT: run the new case's own body against a copy of the CURRENT script
               (`git show HEAD:scripts/record-cost-event.sh` into a temp dir) and show it
               fails there -- the loop does not terminate -- then passes against the fixed
               script. A case that cannot fail against today's HEAD proves nothing.
             - NO NEW CONFIGURABLE (A9). No change to the ledger's format, retention order,
               cap variable, or any other write path.
             - +1 case, appended before the final `docs (case count)` case which stays last;
               README.md:167 bumped to the harness's own new total in the same commit.
             - bash 3.2 and the runner's bash both; `shellcheck -S warning scripts/*.sh`
               clean; existing cases pass unmodified and the count never goes down.
Output:      scripts/record-cost-event.sh (the one line); tests/guardrails.test.sh (one new
             case in section (b)); README.md (the one literal).
Done when:   With `mv` made to fail persistently, `append_and_evict()` returns rather than
             looping, the evict lock is released, and the invocation exits 0 -- observed
             within a bound, red against today's HEAD and green after -- while S5's
             convergence case and every other existing case stay green.
Test set:    2 cases -- 1 new, 1 existing regression. Selection rule: exactly one new
             condition is in play (a persistently failing `mv`), and exactly one existing
             invariant must not move (convergence).
               1. NEW, RED->GREEN: with a failing `mv` in force, the eviction path terminates
                  within a bound and the lock directory is released. Red against HEAD, green
                  after -- falsified as described above.                        [the finding]
               2. S5's convergence case unmodified and green: the loop still drains to cap
                  when trims succeed.                              [A7, no convergence loss]
             Fails now: nothing in this repository exercises a failing `mv` inside the
             eviction loop, which is why the regression shipped through a 426-case green
             suite and a G2 pass on every other criterion.
Do NOT:      - Do not add an attempt bound, iteration counter, or no-progress guard.
             - Do not touch the stale-lock behaviour. It is confirmed pre-existing and a
               prior decision deliberately scoped it out; changing it here needs its own
               recorded decision.
             - Do not edit scripts/ship-check.sh, cost-ledger-lib.sh, cost-report.sh,
               record-recovered-cost.sh, or check-budget-gate.sh.
             - Do not edit .github/workflows/ci.yml, docs/loop/checks.md, spec.md, any
               spike-*.md, verify.md, log.md, or this file.
             - Do not modify, weaken, skip, or renumber any existing case.
             - Do not add an env var, threshold, or default.
             - Do not push, dispatch, re-run, or tag anything.
Depends on:  nothing -- S5 through S8 are all merged.
```
