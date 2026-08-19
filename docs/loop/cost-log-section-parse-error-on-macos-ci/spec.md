# cost-log-section-parse-error-on-macos-ci

**Status: G0 held and approved 2026-08-19, with one substantive change of scope** — see *G0
decisions*. All seven open questions are decided; `OQ1` was decided **against this document's own
recommendation**, and this document has been amended to carry that decision rather than to argue
with it. One residual question remains, and it belongs to the builder, not the human.

Source: `docs/loop/cost-log-section-parse-error-on-macos-ci/intent.md` (captured 2026-08-18T19:10:00Z,
commit `e59215c`), which is authoritative for what was observed and deliberately assigns no cause.
Prior art worth reading in full before slicing: `docs/loop/harness-fails-only-on-linux/` — in
particular `spike-case-a.md` (how this repository reads a mechanism without asserting a cause) and
`spike-platforms.md` (why a platform label is not a property) — and
`docs/loop/eviction-cap-not-honoured-under-contention/spec.md`'s proof-problem section, which this
unit inherits in a harder form.

Amends nothing. **This unit carries three things that must never be conflated, and the whole shape
of it depends on keeping them apart:**

1. **Instrumentation** — `PF1`–`PF6`. Making the next degraded read say which parser ran, what it
   returned, and which route produced the state.
2. **A fix for one verified route** — `PF12`–`PF15`. `cost_scan`'s state test is
   `printf '%s' "$out" | grep -q 'COST_N_LINES'` (`scripts/cost-ledger-lib.sh:976`): a `grep` that is
   missing or fails is **indistinguishable from a parse failure**, because the test's own dependency
   sits inside the thing it tests. That route is already recorded as verified in this repository
   (`tests/guardrails.test.sh:2770-2775`, 2026-08-18), reaches the exact observed state from
   **non-corrupt input**, and is reproducible — so it has a real red-before-green and is fixable
   without guessing at anything.
3. **No cause for the macOS CI sighting** — `PF11`. **This document still names none.** The fix in
   (2) is *not* claimed to explain that red, and must never be written up as though it were. If the
   CI fault recurs after this ships, that is a **new sighting against an instrumented library**, not
   a regression of this unit.

Queue position and build order, from `docs/loop/decisions.md` ("Backlog gate", 2026-08-19): this
unit entered `G0` first, ahead of the backlog, because it touches `scripts/write-cost-log-section.sh` and
`scripts/cost-ledger-lib.sh` — files two queued units also touch — and the point is to avoid building
on an unexplained fault. That is a constraint on this unit's shape, not a licence to widen it.

**This unit lands before `resumed-invocation-never-reaches-the-ledger`, and that ordering is
load-bearing.** That unit adds a record class **both** parser programs in
`scripts/cost-ledger-lib.sh` must learn, and its own `RS10` requires any parser change to land in
both programs "or the two disagree by construction" — this unit's neighbourhood, which is why it was
ordered after this one. Whoever slices it rebases onto this unit's landed change rather than developing
alongside it. See *Constraints — build-order coupling*.

## Problem

**One of the project's own checks went red once, said the cost ledger could not be parsed, and
nothing anywhere records enough for anyone to say why — including whether anyone will be able to say
why the next time it happens.**

Three things a person actually feels:

1. **The same two-line sentence is printed for several unrelated things.** "Could not read the cost
   ledger (parse error)" is what a reader of a `## Cost` section sees whether the ledger genuinely
   held unparseable content, the parser never executed, the parser executed and failed, or the code
   that decides whether the parser's output looked right could not itself run. A reader cannot tell
   "this unit's cost is unknown because nothing recorded it" from "this unit's cost is unknown
   because the tooling misfired on that machine that minute."
2. **The one occurrence consumed its own evidence.** Both parser invocations discard the parser's
   stderr (`2>/dev/null`, `scripts/cost-ledger-lib.sh:971` and `:973`), neither captures its exit
   status, and nothing records which of the two parsers was selected. So the only artefact of the
   failure is the text it wrote — which was enough to narrow the state and nothing else. Establishing
   even that much required reading the raw job log by hand.
3. **It is not reproducible, and it is not gone.** 0 divergences in 150 local iterations; 1 red in 3
   samples on commit `c32daf0`; never seen on `ubuntu-latest`; never seen on the maintainer's host.
   Two other units are queued against the same two files. Whoever builds those cannot currently tell
   their own new red from this standing one, and neither can whoever reviews it.

Whether the fault is in `cost_scan`, in the environment that second invocation ran in, or in what the
test case does around it is **not established here**, and nothing observed prefers an answer. The
`OQ3` decision — instrument the library *and* the harness — was taken precisely so that nothing this
unit builds depends on knowing.

## Users

