# ship-gate-blind-to-ci

**Status: awaiting G0.** Three open questions are deliberately unresolved — see *Open
questions*. Two of them (OQ1, OQ2) decide the shape of the fix and are not a builder's call.

Amends nothing. This is the "new intent" that `docs/loop/ship-observe-automation/spec.md`
said would be required before an executable-bit check could enter the G3 gate set.

## Problem

**A maintainer can be told "go" at release time and ship anyway with the project's own
automated checks failing — and has, on every release so far.**

The action a maintainer runs before releasing reports every gate it knows about as passing,
and it has done so for six consecutive releases while the checks that run on the pushed
commit failed on all twelve runs in the surviving history. Neither side is lying: they are
different sets of checks, and *nothing anywhere tells the maintainer that*. The release
action reports on its own three checks and stays silent about the checks it does not run;
the pushed-commit checks report on theirs and are seen minutes later, in a browser, after
the tag already exists.

Two consequences a person actually feels:

1. **A red result stops meaning anything.** Twelve failures in a row for one long-standing
   cause is indistinguishable, at a glance, from twelve failures for twelve causes. A
   contributor's first push arrives red for a reason that is not theirs, and nobody can tell
   the difference without opening logs.
2. **The gap is bidirectional and invisible in both directions.** The release action checks
   something the pushed-commit checks do not (that the version stated in three files
   agrees). The pushed-commit checks check something the release action does not (that every
   script file carries the bit that lets it be run directly). A green result on either side
   is being read as "this is fine" while it can only ever mean "the part I look at is fine".

The immediate trigger is one file: a file that exists only to be *read into* other scripts,
never run on its own, committed without the run-me bit, failing a check that expects every
file of that kind to carry it. Whether that expectation or that file is the thing that is
wrong is OQ1, and it is not answered here.

This is the same shape as the rule already in `docs/loop/conventions.md` — *a green harness
never proves a hook is live*. Here: **a green local check never proves the pushed-commit
checks agree.** Same failure, one layer out.

## Users

- **The maintainer of this plugin, standing at G3.** Today: runs the release action, reads
  `verdict: go`, tags, pushes, and finds out separately (or does not) that the pushed commit
  is red. Has done exactly this six times. Their local machine cannot currently reproduce
  the failing check at all, so "it passes here" is true and worthless.
- **Anyone opening a pull request or reading the run history.** Today: sees red, cannot tell
  whether it is their change or the standing failure, and either investigates a fault that
  is not theirs or learns to ignore red — which is worse.
- **Whoever adds the next script or the next read-into-other-scripts file.** Today: has no
  stated rule for which kind of file needs the run-me bit, so they get it right or wrong by
  imitation, and find out only after pushing.

## Acceptance criteria

Each is observable, and names what would be checked to prove it. None of them names a fix.

- [ ] **A1** On the resolved tree, the repository's pushed-commit checks conclude *success*.
      Proof: a real run on a real commit, all steps green — not a local re-implementation of
      them. Per the convention above, only the run itself proves this.
- [ ] **A2** A maintainer can, before pushing, run something on their own machine that fails
      on a tree the pushed-commit checks would fail for this reason, and that failure names
      the offending file. Proof: introduce a fixture file in that state, run the local
      check, and read the filename out of its output. Where that check lives is OQ2.
- [ ] **A3** The two sets are no longer only discoverable by reading two files and diffing
      them by eye. A person can determine which checks run on the pushed commit but not
      locally, and which run locally but not on the pushed commit, from one place that says
      so. Proof: point at that place; confirm it names the version-agreement check as
      absent from the pushed-commit side and the run-me-bit check as absent (today) from the
      local side, and that the enumeration matches both files as they currently stand.
- [ ] **A4** Adding a new read-into-other-scripts file tomorrow produces the **same** answer
      from the pushed-commit checks and the local check — both fail naming it, or both pass.
      They never disagree. Proof: a harness case over a fixture directory containing one
      such file, asserting the two results are equal, run for both the with-bit and
      without-bit case.
- [ ] **A5** The rule that decides which files must carry the run-me bit is written down and
      is mechanically checkable — someone adding a file can apply it without asking. Proof:
      apply the stated rule to all eleven files currently under `scripts/` and `tests/` and
      confirm it classifies each one, with the classification matching what the resolved
      tree actually commits (`git ls-files -s scripts/*.sh tests/*.sh`).
- [ ] **A6** The repository records that every release through v0.6.0 shipped with the
      pushed-commit checks failing, so a future reader does not mistake the post-fix green
      history for an always-green one. Any part of that history whose cause is not known
      stays recorded as unknown. Proof: the record exists, names the affected versions, and
      contains no inferred cause.
