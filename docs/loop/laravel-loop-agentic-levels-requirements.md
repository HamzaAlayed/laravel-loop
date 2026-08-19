# laravel-loop — Agentic Level Requirements

> **Sequencing retired 2026-08-19.** §8's release table no longer schedules anything — see
> `docs/loop/decisions.md`, *"Backlog gate: one queue, four drops, and six questions closed"*. Two
> changes that gate made to this document's plan: the **planning checkers (`R2.1`, `R2.2`) come
> before the eval harness (`R3.1`)**, so the harness scores against them instead of re-implementing
> the same rules; and **`R4.2` (autonomous triggering) is cancelled**, taking the branch `R4.3`
> itself offers, while `R4.1` (persistent state) survives. `R2.1` is settled as **structural only,
> no quality judgement**.


**Target:** laravel-loop v0.6 → v0.8
**Author:** Hamza Alayed · **Date:** 14 August 2026
**Source:** *The 6 Levels of Agentic Behavior* — Vellum — https://www.vellum.ai/blog/levels-of-agentic-behavior

---

## How to read this

Same shape as `laravel-loop-cost-requirements.md`: ID, priority, rationale, machine-checkable acceptance criteria. **P0** blocks what follows · **P1** the value · **P2** later.

### On the source

Vellum publishes this and places its own product at the top of the ladder. Two things to separate:

**Keep — the L0–L5 ladder.** It is the SAE self-driving-levels analogy applied to agents, and it holds up: autonomy as "a gradual, structured progression" rather than a binary. The per-level split of *what the system decides* vs *what the human decides* is the useful axis, and it maps cleanly onto a gated workflow.

**Discard — L6.** "Personal Assistant (Companion)" is not a level. It describes a *deployment surface* — one user, many channels, accumulated context — which is orthogonal to how much the system decides for itself. A single-surface L4 is more autonomous than a multi-surface L2. It sits above L5 in the article because that is where the vendor's product sits, not because it is further along any axis.

Also treat "no current implementations" (L5) and "we're nowhere near this" as the article's own admission that the top of its ladder is speculative. Requirements below stop at L4.

---

## 1. Where laravel-loop actually sits

Not one level — a different level per component, which is the honest reading and the useful one.

| Component | Level | Why |
|---|---|---|
| Guardrail hooks (`enforce-refine-cap`, `block-untested-commit`, `warn-full-suite`) | **L0** | Pure if-this-then-that. Deliberately. |
| CI, `ship-check.sh` version gate | **L0** | Deterministic by design |
| `loop-spec`, `loop-slice` | **L2** | Tool-using, single-shot, self-audit is unmeasured |
| `loop-build` inner loop | **L3** | Parse → plan → generate → **validate → refine** is a real evaluation loop with a bounded retry |
| `loop-verify` | **L2–L3** | Evaluates outputs, but does not adjust and re-run — it reports and stops |
| `/loop` orchestration | **L3** | Multi-step, state-aware, sequences by dependency |
| `/observe` | **L3, aspiring L4** | Human-invoked. Does not monitor, does not self-trigger |
| Cross-session memory (`docs/loop/`) | **L3** | Persists as files, but nothing *acts* on them unprompted |

**laravel-loop is an L3 system with an L0 safety floor.** That floor is a feature: the article's L0 failure mode ("breaks the moment conditions change") is exactly what you want from a guard that refuses untested commits. Do not upgrade the hooks.

The article's L3 ceiling describes the plugin precisely: *"once the task is complete, the system shuts down. It doesn't set its own goals."* That is `/loop` after G3.

---

## 2. The tension this framework creates — read before any requirement below

The ladder measures **how much the system decides without a human**. laravel-loop's entire thesis is that a human decides at five specific gates. Those are the same axis pointing opposite directions.

**Climbing the ladder as such would destroy the product.** An L4 laravel-loop that self-triggers builds and merges its own PRs is not a better laravel-loop; it is a worse one with the gates removed, and the gates are the reason anyone would install it.