- **Whoever closes a unit with `/loop`.** The close step runs this script. Today, if it degrades,
  the degraded sentence lands in `log.md`, the script prints nothing at all, and it exits 0 — so
  there is no moment at which anyone is told. They find out by reading the file later, or never. The
  recovery is cheap (re-run the script) and the damage is bounded; the silence is the cost, not the
  data loss.
- **Whoever reads a `## Cost` section months later.** Today: reads one sentence that covers at least
  four distinct situations, three of which mean the tooling failed and one of which means the ledger
  was genuinely bad. They have no way to tell which, and no way to know whether re-running would
  have produced a real figure.
- **Whoever reads a red run on this repository.** This is the acute cost right now. Today: the
  harness's failure line carries a diff of two file bodies and nothing else — no parser identity, no
  exit status, no stderr, no environment. The intent's author had to go to the raw job log to learn
  what the second run wrote, and after that the cause was still unknown.
- **Whoever builds `stale-evict-lock-permanently-defeats-the-cap` or
  `resumed-invocation-never-reaches-the-ledger`.** Both touch these files. Today they inherit one
  intermittent unexplained failure in the file `decisions.md` calls the most dangerous in the
  repository, with no way to distinguish it from a red they caused.
- **Nobody's recorded cost data is at risk.** This script never writes the ledger, and case (d) of
  the harness asserts that (`H1`/`DL7`). No criterion below trades that.

## What the record establishes — and the four things that shape this unit

None of this is an aside. §1–§3 are why a fix for the CI sighting cannot be specified; §4 is the one
route that *can* be, and the two must not be allowed to blur into each other at any point downstream.

### 1. The observed text narrows the state, and stops there

The sentence the second run wrote is produced by exactly two arms of
`build_section_body` in `scripts/write-cost-log-section.sh`: `scan-error`, and the `*)` default that
catches **any unrecognised or unset `COST_SCAN_STATE`** and prints the identical sentence. So the
observation establishes that `cost_scan` did not return `ok`, `absent`, `empty`, `no-slug`, or
`no-parser` on the second invocation — and cannot distinguish `scan-error` from a state the caller
did not recognise at all.

Reading `cost_scan` (`scripts/cost-ledger-lib.sh:954-997`), `COST_SCAN_STATE="scan-error"` is set by
one test — the parser's captured stdout does not contain the string `COST_N_LINES` — and **at least
these routes reach it, indistinguishably**:

- the selected parser did not execute (failed to start, was killed, produced nothing);
- the parser executed and exited non-zero on some line, its stderr discarded;
- the parser exited zero but emitted output the caller did not recognise;
- the caller's own recognition step could not run. This is not hypothetical: a comment in the
  harness itself (`tests/guardrails.test.sh:2769-2777`, verified 2026-08-18) records that a `PATH`
  missing `grep`/`sed` makes the library report a parse error rather than falling through to
  `python3` — which is why `new_jq_absent_path()` symlinks every resolvable binary rather than a
  curated list;
- the ledger genuinely held content neither program could parse.

The last of those is a correct degradation. The others are the tooling failing while wearing the
same words. **That collapse is the specifiable defect in this unit.** It is present on every
platform, on every run, today, and it does not require reproducing the macOS failure to observe or to
close.

### 2. The proof problem, harder than the previous unit's

`eviction-cap-not-honoured-under-contention` at least had a scenario that went red 5/5 locally
against a pre-fix script. Here there is nothing:

- **0/150** local iterations diverged, on the platform family where it was seen (Darwin 25.6.0
  arm64, bash 3.2.57), with the case's own fixture rebuilt from scratch each time.
- **1 red in 3 samples** on `c32daf0`, and that one red is the only sighting anywhere. One in three
  is a **ratio of the samples taken**, not a rate — three samples cannot establish a rate.
- The input was identical across the two invocations: the fixture's ledger is written by the case
  with fixed `ts` values, nothing rewrites it between runs, and the script never writes the ledger.

Two consequences the acceptance criteria are shaped by:

- **Nothing can be red-before / green-after for *this sighting*.** Any change presented as fixing the
  macOS failure would be unfalsifiable, in the file this repository already calls its most dangerous,
  on one sample. That was the argument for instrumentation alone, and it was put to the human at
  `OQ1`. **Their decision was to attempt a fix as well** — workable only because §4 supplies a
  *different* route that does have a red before it, and bounded by `PF11` so the fix is never written
  up as an explanation of this red.
- **A green run after this unit means nothing about the fault.** It is one more sample. No criterion
  below is satisfied by colour.

### 3. The test case is implicated, and cannot currently tell the two degradations apart

Reading the case (`tests/guardrails.test.sh:3670-3760`), three things are true today:

- **The script's degraded path exits 0**, so `writelog_exit`'s `0` is consistent with success and
  with every degradation. Exit code carries no signal here, by deliberate design (the script's own
  header) — which means something else has to.
