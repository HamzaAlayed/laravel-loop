# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] - 2026-08-14

### Added

- **`build-conventions` skill** — the Generate step's cookbook, the last inner-loop step
  without one. `loop-build` carried a single paragraph of Laravel defaults inline, in a prompt
  loaded in full on every invocation, covering the step where the most tokens are spent and
  the most code is produced. The skill carries the requirement-to-primitive mapping (Form
  Request, Policy, API Resource, `$fillable`, `config()`, transactions, `afterCommit`, Action
  classes, `make:*`), each paired with the antipattern `loop-verify` already looks for, a
  four-question per-slice checklist, and the three reasons that actually change behaviour
  under time pressure — `env()` after `config:cache`, mass assignment as an authorization
  hole, and `afterCommit` race conditions.

### Changed

- **`agents/loop-build.md`** — the inline "Laravel defaults" paragraph is replaced by a skill
  invocation plus the one rule that governs the rest (match the codebase, flag that you did).
  The agent prompt is shorter than before; method moved rather than copied.
- Skill count 6 → 7. Every inner-loop step now has cookbook coverage:
  Parse/Plan (`loop-protocol`) → Generate (`build-conventions`) → Validate (`laravel-validate`)
  → Refine (`loop-debug`) → Integrate (`worktree-merge`).

### Fixed

- **`tests/guardrails.test.sh` no longer fails on a stray dotfile in `skills/`.** Both the
  structure and frontmatter checks iterated `skills/` assuming every entry was a skill
  directory, so a `.DS_Store` left by Finder became `skills/.DS_Store/SKILL.md` and red-lined
  two cases for every macOS contributor. Both loops now skip dotfiles and non-directories.
  Adding `.DS_Store` to `.gitignore` stops git tracking it but does not stop the harness
  reading it off disk — the check itself had to change. Verified still catching real defects:
  a skill directory without `SKILL.md`, and a `SKILL.md` without frontmatter, both still fail.

## [0.4.0] - 2026-08-14

Four cookbooks, taking the skills count from two to six. Each closes a specific gap
where an agent had a *destination* but no *procedure* — the phases that were carried
entirely by prompt text, or not carried at all.

### Added

- **`test-design`** — closes the gap between G1's sliceability bar and actual coverage.
  G1 required naming "the test that fails now and passes after", singular: the right bar
  for deciding a slice is testable, the wrong one for deciding it is tested. A slice
  could name one valid test, ship three untested branches, and pass the commit guard,
  which only ever proved a test *exists*. The skill covers red-before-green inside a
  slice, pairwise case selection when the input cross-product is unaffordable (with an
  honest account of the three-way interactions pairwise misses), the minimum set a slice
  owes, which level to test at, overlap between sibling slices, and the case-count dial
  that says a slice should have been two.
- **`loop-debug`** — closes the gap in the Refine step. `loop-build` said "red → back to
  step 3 with the actual failure output", which is *where to go*, not *what to do on
  arrival*; passes 2 and 3 were procedurally "try again harder". The skill requires one
  falsifiable hypothesis per pass, and puts failure classification *before* pass 1 —
  code defect, test defect, or slice defect, three different owners, with `blocked`
  returned immediately for the third rather than spending a pass on it. Plus the
  isolation ladder, root-cause tracing, the suite-only leak table, and what a `blocked`
  return has to carry so the next agent does not repeat the passes already spent.
- **`verify-playbook`** — closes the gap of `loop-verify` being the only agent with no
  cookbook at all. Its whole method lived in its prompt, loaded in full on every
  invocation regardless of what was being verified, and Verify is the phase most likely
  to drift silently: a verifier that gets gradually laxer emits no signal until defects
  ship. The method now versions independently of the prompt, and adds two things the
  prompt never had — tracing a failure the diff cannot explain *before* writing the
  verdict (previously an undifferentiated FAIL that bounced slices back to builders who
  had not caused the problem), and a scope declaration so a scoped PASS can never read
  like a full one.
- **`worktree-merge`** — closes the gap at integration. `loop-build` runs
  worktree-isolated and `/loop` caps lanes at 2–3, but nothing documented what happens
  when the lanes come back; the only guidance was "merge along the dependency chain", a
  correct principle and not a procedure. Integration is where parallelism fails, and it
  fails at the end, when every lane's budget is already spent. Covers checking the base
  on entry rather than at merge time, the full suite after **each** merge, conflict
  ownership (app code routes back to the owning builder; only mechanically-correct
  resolutions stay with the orchestrator), migration timestamp collisions across
  branches, and what to preserve from an abandoned lane.

### Changed

- **`loop-verify`'s prompt is shorter than before**, not longer: the test-quality
  heuristics and Laravel checks moved into `verify-playbook` rather than being
  duplicated across both. Moving method out of an always-loaded prompt is the point.
- `loop-protocol` gains a **Cookbooks** table mapping each phase and moment to the skill
  it should invoke, placed deliberately last in the file so nothing above it shifts in
  the cached prefix every agent loads.
- `loop-build` invokes `loop-debug` on the first red and `test-design` when a slice names
  a set; `loop-slice` invokes `test-design` at the five-test check; `/loop` invokes
  `worktree-merge` where parallel lanes are merged.

### Fixed

- README's intro claimed "two hooks" while its own Guardrails section said three — stale
  since v0.3.0. Five hook scripts are actually registered; the intro now says five, and
  names the six cookbooks.

