# laravel-loop — Cost Optimization Requirements

**Target:** laravel-loop v0.2 → v0.4

> **Sequencing retired 2026-08-19.** §9's release table no longer schedules anything — see
> `docs/loop/decisions.md`, *"Backlog gate: one queue, four drops, and six questions closed"*. The
> requirements below remain a **backlog**, each entering `G0` on its own merits. **Dropped by that
> gate:** `R3.1` and `R3.2` (routing to a cheaper model — its own safety detector is not derivable
> while `loop-build` is unpriced), `R6`'s artifact-size criterion, and `R1.3`'s per-pass granularity
> (satisfied by substitution). §10's success targets are **withdrawn**: none is computable, and any
> future target must name the figure that computes it.

**Author:** Hamza Alayed · **Date:** 12 August 2026
**Source:** *Best AI Agent Cost Optimization Tools* — https://fast.io/resources/best-ai-agent-cost-optimization-tools/

---

## How to read this

Each requirement carries an ID, a priority, the reason it exists, and **testable acceptance criteria**. That last part is deliberate: laravel-loop's own G1 gate refuses a slice that cannot name the test that proves it, so a requirements doc for laravel-loop that fails its own standard would be embarrassing. Every AC below is checkable by a script or by reading a file.

Priorities: **P0** blocks everything after it · **P1** the actual value · **P2** worth doing once the rest is real.

### On the source

fast.io publishes this article and ranks its own product eighth in it. Treat the tool rankings as marketing and the *cost-driver taxonomy* as the useful part — the latter matches what anyone running multi-agent workflows sees, and it is what this document builds on.

Load-bearing (mechanism is real, magnitude varies): provider-level prompt caching reducing input token cost, retries multiplying spend, context repetition across turns.
Directional only (vendor-reported, uncited): "73% cost reduction", "30–50% on redundant requests", "65% of IT leaders report unexpected charges", "teams underestimate by 30–50%". Do not quote these to a client.

---

## 1. Where laravel-loop actually spends

The article names five cost drivers. Mapped onto this plugin specifically, ranked by expected contribution:

| # | Driver (article) | How it shows up in laravel-loop | Est. share |
|---|---|---|---|
| 1 | Multi-step reasoning | `loop-spec` and `loop-slice` both run **Opus**, on every unit of work, regardless of size | High |
| 2 | Context accumulation | Four agents, each with fresh context, each re-reading `conventions.md`, `decisions.md`, `spec.md`, `slices.md` | High |
| 3 | Retries | Up to 3 generate→validate cycles per slice before the cap trips | Medium |
| 4 | Tool calls | `loop-verify` reproduces the build's evidence from scratch — correct, and expensive by design | Medium |
| 5 | Storage | `docs/loop/<slug>/` artifacts and the refine-state file accumulate forever | Low |

Two of these are **deliberate design choices**, not defects. Opus on framing phases is a bet that a bad spec costs more than an expensive one. Verify re-running everything is a bet that an unverified green claim costs more than the tokens to re-check it. The goal here is not to reverse those bets — it is to make them **visible and priced**, so they can be re-evaluated with numbers instead of intuition.

**The ordering below is not negotiable.** R1 ships before R2–R5, because every other requirement is a guess without it. A cost control built on an unmeasured assumption is how you end up optimizing the wrong 10%.

---

## 2. R1 — Measurement (P0, foundation)

> *"Which 5% of requests consume 50% of tokens"* — Braintrust's framing, and the only question worth answering first.

### R1.1 — Cost ledger hook

Emit one event per subagent start/finish to `.claude/loop-cost.jsonl`.

**Fields:** timestamp, session id, slug, slice id, phase, agent, model, input tokens, output tokens, cache-read tokens (when the payload carries them), duration ms, terminal status.

**Why:** nothing in the plugin currently knows what anything cost. laravel-team's `emit-agent-events.sh` proves the mechanism works — a `PostToolUse` hook on `Agent|Task` reads `totalTokens` and `totalDurationMs` off `tool_response`.

