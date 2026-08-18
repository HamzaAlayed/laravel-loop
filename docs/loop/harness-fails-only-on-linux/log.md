# Log — harness-fails-only-on-linux

**Closed 2026-08-18.** Verdict at the second G2: **PASS**, scoped to everything checkable without
a push. A1, A2's resolved-tree half, and A4's cross-job comparison were held outside it and are
recorded below against the real run.

The first G2 pass returned **CONCERNS** — see *Phase 5* — and that is part of this unit's record,
not something the close paves over.

The unit that fixed the two Linux failures, added a second platform — and shipped one real
regression doing it.

---

## Where it came from

The `ship-gate-blind-to-ci` unit unblocked CI's `scripts are executable` step, which let
`guardrail tests` run on the Linux runner **for the first time in the surviving history** — every
one of the twelve prior runs had *skipped* it. It immediately failed two cases that pass on the
maintainer's macOS host. Captured with `/observe` as `intent.md`, which recorded the earliest run's
cause as `unknown` rather than inferring it.

## Phase 1 — Spec (G0)

**Artifact:** `spec.md` — A1–A9, twelve non-goals, four open questions.

The framing that mattered: the problem is not "two tests fail on Linux" but that *the project's
only automated proof that it works gives one answer on the maintainer's machine and a different
answer on the machine guarding every push — and how far apart the two answers are is not known.*
A2 made that unknown floor a criterion rather than a footnote.

**Gate G0 decisions:**

| Question | Decision |
|---|---|
| OQ1 — is each case wrong, or the code it exercises? | **Neither is resolvable without reading it. A read-only spike first, per case.** |
| OQ2 + OQ3 — should the portability contract be two-directional, and what enforces it? | **Yes, enforced by the guarding checks covering both platforms — CONTINGENT on a spike showing a hosted runner can reproduce bash 3.2.** |
| OQ4 — how much of the unknown floor does this unit close? | **Establish the floor first, then scope.** |

## Phase 2 — Slice (G1, twice)

**First pass:** four read-only spike slices (S1–S4), all genuinely parallel, and the fix group
**deliberately left uncut** — the same precedent as the RC group behind S6's spike in
`cost-ledger-blind-to-background-agents`. Run at three lanes rather than the slicer's proposed
four, to stay inside the protocol's 2–3 cap without altering any envelope.

**What the spikes found:**

| Slice | Finding |
|---|---|
| S1 | The floor is **2**, and **all 421 cases executed** — ratified independently by the harness's own final case-count assertion passing on the runner. Still recorded as a lower bound, because the suite shares mutable state across cases. |
| S2 | **Case A is not a Linux bug.** The platform hypothesis was *refuted* — 20/20 trials across two Ubuntu versions, two bash versions, two CPU allocations all settled at cap. The real defect, found by *reading*: a lock-loser never retries and the winner gives up after 5 attempts, so the declared cap has no convergence guarantee under enough append pressure. |
| S3 | **Case B is wrong, and the safety property holds.** apt installs shellcheck to `/usr/bin`, inside the fixture's own hard-coded allow-list, so the PATH pruning never created absence. Separately verified — as instructed — that `not-run → hold` holds on Linux, corroborated on the *real* runner by the sibling case passing on the very run that failed case B. |
| S4 | **The contingency clears.** `macos-latest` (arm64) reports `Bash 3.2.57(1)-release` and arm64, both exact matches, cited to pinned `actions/runner-images` manifests — with its own limit stated: a manifest is not proof. |

**Second pass (S5–S8)**, cut against that evidence and the second G1's four decisions. One
genuinely concurrent lane; S5, S6 and S8 all touch `README.md:167`'s literal, which the suite's
last case asserts, so any two in flight conflict by construction. Deltas pinned +2/+1/0/+2 → 426.

**Gate G1 (second) decisions:** approved as cut; two lanes (S5 ∥ S7), S7 merged after S6 for
evidence hygiene. Two pairings refused with reasons: both fixes in one slice (A3 fails a group
decision), and S7+S8 merged (the claim would land in the same commit as the thing it claims).

## Phase 3 — Build

Eight slices total, eight `--no-ff` merges, full suite green after **each** rather than only the
last. Harness 404 → 421 (spikes added none) → **426**.