### Notes

- No new agent, command, or hook. No change to the 2–3 lane cap, worktree isolation, the
  refine cap, `loop-verify`'s read-only constraint, or the PASS / CONCERNS / FAIL
  vocabulary.
- The harness validates every `skills/*/SKILL.md` for `name` and `description`
  frontmatter by globbing the directory, so the four new skills are covered without new
  cases — verified by breaking one deliberately and confirming the suite named it.

## [0.3.1] - 2026-08-14

Test and documentation hardening only — no behavior change, no new command, no new
acceptance criteria. Closes five gaps filed as follow-up during the v0.2.0 and v0.3.0
releases.

### Fixed

- **A genuine, reproducible test flake** in the `warn-full-suite.sh` harness cases
  (`FS1`/`FS4`), first observed at roughly 1-in-15 runs. Root-caused to the test's own
  double-invocation, nested-command-substitution capture pattern racing under bash 3.2
  (macOS's stock `/bin/bash`) — the script itself wrote its warning correctly on every
  run; the test occasionally lost the captured bytes on the way back. Fixed by
  collapsing each case to a single invocation with one flat capture. Verified against
  5,500+ consecutive clean iterations and 20 consecutive full-suite runs.
- Ship's "own release readiness, not a downstream check" disclaimer is now asserted
  against `scripts/ship-check.sh`'s own stdout, not only `commands/ship.md`'s prose.
- Observe's O4 (attribution as a followable reference), O5 (no credentials, no
  telemetry, no network call), and O6 (project-agnostic) now have dedicated harness
  cases — previously only O1-O3 did. `commands/observe.md`'s procedure already covered
  all three; only the missing assertions were added.
- `loop-protocol`'s claim that the outer loop's `↺` resolves to Observe's capture step
  is now tested directly — previously only README's equivalent claim was.
- A stale header comment in `scripts/check-budget-gate.sh` overstated when the budget
  gate reads stdin relative to its unset-check; corrected to match the actual code.

### Notes

- Harness grew from 121 to 334 cases across v0.2.0, v0.3.0, and this release combined.
- No version file, script behavior, hook registration, or command surface changed
  beyond the fixes above.

## [0.3.0] - 2026-08-13

Closes the reporting gap v0.2 deliberately left open: the ledger existed but nothing read
it, and nothing could pause a spawn on spend. Ships the full v0.3 row of the
cost-optimization requirements doc in one release — `/cost`, the budget gate, per-phase
expectations, cost in the delivery log, and the full-suite guard — with no threshold
shipped as a default anywhere, by explicit decision (G0-D1): this repo holds no spend
baseline, and most invocations recorded so far carry no token figure at all, so any number
offered would be a guess dressed as a default.

### Added

- **`/cost [slug]`** — reports what `.claude/loop-cost.jsonl` can see for one unit of
  work, coverage stated before any total, always: how many invocations were observed, how
  many carry a token figure, how many do not, per phase. A partial total is labelled as
  covering only the priced subset, never presented as the whole, and where nothing for a
  unit is priced no token table is printed at all. Rework is reported as invocation counts,
  with a token share only where those invocations are priced, and no verdict is ever
  printed against the source requirements doc's rework target — v0.2's whole-invocation
  attribution already made that comparison invalid by definition. Reads only the ledger:
  no network call, no account, no reading of Laravel Guild's `agents-board.jsonl`.
- **Budget gate** (`scripts/check-budget-gate.sh`) — `LARAVEL_LOOP_BUDGET_WARN` and
  `LARAVEL_LOOP_BUDGET_HARD`, both unset by default and doing nothing at all until a human
  sets a number. An unparseable value disables that threshold loudly, naming the variable
  and the value, rather than falling back to anything. At the hard threshold the loop
  pauses before the next spawn and presents numbered options; a slice already in flight
  always completes. Raising the cap at that pause applies to the current unit only.
- **Per-phase expectations** — `LARAVEL_LOOP_BUDGET_PHASE_SPEC` / `_SLICE` / `_BUILD` /
  `_VERIFY`, same discipline: unset by default, flags an overrun in that phase's own
  return without ever blocking, and the flag always carries its own coverage caveat.
- **Full-suite guard** (`scripts/warn-full-suite.sh`) — the one guard in this plugin that
  warns instead of refusing: an unfiltered test suite run by `loop-build` mid-slice prints
  to stderr and exits 0, naming its escape hatch (`LARAVEL_LOOP_ALLOW_FULL_SUITE=1`)
  inline. The command underneath it still runs, unchanged.
- **Cost in the delivery log** — `/loop`'s close step now writes a `## Cost` section into
  `docs/loop/<slug>/log.md`, replaced rather than duplicated on a re-run, carrying its own
  coverage statement and any budget event that fired during the unit.

### Notes

- No threshold ships as a default for any of the five new variables above, anywhere in
  this plugin or this README — not baked in, not commented out, not offered as a
  "suggested starting value." Set one from your own ledger's observed totals once you
  have some.
- Harness grew from 121 to 329 cases; shellcheck stays clean throughout.
- DC2 and DC3 (the report recognised against a real run; the gate observed doing nothing,
  then observed firing) are open, human-judged conditions, the same footing as v0.2's
  still-open DC1 — passing verify means this is built, not yet that it is trusted in the
  field.

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
