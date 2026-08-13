# Slices — ship-observe-automation

Spec: `docs/loop/ship-observe-automation/spec.md` (G0 approved, D1–D5 recorded).
Owner of every slice: `loop-build`. No slice touches both Ship and Observe.

```
S1 ─┬─ S2 ─ S3 ─ S4 ──┬─ S7
    └─ S5 ────────────┤
S6 ──────────────────-┘
```

**Critical path:** S1 → S2 → S3 → S4 → S7
**Genuinely concurrent:** S6 (Observe) from the start · S5 alongside S2–S4
**Serialized by shared file, not by logic:** S2, S3, S4 all edit `scripts/ship-check.sh` — each depends only on S1, but they merge in the stated order.

## The seam

The first observable value is **a verdict that cannot lie about a gate nobody ran** (D2). That is the runner, not a gate — so S1 ships the runner with all three gates declared, two of them real, and the third honestly reporting `not-run` and therefore `hold`. That intermediate state is not a stub excuse: it is exactly what the spec says must happen when a gate has no result. Every later Ship slice converts one `not-run` into a real result or adds context around the verdict.

## Shared testing pattern (established in S1, inherited by S2–S5)

Ship is tested against a **temporary git-repo fixture**, never against this repo:

- `mktemp -d`, `git init`, write `scripts/`, `tests/`, `VERSION`, `.claude-plugin/*.json` stubs,
  `cp scripts/ship-check.sh "$FIX/scripts/"`, run it with `cd "$FIX"`.
- Stub gates are one-line scripts that print a sentinel and exit with a chosen code, so
  pass / fail / missing / hanging are all reachable deterministically.

**Running the real `ship-check.sh` at this repo's root from inside `tests/guardrails.test.sh` recurses**, because gate 1 *is* that harness. Every Ship case runs in a fixture. This is on each Ship slice's `Do NOT`.

---

