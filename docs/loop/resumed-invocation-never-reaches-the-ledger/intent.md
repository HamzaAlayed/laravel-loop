# Intent — resumed-invocation-never-reaches-the-ledger

Captured: 2026-08-18T19:30:00Z

## What was observed

A `/loop` invocation resumed with `SendMessage` is never recorded in the cost ledger at all. The
cost hook matches `Agent|Task`, and a `SendMessage` is neither, so:

- the resumed run carries a tool-use id the ledger has never seen;
- its figure is therefore attributed to nothing, when it should be attributed to the **original
  launch's** id;
- and the killed attempt's tokens are reported nowhere by anything.

Quoted from `docs/loop/recovered-figure-drops-slice-and-model/spec.md`, which scoped it out:
*"That is a capture gap — an invocation the ledger has no record of — upstream of and independent
from this unit's dimension gap, which is about records the ledger does hold."*

This is a different class from the transcription gap already handled: recovery
(`scripts/record-recovered-cost.sh`) can restore a figure for an invocation the ledger **has** a
record of. Here there is no record to attach a figure to.

## Where it surfaced

`docs/loop/conventions.md` records the resumed-invocation behaviour; the gap was named at
`recovered-figure-drops-slice-and-model`'s G0 as `OQ5` and confirmed out of scope there. The
mechanism is the matcher set in `hooks/hooks.json` (`PreToolUse Agent|Task`,
`PostToolUse Bash`, `PostToolUse Agent|Task`).

## When

Named as `OQ5` at that unit's G0 (2026-08-18) and left out; that unit's `RC7` puts the hook matcher
out of bounds, so it could not be fixed there even if wanted. Recorded here 2026-08-18 because its
own record says it "needs its own intent and its own G0".

## What was already tried

- **Nothing beyond scoping it out**, twice: once as `OQ5` at G0, and once in that unit's
  *Explicitly not cut, not scoped, not decided* list.
- No count exists of how often this has happened. The ledger cannot answer it — the missing
  invocations are missing by definition, so the ledger's own figures cannot be used to size this
  gap, which is itself worth stating rather than discovering at G0.

## Suspected unit or commit

`unknown` as a cause; pre-existing and structural rather than introduced.

The surface is `hooks/hooks.json`'s matcher set together with
`scripts/record-cost-event.sh`'s `Agent|Task` gate. The unit that documented and deferred it is
`docs/loop/recovered-figure-drops-slice-and-model/` (`OQ5`).

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance criteria, no
non-goals, and no slices**; nothing builds from it directly. Two questions G0 will have to settle
before anything can be sliced: whether a `SendMessage` arrival can be matched at all without the
hook acquiring judgement it is not allowed to have, and how a resumed run's figure is attributed to
the original launch's id without inventing a second invocation.
