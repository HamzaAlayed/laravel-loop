---
name: verify-playbook
description: "Gate G2's method — walking acceptance criteria one at a time against the tests that prove them, the test-quality heuristics that catch an assertion which cannot fail, tracing a failure that has nothing to do with the diff before blaming the diff, the cheap Laravel checks that find real defects, and how a scoped verdict declares its own scope. Use before issuing any PASS / CONCERNS / FAIL, when a criterion has no obvious covering test, when a test fails for a reason the diff cannot explain, or when verifying only part of a unit."
---

# Verify Playbook

Gate G2's procedure. Verify is the phase that drifts silently: a verifier that gets gradually laxer emits no signal at all until defects reach production.

## Walk the criteria, one at a time

Open `docs/loop/<slug>/spec.md`. For each acceptance criterion, answer two questions in order — the second is the one agents skip:

1. **Does a test prove it?** Name the test. "The code looks right" is not an answer.
2. **Does that test actually run?** Filtered out, in a skipped group, or in a file the suite does not collect — a test that does not execute proves nothing and is indistinguishable from a test that does not exist.

A criterion with no covering test is a **finding even when the code is obviously correct**. The loop's entire claim is that behaviour is provable; an unproven criterion voids that claim regardless of how sound the implementation looks.

Record one row per criterion. Never collapse several criteria into "all covered" — that sentence is what a lax verify pass produces.

## Test-quality heuristics

Read the tests. Counting them measures effort, not coverage.

| Smell | How to spot it | Why it matters |
|---|---|---|
| Assertion that cannot fail | `assertTrue(true)`, `assertNotNull` on a literal, a bare `expect($x)` with no matcher | The test is a placeholder wearing a test's name |
| Asserting on the test's own input | The expected value was set by the test two lines earlier, never round-tripped | Proves assignment works, not the behaviour |
| Happy path with no sibling | One test per feature, all green-path | Every named failure mode in the spec is a criterion; unproven is unproven |
| Authorization in one direction | Asserts the permitted actor succeeds, never that the forbidden one is denied | The denial is the security property; the success is the feature |
| Weakened or deleted test | `git diff <base>...HEAD -- tests/` — look for removed assertion lines, widened expectations, added `->skip()` | This is the failure mode both guardrails exist to prevent; check it explicitly, every time |

Run the diff check as a command, not from memory:

```bash
git diff <base>...HEAD -- tests/ | grep -E '^-' | grep -vE '^---'
```

Any removed assertion is a FAIL until the diff explains why, in writing, somewhere a human read.

## Trace an unrelated failure before you blame the diff

A test failing for a reason the diff cannot explain, reported as an undifferentiated FAIL, sends the slice back to a builder who did not cause it — who then spends refine passes on someone else's bug and hits the cap.

Before writing the verdict: establish whether the failure is **in** the diff's blast radius. Climb `loop-debug`'s isolation ladder — rungs 1, 2 and 4 are the ones that matter here (fails alone? failed before the change? touches anything you changed?). Then report what you found:

- **Caused by the diff** → FAIL against this slice, with the assertion.
- **Pre-existing red** → say so explicitly. Not this slice's FAIL. It is a finding about the base, and hiding it inside this verdict loses it.
- **Environmental** (stale autoload, uncached config, missing test DB) → fix nothing, report the reproduction step. A verdict that blames code for an environment is a verdict that gets ignored next time.

## The `Do NOT` diff check

Diff the branch against the slice's out-of-bounds list. **Scope creep that improves the code is still scope creep** — it was not specified, not reviewed as part of this slice, and it widens the diff a human has to hold in their head at G2.

Report it. Do not praise it. "Also refactored X while here" is a finding, and its quality is irrelevant to that.

## Cheap Laravel checks with real yield

Six checks, each a grep or a read, each catching a class of defect that survives a green suite:

| Check | Where to look |
|---|---|
| N+1 in anything list-shaped | Index/collection endpoints, Blade loops touching a relation, missing `with()` |
| State-changing route with no Policy | `route:list` for POST/PUT/PATCH/DELETE, then the controller for `authorize()` |
| Mass assignment unfiltered | `create(`/`update(` fed from a request without a Form Request narrowing it |
| `env()` outside `config/` | `grep -rn "env(" app/ routes/` — anything here breaks under `config:cache` |
| New query shape, no supporting index | A new `where`/`orderBy` column against the migration set |
| Migration with no `down()` | An empty or absent `down()` is an un-rollbackable release |

## Declare the scope of the verdict

**The changed surface** = the files in `git diff <base>...HEAD`, plus every test that exercises them, plus every caller of a changed public signature. Derive it, do not estimate it:

```bash
git diff <base>...HEAD --name-only                    # the surface itself
git diff <base>...HEAD --name-only | xargs -I{} grep -rln "$(basename {} .php)" app/ tests/
```

A verdict covering only that surface is legitimate — and **must say so in the verdict line itself**. A scoped PASS that reads like a full PASS is the most expensive sentence in this playbook, because the gap between what was checked and what a reader believes was checked is invisible.

```
**Verdict:** PASS — scoped to the changed surface (7 files, 12 tests). Full suite not re-run.
**Verdict:** PASS — full suite reproduced green.
```

Both are honest. Only one of them is true at any given time.

## Verdict discipline

Verdict first, evidence attached. A human reading the report should know the answer before they know the reasoning.

The thresholds are fixed and are not yours to renegotiate: any unproven criterion, any assertion that cannot fail, any weakened or deleted test, any authz gap on a state change, or a green claim that does not reproduce → **FAIL**. Everything specified proven but something worth fixing → **CONCERNS**. Criteria proven, nothing out of bounds, evidence reproduces → **PASS**.

Do not soften a FAIL because the work is nearly there — "nearly" is exactly what CONCERNS is for. **A verifier that negotiates its own verdicts is worth nothing**, and the negotiation is invisible to everyone downstream.

## What this playbook cannot tell you

It cannot tell you the spec was right. Verify checks built work against stated criteria; a criterion that was wrong at G0 will pass here and fail in production. If the spec itself looks wrong, that is a finding for the human at G2 — not a verdict you can express in PASS / CONCERNS / FAIL.
