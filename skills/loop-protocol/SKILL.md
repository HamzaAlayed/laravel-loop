---
name: loop-protocol
description: "The contract every laravel-loop agent runs on — the outer loop (intent → spec → slice → build → verify → ship → observe) with five human gates, the inner loop (parse → plan → generate → validate → refine) with a hard 3-pass refine cap, the slice-quality test, the task-envelope brief shape, and the STATUS/DID/VERIFIED/FLAGS/NEXT return shape. Use before starting any loop phase, when deciding whether work is ready to hand on, when briefing another agent, or when a task is looping on a red test."
---

# Loop Protocol

The contract. Every `loop-*` agent reads this before acting, so a handoff between them needs no explanation.

```
OUTER — per unit of work
  Intent → Spec → Slice → Build → Verify → Ship → Observe
             G0     G1              G2      G3      ↺

INNER — per slice, one agent, one worktree
  Parse → Plan → Generate → Validate ─┬→ done (green)
                    ↑                 │
                    └─── Refine ──────┘  red — cap 3, then blocked
```

`↺` is `/observe`'s capture step: it writes `docs/loop/<slug>/intent.md` (what was observed, where,
when, what was already tried, which unit or commit is suspected) and hands off to a fresh Intent at
G0. It never diagnoses, reproduces, or builds by itself.

The failure this prevents is **unstructured delegation**: one large ambiguous ask handed to one agent, producing work that reads like several people who never spoke. Every phase below exists to move an ambiguity earlier, to where fixing it is cheap.

## Phase placement

Identify the phase before doing anything. Most bad outcomes are phase errors — building while the spec is unsettled, or re-specifying a slice already agreed.

