# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-08-13

Closes two of v0.1's named gaps (Ship automation, Observe phase) and adds the
foundation for cost visibility — measurement first, per the cost-optimization
requirements doc's own non-negotiable ordering.

### Added

- **`/ship`** — G3 release-readiness, backed by `scripts/ship-check.sh`: three
  hardcoded gates (guardrail harness, shellcheck, version consistency across
  `VERSION` / `plugin.json` / `marketplace.json`), each reported `passed` /
  `failed` / `not-run` — never silently skipped — with one go/hold verdict.
  Read-only; checks this plugin's own release readiness only, never a
  downstream Laravel app's gates, and does not overlap Guild's
  `laravel-team:ship-checklist`. Deploying, tagging, publishing, and version
  bumps stay a human action (G4) even on a `go`.
- **`/observe`** — closes the outer loop's `↺`: a documented procedure plus a
  thin command that captures a production fault or observation as a new
  `docs/loop/<slug>/intent.md` (what, where, when, tried, suspected unit),
  recording unknowns as `unknown` rather than inferring, then hands off to
  `/loop` at G0. No script, no telemetry, no diagnosis.
- **Cost ledger** (`scripts/record-cost-event.sh`) — one JSONL record per
  subagent start/finish to `.claude/loop-cost.jsonl`: tokens, duration,
  model (observed or derived, stated which), and `Unit:`/`Slice:`
  attribution now carried through the task envelope and every agent's
  return. Rework is tagged at whole-invocation granularity against the
  existing refine-cap definition — deliberately over-attributing rather
  than estimating a per-pass split, and explicitly not comparable to the
  source doc's <15% target until v0.3's reporting work reconciles it.
  Zero dependency, exits 0 unconditionally, bounded and gitignored, never
  reads or depends on Laravel Guild's `agents-board.jsonl`.
- **Cache-friendly prompt ordering** — a hard rule in `loop-protocol`
  (system prompt → protocol → conventions/decisions → spec/slice →
  envelope last), with a guardrail case proven able to fail against a
  seeded violation, not just proven to pass today.
- **G4** (production-change gate) now stated in the README alongside the
  outer-loop diagram, not only in `loop-protocol`.

### Notes

- Harness grew from 22 to 121 cases across both units; shellcheck stays
  clean throughout.
- DC1 (believable ledger numbers across 5+ real units of work) is an open,
  human-judged condition — passing verify means the ledger is built, not
  yet that it is trusted.
- Three small test-coverage gaps on already-correct Ship/Observe prose were
  accepted as CONCERNS at G2 and filed as follow-up, not built in this
  release: Ship's own-repo disclaimer isn't asserted against the script's
  stdout, Observe's O4-O6 have no dedicated cases, and `loop-protocol`'s
  `↺`-resolution wording is untested (README's copy is).

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
