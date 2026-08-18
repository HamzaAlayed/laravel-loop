# Intent — eviction-cap-not-honoured-under-contention

Captured: 2026-08-18T08:39:05Z

## What was observed

The cost ledger does not honour its declared line cap when appends arrive under real CI contention,
and the case that asserts it fails on **both** guarding platforms while passing on the maintainer's
own machine.

CI run `32112900121`, commit `9f37a5b`, both jobs of `.github/workflows/ci.yml`:

```
FAIL eviction convergence: a sustained concurrent stream still settles at or under cap
     once it finishes (expected exit yes, got no)
total: 426 passed, 1 failed
```

Identical on `guardrails` (ubuntu-latest) and `guardrails-macos` (macos-latest). The same suite
reports `427 passed, 0 failed` on the maintainer's host, and that same case was falsified 5/5 red
against the pre-fix script and 5/5 green after, locally, when it was written.

Two things about the shape of this, both observed rather than argued:

1. **It is not platform-specific.** The macOS runner's `Bash 3.2.57(1)-release` and arm64
   architecture both exactly match the maintainer's host, and it fails there too. What the two
   failing environments share is being contended CI runners, not an operating system.
2. **The two failures that preceded it are genuinely gone.** `tests/guardrails.test.sh:429` and
   `:2520` — the two cases whose fixes were the point of `harness-fails-only-on-linux` — appear on
   neither job. This is a different failure, exposed by resolving those, exactly as that unit's own
   floor-is-a-lower-bound record anticipated.

The failing case is at `tests/guardrails.test.sh:464`. The code it exercises is
`scripts/record-cost-event.sh`'s `append_and_evict()`.

## Where it surfaced

GitHub Actions, repository `HamzaAlayed/laravel-loop`, workflow `.github/workflows/ci.yml`, **both**
jobs, step `guardrail tests` / `guardrail tests (macos)`. Runners `ubuntu-latest` and
`macos-latest`.

Not reproducible on the maintainer's host (macOS 26.6.1, arm64, `GNU bash, version
3.2.57(1)-release`), where the full suite is green. Also not reproducible in throwaway Docker
containers: a prior spike ran 20 trials across two Ubuntu versions, two bash versions, and two CPU
allocations, and every one settled at cap.

## When

2026-08-18T07:44Z — run `32112900121` on commit `9f37a5b`, the first pushed run after
`harness-fails-only-on-linux` closed. Noticed immediately, while confirming that unit's A1.

## What was already tried

Extensively, across the preceding unit — all of it recorded, none of it closing this:

- **`spike-case-a.md`** refuted a deterministic platform cause (H1) with 20/20 passing Linux trials,
  and established by reading that the eviction loop's fixed 5-attempt bound had no convergence
  guarantee. It left **H2** explicitly open — *"the CI runner's specific resource profile produced
  that rate once, where this sandbox's Docker containers did not"* — and named a repeated real run as
  what would settle it.
- **S5** removed the fixed bound so the evictor loops until it observes the file at or under cap, and
  so a lock-loser is no longer simply abandoned. Falsified 5/5 red / 5/5 green locally.
- **S9** added a `break` on a persistently failing `mv`, after the first G2 found S5's unbounded loop
  could hang. Verified across three script versions.
- **Two G2 passes**, the second a PASS, both of which correctly declared A1 outside their scope
  because nothing had been pushed.
- **This run is what settles H2**: the arrival-rate reading is confirmed, and the platform reading is
  refuted a second time by the macOS job failing identically.

**No fix has been attempted for this.** Whether the remaining gap is in the algorithm or in what the
case asserts has not been established, and is not asserted here.

## Suspected unit or commit

- `scripts/record-cost-event.sh`'s `append_and_evict()` — the code the failing case exercises.
  Introduced in its current form by commit `68ece94` (S5) with `22779f8` (S9) amending one line.
- `docs/loop/harness-fails-only-on-linux/` — the full history: the spike that left H2 open, both G2
  verdicts, and the A1 record showing this failure.

Whether the defect is in that function or in the case's expectation is `unknown`, and deliberately
not resolved here.

## The maintainer's stated instinct — input to G0, not a decision

Asked at the point of capture, the maintainer's instinct is that **the cap should be a hard bound and
the code should be fixed**, rather than the case's expectation being relaxed to eventual convergence.

Recorded so G0 has it, and recorded as an *instinct* rather than a decision: it does not foreclose the
alternative, and the tension it runs into is real and unresolved. A design where appenders never
block on the evict lock — `L7`, deliberate and documented, with its own regression guard — means some
invocation always appends last, after the final trim, with no later appender obliged to re-evict.
Whether a hard bound is achievable without giving up L7, and what a genuine closing mechanism would
cost, is exactly what G0 should interrogate rather than inherit.

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance
criteria, no non-goals, and no slices**; nothing builds from it directly.
