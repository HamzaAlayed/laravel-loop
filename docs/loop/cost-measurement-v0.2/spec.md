# cost-measurement-v0.2

Implements the **v0.2 row** of `docs/loop/laravel-loop-cost-requirements.md` §9, and only
that row: R1.1 (cost ledger hook), R1.2 (slug/slice propagation), R1.3 (rework
attribution), R1.4 (ledger hygiene), R4.1 (cache-friendly prompt ordering).

That requirements document is human-authored by the repo owner and is the source of truth
for **what** v0.2 contains. This spec does not re-derive it. What this spec adds is the
part the requirements document could not do from a desk: it checks the proposed mechanism
against this repo's actual hook infrastructure, resolves what that infrastructure settles,
and carries forward — as questions, not guesses — what it does not.

**Status: G0 approved.** All five open questions were resolved by the human before slicing
— see *Decisions taken at G0* below. Open questions: none.

## Problem

Nobody running this plugin can answer *what did that unit of work cost*, and therefore
nobody can answer any of the questions that follow from it.

A person runs `/loop` on an intent. Four agents spawn, some more than once, some
concurrently. Two of them are deliberately pinned to the most expensive model available,
on the argument that a bad spec costs more than an expensive one. Slices that fail
validation are retried up to three times, on the argument that the cap makes the retry
cost bounded. Verify re-runs the build's evidence from scratch, on the argument that an
unverified green claim costs more than the tokens to re-check it.

Every one of those arguments may be right. **None of them has ever been checked against a
number**, because the plugin records nothing. When the bill arrives it is a single figure
covering every unit of work in the period, attributable to nothing. The person who wants
to know whether the expensive framing phases earned their cost, or whether one badly-cut
slice consumed a third of the unit, has no way to find out and no way to notice they were
wrong for months.

The specific number that matters most does not exist anywhere and cannot be bought: **what
share of the work was rework** — everything spent after a slice first failed validation.
That is the direct read on whether slicing is any good, and it is computable only by
something that knows what a first attempt was. Only the loop knows that. Today the loop
knows it and throws it away.

Two smaller problems ride along. The plugin briefs agents without recording which unit of
work a brief belongs to, so even if spending were observed it could not be attributed to
anything a human acts on. And nothing anywhere states that a brief should be assembled
stable-parts-first, so any prompt-prefix caching the host offers is defeated by accident,
invisibly, at no one's decision.

## Users

- **The person paying for the plugin's runs** — the repo owner today, anyone who installs
  it tomorrow. Today: reads a monthly total, cannot attribute it, and either accepts it or
  stops using the tool. Has no way to tell an expensive unit of work from an expensive
  habit.
- **Whoever is deciding whether the loop's design bets still hold** — Opus on framing,
  three refine passes, full re-verification. Today: argues from intuition, because that is
  all there is. The requirements document's own R2–R5 are all blocked behind this: a cost
  control built on an unmeasured assumption optimises the wrong thing.
- **Whoever cuts the slices.** Today: learns that a slice was too coarse when its refine
  cap trips, which is late and coarse feedback. A rework share per unit is the same signal,
  earlier and quantified — and it is a *process* fix, not a spend fix.
- **The person who installed this plugin and did not ask for telemetry.** Their interest is
  that whatever gets recorded stays on their machine, stays out of their commits, stays
  bounded, and can be deleted without breaking anything.

## What the evidence already settles

Recorded here because these were open questions in the source document and answering them
from a file someone can re-read is cheaper than answering them twice.

**E1 — Hooking subagent invocations is possible here, and this is observed, not inferred.**
`/Users/developer/Downloads/laravel-loop-repo/.claude/agents-board.jsonl` exists in this
repository and contains five records of `loop-spec` invocations made **in this repo**,
including this one. It was written by
`/Users/developer/Projects/Personal/laravel-claude-agents/scripts/emit-agent-events.sh`,
registered in that plugin's `hooks/hooks.json` as `PreToolUse` on matcher `Agent|Task`,
`PostToolUse` on `Agent|Task`, and `SubagentStop`. So the host fires all three here. The
requirements document cited that script as prior art from another project; it turns out to
be prior art running in this directory. R1.1's mechanism is not speculative.

