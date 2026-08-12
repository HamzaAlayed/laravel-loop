---
description: Run laravel-loop's own G3 release-readiness gates and relay the verdict verbatim — go or hold. Deploys, publishes, tags, and bumps nothing.
argument-hint: (no arguments — checks this repository only)
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

# Ship

> **Deterministic, not delegated.** Ship sits on the deterministic side of the protocol's
> determinism boundary, next to Observe. No agent is spawned here. This command runs
> `scripts/ship-check.sh` and relays its output — it applies no judgment and re-derives no
> verdict.

This checks **laravel-loop's own** release readiness — the three gates declared in
`scripts/ship-check.sh`. It is **not** a downstream Laravel application's gate check: running
`/ship` here checks nothing about your Laravel project, and it does not overlap
`laravel-team:ship-checklist`, which is the pre-release checklist for a Laravel *app*
(migrations, queues, env, security, docs).

This run **deploys, publishes, tags, and bumps nothing** — no git push, no tag, no GitHub
release, no marketplace publish, no version bump, here or behind any confirmation in this
command. That is G4, and it stays a human action taken outside this command.

## What you do

1. **Run the gate script exactly as written:**

   ```
   bash scripts/ship-check.sh
   ```

2. **Relay its output verbatim.** Every gate line, any verbatim failure block, and the
   `verdict:` line — unedited. No summarizing, no re-wording, no softening a `hold` into a
   maybe. This command applies no judgment of its own and re-runs no gate to double-check it.

3. **On `hold`, stop.** State that the verdict is `hold` and the release does not proceed.
   Do not retry a gate and do not attempt to fix one here — a failing gate goes back to
   `loop-build` as its own slice.

4. **On `go`, present G3** as numbered options, leaving the actual release action to the
   human at G4:

   ```
   1. Approve — proceed to release (tag, publish, bump: done by you, not this command)
   2. Hold anyway — something the gates didn't catch
   ```

5. **Never re-run a gate, never re-derive the verdict, never soften a `hold`.** Disagreement
   with a `go` is new information for `loop-build` or `docs/loop/decisions.md`, not a reason
   for this command to check again.
