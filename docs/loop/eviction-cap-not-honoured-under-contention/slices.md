# Slices — eviction-cap-not-honoured-under-contention

Cuts `spec.md` (G0 approved) into **three read-only spike slices**, plus a **second G1** for the fix
group that cannot honestly be cut yet.

The G0 decisions this pass is cut against, restated so no slice re-derives them:

| Question | G0 decision (not reopened by any slice here) |
|---|---|
| **OQ1** — hard bound at rest, or eventual convergence? | **HELD for the spike.** The human answers it at the second G1, with this pass's evidence in hand. No slice picks, recommends, or implies an answer. |
| **OQ2** — is a bound at rest achievable without giving up `L7`, and at what cost? | **The spike's** — `S1`. |
| **OQ3** — does the failing case's fixture faithfully model a real appender? | **Folded into the spike at G0** — `S3`. Established by *reading* the fixture and the real write path, never by assuming. |
| **OQ4** — the stale evict lock | **OUT of scope.** Confirmed pre-existing, scoped out twice before. No slice for it, and it is not folded into any spike question — it deserves its own intent. A spike that stumbles on it records the observation in one line and moves on. |
| **OQ5** — can a harsher local scenario go red against today's HEAD? | **The spike's** — `S2`. Load-bearing: it is the one answer that can make `E3` unmeetable. |

**3 slices · all 3 genuinely parallel at t0 · critical path depth 1 (S1 ∥ S2 ∥ S3) → SECOND G1**

No slice in this pass writes code, a test, a workflow, a case, or a file mode. Every one of them
returns evidence, and the whole point of the pass is that the fix — if `OQ1` licenses one — is
designed *after* that evidence exists.

---

## The seam — and why this pass does not have one

The usual first question ("what is the smallest change that delivers observable value?") has no
honest answer here, and saying so is more useful than inventing one. `OQ1` is held, and `OQ1` is the
question of *what the cap even guarantees*. A slice that changed behaviour before that is answered
would be a guess wearing an envelope — and it would land in `append_and_evict()`, the one function
the previous unit's non-goals put out of bounds beyond a recorded decision.

The value this pass delivers is a different kind, and it is real. After it, the project knows:

1. whether a bound **at rest** is achievable at all without giving up `L7`, and what the closing
   work would cost the invocation that pays for it (`S1`) — recorded nowhere today, and
   `spec.md` states it as unestablished in *both* directions;
2. whether the failing case's fixture models a real appender or a harsher world than production
   (`S3`) — which changes what "the cap is broken" means before anyone decides what to do about it;
3. whether `E3`'s red-before observation is constructible on the maintainer's own host against
   today's HEAD, or whether a CI-only proof becomes the human's call (`S2`).

The fix group's seam — if `OQ1` produces one — is named at the second G1, off these three answers.

Deliberately **not** in this pass:

- **Fix slices.** Same precedent, twice over: `cost-ledger-blind-to-background-agents` left the RC
  group uncut behind `S6`'s spike, and `harness-fails-only-on-linux` left its fix group uncut behind
  `S1`–`S4`. An envelope names files, outputs and tests — it *is* a design commitment — so writing
  one now pre-empts the `OQ1` decision G0 explicitly held, and makes the spike ceremonial. See *The
  second G1* below.
- **An `E1` slice** stating the cap's property in the script's header. Which of the three properties
  gets written down **is** `OQ1`'s answer. Cutting it now would put the decision in a builder's
  envelope.
- **A stale-evict-lock slice.** `OQ4` is out by G0 decision. It is not folded in, not silently
  dropped, and not a spike question — one recorded observation if a lane trips over it, nothing more.
- **Any change to `tests/guardrails.test.sh`.** Not the failing case, not its fixture, not a new
  case, not a renumber. The suite stays at **427 cases** and `README.md:167` is untouched by every
  lane in this pass.
- **Anything in `.github/workflows/ci.yml` or `docs/loop/checks.md`.** This pass changes nothing that
  runs anywhere, so the map stays true without being edited.

---

## Order and concurrency

```
t0  ├── S1  OQ2: is a bound at rest achievable without giving up L7,
    │       and what does the closing work cost where it is paid?      (read-only)
    ├── S2  OQ5: can a scenario on the maintainer's host go red
    │       against today's HEAD?  (E3's before-half, or E3 unmet)     (read-only diff)
    └── S3  OQ3: does case (f)'s fixture faithfully model a real
            appender?  Established by reading, not assuming.           (read-only)
             │
             └──→ SECOND G1: OQ1 is answered by the human; the fix group (if any) is cut there
```

- **Genuinely parallel: all three.** Three builders, three worktrees, three distinct output files,
  zero shared files. No lane touches `scripts/`, `tests/`, `.github/`, `README.md`, or another unit's
  artifacts, which is what makes the parallelism structural rather than asserted.
- **`S1` is not a dependency of `S2` or `S3`, and vice versa.** `S1` reads what the code guarantees;
  `S2` runs pressure against the code as it stands; `S3` compares the fixture to the code. None
  needs another's verdict to start, and sequencing them would buy nothing and cost two merges.
- **`S2` and `S3` are separate slices, and this is the pairing to refuse merging.** They are the two
  that *look* mergeable — both are about the failing case — and they are the two whose answers must
  not become one narrative. "No local red is constructible" and "the fixture models a harsher world
  than production" are independent findings that a single lane would be strongly tempted to fuse into
  a single story ("the case is unfaithful, which is why nothing reproduces"). Structural separation
  is cheaper than a review that has to catch that. This is the same reason the previous unit refused
  to merge its `S2` and `S3`.
- **If the human wants two lanes rather than three**, the merge to make is **`S1` + `S3`** — both are
  reads of the same two artifacts (`append_and_evict()` and the fixture) with no experiment between
  them. `S2` stays alone: it is the only lane that runs anything.

### Overlap between lanes, resolved here rather than at integration