- **`writelog()` discards stderr** (`>/dev/null 2>&1`). Any evidence the script did write, or might
  write in future, is thrown away by the harness before the assertion runs.
- **No case anywhere feeds this script a deliberately unparseable ledger**, and no case asserts that
  the degraded sentence is *absent* from a run over a valid one. Case (b) asserts only that run 2 is
  byte-identical to run 1; run 1's `ok` content is asserted separately, by case (a). So the harness
  detects this class of fault only as a byte-diff or as three unrelated content assertions going red
  — never as "it degraded", and never with the reason attached.

So the harness cannot presently distinguish **degraded correctly** (bad input, right answer) from
**degraded wrongly** (good input, tooling failed). `OQ4` decided this is fixed here: both new cases,
and run 2's body asserted directly rather than only by byte-identity with run 1.

### 4. The one route that has a red before it — the fix in scope

This is the whole of the fix half's evidence base. It is short on purpose: everything in it is
readable in the repository today, and nothing in it is inferred from the CI sighting.

- **The state test's own dependency is inside the thing it tests.** `cost_scan` decides between "the
  parser worked" and "the parse failed" with one line, `scripts/cost-ledger-lib.sh:976`:
  `if ! printf '%s' "$out" | grep -q 'COST_N_LINES'; then COST_SCAN_STATE="scan-error"`. A `grep`
  that is absent, unexecutable, or fails for any reason of its own makes that test report a **parse
  error over input it never examined**. Under `set -o pipefail` a failing `printf` does the same.
- **It is already verified, by this repository, in writing.** `tests/guardrails.test.sh:2770-2775`
  records it as checked on 2026-08-18: a sparser `PATH` missing `grep`/`sed` makes the library report
  a parse error rather than falling through to `python3`, which is why `new_jq_absent_path()`
  symlinks every resolvable binary instead of a curated list. The finding exists; nothing acted on
  it.
- **It reaches the observed state from non-corrupt input**, which is the property that makes it worth
  fixing here rather than filing separately: it is one of the routes §1 shows collapsing into the
  exact sentence the macOS run wrote.
- **It is reproducible, so it has a real red-before-green** — a bounded `PATH` is a deterministic,
  portable forcing condition, on both platforms, unlike anything in §2.
- **A naive fix relocates the failure, and relocates it into a worse shape.** Twelve lines later,
  `cost_scan`'s slug-presence test is the library's *only other* use of `grep`
  (`scripts/cost-ledger-lib.sh:990`): `if ! printf '%s\n' "$COST_SLUGS_PRESENT" | grep -qxF "$slug"`.
  Today `:976` fires first, so `:990` is never reached with `grep` absent. Remove the dependency at
  `:976` only, and `:990` becomes reachable — and its state is `no-slug`, whose message is a
  **positive claim about the ledger's contents** ("the ledger simply has nothing filed under this
  slug") rather than an admission that something could not be read. That is strictly worse than
  today's failure: an honest degradation replaced by a confident wrong answer. `PF13` exists for
  this, and it is the single thing most likely to be missed by a builder reading `:976` alone.
- **Blast radius, established by reading rather than assumed:** `:976` and `:990` are the **only two**
  `grep` invocations in `scripts/cost-ledger-lib.sh`. `cost_slice_rows` and `cost_lookup` perform no
  recognition test of this kind at all — they read whatever the parser returned and set nothing — so
  the defect is confined to `cost_scan`, and neither parser program has to be edited to close it
  (`PF15`, and the residual question in *Open questions*).

## Acceptance criteria

Each is observable and names what would be checked. Four groups, and the grouping is the point:
`PF1`–`PF6` are the **instrumentation**; `PF7`–`PF10` are **what must not be traded** to get it;
`PF11` is the **honesty of the record**; `PF12`–`PF15` are the **fix for the one verified route** of
§4. **None names a cause for the macOS sighting, and none promises that sighting will not recur.**
`PF7` is no longer merely defensive — this unit now edits the parser programs' own neighbourhood, so
it is load-bearing and is checked before anything in the fix group is believed.

- [ ] **PF1 — a degraded read records which parser ran and what happened to it.** When a scan
      degrades, the evidence available names: which parser was selected (`jq` or `python3`), that
      parser's exit status, and a bounded capture of what it wrote to its own stderr. *Checked by:*
      forcing a degradation with a stub parser on `PATH` and reading the three facts back from the
      output; today all three are discarded at `scripts/cost-ledger-lib.sh:971`/`:973`.
