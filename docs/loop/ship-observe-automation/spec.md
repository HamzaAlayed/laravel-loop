# ship-observe-automation

Closes the first two items in README's "Not included in v0.1": no Ship-phase (G3)
automation, and no Observe phase. The other two items in that list (no Gemini/Codex
target; no frontend/mobile/infra/docs specialist agent) are out of bounds here.

**Status: G0 approved.** All five open questions were resolved by the human before
slicing — see *Decisions taken at G0* below. Open questions: none.

## Problem

The loop draws seven phases and five gates, but two of them are drawings.

**At G3, "ship or hold" is a decision with no evidence behind it.** Someone about to cut a
laravel-loop release has no single action that tells them whether the plugin is releasable.
They re-run the checks they remember, in whatever order they remember, and read the result
themselves. Two people doing this on the same tree can reach different answers, and the
same person can reach different answers on Friday than on Tuesday. What they most often get
wrong is not a failing check — it is a check nobody ran, which reads exactly like a check
that passed. The version number in particular lives in three separate files, and nothing
today notices when they disagree until someone installs the plugin and gets the wrong one.

**The loop's closing arrow does not close.** When something breaks in production, or a
merged unit turns out not to have solved the problem, the person holding that information
has nowhere to put it. They open a fresh request and describe the fault from memory, in a
sentence. The stack trace, the time, where it surfaced, what was already tried, and which
unit of work is suspected all evaporate at that moment — which is the moment they were
cheapest to record and the moment they mattered most. The next unit therefore starts from a
summary of a fault rather than the fault, and nothing in the repo connects the two.

## Users

- **The maintainer of this plugin, standing at G3 after a G2 approval**, about to tag a
  release. Today: runs remembered commands by hand, eyeballs the output, decides — or skips
  it, because CI will probably catch it. CI does not check that the three version files
  agree.
- **Whoever is holding a production fault** — on call, or reading a bug report, or
  discovering that shipped work missed. Today: writes a one-sentence prompt and loses the
  evidence, or files an issue in a tracker the loop never reads.
- **Whoever picks the work up next week.** Today: cannot tell from the repo that this unit
  exists *because* that unit broke. The `↺` is in the diagram and nowhere else.

## Acceptance criteria

Ship (G3). Ship checks **laravel-loop's own release readiness**. Its gate set is fixed at
exactly three gates and involves no toolchain detection:

- the guardrail test harness (`tests/guardrails.test.sh`)
- `shellcheck` over `scripts/*.sh`
- version consistency across `VERSION`, `.claude-plugin/plugin.json`, and
  `.claude-plugin/marketplace.json`

- [ ] **S1** One invocation runs all three gates and prints one line per gate, each
      carrying an explicit state: passed, failed, or not-run.
- [ ] **S2** The run ends in exactly one overall verdict — go or hold — and exits non-zero
      on hold.
- [ ] **S3** A failed gate produces a hold verdict and the output includes that gate's own
      output, not a summary of it.
- [ ] **S4** A gate that cannot be run — `shellcheck` not installed, a missing file — is
      reported by name as not-run, and the verdict is **hold**. No gate is ever omitted
      from the summary, and a gate nobody could run never reads as a gate that passed.
      This is the failure the whole criterion exists to prevent.
- [ ] **S5** When the three version files disagree, the verdict is hold and the summary
      names each file and the value found in it.
- [ ] **S6** Two runs against the same unchanged tree produce the same verdict. The verdict
      is a function of the three gate results, not of who or what read them.
- [ ] **S7** A run leaves the repository's refs, tags, remotes, version files, and working
      tree exactly as it found them, and makes no state-changing network call. Provable by
      comparing repo state before and after against a fixture.
- [ ] **S8** The summary a human reads states plainly that it checks laravel-loop's own
      release readiness, that it deploys and publishes nothing, and that it is not a check
      of a downstream Laravel application's gates.
- [ ] **S9** Run where a unit's contract exists under `docs/loop/<slug>/`, the summary names
      the slug and whether a verify record is present. Run where it does not, the summary
      says so rather than staying quiet about it.

Observe (`↺`). Ships as a documented procedure plus one thin command surface, and no new
script.

