# Verify — cost-measurement-v0.2

**Verdict: PASS** — all 37 acceptance criteria (L1-L11, P1-P4, W1-W8, H1-H5, C1-C4, X1-X4) proven by a named, running harness case. 121/121 total. No concerns, no blocking findings, no out-of-bounds touches.

## Confirmed by independent reproduction

- `enforce-refine-cap.sh` and `block-untested-commit.sh` byte-identical to before this unit started (W8/X2) — their original 20 cases pass unmodified.
- `hooks.json`'s original two Bash entries byte-identical; only new `Agent|Task` matchers and one additional Bash/PostToolUse hook item added (X3).
- S2's field-path guesses (`tool_input.prompt`, `tool_use_id`) degrade safely to `slug: "unknown"` / a composite key if wrong — the script's correctness doesn't depend on those guesses being exactly right.
- S3's SubagentStop claim is moot regardless of its accuracy: the script discards SubagentStop events before extracting any field, so behavior doesn't depend on the disputed "no tool_use_id" observation.
- D3's rework semantics ("cost of slices not right first time," not "cost of retrying," deliberately over-attributing, not comparable to the source doc's <15% target) are stated plainly in both the script header and README.
- No `/cost` command, no report, no dollar figure, no budget/threshold anywhere in the diff — all correctly deferred to v0.3.
- DC1 (believable numbers across 5+ real units) is absent from every test and from README — correctly left as a human-judged post-merge condition, not something any test claims to satisfy.

## DC1 — still open, by design

Per the spec: passing G2 means this is *built*, not *trusted*. The next step (not part of this unit) is watching the ledger accumulate across 5+ real `/loop` runs and checking the share of null-token (unpriced) records — flagged in slices.md as likely to be large for async-launched build invocations.

---

## DC1 — the countable half, answered 2026-08-18

`DC1` was left open "by design" above: the next step was watching the ledger accumulate across 5+
real `/loop` runs and checking the share of null-token records, flagged as likely large for
async-launched build invocations. Five real units have since accumulated, so the countable half is
answerable now. Read from `.claude/loop-cost.jsonl` at 128 lines (no eviction has trimmed it — the
cap is 5,000), grouped by `invocation_id`:

| Slug | Invocations | Host-observed | Priced only by a `recovered` record | Unpriced | In flight |
|---|---|---|---|---|---|
| `cost-ledger-blind-to-background-agents` | 15 | 7 | 0 | 7 | 1 |
| `harness-fails-only-on-linux` | 14 | 0 | 14 | 0 | 0 |
| `eviction-cap-not-honoured-under-contention` | 8 | 0 | 0 | 8 | 0 |
| `ship-gate-blind-to-ci` | 7 | 0 | 7 | 0 | 0 |
| `recovered-figure-drops-slice-and-model` | 6 | 0 | 0 | 6 | 0 |
| **5 real units** | **50** | **7** | **21** | **21** | **1** |

A sixth slug, `unknown`, holds 4 invocations that are not a unit of work (two controlled probes from
2026-08-14 and two backgrounded agents from the session that gathered these figures).

**The unpriced reason, which is what `DC1` actually asks about:** all **24 of 24** unpriced
invocations across the whole ledger carry `status:"async_launched"`. None is `line_too_long`, none
has the status field absent. By phase the 24 split build 15, slice 3, spec 2, verify 1, unknown 3.
So v0.2's prediction holds by count — the unpriced share is dominated by backgrounded invocations,
and build is the largest block of them.

**One thing the prediction got wrong, recorded because it matters:** build is **not** structurally
unpriced. `cost-ledger-blind-to-background-agents` recorded 4 build invocations with
`status:"completed"` and real host figures (206812, 99063, 153109, 104943). Host-observed build
coverage across the ledger is 4 of 33 build invocations; 13 more are priced only because a human or
an orchestrating agent transcribed the figure by hand.

**Also recorded:** `cap_trip` has never fired — 0 records in 128. And 0 of 54 invocations carry both
a host-observed and a transcribed figure, so `RC3`'s disagreement case still has no real-world
instance; every test of it is a fixture.

**What is still not answerable, and stays open:** `DC1` is worded as *believable* numbers, which is a
human-judgement condition no ledger can hold evidence for — it needs a person reading a report for a
run they watched. And what those 24 unpriced invocations actually spent is unknowable from these
records: no figure exists on any of them. Counts above are counts, one observation each; nothing here
is a rate.