Note what this does *not* say: laravel-loop's own `hooks/hooks.json` registers `Bash`
matchers only. R1.1 requires new registrations. What is established is host support, not
current wiring.

**E2 — The finish payload carries a combined token total, a duration, and a status.** A
completed `loop-spec` invocation in that feed records `totalTokens` 60787,
`totalDurationMs` 239271, `status` "completed". `tool_input.subagent_type`,
`tool_input.description`, `session_id`, and a top-level `agent_type` naming the *calling*
agent are all populated. Cost-per-invocation is therefore observable today.

**E3 — Nothing in the payload identifies a unit of work.** There is no slug, no slice, no
phase. This is exactly why R1.2 exists, and it makes R1.2 a hard dependency of R1.1's
attribution rather than a nicety: without something the hook can read, every event is
`slug: "unknown"` and the ledger is a list of anonymous charges.

**E4 — A single invocation can produce three lifecycle records.** The feed shows
`PreToolUse` start, a `SubagentStop` finish, and a `PostToolUse` finish for one `loop-spec`
run. The `SubagentStop` record carries no tokens at all. Any ledger that treats every
finish signal as an invocation will double-count.

**E5 — Asynchronously launched subagents report no tokens on completion.** Documented in
the prior-art script's own header and corroborated by the null-token stop records in the
feed: `PostToolUse` fires at launch with status `async_launched` and null tokens and
duration, and the only later signal, `SubagentStop`, carries no tokens either. `/loop`
runs independent build slices concurrently. If that concurrency is async launching, **the
build phase — the largest spender — may be partly unpriceable**. See D4.

**E6 — Neither the input/output token split nor cache-read tokens are established.** The
prior-art script reads a combined `totalTokens` and does not look for more, so their
absence from the feed proves nothing about the payload. This cannot be settled by reading
files; it needs one raw payload captured during the work. Until then the source document's
own hedge — "when the payload carries them" — is the answer: **best-effort optional
fields, and no acceptance criterion depends on them.**

**E7 — Whether prompt caching is active for subagent invocations, and at what minimum
prefix length, is not determinable from this repository at all.** Consequence: R4.1's rule
can be written and enforced in v0.2, but its payoff cannot be measured in v0.2.

## Acceptance criteria

### The ledger (source R1.1)

- [ ] **L1** A completed `/loop` run produces, for each agent invocation it made, exactly
      one start record and exactly one finish record. Never zero. Never two finishes for
      the same invocation, whichever host signals fired (E4).
- [ ] **L2** Every record carries every field the source document names: timestamp,
      session id, slug, slice id, phase, agent, model, input tokens, output tokens,
      cache-read tokens, duration ms, terminal status. A field the payload does not supply
      is null or absent by a stated rule.
- [ ] **L3** No record ever reports `0` for a value that was unavailable. Zero means
      measured-as-zero. Unavailable means null. A ledger whose whole purpose is to be
      believed cannot round a gap down to a number.
- [ ] **L4** Every record carries a slug. An invocation whose slug cannot be resolved is
      written with `slug: "unknown"` — never dropped, never guessed from context.
- [ ] **L5** Two invocations finishing concurrently produce two intact records. No
      interleaved, truncated, or merged line. Provable by a test that forces the
      concurrency rather than hoping for it.
- [ ] **L6** The hook exits 0 on every path: valid payload, malformed payload, empty
      payload, unwritable ledger, missing parser, its own internal error. Asserted per
      case, not in aggregate.
- [ ] **L7** The hook never blocks, delays, or alters a spawn. Cost accounting that can
      stop delivery is worse than no cost accounting.
- [ ] **L8** With neither `jq` nor `python3` on PATH the hook exits 0 and writes nothing
      corrupt. Writing a reduced record or none is a build decision; writing a broken line
      is not permitted either way.