- [ ] **O1** Following the documented procedure with a fault report produces a new
      `docs/loop/<slug>/` whose captured intent records: what was observed, where it
      surfaced, when, what was already tried, and which unit or commit is suspected. Any of
      these that is unknown is recorded as unknown. None is ever inferred.
- [ ] **O2** A capture is an *intent*, not a spec. It carries no acceptance criteria, and
      the documented next step is the normal entry at G0. Nothing builds from a capture.
- [ ] **O3** A capture never overwrites or edits an existing unit's `spec.md`, `slices.md`,
      or `verify.md`.
- [ ] **O4** When a fault is attributed to a merged unit, the link is recorded so it can be
      followed in the repo from the new intent back to that unit's slug.
- [ ] **O5** A capture requires no service credentials and no telemetry integration. It
      works from a pasted stack trace, or from one sentence of prose.
- [ ] **O6** The capture works the same way in any repository — it writes markdown under
      `docs/loop/` and assumes nothing about the project's language or toolchain.
- [ ] **O7** README and the protocol describe Observe as a phase with a named capture step,
      and the `↺` in the diagram resolves to that step.

Both.

- [ ] **X1** README's "Not included in v0.1" no longer claims these two things are missing;
      its replacement wording states that Ship checks laravel-loop's own release readiness
      and not a downstream Laravel app's gates. Every command surface added is listed in
      README's Commands table.
- [ ] **X2** With this work included, `shellcheck -S warning scripts/*.sh` and
      `bash tests/guardrails.test.sh` both pass, every `scripts/*.sh` and `tests/*.sh` is
      executable, and the harness case count is higher than 22.
- [ ] **X3** Both existing guardrails behave exactly as they do today — same exits, same
      env-var overrides, same subagent scoping. The existing 22 cases pass unmodified.

## Non-goals

Read these out loud at G0. This is where the scope of a "release command" gets away.

- **No downstream project gates.** Ship never runs, detects, or inspects Pint, PHPStan,
  Larastan, Pest, PHPUnit, artisan, Sail, or composer, and never inspects a project that
  installed the plugin. It checks this repository's own release readiness, full stop.
- **Therefore it does not overlap, replace, or require `laravel-team:ship-checklist`.**
  Guild's checklist remains the tool for a downstream Laravel app's pre-release audit;
  Ship answers a different question about a different repository. README must not imply
  otherwise.
- **No gate discovery.** The gate set is the three named above, hard-coded. Nothing is
  inferred from the project's files.
- **No deploying.** Not a pipeline, not a step in one, not a hook into one.
- **No releasing either.** No `git push`, no tag, no GitHub release, no marketplace
  publish, and no version bump — not even after a go verdict. Anything that touches a live
  artifact is G4 and stays a human action.
- **No fifth agent.** The team is four phase agents and stays four. Ship and Observe sit on
  the deterministic side of the protocol's determinism boundary; giving them agent judgment
  is the mistake this spec is trying not to make.
- **No new runtime dependency.** Nothing that requires jq, node, python, or composer to be
  present in order to work.
- **No telemetry ingestion.** No Sentry/Flare/Bugsnag client, no log tailing, no polling, no
  dashboard, no webhook receiver. Observe starts from a human handing over a fault.
- **No triage.** Observe captures; it does not diagnose, assign a cause, reproduce, or open
  the loop by itself.
- **No second verifier.** Ship does not re-check acceptance criteria or re-read the diff.
  That is G2 and it already has an owner.
- **Not a changelog generator or version bumper.** Ship reports a version mismatch; it does
  not fix one.
- **Not the other two v0.1 gaps.** No Gemini/Codex support. No frontend, mobile, infra, or
  docs specialist agent.
- **No new state format.** Project memory stays plain markdown under `docs/loop/`, human
  readable and deletable by hand.

**Deliberately not in the gate set.** Two candidates were raised while framing this and
**not** adopted: a check that CHANGELOG has an entry for the version being shipped, and a
check that `scripts/*.sh` and `tests/*.sh` carry the executable bit (CI already does the
latter). Building either is out of bounds. Adding them later is a new intent, so that it is
a decision someone makes rather than one that accretes.

## Failure modes

