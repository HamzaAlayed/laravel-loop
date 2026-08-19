# Laravel Loop

**A 4-agent Laravel team organized by delivery phase instead of job title.**

Most agent packs give you a org chart — a backend developer, a QA engineer, a tech lead. Laravel Loop gives you a **loop**. Four agents, one per phase, each owning its stage end to end, with human gates between them, seven on-demand cookbooks carrying each phase's method, and five hooks that make the rules real instead of aspirational.

```
OUTER — per unit of work
  Intent → Spec → Slice → Build → Verify → Ship → Observe
             G0     G1              G2      G3      ↺

INNER — per slice, one agent, one worktree
  Parse → Plan → Generate → Validate ─┬→ done (green)
                    ↑                 │
                    └─── Refine ──────┘  red — cap 3, then blocked
```

A fifth gate, **G4**, sits outside this line: it fires whenever an agent is about to take any production-affecting action (a deploy, a rollback, a live-data change), regardless of which outer phase triggered it. See `loop-protocol` for the full gate table.

---

## Why phases, not roles

A role-based team answers "who does this?". A phase-based team answers the question that actually goes wrong: **"is this ready to hand on?"**

The failure mode of AI-assisted development is not bad code generation — it is unstructured delegation. One large ambiguous ask, handed to one agent, producing work that reads like several people who never spoke. Every phase below exists to move an ambiguity earlier, to where fixing it is cheap: a wrong cut costs a sentence at G1 and a rewrite at G2.

Four agents is also small enough to hold in your head. You always know which one you are talking to and why.

## The team

| Agent | Phase | Owns | Can write code? |
|---|---|---|---|
| `loop-spec` | Spec (G0) | Intent → `spec.md` with acceptance criteria and explicit non-goals | No — refuses |
| `loop-slice` | Slice (G1) | Spec → `slices.md`, five-test-clean, with `Do NOT` per slice | No — refuses |
| `loop-build` | Build | One slice → green code **and its test**, or `blocked` with evidence | Yes, in a worktree |
| `loop-verify` | Verify (G2) | Built work → PASS / CONCERNS / FAIL against the spec | No — read-only by design |

`loop-spec` and `loop-slice` run on Opus (framing and decomposition have long consequences). `loop-build` and `loop-verify` run on Sonnet. `loop-verify` has `Edit` and `Write` removed: a verifier that can rewrite the code it is verifying cannot be trusted to have verified it.

## Commands

| Command | What it does |
|---|---|
| `/loop <intent>` | The whole outer loop — spec, slice, build, verify — stopping at every gate. The main entry point. |
| `/slice <spec>` | G1 alone, when a spec already exists and the only question is how to cut the work. |
| `/verify [slug\|base]` | G2 alone, before opening or merging a PR — including when the claim of "done" is your own. |
| `/ship` | G3 alone — runs `scripts/ship-check.sh`'s three release-readiness gates and relays the go/hold verdict verbatim. Checks **laravel-loop's own** release readiness only, never a downstream Laravel app's gates, and does not overlap `laravel-team:ship-checklist`. |
| `/observe [fault]` | The `↺` — captures a fault or observation as a new `docs/loop/<slug>/intent.md` (what, where, when, tried, suspected unit), then hands off to `/loop` at G0. Never diagnoses, never builds. |
| `/cost [slug]` | Reports what `.claude/loop-cost.jsonl` can see for one unit of work — coverage stated before any total, always — or lists every unit the ledger holds with no argument. Reads only that file; no network call, no account, no dollar figure. |

## Skills

Loaded on demand via the `Skill` tool, so the detail costs nothing until a task needs it.

