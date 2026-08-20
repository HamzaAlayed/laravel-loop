# Intent — untouched-guard-satisfied-by-git-add

Captured: 2026-08-20T16:20:00Z

Captured while building `resumed-invocation-never-reaches-the-ledger` `S6`. This file carries **no
acceptance criteria, no non-goals, and no slices**; nothing builds from it directly.

## What was observed

`tests/guardrails.test.sh`'s case **`(S9-7)`** — titled *"RC7: hooks.json names no recovery script;
record-cost-event.sh untouched by this slice"* — proves neither half of what its title claims. Its
assertion is:

```bash
[ -z "$(git diff -- scripts/record-cost-event.sh)" ] \
  && [ -z "$(git diff -- hooks/hooks.json)" ] \
  && ! grep -q 'record-recovered-cost' hooks/hooks.json
```

`git diff` with no `--cached` reports **unstaged** changes only. So:

1. **It goes red for any uncommitted change to either file, legitimate or not.** Observed twice in one
   day: once when `scripts/record-cost-event.sh` was deliberately mutated to reproduce `SL4`'s
   red-before (it fired alongside the intended red, which was useful), and once during `S6`'s
   ordinary build, where it was a **spurious red on correct work**.
2. **`git add` alone silences it.** Staging the modified file made the case pass while the file was
   still modified — confirmed: `git diff -- scripts/record-cost-event.sh` printed empty with the
   change staged, and the suite went `521 passed, 0 failed`.

So the case is simultaneously **too strict** (red on any dirty tree) and **too weak** (defeated by
staging). It measures working-tree cleanliness, not whether a slice touched a file.

## Why it matters rather than being cosmetic

- A builder validating a slice **before** committing sees a red that has nothing to do with their
  code, which is exactly the signal-destroying pattern `guardrail-suite-transient-red-after-merge`
  was captured for.
- The guard's *stated* purpose — that the recovery slice did not touch the hook writer or
  `hooks.json` — is a claim about a **historical diff**, not about the working tree. It is checking
  the wrong thing to prove the right claim.
- `resumed-invocation`'s `S7` **must** change `hooks/hooks.json` (Arm A's `SendMessage` matcher).
  After that lands and is committed the case passes again, so this is not a blocker — but it means the
  case will keep going red mid-build for every future slice that touches either file.

## Where it surfaced

`tests/guardrails.test.sh:1834-1842`. On the maintainer's host, and it would behave identically in
CI — where the tree is always clean after checkout, which is **why CI has never caught this**. The
case is green in CI by construction and can only fail locally, mid-edit.

## What was already tried

- **Read the assertion** and confirmed the `git diff` semantics.
- **Observed both failure directions**: spurious red on an uncommitted legitimate change; pass while
  the same change sat staged.
- **Not tried:** any fix. Committing `S6` restored green, which is why this is a capture and not a
  patch.

## Suspected unit or commit

The case belongs to `cost-ledger-blind-to-background-agents` (`RC7`, slice `S9`). Not a defect in that
unit's *subject* — the recovery script genuinely is absent from `hooks.json`, and the `grep` half of
the assertion is sound and worth keeping. The defect is in how the other two halves are expressed.

## The open question a spec pass would have to put to a human

**What should a "this slice did not touch file X" guard actually compare against?** A committed
range (`git diff <base>..HEAD -- path`) needs a base the suite does not currently know. A content
hash pins the file against legitimate future change — which `S6` and `S7` both make. Dropping the two
`git diff` halves and keeping only the `grep` may be the honest answer, since the `grep` is the part
that tests a real invariant. **Not decided here, and no mechanism is proposed.**

## Next step

Normal entry at G0 — run `/loop` on this intent.
