---
name: loop-debug
description: "The inner loop's Refine step done as an experiment rather than a retry — classifying a failure as a code, test, or slice defect before pass 1, one falsifiable hypothesis per pass, the isolation ladder, root-cause tracing, and what a useful `blocked` escalation contains. Use on the first red inside a slice, when pass 2 is about to repeat pass 1's guess, when a test passes alone but fails in the whole suite, or when the refine cap is one pass away."
---

# Loop Debug

Step 5 of the inner loop. The cap is 3 passes, so a pass spent guessing is a third of the budget spent learning nothing.

## One falsifiable hypothesis per pass

Write the hypothesis down before editing. If it cannot be wrong, it is not a hypothesis — it is a hope, and it will consume a pass and leave the search space exactly as wide.

```
Pass 1  Hypothesis: the total is wrong because tax is applied before the discount.
        Experiment:  assert the intermediate subtotal, not just the total.
        Result:      subtotal correct, total wrong.
        Eliminated:  ordering. The defect is after the subtotal.

Pass 2  Hypothesis: the discount is applied twice — once in the accessor, once in the total.
        Experiment:  grep for every writer of `discount_amount`.
        Result:      two writers. Confirmed.
        Fix:         remove the accessor's application; the total owns it.
```

Each pass narrows. **Three passes with the same hypothesis is one attempt repeated**, and it trips the cap having proved nothing.

## Classify before pass 1

Most wasted refine passes are a correctly-diagnosed failure handed to the wrong owner. Three classes, three different next actions:

| Class | The tell | Action |
|---|---|---|
| **Code defect** | Test asserts the behaviour the spec named; code does not do it | Refine. This is the only class you fix silently. |
| **Test defect** | Code is right; the test asserts something the spec never said | Fix the test — and **say so in FLAGS**. A changed assertion is a claim about intent, not a fix. |
| **Slice defect** | `Done when` is unreachable from `Context`, or reaching it needs something on `Do NOT` | Return `blocked` **now**. Do not spend a pass. |

**The slice-defect tell worth memorising: you want to edit a file the envelope never mentioned.** That impulse is rarely laziness — it usually means the slice was cut across a seam that does not exist in the code. Grinding cannot repair a bad cut, and passes 2 and 3 will confirm that expensively.

## The isolation ladder

Climb in order. Stop at the first rung that changes your answer — the rungs below it are now about a different failure.

1. **Does it fail alone?** `php artisan test --filter=<OneTest>`. Fails alone → a real defect, keep climbing. Passes alone → jump to *Suite-only failures* below; the ladder does not apply.
2. **Did it fail before your change?** `git stash && php artisan test --filter=<OneTest>; git stash pop`. Already red → you are debugging someone else's bug inside your slice. Say so in FLAGS; do not silently adopt it.
3. **Is it failing for the reason you assume?** Read the assertion line and the actual-vs-expected values. Not the summary line, not the test name. The name says what it was *meant* to prove.
4. **Is the cause inside your diff's blast radius?** `git diff --stat`. If the failing path touches nothing you changed, rung 2 lied or the failure is environmental.
5. **Can you reproduce it deliberately?** A failure you cannot cause on demand is a failure you cannot confirm you fixed — the next green may be luck.

## Root cause, not the nearest symptom

A failure surfaces where a wrong value is **used**, never where it was **produced**. Trace backwards from the assertion to the first point the value was wrong, and fix there.

```
Assertion: expected 100, got 0        ← where it surfaced
  ← the total reads $order->discount  ← still 0 here
    ← discount set in the Observer    ← still 0 here
      ← Observer fires on `saved`, the discount is read on `saving`  ← root cause
```

Patching the total to special-case `0` makes this test green and moves the bug to the next reader of `discount`. A fix at the symptom is a bug relocated, not removed.

## Suite-only failures

Passes alone, fails in the suite — the failure is not in your code, it is in what ran before it.

| Leak | How it shows | Fix |
|---|---|---|
| Leaked fake | `Event::fake()` / `Queue::fake()` with no allowlist, so a later test's real listener never runs | Fake only what the test asserts: `Event::fake([OrderShipped::class])` |
| Unreset time travel | `travelTo()` with no `travelBack()`; later date assertions drift | `travelBack()` in `tearDown`, or scope with `travel()->to()` |
| Shared DB state | A test writes without `RefreshDatabase`, the next one counts rows | Add the trait; never make the assertion looser |
| Static / singleton state | A resolved singleton or static cache survives the container rebuild | Reset it in `setUp`, or stop caching in a static |
| Cached config | `config:cache` left over from a previous run | `php artisan config:clear` before the suite |

**Bisect when the culprit is not obvious.** Run the failing test with progressively fewer preceding tests until it goes green; the last file you removed owns the leak:

```bash
php artisan test tests/Feature/A tests/Feature/Target   # green?  A is innocent
php artisan test tests/Feature/B tests/Feature/Target   # red?    B owns it
```

Never reorder tests, mark one `skipped`, or split a file to hide an order dependence. The leak outlives the workaround and fails something else later, further from its cause. (`laravel-validate`'s failure table lists the same rule at the top level; this is the procedure behind it.)

## What never counts as a fix

Deleting the test. Marking it skipped or excluded. Weakening an assertion until the current value passes. Asserting on a value the test itself just set. Adding `sleep()` to mask a timing dependence. Widening a type until PHPStan stops objecting.

All six are hook-enforced or verify-caught, and all six are the same move: making the evidence agree with the code instead of the code agree with the spec.

## Escalate the moment a pass repeats

**If pass N's hypothesis restates pass N−1's, stop and escalate now.** Do not spend pass 3 to arrive at the same place with less time to explain it. A repeated hypothesis means the information needed to narrow further is not in your envelope — and no number of passes will put it there.

## At the cap

A `blocked` return is a handoff, not an apology. It contains:

- The **classification** — code, test, or slice defect, and why you think so
- The **rung reached** on the ladder, and what each rung told you
- **Each hypothesis and what eliminated it** — this is what stops the next agent repeating your passes
- The **exact failing assertion** with its expected-vs-actual, plus the command that produced it

```
FLAGS: slice defect — `Done when` requires a persisted invoice, but Context names
       only the Action; no factory or migration is in scope to create one.
       H1 (missing eager load) eliminated: relation loads, value is null at source.
       H2 (factory state) eliminated: no factory reachable from this slice.
```

Against: `FLAGS: still failing after 3 attempts`. That sentence costs the next agent every pass you already spent.