So the upgrade is not *height*. It is **depth within each gate segment**: raise the level of the work that happens *between* two gates, while the gates themselves stay exactly where they are.

Concretely — G0 and G1 currently sit at L2. The work between "intent arrives" and "human reviews the spec" is single-shot generation with an unmeasured self-check. That segment can become L3 — evaluate, adjust, re-run — without moving the gate one inch. **That is the whole upgrade path, and R2 is where the value is.**

The one place genuine L4 is warranted is Observe, because monitoring production *is* the job, and a monitor that only runs when invoked is not a monitor. R4 covers it, fenced.

---

## 3. R1 — Declare the level (P0)

### R1.1 — Per-phase level declaration

Each agent, command, and hook states its intended level and what it therefore may not do.

**Why:** unstated autonomy drifts upward. Every "it could just handle that itself" is a half-step, and half-steps accumulate silently until something acts unsupervised that nobody decided should. A declared level makes drift a diff.

**Acceptance criteria**

- [ ] `loop-protocol` carries the level table from §1, with the gates marked
- [ ] Each agent's body states its level in one line and names the next-level behaviour it refuses
- [ ] The L0 floor is documented as **deliberate**, so no future contributor "improves" a guardrail into a judgement call
- [ ] A test asserts every agent and command file contains a level declaration

### R1.2 — The ceiling is a rule, not a preference

**Acceptance criteria**

- [ ] `loop-protocol` states: no component exceeds L4, and only Observe may reach it
- [ ] L5 (self-authored tools, self-composed logic) is a permanent non-goal, stated with the reason — a plugin whose value is *predictability* cannot also invent its own procedures
- [ ] Any PR raising a component's level must change its declaration, making it visible at review

---

## 4. R2 — Complete L3 in the planning phases (P0) ⭐

The highest-value work in this document. `loop-build` has an evaluation loop; `loop-spec` and `loop-slice` do not.

Today both *self-audit* — they check their own output against a list and decide whether it passes. That is the L2 failure mode the article names: *"if it makes a mistake, it won't self-correct."* An agent grading its own homework with no external signal is not an evaluation loop; it is a prompt hoping to be believed.

`loop-build` is L3 because `php artisan test` is an **external, machine-checkable verdict** it cannot argue with. G0 and G1 have no equivalent.

### R2.1 — `spec-check.sh` — a machine verdict for G0

A deterministic (L0) checker over `docs/loop/<slug>/spec.md`, in the shape of the existing `ship-check.sh`.

Checks that need no judgement:
- Non-goals section exists and is non-empty
- ≥1 acceptance criterion, each phrased observably (no "feels", "intuitive", "fast" without a number)
- Failure-modes table has ≥1 row, or an explicit "none — stated why"
- Open questions section present (may say "none")
- No code fences (a spec containing an implementation has pre-solved the problem)

**Acceptance criteria**

- [ ] Exits 0 clean / 1 with findings; never blocks, prints findings for the agent to act on
- [ ] `loop-spec` runs it before returning and refines until clean or reports why it cannot — **this is the loop that makes G0 L3**
- [ ] Findings name the section and the rule, never a vague "improve this"
- [ ] Guardrail tests cover each rule, plus a clean spec passing
- [ ] The human still decides at G0. The checker gates *readiness to be reviewed*, not the decision.

### R2.2 — `slice-check.sh` — a machine verdict for G1

Deterministic checks over `docs/loop/<slug>/slices.md`:
- Every slice has all seven envelope fields
- `Do NOT` is present and is **not** "nothing" / "n/a" / empty
- `Done when` names a test
- One owner per slice
- `Depends on` references only earlier slices — a forward reference is a cycle or a mis-order
- Slice count ≥1, and any slice whose title contains " and " is flagged for review

**Acceptance criteria**

- [ ] Same exit convention and non-blocking behaviour as R2.1
- [ ] `loop-slice` runs it, refines, and returns clean or explains
- [ ] Forward-dependency detection has a test with a deliberately cyclic fixture
- [ ] Findings quote the offending slice ID

### R2.3 — Bound the planning loop

