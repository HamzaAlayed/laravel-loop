# Intent — transcript-scraping-as-a-recovery-path

Captured: 2026-08-17T19:09:33Z

## What was observed

The ledger's only route to a backgrounded invocation's token figure is a **model-reported**
one — an agent reads the figure out of its own context and types it into
`scripts/record-recovered-cost.sh`. The same figure also exists **host-observed**, in the session
transcript, which would sidestep the model-reported objection entirely. Nothing reads it from
there, by decision.

Two things observed on 2026-08-17 make the alternative worth its own intent rather than leaving
it as a line in a closed unit's log:

1. **The transcription path was exercised for real for the first time** (seven invocations,
   667,094 tokens, unit `ship-gate-blind-to-ci`) and it worked — coverage 0 % → 100 %, every
   figure permanently marked `transcribed rather than host-observed`. So the model-reported route
   is not merely theoretical any more; it has a track record, and its costs are now observable
   rather than predicted.
2. **It has two observed costs.** A transcribed figure restores the unit total but drops the slice
   and model dimensions (captured separately at
   `docs/loop/recovered-figure-drops-slice-and-model/`), and a `SendMessage`-resumed invocation
   cannot be transcribed against its own id at all, because the cost hook matches `Agent|Task` and
   never sees the resume — so the resumed run's figure has to be attributed to the original
   launch's id, and the killed attempt's tokens are reported nowhere by anything
   (`docs/loop/conventions.md`).

Neither of those costs is an argument *for* scraping on its own. They are the observations that
make the comparison concrete, which it was not when the alternative was first put out of bounds.

## Where it surfaced

Not a runtime fault, and this file is not reporting one. It surfaced as a design alternative
during the second slicing gate of `cost-ledger-blind-to-background-agents`, was put out of
bounds there, and is recorded in two places:

- `docs/loop/decisions.md`, under *"Second G1: land model-transcribed recovery, hold automatic
  wiring (2026-08-17)"*, which rejected it for this pass in these words: *"reading
  `~/.claude/projects/.../*.jsonl` after the fact to recover a figure nobody deliberately
  transcribed. Rejected because it would give the ledger a second, undeclared input path outside
  RC7's observe-only contract, turning a deliberate, typed act into a silent background scan."*
- `docs/loop/cost-ledger-blind-to-background-agents/log.md`, under *"What is still open,
  deliberately"*, which states it *"reads conversation logs outside the project directory, so it
  is a different consent conversation and deserves its own intent."*

The files in question live under `~/.claude/projects/<sanitised-cwd>/`, outside this repository.

## When

Alternative first surfaced 2026-08-17 at that unit's second G1. The two observed costs above were
established later the same day, while closing `ship-gate-blind-to-ci`. Captured as its own intent
2026-08-17T19:09:33Z.

## What was already tried

- The model-reported route was **built and shipped** in v0.6.0 (`scripts/record-recovered-cost.sh`,
  five refusal paths, exit 0 on each) and then exercised by hand seven times, which is what
  produced the track record described above.
- Its two costs were established by doing it and reading the output, and each is captured
  separately rather than folded in here.
- **Scraping itself has not been attempted, prototyped, or measured.** No transcript file has been
  read for this purpose, no format has been surveyed, and no estimate exists of whether the figure
  is reliably present, stably located, or stably shaped across sessions and hosts. All of that is
  `unknown`.
- No consent question has been answered. Whether reading conversation logs outside the project
  directory is acceptable at all, under what scope, and with what disclosure, is exactly what was
  deferred and is not decided here.

## Suspected unit or commit

No fault, so nothing is suspected of causing one. Two followable references for where the
alternative and its rejection are recorded:

- `docs/loop/cost-ledger-blind-to-background-agents/` — the unit that built the model-reported
  route and put this out of bounds. Its RC7 contract (nothing hook-wired, nothing that runs
  unless typed) is the constraint any scraping design would have to answer to.
- `docs/loop/decisions.md` — the rejection above, which a new unit would either uphold on the same
  grounds or overturn with new ones. It is not overturned here.

## Bearing on other open work

- `docs/loop/recovered-figure-drops-slice-and-model/` — a defect in the existing route. It should
  be settled on its own merits; a scraping design that inherits the same record shape would
  inherit the same defect.
- **S11** (automatic transcription wiring) remains held in the unit above. If scraping ever
  displaced model-reported transcription, S11's subject would change rather than merely being
  scheduled, so the two should not be decided independently.

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance
criteria, no non-goals, and no slices**; nothing builds from it directly. Note that its first
G0 question is a consent question, not a technical one.

---

## Status — DECLINED at G0, 2026-08-19

Answered `no` rather than left open. A plugin reading files outside the repository it is installed in
is a different trust posture from anything shipped so far, and the same figures are already reachable
through `scripts/record-recovered-cost.sh`, a human-invoked CLI. The consent question this intent
names is the reason: it is not a technical trade, and it was decided as a consent question.

This file stays as the record of the question and the reasoning, not as pending work. See
`docs/loop/decisions.md`, *"Backlog gate: one queue, four drops, and six questions closed"*. Nothing
here is scheduled; reopening it means overturning that entry with new argument.