**Acceptance criteria**

- [ ] A completed `/loop` run produces one start and one finish event per agent invocation
- [ ] Every event carries a resolvable `slug`; unattributed events are written with `slug: "unknown"` rather than dropped
- [ ] Concurrent invocations do not interleave-corrupt the file (atomic append or lock, per laravel-team's dedupe-race fix)
- [ ] Hook exits 0 unconditionally — cost accounting never blocks delivery
- [ ] Degrades cleanly with no `jq` and no `python3`
- [ ] Guardrail test asserts event count and field presence for a simulated 4-phase run

### R1.2 — Slug and slice propagation

The task envelope gains two lines so events can be attributed without inference.

```
Unit:  <slug>
Slice: S<n>          # omit for spec/slice phases
```

**Why:** cost per *unit of work* is the number a human can act on. Cost per anonymous subagent call is trivia.

**Acceptance criteria**

- [ ] `loop-protocol` documents both fields as mandatory in the envelope
- [ ] `/loop`, `/slice`, `/verify` all set them when briefing
- [ ] All four agents echo `Unit`/`Slice` in their return so a mis-brief is visible immediately

### R1.3 — Rework attribution ⭐

Tag every token spent after a slice's **first failing validate** as `rework`.

**Why:** this is the single most valuable number the plugin could produce, and nobody else's tooling can compute it — it requires knowing what a "first attempt" was, which only the loop knows. The article's retry point (an agent retrying 3 times is "effectively 4x more expensive than one that fails gracefully") is exactly the quantity the refine cap already bounds. Right now that bound is a claim; R1.3 turns it into a measurement.

Rework rate is also the direct feedback signal on slice quality: high rework means G1 is cutting badly, which is a *process* fix, not a spend fix.

**Acceptance criteria**

- [ ] Events after the first failing validate for a given (slice, target) carry `phase_detail: "rework"`
- [ ] A tripped refine cap emits a terminal event with the total rework cost of that slice
- [ ] Rework tokens are separable from first-attempt tokens in any report
- [ ] Test: a simulated red→red→red sequence attributes passes 2 and 3 as rework, and pass 1 as not

### R1.4 — Ledger hygiene

**Acceptance criteria**

- [ ] Ledger caps at a configurable line count (default 5,000), oldest-first eviction
- [ ] `.gitignore` covers it — cost data is local telemetry, not a repo artifact
- [ ] Written under `.claude/`, never inside `docs/loop/`

---

## 3. R2 — Budgets (P1)

> Budget caps and fallback chains are LiteLLM/Portkey's core feature. A plugin cannot intercept the provider call — but it *can* refuse to spawn the next agent.

### R2.1 — Per-unit budget with a gate, not a kill

A soft warn threshold and a hard gate. At the hard gate, `/loop` stops and presents options.

```
⏸ BUDGET — <slug> has consumed 412k tokens (cap: 400k)
Spent so far: spec 38k · slice 51k · build 289k (rework 104k) · verify 34k
Most expensive: S3 (147k, 2 refine passes)

1. Re-slice S3 and continue — rework is 25% of spend  (recommended)
2. Raise the cap to <n> and continue
3. Stop; keep artifacts and the log
```

**Why:** an unattended agent loop is the shape of spend that surprises people. But a hard kill mid-slice leaves a half-built worktree and wastes everything already spent — which is a *worse* cost outcome than finishing. Gate, don't kill.

Note the recommended option: at the budget gate, the useful move is usually **fixing the slicing**, not buying more tokens. The gate should say so.

**Acceptance criteria**

- [ ] Warn and hard thresholds configurable via `LARAVEL_LOOP_BUDGET_WARN` / `_HARD`; unset = disabled
- [ ] Breach presents numbered options with a recommended default; never silently continues, never silently aborts
- [ ] The breach message names the most expensive slice and its rework share
- [ ] A slice already in flight completes; the gate fires before the *next* spawn
- [ ] Test: simulated ledger over threshold produces the gate; under threshold does not

### R2.2 — Per-phase expectations

Defaults per phase, breach logged as a FLAG rather than gated.

**Why:** a spec phase that costs more than the build phase is a signal something is wrong — usually an intent that should have been three units of work. Worth surfacing, not worth blocking on.

**Acceptance criteria**

- [ ] Documented defaults per phase in `loop-protocol`
- [ ] Overrun appears in the phase's return `FLAGS`
- [ ] Never blocks

---

## 4. R3 — Routing (P1)

> *"Not every agent step requires frontier models."*

### R3.1 — Escalate, don't default, to Opus ⭐

Currently `loop-spec` and `loop-slice` are pinned to Opus in frontmatter — every unit of work, from a copy change to a billing rewrite, pays frontier rates for framing.

Change the default to Sonnet with **explicit escalation triggers**:

| Escalate to Opus when | Rationale |
|---|---|
| Spec has >8 acceptance criteria, or >3 failure modes | Genuine complexity |
| The unit touches auth, billing, PII, or tenant isolation | Blast radius justifies the spend |
| `loop-slice`'s self-audit rejects its own first pass | Demonstrated difficulty, not assumed |
| The human asks for it | Their call, no argument |

**Why:** this is the largest single lever available, and the "self-audit rejected its own pass" trigger is the interesting one — it escalates on *demonstrated* difficulty rather than a guess made before any work happened. It also composes with the existing design: a bad cheap slice already gets caught by the audit.

**Risk to watch:** a Sonnet spec that is subtly worse produces a bad slice, which produces rework — and rework is more expensive than the Opus spec would have been. **R1.3 is the instrument that detects this.** If rework rate rises after shipping R3.1, revert the default. This is precisely why R1 ships first, and this requirement should not ship without at least two weeks of baseline rework data behind it.

**Acceptance criteria**

- [ ] Escalation triggers documented in `loop-protocol` and in both agents
- [ ] The chosen tier and the trigger that selected it appear in the agent's return
- [ ] `LARAVEL_LOOP_ALWAYS_OPUS=1` restores current behaviour
- [ ] Ledger records the model per event so before/after is comparable
- [ ] Rollback criterion written into the release notes: rework rate up >20% vs. baseline → revert

### R3.2 — Cheap tier for mechanical slices

Slices matching a mechanical shape (a rename, a config change, a migration with no logic, a docblock pass) may run on the cheapest tier.

**Acceptance criteria**

- [ ] `loop-slice` may tag a slice `tier: mechanical` with a stated reason
- [ ] A mechanical slice that trips the refine cap re-runs once at the standard tier before escalating to the human — a cap trip is evidence the tag was wrong
- [ ] Test: a mechanical-tagged slice records the cheaper model in the ledger

---

## 5. R4 — Token reduction (P0 / P1)

> *"Prompt caching at the provider level reduces input token costs by 50 to 90%."* The mechanism is real; the plugin's job is to stop defeating it.

### R4.1 — Cache-friendly prompt ordering (P0) ⭐

Order every agent prompt and every brief **invariant first, volatile last**:

1. Agent system prompt (never changes)
2. `loop-protocol` contract (changes rarely)
3. `conventions.md` / `decisions.md` (changes occasionally)
4. Spec and slice list (per unit of work)
5. The specific task envelope (per slice)

**Why:** provider prompt caching keys on a **stable prefix**. A single volatile token near the front — a timestamp, a slice id, a run counter — invalidates the entire cached prefix behind it. This is the cheapest requirement in this document and plausibly the highest-yield: it is an ordering change, not a feature.

**Acceptance criteria**

- [ ] Ordering documented in `loop-protocol` as a hard rule with the reason stated
- [ ] No agent prompt or command brief interpolates a timestamp, run id, or counter above section 4
- [ ] Grep-based test asserts no volatile-looking interpolation in the top half of any agent file
- [ ] Where the payload exposes cache-read tokens, the ledger records them and the report shows a hit rate

### R4.2 — Context budget in the envelope (P1)

`Context:` gains a stated ceiling: at most N paths, each with a line range where the file exceeds M lines. No whole-file dumps, no directory globs.

**Why:** "context is a budget, not a bucket" is already in `loop-protocol` as advice. Advice does not survive an agent that is unsure and hedges by including everything.

**Acceptance criteria**

- [ ] Ceiling documented; `loop-slice` states path count per slice
- [ ] A slice exceeding the ceiling fails `loop-slice`'s self-audit and is re-cut
- [ ] `loop-build` returns a FLAG when a brief's context was insufficient — over-trimming has to be detectable, or this requirement quietly makes rework worse

### R4.3 — Bounded memory files (P1)

`conventions.md` and `decisions.md` are read by **every agent on every invocation**. Their size is multiplied by every agent call the plugin ever makes — the article's "4,000-token system prompt across 20 turns costs 80,000 tokens" arithmetic, applied to a file that only ever grows.

**Acceptance criteria**

- [ ] Soft cap documented (suggest ~150 lines each)
- [ ] Over cap → `/loop`'s close step flags the oldest or least-cited entries **for a human to remove**; never silently deleted
- [ ] Each entry carries a date so staleness is visible
- [ ] Report surfaces the per-invocation cost of these two files, so the cap can be argued about with a number

### R4.4 — No full-suite runs per slice (P1)

`laravel-validate` already prescribes filtered tests per slice and the full suite once at integration. Make it enforced.

**Why:** wall-clock more than tokens, but it compounds across every slice and it is trivially preventable.

**Acceptance criteria**

- [ ] Guardrail warns (exit 0 + stderr, not a block) when a subagent runs an unfiltered suite mid-slice
- [ ] Integration-time full run is not warned on
- [ ] `LARAVEL_LOOP_ALLOW_FULL_SUITE=1` escape hatch, named in the message

### R4.5 — Scoped verification (P2)

`loop-verify` reproduces evidence for the **changed surface** by default; full reproduction at G3 or on demand.

**Why:** the cheapest defensible reduction of the verify bet. Full re-verification of an unchanged surface buys very little.

**Acceptance criteria**

- [ ] Verify scopes test selection to the diff's touched paths by default
- [ ] The verdict **states its scope explicitly** — a scoped PASS must never read like a full PASS
- [ ] Full mode available and used at G3

---

## 6. R5 — Reporting (P1)

### R5.1 — `/cost [slug]`

```
# Cost — invoices-idempotency

Total: 412k tokens · 18m agent time · 4 phases · 6 slices

By phase          tokens    share   model
  spec              38k       9%    opus
  slice             51k      12%    opus
  build            289k      70%    sonnet
  verify            34k       8%    sonnet

Rework            104k      25%  ← first-attempt failures onward
Cache reads       187k      45%  ← prompt-cache hits

Most expensive slices
  S3  147k  (2 refine passes)  ← 36% of total
  S1   61k
  S5   44k

Flags
  · S3 alone is 36% of the unit — likely mis-sliced at G1
  · rework at 25% is above the 15% target
```

**Acceptance criteria**

- [ ] Reads only the ledger; makes no network calls and requires no third-party account
- [ ] Reports rework share, cache-read share, and the top slices by cost
- [ ] Flags any single slice exceeding 30% of unit total
- [ ] Empty or missing ledger produces a clear "no data, is the hook wired?" message rather than a crash or a zeroed table

### R5.2 — Cost in the delivery log

**Acceptance criteria**

- [ ] `/loop`'s close step appends the cost summary to `docs/loop/<slug>/log.md`
- [ ] Rework percentage recorded per unit, so the trend is visible across units without re-deriving it

---

## 7. R6 — Storage hygiene (P2)

**Acceptance criteria**

- [ ] Stale `loop-build` worktrees are listed at close and offered for cleanup
- [ ] Refine-state and ledger files both bounded
- [ ] `docs/loop/<slug>/` artifact sizes reported when a unit closes

---

## 8. Non-goals

Named explicitly, because the article's tool list is a catalogue of things this plugin should **not** become.

- **Not a gateway or proxy.** No routing layer, no provider fallback chain. That is LiteLLM's and Portkey's job, and a plugin sits in the wrong place in the stack to do it.
- **No semantic caching.** Needs an embedding store and a similarity threshold; wrong shape for a zero-dependency plugin, and the correctness risk on a near-miss cache hit is real.
- **No SaaS dependency.** No Helicone, AgentOps, Braintrust, or Galileo integration. The ledger is a local JSONL file. Anyone wanting a hosted dashboard can ship the file there themselves.
- **No hosted dashboard.** A `/cost` command reading a local file is the whole surface.
- **No cost-based auto-degradation.** Never silently switch to a cheaper model because spend is high — that trades a visible cost for an invisible quality loss, which is the worst available trade and impossible to detect after the fact.

---

## 9. Sequencing

| Release | Contents | Gate to proceed |
|---|---|---|
| **v0.2** | R1.1–R1.4 (ledger, attribution, rework), R4.1 (cache ordering) | Ledger produces believable numbers on 5+ real units |
| **v0.3** | R5.1–R5.2 (reporting), R2.1–R2.2 (budgets), R4.4 | Two weeks of baseline rework rate recorded |
| **v0.4** | R3.1–R3.2 (routing), R4.2–R4.3, R4.5, R6 | Rework rate stable or improved vs. v0.3 baseline |

R3.1 is deliberately last despite being the biggest lever. Changing the model tier without a rework baseline means a quality regression would be invisible — and a cheap spec that causes one extra refine pass costs more than the Opus spec it replaced.

---

## 10. Success criteria

Measured per unit of work, compared against the v0.2 baseline:

| Metric | Target | Why this one |
|---|---|---|
| **Rework share of tokens** | < 15% | The direct read on slice quality — the process fix, not the spend fix |
| **Cache-read share** | > 40% | Whether R4.1's ordering actually holds |
| **Cost concentration** | No slice > 30% of unit | A dominant slice is a G1 failure wearing a cost costume |
| **Total tokens per unit** | ↓ 25–40% | Deliberately below the article's "30–60%" — that figure assumes gateway and semantic caching, which are explicit non-goals here |
| **Verify FAIL rate** | Unchanged | The guardrail on all of it: cheaper work that ships more defects is not cheaper |

That last row is the one that matters. Every requirement above is void if it moves it.

---

## 11. Open questions

1. **Does the `Agent`/`Task` hook payload expose input/output tokens separately, and cache-read tokens at all?** laravel-team's emitter reads a combined `totalTokens`. If the split is unavailable, R4.1's cache-hit measurement is not directly observable and needs a proxy metric — resolve before committing to R5.1's report shape.
2. **Can a subagent's model be set per spawn**, or only in agent frontmatter? R3.1 and R3.2 both depend on the former. If frontmatter-only, escalation needs two agent definitions per phase, which is uglier but workable.
3. **Is prompt caching active by default** for plugin subagent invocations, and what is the minimum prefix length that qualifies? Changes how much R4.1 is worth.
4. **What is the real current rework rate?** Everything in §10 is calibrated against a baseline nobody has measured yet. If it is already under 15%, R3.1's risk profile improves considerably and it could move earlier.

---

## Source

*Best AI Agent Cost Optimization Tools* — fast.io — https://fast.io/resources/best-ai-agent-cost-optimization-tools/

Vendor-published; fast.io ranks its own storage product within the list. The cost-driver taxonomy in §1 is drawn from it and is sound. Savings percentages attributed to specific tools are vendor-reported and uncited — cited above as directional only, and deliberately not used to set any target in §10.