- [ ] **PF2 — "parse error" stops being one bucket for several causes.** The routes enumerated in
      §1 above are distinguishable to whoever reads a degraded section or a degraded run: at minimum
      *parser did not execute*, *parser executed and failed*, *parser produced unrecognised output*,
      *the caller's own recognition step could not run*, and *the input was genuinely unparseable*.
      The `*)` fall-through in `build_section_body` no longer prints the same sentence as
      `scan-error` without saying it was an unrecognised state. *Checked by:* one case per route that
      can be forced, each asserting a distinguishable outcome, plus a read of the `*)` arm.
- [ ] **PF3 — a degraded write is visible to whoever ran it, not only in the file.** A degraded
      `## Cost` write says so on stderr, naming the slug and the route; an `ok` write stays silent;
      both still exit 0. *Checked by:* capturing stderr and the exit code on a forced degraded run
      and on the existing mixed fixture — non-empty and `0` for the first, byte-identical-to-today
      and `0` for the second.
- [ ] **PF4 — the harness can tell degraded-correctly from degraded-wrongly.** Two cases exist that
      do not today: one feeds a deliberately unparseable ledger and asserts the section *is* still
      written and says which route it degraded on; one asserts, over the valid mixed fixture, that
      the degraded sentence is *absent* from both runs' output. *Checked by:* both cases, run on
      both platforms.
- [ ] **PF5 — when case (b) goes red, its own output carries the evidence.** The failure surfaces
      the parser identity, exit status and stderr of each invocation, and the body actually written
      by each run — in the harness's own output, on the platform where it failed, without anyone
      re-running anything. *Checked by:* forcing that case red (a stub parser on `PATH` for the
      second invocation) and reading the harness output; today `writelog()` discards stderr and the
      `FAIL` line reports only a diff.
- [ ] **PF6 — the next occurrence is diagnosable from the run's output alone.** A person holding only
      the failing job's log can name which parser ran, what it returned, and which route produced the
      state — with no access to the machine and no re-run. *Checked by:* reading the output of the
      forced red from `PF5` and confirming each of those three questions is answered by text present
      in it. This is the criterion the unit is for; if it cannot be met, that is a finding to record,
      not to route around.
- [ ] **PF7 — the two parser programs still agree.** `_cost_scan_jq_program` and
      `_cost_scan_py_program` stay behaviourally identical: either both change, symmetrically, or
      neither does and the evidence is captured in the shell around them. The existing parity case
      still passes, and a suite run with `jq` genuinely absent (`new_jq_absent_path()`) still
      exercises the real `python3` fallback rather than a parse-error path. *Checked by:* the parity
      case plus that PATH-stripped run; a divergence here is the exact failure class
      `decisions.md` records as `_cost_scan_*` vs `_cost_slice_*`.
- [ ] **PF8 — nothing already guaranteed regresses.** After the change: the section is still replaced
      in place and byte-identical on re-run with no other byte of `log.md` disturbed, `## Budget
      events` included (`DL4`); a section is still written for *every* scan state, so a missing
      section and a cheap unit never look alike (`DL5`); only that unit's `log.md` changes and no
      ledger content appears anywhere under `docs/loop/` (`DL7`/`H1`); the script never creates
      `log.md`; every path still exits 0; coverage is still stated before any total (`CV1`); no
      reassurance token appears (`BG6`); the figures still come from the shared library so `/cost`
      and this section cannot disagree (`CV7`/`CV8`); and both jobs still report an identical
      `total: N passed, M failed` line (`A4`, `docs/loop/checks.md`). *Checked by:* the existing
      cases for each, unmodified, plus the before/after `total:` lines from both platforms.
- [ ] **PF9 — no case is weakened, and the suite's case total does not go down.** Case (b) may be
      *strengthened* (see `OQ4`); it is not relaxed, skipped, quarantined, renumbered, or made
      tolerant of a degraded second write. *Checked by:* the diff against the case list and the
      before/after totals.
- [ ] **PF10 — nothing new ships set, and an unchanged path's output is byte-identical.** No
      threshold, default, or suggested value appears anywhere. Any configurable introduced ships
      **unset** and provably does nothing until a human sets it. Whatever evidence capture is
      always-on is confined to the degraded path and adds no byte to any `ok` path's stdout or
      stderr. *Checked by:* a case asserting an `ok` run's output byte-identical to today's, a case
      asserting zero output and zero behaviour change with any new variable absent, and a grep of the
      diff for new environment names and numeric literals.
- [ ] **PF11 — the fix is never written up as an explanation of the CI sighting.** The unit's record
      states, in these terms: **no cause is assigned for the macOS red**; the fix closes the one
      verified route of §4 and is *not* claimed to be what happened on `c32daf0`; the sample count is
      1 red in 3 samples on `c32daf0` and 0 divergences in 150 local iterations, stated as **samples,
      never as a rate**; a green run after this change is one more sample, not a closure; and **if the
      CI fault recurs, that is a new sighting against an instrumented library, not a regression of
      this unit**. *Checked by:* the wording of `log.md` and `verify.md`. Any sentence of the form
      "this fixes the macOS parse error", or any changelog or commit message implying it, fails this
      criterion outright — and it fails it even if the fault never recurs.