### S1 — Build the Ship gate runner with three declared gates and one verdict
Owner:       loop-build
Context:     `docs/loop/ship-observe-automation/spec.md` (S1, S2, S3, S4, S6, S7, S8 + failure-mode
             rows for "not installed", "missing file", "expecting a deploy", "outside a git
             repository", "output contains secrets"). Style to follow: `scripts/enforce-refine-cap.sh`
             — `#!/usr/bin/env bash`, `set -uo pipefail`, a header comment that explains *why*, not
             just what. Harness pattern to extend: `tests/guardrails.test.sh` (`expect` helper,
             section banner, exit code = failure count).
Constraints: - New file `scripts/ship-check.sh`, executable bit set, clean under
               `shellcheck -S warning scripts/*.sh` (CI runs exactly this).
             - Zero dependency: bash + coreutils only. No jq, node, python, composer — the script
               must work when none are installed.
             - Gate set is hard-coded and exactly three, in this order: `bash tests/guardrails.test.sh`,
               `shellcheck scripts/*.sh`, version consistency. No discovery, no detection.
             - Exactly three gate lines print on every run, each with an explicit state:
               `passed` / `failed` / `not-run`. Gate 3 prints `not-run (not yet implemented)` in this
               slice — honest, and therefore `hold`.
             - Read-only. No write outside `mktemp` scratch, no network, no git command that mutates.
             - Prints the failing gate's own captured output verbatim; adds no environment dump,
               no `set -x`, no echo of variables the gate did not itself print.
             - Not inside a git work tree → say so and stop before running any gate.
             - Gates run untimed in this slice; S3 adds time-bounding.
Output:      `scripts/ship-check.sh`; a new `ship-check.sh (G3 release readiness)` section in
             `tests/guardrails.test.sh` with at least these cases:
             `ship: summary prints exactly three gate lines`,
             `ship: all runnable gates passing gives go and exit 0`,
             `ship: a failing gate gives hold and non-zero exit`,
             `ship: a failing gate's own output appears verbatim`,
             `ship: shellcheck absent from PATH reads not-run, verdict hold`,
             `ship: a missing gate file reads not-run by name, verdict hold`,
             `ship: two runs on an unchanged tree give the same verdict and exit code`,
             `ship: fixture refs, tags, and porcelain status are byte-identical after a run`,
             `ship: outside a git work tree it says so and runs no gate`,
             `ship: summary states it publishes and deploys nothing`.
Done when:   In a fixture whose three stub gates all pass, one invocation prints three `passed`
             lines, one `go`, exits 0, and the fixture's `git status --porcelain`, `git show-ref`,
             and `git tag` output are unchanged. In a fixture where `shellcheck` is not reachable,
             the shellcheck line reads `not-run`, the verdict is `hold`, and the exit is non-zero.
             The ten cases above are green and the existing 22 still pass
             (`bash tests/guardrails.test.sh` → `ALL GREEN`, total ≥ 32).
Do NOT:      - Do not invoke `scripts/ship-check.sh` against this repository's own root from inside
               the harness — gate 1 is that harness and it will recurse.
             - Do not tag, push, publish, bump a version, or write any file in the repo.
             - Do not implement the version-consistency comparison (S2), timeouts (S3), dirty-tree or
               unit-contract context (S4), or `commands/ship.md` (S5).
             - Do not touch `scripts/enforce-refine-cap.sh`, `scripts/block-untested-commit.sh`,
               `hooks/hooks.json`, `README.md`, or the existing 22 harness cases.
             - Do not add a fifth agent, a hook registration, or a CI step.
Depends on:  nothing

Five-test: **1** one owner, one script + its harness section. **2** one commit — one new file, one
new test section. **3** names ten cases that do not exist today and pass after. **4** criteria are
printed states, verdict, exit code, and fixture state after the run — no assertion about how the
gates are dispatched. **5** depends on nothing, stated.

---

### S2 — Implement the version-consistency gate without a JSON parser
Owner:       loop-build
Context:     Spec S5 and the failure-mode rows "The three version files disagree" and "A version file
             is unreadable or its version field absent". The three subjects: `VERSION` (bare
             `0.1.0\n`), `.claude-plugin/plugin.json` (top-level `"version"`),
             `.claude-plugin/marketplace.json` (`plugins[0].version`, nested — note there is no
             top-level `version` key in that file). Runner and fixture harness from S1.
Constraints: - Reading the two JSON files uses bash + coreutils only (`grep`/`sed`). jq or python3 may
               be *absent*; if the builder chooses to use one when present it must be a pure
               optimisation with the coreutils path tested, otherwise do not use them at all.
             - The summary names each of the three files and the value found in each, on disagreement.
             - A file that is missing, unreadable, or has no version field is `hold` and named — never
               silently treated as matching, never skipped from the report.
             - `marketplace.json`'s value is read from the plugin entry, not from whatever the first
               `"version"` string in the file happens to be.
             - Gate 3's line changes from `not-run (not yet implemented)` to a real
               `passed` / `failed` / `not-run` state. The three-line summary shape from S1 is unchanged.
Output:      Version gate implemented in `scripts/ship-check.sh`; new cases in the harness's ship
             section: `ship: three agreeing versions pass the version gate`,
             `ship: a disagreeing version file gives hold and names all three files with values`,
             `ship: a missing version file gives hold and names it`,
             `ship: a version field absent from plugin.json gives hold, not a match`,
             `ship: marketplace version is read from the plugin entry, not the first match`,
             `ship: version gate works with jq and python3 unavailable on PATH`.
Done when:   A fixture with `VERSION=0.2.0`, `plugin.json` at `0.2.0`, `marketplace.json` at `0.1.9`
             produces `hold`, non-zero exit, and a summary naming all three paths with `0.2.0`,
             `0.2.0`, `0.1.9`. The same fixture with all three at `0.2.0` and passing stub gates
             produces `go` and exit 0. Both hold with `PATH` stripped of jq and python3.
             `bash tests/guardrails.test.sh` → `ALL GREEN`.
