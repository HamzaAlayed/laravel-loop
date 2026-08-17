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