- [ ] **PF12 — the state test no longer reports a parse error over input it never examined.**
      `cost_scan`'s decision between "the parser worked" and "the parse failed" no longer depends on
      an external tool whose own absence or failure is indistinguishable from the condition it
      reports (`scripts/cost-ledger-lib.sh:976`). With a `PATH` that cannot resolve `grep`, a valid
      ledger and a present parser produce the **same result they produce today with `grep` on
      `PATH`**. *Checked by:* the case named in `PF14`, plus a read of the changed line — a fix that
      keeps the dependency and merely reports it differently does not satisfy this.
- [ ] **PF13 — the failure is not relocated to the slug test, and never becomes a confident wrong
      answer.** `cost_scan`'s slug-presence test (`scripts/cost-ledger-lib.sh:990`, the library's only
      other `grep`) is closed in the same change. With `grep` unresolvable, a slug that **is** present
      in the ledger must never be reported as `no-slug` — whose message is a positive claim about the
      ledger's contents, strictly worse than today's honest degradation. *Checked by:* a case running
      the same valid mixed fixture under a `grep`-less `PATH` and asserting the `ok` body, not the "no
      records for this unit" body. **This case must be shown red against a fix that changes `:976`
      alone**, so the relocation is demonstrated rather than merely warned about.
- [ ] **PF14 — the fix has a reproduced red before it, on both platforms.** A case exists that is
      **red against the pre-change library and green against the changed one**, forced by a bounded
      `PATH` rather than by mocking, with the trial count and both library versions recorded. The
      pre-change red is **reproduced and recorded, not asserted**. *Checked by:* running it against
      both versions locally, then reading both jobs' output on a real pushed commit — per this
      repository's standing discipline, the local red/green establishes the mechanism and only the
      real run establishes the guarding checks.
- [ ] **PF15 — the fix does not edit either parser program, or if it must, it edits both.** The
      preferred and expected outcome is that neither `_cost_scan_jq_program` nor
      `_cost_scan_py_program` is touched at all, because §4 places the defect in the shell around
      them. If a builder concludes otherwise, both change symmetrically in the same commit under
      `PF7`, with the reason recorded. *Checked by:* the diff — the two program functions are
      byte-identical to today's, or both changed with a recorded reason; one changed alone fails this
      regardless of the suite's colour.

## Non-goals

Read out loud at G0 and approved unchanged. Each is a direction this could plausibly wander, and
several are directions the two previous units had to be pulled back from. **The first one below was
narrowed by the G0 decision and by nothing else: a fix is now in scope for the one route §4
establishes, and for nothing beyond it.**

- **Not a cause for the macOS sighting, and no fix justified by one.** The fix in scope is `PF12`–
  `PF15`, whose entire justification is readable in the repository today (§4). No slice may name why
  the second invocation on `c32daf0` degraded, no patch may be justified by an unevidenced mechanism,
  and "this probably fixes it" remains out of bounds as a rationale. If the work exposes the CI
  cause, that is a **finding to record and a new unit**, not scope to absorb.
- **Not a retry, fallback, or self-heal around the parser.** Re-invoking the parser on failure,
  falling from `jq` to `python3` on a *failed* run rather than an *absent* binary, or re-running the
  scan before printing would destroy exactly the signal this unit exists to capture, and would turn a
  visible fault into an invisible one. **This survives the fix, and the distinction is one line:**
  `PF12` removes a dependency from the *test that classifies* the parser's result; it does not
  re-run, retry, or substitute for the parser itself, and no builder may read it as licence to do so.
- **Not a widening to every external tool the library reaches for.** The fix closes the two `grep`
  invocations at `:976` and `:990` — the only two in the file. The `tr` at
  `scripts/cost-ledger-lib.sh:310` has the same class of dependency and is **out of bounds here**;
  it is named so it is not discovered as a surprise, not so it is folded in. A separate observation
  is the route for it.
- **Not a change to the parser preference or the dependency posture.** `jq` first, then `python3`,
  then `no-parser`, stays. Neither is made required, neither is vendored, no third parser is added,
  and the bash-3.2-plus-coreutils zero-dependency constraint is not relaxed as a way of closing this.
- **Not a redesign of the cost ledger or its library.** The record shape, the field set, the JSONL
  format, eviction and its order, the `mkdir` dedup, rework bookkeeping, `cost_slice_rows`,
  `cost_lookup`, `cost_list_slugs`, `/cost`'s report, the budget gate, and recovered figures are all
  out of bounds except for exactly what the degraded-read path requires.