Do NOT:      - Do not edit, normalise, or bump any version file — reporting a mismatch is the whole
               job (spec: "Not a changelog generator or version bumper").
             - Do not check CHANGELOG for an entry, and do not check the executable bit. Both were
               explicitly considered and rejected at G0.
             - Do not add jq, python3, or any package as a requirement.
             - Do not change the summary layout, verdict wording, or exit semantics S1 fixed.
             - Do not run ship-check against this repo's root from the harness.
Depends on:  S1

Five-test: **1** one owner, one gate. **2** one commit — one function plus its cases. **3** six named
cases, all red before (gate 3 currently reads `not-run`). **4** criteria are the printed file names
and values and the verdict — not how the JSON is read. **5** S1, stated; merges before S3 and S4
because all three edit `scripts/ship-check.sh`.

---

### S3 — Time-bound every gate so a hung gate becomes a hold, not a hang
Owner:       loop-build
Context:     Spec failure-mode row "A gate never returns → Time-bounded, and the timeout is reported
               as a hold. A human is never left without a verdict." Runner from S1.
             Portability trap: GNU `timeout` is present on the CI runner (ubuntu) and **absent from a
             stock macOS** — the maintainer's own machine. A bash fallback (background the gate, poll,
             kill the process group) is required, or the guarantee only holds on Linux.
Constraints: - Per-gate wall-clock bound with a sane default; overridable via a `LARAVEL_LOOP_*`
               environment variable, matching how the existing guardrails expose their overrides.
               `LARAVEL_LOOP_` prefix keeps it clear of Laravel Guild.
             - A timed-out gate is reported by name with its own state and **never reads as passed**;
               the verdict is `hold` with a non-zero exit.
             - Works with `timeout` absent from `PATH`. The fallback leaves no orphan process behind.
             - Still exactly three gate lines. Still read-only. Still shellcheck-clean.
Output:      Time-bounding in `scripts/ship-check.sh`; harness cases
             `ship: a gate that never returns is bounded and gives hold`,
             `ship: a timed-out gate never prints as passed`,
             `ship: the bound holds with timeout(1) absent from PATH`,
             `ship: no orphan child survives a timed-out run`.
Done when:   A fixture whose stub gate runs `sleep 600` returns a `hold` verdict and non-zero exit in
             under the configured bound (test sets the bound low, e.g. 2s), both with `timeout` on
             `PATH` and with a `PATH` that lacks it; no `sleep 600` process remains afterwards.
             `bash tests/guardrails.test.sh` → `ALL GREEN`.
Do NOT:      - Do not require GNU coreutils `timeout`, `gtimeout`, `perl`, or `python3`.
             - Do not apply a global timeout to the whole run in place of per-gate bounds — a
               whole-run timeout cannot say *which* gate hung.
             - Do not change gate order, the summary shape, the version gate, or the verdict wording.
             - Do not run ship-check against this repo's root from the harness.
Depends on:  S1. Merge after S2 (shared file `scripts/ship-check.sh`).

Five-test: **1** one owner, one property. **2** one commit — a wrapper around gate dispatch plus four
cases. **3** the four cases fail today: a hung gate currently hangs forever. **4** criteria are
"verdict returned within the bound, gate named, never passed, no orphan" — observable, not
implementation. **5** S1 logically, S2 by merge order, both stated.

---

### S4 — Add the release-context block: dirty tree and unit contract
Owner:       loop-build
Context:     Spec S9 and the failure-mode rows "Working tree is dirty when Ship runs" and "No
             `docs/loop/<slug>/` for the unit". Runner from S1. `docs/loop/<slug>/` holds `spec.md`,
             `slices.md`, and optionally `verify.md` — see `docs/loop/ship-observe-automation/`.
