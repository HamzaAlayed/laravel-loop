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
