# harness-fails-only-on-linux

**Status: awaiting G0.** Four open questions are deliberately unresolved — see *Open questions*.
OQ1 (per case, and it may differ between the two cases) and OQ2/OQ3 (the portability contract, and
whether anything enforces it in both directions) are not a builder's call and are not answered here.

Amends nothing. Built from `docs/loop/harness-fails-only-on-linux/intent.md`, which records the two
observed failures verbatim and deliberately assigns no cause. `docs/loop/ship-gate-blind-to-ci/` is
the unit that revealed this by unblocking the step; it did not cause it.

## Problem

**The project's only automated proof that it works gives one answer on the maintainer's machine and
a different answer on the machine that guards every push — and how far apart the two answers are is
not known.**

Three things a person actually feels:

1. **A local green is not a push-safe green.** The suite reports everything passing on the
   maintainer's host and reports failures on the runner. Both reports are honest; they disagree, and
   until one of them is fixed neither can be used as the evidence it exists to provide.
2. **The size of the problem is unknown, and that is part of the problem, not a footnote.** The
   guarding checks have completed the suite exactly **once, ever** — every earlier run stopped at a
   preceding step, so the suite was skipped rather than run. Two cases failed on that single run.
   **Two is a lower bound, not a count.** Resolving those two may expose more that were behind them
   in the same never-executed blind spot. Any plan that treats "two failures" as the whole problem is
   planning against a number nobody has evidence for.
3. **The rule the project states about where it must work runs in one direction only.** The stated
   constraint everywhere in this repository is that the work must hold on the maintainer's older,
   stock shell — *not only* on the guarding machine. The inverse has now bitten: work that holds on
   the older shell fails on the guarding machine's newer one. Nothing in the project says the
   reverse must hold, and nothing checks it, so the same class of failure can be reintroduced by the
   next change and discovered the same way — by accident, later.

Whether each failing case is a badly-written test or is correctly catching real platform-dependent
behaviour in the thing it exercises is **not established here**. It is OQ1, it is asked per case, and
the answer may differ between the two.

## Users

- **The maintainer, standing at release.** Today: runs the suite locally, reads zero failures, and
  cannot use that as evidence about the pushed commit. Their machine cannot currently reproduce
  either failure at all, so "it passes here" is true and worthless — the same shape as the standing
  convention that a green harness never proves a hook is live.
- **Anyone opening a pull request.** Today: sees red, and cannot tell a failure they caused from the
  two standing ones. This is the exact reading-red-as-noise problem the previous unit was opened to
  end, reappearing one layer in.
- **Whoever writes the next test case.** Today: writes it against the behaviour of whichever shell
  they happen to have, has no stated rule about which platforms it must hold on, and finds out only
  if a push happens to expose it.
- **Whoever reads the run history later.** Today: would read a post-fix green history as an
  always-green one, and would read one green run as proof the suite is portable.

## Acceptance criteria

Each is observable and names what would be checked. None names a fix.

- [ ] **A1** On the resolved tree, a **real run** of the guarding checks on a **real pushed commit**
      completes the suite and reports zero failures. Proof: that run's own output, plus the step's
      conclusion read from the run record (it must be `success`, not `skipped` — the distinction that
      hid this for twelve runs). Per this repository's standing discipline, only the run itself is
      proof: a locally-emulated, containerised, or otherwise simulated Linux is **not** evidence for
      A1, however convincing.
- [ ] **A2** The floor is **established rather than assumed**. The number of cases that fail on the
      guarding machine is recorded from a run in which every case actually executed, and every such
      case is named. If that number is larger than the two already observed, the additional ones are
      enumerated with their expected-versus-got strings, exactly as the intent recorded the first two.
      Proof: read the record; each named case traces to a run id and a line in the suite. A count
      inferred from the single prior run, rather than read off a run in which the suite completed,
      fails this criterion.
- [ ] **A3** Every case that failed on the guarding machine has, **individually**, a recorded human
      decision as to whether the case or the thing it exercises was wrong, and the change made
      matches that decision. Proof: for each named case, point at the recorded decision and at the
      change; a case altered with no recorded decision fails this, and so does one decision applied
      to both cases as a group.
- [ ] **A4** No case is silently absent on either platform. If any case is deliberately not run
      somewhere, that is visible by name and reflected in that platform's own reported case count.
      Proof: run the suite on both platforms and compare the two outputs — total run, total passed,
      total failed, and the name of anything not run. Two runs whose totals differ with nothing
      naming the difference fails this.
- [ ] **A5** The repository **states which platforms the suite is claimed to hold on**, and for each
      claimed platform there is a named way evidence for that claim is produced — either something
      that runs it there, or a written human procedure. Proof: read the statement; for each platform
      named, point at the thing that produces the evidence. A platform claimed with nothing behind
      the claim fails this. (Whether that list should be one platform or more is OQ3; this criterion
      is satisfiable under either answer, and takes no position on which.)
- [ ] **A6** If this unit changes what runs where, `docs/loop/checks.md` says so, and its enumeration
      still matches both check sets as they then stand. Proof: read the two files against that
      document, line by line, as that document itself requires.