| Shared surface | Who owns it | What the other lane does |
|---|---|---|
| The fidelity question (raw `>>` writer vs a real appender) | **`S3`** owns the verdict | `S2` labels each of its scenario arms by *what does the appending* and cites `S3` for whether a raw-writer arm is faithful. It does not answer it. |
| Trial counts and reproduction | **`S2`** owns every count | `S3` may corroborate a read with at most one observation; it reports no trial counts and no rates. |
| `L7`'s exact guarantee | **`S1`** quotes it verbatim and owns what "giving up `L7`" means | `S2` and `S3` cite it; neither restates it in their own words. |
| The cost of an append today (`E8`'s before-half) | **`S1`** | `S2` may report wall clocks for its own scenarios; those are scenario parameters, not `E8`'s baseline. |

---

## Pinned contracts, so no two lanes derive the same thing twice

Decided here, at G1, because discovering any of them at build time costs a rewrite. A builder that
believes one is wrong returns `needs-decision` rather than changing it.

| Contract | Value | Why it is pinned |
|---|---|---|
| Spike output paths | One file per lane, all under `docs/loop/eviction-cap-not-honoured-under-contention/`: `spike-oq2-bound-at-rest.md` (S1), `spike-oq5-local-red.md` (S2), `spike-oq3-fixture-fidelity.md` (S3) | Three lanes appending to one `spike.md` conflict at the same insertion point, every time. Distinct files make the parallelism structural. Consolidation, if wanted, is the second G1's call. |
| Every lane's diff | **Markdown only, exactly one file**: `git diff --name-only main` returns that lane's own path and nothing else | The cheapest possible check that a read-only slice stayed read-only, and what makes `E6` and `E7` trivially true for the whole pass. |
| The suite's case count | **427, unchanged by this pass.** No lane adds, removes, edits, skips, or renumbers a case, so no lane touches `README.md:167`'s `427 cases` literal | The harness's own **last** case asserts `PASS + FAIL + 1` equals that literal, so a lane that "helpfully" added a case would turn the suite red on a case its diff never touched — in a pass whose entire value is not changing behaviour. |
| `OQ1` stays the human's | No lane picks between bound-at-rest and eventual convergence, recommends either, or writes a sentence whose effect is a recommendation. A lane that believes its evidence forces the answer states the evidence and says the decision is the human's | G0 held `OQ1` explicitly. The maintainer's recorded instinct is **input, not a decision** (`intent.md`), and the alternative stays live with its cost attached. |
| What "no fix" means, exactly | A lane may name **which artifact** a resolution would live in, and may characterise **classes** of obligation with their costs. It may not write a patch, a diff, a prototype, a branch, or a sentence beginning "the fix would be" | The line between evidence and design, drawn where the spec draws it. Crossing it re-creates the diagnosis-delivered-as-a-spec failure one phase later. |
| `unknown` as an answer | A **complete and successful** outcome for any lane, recorded with what was tried and what would settle it | `spec.md`'s standing discipline and the previous unit's own contract. A lane that guesses to avoid returning `unknown` is the failure this pass exists to prevent. |
| Investigation vs proof | A container, VM, or otherwise simulated environment may be used to **investigate** and **must be labelled investigation-grade** in the finding. Only a real run on the guarding machines is evidence about them, and `E2` is unreachable by any lane in this pass | `spec.md`'s *proof problem*, `docs/loop/conventions.md`, and 20/20 Docker trials that already settled at cap while CI failed. |
| A local run's scope | A run on the maintainer's host **is** evidence for a claim about the maintainer's host — that is exactly what `OQ5` asks — and is **never** evidence about CI, in either colour | `spec.md`'s failure-mode row: the CI result is authoritative for a claim about the guarding checks, and the local green is not reported as though it were evidence against it. |
| The stale evict lock | **Out of scope (`OQ4`, G0).** One recorded observation line if a lane trips over it, then move on. **A red attributable to a stale lock is not an `OQ5` answer** and is never reported as one | It is a permanent cap violation by a *second* route with the same observable, so a red it produced would look exactly like the one this unit is about — and would license a fix validated against the wrong defect. |
| Platform / shell dialect | **Closed. Not re-tested by any lane.** Refuted twice: `spike-case-a.md` §1's primitive-by-primitive read plus 20/20 Linux trials, and the macOS job failing identically on matching bash and architecture | `spec.md`, *Also foreclosed*: no slice should spend time on it. |
| The repository's own `.claude/` | **Never written to by any lane.** No lane appends to `.claude/loop-cost.jsonl`, creates `.claude/loop-cost-finished/`, or touches `.claude/loop-cost-evict.lock` in this repository. Every experiment runs against a throwaway `CLAUDE_PROJECT_DIR` | The repo's ledger is real recorded data for other units, and a spike that polluted it would corrupt the evidence base of the thing it is investigating. |
| Older script versions | Obtained read-only with `git show <rev>:scripts/record-cost-event.sh > "$TMP/..."`. **No `git checkout`, no branch, no stash, no reset** of the working tree | A lane that moves the working tree can lose another lane's work and can silently change what "today's HEAD" means mid-experiment. |
| New configurables, thresholds, defaults | **None, in any lane.** A lane that thinks it needs one returns `needs-decision` | `E7`, and the standing rule that no threshold, default, or suggested value ships anywhere in this repository. |
| Nobody pushes | No lane pushes, dispatches, re-runs, cancels, or tags anything. The push that produces `E2`'s evidence is the human's, after a fix group (if any) merges | `E2` is unreachable from a builder's seat, and this pass touches nothing about the guarding checks' state. |
| Already-rejected shapes | `decisions.md`'s G2-follow-up rejected an **attempt bound**, an **iteration counter**, and a **no-progress guard**; the second-G1 entry rejected **loosening the assertion**. Those rejections were about `S9`'s shape and do not automatically bind this unit — but a lane that reaches for one owes an explicit argument against the recorded reasoning, in the finding | `spec.md`, *Already rejected*. Re-adding a bound in particular would restore the very convergence gap `S5` removed. |

---

## Slices

### S1 — Establish whether a bound at rest is achievable without giving up L7, and what the closing work costs where it is paid
```
Owner:       loop-build
Context:     scripts/record-cost-event.sh -- the "Bound + oldest-first eviction" header block
             (lines ~85-116, including the L7 sentence "Appenders never contend for that lock
             and never block on it (L7) -- they poll briefly for it to clear, then append
             regardless" and the accepted cost "a ledger that sits slightly over cap for a
             moment"); the L9-precedence sentence at ~line 60-67; append_and_evict()
             (~lines 253-289) in full, including the poll loop, the unconditional `>>`, the
             single `mkdir "$EVICT_LOCK"` attempt, and the four break paths;
             its two real call sites (~line 441, the cap_trip record; ~line 782, the finish
             record); tests/guardrails.test.sh case (g), the L7 regression guard -- its
             assertion string and its hold-time comparison; spec.md's three candidate cap
             properties (E1's 1 / 2 / 3), OQ2 verbatim, E5, E8, E9; docs/loop/decisions.md's
             "G2 follow-up: break the eviction loop on a failed `mv`" and "Second G1" entries;
             spike-case-a.md section 1 (the platform primitives already ruled out).
Constraints: - THE ONLY DELIVERABLE IS OQ2's ANSWER: whether E1's property 2 (at rest -- the
               file is at or under cap once the last append of a run has landed and its
               invocation has returned) can hold at the same time as L7 as documented and as
               guarded. One of: achievable / not achievable / unknown.
             - Quote L7's guarantee VERBATIM from the two places that define it -- the header
               sentence and case (g)'s assertion -- so that "giving up L7" has a fixed meaning
               in the finding rather than a loose one. A paraphrase cannot be checked.
             - Characterise the answer by CLASS OF OBLIGATION, never by a designed mechanism.
               The structural fact spec.md states is that *something* must be obliged to trim
               after the last append; enumerate what could carry that obligation (the appender
               itself before it returns; a lock-loser that retries; a later invocation; the
               run's end; anything else the reading suggests) and for EACH class state: which
               of E1's three properties it would deliver, whether it can coexist with L7 as
               written, and what work it adds to an APPENDING invocation. Naming a class is
               not designing a fix; picking one, sketching one, or prototyping one is.
             - E8's BEFORE-HALF IS THIS LANE'S, and it is why "at what cost" is answerable
               rather than rhetorical: measure what an append costs TODAY on the maintainer's
               host -- wall clock for a single real hook invocation, with the ledger under cap
               and with it over cap -- and record the numbers, the trial count, the host, and
               the sha. No adjective substitutes for a number. The after-half belongs to
               whatever the second G1 cuts, if anything.
             - Every achievability claim carries the observation OR the structural argument
               that would refute it. A claim nobody could disconfirm is not a finding.
             - If the honest answer is that L7 and a bound at rest cannot both hold, SAY THAT
               PLAINLY. spec.md says that is itself an answer, and E1/E9 are where it lands.
               Do not soften it into "the window can be reduced" -- spec.md already records
               that reducing the window is not closing it.
             - Do not re-test the platform or shell-dialect question. Refuted twice; out.
             - `unknown` is a complete answer, recorded with what was tried.
Output:      docs/loop/eviction-cap-not-honoured-under-contention/spike-oq2-bound-at-rest.md
Done when:   That file states: L7's guarantee quoted verbatim from the header and from case
             (g); a verdict on OQ2 -- achievable / not achievable / unknown -- with the
             structural argument behind it and the observation or argument that would refute
             it; a per-class table of obligations, each row carrying which of E1's three
             properties it delivers, its L7 status, and its cost on the appending path; and
             today's measured append cost with trial count, host, sha, and both ledger states,
             labelled as E8's before-half.
Test set:    4 checks. THE PROOF IS A READ PLUS A TIMING MEASUREMENT, NOT A HARNESS CASE, and
             that is stated in the finding rather than disguised: no fixture in this suite can
             answer whether a property is ACHIEVABLE -- it can only exercise the property that
             exists today, which is the thing already known to fail on CI. Selection rule: one
             check per thing the finding could get wrong in a way nobody downstream could
             catch.
               1. L7's guarantee appears verbatim from both defining places -- header and
                  case (g) -- not paraphrased                                          [E5]
               2. the verdict names the observation or structural fact that would refute it
                                                                                      [OQ2]
               3. no obligation class is listed without all three of: which E1 property it
                  delivers, its L7 status, its cost on the appending path            [E1,E8]
               4. the append-cost baseline states trial count, host, sha, and both ledger
                  states measured, in numbers                                          [E8]
             Fails now: spec.md records OQ2 as unestablished in both directions, nothing in
             this repository states whether a bound at rest can coexist with L7, and no
             append-cost figure exists anywhere -- E8 has no baseline to be measured against.
             Passes after: exactly one verdict with its refuter, a complete per-class table,
             and the baseline numbers -- or `unknown` with what was tried.
Do NOT:      - Do not edit scripts/, tests/, .github/, README.md, spec.md, decisions.md,
               docs/loop/checks.md, or any other unit's artifacts. This lane's whole diff is
               one markdown file.
             - Do not write, sketch, prototype, or branch a fix, and do not write a sentence
               beginning "the fix would be". Naming which artifact a resolution would live in
               is the limit.
             - Do not pick between OQ1's two options, recommend either, or phrase the finding
               so that one reads as the only remaining choice. G0 held that decision.
             - Do not answer OQ3 (S3's) or OQ5 (S2's), and do not run pressure trials to try.
             - Do not investigate or fix the stale evict lock (OQ4, out by G0). One recorded
               observation line if you trip over it, then move on.
             - Do not propose a new threshold, default, configurable, or suggested value.
             - Do not write to this repository's own .claude/ -- not the ledger, not the
               finished-marker directory, not the evict lock. Throwaway dir only.
             - Do not re-test platform or shell-dialect causes. Closed twice.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  nothing
```

### S2 — Establish whether a scenario on the maintainer's own host can go red against today's HEAD, or record E3 as unmet with what was tried
```
Owner:       loop-build
Context:     tests/guardrails.test.sh section (f) (~lines 436-465) -- the failing case
             `eviction convergence: a sustained concurrent stream still settles at or under
             cap once it finishes`, its parameters (CONV_CAP=15, CONV_WRITER_LINES=20000, one
             background raw-`>>` writer, one real hook invocation) and its own comment
             explaining why it constructs the pressure it does; scripts/record-cost-event.sh
             at today's HEAD, unmodified; intent.md and harness-fails-only-on-linux/log.md's
             "A1 -- attempted, and FAILED" section -- the 5/5 red against the pre-fix script,
             5/5 green after, and 426 passed / 1 failed identically on both CI jobs at commit
             9f37a5b, run 32112900121; spec.md OQ5 verbatim, E3, E4, and the *proof problem*
             section's asymmetry (constructed local pressure exposed the OLD bug; CI is known
             only to apply MORE pressure than that fixture does); the host record -- macOS
             26.6.1, arm64, GNU bash 3.2.57(1)-release; the S5 commit 68ece94 and the S9
             amendment 22779f8, for obtaining older versions read-only.
Constraints: - THE ONLY DELIVERABLE IS OQ5's ANSWER: can a scenario runnable on the
               maintainer's own host be made to leave the ledger OVER CAP AT REST against
               today's HEAD -- yes with the scenario, or no with what was tried.
             - Everything runs in a throwaway directory with its own CLAUDE_PROJECT_DIR and
               .claude. The script under test is scripts/record-cost-event.sh at its own path,
               UNMODIFIED. Older versions come from `git show <rev>:path` into a temp dir --
               never `git checkout`, never a branch, never a stash.
             - THE SCENARIO LIVES IN THIS LANE'S MARKDOWN AS A RUNNABLE SNIPPET, not as a new
               harness case and not as an edit to an existing one. Turning a found red into a
               committed case is the fix group's work, if the second G1 cuts one.
             - LABEL EVERY ARM BY WHAT DOES THE APPENDING. An arm whose pressure comes from
               raw `>>` writers and an arm whose pressure comes from real hook invocations are
               different claims and are reported separately. Whether a raw-writer arm
               faithfully models a real appender is OQ3 -- S3's question. Cite it; do not
               answer it.
             - A RED ATTRIBUTABLE TO A STALE .claude/loop-cost-evict.lock IS NOT AN OQ5
               ANSWER. Verify the lock directory is absent at the start of every trial and
               state that you did. If a scenario only goes red because an evictor died holding
               the lock, record it in ONE line as the out-of-scope route (OQ4, out by G0) and
               keep looking for a red that is not it.
             - Report counts, never rates: "N/M red against HEAD (<sha>)", per arm, the same
               shape as the existing 5/5 records. One red is one sample and one green is one
               sample (E4).
             - A container or VM may be used to EXPLORE and must be labelled
               investigation-grade -- but OQ5 asks about the maintainer's own host, so a red
               seen only in a container is an investigation note, never the answer, and never
               reported as covering for a local negative.
             - IF NO LOCAL RED CAN BE CONSTRUCTED, THAT IS A COMPLETE ANSWER AND IT MUST BE
               STATED PLAINLY: record E3 as an UNMET CONDITION, name every scenario tried with
               its parameters, its trial count and the pressure dimension it varied, and state
               outright that a CI-only proof then becomes the human's call at the second G1.
               Do not imply it, do not soften it, and do not let E2 be read as covering it.
             - Do not weaken, edit, delete, skip, or renumber any existing case, and do not
               propose doing so.
Output:      docs/loop/eviction-cap-not-honoured-under-contention/spike-oq5-local-red.md
Done when:   That file states: whether a scenario runnable on the maintainer's host goes red
             against today's HEAD, naming the sha; if yes -- the scenario verbatim and
             runnable by a second person, its parameters, its arm labelling, N/M per arm, and
             the confirmation that the evict lock was absent at the start of each trial; if no
             -- E3 recorded as unmet, every scenario tried with parameters and trial counts,
             the dimensions varied and how far, and the statement that a CI-only proof is the
             human's call; and in both cases E4's one-sample discipline applied to every count
             it reports.
Test set:    4 steps, run in this order. THE PROOF IS AN EXPERIMENT AGAINST TWO NAMED SCRIPT
             VERSIONS, NOT A HARNESS CASE: no case in this suite can distinguish "the harness
             cannot construct this pressure locally" from "this pressure does not arise
             locally", which is the entire question. Selection rule: one step per claim the
             answer rests on, ordered so a later step cannot be run without the earlier one's
             number.
               1. reproduce the baseline -- case (f)'s own scenario against HEAD, K trials,
                  green/red recorded -- rather than trusting the 5/5 record            [OQ5]
               2. vary ONE pressure dimension at a time from case (f)'s parameters (cap,
                  writer line count, writer count, concurrent real hook invocations, arrival
                  interleaving, filesystem), N/M per arm -- one-at-a-time is what makes a red
                  attributable to a dimension                                          [OQ5]
               3. for any red found: re-run it with the evict lock verifiably absent at start,
                  AND against the pre-S5 version (`68ece94^`), so the red is placed against
                  version history instead of asserted                              [E3, OQ4]
               4. for a negative answer: state which dimensions were varied and to what
                  extreme -- an unbounded "could not reproduce" is not falsifiable
                                                                              [E3 unmet, E4]
             Fails now: spec.md records OQ5 as asserted in neither direction; nothing in this
             repository states whether a local red against today's HEAD is constructible, and
             E3's before-half has no candidate observation at all.
             Passes after: a named, reproducible local red with per-arm counts and the lock
             ruled out -- or E3 recorded unmet with the dimensions varied and how far.
Do NOT:      - Do not edit tests/guardrails.test.sh -- not the failing case, not its fixture,
               not a new case, not a renumber. The scenario stays in markdown.
             - Do not edit scripts/, .github/, README.md, spec.md, decisions.md,
               docs/loop/checks.md, or any other unit's artifacts. One markdown file.
             - Do not write to this repository's own .claude/loop-cost.jsonl, its
               finished-marker directory, or its evict lock. Throwaway CLAUDE_PROJECT_DIR only.
             - Do not `git checkout`, branch, stash, reset, or otherwise move the working tree.
             - Do not fix, patch, or prototype anything, and do not describe a found scenario
               as "the fix's test".
             - Do not answer OQ2 (S1's) or OQ3 (S3's), and do not pick between OQ1's options.
             - Do not investigate or fix the stale evict lock beyond the one observation line
               this envelope allows (OQ4, out by G0).
             - Do not push, dispatch, re-run, or cancel any CI run, and do not attempt to make
               CI red on purpose to obtain evidence.
             - Do not report a container red as the answer, and do not report a local green as
               evidence about CI in either direction.
Depends on:  nothing
```

### S3 — Establish by reading whether the failing case's fixture faithfully models a real appender
```
Owner:       loop-build
Context:     tests/guardrails.test.sh section (f)'s fixture (~lines 436-465) -- specifically
             its writer, which streams `printf '{"raw":%d}\n' "$n" >> "$LEDGER"` 20000 times
             and never once invokes the hook, and its single real hook invocation;
             scripts/record-cost-event.sh's append_and_evict() (~lines 253-289) -- the poll
             loop (`while [ -d "$EVICT_LOCK" ] && [ "$backoff" -lt 5 ]; do sleep 0.02`), the
             unconditional `>>`, the single `mkdir "$EVICT_LOCK"` attempt and what a loser
             does next (nothing), and the convergence loop's four break paths; the two real
             call sites (~441 and ~782) and what else a real invocation does before it
             appends (the finished-marker mkdir, the open-invocation bookkeeping);
             tests/guardrails.test.sh section (b) (~lines 407-435) as the CONTRAST fixture --
             60 real hook invocations and no raw writer; spec.md OQ3 verbatim, INCLUDING its
             own candidate answer ("a lock-loser's single attempt is a no-op, so a stream of
             losers is behaviourally a stream of raw writes"), and E1's three properties;
             spike-case-a.md section 1's read of the lock-loser path.
Constraints: - THE ONLY DELIVERABLE IS OQ3's ANSWER: does case (f)'s writer faithfully model a
               real appender -- yes / no / unknown -- ESTABLISHED BY READING the fixture and
               the real write path side by side, as spec.md requires outright, never by
               assuming and never by inferring it from whether the case passes.
             - Produce a difference-by-difference comparison. Every behavioural difference
               between the fixture's writer and a real appender is named concretely -- the
               poll-then-append backoff, the single `mkdir` attempt and what a loser leaves
               behind, the finished-marker mkdir, per-invocation process startup and its
               effect on arrival rate, line size, anything else the read turns up -- and each
               is marked HARSHER / GENTLER / IDENTICAL relative to production, with the
               observation that would flip its mark.
             - Every claim about what a real appender does is traced to a line number in
               scripts/record-cost-event.sh. A claim without a line is unfalsifiable.
             - spec.md's OWN candidate answer must be QUOTED and then explicitly corroborated
               or refuted, with the specific reason. It is a hypothesis in the spec, not a
               finding, and handing it back unexamined is not an answer.
             - IF THE FIXTURE MODELS A HARSHER WORLD THAN PRODUCTION, say so plainly and state
               what that does to the MEANING of "the cap is broken" -- and stop there. What
               should therefore happen to the case is the human's at the second G1, with
               spike-case-a.md's recorded cost attached (weakening the assertion discards the
               only warning anyone gets that the property can be violated at all). This lane
               names no verdict on the assertion.
             - AT MOST ONE observation may corroborate the read -- e.g. running a single real
               hook invocation in a throwaway directory and observing what it leaves behind.
               It is labelled as corroboration of a read and is never a substitute for it.
               This lane runs no pressure trials and reports no trial counts or rates; those
               are S2's.
             - `unknown` is a complete answer, recorded with what was tried.
Output:      docs/loop/eviction-cap-not-honoured-under-contention/spike-oq3-fixture-fidelity.md
Done when:   That file states: yes / no / unknown for OQ3; a difference-by-difference table
             between the fixture's writer and a real appender, every row traced to a line
             number and marked harsher / gentler / identical with the observation that would
             flip it; spec.md's own candidate answer quoted and then corroborated or refuted
             with the reason; and, if the fixture is unfaithful, what that does to the meaning
             of the assertion -- with no verdict on what should happen to the case.
Test set:    4 checks. THE PROOF IS A SIDE-BY-SIDE READ WITH LINE CITATIONS, corroborated by
             at most one observation -- NOT A HARNESS CASE: a harness case would exercise the
             fixture, and the question is how the fixture compares to the real path, which no
             fixture can observe about itself. Selection rule: one check per way this finding
             could be wrong while still looking complete.
               1. every claim about a real appender's behaviour cites a line in
                  scripts/record-cost-event.sh                                         [OQ3]
               2. every difference is marked harsher / gentler / identical AND carries the
                  observation that would flip its mark                                 [OQ3]
               3. spec.md's candidate answer is quoted, then corroborated or refuted with a
                  reason -- never restated                                             [OQ3]
               4. the file is greppable for the thing it must not contain: no sentence says
                  what should happen to the case or its assertion         [OQ1 is the human's]
             Fails now: spec.md records OQ3 as unestablished, nothing anywhere in this
             repository compares the fixture's writer to the real appender path, and the
             spec's candidate answer is explicitly flagged as a hypothesis.
             Passes after: one verdict with a complete difference table and the candidate
             answer resolved -- or `unknown` with what was tried.
Do NOT:      - Do not edit tests/guardrails.test.sh, its fixture, or any case, and do not
               propose an edit to either the fixture or the assertion.
             - Do not edit scripts/, .github/, README.md, spec.md, decisions.md,
               docs/loop/checks.md, or any other unit's artifacts. One markdown file.
             - Do not run pressure trials, sustained-stream scenarios, or repeated-trial
               experiments to answer this -- that is S2's lane, and a trial count here is the
               first step to two lanes telling one story.
             - Do not write to this repository's own .claude/ anything. Throwaway dir only.
             - Do not answer OQ2 (S1's) or OQ5 (S2's), and do not pick between OQ1's options.
             - Do not investigate or fix the stale evict lock (OQ4, out by G0) beyond one
               recorded observation line.
             - Do not conclude anything about whether the case should change. That is exactly
               the sentence this lane must not contain.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  nothing
```

---

## Self-audit against the five-point G1 test

Run on my own bench before this reached the gate. Anything with two owners, no nameable test set,
multi-commit scope, an empty `Do NOT`, or a dependency on something later in the list went back.

| Test | S1 | S2 | S3 |
|---|---|---|---|
| **1. One owning agent** | `loop-build`, one lane, one question (`OQ2`) | `loop-build`, one lane, one question (`OQ5`) | `loop-build`, one lane, one question (`OQ3`) |
| **2. One commit's worth** | One markdown file. No "and also" in the title: the append-cost baseline is not a second deliverable, it is the *"at what cost"* half of `OQ2`'s own wording | One markdown file. The scenario is content in that file, not a committed case | One markdown file. The single corroborating observation is part of the read, not a second experiment |
| **3. Independently testable** | 4 named checks, selection rule stated; fails today because `spec.md` records `OQ2` unestablished and no append-cost figure exists anywhere | 4 named steps, ordered, selection rule stated; fails today because `OQ5` is asserted in neither direction and `E3` has no candidate observation | 4 named checks, selection rule stated; fails today because nothing compares the fixture to the real path and the spec's answer is a hypothesis |
| **4. Criteria as observable behaviour** | The output file's own contents are the observable: a verdict, its refuter, a complete table, numbers with a trial count | The observable is a red or its recorded absence, per arm, with counts and the lock ruled out | The observable is a table where every row cites a line and carries a flip condition, and a file that does not contain one named sentence |
| **5. Dependencies explicit** | `nothing` | `nothing` | `nothing` |

**Set sizes: 4, 4, 4.** Inside `test-design`'s healthy-to-large band, and none of the three is
a re-slice conversation. Each set is checks-on-one-finding rather than branches of one behaviour,
which is what a spike's set looks like when it is honest — `test-design`'s warning about eleven
tests meaning two slices is what kept `OQ3` out of `S2`, where it would have been arm-labelling plus
a fidelity verdict plus a trial regime in one envelope.

**Three lanes and not one.** A single "go read and probe everything" lane would have two *and also*s
in its title, would fail the one-commit test, and — worse — would let one lane's `unknown` take the
other two answers down with it. `unknown` is a legitimate outcome for all three here, and the whole
point of separate files is that it stays a legitimate outcome for one of them.

---

## The second G1 — the fix group, left uncut on purpose

**Not cut here.** `OQ1` is the decision this unit cannot proceed without, and G0 **held it for the
spike**. A slice envelope names files, outputs and tests — it *is* a design commitment — so writing
one now would commit the repository to a resolution the human has not chosen, against a mechanism
`spec.md` says is unestablished in both directions. That is the precedent
`cost-ledger-blind-to-background-agents` set when it left the RC group uncut behind `S6`'s spike, and
that `harness-fails-only-on-linux` set again when it left its fix group uncut behind `S1`–`S4`. It
applies here without modification.

Three separate things block the cut, and each is a different lane's answer plus a human decision:

1. **Whether there is a fix to make at all** — `OQ1`. "Bound at rest" produces a change in
   `append_and_evict()`; "eventual convergence" produces a change to what the repository *states*
   and to what the case asserts. Those are different slices in different files with different tests,
   and nothing in between.
2. **Whether the chosen answer is even buildable** — `S1`. If a bound at rest cannot coexist with
   `L7`, then `E5`'s second branch opens (`L7` deliberately revised, with its header note, its
   `L9` precedence, its regression guard and a `decisions.md` entry all updated in the same change)
   and the fix group's shape changes completely.