The refine cap exists because an unbounded loop is worse than no loop.

**Acceptance criteria**

- [ ] Planning refine capped (suggest 2 — a spec is cheaper to fix by hand than code)
- [ ] At the cap: return with findings unresolved and say which, rather than silently returning dirty
- [ ] `LARAVEL_LOOP_PLAN_REFINE_CAP` override, `0` disables

### R2.4 — Close `loop-verify`'s loop

Verify evaluates but does not adjust — it reports and stops, which is L2 behaviour in an L3 system.

**Acceptance criteria**

- [ ] On a finding it cannot substantiate (a failure the diff cannot explain), verify **re-runs scoped** before writing the verdict rather than reporting an unexplained FAIL
- [ ] Bounded — one re-run, then report with the ambiguity stated
- [ ] The verdict states whether a re-run happened and what changed

---

## 5. R3 — Evaluations (P0) ⭐

The article is explicit: *"version testing and evaluations are critical at higher levels"* — mock inputs, human-in-the-loop review, execution logging.

laravel-loop has **execution logging** (cost ledger) and **human-in-the-loop** (gates). It has **no evals**. Every skill and agent body shipped so far — including `build-conventions` — was reasoned about and shipped without a single measurement of whether it changed behaviour.

The guardrail suite tests the L0 floor. Nothing tests the L2–L3 layer, which is where all the product value lives. Laravel Guild has `docs/evals/` with dated runs; laravel-loop has nothing.

### R3.1 — Eval harness with recorded fixtures

**Acceptance criteria**

- [ ] `tests/eval/` with ≥1 case per phase: a fixture repo, a fixed input, and recorded expectations
- [ ] Expectations are **structural and checkable** — did the spec produce non-goals, did the slice list carry a `Do NOT`, did the build produce a test, did verify catch a planted defect — not prose comparison
- [ ] A planted-defect case per phase: a spec with an unfalsifiable criterion, a slice with an empty `Do NOT`, a diff with a deleted test. Each must be caught.
- [ ] Runs opt-in and separately from `guardrails.test.sh` — evals cost tokens; the guardrail suite must stay free and fast
- [ ] Results written dated to `docs/evals/`, following the Guild's convention

### R3.2 — Change gate for prompt-layer edits

**Acceptance criteria**

- [ ] Editing any agent body or `SKILL.md` requires an eval run recorded in the PR
- [ ] Documented in CONTRIBUTING and in the release checklist
- [ ] A regression is a **blocking** finding at G2, same as a failing test

**This requirement retroactively covers a real gap.** Seven skills exist; none was measured. R3.1's first run is also the first evidence any of them works.

---

## 6. R4 — L4, fenced to Observe (P1)

The only place autonomy is genuinely warranted: a monitor that runs only when invoked is not a monitor.

### R4.1 — Persistent, session-independent state

L4 requires *"persistent state, monitors environments across sessions."* The article's own L4 failure mode is *"don't reliably persist across sessions."*

**Acceptance criteria**

- [ ] The watched-signal set is a file in the repo, not session context
- [ ] Each signal carries: what, where, last-checked, last-state
- [ ] Restart-safe — a fresh session resumes from the file with no context carried over
- [ ] Bounded and evictable, like every other memory file

### R4.2 — Autonomous triggering, and what it may do

**Acceptance criteria**

- [ ] On a detected signal, Observe may **only** open an intent — origin, context, attempted resolution. It may not spec, slice, build, or merge.
- [ ] Every autonomous action leaves a paper trail; a remediation with no issue behind it has hidden a signal rather than fixed a fault
- [ ] Rate-limited, with the limit stated and tested
- [ ] G4 unchanged: any production-touching action still needs a human

### R4.3 — The capability gate ⛔ blocking

**Do not build R4.2 until spend on backgrounded agents can be measured.**

`docs/loop/decisions.md` (2026-08-14) records that only foreground invocations return tokens — 3 of 79 terminal records priced, `loop-build` structurally 100% unpriced. The article's L4 caveat is the same point in the abstract: *"infrastructure lacks primitives for real autonomy."* Yours is not abstract; it is measured.

