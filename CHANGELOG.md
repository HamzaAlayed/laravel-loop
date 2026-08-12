# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-12

First release. A Laravel agent team organized by **delivery phase** rather than job
title — the thesis being that a role-based team answers "who does this?", while the
question that actually goes wrong is "is this ready to hand on?".

### Added

- **Four phase agents.** `loop-spec` (G0, Opus) turns intent into a spec with explicit
  non-goals and refuses to design or code. `loop-slice` (G1, Opus) cuts the spec into
  slices that each pass a five-test check, with a mandatory `Do NOT`. `loop-build`
  (Sonnet, worktree-isolated) runs the inner loop and never returns red. `loop-verify`
  (G2, Sonnet, **read-only** — `Edit`/`Write` removed) checks built work against the
  spec's acceptance criteria and issues PASS / CONCERNS / FAIL.
- **Three commands.** `/loop` runs the whole outer loop with gates; `/slice` and
  `/verify` expose G1 and G2 standalone for work that entered the loop midway.
- **`loop-protocol` skill** — the shared contract: the two loops, the five gates,
  phase placement, the slice-quality test, the task envelope, the
  `STATUS/DID/VERIFIED/FLAGS/NEXT` return shape, the determinism boundary.
- **`laravel-validate` skill** — the Validate step: toolchain detection (Sail vs host,
  Pest vs PHPUnit, Pint, Larastan), command order, a failure-to-next-action table, and
  the self-check every slice passes before it is returned.
- **`enforce-refine-cap.sh`** — `PostToolUse` on `Bash`, deliberately: a `PreToolUse`
  hook can only count *attempts*, and attempts false-positive on every normal
  red→green→refactor cycle. Seeing the result lets it count failures and reset on
  green. Blocks the 3rd consecutive failing run of the same target with the escalation
  shape. `LARAVEL_LOOP_REFINE_CAP` overrides; `0` disables.
- **`block-untested-commit.sh`** — `PreToolUse` on `Bash`. Refuses a subagent `git
  commit` that stages application code with no test alongside it, making "the test
  ships with the code" a property of the system rather than a line in a prompt.
  Carve-outs for migrations, config, docs, assets, and framework service providers.
  `LARAVEL_LOOP_ALLOW_UNTESTED=1` is the escape hatch, named in the block message.
- **22-case zero-dependency test harness** covering both guardrails (including the
  TDD-rhythm false-positive case, both env-var overrides, and main-thread scoping)
  plus manifest, component-structure, and frontmatter validation.
- **CI** — shellcheck and the harness on every push.

### Notes

- Both guardrails scope to subagents via the hook payload's `agent_type`. A human on
  the main thread is never blocked.
- Fully standalone from Laravel Guild: separate agents, skills, env vars, and state
  file (`.claude/loop-refine-passes.tsv`). Both can be installed side by side.
- v0.1 has no Ship automation, no Observe phase, and no Gemini/Codex target. These are
  stated in the README rather than left to be discovered.
