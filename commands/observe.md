---
description: Capture a fault, regression, or observation as a new intent under docs/loop/ — records what, where, when, what was tried, and which unit is suspected. Never triages, never edits an existing unit, never builds. The `↺` in the outer loop.
argument-hint: [a pasted stack trace, one sentence of prose, or nothing]
allowed-tools: Read, Write, Bash, Grep, Glob, AskUserQuestion
---

# Observe — `{{args}}`

> **No agent, no script.** Observe sits on the deterministic side of the protocol, next to
> Ship. This procedure runs directly, from whoever invokes it — no subagent is spawned and
> nothing under `scripts/` backs it. Markdown only.

The `↺` in the outer loop: the closing arrow from a production fault, or a merged unit that
turns out not to have solved the problem, back to a new Intent. **A capture records; it does
not diagnose, reproduce, assign a cause, or start the loop by itself.**

## What you do

1. **Read `{{args}}`.** It may be a full stack trace, one sentence, or empty. Whatever is
   missing, ask for it once with `AskUserQuestion`; whatever remains unknown after asking
   stays unknown — never guessed.

2. **Collect exactly five things.** No more, no fewer. Any of these not known is written as
   the literal word `unknown` in that field. **None is ever inferred.**
   - What was observed
   - Where it surfaced
   - When
   - What was already tried
   - Which unit or commit is suspected

3. **Check the repo.** Not inside a git repository → say so and stop before writing
   anything.

4. **Choose a slug.** Derive a short kebab-case slug from what was observed. Check
   `docs/loop/<slug>/` for an existing `spec.md`, `slices.md`, or `intent.md`. If any exist,
   this is a **slug collision** — refuse the write and pick a distinct slug (append `-2`, a
   date, or ask which name to use). **Never an overwrite**, and never touch the colliding
   unit's `spec.md`, `slices.md`, or `verify.md` — those files are never opened for writing
   by this procedure, collision or not.

5. **Write `docs/loop/<slug>/intent.md`** using the template below, filled in with the five
   fields from step 2. This is the only file this procedure creates.

6. **Attribute, if known.** When a merged unit or commit is suspected, record it as a
   followable in-repo reference — a path like `docs/loop/<other-slug>/` or a commit SHA. When
   unknown, leave the field `unknown`: no link, no guess.

7. **Hand off and stop.** State plainly that the next step is the normal entry at G0 — run
   `/loop` (or hand the intent to `loop-spec`). Nothing builds, slices, or ships from a
   capture directly.

## Template — `docs/loop/<slug>/intent.md`

```markdown
# Intent — <slug>

Captured: <ISO 8601 timestamp, or `unknown`>

## What was observed

<the fault, in the reporter's words or a pasted trace — or `unknown`>

## Where it surfaced

<environment, page, command, or user report — or `unknown`>

## When

<ISO 8601 timestamp or relative time — or `unknown`>

## What was already tried

<bullet list of things already attempted — or `unknown`>

## Suspected unit or commit

<a followable reference — `docs/loop/<other-slug>/` or a commit SHA — or `unknown`. Never a
guess.>

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance
criteria, no non-goals, and no slices**; nothing builds from it directly.
```

## What this is not

- **Not a spec.** No acceptance criteria, no non-goals, no slices are ever added to an
  `intent.md`. It is thinner than a spec by design — see
  `docs/loop/ship-observe-automation/spec.md` for what a spec looks like, and notice this
  isn't it.
- **Not a diagnosis.** Nothing here triages, reproduces, assigns a cause, or auto-starts the
  loop.
- **Not telemetry.** No log tailing, no polling, no webhook receiver, no network call, no
  credentials. It works the same from a pasted stack trace or a single sentence, in any
  repository, regardless of language or toolchain.
- **Not an edit.** An existing unit's `spec.md`, `slices.md`, or `verify.md` are never opened
  for writing by this procedure — a capture only ever adds a new `docs/loop/<slug>/intent.md`.

## Refusals

- Run outside a git repository → say so and stop; write nothing.
- The chosen slug already exists under `docs/loop/` → refuse the write and choose a distinct
  slug. Never an overwrite.
- Any of the five required fields is not known → write `unknown` in that field. None is ever
  inferred.