- **Not making the degraded path fail.** It still writes a section and still exits 0. A close-step
  tool that can fail a unit over its own bookkeeping is worse than one that says plainly it could
  not write the section — the script's own header settles that and this unit does not reopen it.
- **Not a CI change.** No new job, no matrix change, no retry, no re-run-on-failure, no
  `continue-on-error`, no artifact upload, no scheduled run, no caching, and no change to either
  job's three steps or their identical invocation of the suite. No platform conditional anywhere.
- **Not making red acceptable.** No known-failures list, no quarantine, no advisory step, no moving
  the suite off the guarding checks. `PF9` says this as a criterion because it is the cheapest wrong
  answer available here.
- **Not a claim about macOS.** `macos-latest` is where it was seen once, on a rolling image. Platform
  is not established as the property, the maintainer's host is not a claimed platform
  (`docs/loop/checks.md`), and no slice spends time proving or disproving a platform dialect cause.
- **Not the two queued sibling units.** `stale-evict-lock-permanently-defeats-the-cap` and
  `resumed-invocation-never-reaches-the-ledger` are out of bounds even though they touch these files;
  this unit exists so they can be built on a file whose one unexplained failure is diagnosable, not
  to fold them in.
- **Not a `log.md` format change.** No new headings, no change to `## Budget events`, no second
  writer in the close step, no artifact-size figure (dropped at the backlog gate), and this script
  still never creates `log.md`.
- **Not a performance or refactoring pass on `cost_scan`.** No restructuring for its own sake in the
  file `decisions.md` calls the most dangerous in the repository.
- **No new agent, command, hook, state file, phase, or release gate.** `ship-check.sh` stays at
  exactly three gates.
- **No status badge and no CI-health section.** Still a different intent, as it was for the three
  previous units.
- **Not a spike disguised as a build.** If the residual question in *Open questions* needs reading
  rather than deciding, that reading lands as a `spike-*.md` finding in this directory — the shape
  `harness-fails-only-on-linux/` already established — and touches no other file.
- **Not `resumed-invocation-never-reaches-the-ledger`'s change, begun early.** That unit's `RS10`
  edits both parser programs. This unit does not start it, prepare for it, or leave a partial version
  of it behind; `PF15` expects both programs byte-identical when this lands, precisely so that unit
  rebases onto a known state rather than a half-moved one.

## Failure modes

| When | Expected behaviour |
|---|---|
| The ledger genuinely holds a line neither parser can read | The section is still written, still exits 0, and it is distinguishable that the **input** was at fault (`PF2`) — the one route where today's sentence is already correct |
| The selected parser never executes | Recorded as *parser did not run*, with its exit status, never as an input parse error (`PF1`, `PF2`) |
| The parser exits non-zero and writes to stderr | Its exit status and a bounded capture of its stderr are reported. Never silently discarded (`PF1`) |
| `grep` cannot be resolved and the parser worked (the route verified at `tests/guardrails.test.sh:2770-2775`) | The scan returns exactly what it returns with `grep` present — `ok`, with the real figures. **This is the fixed route** (`PF12`), not a better-labelled failure |
| `grep` cannot be resolved and the input genuinely is unparseable | Still a parse error, still distinguishable as an input fault, still exit 0 (`PF2`) |
| `grep` cannot be resolved and the slug **is** present in the ledger | The `ok` body. Never `no-slug`'s "nothing filed under this slug" — a positive claim about the ledger's contents is worse than an admission of failure (`PF13`) |
| The recognition step fails for a reason other than `grep` (a failing `printf` under `pipefail`, say) | Reads as the **caller's** failure, not as unparseable input (`PF2`) |
| `COST_SCAN_STATE` is unset or holds an unrecognised value | Says so. Today the `*)` arm prints the identical parse-error sentence and the two are indistinguishable (`PF2`) |
| A degraded section is written during a real close step | Whoever ran it is told on stderr, naming the slug and the route; the section is still written and the exit code is still 0 (`PF3`) |
| An `ok` scan | Output byte-identical to today's, on stdout and stderr. Instrumentation is confined to the degraded path (`PF10`) |
| Neither `jq` nor `python3` is present | `no-parser`, with its own distinct message, exit 0 — unchanged |
| `jq` absent, `python3` present | The real `python3` path runs and produces the identical scan result; the parity case still passes (`PF7`) |
| Case (b) goes red again, anywhere | Its output carries parser identity, exit status, stderr, and both bodies, so the next occurrence is diagnosed from the log rather than re-investigated (`PF5`, `PF6`) |
| The fault recurs on CI after this unit | Expected and permitted. This unit does not claim to prevent it; it claims the run will say enough to explain it |
| The fault recurs after this unit ships | A **new sighting against an instrumented library**, not a regression of this unit, and not evidence the fix was wrong. It enters `/observe` as its own intent (`PF11`) |
| The fault never recurs | No claim it was fixed, and no cause backfilled to explain the silence. The unit closed on §4's route plus the instrumentation, and the record says exactly that (`PF11`) |
| A fix lands at `:976` and leaves `:990` | Fails `PF13`. The failure is not closed, it is moved into a worse shape — and the `PF13` case is required to be red against exactly this partial fix |
| The fix appears to also cure the CI sighting | Not claimable on one green run. `PF11` governs the wording; `PF14` governs the evidence |
| A configurable added by this work is left unset | Nothing happens: no output, no behaviour change (`PF10`) |
| Instrumentation or the fix would require changing one parser program only | Not permitted. Both, symmetrically, or neither — the `_cost_scan_*` / `_cost_slice_*` divergence class (`PF7`, `PF15`) |