- [ ] **L9** The same invocation observed twice — the hook registered twice, or two host
      signals for one finish — yields one finish record.
- [ ] **L10** A simulated four-phase run in `tests/guardrails.test.sh` asserts the record
      count and the presence of every L2 field, per phase.
- [ ] **L11** The `model` recorded for an invocation is the model that invocation actually
      ran under, or `unknown`. It is never a default the ledger assumed. If it is derived
      from the agent definition rather than observed, the ledger states that it is derived
      — otherwise the first per-spawn model change silently makes every historical row a
      lie, which is the exact comparison the later routing work depends on.

### Attribution (source R1.2)

- [ ] **P1** `loop-protocol`'s task envelope documents `Unit:` and `Slice:` as mandatory
      fields, with `Slice` omitted for the spec and slice phases.
- [ ] **P2** `/loop`, `/slice`, and `/verify` all set both when briefing, everywhere they
      brief.
- [ ] **P3** All four agents echo `Unit` and `Slice` in their return, so a mis-brief is
      visible in the return a human reads and not only in a file nobody opens.
- [ ] **P4** An agent briefed without them says so in its return rather than inventing a
      value or staying quiet.

### Rework (source R1.3)

- [ ] **W1** Per **D3**, an agent invocation that needed at least one refine pass is marked
      `phase_detail: "rework"` **in full** — its whole token cost, not a portion of it. An
      invocation that reached green without one is not marked.
- [ ] **W2** "Needed a refine pass" means what `enforce-refine-cap.sh` already means by a
      repeat failure: a second consecutive failing run of the same target. A normal
      red → implement → green rhythm is **not** rework. Under any other reading every
      invocation is rework and the metric reads 100% forever.
- [ ] **W3** Rework is separable from first-attempt work by reading the ledger alone — no
      transcript, no inference, no re-derivation by whoever reads it later.
- [ ] **W4** The whole-invocation granularity, and what it therefore does and does not
      measure (D3), is stated in writing next to the ledger. A reader who takes the figure
      for "tokens spent retrying" will misread it, and the file has to prevent that itself.
- [ ] **W5** Refine passes within an invocation are recorded as a **count**, and that count
      is never converted into a token figure.
- [ ] **W6** A tripped refine cap produces a terminal record naming the slice and its
      rework total at the D3 granularity.
- [ ] **W7** Guardrail test cases discriminate the two directions: a simulated
      red → red → red invocation is marked rework in full and carries a pass count; a
      simulated red → green invocation is not marked, and neither is red → green → red →
      green.
- [ ] **W8** The refine cap's own behaviour is unchanged. The same sequences block and
      allow as they do today, `.claude/loop-refine-passes.tsv` keeps its current semantics,
      and its existing test cases pass unmodified. This work may read that state; it may
      not repurpose it.

### Hygiene (source R1.4)

- [ ] **H1** The ledger is written under `.claude/` and never inside `docs/loop/`.
- [ ] **H2** It is bounded at a configurable line count, default 5,000, oldest-first
      eviction. The bound holds after a run that would exceed it.
- [ ] **H3** Eviction never corrupts a concurrent append and never truncates the file to
      empty.
- [ ] **H4** `.gitignore` covers it. A `git status` after a `/loop` run shows no ledger.
- [ ] **H5** Deleting the ledger mid-run breaks nothing: the next event recreates it, and
      no run fails because it was gone.

### Cache-friendly ordering (source R4.1)

- [ ] **C1** `loop-protocol` states the invariant-first, volatile-last ordering as a hard
      rule, with its reason stated alongside it — a single volatile token near the front
      invalidates the whole cached prefix behind it. The reason is load-bearing: a rule
      whose rationale is not written down gets reordered by the next person who finds it
      inconvenient.
- [ ] **C2** No agent file and no command brief interpolates a timestamp, run id, or
      counter above the per-unit-of-work section.
- [ ] **C3** A grep-based case in `tests/guardrails.test.sh` fails when a volatile-looking
      interpolation appears in the top half of any `agents/*.md`.