An autonomous trigger is a process that starts work without a human present. If spend on that work cannot be seen, the budget gate cannot bound it — and `check-budget-gate.sh` currently sees ~4% of it.

**Acceptance criteria**

- [ ] R4.2 does not ship while background-invocation pricing coverage is below a stated threshold
- [ ] The threshold is written into `loop-protocol` with the measurement behind it
- [ ] If coverage cannot be raised, R4.2 is **cancelled**, not shipped unbounded, and that decision is recorded

---

## 7. R5 — Declared ceilings (P1)

| Level | Stance | Reason |
|---|---|---|
| **L0** | Keep for all hooks and CI | Determinism is the point. "Breaks when conditions change" is correct behaviour for a guard. |
| **L2** | Acceptable transitional state | Only where R2 has not landed yet |
| **L3** | The target for every phase | Evaluate, adjust, bounded retry |
| **L4** | Observe only, after R4.3 | Monitoring is the one job that needs self-triggering |
| **L5** | **Permanent non-goal** | A plugin whose value is predictability cannot invent its own procedures. Also: no current implementations exist. |
| **L6** | Not a level | Deployment surface, not autonomy. Out of scope. |

**Acceptance criteria**

- [ ] Table in `loop-protocol` and README
- [ ] Each ceiling carries its reason, so a future contributor argues with the reason rather than rediscovering it

---

## 8. Sequencing

| Release | Contents | Gate to proceed |
|---|---|---|
| **v0.6** | R1 (declarations), R3.1 (eval harness) | Evals run and catch every planted defect |
| **v0.7** | R2.1–R2.4 (planning phases to L3), R3.2 | Eval run shows G0/G1 output improved, no regression elsewhere |
| **v0.8** | R4.1, R5 | — |
| **later** | R4.2 | Only after R4.3's coverage threshold is met |

R3.1 lands in v0.6, before R2, deliberately: R2 changes agent behaviour, and without evals there is no way to know whether it helped. Shipping R2 first repeats the mistake the seven existing skills already embody.

---

## 9. Success criteria

| Metric | Target | Why |
|---|---|---|
| Planted defects caught by evals | 100% | The floor. A miss means the phase does not do its stated job. |
| Specs passing `spec-check` unaided | rising | Whether the G0 loop is learning |
| Human edits at G0/G1 after approval | falling | The real read on planning quality |
| Rework share of invocations | ≤ current | R2 adds refine passes; if it raises rework, the checks are wrong |
| Guardrail suite | green, unchanged runtime | L0 floor stays free and fast |
| Components above declared level | **0** | Drift detection |

The fourth row is the guardrail on the whole document. R2 adds loops, and loops cost. If planning refine rises without G0/G1 quality rising, the checkers are measuring the wrong things and should be cut back, not tuned.

---

## 10. Open questions

1. **Can `spec-check` be strict enough to be useful without being gameable?** An agent that learns to satisfy the checker rather than write a good spec is worse than no checker. R3.1's planted-defect cases are the detector — but only if the fixtures are refreshed when the checker changes.
2. **Is one re-run enough for R2.4?** Unknown until evals exist. Start at one.
3. **What is the honest background-pricing threshold for R4.3?** 4% is plainly too low. 80% is defensible. Anything between needs an argument, and the argument needs data the ledger cannot yet produce.
4. **Does the L0 floor need its own regression test?** The suite tests each hook's behaviour but nothing asserts a hook has not *acquired* judgement — e.g. a model call added to a guardrail script. A grep-level test would catch it cheaply.

---

## Source

*The 6 Levels of Agentic Behavior* — Vellum — https://www.vellum.ai/blog/levels-of-agentic-behavior

Vendor-published; the article places the vendor's own product at the top of its ladder. §1's L0–L5 assessment uses the framework as given. L6 is excluded as a deployment surface rather than an autonomy level — see the note at the top. No performance figures from the article are used anywhere in this document, because it offers none that are cited.
