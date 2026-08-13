---
description: Report what .claude/loop-cost.jsonl can see for one unit of work -- coverage before any total, always -- or list every unit the ledger holds. Reads only; computes nothing itself.
argument-hint: [slug]
allowed-tools: Bash, Read
---

# Cost — `{{args}}`

> **Deterministic, not delegated.** Like `/ship`, this sits on the deterministic side of
> the protocol's determinism boundary. No agent is spawned here. This command runs
> `scripts/cost-report.sh` and relays its output verbatim -- it computes no figure of its
> own and re-derives no total.

Reports what the cost ledger (`.claude/loop-cost.jsonl`) holds for a unit of work: how many
invocations it observed, how many of those carry a token figure, how many do not, and the
priced-subset total labelled as partial -- coverage stated before any total, always. With no
argument, it lists every unit the ledger holds, most recent first, each carrying its own
coverage.

This reads **only** `.claude/loop-cost.jsonl`. No network call, no account, and no reading of
a sibling plugin's own separate event feed even when one happens to sit right next to it.

## What you do

1. **Run the report script exactly as written:**

   ```
   bash scripts/cost-report.sh {{args}}
   ```

2. **Relay its output verbatim.** Every line -- the coverage statement, the token total or
   its stated absence, any empty-state message -- unedited. This command applies no judgment
   of its own and prints no figure the script did not already produce.

3. **Never soften an absent or empty ledger into reassurance.** If the ledger is missing,
   empty, or holds nothing for the requested unit, say exactly what the script said. A quiet
   ledger and a healthy one are not the same thing, and this command never treats them as
   though they were.