- [ ] **C4** Where a finish payload exposes cache-read tokens, the ledger records them;
      where it does not, the field is absent rather than zero (L3). Reporting a hit rate is
      **not** in this unit — see Non-goals.

### This repository's own gates

- [ ] **X1** `bash tests/guardrails.test.sh` is green, `shellcheck -S warning scripts/*.sh`
      is clean, every new script carries the executable bit, and the harness case count is
      higher than it is today.
- [ ] **X2** Both existing guardrails behave exactly as they do now — same exit codes, same
      `LARAVEL_LOOP_REFINE_CAP` / `LARAVEL_LOOP_ALLOW_UNTESTED` overrides, same
      subagent-only scoping. Their existing cases pass unmodified.
- [ ] **X3** Every script named in `hooks/hooks.json` exists and is executable, so the
      harness's structure check still passes with the new registration in place.
- [ ] **X4** README documents the ledger the way it already documents the other two state
      files: what writes it, where it lives, what it records, how to disable or delete it,
      and that it never leaves the machine. A plugin that quietly starts recording
      telemetry into someone's repository is a surprise, and this repo's existing README
      does not spring surprises.

### The condition for calling this done

- [ ] **DC1** The ledger produces believable numbers across **5 or more real units of
      work** — totals that a human who watched those runs recognises, with the share of
      unpriced invocations (E5) stated rather than hidden.

**DC1 is not a G2 criterion.** Verify can only check that the code does what the spec says
against fixtures. DC1 needs real runs over real time, and it is the source document's
stated gate for proceeding to v0.3. Passing G2 means this is built; passing DC1 means it is
trusted. Do not let the first be reported as the second.

## Traceability

Every acceptance checkbox in the source document under R1.1–R1.4 and R4.1, and where it
went. Nothing here is dropped silently.

| Source AC | Here | Note |
|---|---|---|
| R1.1 · one start + one finish per invocation | L1 | Sharpened by E4: "never two finishes" is now explicit |
| R1.1 · resolvable slug, `unknown` not dropped | L4 | |
| R1.1 · concurrent appends do not corrupt | L5 | |
| R1.1 · hook exits 0 unconditionally | L6, L7 | Split: exit code, and never blocking |
| R1.1 · degrades with no `jq`, no `python3` | L8 | |
| R1.1 · guardrail test, 4-phase run | L10 | |
| R1.1 · field list | L2, L3, L11 | L3 and L11 added from E2/E5/E6 — missing must not read as zero, model must not be assumed |
| R1.2 · protocol documents both fields | P1 | |
| R1.2 · all three commands set them | P2 | |
| R1.2 · all four agents echo them | P3, P4 | |
| R1.3 · post-first-failure events tagged `rework` | W1, W2 | Granularity settled by **D3**: whole invocation, not the retried portion |
| R1.3 · cap trip emits terminal rework cost | W6 | |
| R1.3 · rework separable "in any report" | W3, W4 | Restated as separable **in the ledger**; reports are v0.3 |
| R1.3 · red→red→red test | W7 | Widened to test both directions — the discriminating case is the invocation that is *not* rework |
| R1.4 · configurable cap, oldest-first | H2, H3 | |
| R1.4 · `.gitignore` covers it | H4 | |
| R1.4 · under `.claude/`, never `docs/loop/` | H1 | |
| R4.1 · ordering documented as a hard rule | C1 | |
| R4.1 · no volatile interpolation above section 4 | C2 | Scope boundary settled by **D5**: literal wording only |
| R4.1 · grep-based test | C3 | |
| R4.1 · ledger records cache-reads **and report shows hit rate** | C4 (first half only) | **Deliberate cut.** The report is R5.1, which §9 assigns to v0.3. Recording is in; rendering is not |

## Non-goals

Read these out loud at G0. This is a measurement unit inside a document full of tempting
optimisations, and every one of them looks like a small addition from here.

**Not in this unit because §9 assigns them to a later release:**

