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