| Skill | Cookbook |
|---|---|
| `loop-protocol` | The contract — gates, phase placement, slice-quality test, task envelope, return shape, refine cap, determinism boundary |
| `build-conventions` | The Generate step — requirement-to-primitive mapping, the antipatterns `loop-verify` looks for, the three reasons people get wrong under pressure, and why matching the codebase outranks the cookbook |
| `laravel-validate` | The Validate step — toolchain detection (Sail/Pest/Larastan/Pint), command order, reading a failure into a next action, the pre-return self-check |
| `test-design` | Which tests a slice needs (G1) — red-before-green, pairwise selection when the cross-product is unaffordable, the minimum set, which level to test at, and when a test set means the slice should have been two |
| `loop-debug` | The Refine step as an experiment — classifying a failure as a code, test, or slice defect, one falsifiable hypothesis per pass, the isolation ladder, and what a useful `blocked` escalation carries |
| `verify-playbook` | Gate G2's method — the acceptance-criteria walk, test-quality smells, tracing a failure the diff cannot explain, and how a scoped verdict declares its own scope |
| `worktree-merge` | Integration — merge order from the dependency graph, the full suite after each merge, conflict ownership, migration collisions, and why an "independent" slice conflict is a G1 defect |

## Guardrails

Three hooks. All scoped to **subagents** via the payload's `agent_type` — a human on the main thread is never blocked or warned, because a human doing these things is a deliberate, visible act and an agent doing them mid-refine or mid-slice is not.

| Script | Event | Blocks |
|---|---|---|
| `enforce-refine-cap.sh` | `PostToolUse` / `Bash` | The 3rd consecutive **failing** run of the same test target. Wired PostToolUse deliberately: it needs the command's *result*, so it counts failures rather than attempts, and a green run resets that target — normal red→green TDD never trips it. Cap via `LARAVEL_LOOP_REFINE_CAP` (default `3`, `0` disables). |
| `block-untested-commit.sh` | `PreToolUse` / `Bash` | A `git commit` staging application code with no test staged alongside it. Migrations, config, docs, assets, and framework service providers are carved out. Escape hatch: `LARAVEL_LOOP_ALLOW_UNTESTED=1`. |
| `warn-full-suite.sh` | `PreToolUse` / `Bash` | Nothing — the one guard here that **warns instead of refusing**. When a `loop-build` subagent runs an unfiltered test suite mid-slice instead of the filtered per-slice run `laravel-validate` prescribes, it prints a message to stderr and exits `0`; the command underneath it still runs, unchanged. Scoped to `loop-build` only — a human on the main thread and `loop-verify`'s own broad re-runs are never warned. Escape hatch: `LARAVEL_LOOP_ALLOW_FULL_SUITE=1`, named inline in the warning. |

Together the first two close both exits from a red test: grinding on it, and making it go away. The third is different in kind — advice, not refusal, because a wrong block here would cost more than the suite run it might have prevented.

**Guards need escape hatches.** All three have one, and each message names it. A guard that is occasionally wrong and cannot be overridden gets disabled wholesale the first time it is wrong — which is worse than not having it.

## Cost ledger

A third hook that only observes — it never blocks a spawn. `record-cost-event.sh` is wired on `PreToolUse` and `PostToolUse` for matcher `Agent|Task` (plus `PostToolUse` / `Bash`, alongside `enforce-refine-cap.sh`, purely to detect refine passes), and writes one JSONL record per agent-invocation lifecycle signal to `.claude/loop-cost.jsonl` — a start record and a finish record per invocation, so a completed `/loop` run can be priced per invocation, per phase, and per slice.

| Script | Event | Writes |
|---|---|---|
| `record-cost-event.sh` | `PreToolUse` / `PostToolUse` (`Agent\|Task`), `PostToolUse` (`Bash`, rework detection only) | One JSONL line per lifecycle signal, appended to `.claude/loop-cost.jsonl` |

It records tokens and durations, never a dollar figure — it counts tokens and durations, it is not money, and no arithmetic ever invents a price. A `null` field means the value was unavailable, never a measured zero: an asynchronously-launched invocation, for example, may report no tokens at all and is recorded that way rather than as `0`.

Rework is attributed at whole-invocation granularity: if a slice needed even one refine pass, that build invocation's entire cost is tagged `phase_detail: "rework"`. This deliberately over-attributes — the figure measures the cost of slices that were not right first time, not the cost of retrying — so a v0.2 rework share is not directly comparable to a narrower, per-pass definition.

