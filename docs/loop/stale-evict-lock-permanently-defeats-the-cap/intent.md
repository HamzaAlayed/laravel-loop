# Intent — stale-evict-lock-permanently-defeats-the-cap

Captured: 2026-08-18T19:30:00Z

## What was observed

An evictor killed mid-loop never reaches its `rmdir`, so `.claude/loop-cost-evict.lock` stays on
disk. From then on **every** later appender polls for the lock, gives up, appends its line
regardless (`L7`), and never evicts — so the ledger's line cap is not honoured again for the
lifetime of that directory. `spec.md`'s own failure-mode table for
`docs/loop/eviction-cap-not-honoured-under-contention/` states it as: *"every later appender polls,
gives up, appends, and never evicts — a permanent cap violation by a second route."*

It has the **same observable** as the convergence hole that unit just fixed — a ledger sitting over
cap — by a different mechanism, and it is permanent rather than transient.

Confirmed **pre-existing**: it predates the arrival-trim work, and `S5`'s new `trim_on_arrival()`
does not address it (that path makes one `mkdir` attempt and returns immediately when the lock is
held, by design, so a stale lock defeats it exactly as it defeats an appender).

## Where it surfaced

Established by reading `scripts/record-cost-event.sh` — the `mkdir "$EVICT_LOCK"` /
`rmdir "$EVICT_LOCK"` pair in `append_and_evict()` and `trim_on_arrival()`, and the poll loop an
appender runs before appending. Not from a failing run: no run has been observed failing this way.

## When

Raised as `OQ4` at that unit's G0 (2026-08-18) and scoped out there; scoped out twice before that in
earlier units; named again as an open gap that **compounds** with the convergence hole in the second
G2 verdict of `docs/loop/harness-fails-only-on-linux/`. Recorded here on 2026-08-18 because three
units in a row have now declined it and its own record kept saying it "needs its own intent".

## What was already tried

- **Deliberately nothing.** It has been left out of scope three times, each time as a recorded
  decision rather than an oversight — most recently as `OQ4` in
  `docs/loop/eviction-cap-not-honoured-under-contention/spec.md`, whose pinned contracts also
  instruct any lane that trips over it to record one observation line and move on, and state that
  **a red attributable to a stale lock is not that unit's red**.
- No reproduction was attempted, no cleanup mechanism was designed, and no staleness criterion
  (age, pid liveness, anything else) has been proposed anywhere in this repository.

## Suspected unit or commit

`unknown` as a *cause* — it is pre-existing, and no commit introduced it as a regression.

The mechanism lives in `scripts/record-cost-event.sh`, and the unit that documents it most fully is
`docs/loop/eviction-cap-not-honoured-under-contention/` (see its `spec.md` failure-mode table and
`OQ4`). `scripts/record-recovered-cost.sh` carries its own independent copy of the same lock
primitive and would need the same question asked of it.

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance criteria, no
non-goals, and no slices**; nothing builds from it directly. The first question for G0 is whether a
lock can be declared stale at all without a liveness signal this repository has (`bash` + coreutils
only, no `flock`), and what a wrong answer costs — a lock stolen from a live evictor is a torn
ledger, which is worse than a ledger over cap.