- [ ] **A7** If the resolution introduces any configurable of any kind, it ships **unset**,
      and with it unset the repository behaves exactly as it did before. Proof: a test
      asserting zero output and no behaviour change with the variable absent from the
      environment — asserted by the test, not claimed in a comment. No threshold, default,
      or suggested starting value appears anywhere in this repository.
- [ ] **A8** Everything already guaranteed still holds, unmodified: the existing harness
      cases all pass without being edited, `shellcheck -S warning scripts/*.sh` is clean,
      and two runs of the release action against one unchanged tree still produce the same
      verdict. Proof: run all three; the harness case count does not go down and no existing
      case is rewritten to accommodate this work.
- [ ] **A9** Whatever the release action's gate set becomes, its verdict remains a function
      of exactly the gates it declares, and each gate still reports passed / failed /
      not-run by name, with a gate nobody could run never reading as one that passed. Proof:
      the existing cases covering that discipline pass unmodified, and if the gate count
      changes, the declared count in the file's own header and in `README` change with it.

## Non-goals

Read these out loud at G0. Every one of them is a direction this could plausibly wander.

- **Not a general CI improvement.** No new jobs, no matrix, no caching, no runner change, no
  added linter, no test-coverage step, no scheduled runs. The pushed-commit checks keep the
  one job and the same three steps unless OQ1's answer requires touching one of them.
- **No status badge, and no README section about CI health.** Making red visible in the
  README is a different intent; this one is about the two sets disagreeing.
- **No re-releasing history.** v0.2.0 through v0.6.0 are not re-tagged, deleted, re-pushed,
  or republished, and no release is amended to have been green. Anything touching a
  published artifact is G4 and stays a human action outside this work.
- **The pushed-commit checks are not made green by weakening them.** If OQ1 resolves toward
  narrowing what a check covers, the narrowing is by a stated rule (A5), not by excluding
  whatever is currently inconvenient. Silencing a check is not a fix and would reintroduce
  this exact problem with the evidence removed.
- **No gate discovery.** The release action still infers nothing from what the project
  happens to contain. `docs/loop/ship-observe-automation/spec.md`'s D1 stands, and this unit
  does not reopen it.
- **The release action makes no network call and runs no CI.** It does not invoke `gh`, does
  not query the run history, does not poll, and does not read a remote's status. It stays
  read-only and works offline. "Ask GitHub what it thought" is out of bounds as a mechanism
  for A2 or A3.
- **No CHANGELOG gate.** The other candidate parked by the prior unit stays parked. If this
  work makes adding a gate feel easy, that is not a reason to add that one too.
- **Nothing about cost.** The ledger, the budget gate, `/cost`, recovered figures, and the
  held question of automatic transcription wiring are all untouched. That one of the
  eleven files involved happens to be a cost library is a coincidence of which file lacked
  a bit, not a reason to open that unit.
- **No repo-wide file-mode audit.** Scope is `scripts/` and `tests/` — the paths the
  pushed-commit checks already iterate. Not hooks, not docs, not `.claude-plugin/`.
- **No fifth agent, no new command surface, no new state file.** Not a new phase, not a new
  hook registration.
- **Not a fix for "the maintainer forgot to look."** Making a human reliably read a browser
  tab is not in scope; making the two check sets agree, or say where they differ, is.

## Failure modes

| When | Expected behaviour |
|---|---|
| A new script is added without the run-me bit | Fails locally, before the push, naming the file — not only on the pushed commit minutes later |
| A new read-into-other-scripts file is added | Local check and pushed-commit checks give the identical answer (A4). Which answer is OQ1 |
| The two sets diverge again, for a new reason | The divergence is readable in one place (A3) rather than requiring a hand diff of two files |
| The release action reports go while the pushed commit is red | Resolution depends on OQ2 — either the release action can no longer say go in that state, or it says plainly which checks it does not cover |
| A check the local side needs is unavailable on this machine | Existing discipline unchanged: reported by name as not-run, verdict hold. Never a quiet go |
| A configurable introduced by this work is unset | Nothing happens. No output, no comparison, no behaviour change (A7) |
| The local check runs outside a git work tree | Says so and stops before running anything, as today |
| Someone reads a green local result as proof the pushed commit will pass | The output does not support that reading. Only A1's real run proves it |
| The cause of a historical red run cannot be established | Recorded as unknown. Never inferred from a later run's cause (A6) |

## Constraints

Existing behaviour that must not change:

- The release action stays read-only, offline, deterministic, and its verdict a function of
  exactly its declared gates. If a gate is added, `docs/loop/ship-observe-automation`'s S6
  is restated to match the new declared count, never quietly falsified.