- **No `/cost` command, no report, no summary, no rendering of any kind** (R5.1, R5.2 —
  v0.3). The ledger is written and read by nobody in v0.2. This is deliberate: a report
  built on numbers nobody has sanity-checked against five real units teaches people to
  trust a figure before it has earned it.
- **No budgets, no thresholds, no warnings, no gates on spend** (R2.1, R2.2 — v0.3). No
  `LARAVEL_LOOP_BUDGET_*`. Nothing in this unit ever stops, pauses, or prompts because of
  cost.
- **No model or routing changes at all** (R3.1, R3.2 — v0.4). `loop-spec` and `loop-slice`
  stay pinned to Opus in frontmatter; `loop-build` and `loop-verify` stay on Sonnet. This
  unit does not touch a `model:` line. It exists precisely so that change can later be
  judged against a baseline instead of a hope.
- **No context budget in the envelope** (R4.2), **no bounded memory files** (R4.3), **no
  full-suite guardrail** (R4.4), **no scoped verification** (R4.5), **no storage hygiene or
  worktree cleanup** (R6). All v0.3/v0.4.

**Not in this unit at any point, per the source document's own §8:**

- **No pricing.** Tokens and durations only. No dollar figure, no rate card, no currency.
  A rate table in a repo is wrong within a quarter and nobody notices.
- **No gateway, proxy, or provider fallback chain.** Wrong layer of the stack.
- **No semantic caching.** Needs an embedding store; wrong shape for a zero-dependency
  plugin, and a near-miss cache hit is a correctness bug.
- **No SaaS, no hosted dashboard, no network call, no account.** The ledger is a local
  file. Anyone who wants it elsewhere can ship it there themselves.
- **No cost-based auto-degradation.** Nothing ever silently switches to a cheaper model
  because spend is high. That trades a visible cost for an invisible quality loss.

**Not in this unit because of what this repository already is:**

- **Not a live dashboard.** Guild's `laravel-team:board` already streams subagent lifecycle
  events to `.claude/agents-board.jsonl`, and it is installed alongside this plugin
  routinely. This ledger answers a different question — cost per unit of work and per
  slice, with rework separated — which Guild's feed structurally cannot, because it does
  not know what a slice or a first attempt is. **This unit never reads, writes, imports, or
  depends on Guild's feed, and never replaces it.** Both files coexist.
- **No fifth agent, and no agent behaviour change beyond echoing two fields.** The team is
  four. Measurement is on the deterministic side of the protocol's determinism boundary.
- **No new runtime dependency.** Nothing requiring `jq`, `python3`, node, composer, or PHP
  to be present in order to work.
- **No retroactive backfill.** Past runs are gone. The ledger starts empty.
- **No change to the refine cap or to `loop-refine-passes.tsv`'s semantics.** This unit may
  read that state. It may not extend, reshape, or take ownership of it.
- **No new artifact under `docs/loop/<slug>/`.** Cost data is local telemetry, not part of
  a unit's contract.

**Raised while framing and deliberately not adopted.** Building either is out of bounds;
adding one later is a new intent, so that it stays a decision someone makes rather than
one that accretes: a per-invocation dollar estimate derived from a hard-coded rate table,
and a `.claude/` state-file cleanup command covering all three state files at once.

## Failure modes

