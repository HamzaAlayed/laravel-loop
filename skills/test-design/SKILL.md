---
name: test-design
description: "Choosing which tests a slice needs, not how to write them — red-green ordering inside a slice, pairwise case selection when the input cross-product is unaffordable, the minimum set every slice owes (happy path, each named failure mode, authorization both ways, each stated boundary), and when needing many tests means the slice should have been two. Use at G1 when naming a slice's test set, when a feature has several interacting inputs, when one named test clearly leaves branches uncovered, or when deciding whether a slice is too big."
---

# Test Design

Selection, not authoring — `laravel-validate` has the runner and the syntax. This decides *which* cases earn a test.

G1 requires naming "the test that fails now and passes after". That is the right bar for **sliceability** and the wrong bar for **coverage**: a slice can name one valid test, ship three untested branches, and pass the commit guard, which only proves a test exists.

## Red before green, inside the slice

The named test is written **first** and must be **seen to fail** before the code exists. A test that passes both before and after the change proves nothing about the change — it is a description of behaviour that was already there.

Check it cheaply, one of two ways:

```bash
# Cheap and certain: stash the implementation, keep the test.
git stash push -- app/ && php artisan test --filter=<Name>   # expect RED
git stash pop
```

Or reason about it explicitly and write the reasoning down: *"asserts the discount column, which did not exist before this migration — cannot have passed."* Reasoning is acceptable; assuming is not. An unfalsified test is the commonest way a green slice ships nothing.

## Pairwise selection when the cross-product is unaffordable

Several inputs with a few states each: the full cross-product is too many tests to write and too slow to run, and three guessed cases miss the interaction bug. Pairwise covers **every pair of input states at least once** in a small set.

Invoice export, three inputs — role (owner / admin / guest), status (draft / paid / void), format (pdf / csv). Full cross-product: 3 × 3 × 2 = **18**. Pairwise: **9**.

| # | role | status | format |
|---|---|---|---|
| 1 | owner | draft | pdf |
| 2 | owner | paid | csv |
| 3 | owner | void | pdf |
| 4 | admin | draft | csv |
| 5 | admin | paid | pdf |
| 6 | admin | void | csv |
| 7 | guest | draft | pdf |
| 8 | guest | paid | csv |
| 9 | guest | void | pdf |

Every role–status pair appears; every role–format pair appears; every status–format pair appears. Build the table by covering the two largest inputs exhaustively first, then distributing the smaller ones across those rows.

The win scales with the **number of inputs**, not the number of cases: five three-state inputs are 243 combinations and still land in the low teens pairwise.

**Be honest about what it misses: three-way interactions.** In the table above, `guest` appears with `void`, and `guest` appears with `csv`, but `guest + void + csv` never appears together. A defect needing all three is invisible to this set. Pairwise is a budget decision, not a proof — when a specific triple is known to be risky, name it as its own case on top.

## The minimum set a slice owes

Independent of pairwise, every slice states:

| Case | Why it is not optional |
|---|---|
| **Happy path** | The feature |
| **Each failure mode named in the spec** | A spec'd failure mode is an acceptance criterion; unproven is unproven at G2 |
| **Authorization allowed *and* denied** | The denial is the security property. One direction proves half a Policy. |
| **Each boundary named in the acceptance criteria** | Zero, one, many; first, last; empty, at-limit, over-limit — whichever the criteria actually mention |

Not on the list: every getter, every framework behaviour, every permutation the spec never mentioned. Coverage of the criteria, not of the code.

## Which level to test at

The same behaviour can be proven at three levels with very different costs. Pick the cheapest level that can actually observe the criterion.

| Level | Use when | Cost |
|---|---|---|
| **Unit** — the class alone, no container | The criterion is arithmetic, a state machine, a value object, a pure transformation | Milliseconds. Prefer it. |
| **Feature** — HTTP or Livewire, DB, container | The criterion mentions a route, a status code, authorization, persistence, or a queued side effect | Tens of milliseconds, and the default for most slices |
| **Browser** (Pest v4 / Dusk) | The criterion is only true in a real browser — JS interaction, focus, a rendered chart | Seconds. One case, never a set. |

A criterion naming a status code or a Policy cannot be proven at unit level — the authorization does not exist outside the request lifecycle. Conversely, proving a discount calculation through an HTTP round trip pays the whole framework's cost to test a multiplication.

**Do not prove the same criterion twice at two levels.** Duplicate coverage doubles the maintenance and halves the signal when one of them breaks.

## Overlap with sibling slices

In a multi-slice unit, two slices often touch the same endpoint. Each slice's set covers **only its own criteria** — not the whole endpoint's behaviour, and not its sibling's.

- Slice A adds the route and its happy path → A owns the 200.
- Slice B adds the Policy → B owns the 403, and does **not** re-assert the 200.

When both slices assert the same case, the second one to merge is not extra safety — it is a conflict waiting at integration and a test that fails twice for one defect. If two slices genuinely need the same case to exist first, that case belongs to whichever merges earlier, and the later slice's envelope should say it depends on it.

## When one test is enough — and when it is a warning

**One test is genuinely enough** when the slice has one input with one meaningful state and no authorization surface: a rename, a config default, a migration adding a nullable column, a copy change.

**One test is a warning sign** when the slice has branches. Count the states in the slice's `Done when`. If naming the set produces eleven tests, the honest read is not "eleven tests" — it is **two slices**, and the cut belongs back at G1 where it costs a sentence. A slice whose test set does not fit in its own envelope was sliced by file, not by behaviour.

Rough dial, not a rule: 1–3 cases is a healthy slice, 4–6 is a large one worth a second look, 7+ is a re-slice conversation.

## How this feeds G1

`loop-slice` states the **test set**, not a single test, and states the rule that produced it:

```
Done when:   Export returns a signed URL for a paid invoice, and 403 for a guest.
Test set:    9 cases, pairwise over role × status × format (see test-design).
             Plus: guest + void + csv named explicitly — the triple pairwise skips.
             Fails today: no ExportInvoiceTest exists.
```

The five-test check's item 3 — *independently testable: name the test that fails now and passes after* — is satisfied by a named set with a stated selection rationale. A set with no rationale is a guess with more rows.