Disable it entirely with `LARAVEL_LOOP_COST_LEDGER=0`. Bound it with `LARAVEL_LOOP_COST_MAX_LINES` (default 5,000; oldest lines evicted first — at or under cap once a later invocation has arrived and discharged the trim, not necessarily before then). Delete `.claude/loop-cost.jsonl` at any time — the next event recreates it, and nothing else depends on its contents. It never leaves the machine: no network call, no account, nothing but a local file.

This is entirely separate from Laravel Guild's `.claude/agents-board.jsonl`, if that plugin is also installed — neither file reads the other, and both coexist without collision.

Background-launched invocations are the majority of a `/loop` run — build lanes run several at a time, by design, and that is the point of running them that way — and this hook cannot price them: a backgrounded invocation's finish event carries no token figure at all. It is recorded as launched in background, outcome never observed, never silently folded into a priced total and never guessed at. The real figure is measured by the host and delivered into the session the moment that invocation finishes; it is not captured here, and no code in this plugin reaches for it.

That real figure can still reach the ledger, but only by hand. `scripts/record-recovered-cost.sh --invocation-id <id> --total-tokens <n>` writes one recovered record for an invocation the host never priced — tagged `token_source: "transcribed"`, never `"observed"`. A recovered figure is **model-transcribed, not host-observed**: it is whatever a human or an orchestrating agent read off that invocation's own completion notification and typed in, not something this plugin measured itself. Nothing in this plugin runs that command automatically — it is a standalone CLI, not wired into any hook or spawn path — so skipping it changes nothing (RC6): a run in which nobody transcribes anything looks exactly as it always has, coverage included. Recovery narrows the gap only for the invocations somebody actually transcribed, and for no others — it does not close it.

A recovered record carries exactly one dimension: the token figure. Everything else the report shows for that invocation — its phase, its model, its slice — comes from the invocation's own `start` and `finish` records, the ones the hook already wrote; a recovered record neither carries those fields nor invents them, which is what lets a transcribed figure appear in the per-phase breakdown, the per-phase model line and the per-slice ranking at all. Where an invocation's own records named nothing, nothing is guessed: a priced invocation whose records carry no `slice` is reported as **unattributed** — counted, with its tokens, outside the ranking, so the ranking states what it cannot place instead of quietly ranking a smaller population — and a recovered record for an invocation with no `start` or `finish` anywhere is left out of the ranking and out of the priced population alike, rather than being handed a label or a place in either.

A run resumed with `SendMessage` is not recorded as an invocation at all — `hooks.json`'s matcher matches `Agent|Task`, and a `SendMessage` is neither — so its tokens are in no total this ledger produces, and a killed attempt's own tokens are recorded nowhere, by anything.

## Cost reporting and the budget gate

`/cost [slug]` reads **only** `.claude/loop-cost.jsonl` — no network call, no account, and no reading of Laravel Guild's `.claude/agents-board.jsonl` even when that file happens to sit right next to it and see more. Coverage is printed **before any total, always**: how many invocations the ledger holds for the unit, how many carry a token figure, how many do not, per phase. A total built from only the priced subset is labelled as covering that subset, never presented as the unit's whole cost, and where nothing for a unit is priced no token table is printed at all — the report says plainly that nothing about that unit's cost is observable, and why. No currency figure is ever produced: tokens, counts, and durations, never a dollar figure, never a rate card.

A per-unit budget gate (`scripts/check-budget-gate.sh`) exists, is configurable, and does **nothing at all** until a human sets a number. `LARAVEL_LOOP_BUDGET_WARN` and `LARAVEL_LOOP_BUDGET_HARD` ship with no default value anywhere in this plugin — unset means disabled, not "falls back to a number." A value that cannot be parsed disables that threshold loudly, naming the variable and the value it could not use, rather than falling back to anything. At the hard threshold the loop pauses **before the next spawn** and presents numbered options; a slice already in flight always completes — the gate pauses work, it never kills it. Raising the cap at that pause applies to the current unit only and is never carried forward as a standing value.