| When | Expected behaviour |
|---|---|
| The slug cannot be resolved for an invocation | Record written with `slug: "unknown"`. Never dropped, never inferred from the working directory or the last-seen unit |
| An agent is briefed with no `Unit` line | The agent's return says so (P4). The ledger's `unknown` is the symptom; the return is where it gets caught |
| Two invocations finish at the same instant | Both records land intact. No interleave, no truncation, no lost line |
| The hook is registered twice — plugin install plus manual install | One record per invocation, not two. This has already happened in the prior-art project |
| `PostToolUse` and `SubagentStop` both fire for one invocation (E4) | Exactly one finish record. The invocation is counted once |
| An invocation was launched async: finish payload carries `async_launched` and no tokens (E5) | Token fields null with a status that says why. **Never zero.** The gap is visible in the ledger and is part of what DC1 judges |
| The payload carries no input/output split (E6) | Combined total recorded; split fields null. No arithmetic invents a split |
| The payload carries no cache-read tokens (E6) | Field absent. Cache-read share is *unavailable*, which is not the same as 0% and must never render as one |
| The model cannot be observed for an invocation | `unknown`, or a derived value the ledger declares as derived (L11). Never an assumed default |
| Neither `jq` nor `python3` is present | Hook exits 0, writes nothing corrupt, the run is unaffected |
| The payload is malformed, empty, or an unexpected shape | Hook exits 0 and writes nothing rather than writing a partial line |
| The ledger path is unwritable, or `.claude/` cannot be created | Hook exits 0 silently. No crash, no error surfaced into the agent's context, no block |
| The hook itself throws | Exits 0. A failure in cost accounting is never a failure of the work being accounted for |
| The ledger hits its line cap mid-run | Oldest lines evicted, newest retained, and a concurrent append is not corrupted by the eviction |
| A human deletes the ledger mid-run | Next event recreates the file. Nothing errors, and the run does not stop |
| A slice trips the refine cap | Terminal record with that slice's rework total at the D3 granularity (W6). The cap still blocks exactly as it does today (W8) |
| A `loop-build` invocation does red → green → red → green | Not rework. Normal TDD rhythm must never read as a quality problem, and the existing cap already draws exactly this line |
| A `loop-build` invocation needed one refine pass and then went green | Rework **in full** (D3), including the part that was a first attempt. Deliberate over-attribution — the alternative was inventing a split |
| Someone reads "rework share" as tokens spent retrying | The ledger states what the figure actually measures: the cost of slices that were not right first time (D3) |
| Someone compares a v0.2 rework figure to the source document's <15% target | Not comparable — that target was written against a narrower definition. Reconciling the two belongs to v0.3's reporting work |
| Someone reads the ledger and totals it as a bill | The file says plainly it counts tokens and durations, not money |
| Someone treats a v0.2 total as trustworthy before DC1 | The unit is not done until DC1. Verify's PASS is not DC1, and this spec says so in both places |
| Guild is installed too and is also hooking `Agent|Task` | Both hooks fire, both files are written, neither reads the other, neither breaks |
| A commit is prepared after a `/loop` run | The ledger is not in it (H4) |

## Constraints

**Given by the source document — settled, not open.** Treat these as inputs, not decisions
to revisit at slice time: the ledger is JSONL at `.claude/loop-cost.jsonl`; the field list
is the one in R1.1; the default line cap is 5,000; the mechanism is a hook on the subagent
tool; the envelope gains `Unit:` and `Slice:`; the ordering is the five-level one in R4.1.
Reopening any of these is a new intent.

**Existing behaviour that must not change:**

- Both guardrail scripts: exit codes, `LARAVEL_LOOP_REFINE_CAP` and
  `LARAVEL_LOOP_ALLOW_UNTESTED`, subagent-only scoping via `agent_type`, and the fact that
  a human on the main thread is never blocked.
- `.claude/loop-refine-passes.tsv`'s format and meaning.
- The four-agent team, and README's and CHANGELOG's claim that it is four.
- Standalone from Laravel Guild: separate agents, skills, env vars, and state files, no
  collision when both are installed.
- The protocol's ≤10-line return shape. `Unit`/`Slice` must fit inside it, not extend it.
- `hooks/hooks.json`'s existing `Bash` registrations, which the two existing guards depend
  on.

**Repo conventions this lives inside:**

- Zero-dependency bash plus coreutils for anything executable, degrading `jq` → `python3` →
  a safe no-op, matching both existing scripts. Clean under `shellcheck -S warning`,
  executable bit set, tested by `tests/guardrails.test.sh`. CI runs exactly these.
- This repo has no PHP, no composer, no artisan. The Laravel-facing parts of the plugin are
  markdown; the testable surface is bash.
- Hook scripts carry a header comment explaining *why* they are wired to the event they are
  wired to. Both existing scripts do; this one is expected to.