3. **Whether the change can be falsified before it is believed** — `S2`. `E3` wants red-before /
   green-after. If no local red exists against today's HEAD, `E3` is recorded unmet and whether a
   CI-only proof is acceptable is the human's call — not something a builder discovers on its third
   refine pass.

What is already known about the shape of that second cut, so the human sees what they are deferring
rather than a blank:

- **`E1` is its own slice, and it is probably the seam** — whichever way `OQ1` goes, the property
  gets written down where a reader of the ledger's mechanism finds it, and the phrase "hard cap"
  stops appearing without saying at what moment it holds. It is the one slice that exists under
  *both* `OQ1` answers.
- **`E9`'s `decisions.md` entry lands in the same pass**, naming what was foreclosed and what was
  considered and not taken — including, if it comes up, an explicit argument against the recorded
  rejections of an attempt bound, an iteration counter, and a no-progress guard.
- **`E8`'s after-half belongs to whichever slice changes the appending path**, measured against
  `S1`'s baseline, in the same commit. A slice that changes what an append does and does not
  re-measure has not met `E8`.
- **Expect the fix group to be largely sequential, not parallel.** Any slice that changes the case
  count touches `README.md:167`'s `427 cases` literal, and the harness's own last case asserts that
  literal equals the live tally — so two such lanes in flight conflict at the same number every
  time, and the loser's merge leaves the suite red on a case its diff never touched. Pin the
  per-slice deltas at the second G1, as the previous unit's second pass did.
- **New cases go before the final `docs (case count)` case**, which stays last in the file. Its
  `PASS + FAIL + 1` arithmetic is only the grand total if it runs last; its own comment says so.
- **Any fix slice that reaches for `continue-on-error`, a known-failures list, quarantining the
  case, de-blocking the step, or skipping a case on a platform returns `needs-decision`.** Out of
  bounds by non-goal, and it stays out of bounds even when it is the fastest route to green.