| Slice | Delivered |
|---|---|
| S5 | The eviction convergence gap closed. Falsified as mandated: **5/5 red against a copy of the pre-fix script** (14,487–15,559 lines against a cap of 15) and 5/5 green after. |
| S6 | Case B's trigger now discovers where shellcheck actually resolves and excludes that, plus a new case asserting the precondition the old fixture only assumed. |
| S7 | A second `guardrails-macos` job with distinctly-named steps, and `checks.md` updated in the same commit. Demonstrated the red first: `missing 3` → 420/1 → green. |
| S8 | The claimed-platforms statement, with an evidence producer per platform and S4's citation-is-not-proof limit in the same place as the claim. |

**A landmine caught at G1 rather than on a pushed run:** four ship cases assume shellcheck is on
`PATH`, and the macOS image manifest lists none — so S7 installs it in the macOS job, pinned in the
envelope instead of discovered as a surprise red.

## Phase 4 — Verify (G2)

**Artifact:** `verify.md`. **Verdict: CONCERNS.**

Every criterion this pass owns is proven, every `Do NOT` holds — and S5 shipped a **real, reproduced
regression**. The eviction loop went from a fixed 5-attempt bound to `while :;`, and a persistently
failing `mv -f` falls through all four of its breaks and loops forever. Reproduced twice
independently (209 iterations in 3s under `chflags uchg`; 501 iterations in the orchestrator's own
re-check), and confirmed *new* — the pre-fix bounded loop always terminated.

The part that makes it more than cosmetic: it contradicts `record-cost-event.sh`'s own header
contract, which S5 left in place — *"Exits 0 on every path … cost accounting must never block,
delay, or alter a spawn."* A stuck evictor never reaches `rmdir` or `return 0`.

The verifier also confirmed the stale-lock widening is **pre-existing, not introduced**, but noted
that it and the `mv` path now **compound**: two independent routes reach the same
permanently-stuck-lock state where before there was one.

**Gate G2: not resolved.** A CONCERNS verdict is the human's to act on.

---

## What was open at the first G2 — superseded, kept for the record

*This section records the state on 2026-08-17, when the verdict was CONCERNS. It is left in place
because the sequence matters; see "What this unit did not close" at the end for the state at close.*

- **The `mv`-failure non-convergence path.** The verifier's own recommendation is to file it as a
  follow-up slice before S5 is treated as closed. That is a **new slice**, so it is a G1 decision
  and deliberately not taken unattended. The design question is real: how to guarantee termination
  *and* convergence, without reintroducing the arbitrary bound the fix removed.
- **A1** — a real Actions run concluding success on both jobs. Nothing is pushed;
  `main` is 19 commits ahead of `origin/main`, all local. The push was deliberately withheld
  because the verdict is not a clean PASS.
- **A2's resolved-tree count** and **A4's cross-job total comparison** — both come off that same
  run.
- **The cost section is deliberately absent.** `scripts/write-cost-log-section.sh` belongs to the
  close step, and this unit is not closed. Every one of this unit's twelve agent invocations was
  backgrounded and landed unpriced — the same blind spot again — and their figures are available in
  the session's own completion notifications for transcription at close.

## The overnight account (2026-08-17 → 18)

Slices S5–S8, all four merges, and G2 ran unattended at the maintainer's request, with the standing
instruction to lead and be reviewed afterwards. What was done: the four approved envelopes built and
merged, full suite after each, lanes cleaned with `git branch -d` so git would refuse anything
unmerged, and the verdict persisted verbatim.

What was **not** done, and why: nothing was pushed (the verdict is not a clean PASS); no fifth slice
was cut for the regression (a G1 decision); no G0 was opened on either waiting intent (both turn on
questions only the maintainer can answer); no tag, release, or version bump; and no recorded
decision was overturned.

One capture was made during a wait — `docs/loop/transcript-scraping-as-a-recovery-path/intent.md` —
which is why an unrelated commit sits inside this unit's range. The verifier was told about it and
correctly excluded it rather than reporting scope creep.

**Continued 2026-08-18**, after the maintainer approved S9's one-line shape and authorised the close:
S9 was built, merged, and re-verified, the unit was closed, and the push was made — all under the
same standing instruction. The push happened only because the second verdict was a clean PASS; the
first, being CONCERNS, had held it back overnight exactly as stated.