- [ ] **A7** Nothing is made green by removing evidence. No case is deleted, skipped, or weakened
      except where A3's recorded decision says that case was wrong, and the total case count does not
      go down other than by exactly the cases that decision names. Proof: compare the suite's
      reported totals before and after against the recorded decisions — the baseline on the
      maintainer's host is `421 passed, 0 failed`, and on the guarding machine's single completed run
      `419 passed, 2 failed`. Making the step non-blocking, tolerated, or removed from the guarding
      checks fails this outright.
- [ ] **A8** Everything already guaranteed still holds, unmodified: the full suite still passes on the
      maintainer's stock older shell, `shellcheck -S warning scripts/*.sh` is clean, the release
      action still declares and reports exactly the gate set it declares today, and both guardrails
      keep their exit codes, their env-var overrides, and their subagent-only scoping. Proof: run all
      of them; a human on the main thread is still never blocked.
- [ ] **A9** If this work introduces any configurable of any kind, it ships **unset**, and with it
      unset the repository behaves exactly as it does today. Proof: a test asserting zero output and
      no behaviour change with the variable absent from the environment — asserted by a test, not
      claimed in a comment. No threshold, default, or suggested starting value appears anywhere in
      this repository.

## Non-goals

Read these out loud at G0. Each is a direction this could plausibly wander.

- **Not a general CI improvement.** No caching, no new linter, no coverage step, no scheduled runs,
  no artifact upload, no job restructuring. The guarding checks keep the one job and the same three
  steps unless OQ1's or OQ3's answer requires touching one.
- **Not a suite rewrite.** No test framework introduced, no change to how cases are declared,
  asserted, counted, or reported, and no reorganisation of the harness file. Only the cases the
  recorded decisions name are touched.
- **Not a portability abstraction layer.** No vendored coreutils, no shell-compatibility shim
  library, no wrapper indirection for tools that differ across platforms, and no raising of the
  minimum shell version. The zero-dependency, bash-3.2-and-coreutils constraint is not relaxed as a
  way of closing this.
- **Not a change to the shellcheck policy.** Severity, file scope, and whether `tests/*.sh` is
  covered all stay as they are. One failing case involves a gate reading `not-run` when shellcheck
  is unavailable; that is about the gate's reading, not about how much shellcheck covers.
- **Not a redesign of the cost ledger.** The other failing case exercises eviction. Its bound, its
  eviction order, its file format, its coverage caveats, `/cost`, the budget gate, recovered figures,
  and the held question of automatic transcription wiring are all out of bounds beyond exactly what
  the recorded decision for that one case requires.
- **Not a fourth release gate.** The release action's gate set stays exactly the three it declares;
  that count is a documented design choice settled by a prior decision and is not reopened here.
- **Not making red acceptable.** `continue-on-error`, removing the step, marking it advisory,
  allowing a known-failures list, or moving the suite off the guarding checks are all out of bounds.
  The problem is the disagreement, not the colour.
- **No status badge and no CI-health section anywhere.** Still a different intent, as it was for the
  previous unit.
- **No re-releasing history.** No release is re-tagged, deleted, re-pushed, or amended to have been
  green. Anything touching a published artifact is a human action at G4, outside this work.
- **No new agent, command, hook, state file, or phase.**
- **Not a fix for "nobody looked."** Making a human reliably read a browser tab is not in scope;
  making the two platforms agree, or say plainly where they do not, is.
- **Not a diagnosis delivered as a spec.** This document names no cause for either case, and a
  builder inheriting it is not licensed to pick one; A3 requires the human decision first.

## Failure modes

| When | Expected behaviour |
|---|---|
| A case passes on one platform and fails on the other | Named in that platform's output with expected-versus-got, and carried to a per-case human decision (A3) — never closed by whichever edit happens to turn it green |
| Resolving the two known cases reveals a third | The expected outcome of an unknown floor, not a surprise. The count was recorded as a lower bound (A2) and the new case enters the same per-case path |
| The suite is claimed green for a platform nothing ran it on | Not claimable. Only a real run on that platform is evidence; a simulated one is not (A1, A5) |
| A case is deliberately not run on some platform | Visible by name and in that platform's reported counts. Never silently absent (A4) |
| The maintainer's stock older shell stops being able to run the suite | A regression, not a fix. Fails A8 |
| A case is edited with no recorded decision behind it | Fails A3, regardless of the suite turning green |
| The guarding checks are made to tolerate the failures | Fails A7. Silencing a check reintroduces this problem with the evidence removed |
| A configurable introduced by this work is left unset | Nothing happens: no output, no comparison, no behaviour change (A9) |
| `docs/loop/checks.md` falls out of step with what runs where | Fails A6. That document states its own rule: an enumeration that drifts is worse than none |
| The cause of a case's platform-dependence cannot be established | Recorded as unknown, never inferred from the other case's cause. The two cases are unrelated as far as anything observed shows |

## Constraints

Existing behaviour that must not change:

- The full suite keeps passing on the maintainer's stock macOS bash 3.2 host, with no GNU `timeout`
  and no GNU-only coreutils behaviour assumed. That host stays a place the suite can be run and
  believed.