## Constraints

**Existing behaviour that must not change** (each has a guard today; regressing one is a failure of
`PF8`, not a trade):

- `DL4` — the `## Cost` section is replaced in place, byte-identically on re-run, disturbing no other
  byte of `log.md`. This *is* the failing case; it is strengthened or left alone, never relaxed.
- `DL5` — every scan state still produces a section. A missing section and a cheap unit must never
  look identical.
- `DL7`/`H1` — only the target unit's `log.md` is written; no ledger content ever appears under
  `docs/loop/`; the script never creates `log.md`.
- Always exit 0, on every path, including its own errors.
- `CV1` — coverage stated before any total. `BG6` — no reassurance token, ever.
- `CV7`/`CV8` — every figure comes from `scripts/cost-ledger-lib.sh`, the same source `/cost` reads,
  so the two cannot disagree. No second implementation of any figure.
- `A4` — both jobs run the identical suite file with the identical invocation and no platform
  conditional; their `total:` lines must match exactly, and `docs/loop/checks.md` stays a true map of
  both check sets.

**The file itself.** `scripts/cost-ledger-lib.sh` is described in `docs/loop/decisions.md` as the most
dangerous file in the repository, and the recorded prior failure class is divergence between its
paired parser programs (`_cost_scan_*` vs `_cost_slice_*`). Any change keeps the two scan programs in
agreement. Both halves of this unit are expected to land **entirely in the shell around those calls**
— §4 places the defect there and the instrumentation has no reason to be anywhere else — which is why
`PF15` states the byte-identical outcome as the expectation rather than as a hope. `PF7` is now
load-bearing rather than defensive: this unit edits that neighbourhood.

**Build-order coupling.** `resumed-invocation-never-reaches-the-ledger` is approved and ordered
**after** this unit, because it adds a record class **both** parser programs in
`scripts/cost-ledger-lib.sh` must learn and its `RS10` binds any parser change to land in both.
Recorded here so it is not rediscovered at that unit's `G1`:

- This unit lands first. That unit rebases onto it rather than developing in parallel — per
  `docs/loop/conventions.md`, a lane confirms its base against local `main` on entry, and this is the
  case that rule exists for.
- This unit leaves both parser programs byte-identical (`PF15`), so that unit inherits a known state
  and its own diff stays legible as `RS10`'s change and nothing else.
- `stale-evict-lock-permanently-defeats-the-cap` is also approved and also out of bounds here; it
  touches `scripts/record-cost-event.sh`'s eviction path rather than this neighbourhood.

**Environment.** bash 3.2 and coreutils only; zero dependencies; `jq` and `python3` both optional and
neither assumed; no `flock`. The guarding platforms are `ubuntu-latest` and `macos-latest`;
`macos-latest` is a rolling image whose point version is not a fixed contract. The maintainer's host
is macOS/arm64/bash 3.2 and is **not** a claimed platform.

**Limits on evidence.**

- Only a real run on the guarding platform proves a claim about the guarding checks. A local run, a
  container, or a simulation may **investigate**; none may be cited as proof.
- 0/150 local iterations is not evidence of absence, and 1 red in 3 samples is not a rate. Every
  figure derived from the single sighting is a bound.
- Per `docs/loop/conventions.md`, a green harness proves nothing about behaviour outside the harness.
  A case that forces a degradation with a stub on `PATH` proves the *instrumentation* works; it does
  not prove the macOS fault is understood, and no criterion above reads it that way.
- **The fix's evidence and the sighting's evidence are separate ledgers.** `PF14`'s reproduced red
  establishes the `grep`-dependency route and nothing more. It is not evidence about `c32daf0`, and a
  verdict that cites it as such fails `PF11` — which is a `G2` finding, not a wording preference.

**Already settled, and not reopened here.** From `docs/loop/decisions.md`: `L7` stands; all five
threshold variables stay unset and none ships a default; per-pass rework granularity is dropped;
`S7` and `S11` are closed; transcript scraping is declined permanently; `ship-check` stays at exactly
three gates; the cost doc's success targets are withdrawn, and any future target must name the figure
that computes it. A proposal reaching for one of these owes an explicit argument against the recorded
reasoning, not a fresh start.