Constraints: - Context is reported, it does not change the verdict. A dirty tree is stated because the
               tree is not what a release would contain; it is not a fourth gate. The verdict stays a
               function of exactly the three gate results (spec S6).
             - Slug resolution takes an optional argument; with no argument, resolve from the current
               branch or say plainly that no unit contract was found. Never guess a slug, and never
               pick "the most recent directory" as a stand-in for knowing.
             - Present or absent, it is stated. "No unit contract found" is printed, not omitted —
               same discipline as `not-run` for gates.
             - Read-only: `git status --porcelain` and reads under `docs/loop/` only.
Output:      Context block in `scripts/ship-check.sh`; harness cases
             `ship: a dirty fixture tree is reported and the verdict is unchanged`,
             `ship: a named slug with a verify record is reported as present`,
             `ship: a named slug without a verify record says so`,
             `ship: no unit contract found is stated, not omitted`.
Done when:   In a clean fixture with `docs/loop/demo/spec.md` and no `verify.md`, running with the
             slug prints the slug and states the verify record is absent, while the verdict still
             matches the same run without a slug. Touching an untracked file in the fixture adds a
             dirty-tree line and leaves the verdict and exit code identical.
             `bash tests/guardrails.test.sh` → `ALL GREEN`.
Do NOT:      - Do not let context influence go/hold — a dirty tree or a missing contract must not flip
               the verdict, or S6's determinism claim stops being true.
             - Do not read, parse, or re-check acceptance criteria out of `spec.md`, and do not read
               the diff. That is G2 and `loop-verify` owns it (spec: "No second verifier").
             - Do not create, move, or write anything under `docs/loop/`.
             - Do not change the three gate lines, the verdict wording, or the exit semantics.
             - Do not run ship-check against this repo's root from the harness.
Depends on:  S1. Merge after S3 (shared file `scripts/ship-check.sh`).

Five-test: **1** one owner, one output block. **2** one commit. **3** four named cases, red today.
**4** criteria are printed lines plus "verdict unchanged" — behaviour a human can read off two runs.
**5** S1 logically, S3 by merge order, both stated.

---

### S5 — Add the `/ship` command surface
Owner:       loop-build
Context:     Spec S8, X1, and the failure-mode rows "Someone runs Ship expecting a deploy" and
             "Someone runs Ship inside a downstream Laravel project". Shape to follow exactly:
             `commands/verify.md` — frontmatter with `description` and `allowed-tools`, an
             `argument-hint`, a short "What you do" numbered body. Frontmatter is validated by the
             existing `frontmatter_check` case in `tests/guardrails.test.sh`.
Constraints: - Thin. The command runs `bash scripts/ship-check.sh` and relays its output verbatim.
               No agent spawned, no judgment applied, no verdict re-interpreted — Ship sits on the
               deterministic side of the protocol's determinism boundary.
             - `allowed-tools` is read-only (`Bash`, `Read`, `Glob`, `Grep`, `AskUserQuestion`).
               No `Write`, no `Edit`, no `Agent`.
             - The body states plainly: this checks laravel-loop's own release readiness; it deploys,
               publishes, tags, and bumps nothing; it is **not** a downstream Laravel app's gate check
               and does not overlap `laravel-team:ship-checklist`.
             - On `hold`, the command stops. On `go`, it presents G3 as numbered options with the
               release action left to the human (G4).
Output:      `commands/ship.md`; harness cases
             `ship: commands/ship.md declares no write-capable tool`,
             `ship: commands/ship.md states nothing is deployed, published, or tagged`,
             `ship: commands/ship.md disclaims downstream Laravel app gates`.
Done when:   `commands/ship.md` exists, the existing frontmatter case still passes over it, and the
             three new cases pass by grepping the file for a write-capable tool (absent) and for the
             two disclaimers (present). `bash tests/guardrails.test.sh` → `ALL GREEN`.