- **A stale-lock slice is still not on the table** unless `OQ4` is reopened deliberately, with its
  own intent. The second G2 named it as a gap that *compounds* with this one; compounding is a
  reason to record it, not a licence to fold it in.
- **`E2` is not a builder's slice in any pass.** It needs a real run on a real pushed commit, so it
  is the human's, after the group merges. See the traceability table.

---

## Cross-unit collisions

- **`docs/loop/recovered-figure-drops-slice-and-model/`** — specced at G0, not cut. When it is cut it
  will touch `scripts/cost-ledger-lib.sh`, `scripts/cost-report.sh`, `tests/guardrails.test.sh` and
  `README.md`'s case-count literal.
- **`docs/loop/transcript-scraping-as-a-recovery-path/`** — `intent.md` only; captured, not specced.

**This pass: zero collision.** No spike lane touches `scripts/`, `tests/`, `README.md`, or either
unit's files. **At the second G1, name it again:** if `OQ1` produces a change in
`append_and_evict()` plus a harness case, this unit and `recovered-figure-drops-slice-and-model`
share the harness and the `README.md:167` literal. Land one unit's harness-touching slices before
starting the other's.

---

## Criterion traceability — assigned, human-owned, or explicitly not yet assignable

Nothing is dropped, and nothing is claimed as assigned that is not.

| Criterion | Where it stands after this pass |
|---|---|
| **E1** — the cap's property written down, at the moment it holds | **Not yet assignable, and deliberately so.** *Which* of the three properties gets stated **is** `OQ1`'s answer, held by G0 for the human. `S1` supplies what the statement has to be honest about (whether property 2 is achievable with `L7` at all); the statement itself is its own slice at the second G1. |
| **E2** — the case green on both guarding platforms, on a real pushed commit | **The human's, post-merge.** Not assignable to any builder in any pass: no container or local run substitutes, and a builder does not push. A fix group makes it *reachable*; only the human's push makes it *true*. |
| **E3** — the change falsified before it is believed | **Split, and both halves are named.** The *before-half* — whether a red is constructible at all against today's HEAD — is **`S2`**, and `S2` is also the lane licensed to record `E3` as **unmet** with what was tried. The *after-half* (green against the changed script) belongs to whatever the second G1 cuts. If `S2` returns no local red, whether a CI-only proof is acceptable is the **human's** decision, stated rather than implied. |
| **E4** — no green run read as a rate | **Cross-cutting, and structurally live this pass:** `S2` reports counts per arm with the version each ran against, never a rate, and `S1`'s baseline states its trial count. The discipline then binds whatever the second G1 cuts. |
| **E5** — `L7` not traded silently | **Evidence: `S1`**, which fixes what `L7`'s guarantee *is* by quoting it verbatim from the header and case (g), and states per obligation class whether it survives. The **trade itself, if any, is the human's** at the second G1, and the four-part update (header note, `L9` precedence, regression guard, `decisions.md`) belongs to the slice that makes it. |
| **E6** — nothing already guaranteed regresses | **Structurally satisfied this pass**, and that is the whole benefit of a markdown-only diff: every lane's diff is one markdown file, so `L5`, `L6`, `L7`, `L9`, `H3`, `H5`, the non-numeric-cap fallback, and the 427-case total cannot move. **Per-slice gate:** each lane returns `bash tests/guardrails.test.sh` green and `shellcheck -S warning scripts/*.sh` clean, plus `git diff --name-only main` showing exactly its own file. |
| **E7** — no new threshold, default, or suggested value | **Vacuous this pass, and said so rather than left looking unmet:** no lane introduces a configurable, and a lane that thinks it needs one returns `needs-decision` (pinned contract). If a recorded decision later produces one, `E7` belongs to that slice, with the zero-output-when-unset case it demands. |
| **E8** — the closing mechanism's cost measured where it is paid | **Split, and both halves are named.** The *before-half* — what an append costs today, with numbers, trial count, host and sha — is **`S1`**. The *after-half* belongs to whichever slice changes the appending path, measured against that baseline in the same commit. Neither half is the other. |
| **E9** — the `L7` answer recorded so it is not re-litigated | **The human's decision, then a slice at the second G1.** `S1` supplies the foreclosed alternatives (the obligation classes ruled out and why); the `decisions.md` entry is written once `OQ1` and `OQ2` have answers. Not assignable now: an entry naming what was foreclosed cannot be written before anything is. |
| **OQ1** | **The human's, at the second G1.** No lane answers it; the pinned contract forbids even a phrasing that reads as a recommendation. |
| **OQ2** | **`S1`** — evidence only, verdict recorded, no mechanism chosen. |
| **OQ3** | **`S3`** — evidence only, established by reading. If the answer is "not faithful", what the case should assert goes to the human alongside `OQ1`. |
| **OQ4** (the stale evict lock) | **Out of scope by G0 decision.** No slice, and not folded into any spike question. A lane that trips over it records one observation line. Reopening it needs its own intent. |
| **OQ5** | **`S2`** — and it is the criterion-breaking one: its answer decides whether `E3` is meetable locally at all. |

---

## Riskiest slice: **S2**

**Not `S1`**, and the distinction matters. `S1` has the highest *uncertainty* — `spec.md` records
`OQ2` as unestablished in both directions and the answer is genuinely unknown — but its risk is
contained by the form of its output: it is an argument, in text, that the human reads and can push
back on, and its worst outcome lands back at a human gate with the other two answers intact.
Uncertainty that has been deliberately contained is not the risk to nominate.

**`S2` is the riskiest because it is the only lane that can produce a positive result that is
wrong.** `S1` and `S3` return reads; a bad read is visible as a bad argument. `S2` returns a red, and
a red is *persuasive*. Two specific ways it can be the wrong red, and nothing in this repository can
tell them apart from the right one:

1. **A stale evict lock.** An evictor killed mid-loop never reaches its `rmdir`, and every later
   appender then polls, gives up, appends, and never evicts — a permanent cap violation with **the
   exact same observable** as the hole this unit is about. `S2` will be running many trials, some of
   which it will bound or interrupt, so it is precisely the lane most likely to *create* that state
   and then measure it. A red sourced there gets carried to the second G1 as `E3`'s before-half, a
   fix gets built and validated against it, the suite goes green — and CI stays red, because the
   defect the fix closed was never the one CI hit. The mitigation is the one line in `S2` requiring
   the lock's absence to be verified and stated per trial, and it is the line worth reading twice at
   this gate.
2. **An unfaithful arm.** If the fixture's raw-`>>` writer models a harsher world than production
   (`OQ3`, and `S3`'s to answer, not `S2`'s), then a red produced by making that writer *harsher
   still* may be a red against a world no appender lives in. `S2` is required to label arms by what
   does the appending, and to cite `S3` rather than rule on it, exactly so the second G1 can read the
   two findings against each other instead of inheriting a fused one.

And the negative answer carries its own, quieter risk: `S2` is the lane whose "no" makes `E3`
unmeetable. A lane that softens that into "not reproduced yet, but CI shows it" hands the human a
criterion that reads satisfiable when it is not — which is why the envelope requires the words
*unmet condition*, the list of dimensions varied, and the explicit statement that a CI-only proof is
the human's call.

**Runner-up: `S3`**, for the fused-narrative failure. Its answer is the one most likely to be
*reported as a conclusion about the case* — "the fixture is unfaithful" sits one sentence away from
"so the assertion should change", and that sentence is `OQ1`'s answer 2 arriving from a builder
instead of a human, after which the suite can be made green and nothing anywhere is left that could
fail. `spike-case-a.md` already recorded the cost of that trade; `S3`'s `Do NOT` names the sentence
explicitly for exactly this reason.

Not nominated, and worth saying why: **`S1`** is the lane whose evidence the human's decision most
depends on, and it is still not the riskiest — because it cannot manufacture a false positive. Its
failure mode is an argument someone can disagree with at the gate.

---

# G1 — Slices — eviction-cap-not-honoured-under-contention

```
Slices: 3  ·  Parallel: 3  ·  Critical path: S1 ∥ S2 ∥ S3 → SECOND G1 (OQ1 is yours)
Riskiest: S2 — it is the only lane that can return a positive result that is wrong: a red
          sourced from a stale evict lock (out of scope, same observable) or from an
          unfaithful arm would be persuasive, would become E3's before-half, and would get
          a fix validated against the wrong defect.

S1 · OQ2: is a bound at rest achievable without giving up L7, and what does an append cost
     today (E8's baseline)                                            · depends on nothing
S2 · OQ5: can a scenario on this host go red against today's HEAD — E3's before-half, or
     E3 recorded unmet with what was tried                            · depends on nothing
S3 · OQ3: does case (f)'s fixture model a real appender, established by reading
                                                                      · depends on nothing

Fix group: NOT CUT. OQ1 is held for the spike, so an envelope now would commit the repo to a
           resolution you have not chosen. E1, E9, E8's after-half and E3's after-half are
           cut at the second G1, off these three answers.

1. Approve — brief S1, S2, S3 as three parallel lanes  (recommended)
2. Re-slice — say which, and why
3. Spec is wrong — back to loop-spec
```

---
---

# Second G1 — the fix group, cut 2026-08-18

Everything above stands. This section **extends** it: the first pass's *Pinned contracts* table
stays in force verbatim for the surfaces it covers, S-numbering continues at **S4**, and nothing
here contradicts an earlier line. Where a first-pass statement was written for a markdown-only pass
and no longer applies to a code-touching one (the `427 cases` pin, "no lane touches `scripts/`"),
this section says so explicitly rather than quietly overriding it.

**4 slices · parallel set: EMPTY (and that is a finding, not an omission) · critical path
S4 → S5 → S6 → S7**

## The decision this pass is cut against

`docs/loop/decisions.md`'s newest entry — *"Second G1: the ledger promises convergence, and a later
invocation is obliged to trim (2026-08-18)"* — is the input, restated so no slice re-derives it and
no slice reopens it:

| # | Decided | Consequence for this cut |
|---|---|---|
| 1 | The cap promises **`E1`'s property 3 — eventual convergence — stated explicitly**, where today it is only *implied* by the header's accepted-cost sentence ("a ledger that sits slightly over cap for a moment", `scripts/record-cost-event.sh:97-98`) | **S4**, and it is the seam |
| 2 | Obligation **class 3** — a later invocation checks and trims **on arrival, unconditionally, regardless of what its own append needs** | **S5** |
| 3 | Case (f)'s assertion is **replaced** with `S2`'s deterministic lock-hold construction — not deleted, not weakened | **S5**, in the same commit as the behaviour it proves |