Per-phase expectations follow the same discipline: `LARAVEL_LOOP_BUDGET_PHASE_SPEC`, `_SLICE`, `_BUILD`, and `_VERIFY` are each unset by default, compare nothing, and raise no flag until a human sets one — see `loop-protocol`'s Per-phase expectations section for the mechanism.

**No number for any of these five variables ships anywhere in this plugin** — not in the code, not in this README, not as a "suggested starting value" in a code fence. There is no baseline to derive one from: this repository has never seen a completed `/loop` run produce a full ledger, and most invocations recorded so far carry no token figure at all — a number offered under either condition would be a guess wearing a default's clothes. Set a threshold from your own ledger's observed totals once you have some, never from a number in a document. A budget is denominated in tokens, never in money.

An unfired gate is never reported as reassurance, anywhere — not in `/cost`'s output, not in a return, not in `log.md`. Silence means either no threshold was set or the observed total has not reached it, and `/cost` always shows which.

`LARAVEL_LOOP_COST_MIN_COVERAGE` sets a coverage floor, as a whole percent, below which `/cost` prints no unit-level token total at all — the unit's cost is stated as not established, with the observed subset left visible only where the coverage figure above already showed it, never repeated as a second, competing number. Unset means today's behaviour: the total prints exactly as it always has, labelled by the observed subset. Like every other threshold in this plugin, no value ships as a default and none is suggested anywhere in this repository.

## Install

```bash
# As a Claude Code plugin — register this repo as a marketplace, then install
claude plugin marketplace add HamzaAlayed/laravel-loop
claude plugin install laravel-loop@laravel-loop

# Or drop it in a project
cp -r laravel-loop/agents laravel-loop/commands laravel-loop/skills .claude/
cp -r laravel-loop/scripts .claude/
```

Wire the hooks into `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "./.claude/scripts/block-untested-commit.sh" }
      ]}
    ],
    "PostToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "./.claude/scripts/enforce-refine-cap.sh" }
      ]}
    ]
  }
}
```

## Project memory

Four files, in your repo, human-readable and deletable. Three are agent-authored — agents propose, you approve, the repo remembers. The fourth, the cost ledger, is written automatically by a hook and never leaves your machine.

| File | Holds |
|---|---|
| `docs/loop/conventions.md` | Rules you taught — every agent treats these as overrides |
| `docs/loop/decisions.md` | Approaches **tried and rejected**, with why |
| `docs/loop/<slug>/` | `spec.md`, `slices.md`, `verify.md`, `log.md` for one unit of work |
| `.claude/loop-cost.jsonl` | Cost ledger — tokens and durations per agent invocation, not money. See [Cost ledger](#cost-ledger) above |

`decisions.md` is the one teams skip and then regret. Git tells an agent what the code *is*; nothing else records "we tried this in March, it broke under load, stop proposing it." Without it, every new session re-proposes your rejected designs and you re-litigate them by hand.

## Using it with Laravel Guild

Laravel Loop is fully standalone — its own agents, skills, guardrails, env vars, and state file (`.claude/loop-refine-passes.tsv`), so both can be installed side by side without collision.

They answer different questions. Reach for the **Guild** when you want a named specialist for a specific craft — a security review, a query plan, an accessibility audit. Reach for **Loop** when you want the delivery process itself to be the thing enforcing quality. Running both, a reasonable split is Loop for the spine and Guild specialists called in at Verify.

## Development

```bash
bash tests/guardrails.test.sh   # 511 cases, zero dependencies
shellcheck scripts/*.sh
```

CI runs three steps on every push; `docs/loop/checks.md` maps which checks run there against which run locally at G3.

## Not included in v0.1

Named deliberately, because a plugin that hides its edges is worse than one that states them:

- **No Gemini or Codex target.** Both guardrails need agent identity in the hook payload, which those hosts do not carry.
- **Frontend, mobile, infra, and docs** have no dedicated phase agent. `loop-build` handles what it can; deep specialist work is where Laravel Guild earns its keep.

## License

MIT © Hamza Alayed