Do NOT:      - Do not spawn an agent, and do not create a fifth agent in `agents/`.
             - Do not have the command re-run gates itself, re-derive a verdict, or soften a hold.
             - Do not add tagging, pushing, publishing, or version-bump steps even behind a
               confirmation — that is G4 and stays a human action.
             - Do not edit `scripts/ship-check.sh`, `README.md`, `commands/loop.md`, or
               `commands/verify.md`.
Depends on:  S1 (the script it invokes must exist). Runs concurrently with S2–S4 — different files.

Five-test: **1** one owner, one markdown surface. **2** one commit. **3** three named cases plus the
existing frontmatter case now covering a new file. **4** criteria are what the file declares and
what it says to the human. **5** S1, stated.

---

### S6 — Add the Observe capture procedure and `/observe` command surface
Owner:       loop-build
Context:     Spec O1–O6 and D4/D5, plus the failure-mode rows "Observe capture would collide with an
             existing slug", "no reproduction, no suspect, no timestamp", "cannot be attributed to any
             merged unit", "run outside a git repository". Shape to follow: `commands/verify.md` and
             `commands/slice.md`. Prior art for what an intent is *not*:
             `docs/loop/ship-observe-automation/spec.md` is a spec — a capture is thinner than that.
Constraints: - **No new script.** Markdown only: `commands/observe.md` carrying the procedure and an
               inline fenced template for `docs/loop/<slug>/intent.md`.
             - The capture records exactly five things — what was observed, where it surfaced, when,
               what was already tried, which unit or commit is suspected. Any unknown is written as
               `unknown`. None is ever inferred, and the procedure says so in those words.
             - It is an **intent, not a spec**: no acceptance criteria, no non-goals, no slices. The
               documented next step is the normal entry at G0 (`/loop`), and nothing builds from it.
             - Never writes to or edits an existing unit's `spec.md`, `slices.md`, or `verify.md`.
               A slug collision is refused or given a distinct slug — never an overwrite.
             - Attribution to a merged unit, when known, is recorded as a followable in-repo reference
               to that unit's slug. When unknown, no link and no guess.
             - Project-agnostic: writes markdown under `docs/loop/`, assumes nothing about language or
               toolchain, needs no credentials, no telemetry client, no network. Works from a pasted
               stack trace or one sentence of prose.
Output:      `commands/observe.md`; a new `observe (capture procedure)` harness section with cases
             `observe: no capture script exists — the surface is markdown only`,
             `observe: procedure names all five required capture fields`,
             `observe: procedure records unknown rather than inferring`,
             `observe: procedure forbids editing an existing unit's spec, slices, or verify`,
             `observe: procedure refuses a slug collision`,
             `observe: capture carries no acceptance criteria and hands off at G0`.
Done when:   `commands/observe.md` exists with valid frontmatter (the existing frontmatter case covers
             it), `ls scripts/` contains no `observe`/`capture` script, and the six cases pass.
             `bash tests/guardrails.test.sh` → `ALL GREEN`.
Do NOT:      - Do not add any file under `scripts/`, and do not add a hook.
             - Do not add a telemetry client, log tailing, polling, a webhook receiver, or any network
               call.
             - Do not triage, diagnose, reproduce, assign a cause, or auto-start the loop from a
               capture.
             - Do not create a new state format — plain markdown under `docs/loop/` only.
             - Do not edit `README.md` or `skills/loop-protocol/SKILL.md` (S7 owns those), and do not
               touch anything under `scripts/` or `commands/ship.md`.
Depends on:  nothing. Runs concurrently with the whole Ship chain.

Five-test: **1** one owner, one markdown surface. **2** one commit — one new command file plus its
harness section. **3** six named cases, red today (`commands/observe.md` does not exist). **4** the
criteria are what the procedure instructs and refuses; the caveat is that these are contract-shape
assertions over a document, because the executor is a human-plus-agent, not a script — flagged below.
**5** depends on nothing, stated.

---