**The load-bearing reason class 3 was chosen, restated because it is also this cut's guardrail:**
`S1` rated class 3 the only obligation class that is **fully `L7`-compatible at zero cost to any
appending invocation** (`spike-oq2-bound-at-rest.md` §3, row 3: *"Fully compatible — it changes
nothing about any appending invocation's own path"*). So a cut that puts new work on an appending
invocation's own path has drifted off the decision, and every slice below is written to make that
drift visible rather than possible. A builder that concludes it needs to touch the appending path
returns **`needs-decision`**.

`OQ1`, `OQ2`, `OQ3` and `OQ5` are **answered and closed**. No slice reopens any of them. `OQ4` (the
stale evict lock) remains **out of scope**, exactly as in the first pass: no slice, not folded in,
one recorded observation line if a lane trips over it.

### The three things that blocked the first cut, and where each now stands

The first pass named three blockers. All three are discharged, which is why the group is cuttable now
and was not then:

1. **Whether there is a fix to make at all** (`OQ1`) → answered: property 3 stated, class 3
   obliged. Both halves produce work, so the group has both a documentation slice and a behaviour
   slice, not one or the other.
2. **Whether the chosen answer is buildable** (`S1`) → answered: property 2 is **not achievable**
   alongside `L7`, and class 3 is achievable at zero appending-path cost. `E5`'s second branch
   (revising `L7`) therefore never opens — **`L7` is not amended by any slice here**, and that was
   explicitly foreclosed at this gate.
3. **Whether the change can be falsified before it is believed** (`S2`) → answered: **yes**, 5/5 red
   against HEAD `d24e2ce` and 5/5 against pre-`S5`, with a 0/5 sub-budget control. `E3` is meetable,
   and `S5` inherits the obligation to reproduce its own red rather than cite `S2`'s.

---

## The seam

**S4 — say what the cap promises.** It is the smallest change that delivers observable value, it is
the one thing `spec.md` puts deliberately first (*"until the property is stated, none of the others
can be checked against anything"*), and — unlike a refactor-first opening — a reader of the ledger's
mechanism is better off the moment it lands, with or without S5.

It is also honestly *only* documentation, and the ordering is chosen so that it is not documentation
ahead of code: **property 3 is already true today.** Today a ledger left over cap converges when the
next *appending* invocation runs; S4 writes that down, with the moment it holds at and the limit
`L7` puts on it. S5 then tightens *which* later invocation discharges it — any arrival, not only an
appending one — and amends the mechanism sentence in the same commit. So no slice ever leaves the
header describing behaviour the script does not have.

The alternative order (S5 first, S4 second) was considered and not taken: it would leave one commit
in which the code converges on arrival while the only written statement of the cap remains the
implied one that started this whole unit.

---

## Order and concurrency

```
S4  state the property (E1)                     README, script header, +1 case
 └─→ S5  oblige an arrival that appends nothing to trim (class 3, E3, E5, E6)
     │       script, case (f) REPLACED, +3 cases        ← riskiest
     └─→ S6  measure the cost where it is now paid (E8's after-half)   markdown only
         └─→ S7  record what this fix foreclosed, with the number (E9) decisions.md
```

**Parallel set: empty.** Not a missed lane — four independent reasons, each of which alone forces a
sequence:

- **S4 → S5** is textual twice over: both edit the same header block
  (`scripts/record-cost-event.sh:85-116`) and both add cases to `tests/guardrails.test.sh`, so both
  move `README.md`'s case-count literal. Two lanes moving that one number conflict *by
  construction*, and the loser's merge leaves the suite red on a case its diff never touched.
- **S5 → S6** is logical: `E8`'s after-half measures the changed script. There is nothing to measure
  before S5.
- **S6 → S7** is logical: S7's entry carries S6's number. A decisions entry that says "the cost is
  small" instead of a figure is exactly the adjective this repository's `E8` refuses.
- The whole group shares `tests/guardrails.test.sh` with a **concurrently building neighbour unit** —
  see *Cross-unit landing order* below.

Stating an empty parallel set plainly is the finding: this group is four sequential merges, and any
plan that promises otherwise is promising a rebase.

---

## Case-count deltas — pinned as DELTAS, never as absolute literals

⚠ **`recovered-figure-drops-slice-and-model` is building concurrently and its six slices move
`README.md:167` from 427 through to 460. Its S1 is in flight at this gate.** The absolute case count
at the moment any slice below builds is therefore **not knowable here**, and a pinned absolute would
be wrong the moment the neighbour merges — turning the harness's own last case red on a diff this
lane never touched.

| Slice | Case-count delta | What produces it |
|---|---|---|
| **S4** | **+1** | one conjoined docs case over the flattened header + README ledger paragraph |
| **S5** | **+3** | case (f) **replaced** in place (net 0) + three new cases (arrival trims on a Bash-shaped event; arrival while the lock is held does nothing and does not wait; arrival at/under cap is a no-op) |
| **S6** | **0** | markdown only |
| **S7** | **0** | markdown only |
| **group** | **+4** | |

**Build-time computation rule, binding on every lane:**

1. Merge local `main` in first (`docs/loop/conventions.md`, *Confirm a lane's base*).
2. Read the live literal from `main`, never from this document:
   `sed -n '/^## Development/,/^## /p' README.md | grep -oE '[0-9]+ cases'`.
3. Write `that number + this slice's delta` back into the same line. Nothing else in
   `README.md`'s `## Development` block changes.
4. The arbiter is the harness's own **last** case, `docs (case count)`
   (`tests/guardrails.test.sh:4017`), whose `PASS + FAIL + 1` must equal the new literal. Green
   there is the proof; this table is only a forecast.
5. **New cases go before that last case**, which stays last in the file — its arithmetic is the
   grand total only if it runs last, as its own comment says.
6. A lane whose **honest delta differs** from the table (a conjoined case split in two, a case that
   fires inside a loop) states the real delta in its return and computes the literal from it. The
   table is not a licence to write the wrong number.

---

## Pinned contracts for the fix group

Extends the first pass's table; a builder that believes one is wrong returns `needs-decision` rather
than changing it.

| Contract | Value | Why it is pinned |
|---|---|---|
| One trim loop, not two | The arrival trim and the append-path trim share **exactly one** implementation inside `record-cost-event.sh` — the existing loop at `:274-284`, factored out of `append_and_evict()` and called from both. A second copy is a defect, not a style choice | Two copies of a rule can only *promise* agreement; one shared program makes it structural. This repository's own precedent, twice: `cost-ledger-lib.sh`'s header and `check-script-modes.sh`'s G0 entry in `decisions.md` |
| Where the obligation lives | Only on arrival paths **this invocation ends without appending**: the `Bash` rework branch (`:537-540`) when no `cap_trip` was emitted, and the deduped duplicate-finish discard (`:762-784`, its `exit 0` at `:779`) | This is class 3 as decided, and it is the placement that keeps the appending path untouched |
| Where it must **not** live | Not on the appending paths (`:441`, `:782`); not before `append_and_evict()`; not in `record-recovered-cost.sh` (a deliberate, human-typed CLI with its own independent copy, out of scope); not on the two early exits `SubagentStop` (`:528`) and the unmatched-event `*)` (`:529`) — neither is registered in `hooks.json`, so a filesystem read there buys nothing and only widens the diff | The first is the decision's own guardrail; the rest are scope control |
| One trim per invocation, ever | No invocation performs both an arrival trim and an append-path trim. **Checked by reading the diff at G2, not by a case** — a case asserting it could not fail, since a double trim and a single trim leave the same file | Naming the unfalsifiable check as unfalsifiable, rather than shipping a test that cannot go red |
| The arrival trim never waits | One `mkdir "$EVICT_LOCK"` attempt, no poll loop, no retry, no `sleep`. Lock lost → return 0 and let the holder finish | `L6` (cost accounting never blocks or delays) and `L7`'s spirit. The arrival path fires on the frequent `PostToolUse`/`Bash` registration; a wait there would delay a real tool return |
| No bound, counter, or no-progress guard | The trim loop keeps its `while :;` shape and its I/O breaks, including `S9`'s `mv` break. Re-adding an attempt cap restores the very convergence gap `S5` removed | `decisions.md`'s G2-follow-up entry, and `spec.md`'s *Already rejected* |
| `L7` is not amended | Its header sentence (`:95-98`), its documented precedence over `L9` (`:62-67`), and case (g) (`tests/guardrails.test.sh:467-486`) are all untouched and green. `E5`'s second branch never opens | Explicitly foreclosed at this gate; questioning `L7` is its own unit at G0 |
| Replaced ≠ weakened, and the difference is spelled out | Case (f) keeps its letter, its position and its section. Its **assertion and construction change**. A *weakened* case asserts less than before or can no longer fail; this one asserts **strictly more** (the hole is constructed, the file is observed over cap at rest, *then* observed converged) and is red 5/5 against the pre-change script where the old one was 0/N locally across 8 arms | `spec.md`'s non-goal — *no case weakened, deleted, skipped, or renumbered* — needs a stated distinction, or a builder will read "replace" as licence to relax |
| What the old construction guarded, and where that cover now lives | The dropped raw-`>>`-writer arm's pressure (a sustained stream landing throughout the winner's own loop) stays guarded by case (a) (80 sequential events, cap 50, newest-in-order) and case (b) (60 **concurrent real** hook invocations settle at or under cap, never empty, every line parseable). Neither is modified | "Nothing is lost" is a claim that has to name where the cover moved, or it is a hope |
| `E1`'s "hard cap" scope | E1's grep condition covers the **ledger line cap** only, in `scripts/record-cost-event.sh` and `README.md`'s ledger paragraph. The **budget gate's** unrelated "hard cap" (`commands/loop.md:63`, `scripts/check-budget-gate.sh:404`, and the harness's own grep filter at `tests/guardrails.test.sh:2228`) is a different mechanism and is **out of bounds** | A lane that greps the repo for `hard cap` and "fixes every hit" edits a different feature and turns case `:2228` red |
| Header greps are done flattened | Any case asserting header or README wording flattens first (`tr '\n' ' '`, the `CHECKSMD_FLAT` technique already in this suite) before grepping | The header wraps at ~76 columns; a single-line grep for a sentence that spans three lines fails for the wrong reason |
| New configurables | **None.** No env var, threshold, default, or suggested value, anywhere. A lane that thinks it needs one returns `needs-decision` | `E7`, and the standing repository rule |
| The repository's own `.claude/` | Never written to. Every measurement and every trial runs against a throwaway `CLAUDE_PROJECT_DIR` | The real ledger is other units' evidence |
| Older script versions | Read-only via `git show <rev>:scripts/record-cost-event.sh > "$TMP/..."`. No `checkout`, no branch, no stash, no reset | Carried forward from the first pass |
| Counts, never rates | Every trial figure is `N/M`, one trial = one sample. No percentages, no "usually", no "intermittent" | `E4`, and it binds S5, S6 and S7 |
| Nobody pushes | No lane pushes, dispatches, re-runs, cancels or tags. `E2` is the human's, after the group merges | Carried forward from the first pass |
| First-pass pins that this pass **supersedes**, named rather than silently dropped | The `427 cases` pin and "no lane touches `scripts/`, `tests/`, `README.md`" were pins **for the markdown-only spike pass**. This pass touches all three, under the delta rule above. Everything else in the first table stands unchanged | A superseded pin has to be named as superseded, or the document contradicts itself |

---

## Slices

### S4 — State what the cap promises, and the moment it holds at
```
Owner:       loop-build
Context:     scripts/record-cost-event.sh -- the "Bound + oldest-first eviction" header block
             (:85-116). Specifically :88-90 ("Every invocation that appends a line then checks
             whether the ledger is over cap and, if so, evicts the oldest lines itself"), the
             L7 sentence at :95-98 with its accepted cost ("a ledger that sits slightly over
             cap for a moment"), and the convergence-loop note at :105-112.
             README.md's cost-ledger paragraph (:92) -- "Bound it with
             LARAVEL_LOOP_COST_MAX_LINES (default 5,000; oldest lines evicted first)", a bound
             stated with no moment attached.
             spec.md E1 and its three candidate properties (:44-60); decisions.md's newest
             entry (this gate's decision, all three parts);
             spike-oq2-bound-at-rest.md SS1-SS3 -- L7 quoted verbatim, the not-achievable
             verdict, and the per-class table whose row 3 is the chosen obligation.
             tests/guardrails.test.sh :3029-3050 (the existing README/script ledger docs case,
             `readme_ledger_check`) as the shape and the neighbourhood for the new case; the
             CHECKSMD_FLAT flatten-then-grep technique used by the docs/loop/checks.md cases;
             tests/guardrails.test.sh:4017 (`docs (case count)`), which must stay last.
Constraints: - STATE PROPERTY 3, IN THOSE TERMS: the ledger is at or under cap once a later
               invocation has arrived and discharged the trim; it may sit over cap until then;
               and with L7 as written that is the strongest property available -- a bound AT
               REST is NOT achievable, per spike-oq2-bound-at-rest.md SS2. All three parts, in
               the header block where a reader of the mechanism already goes.
             - The property statement must name the MOMENT it holds at. "Converges" on its own
               is what the file already implies and is what let a case and a codebase disagree
               about one word for two releases.
             - README's ledger paragraph gets the same moment, in one clause. It currently
               promises a bound with no moment, to a reader who never opens the script.
             - E1's grep condition is scoped to the LEDGER LINE CAP. Do not touch the budget
               gate's unrelated "hard cap" wording (commands/loop.md:63,
               scripts/check-budget-gate.sh:404) or the harness grep filter at :2228.
             - Documentation only: not one line of behaviour changes in this slice. `git diff
               main -- scripts/` shows comment lines only.
             - Do not describe the arrival obligation as existing yet -- S5 builds it and
               amends :88-90 itself. Property 3 as stated here is true of today's script.
             - Case count: +1. Compute README's literal from `main` at build time per the rule
               above; never from a number written in this document.
             - shellcheck -S warning scripts/*.sh stays clean; bash 3.2 only.
Output:      scripts/record-cost-event.sh (header comment), README.md (ledger paragraph +
             the `## Development` case-count literal), tests/guardrails.test.sh (+1 case).
Done when:   A reader of the eviction header learns which property the cap guarantees, at what
             moment it holds, and that a bound at rest is not achievable while L7 stands; a
             reader of README learns the same moment in one clause; and a case asserts it.
Test set:    1 case. Selection rule: ONE CONJOINED CASE with labelled tokens over the
             flattened header and the flattened README paragraph -- this suite's own house
             shape (case 6 of the checks.md group, `readme_ledger_check`), chosen because two
             separate cases would let one surface drift while the other stayed green, and a
             labelled token still names which half broke. Four tokens:
               1. property     -- the header names eventual convergence as the guarantee   [E1]
               2. moment       -- it names the moment it holds at (a later invocation
                                  having arrived), not merely that it converges            [E1]
               3. l7-limit     -- it states that a bound at rest is not achievable while L7
                                  holds, so the limit ships with the promise            [E1,E5]
               4. readme-moment-- README's ledger paragraph carries the same moment         [E1]
             Fails now: none of the four strings exists. The header states the accepted cost
             ("slightly over cap for a moment") and the loop's own convergence, and never the
             ledger's promise or its moment; README states a bound with no moment at all.
             Falsify it, do not assume: run the new case against the pre-change files
             (`git stash push -- scripts/ README.md`, or grep the pre-change text out with
             `git show HEAD:`) and record RED in the return before making it green.
             Passes after: all four tokens present, and `docs (case count)` green on the
             recomputed literal.
Do NOT:      - Do not change any behaviour: no code line in scripts/, no new function, no new
               call site. S5 owns the mechanism.
             - Do not touch the budget gate's "hard cap" wording anywhere, or the harness's
               grep filter at tests/guardrails.test.sh:2228.
             - Do not edit case (f), case (g), case (a), case (b), or case (h); do not
               renumber, reletter, skip or delete any case.
             - Do not edit scripts/record-recovered-cost.sh, scripts/ship-check.sh,
               .github/, docs/loop/checks.md, spec.md, the three spike-*.md files, or any
               file under docs/loop/recovered-figure-drops-slice-and-model/.
             - Do not pin an absolute case count read from this document; compute it from main.
             - Do not introduce an env var, threshold, default, or suggested value.
             - Do not reopen OQ1, OQ2, OQ3 or OQ5, and do not touch the stale evict lock (OQ4).
             - Do not write to this repository's own .claude/.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  nothing
```

### S5 — Oblige an arrival that appends nothing to trim the ledger on arrival
```
Owner:       loop-build
Context:     scripts/record-cost-event.sh: append_and_evict() in full (:253-288) -- the L7 poll
             (:257-260), the unconditional `>>` (:263), the single `mkdir "$EVICT_LOCK"`
             attempt (:265), the convergence loop and its four I/O breaks (:274-284, including
             S9's `mv` break at :283), and `rmdir` (:285). Its two appending call sites: :441
             (cap_trip) and :782 (the finish/start record).
             The arrival paths that append nothing: the Bash rework branch (:537-540, whose
             handle_bash_rework_observation at :477-516 appends only when it emits a cap_trip
             at :512), and the duplicate-finish discard (:762-784, `exit 0` at :779 when the
             finished-marker mkdir loses). Also read, and deliberately NOT to be touched:
             SubagentStop (:528) and the unmatched-event `*)` (:529), neither registered in
             hooks/hooks.json.
             hooks/hooks.json -- the three registrations that decide which arrivals are even
             reachable: PreToolUse Agent|Task, PostToolUse Bash, PostToolUse Agent|Task.
             spike-oq5-local-red.md SS3 -- the deterministic lock-hold construction, 5/5 red
             vs HEAD and 5/5 vs pre-S5, AND its 0/5 sub-budget control (HOLD=0.02s), which is
             the evidence for the synchronous-release change required below.
             spike-oq2-bound-at-rest.md SS3 row 3 -- class 3, "fully compatible... zero on the
             invocation that made the run's last append".
             tests/guardrails.test.sh: case (f) at :437-465 (the assertion being replaced, at
             :464), case (g) at :467-486 (untouched, must stay green), case (b) at :407-435 and
             case (a) at :383-405 (where the dropped raw-writer arm's cover now lives), case
             (h) at :488-540 (the mv-break guard), the `cost()` helper at :70, `finish_json`,
             and `bash_test_json` at :593-613 in the REWORK section (defined AFTER the eviction
             section -- see the placement constraint below).
             docs/loop/decisions.md's newest entry; spec.md E3, E4, E5, E6, E7 and the failure-
             mode table.
Constraints: - THE BEHAVIOUR: an invocation that arrives and appends nothing checks the
               ledger's line count and, if over cap, trims it -- unconditionally, regardless
               of what its own event needed. This is obligation class 3 as decided.
             - ZERO NEW WORK ON ANY APPENDING INVOCATION'S OWN PATH. The append path's
               observable work is unchanged: same poll, same `>>`, same single mkdir attempt,
               same loop. If your change adds a `wc -l`, a subprocess, or a branch to an
               invocation that appends, you have drifted off the decision -- return
               `needs-decision`. S6 measures this claim; do not make it unmeasurable.
             - ONE TRIM LOOP. Factor the existing loop (:274-284) into a function both paths
               call. Do not copy it. Do not alter its break set, and do not add an attempt
               bound, iteration counter, or no-progress guard -- all three are foreclosed.
             - THE ARRIVAL TRIM NEVER WAITS: one mkdir attempt, no poll, no retry, no sleep;
               lock lost -> return 0. It fires on the PostToolUse/Bash registration, which is
               the most frequent hook arrival in a real session, and delaying a tool return
               there would trade L6 for a bound nobody asked for.
             - ONE TRIM PER INVOCATION, EVER: an invocation that emits a cap_trip (and so
               already trims via append_and_evict) does not also arrival-trim. Unfalsifiable by
               a case (both leave the same file), so it is a read at G2 -- write it so the
               reader can see it.
             - L7 IS NOT AMENDED. Header sentence (:95-98), L9 precedence (:62-67) and case (g)
               are untouched, and case (g) stays green.
             - CASE (f) IS REPLACED IN ITS ASSERTION AND CONSTRUCTION, NOT WEAKENED AND NOT
               DELETED. Same letter, same position, same section. The replacement asserts
               STRICTLY MORE than the old one: that the hole is constructed AND that it closes.
               Use S2's construction with ONE change -- release the lock SYNCHRONOUSLY (mkdir
               the lock; run the real finish hook, which polls, gives up, appends and loses the
               race; assert OVER cap; rmdir the lock; deliver one arrival that appends nothing;
               assert AT OR UNDER cap) instead of S2's backgrounded `sleep N; rmdir`. Reason,
               and it is S2's own evidence: its 0/5 control at HOLD=0.02s shows a hold shorter
               than L7's poll budget flips the arm's colour, so a timed hold on a loaded CI
               runner could release early and make the case green for the wrong reason. No
               sleep, no background job, no timing dependence beyond L7's own bounded poll.
             - The over-cap-before token is what stops the case being vacuous. Both tokens
               assert, in one `expect`, in this suite's `"yes yes"` style. Dropping the first
               token is weakening the case.
             - E3 IS THIS SLICE'S: reproduce your OWN red before green. Obtain the pre-change
               script read-only (`git show <rev>:scripts/record-cost-event.sh` into a temp
               file -- never checkout/branch/stash of the tree), run the replaced case against
               it 5 times and the changed one 5 times, and record both counts and the shas in
               your return. Citing S2's 5/5 is not a substitute: S2 falsified the hole, you are
               falsifying the fix.
             - PLACEMENT: `bash_test_json` (:593) is defined AFTER the eviction section, so the
               Bash-arrival case belongs in the rework section beside it; the other cases
               belong in the eviction section. Do not move, re-order, or duplicate an existing
               helper to work around this.
             - E6: cases (a), (b), (c), (d), (e), (g), (h) are unmodified and green. E7: no env
               var, threshold, default or literal is introduced -- evidence it that way, by
               grepping your own diff for `LARAVEL_LOOP_` and for new numeric literals.
             - Case count: +3 (case (f) replaced in place is net 0). Compute README's literal
               from `main` at build time; state your honest delta in your return if it differs.
             - bash 3.2 only; shellcheck -S warning scripts/*.sh clean; the hook exits 0 on
               every path (L6).
Output:      scripts/record-cost-event.sh (the factored trim function, two arrival call sites,
             the amended mechanism sentence at :88-90), tests/guardrails.test.sh (case (f)
             replaced + 3 new cases), README.md (`## Development` literal only).
Done when:   A ledger left over cap at rest by a lock-losing last appender is at or under cap
             again as soon as ANY later invocation arrives -- including one that appends
             nothing at all -- and case (f), in its replaced form, proves it: red 5/5 against
             the pre-change script, green 5/5 after.
Test set:    4 cases. Selection rule: one per thing this mechanism can get wrong that no other
             case in the suite would catch -- the property itself, each of the two obliged call
             sites, the never-wait failure mode, and the at-cap boundary. The 20000-line
             "converge a massively over-cap file on one arrival" arm was CONSIDERED AND NOT
             TAKEN: cases (a) and (b) already guard multi-iteration convergence, and a second
             20000-line arm would double this suite's slowest section to cover an iteration
             count the shared loop already owns.
               1. case (f), REPLACED: held lock -> real finish appends as a lock loser ->
                  ledger observed OVER cap at rest -> lock released -> one arrival that appends
                  nothing (a duplicate finish for an id already recorded, which is discarded at
                  :779 and appends nothing) -> ledger at or under cap. One `expect`, tokens
                  "yes yes".                                          [E1 property 3, E3, OQ1]
               2. the frequent real arrival: a PostToolUse/Bash event (`bash_test_json ...
                  pass`) against a ledger seeded over cap trims it to cap, appends no line of
                  its own, and exits 0. This is the path that fires most in a real session, and
                  no existing case sends a Bash event with an over-cap ledger.        [class 3]
               3. never waits: with the evict lock held by another process, an arrival that
                  appends nothing returns with its wall clock well under the hold, exits 0, and
                  leaves the ledger untrimmed -- case (g)'s shape, for the NEW path, which case
                  (g) does not cover because case (g)'s subject is an appender.        [L6, E5]
               4. boundary, at or under cap: an arrival with the ledger AT cap changes nothing
                  -- byte-identical ledger, no leftover `.evict.` temp file, exit 0.  [H3, E6]
             Fails now: today no arrival that appends nothing ever reads the ledger's line
             count, so 1, 2 and 3 have no code path at all; 4 passes trivially today and is
             kept as the regression guard for the path 1-3 add -- say so in its comment rather
             than presenting it as red-before.
             Passes after: 1-3 green, 4 still green, (a)(b)(c)(d)(e)(g)(h) untouched and green,
             `docs (case count)` green on the recomputed literal.
Do NOT:      - Do not add work of any kind to an appending invocation's path, and do not place
               the arrival trim before append_and_evict() on a path that will append.
             - Do not amend L7: not its header sentence, not its L9 precedence, not case (g).
             - Do not add an attempt bound, an iteration counter, or a no-progress guard.
             - Do not copy the trim loop; there is exactly one implementation.
             - Do not weaken, delete, skip, reletter, renumber or reorder any case. Case (f) is
               replaced in place, keeping its letter and position.
             - Do not touch scripts/record-recovered-cost.sh (its own independent
               append_and_evict is deliberate and out of scope), scripts/ship-check.sh,
               .github/, docs/loop/checks.md, hooks/hooks.json, spec.md, the three spike-*.md
               files, or docs/loop/recovered-figure-drops-slice-and-model/.
             - Do not reach for continue-on-error, a known-failures list, quarantining,
               de-blocking a step, or a platform skip -- out of bounds by non-goal even when it
               is the fastest route to green. Return `needs-decision` instead.
             - Do not investigate or fix the stale evict lock (OQ4): one observation line if you
               trip over it. A red you cannot show the lock absent for is not this unit's red.
             - Do not introduce an env var, threshold, default, or suggested value.
             - Do not write to this repository's own .claude/; throwaway CLAUDE_PROJECT_DIR
               only. Do not `git checkout`/branch/stash to obtain the pre-change script.
             - Do not pin an absolute case count from this document.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  S4 -- textual (same header block, same case-count literal) AND semantic (S5 amends
             the mechanism sentence that S4 writes the property into). Not a layer habit: if S5
             landed first, one commit would exist in which the code converges on arrival while
             the only written statement of the cap is the implied one that started this unit.
```

### S6 — Measure what the change costs where it is now paid, against S1's recorded baseline
```
Owner:       loop-build
Context:     spike-oq2-bound-at-rest.md SS4 -- E8's before-half, and the figures this slice
             measures against: under cap n=20 mean 148.0 ms / median 144.5 ms (min 136, max
             216); over cap n=20 mean 153.2 ms / median 149.5 ms (min 145, max 180); host
             macOS 26.6.1 arm64 GNU bash 3.2.57(1)-release; sha d24e2ce; method -- payload
             built OUTSIDE the timed interval, one `bash record-cost-event.sh` per trial under
             a fresh throwaway CLAUDE_PROJECT_DIR, over-cap arm re-seeded to 5000 lines before
             each trial with cap 15 so every trial runs a full convergence loop.
             spec.md E8 and E4. scripts/record-cost-event.sh as changed by S5.
             hooks/hooks.json -- PostToolUse/Bash is the registration that makes the arrival
             path frequent, which is why it is the arm that matters here.
Constraints: - REPRODUCE S1'S METHOD EXACTLY for the two comparable arms, or the comparison is
               not one: same host, same trial count (n=20 per arm), same payload-outside-the-
               timed-interval construction, same throwaway-directory discipline, same seeding.
               State the host and the sha you measured.
             - THREE ARMS, and the third is the new information:
                 (a) appending invocation, ledger under cap -- expected UNCHANGED vs 148.0/144.5
                 (b) appending invocation, ledger over cap  -- expected UNCHANGED vs 153.2/149.5
                 (c) an arrival that appends nothing (a PostToolUse/Bash event), with the
                     ledger over cap and with it under cap -- the newly-paid work, which had no
                     baseline because the path did not exist.
             - E8 IS ANSWERED WITH A NUMBER, NOT AN ADJECTIVE. "Negligible", "small", "no
               measurable difference" are all refused. Report mean, median, min, max, n.
             - THE CLAIM UNDER TEST IS FALSIFIABLE, AND YOU MAY FALSIFY IT: if arm (a) or (b)
               sits outside its baseline arm's own observed min-max spread, say so plainly and
               return `needs-decision` -- that would mean S5 put cost on the appending path
               after all, which is the one thing this gate's decision forbids. Do not round it
               away and do not average it out.
             - Counts, never rates (E4). One trial is one sample; 20 trials is 20 samples, not
               a distribution to extrapolate from.
             - Markdown only: this slice's whole diff is one new file. No code, no case, no
               change to the case-count literal.
             - Never the repository's own .claude/: throwaway CLAUDE_PROJECT_DIR per trial.
Output:      docs/loop/eviction-cap-not-honoured-under-contention/measure-e8-after.md
Done when:   That file states, in numbers: the three arms with mean/median/min/max/n each, the
             host, the sha, the method (and where it is identical to S1's), the delta of arms
             (a) and (b) against S1's recorded before-figures, and the arrival path's own cost
             with the ledger over and under cap.
Test set:    4 checks. THE PROOF IS A MEASUREMENT, NOT A HARNESS CASE, and that is stated in
             the file rather than disguised: a timing assertion in this suite would be flaky on
             a shared CI runner and would be the kind of case that goes red for reasons the diff
             cannot explain. Selection rule: one check per way this record could mislead
             someone downstream who cannot re-run it.
               1. arms (a) and (b) are compared against S1's exact figures, and the comparison
                  states whether each sits inside the baseline arm's own min-max spread    [E8]
               2. arm (c) is reported with both ledger states, since the over-cap one is the
                  only place the new work is actually paid                                 [E8]
               3. every arm carries n, mean, median, min, max -- no arm summarised in prose
                                                                                        [E8,E4]
               4. the method section names each point where it matches S1's and each where it
                  could not (and why), so a second person can re-run it            [E8, E3-ish]
             Fails now: no after-figure exists anywhere; E8 has a before-half and nothing to
             compare it to, and the arrival path has never been timed because it did not exist.
             Passes after: three arms, twelve figures, one method section, one explicit verdict
             on whether the appending path's cost moved.
Do NOT:      - Do not edit scripts/, tests/, .github/, README.md, spec.md, decisions.md, the
               three spike-*.md files, or any other unit's artifacts. One new markdown file.
             - Do not "fix" a disappointing number by changing the script; that would be S5's
               work arriving in the wrong slice. Report it and return `needs-decision`.
             - Do not measure on a container, VM, or a different host and present it as
               comparable to S1's -- S1's figures are host-specific and so are yours.
             - Do not state a rate, a percentage, or an expectation.
             - Do not write to this repository's own .claude/.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  S5 -- there is nothing to measure until the arrival path exists. Logical, not
             textual: this slice shares no file with S5.
```

### S7 — Record what this fix foreclosed, with the measured number
```
Owner:       loop-build
Context:     docs/loop/decisions.md -- its newest entry ("Second G1: the ledger promises
             convergence, and a later invocation is obliged to trim", 2026-08-18), which
             already forecloses property 2, obligation classes 1/2/4/5, leaving the assertion
             as it stands, deleting or weakening the case, and amending L7. This slice ADDS to
             that entry (or appends a short follow-up beneath it); it never rewrites it.
             This section of slices.md -- the Pinned contracts table, which is where the
             placement choices being recorded were actually made.
             measure-e8-after.md (S6's output) for the number.
             spec.md E9, E4, E2.
Constraints: - RECORD WHAT THIS PASS FORECLOSED THAT THE GATE ENTRY DID NOT, because these were
               G1's choices and not the gate's:
                 * arrival-trimming on EVERY invocation including appenders -- rejected: it
                   puts new work on an appending invocation's own path, which is the one thing
                   the chosen obligation class was chosen for avoiding;
                 * a second copy of the trim loop for the arrival path -- rejected: two copies
                   of one rule can only promise agreement (cost-ledger-lib.sh's own precedent);
                 * extending the obligation to scripts/record-recovered-cost.sh -- rejected:
                   a deliberate human-typed CLI, no contention, its independent copy is
                   documented as deliberate;
                 * obliging the two unregistered early exits (SubagentStop, unmatched event) --
                   rejected: unreachable through hooks/hooks.json, so it buys nothing;
                 * S2's TIMED lock release in the replaced case -- rejected in favour of a
                   synchronous release, on S2's own 0/5 sub-budget control: a timed hold can
                   release before L7's poll budget expires on a loaded runner and make the case
                   green for the wrong reason;
                 * the 20000-line raw-writer arm as a kept case -- dropped, with cases (a) and
                   (b) named as where that pressure stays guarded;
                 * an attempt bound / iteration counter / no-progress guard -- already
                   foreclosed, restated so a future reader does not re-propose it here.
             - CARRY S6'S NUMBER, not an adjective: the measured cost on the newly-obliged
               arrival path, and whether the appending path's own cost moved.
             - STATE E2 AS OUTSTANDING AND WHOSE IT IS: a real pushed run on both guarding
               platforms is the human's, post-merge, and one green run is ONE SAMPLE, not a
               rate (E4). Do not write a sentence that reads as though merging closed it.
             - STATE E3 AS MET AND HOW: red-before/green-after, with S5's trial counts and the
               script shas, and S2's independent 5/5 as the prior falsification of the hole
               itself.
             - Markdown only, one file. No case, no literal change, no code.
Output:      docs/loop/decisions.md (this pass's foreclosures, appended -- the existing entry is
             not rewritten).
Done when:   A future session reading decisions.md alone can see which placement was chosen,
             which alternatives were considered and rejected and why, what the change cost as a
             number, and that E2 is still open and belongs to the human.
Test set:    1 check, and it is a READ, not a harness case -- nothing in this suite greps
             decisions.md today and adding a grep case would freeze the prose of a file whose
             whole value is being written freely. Selection rule: the one thing this entry can
             fail at is silence about a rejected alternative, so the check is completeness
             against the list above.
               1. every bullet in the Constraints list above appears in the entry with its
                  reason, S6's number is present as a number, and E2 is named as the human's
                  outstanding action with one-green-run-is-one-sample stated       [E9, E4, E2]
             Fails now: decisions.md's newest entry records the gate's decision (property 3,
             class 3, the replaced assertion) and none of the placement choices, because none
             of them had been made when it was written.
             Passes after: all seven foreclosures, one figure, one outstanding-human-action
             sentence.
Do NOT:      - Do not rewrite, reword, or reorder the existing gate entry; append.
             - Do not edit scripts/, tests/, .github/, README.md, spec.md, the three
               spike-*.md files, or docs/loop/recovered-figure-drops-slice-and-model/.
             - Do not claim E2 as met, and do not describe the fix as verified on CI.
             - Do not state a rate or a percentage anywhere.
             - Do not re-open OQ1/OQ2/OQ3/OQ5, and do not record a position on OQ4 beyond
               "still out of scope, still compounds, still needs its own intent".
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  S6 -- the entry carries S6's measured figure. (And S5 transitively, for the
             placement it records.)
```

---

## Self-audit against the five-point G1 test

Run on my own bench before this reached the gate.

| Test | S4 | S5 | S6 | S7 |
|---|---|---|---|---|
| **1. One owning agent** | `loop-build`, one lane | `loop-build`, one lane | `loop-build`, one lane | `loop-build`, one lane |
| **2. One commit's worth** | A header block, one README clause, one case. No "and also": the README clause is the same statement for a reader who never opens the script | Code + the case that proves it, which is one commit by construction — splitting them would commit either a red suite or an untested fix | One markdown file | One markdown append |
| **3. Independently testable** | 1 conjoined case, 4 labelled tokens, red today because none of the four strings exists | 4 cases, selection rule stated, 3 of them with no code path today; plus its own 5/5 red-before against the pre-change script | 4 named checks; the proof is a measurement and the file says so | 1 named check, and it is declared a read rather than dressed up as a case |
| **4. Criteria as observable behaviour** | What a reader of the mechanism and a reader of README each learn | A ledger left over cap at rest is at or under cap after the next arrival, whatever that arrival was | Twelve figures and one explicit verdict on whether the appending path moved | What a future session can reconstruct from decisions.md alone |
| **5. Dependencies explicit** | `nothing` | `S4`, with both reasons named (textual + semantic) | `S5`, named as logical-not-textual | `S6` |

**Set sizes: 1, 4, 4, 1.** S5 at 4 is `test-design`'s "large, worth a second look" band, and it got
one: the four are one mechanism's property, its two obliged call sites, and one boundary — not four
behaviours. The cut that would split it (code in one slice, case (f)'s replacement in another) is
the one thing this repository's own hooks forbid, because one half would be a red suite and the
other an untested fix.

**Sent back to myself during this pass, recorded because the rejected cut is the useful part:**

- **A separate "factor the trim loop out" refactor slice.** Rejected: a refactor that delivers
  nothing observable is not a seam, and it would put the one risky edit (`append_and_evict`'s loop)
  in a commit with no case that could catch a mistake in it.
- **E8's after-half folded into S5**, which is what my own first pass promised ("in the same
  commit"). Deliberately changed, and here is why: S5 does **not** change the appending path — that
  is the whole point of class 3 — so the after-half is no longer "measure the path you changed", it
  is a 60-trial *falsification of the claim that nothing changed*, plus the first measurement of a
  path that did not previously exist. Folding that into S5 makes S5 two commits' worth, and worse,
  makes a disappointing number look like a build failure instead of a finding that belongs at a
  human's desk.
- **A stale-evict-lock slice.** Still out (`OQ4`). It has the same observable as this unit's hole
  and would license a fix validated against the wrong defect.

---

## Cross-unit landing order

**`docs/loop/recovered-figure-drops-slice-and-model` is live and building right now** — six
sequential reader-side slices, its own delta table walking `README.md:167` from 427 to 460, **S1 in
flight at this gate**. Shared surfaces, named here rather than discovered at merge:

| Shared surface | This group | The neighbour |
|---|---|---|
| `README.md`'s `## Development` case-count literal | S4 (+1), S5 (+3) | every one of its six slices |
| `tests/guardrails.test.sh` | eviction section (~:380-540), rework section (~:585+), docs section (~:3029+) — all inserts **before** the final `docs (case count)` case | its cost-report / cost-ledger-lib sections, same final-case rule |
| `README.md` prose | S4, the cost-ledger paragraph (~:92) | its S6, README prose around `/cost` and recovered figures — adjacent, possibly the same block |
| `docs/loop/decisions.md` | S7, appended at the end | its S6, appended at the end — the **same insertion point**, which is the classic silent conflict |

**Recommended order: let the neighbour finish first, then run this group.** Two reasons, neither of
them a coin flip: its S1 is already in flight and its remaining five slices are sequential by its own
table, so interleaving means every lane of mine rebases against a literal that moves under it; and
its S6 and my S7 append to the same end of `decisions.md`, which conflicts textually every time.

**Either order survives, because of the delta rule.** No slice above carries an absolute case count.
Each lane reads the literal from `main` at build time and adds its own delta, so a lane that happens
to build after the neighbour's S4 lands computes 449+1 without being told, and one that builds before
computes 427+1 — both correct, neither pinned here. **The only unsafe thing is a lane from each unit
in flight at the same time**; if that is unavoidable, land the harness-touching one first and merge
`main` into the other before it writes a line.

---

## Criterion traceability — supersedes the first pass's table

Nothing is dropped, nothing is claimed as assigned that is not, and nothing is left "not yet
assignable" — that phrasing was the first pass's honest state and this pass retires it.

| Criterion | Owner, after this cut |
|---|---|
| **E1** — the cap's property written down, at the moment it holds | **S4.** Property 3 named, the moment named, the `L7` limit shipped with the promise, in the header block and in README's ledger paragraph, with one conjoined case over both. |
| **E2** — the case green on both guarding platforms, on a real pushed commit | **The human's, post-merge. No slice claims it,** in this pass or the last. A builder does not push, and no container or local green substitutes. What to read when it runs: both `guardrails` and `guardrails-macos` reporting an identical `total: N passed, M failed`, with the replaced eviction convergence case passing on each. `S7` records it as outstanding so merging cannot be mistaken for closing it. |
| **E3** — the change falsified before it is believed | **Met, in two independent halves.** The hole: `S2`, landed — 5/5 red vs HEAD `d24e2ce`, 5/5 vs pre-`S5`, 0/5 sub-budget control. The fix: **`S5`**, which must reproduce its own red — the replaced case (f) run 5× against the pre-change script obtained read-only, 5× against the changed one, both counts and both shas in its return. Citing `S2` is explicitly not a substitute. |
| **E4** — no green run read as a rate | **Cross-cutting: `S5`, `S6`, `S7`.** Counts per arm with the version each ran against; twelve figures with `n` each; and `S7` stating in writing that the coming green CI run is one sample. |
| **E5** — `L7` not traded silently | **`S5`, structurally.** `L7`'s second branch never opens: `S1` established property 2 is unachievable, class 3 was chosen precisely because it costs the appending path nothing, and the header sentence, the `L9` precedence and case (g) are all untouched. Evidence is case (g) green and unmodified, plus `S6`'s arms (a) and (b) showing the appending path's own cost did not move. |
| **E6** — nothing already guaranteed regresses | **`S5`.** Cases (a), (b), (c), (d), (e), (g), (h) unmodified and green — `H3`, `H5`, `L5`, `L6`, `L9`, the non-numeric-cap fallback and the `mv`-break each keep their existing guard — plus the case-count delta rule, which is how "the suite's case total does not drop" is enforced rather than hoped. |
| **E7** — no new threshold, default, or suggested value | **Vacuous by construction, and evidenced rather than asserted.** No slice introduces a configurable; `S5` greps its own diff for `LARAVEL_LOOP_` and for new numeric literals and reports the result. The zero-output-when-unset case E7 asks for has nothing to be written about — a lane that finds itself needing one has drifted and returns `needs-decision`. |
| **E8** — the closing mechanism's cost measured where it is paid | **Before-half `S1`, landed, figures pinned in this section. After-half `S6`,** three arms: the appending path twice (expected unchanged, and falsifiable against S1's own min-max spread) and the newly-obliged arrival path, which is where the cost actually moved to. |
| **E9** — the `L7`/`OQ1` answer recorded so it is not re-litigated | **Already written at this gate** — `decisions.md`'s newest entry forecloses property 2, classes 1/2/4/5, leaving the assertion, deleting the case, and amending `L7`. **`S7`** adds what that entry could not contain: the placement choices made *here*, the rejected variants, `S6`'s number, and `E2`'s outstanding status. |
| **OQ1** | **Answered** at this gate: property 3, stated explicitly. Closed; no slice reopens it. |
| **OQ2** | **Answered** by `S1`: property 2 is not achievable alongside `L7`. Closed. |
| **OQ3** | **Answered** by `S3`: the fixture models a harsher world than production — mechanism matches a lock-loser, arrival rate does not. This is *why* case (f)'s construction is replaced rather than tuned, and it is recorded in `S7`. Closed. |
| **OQ4** (the stale evict lock) | **Still out of scope.** No slice. It has the same observable as this unit's hole, still compounds with it, and still needs its own intent. One observation line if a lane trips over it. |
| **OQ5** | **Answered** by `S2`: yes, a local red is constructible. Its honest gap — the filesystem dimension recorded **untried**, not tried-and-negative — is carried forward as a known limit of that lane, not re-opened by any slice here. |

---

## Riskiest slice: **S5**

Not S6, which can only produce a number someone argues with, and not S4, whose worst outcome is a
sentence a human rewords at G2. **S5 is the only slice that changes what the software does**, and it
carries three distinct ways to be wrong, in descending order of how likely they are to survive
review:

1. **A new blocking surface on the most frequent hook arrival in the repository.** The arrival trim
   lands on the `PostToolUse`/`Bash` registration — which fires on *every* Bash tool call in a real
   session, far more often than any `Agent|Task` event — and the trim loop it calls is deliberately
   **unbounded** (`while :;`, no attempt cap, by a recorded decision that must not be reversed). An
   over-cap ledger plus a concurrent append stream could therefore hold a Bash tool's return for as
   long as convergence takes, on a path that never previously touched the ledger at all. This is the
   line worth reading twice at this gate. Three things contain it and none of them removes it: the
   arrival trim takes one `mkdir` attempt and never waits on the lock; `S9`'s `mv` break plus the
   loop's three other I/O breaks bound every real failure mode; and **`S6` measures it** — arm (c),
   ledger over cap, in numbers. If the number is uncomfortable, the mitigation is a new decision at a
   gate, not a bound smuggled into this slice.
2. **Drift onto the appending path.** The tidiest-looking implementation — "check on arrival, at the
   top, for every invocation" — is precisely the one the decision forbids, because it charges every
   appending invocation a `wc -l` it does not pay today. It will look like simplification, it will
   pass every case in the suite, and only a read of the diff (or `S6`'s arms (a) and (b)) catches it.
   Hence a `needs-decision` instruction in the envelope rather than a hope.
3. **A replaced case that is green for the wrong reason.** Two specific routes: dropping the
   over-cap-before token (leaving an assertion that passes whether or not the hole was ever
   constructed — the exact defect class that let a regression through a 426-case green suite before),
   and keeping `S2`'s *timed* lock release (whose own 0/5 sub-budget control shows a hold shorter than
   `L7`'s poll budget flips the arm's colour, so a loaded CI runner could release early and hand
   everyone a green case that proves nothing). The envelope pins the synchronous release and both
   tokens for exactly this reason.

**Runner-up: S7**, for a quieter failure — an entry that records the decision but not the
alternatives, which is how a rejected design gets re-proposed in three months. Its check is
completeness against a list, precisely because "write down what we decided" reliably produces prose
about the choice and silence about the seven things it closed.

**And one honest residual nobody's slice closes:** `S2` recorded the **filesystem dimension as
untried** — not tried-and-negative — so the local evidence base for this unit has a named hole in it.
No slice above fills it, because a red found on a different filesystem would not change the
mechanism, the property, or the obligation this cut implements. It stays a limit of `S2`'s finding,
and `E2`'s real pushed run remains the only evidence about the guarding platforms.

---

# G1 — Slices — eviction-cap-not-honoured-under-contention (second G1: the fix group)

```
Slices: 4  ·  Parallel: 0 (empty, and that is the finding)  ·  Critical path: S4 → S5 → S6 → S7
Case-count deltas: S4 +1 · S5 +3 · S6 0 · S7 0  (group +4, computed from main at build time —
                   never from an absolute literal, because the neighbour unit is moving it now)
Riskiest: S5 — the only slice that changes behaviour. It puts an unbounded trim loop on the
          most frequent hook arrival in the repo (PostToolUse/Bash), its tidiest-looking
          implementation is the one the decision forbids (work on the appending path), and its
          replaced case can go green for the wrong reason if either the over-cap-before token
          or the synchronous lock release is dropped.

S4 · state what the cap promises — property 3, its moment, and L7's limit, in the header and
     README; the seam, and true of today's script          · depends on nothing
S5 · oblige an arrival that appends nothing to trim on arrival (class 3); case (f) REPLACED
     with the synchronous lock-hold construction, red 5/5 before          · depends on S4
S6 · measure the cost where it is now paid — three arms against S1's recorded before-figures,
     falsifiable if the appending path moved                              · depends on S5
S7 · record what this fix foreclosed, with S6's number, and E2 as still the human's
                                                                          · depends on S6

Human-owned, no slice claims it: E2 — a real pushed run, both platforms, after the group
                                merges. One green run is one sample.
Cross-unit: let recovered-figure-drops-slice-and-model finish first (its S1 is in flight; its
            S6 and this S7 append to the same end of decisions.md). Either order survives the
            delta rule; two lanes from different units in flight at once does not.

1. Approve — brief S4, then S5, then S6, then S7, sequentially  (recommended)
2. Re-slice — say which, and why
3. Spec is wrong — back to loop-spec
```
