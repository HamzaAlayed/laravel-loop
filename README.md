# Laravel Loop

**A 4-agent Laravel team organized by delivery phase instead of job title.**

Most agent packs give you a org chart — a backend developer, a QA engineer, a tech lead. Laravel Loop gives you a **loop**. Four agents, one per phase, each owning its stage end to end, with human gates between them and two hooks that make the rules real instead of aspirational.

```
OUTER — per unit of work
  Intent → Spec → Slice → Build → Verify → Ship → Observe
             G0     G1              G2      G3      ↺

INNER — per slice, one agent, one worktree
  Parse → Plan → Generate → Validate ─┬→ done (green)
                    ↑                 │
                    └─── Refine ──────┘  red — cap 3, then blocked
```

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

## Skills

Loaded on demand via the `Skill` tool, so the detail costs nothing until a task needs it.

| Skill | Cookbook |
|---|---|
| `loop-protocol` | The contract — gates, phase placement, slice-quality test, task envelope, return shape, refine cap, determinism boundary |
| `laravel-validate` | The Validate step — toolchain detection (Sail/Pest/Larastan/Pint), command order, reading a failure into a next action, the pre-return self-check |

## Guardrails

Two hooks. Both scoped to **subagents** via the payload's `agent_type` — a human on the main thread is never blocked, because a human doing these things is a deliberate, visible act and an agent doing them mid-refine is not.

| Script | Event | Blocks |
|---|---|---|
| `enforce-refine-cap.sh` | `PostToolUse` / `Bash` | The 3rd consecutive **failing** run of the same test target. Wired PostToolUse deliberately: it needs the command's *result*, so it counts failures rather than attempts, and a green run resets that target — normal red→green TDD never trips it. Cap via `LARAVEL_LOOP_REFINE_CAP` (default `3`, `0` disables). |
| `block-untested-commit.sh` | `PreToolUse` / `Bash` | A `git commit` staging application code with no test staged alongside it. Migrations, config, docs, assets, and framework service providers are carved out. Escape hatch: `LARAVEL_LOOP_ALLOW_UNTESTED=1`. |

Together they close both exits from a red test: grinding on it, and making it go away.

**Guards need escape hatches.** Both have one, and each block message names it. A guard that is occasionally wrong and cannot be overridden gets disabled wholesale the first time it is wrong — which is worse than not having it.

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

Three files, in your repo, human-readable and deletable. Agents propose; you approve; the repo remembers.

| File | Holds |
|---|---|
| `docs/loop/conventions.md` | Rules you taught — every agent treats these as overrides |
| `docs/loop/decisions.md` | Approaches **tried and rejected**, with why |
| `docs/loop/<slug>/` | `spec.md`, `slices.md`, `verify.md`, `log.md` for one unit of work |

`decisions.md` is the one teams skip and then regret. Git tells an agent what the code *is*; nothing else records "we tried this in March, it broke under load, stop proposing it." Without it, every new session re-proposes your rejected designs and you re-litigate them by hand.

## Using it with Laravel Guild

Laravel Loop is fully standalone — its own agents, skills, guardrails, env vars, and state file (`.claude/loop-refine-passes.tsv`), so both can be installed side by side without collision.

They answer different questions. Reach for the **Guild** when you want a named specialist for a specific craft — a security review, a query plan, an accessibility audit. Reach for **Loop** when you want the delivery process itself to be the thing enforcing quality. Running both, a reasonable split is Loop for the spine and Guild specialists called in at Verify.

## Development

```bash
bash tests/guardrails.test.sh   # 22 cases, zero dependencies
shellcheck scripts/*.sh
```

CI runs both on every push.

## Not included in v0.1

Named deliberately, because a plugin that hides its edges is worse than one that states them:

- **No Ship phase automation.** G3 is a gate in the protocol, but there is no release command yet — use your existing pipeline.
- **No Observe phase.** Production telemetry → issue → next intent is documented as the loop's closing edge, not automated.
- **No Gemini or Codex target.** Both guardrails need agent identity in the hook payload, which those hosts do not carry.
- **Frontend, mobile, infra, and docs** have no dedicated phase agent. `loop-build` handles what it can; deep specialist work is where Laravel Guild earns its keep.

## License

MIT © Hamza Alayed