- `docs/loop/conventions.md` and `docs/loop/decisions.md` exist and are empty templates.
  Nothing here can rely on a taught rule, and nothing here has been previously rejected.

**Hard limits:**

- **The ledger observes and never steers.** No hook added by this unit may block, delay,
  reorder, or alter a spawn, under any condition including its own failure.
- Nothing leaves the machine. No network call, no credential, no account.
- G4 is not crossed. Nothing touches live infrastructure.

## Decisions taken at G0

Recorded here because a resolved question that leaves no trace gets re-litigated. Any of
these reopening is a new intent, not a mid-build adjustment. All five were the recommended
default; D3 was tightened by the human beyond what was recommended, and that difference is
recorded rather than smoothed over.

**D1 — A combined-token-only ledger is acceptable for v0.2.** (Source OQ1.) The
input/output split and cache-read tokens stay **best-effort**: recorded where the payload
carries them, null where it does not, and depended on by no acceptance criterion. Rationale:
cost per unit, per phase, and per slice is fully answerable from a combined total, and that
is the question v0.2 exists to answer. Consequence to state plainly: §10's "cache-read share
> 40%" is **unmeasurable** until the payload is inspected for real (E6), and v0.3's
reporting work must not print a 0% where it means unavailable.

**D2 — R4.1 ships on its rationale alone.** (Source OQ3.) Whether prompt caching is active
for subagent invocations, and at what minimum prefix length, stays unresolved (E7) and does
not block. It is an ordering rule plus a grep test; the cost is near zero and the downside
of being wrong is nil. Its payoff is deliberately unmeasured in v0.2.

**D3 — Rework is priced at whole-invocation granularity.** The one that was blocking. All
refine passes happen inside a single `loop-build` invocation and tokens arrive once, at that
invocation's finish (E2), so per-pass tokens are **not separable** on the evidence available.
Therefore: **if a slice needed any refine pass, that build invocation's full cost counts as
rework** — not merely the retried portion.

Rejected: dividing or estimating tokens across passes. A fabricated number defeats the
ledger's entire purpose, which is to be believed.

Three consequences, all of which belong in the file itself (W4):

- This deliberately **over-attributes**. An invocation that hit one refine pass and then
  went green is 100% rework, including the part that was a genuine first attempt. The bias
  is toward reading high rather than falsely low, which is the right direction for a
  quality signal.
- What the figure therefore measures is *the cost of slices that were not right first time*,
  not *the cost of retrying*. Those are different quantities and the second is the one a
  reader will assume.
- The source document's `< 15%` target in §10 was calibrated against the narrower
  definition and is **not comparable** to a figure produced this way. Reconciling the target
  belongs to v0.3's reporting work, not here.

**"Needed a refine pass" is pinned to the existing guard's meaning** — a second consecutive
failing run of the same target, exactly as `enforce-refine-cap.sh` already counts it, with a
green run resetting. Not simply "a test failed once". Under the looser reading every
invocation is rework, because writing a failing test first *is* the prescribed rhythm, and
the metric would read 100% forever. The source document's own red → red → red test AC
("pass 1 not rework") points the same way.

**D4 — Ship even if async-launched build agents report no tokens.** (E5.) `/loop` runs 2–3
independent slices concurrently; if that is async launching, the largest spender is the
least observable. The gap is **surfaced loudly, never estimated around**: unpriced
invocations are recorded as unpriced with a status saying why (L3), and the unpriced share
is part of what DC1 judges. Making it visible in a report is v0.3's job, consistent with the
C4 cut. If that share turns out large at DC1, closing it becomes its own intent.

**D5 — `{{args}}` in `commands/loop.md`'s title stays where it is.** R4.1's scope is its
literal wording — timestamp, run id, counter — and `{{args}}` is none of those. Whether a
command file's line order even determines the assembled prompt's prefix is unknown while D2
stands, so moving it is a readability cost paid for an unverified benefit. C2 and C3 are
bounded accordingly. Revisit if caching ever becomes observable.

## Open questions

None. All five were resolved at G0 and are recorded above as D1–D5.
