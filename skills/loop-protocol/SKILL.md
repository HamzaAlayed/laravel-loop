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

The failure this prevents is **unstructured delegation**: one large ambiguous ask handed to one agent, producing work that reads like several people who never spoke. Every phase below exists to move an ambiguity earlier, to where fixing it is cheap.

## Phase placement

Identify the phase before doing anything. Most bad outcomes are phase errors — building while the spec is unsettled, or re-specifying a slice already agreed.

| The ask looks like | Phase | Owner |
|---|---|---|
| A problem, a complaint, a user need | Spec | `loop-spec` |
| An agreed spec, unclear how to build | Slice | `loop-slice` |
| A named, scoped, testable change | Build | `loop-build` |
| "Is this done?" / a branch to merge | Verify | `loop-verify` |
| A production fault | Observe → new Intent | human |

**Escalate when the input is thinner than the phase requires.** "Just add a button" that turns out to need a schema change is an Intent, not a slice. Starting it as a slice is how a one-hour task becomes a three-day one.

## The five gates

Everything not listed here runs without asking. Enumerating the gates is what licenses the autonomy between them — an unbounded instinct to check in is how a team ends up slower with agents than without.

| Gate | When | The human decides |
|---|---|---|
| **G0** | Spec written | Right problem? Right acceptance criteria? Right non-goals? |
| **G1** | Slices written | Right cuts, right order? |
| **G2** | Work claims done | Do I understand and endorse this diff? |
| **G3** | Pre-release | Ship / hold |
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
Context:     <paths, prior art — the minimum to succeed, not everything>
Constraints: - <framework rules that apply>
             - <project rules from docs/loop/conventions.md>
Output:      <exact artifacts expected back>
Done when:   <observable behaviour + the test that proves it>
Do NOT:      <files, packages, or scope explicitly out of bounds>
```

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

**An empty `VERIFIED` is a claim, not a return.** Reject it and re-brief. "Tests pass" is a claim; `php artisan test --filter=Invoice → 12 passed` is evidence.

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