---

## Phase 5 — the first G2 said CONCERNS, and it was right

The first verify pass over S5–S8 proved every criterion it owned and every `Do NOT` — then found
that **S5 had shipped a real regression**. Its convergence fix replaced a fixed 5-attempt bound with
`while :;` and left `mv -f ... || rm -f "$tmp"` without a break, so a persistently failing `mv`
looped forever.

Three things made this more than a nitpick:

1. **It was reproduced, not argued.** 209 iterations under `chflags uchg` by the verifier, then 501
   in an independent re-check. The pre-fix bounded loop always terminated, so the regression was
   **new**.
2. **It broke the script's own header contract**, which S5 left in place — *"Exits 0 on every path,
   including its own internal errors: cost accounting must never block, delay, or alter a spawn."*
   A stuck evictor never reaches `rmdir` or `return 0`.
3. **It compounded** with the pre-existing stale-lock gap: two independent routes to a
   permanently-stuck lock where before there was one.

**How it got through.** A 426-case green suite, shellcheck clean, and a verify pass that proved
every other criterion. Nothing in the repository exercised a failing `mv` inside that loop. The
orchestrator had flagged the path as *theoretically* possible before merging and judged it narrow
rather than establishing it — which is the process lesson, recorded in `conventions.md`.

## Phase 6 — S9, and the second G2

**Gate decision:** the one-line form, `mv -f "$tmp" "$OUT" 2>/dev/null || { rm -f "$tmp"; break; }`.
Not a new design — it makes the fourth I/O failure behave like its three siblings, which the loop's
own comment already prescribed. An attempt bound, an iteration counter, a no-progress guard, and
fixing the stale lock alongside were all explicitly rejected and recorded in `decisions.md`.

S9's envelope was cut by the orchestrator rather than `loop-slice`, and says so: the fix and its test
were fully determined by the decision, and `loop-protocol` warns that a full slicing pass on a
one-slice task is pure latency.

**The hard part was the test, not the fix.** Two problems the builder had to solve rather than
assume: the case must not hang the suite (bounded with bash job control per `run_bounded()`, never
GNU `timeout`, absent on stock macOS), and it needed a privilege-free trigger for a persistently
failing `mv` (`chflags` is macOS-only, `chattr +i` needs root) — solved with a `PATH`-stubbed `mv`.
Falsified against `HEAD`: hung to the bound, killed at exit 143, lock left held; then returned in
0.52s, exit 0, lock released.

**Second G2 verdict: PASS.** The verifier built its own repro rather than trusting the builder's, and
ran it against three script versions: pre-S5 terminates, pre-S9 hangs 3/3, post-S9 terminates 3/3.
It confirmed convergence did not regress, and that the compounding is back down to one route — the
evictor-killed-mid-loop path is unchanged and still pre-existing, deliberately out of bounds.

Harness 404 → **427**.

## What this unit did not close

- **The evictor-killed-mid-loop stale lock.** Confirmed pre-existing, scoped out by decision, and
  still open. If the evictor process dies mid-loop the lock directory persists and eviction stops
  permanently thereafter. It deserves its own intent rather than a ride-along.
- **The `mv`-failure fix was verified against one trigger mechanism** (a `PATH`-stubbed `mv`). The
  EDR / SELinux / NFS-lock routes named in the first verdict were never reproduced — only that the
  code path, once entered, now terminates.

## Cost

Coverage: based on 14 of 14 invocations that carry a token figure (0 unpriced, not counted) -- 100 % coverage; 14 of 14 priced figure(s) transcribed rather than host-observed (1650438 of 1650438 priced token(s), 100 %)

Tokens: 1650438 (priced subset only, partial -- 0 unpriced invocation(s) not counted)

Rework: this figure counts whole invocations that needed at least one refine pass, at
whole-invocation granularity -- deliberately over-attributing rather than estimating a
per-pass split, and NOT the cost of retrying. It is not comparable to the requirements
document's <15% target (Sec.10), which was calibrated against a narrower, per-pass
definition. No pass/fail verdict against that target is printed here.
  count: 0 of 14 invocation(s) marked rework
  token share: unavailable (no priced invocations are marked rework)