### S7 — Close the `↺`: make README and the protocol match what shipped
Owner:       loop-build
Context:     Spec X1, O7, and the constraint that the four-agent claim stays true. Files: `README.md`
             ("Not included in v0.1" bullets 1 and 2, the Commands table, the Development section's
             "22 cases"), `skills/loop-protocol/SKILL.md` (the outer-loop diagram's `↺`, the phase
             placement table's "A production fault" row, the gate table's G3).
Constraints: - Retire only the first two "Not included in v0.1" bullets. The Gemini/Codex bullet and
               the specialist-agent bullet stay exactly as they are.
             - Replacement wording states Ship checks **laravel-loop's own release readiness**, not a
               downstream Laravel app's gates, and does not overlap `laravel-team:ship-checklist`.
             - The Commands table gains a row for every command file added (`/ship`, `/observe`).
             - The Development section's case count matches the harness's actual total.
             - The protocol's Observe phase names the capture step so the `↺` resolves to it, and G3
               names `ship-check.sh` as the evidence behind the ship/hold decision.
             - Still four agents. No change to the agent table, the guardrail table, or the install
               instructions.
Output:      Updated `README.md` and `skills/loop-protocol/SKILL.md`; harness case
             `docs: every commands/*.md has a row in README's Commands table`,
             `docs: README no longer claims Ship and Observe are missing`.
Done when:   `bash tests/guardrails.test.sh` → `ALL GREEN` with the new generic case passing over
             `/loop`, `/slice`, `/verify`, `/ship`, `/observe`; README's Development section states the
             harness's real total (> 22); the two retired bullets are gone and the other two remain;
             `shellcheck -S warning scripts/*.sh` clean.
Do NOT:      - Do not claim a fifth agent, a new phase agent, or downstream-project gate coverage.
             - Do not remove or reword the Gemini/Codex bullet or the specialist-agent bullet.
             - Do not edit `scripts/*.sh`, `commands/*.md`, `CHANGELOG.md`, `VERSION`, or either
               `.claude-plugin/*.json` — version and changelog changes are the human's release action.
             - Do not update `docs/loop/conventions.md` or `docs/loop/decisions.md`; those record human
               corrections, not build output.
Depends on:  S1, S2, S3, S4, S5, S6 — it states what shipped, so it merges last.

Five-test: **1** one owner, docs only. **2** one commit. **3** the generic Commands-table case fails
today the moment `commands/ship.md` exists and README lacks a row. **4** criteria are what a reader
of README finds and no longer finds. **5** all six prior slices, stated.

---

## Riskiest slice

**S1 — the runner.** Three reasons, in order:

1. **Fan-out.** Five slices extend it. Its output contract — three lines, the state vocabulary
   `passed / failed / not-run`, the verdict wording, the exit semantics — is fixed here and inherited
   everywhere. A wrong cut at S1 is a re-slice of S2–S5, not a patch.
2. **Its hardest requirement is a design property, not a line of code.** S4/D2 says a gate nobody
   could run must never read as a gate that passed. That is the failure the whole spec exists to
   prevent, and it fails silently: a false `go` looks exactly like a true one. The named cases
   (`shellcheck absent from PATH`, `missing gate file`) exist to make it fail loudly instead.
3. **The harness recursion trap.** Gate 1 is `bash tests/guardrails.test.sh`, and the tests for Ship
   live in that same file. A builder that reaches for the obvious test — "run ship-check and check the
   output" — recurses. The fixture pattern is specified up front for exactly this reason, and it is on
   the `Do NOT` line.

Runners-up worth watching, but not re-cutting for:

- **S3 (timeouts).** `timeout(1)` is not on stock macOS, so the "a human is never left without a
  verdict" guarantee needs a bash fallback that also reaps its children. It is isolated deliberately:
  if it burns three refine passes it blocks only itself.
- **S6 (Observe).** Its tests assert the *shape of a document*, not runtime behaviour, because D4 says
  no script. That is the weakest evidence in this plan and it is weak by design — worth the human
  knowing before approving, since no harness case can prove a capture actually records `unknown`
  rather than a guess.