| When | Expected behaviour |
|---|---|
| The guardrail harness fails | Hold, non-zero exit, the harness's own failing output shown |
| `shellcheck` reports a warning or error | Hold, with the reported lines shown |
| `shellcheck` is not installed | Reported by name as not-run, verdict hold — never a quiet go |
| A file a gate needs is missing | Reported by name as not-run, verdict hold |
| The three version files disagree | Hold; each file and its value named |
| A version file is unreadable or its version field absent | Hold, naming the file — not treated as "matches" |
| A gate never returns | Time-bounded, and the timeout is reported as a hold. A human is never left without a verdict |
| Working tree is dirty when Ship runs | Reported, because the tree is not what a release would contain |
| No `docs/loop/<slug>/` for the unit | Gates still run; summary states no unit contract was found |
| Someone runs Ship expecting a deploy | Summary says plainly that nothing was deployed, published, or tagged |
| Someone runs Ship inside a downstream Laravel project | Says it checks laravel-loop's own release readiness and does not attempt that project's gates |
| A gate's output contains secrets or env values | Not echoed into the summary |
| Ship or Observe run outside a git repository | Says so and stops, rather than half-running |
| Observe capture would collide with an existing slug | Refuses or writes a distinct slug. Never overwrites an existing unit |
| Observe capture has no reproduction, no suspect, no timestamp | Records each as unknown. Never invents one |
| Observe fault cannot be attributed to any merged unit | New intent with no link, rather than a guessed link |

## Constraints

Existing behaviour that must not change:

- Both guardrail scripts, their exit codes, their `LARAVEL_LOOP_REFINE_CAP` /
  `LARAVEL_LOOP_ALLOW_UNTESTED` overrides, and their subagent-only scoping via
  `agent_type`. A human on the main thread is still never blocked.
- The four-agent team, and the claim in README and CHANGELOG that it is four.
- Standalone from Laravel Guild: separate agents, skills, env vars, and state file. No
  collision when both are installed.
- Project memory stays three files plus per-slug directories, in the repo, deletable.

Repo conventions this must live inside:

- Zero-dependency bash plus coreutils for anything executable; tested by
  `tests/guardrails.test.sh`; clean under `shellcheck -S warning`; executable bit set. CI
  runs exactly these and must stay green.
- Command surfaces live in `commands/*.md` with the frontmatter the harness validates.
- Version is stated in three places — `VERSION`, `.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json` — and CHANGELOG follows Keep a Changelog with semver.
  These three files are the subject of Ship's third gate.
- `docs/loop/conventions.md` and `docs/loop/decisions.md` exist but are empty templates.
  Nothing here can assume a taught rule.

Hard limits:

- G4 is not crossed. No agent-initiated action on live infrastructure, at any point.
- Ship is read-only and its verdict is deterministic. Where judgment is unavoidable, it
  belongs in what the human reads, never in whether the verdict is go or hold.
- Observe adds no new script — a documented procedure and one thin command surface only.

## Decisions taken at G0

Recorded here because a resolved question that leaves no trace gets re-litigated. Any of
these reopening is a new intent, not a mid-build adjustment.

**D1 — Ship checks this plugin's own release readiness only.** Not downstream Laravel
projects, and not by gate discovery. Rationale: this repo is a Claude Code plugin with no
artisan, composer, or PHP, so "the project's gates" only ever meant this repo's own. The
downstream reading was rejected because Guild's `laravel-team:ship-checklist` already
answers that question and duplicating it would break Loop's standalone-but-non-overlapping
relationship with Guild. Discovery was rejected as machinery bought before the need. The
consequence to state plainly in README: Ship is the plugin's release check, not a Laravel
app's.

**D2 — A gate that cannot be run means hold, not go-with-a-warning.** "Nothing proved this
is releasable" and "this is releasable" must never print the same verdict.

**D3 — Ship never tags, releases, publishes, or bumps a version, even on a go.** Publishing
is the production action and belongs to the human at G4. Ship stays read-only, which is
also what makes S6's determinism and S7's provability cheap.

**D4 — Observe is a documented procedure plus one thin command, not a new script.** Enough
to make O1–O5 assertable, without a second executable to maintain.

**D5 — Observe is project-agnostic, and D1 does not narrow it.** It writes markdown under
`docs/loop/`, so it behaves identically in this repo and in any project that installed the
plugin.

## Open questions

None. All five were resolved at G0 and are recorded above as D1–D5.
