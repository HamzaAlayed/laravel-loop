# Log — cost-ledger-blind-to-background-agents

Closed 2026-08-17. Verdict at G2: **PASS**, no blocking findings, no concerns.

The unit that taught the ledger to be honest about what it cannot see, and gave it a
deliberate, marked way to be told.

---

## Phase 1 — Spec (G0)

**Artifact:** `spec.md` — CL1–CL9 (what the tooling may claim), RC1–RC7 (recovering the
figure), X1–X6 (this repository's own gates), plus DC4/DC5 and five non-goal groups.

The framing that mattered: the problem is not "how do we log more". It is *what may these
tools legitimately claim when they can observe only a minority of real spend* — and, given
the missing figure demonstrably exists, should they be claiming so little at all.

**Gate G0 decisions:**

| Question | Decision |
|---|---|
| OQ1 — claim, recover, or both? | **Both, claim first.** CL lands independently of whether recovery is reachable, so the unit cannot deliver nothing. |
| OQ2 — can a hook reach the channel? | **Unknown. A spike answers it by experiment before any recovery design.** |
| OQ3 — a coverage floor? | **Human-set; unset means today's behaviour.** No number ships. |
| OQ4 — trade `/loop`'s parallelism for coverage? | **Out of bounds.** |
| OQ5 — must a recovered figure stay distinguishable? | **Yes, permanently**, following `model_source`'s precedent. |

## Phase 2 — Slice (G1, twice)

**Artifact:** `slices.md`, in two passes.

**First pass — S1–S6.** Six slices, S1 ∥ S6 the only parallel pair. S2/S3/S4 were
explicitly *refused* parallelism: all three rewrite one region of `cost-report.sh`, and
calling them independent would have been the G1 defect `worktree-merge` warns about.

The RC group was deliberately **not cut** in this pass. A slice envelope is a design
commitment — it names files, outputs and tests — and G0 forbade one before the spike
returned.

**Second pass — S7–S11**, after S6 answered OQ2. Zero parallel. The distinguishing marker
lands two slices before any writer exists, so no transcribed figure can ever sit in a
ledger that cannot yet say what it is.

**Gate G1 decisions:** first pass approved as cut, S1 and S6 in parallel. Second pass
approved S7–S10; **S11 held**, not rejected — it serves no RC criterion and automating
transcription before a human has eyeballed one was judged premature.

## Phase 3 — Build

Ten slices, ten merge commits, full suite green after **each** merge rather than only the
last. Harness 334 → 404 cases.

| Slice | What it delivered |
|---|---|
| S1 | A reason per unpriced invocation, from the finish record's `status` alone. A launch stopped being presented as a finish. |
| S2 | Coverage as a percentage share; wholly-unobserved phases named. One shared formatter, so the budget gate inherited it for free. |
| S3 | The report says *why* the gap exists — measured by the host, delivered into the session, not captured here. |
| S4 | `LARAVEL_LOOP_COST_MIN_COVERAGE`. Below it, no unit total. Unset means today's behaviour, byte for byte. |
| S5 | README and the in-place correction of a superseded `decisions.md` claim. |
| S6 | **The spike.** Answered OQ2 by experiment. |
| S7 | The reader understands an `event:"recovered"` line: counted once, counted priced, labelled transcribed. |
| S8 | When observed and transcribed disagree, both print, with the precedence rule stated in the output. |
| S9 | `scripts/record-recovered-cost.sh` — the only writer. Five refusal paths, exit 0 on every one. |
| S10 | Documented what a transcribed figure is; recorded the second G1's decision. |

**What S6 settled.** Every hook event the build exposes except `SubagentStop` was
registered against a throwaway project dir; identical foreground and backgrounded subagents
were launched. **No hook of any registered type fired for the background completion.** The
figure arrives as a queued synthetic user turn injected into the transcript — a queue
operation on the conversation, not an event on the hook bus. There is no channel name a
`hooks.json` entry could subscribe to. Corroborated by grepping the installed binary's own
string table for every `hook_event_name` literal.

That is OQ2 answer 2: recovery is possible, but only as the orchestrating agent
transcribing a figure from its own context. A model-reported number. The human approved it
at the second G1, with OQ5's permanent marker as the condition.

## Phase 4 — Verify (G2)

**Artifact:** `verify.md`. **Verdict: PASS**, scoped to the changed surface.

The verifier did not take the builders' word for anything. It reproduced the harness
itself; reverted the implementation in an isolated scratch copy and got 31 failures, every
one mapping to a CL or RC case, confirming red-before-green was real rather than claimed;
injected a digit into a scratch README to prove the "no number ships" guard can itself
fail; and proved RC7 by absence — zero-line diffs on `record-cost-event.sh` and
`hooks/hooks.json`, which is also the direct evidence S11 was not built.

It declared what it did **not** verify: DC4 and DC5 need a real `/loop` run with background
lanes and a human's own eye, which the harness structurally cannot exercise. Those were not
folded into the PASS.

**Gate G2 decision:** approved, close the unit.

---

## What is still open, deliberately

- **S11** — approved-but-held. Revisit after one transcription has been done by hand and
  checked by eye, which is what DC5 asks for anyway.
- **DC4 and DC5** — require a real `/loop` run and a human's eye. Not closable by harness.
- **`cost-measurement-v0.2`'s DC1** and **`cost-reporting-v0.3`'s DC2/DC3** — untouched by
  this unit.
- **Transcript scraping** — surfaced at the second G1 and put out of bounds. The same figure
  appears in the session transcript *host-observed* rather than model-reported, which would
  sidestep the transcription objection entirely. It reads conversation logs outside the
  project directory, so it is a different consent conversation and deserves its own intent.

## The unit measuring itself

At close the ledger reported **46 % coverage, "wholly unobserved: verify"** — reporting its
own blind spot, in its own output, about the verification that had just passed it.

Coverage moved with launch mode, not with code: it sat at 50 % when the first two lanes ran
backgrounded, rose to 75 % while the sequential slices ran in the foreground, and fell back
as later lanes were backgrounded again. That is the unit's own thesis, demonstrated on
itself.

## Cost

Coverage: based on 7 of 15 invocations that carry a token figure (7 unpriced, not counted) -- 46 % coverage; wholly unobserved: verify

Tokens: 888430 (priced subset only, partial -- 7 unpriced invocation(s) not counted)

Rework: this figure counts whole invocations that needed at least one refine pass, at
whole-invocation granularity -- deliberately over-attributing rather than estimating a
per-pass split, and NOT the cost of retrying. It is not comparable to the requirements
document's <15% target (Sec.10), which was calibrated against a narrower, per-pass
definition. No pass/fail verdict against that target is printed here.
  count: 0 of 15 invocation(s) marked rework
  token share: unavailable (no priced invocations are marked rework)