- Zero dependency: bash plus coreutils only. No jq, node, python, composer, or container runtime
  requirement is introduced for anyone running the suite.
- Clean under `shellcheck -S warning scripts/*.sh`.
- Both guardrails: exit codes, env-var overrides, subagent-only scoping, and a human on the main
  thread never blocked.
- The release action stays read-only, offline, deterministic, with its verdict a function of exactly
  the gates it declares, each reporting passed / failed / not-run by name, and a gate nobody could
  run never reading as one that passed.
- No threshold, default, or suggested value ships anywhere in this repository, for anything. Any
  configurable is unset by default and does nothing until a human sets it.

Limits on evidence:

- Only a real run on the real guarding machine proves a claim about the guarding checks. This is the
  same discipline as the standing convention that a green harness never proves a hook is live, and it
  was already applied as A1 in `docs/loop/ship-gate-blind-to-ci/spec.md`. A locally-simulated Linux
  may be used to *investigate*; it may not be cited as proof.
- The single completed run is the only observation of the suite on that platform that exists. Every
  figure derived from it is a lower bound.

## Open questions

Four. **None is decided here.** OQ1 changes what gets built and is asked twice, once per case.
OQ2 and OQ3 are raised deliberately without a recommendation, in either direction. OQ4 decides only
how much of the unknown floor this unit is asked to close.

### OQ1 — Per case: is the test wrong, or is it correctly catching real platform-dependent behaviour?

Asked separately for each case, because the answer may differ, and nothing observed suggests the two
share a cause. Neither case has been read for why it behaves differently, by anyone, and no
hypothesis exists to prefer.

**Case A — `tests/guardrails.test.sh:429`, `eviction under concurrency: settles at or under cap`**
(expected exit `yes`, got `no`).

**Case B — `tests/guardrails.test.sh:2520`, `ship: shellcheck absent from PATH reads not-run, verdict
hold`** (expected `yes yes 1`, got `no no 0`). Note for the human, not a diagnosis: this case's
expectation encodes a safety property the project has stated deliberately — a gate that cannot be run
reads `not-run` and the verdict holds, never a quiet go. Which side of it is wrong therefore matters
more than case A's, in both directions.

For each case, independently:

1. **The case is wrong** — it asserts something that was only ever true of one platform. Resolution
   is in the test. Cost: if the behaviour it was guarding is genuinely platform-dependent, changing
   the test discards the only warning anyone gets.
2. **The thing it exercises is wrong** — it behaves differently across platforms and the case is
   correctly catching that. Resolution is in the code the case exercises. Cost: a wider change than
   the failure looks like, in a unit this spec otherwise declares out of bounds.
3. **Both, or neither yet** — the case needs reading before this can be answered honestly, and that
   reading is itself work someone must be assigned. Cost: a G0 that ends in an investigation rather
   than a decision.

### OQ2 — Should the portability contract become two-directional, and what would enforce it?

Today the contract runs one way: must hold on the maintainer's older stock shell, not only on the
guarding machine. The inverse has now bitten, and nothing states or checks it.

1. **Keep it one-directional.** The older shell stays the authority; failures on the guarding machine
   are handled as they arise. Cost: this exact discovery repeats, by accident, later.
2. **State it two-directionally, enforced only by convention.** Written into the project's rules,
   with nothing mechanical behind it. Cost: a claim with nothing producing evidence for it — which
   A5 would then fail.
3. **State it two-directionally and put something behind it.** Cost: whatever OQ3 costs, since the
   only thing that produces evidence for a platform is something running there.

### OQ3 — Should the guarding checks cover more than one platform?

In scope **as a question only**. `docs/loop/ship-gate-blind-to-ci/spec.md` listed "no matrix" as a
non-goal; that was scoped to that unit and **does not bind this one**. It is neither a settled
prohibition nor a recommendation here.

1. **One platform, as today.** Cheapest. Cost: the older shell keeps having no automated evidence at
   all, and OQ2 answer 3 is unavailable.
2. **More than one platform.** Cost: unestablished, and it must be established before this option is
   costed rather than assumed — in particular, whether any hosted runner can actually reproduce the
   maintainer's shell version is **not known here** and would need checking. An option that only
   *appears* to give the older shell coverage would be worse than none.
3. **Something short of a second platform** that still produces evidence for the second direction —
   e.g. a human-run procedure, recorded. Cost: evidence that depends on a person remembering, which
   is the failure mode the previous unit was opened for.

### OQ4 — How much of the unknown floor is this unit asked to close?

1. **Close every case that fails on the guarding machine, however many there turn out to be.** A1 is
   then the unit's real finish line. Cost: the unit's scope is genuinely unknown at G0 and could grow
   after the first green-seeking run.
2. **Close the two known cases, then capture whatever the next completed run reveals as a new
   intent.** Cost: the unit closes without A1 satisfied, and the project is back to not knowing —
   which is the state this spec calls part of the problem.
3. **Establish the floor first, decide scope second** — one run whose only purpose is to enumerate
   every failure, then a scope decision on that evidence. Cost: an extra gate before any fix.
