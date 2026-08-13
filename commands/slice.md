---
description: Slice an approved spec into well-formed, independently testable tasks with owners, order, and explicit out-of-bounds. Gate G1 on its own.
argument-hint: <path to a spec, or the slug>
allowed-tools: Agent, Read, Write, Bash, Grep, Glob, Skill, AskUserQuestion
---

# Slice — `{{args}}`

> **Delegation:** spawn `loop-slice` by its registered agent type as it appears in your available-agents list — prefixed when installed as a plugin (`laravel-loop:loop-slice`), unprefixed when installed manually.

G1 without the rest of the loop. Use it when a spec already exists — written by `/loop`, by hand, or lifted from a ticket — and the only open question is how to cut the work.

## What you do

1. **Resolve the spec.** `{{args}}` is a path or a slug; look under `docs/loop/`. No spec on disk → stop and say so. Do not reconstruct one from the ticket title: slicing an unwritten spec produces a plan for a problem nobody agreed on, which is worse than no plan because it looks like progress.

2. **Brief `loop-slice`** with the spec path, `docs/loop/conventions.md`, and `docs/loop/decisions.md`. Require the five-test justification per slice and a nominated riskiest slice. Every brief carries `Unit:  <slug>` (`Slice:` omitted — this command produces the slice list, it does not operate inside one).

3. **Audit what comes back** before showing the human. Send it back for any slice that has two owners, cannot name its failing-then-passing test, plainly exceeds one commit, has an empty `Do NOT`, or depends on something later in the list. A coarse slice surfaces downstream as a tripped refine cap — and by then it costs the whole task instead of a sentence.

4. **⏸ Gate G1.**

```
# Slices — <slug>

Slices: <n>  ·  Parallel: <n>  ·  Critical path: S1 → S4
Riskiest: S<n> — <why>

<one line per slice: S<n> · what it delivers · depends on>

1. Approve  (recommended)
2. Re-slice — <which, and why>
3. Spec is wrong — back to loop-spec
```

5. **On approval**, state the handoff: `/loop` to run the slices with gates, or `loop-build` directly with a single envelope passed verbatim. Do not start building inside this command.
