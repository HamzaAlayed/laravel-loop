# Intent — recovered-figure-drops-slice-and-model

Captured: 2026-08-17T13:13:34Z

## What was observed

A transcribed figure restores the unit's token total and its coverage percentage, but the report
loses the slice and model dimensions for that invocation — while still resolving the phase
correctly for the same invocation, from the same records.

After transcribing all seven of `ship-gate-blind-to-ci`'s backgrounded invocations with
`scripts/record-recovered-cost.sh`, `bash scripts/cost-report.sh ship-gate-blind-to-ci` printed:

```
Coverage:
  based on 7 of 7 invocations that carry a token figure (0 unpriced, not counted) -- 100 % coverage; 7 of 7 priced figure(s) transcribed rather than host-observed (667094 of 667094 priced token(s), 100 %)
  per phase (priced/total invocations; ...):
    spec   1/1 priced (0 unpriced)
    slice  1/1 priced (0 unpriced)
    build  4/4 priced (0 unpriced)
    verify 1/1 priced (0 unpriced)
```

Phase resolution is correct there — the report finds the phase for each recovered figure. But
lower in the same output:

```
Phases (priced invocations only; model per phase, model_source shown when derived):
    spec   unavailable
    slice  unavailable
    build  unavailable
    verify unavailable

Slices (top by priced tokens, priced subset only):
  no slice attributed to any priced invocation.
```

All four phases read `unavailable` for model, and no slice is attributed at all — despite four of
the seven invocations being build-phase invocations whose `start` and `finish` records carry
`"slice":"S1"` through `"slice":"S4"`, and all seven carrying `"model":"opus"` with
`"model_source":"derived"`.

The recovered record itself is minimal:

```json
{"ts":1786966693,"event":"recovered","invocation_id":"toolu_01AYBjiC2newiJibemvr1C28","slug":"ship-gate-blind-to-ci","total_tokens":67654,"token_source":"transcribed"}
```

The asymmetry is the observation: the report evidently joins a recovered record to its
`start`/`finish` records by `invocation_id` in order to report the phase, yet model and slice —
which sit in those same joined records — come back unavailable.

## Where it surfaced

`scripts/cost-report.sh`, run for unit `ship-gate-blind-to-ci` against
`.claude/loop-cost.jsonl`, on the maintainer's host. The records were written by
`scripts/record-recovered-cost.sh`, invoked by hand seven times.

The same output feeds `scripts/write-cost-log-section.sh`, so the `## Cost` section now in
`docs/loop/ship-gate-blind-to-ci/log.md` was generated from a report with these dimensions
missing.

## When

2026-08-17, between roughly 12:58Z and 13:05Z, while closing `ship-gate-blind-to-ci`. This was
the first real use of `scripts/record-recovered-cost.sh` since it shipped in v0.6.0 — the
transcription had not previously been exercised outside fixtures.

## What was already tried

- Transcribed seven figures with `scripts/record-recovered-cost.sh`, one per invocation, from the
  `<subagent_tokens>` values in each agent's own completion notification. All seven exited 0 and
  wrote a record; `grep -c '"event":"recovered"'` returned 7.
- Ran `bash scripts/cost-report.sh ship-gate-blind-to-ci` and read the whole output by eye, which
  is what surfaced this.
- Inspected a recovered record's fields directly and compared them to what the `start` record for
  the same `invocation_id` carries.
- Confirmed the per-phase block resolves correctly for the same seven records, establishing that
  a join on `invocation_id` does happen for at least one dimension.
- Recorded the finding in `docs/loop/ship-gate-blind-to-ci/log.md` under "The ledger measuring
  this unit".
- **No fix attempted, and no cause assigned.** Neither `cost-report.sh` nor `cost-ledger-lib.sh`
  has been read to determine whether the gap is in the writer, the reader, or intended behaviour
  nobody wrote down. Whether the recovered record *should* carry slice and model, or the reader
  should join for them as it apparently does for phase, is not decided here.

## Suspected unit or commit

`docs/loop/cost-ledger-blind-to-background-agents/` — the unit that shipped both sides of this in
v0.6.0. Two followable references within it, per its own log:

- **S7** — "The reader understands an `event:"recovered"` line: counted once, counted priced,
  labelled transcribed." The reader half.
- **S9** — "`scripts/record-recovered-cost.sh` — the only writer. Five refusal paths, exit 0 on
  every one." The writer half, and the record shape above.

That unit's G2 verdict was a scoped PASS reached against fixtures; its own log states DC4 and DC5
were held outside the PASS because the harness structurally could not exercise them. This was
found by exercising DC5 by hand, which is what DC5 asked for.

Which of S7 or S9 is the defect, or whether either is, is `unknown`.

## Bearing on held work

That unit holds **S11** — automatic wiring of transcription after every backgrounded lane —
approved-but-held, with the stated revisit condition being "after one transcription has been done
by hand and checked by eye." That condition is now met, and this is what the check found. Recorded
here as context, not as a decision: whether S11 should be built, and in what shape, is a question
for a gate, and building automation over a record shape that loses dimensions would multiply this
rather than settle it.

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance
criteria, no non-goals, and no slices**; nothing builds from it directly.