| The ask looks like | Phase | Owner |
|---|---|---|
| A problem, a complaint, a user need | Spec | `loop-spec` |
| An agreed spec, unclear how to build | Slice | `loop-slice` |
| A named, scoped, testable change | Build | `loop-build` |
| "Is this done?" / a branch to merge | Verify | `loop-verify` |
| A production fault | Observe (`/observe`'s capture step) → new Intent | human |

**Escalate when the input is thinner than the phase requires.** "Just add a button" that turns out to need a schema change is an Intent, not a slice. Starting it as a slice is how a one-hour task becomes a three-day one.

## The five gates

Everything not listed here runs without asking. Enumerating the gates is what licenses the autonomy between them — an unbounded instinct to check in is how a team ends up slower with agents than without.

| Gate | When | The human decides |
|---|---|---|
| **G0** | Spec written | Right problem? Right acceptance criteria? Right non-goals? |
| **G1** | Slices written | Right cuts, right order? |
| **G2** | Work claims done | Do I understand and endorse this diff? |
| **G3** | Pre-release | Ship / hold — evidence is `scripts/ship-check.sh`'s verdict (run via `/ship`) |
| **G4** | Production change | Any agent-initiated action on live infra |

Present every gate as numbered options with a recommended default (`AskUserQuestion` main-thread, printed text as a subagent), never as a paragraph the human has to decode into a yes or no.

G1 is the cheapest place to fix a design. G2 is the one that carries the weight: **never merge code nobody can explain.**

## Slice quality — the G1 test

All five must hold. A slice failing any one goes back to `loop-slice` rather than forward to `loop-build`.

1. **One owning agent**
2. **One commit's worth** of change
3. **Independently testable** — name the test that fails now and passes after
4. **Acceptance criteria as observable behaviour**, not implementation
5. **Dependencies named explicitly**, not implied by list order

## Task envelope

Brief every agent in this shape. Improvised prose briefs are where scope leaks.

```
Task:        <one line, imperative>
Owner:       <agent>
Unit:  <slug>
Slice: S<n>
Context:     <paths, prior art — the minimum to succeed, not everything>
Constraints: - <framework rules that apply>
             - <project rules from docs/loop/conventions.md>
Output:      <exact artifacts expected back>
Done when:   <observable behaviour + the test that proves it>
Do NOT:      <files, packages, or scope explicitly out of bounds>
```

`Unit:` and `Slice:` are mandatory on every brief — they are what lets anything downstream trace a run back to the work it belongs to. Write them exactly as shown, at line start, with no bold, no backticks, and no reordering: a hook greps them literally. `Slice` is **omitted** (not blank, not "n/a") for the spec and slice phases, which operate on the whole unit rather than inside one slice.

`Do NOT` is mandatory and "nothing" is not a valid value. It is the cheapest scope control available, and its absence is the commonest cause of a diff touching four things nobody asked for.

Context is a budget, not a bucket. Store what the repo cannot answer — intent, taste, rejections. Derive what it can — naming, hot paths, current state.

## Return shape

Every agent returns this, ≤10 lines. Nothing else.

```
STATUS: done | blocked | needs-decision
DID: artifacts touched, one line each
VERIFIED: command → actual result — evidence, not claims
FLAGS: corrections, risks, rejected approaches — or "none"
NEXT: handoff or "none"
```

Every return also names the `Unit` and `Slice` it was briefed with — fold them into `DID` (e.g. `DID: cost-measurement-v0.2 S1 — <files touched>`) rather than adding a line, so the shape stays ≤10 lines. An agent briefed without a `Unit` line says so instead of inventing or guessing one — pin the wording so it is greppable: `FLAGS: briefed without Unit/Slice`.

**An empty `VERIFIED` is a claim, not a return.** Reject it and re-brief. "Tests pass" is a claim; `php artisan test --filter=Invoice → 12 passed` is evidence.

## Per-phase expectations

Optional, off unless a human turns it on, and never anything more than a single line inside `FLAGS` above. Four fields, one per phase: `LARAVEL_LOOP_BUDGET_PHASE_SPEC`, `LARAVEL_LOOP_BUDGET_PHASE_SLICE`, `LARAVEL_LOOP_BUDGET_PHASE_BUILD`, `LARAVEL_LOOP_BUDGET_PHASE_VERIFY`. Set whichever of the four you want compared, to a bare non-negative integer, in tokens, chosen from your own ledger's observed totals for that phase — never from a figure suggested in a document. Leave any of the four unset and nothing happens for that phase: no comparison, no flag, ever — the same discipline the budget gate itself holds for its own two thresholds, and provable the same way, by a test asserting zero output rather than by reading the source.

Nothing here ships set by default, for any of the four fields, anywhere — not baked in, not commented out, not offered as a starting value. There is no baseline in this repository to derive one from: the ledger these fields compare against has never held a full recorded unit, and the great majority of invocations this repository has ever recorded — concentrated in the build phase above every other phase — carry no token figure at all. A number chosen for you here would be a guess wearing the authority of a shipped default, and this mechanism refuses to do that.

**Mechanism.** Before writing its return, the phase agent runs `scripts/check-budget-gate.sh --phase <phase> --unit <slug>` and pastes whatever single line it prints, if any, into that return's `FLAGS` verbatim. The check reuses the budget gate's own threshold parser rather than a second one — an unparseable value disables that phase's comparison loudly, naming the field and the value, the same way an unparseable budget threshold does — and reads the ledger through the identical arithmetic the report and the gate already share, never a second implementation of the total. A raised flag always carries its own coverage caveat inline — how many of that phase's recorded invocations carry a token figure, and how many do not — because a phase comparison drawn from a ledger that cannot see most of the build phase is not self-explanatory on its own. The check always exits cleanly and never blocks, delays, or gates anything: an overrun it finds is information for whoever reads the return, never a control. A phase whose invocations are all unpriced can never raise a flag — there is nothing observed to compare against — and the absence of a flag is never grounds for reading a phase as within expectation: that sentence is never printed, anywhere, by design.

**The in-flight limitation, load-bearing and not hidden.** An invocation's own finish record is written only after that invocation returns, so the figure a phase check sees covers that phase's already-recorded invocations, not the one currently running the check. A phase that runs only once per unit will therefore never see its own overrun reflected back to it — the flag, if any, can only ever come from an earlier invocation of that same phase within the same unit. A mechanism that quietly excluded the very invocation reading it would be exactly the kind of half-visible figure this protocol exists to refuse, so it is named here instead of left for someone to rediscover.

## The refine cap

**3 passes.** Then `STATUS: blocked` with the exact failing assertion as evidence.

Never hand back red code. Never delete, skip, or weaken a test to reach green. Both are hook-enforced (`enforce-refine-cap.sh`, `block-untested-commit.sh`), so these arrive as real blocks rather than reminders.

**A tripped cap is feedback on the slice, not the builder.** Three failures on one target means the slice was too coarse or the context too thin — problems upstream, in `loop-slice`'s layer or the human's. Re-brief once with the gap named; still failing → re-slice at G1. Never a fourth attempt at the same brief.

## Project memory

Three files, in the repo, human-readable and deletable.

| File | Holds |
|---|---|
| `docs/loop/conventions.md` | Rules the team taught — every agent treats these as overrides |
| `docs/loop/decisions.md` | Approaches **tried and rejected**, with why |
| `docs/loop/<slug>/` | `spec.md`, `slices.md`, `verify.md` for one unit of work |

`decisions.md` is the one teams skip and regret. Git tells an agent what the code *is*; nothing else records "we tried this in March, it broke under load, stop proposing it." Without it every session re-proposes your rejected designs and you re-litigate them by hand.

## Determinism boundary

Judgment → agent. Repeatability → hard-coded. Just because a step *could* be non-deterministic does not mean it should be.

| Agents | Deterministic |
|---|---|
| Specs, slicing, trade-offs | Build + deploy pipelines |
| Code generation, refactoring | Migration execution order |
| Test design (what can fail) | Test execution |
| Verification and review | Style + static analysis gates |
| Incident triage | Secrets, env promotion, rollback |

## Anti-patterns

| Anti-pattern | Correction |
|---|---|
| One prompt, whole feature | Slice at G1 first |
| Skipping G0/G1 because they feel slow | Fifteen minutes of spec beats a day of rework |
| Merging a diff nobody can explain | G2 is a read, not a rubber stamp |
| Refine loop running unbounded | Hard cap 3, then escalate |
| Deleting or weakening a red test | Hand the test back with your reasoning |
| Building something on the `Do NOT` list | Out of bounds even when it is an improvement |
| Accepting "done" without evidence | Empty `VERIFIED` is a rejected return |
| Whole codebase pasted as context | Relevant paths + an explicit `Do NOT` |

## Cache-friendly prompt ordering

Assemble every prompt stable-parts-first, in this fixed order: system prompt, this loop-protocol contract, `docs/loop/conventions.md` and `docs/loop/decisions.md`, the spec/slice list for the unit of work, the task envelope last. This is the five-level ordering and it does not get re-derived per project or per agent.

**Rule: never interpolate a timestamp, run id, or counter above the task envelope.** A single volatile token near the front of a prompt invalidates the whole cached prefix behind it — everything stable that follows it stops being cacheable too. Anything more volatile than the envelope itself belongs only inside the envelope, never earlier.

**The reason ships with the rule, in the same place, on purpose.** A rule without its rationale gets reordered by the next person who finds it inconvenient; writing down *why* it costs the whole prefix is what makes the ordering survive that person's judgment call.

This rule ships on its rationale alone. Whether prompt caching is actually active for subagent invocations, and at what minimum prefix length, is not established in this repository, and its payoff is deliberately left unmeasured for now — the rule costs nothing to hold and nothing to be wrong about, so it does not wait on that measurement.

Scope note: the rule's literal wording is timestamp, run id, counter — volatile state that changes on every run. A placeholder like `{{args}}` in a command's title is not a violation of it; substituting user-supplied argument text into a title is not the same failure mode as an ever-changing token, and moving it would be a readability cost paid for a benefit nobody has measured.