## G0 decisions — held 2026-08-19

All seven questions are decided. Recorded with the cost each decision accepts, so none of them is
re-litigated and none of the foreclosed alternatives has to be rediscovered.

- **OQ1 — instrumentation *and* a fix, in one unit. Decided against this document's own
  recommendation.** The human chose to attempt remediation now rather than gate it on a second
  sighting. It is workable only because of §4: the fix targets a route that is **already verified in
  this repository**, reaches the observed state from non-corrupt input, and is reproducible — so it
  has a real red-before-green. It is **not** licence to guess at the macOS cause, and `PF11` is the
  criterion that holds that line.
  **Cost accepted:** the fix's diff and the instrumentation's diff arrive in one unit, which is
  exactly the cost this document recorded against option 3 — at `G2` the two must be legible
  separately or the evidence for one gets read as evidence for the other. Mitigation is structural
  and belongs to `G1`: the fix and the instrumentation are **separate slices with separate tests**,
  and `PF11` plus `PF14` keep their evidence in separate ledgers. This is the weakest joint in the
  amended spec and is named as such rather than smoothed over.
- **OQ2 — always-on, degraded path only.** As recommended. The standing all-five-unset rule governs
  **thresholds, defaults and suggested values**, not diagnostics; a diagnostic that ships unset cannot
  catch a 1-in-3 fault on a machine nobody owns. `PF10`'s "no byte added to any `ok` path" is the
  guard, and it is asserted by a case rather than promised in a comment.
- **OQ3 — both library and harness.** As recommended. `PF1`/`PF2` and `PF5` are independent and
  neither presumes where the fault is.
- **OQ4 — add both new cases and assert run 2's body directly.** As recommended. Strengthening is
  permitted by `PF9`; weakening is not, under any colour.
- **OQ5 — force what a stub parser on `PATH` can force; record the rest as unforced, naming what was
  tried.** As recommended. Note the fix half is **better off than this**: `PF14`'s red is forced by a
  bounded `PATH`, deterministically, on both platforms.
- **OQ6 — one environment line at suite start**, identical in shape on both platforms, and it must not
  change either job's case totals (`A4`).
- **OQ7 — superseded by OQ1.** The question was what closes the unit if the fault never recurs; with a
  fix in scope, **the unit closes on §4's route landing green (`PF12`–`PF15`) plus the instrumentation
  criteria (`PF1`–`PF6`)** — not on the CI fault's absence, which is not a closing condition and never
  becomes one. The point the question existed to protect survives intact: a fault that never recurs
  must not invite a cause backfilled to explain the silence (`PF11`).

## Open questions

One, and it is the **builder's**, not the human's. Nothing here blocks `G1`.

- **R1 — can the fix be made without touching either parser program?** *Expected yes, on evidence, but
  not asserted.* §4 establishes that `:976` and `:990` are the only two `grep` invocations in the
  library and that `cost_slice_rows`/`cost_lookup` perform no recognition test of this kind, which
  places the defect in the shell around the parsers rather than inside either program. Whether the
  marker recognition and the slug-presence test can both be expressed without an external tool, on
  bash 3.2, is a reading task the builder does at the start of the fix slice.
  - **If yes** (expected): both program functions stay byte-identical and `PF15` is satisfied the
    cheap way.
  - **If no:** both programs change symmetrically in the same commit, under `PF7`, with the reason
    recorded — and that outcome deserves a `spike-*.md` note in this directory before the change, not
    after it, because it would put this unit inside the neighbourhood
    `resumed-invocation-never-reaches-the-ledger` also has to edit.

## G0 — held and approved

Approved 2026-08-19 with one substantive change of scope (`OQ1`). What was approved:

1. **The problem framing**, including the reframe from "the macOS parse error" to "one sentence
   covering several unrelated causes, with every piece of evidence discarded" — and the separation of
   that framing from §4's independently verified route.
2. **The non-goals, read out loud and unchanged**, with the first one narrowed by the `OQ1` decision
   and by nothing else. The load-bearing ones: **no cause may be named for the macOS sighting**; **no
   retry, fallback or self-heal may be added around a *failed* parser** (removing a dependency from
   the test that classifies the parser's result is not the same thing, and `PF12` says so); and **no
   case may be weakened** to reach green.

Approval at G0 is approval of the problem and of the scope above. It is not approval of a mechanism,
and the fix half still owes `PF14`'s reproduced red before anything about it is believed. Next step is
`/slice`, and `G1` owes one thing this document cannot do for it: **the fix and the instrumentation as
separate slices**, per `OQ1`'s accepted cost.