- A gate that cannot be run means hold, never go-with-a-warning (that unit's D2).
- Both guardrails, their exit codes, their env-var overrides, and their subagent-only
  scoping. A human on the main thread is still never blocked.
- The existing harness cases pass unmodified; the case count does not go down.

Repo limits this must live inside:

- Zero dependency: bash plus coreutils only. No jq, node, python, or composer requirement.
  The maintainer's own machine runs bash 3.2 and has no GNU `timeout`; anything added must
  hold its guarantee there, not only on the Linux runner.
- Clean under `shellcheck -S warning` for `scripts/*.sh`.
- The prior unit explicitly declined an executable-bit gate, reasoning that the
  pushed-commit checks already covered it — a reasoning this intent's evidence contradicts,
  since those checks failed unseen for four days. That decision is reopenable here **only by
  the human at G0** (OQ2), and the release action's own header states its gate set is exactly
  three, hard-coded, by design. A fourth gate is a change to a documented design choice, not
  an implementation detail.
- No threshold, default, or suggested value ships anywhere in this repository, for anything.

## Open questions

Three. **None is decided here.** OQ1 and OQ2 change what gets built; OQ3 changes only how
much history this unit is asked to account for.

### OQ1 — Mark the library executable, or narrow the check to exclude libraries?

The file at issue exists only to be read into other scripts. It is never run directly. It
carries a shebang line (which is what makes "just mark it executable" look natural) and is
committed without the run-me bit.

1. **Mark it executable.** One mode change, done. Cost: the repository then asserts that a
   file which must never be run directly is runnable, and the next library added will face
   the same choice with no rule to apply — it becomes folklore. Nothing then distinguishes
   "runnable because it is a program" from "runnable because a check demanded it".
2. **Narrow the check so libraries are exempt.** Cost: this requires answering *what marks a
   file as a library* — and that sub-question is the real work. Candidate signals, each with
   a cost: a naming convention (cheap and mechanical, but renames a shipped file and other
   scripts reference it by name); the absence of a shebang (honest, and it is what the shell
   actually cares about, but means deleting a line from a working file and shellcheck then
   needs telling which dialect the file is); a marker comment inside the file (self-describing
   and needs no rename, but is a convention only this repository knows); an explicit exempt
   list in the check (most obvious, and the one most likely to rot into a place people add
   files to make red go away).

**No recommendation is offered.** Option 1 is a one-line change that leaves A5 unsatisfiable
without a follow-up; option 2 satisfies A5 and costs a decision about repository convention
that outlives this fix. That trade — a fast close versus a stated rule — is the human's.

### OQ2 — Should the release action gate on agreeing with the pushed-commit checks?

Its header states, with reasoning, that the gate set is exactly three, hard-coded, no
discovery. The prior unit declined an executable-bit gate specifically because the
pushed-commit checks covered it. That premise is what this intent falsified.

1. **Add a fourth gate mirroring the pushed-commit check.** Closes the gap in the direction
   that actually bit. Cost: "hard-coded, exactly three" becomes "hard-coded, exactly four"
   — the reasoning survives but the specific claim in the header, README, and the prior
   unit's S1/S6 all need restating. It also only closes today's divergence: nothing stops
   the sets diverging again tomorrow.
2. **Leave the gate set at three and put the parity check in the test harness instead.**
   The release action keeps its declared design untouched; the harness gains a case that
   fails when the two sets diverge. Cost: the harness is not what a maintainer runs at G3 —
   though the release action's first gate runs the harness, so a harness failure does reach
   the verdict indirectly. Whether that indirection is acceptable or merely clever is the
   question.
3. **Neither — make the release action state its own blind spot.** It prints which checks it
   does not cover, and the maintainer decides. Cost: this is a documentation fix to a problem
   that has already been read past six times. Cheapest, and least likely to work.

**No recommendation is offered.** 1 and 2 both satisfy A2 and A4; they differ in which
documented design choice gets rewritten. 3 satisfies A3 alone.

### OQ3 — Is accounting for the earliest failure in scope?

The intent records the earliest run's cause as `unknown` and does not infer it: that run
predates the file now failing, and its surviving log does not name a filename.

This does **not** change A1 through A5 — they are about the tree as it will be, not its
history. It changes only A6's demand. The question for the human:

1. **A6 as written** — record that the releases shipped red, name the versions, leave the
   earliest cause as unknown. No archaeology.
2. **Investigate first** — attempt to establish the earliest cause before the spec is
   considered settled, accepting that the log may not yield one and this may end at the same
   place after spending the time.

**No recommendation is offered**, because option 2's cost is unknowable until someone tries
it. What is not on the table is resolving `unknown` by inference from a later run's cause.

## G0 — what the human decides

1. **Approve** the problem framing and the non-goals; answer OQ1, OQ2, OQ3; proceed to G1.
2. **Approve the framing, defer OQ1/OQ2** — slicing then stalls, because both decide what
   gets built. Not recommended for that reason.
3. **Reframe** — the problem is the wrong one, or a non-goal above should be in scope.

Approval here is approval of the **problem and the non-goals**. It is not approval of a
solution and not permission to build.
