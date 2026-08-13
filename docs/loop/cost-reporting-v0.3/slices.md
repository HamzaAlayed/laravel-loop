# Slices — cost-reporting-v0.3

Cuts `docs/loop/cost-reporting-v0.3/spec.md` (G0 approved; **G0-D1** ship the whole v0.3 row
with no threshold default anywhere, **G0-D2** R2.2 documents fields not numbers; one
non-blocking open question) into eight slices. Every one of the spec's **64** acceptance
criteria is assigned to exactly one slice, or named below as cross-cutting or as a post-merge
condition. Nothing is dropped.

**8 slices · 2 can start immediately · 2 parallel again after S4 · critical path S2 → S3 → S4 → S6 → S7 → S8 (6 deep)**

Concerns are kept apart on purpose, per the brief and the spec's own structure: **S2/S3 report,
S4/S5/S6 gate, S7 logs, S1 is unrelated.** R2 depends on R5 (a threshold needs the coverage
arithmetic to compare against) but is never merged into it — reporting states what was spent,
gating decides whether to continue, and the second is the one that can stop work.

## The seam

The smallest change that delivers observable value is **`/cost <slug>` printing, from the real
ledger, how much of that unit's spend is observable — and the priced subset's total, labelled as
partial** (S2). That is the spine the spec names: a reader who stops after the first section has
not been misled. Everything else either enriches that report (S3), thresholds against it (S4,
S5, S6), persists it (S7), documents it (S8), or is independent of all of it (S1).

Deliberately *not* the seam: the budget gate. It is the component the human chose to ship
against a recommendation to defer (G0-D1), and it cannot honestly exist before the coverage
arithmetic it must compare against exists — a gate built first would be a gate with its own
second implementation of the total, which is exactly what CV7/CV8 forbid.

Also deliberately not the seam: a shared arithmetic library on its own. A library with no
caller is a refactor, and refactors are their own slices — so the library ships inside S2, with
its interface pinned below so S3, S4, S5 and S7 can consume it without re-deriving it.

## Order and concurrency

```
t0  ├── S1  Full-suite guard (R4.4)          independent — new script + hook + cases
    └── S2  /cost core + the coverage spine   ← critical path starts
                │
                └─→ S3  Report breakdown sections (phases, rework, slices, budget config)
                         │
                         └─→ S4  Budget gate script — inert until configured
                                  ├─→ S5  Per-phase expectation FLAGs  ─┐
                                  └─→ S6  Conductor at the gate         │
                                           │  (S5 ∥ S6)                 │
                                           └─→ S7  Cost section in log.md
                                                    │
                                                    └─→ S8  README + CHANGELOG + version
```

- **Genuinely parallel at t0:** S1 and S2 — two builders, two worktrees. They share no file.
- **Genuinely parallel after S4:** S5 and S6. S5 is `agents/*.md` + `SKILL.md` + a script mode;
  S6 is `commands/loop.md`. Disjoint surfaces.
- **Two in flight, never more.** That is what this dependency graph actually permits, and it is
  inside `/loop`'s own 2–3 cap. Do not start S3 alongside S2 because a builder is idle.
- **S2 → S3 → S4 is a real chain, not layer habit.** S3 needs S2's ledger scan; S4 needs S3's
  per-slice and rework arithmetic, because **BG5** requires the breach message to name the most
  expensive slice *and its rework share*. A gate that computed those itself would be the second
  implementation CV7 exists to prevent.
- **S6 → S7 is a real chain twice over.** Both edit `commands/loop.md` (different steps), and
  **DL6** must record "the cap was raised", an event only the conductor S6 defines observes.
- **Merge in path order.** S1 may merge at any point before S8.

## Contract pinned across slices

Fixed here, at G1, so builders in separate worktrees cannot invent two versions of one thing.
**No slice may change any of these; a slice that believes one is wrong returns
`needs-decision`.** Items marked *(slicer-chosen)* are not in the spec and are open to human
override at this gate — they are listed again at the end.

| Thing | Value | Set by | Read by |
|---|---|---|---|
| Ledger path | `.claude/loop-cost.jsonl`, **read-only, always** | v0.2 | all |
| Shared arithmetic *(slicer-chosen)* | `scripts/cost-ledger-lib.sh` — sourced, functions only, no top-level side effects, never registered as a hook, `# shellcheck shell=bash` | S2 | S3, S4, S5, S7 |
| Reader | `scripts/cost-report.sh` — read-only, writes no file | S2 | S3 |
| Gate | `scripts/check-budget-gate.sh` — `PreToolUse` / `Agent\|Task`, exit 2 to pause, exit 0 otherwise | S4 | S5, S6 |
| Phase check *(slicer-chosen)* | the same script, invoked `check-budget-gate.sh --phase <phase> --unit <slug>`; prints a FLAG line, **always exit 0**, never blocks | S5 | agents |
| Log writer *(slicer-chosen)* | `scripts/write-cost-log-section.sh <slug>` — the only script in this unit that writes anything | S7 | — |
| Full-suite guard *(slicer-chosen)* | `scripts/warn-full-suite.sh` — `PreToolUse` / `Bash`, stderr + **exit 0**, warns before the wait rather than after it | S1 | — |
| Command surface | `commands/cost.md`, `/cost [slug]`, `allowed-tools: Bash, Read` only — it runs the script and relays stdout **verbatim**, computes nothing | S2 | — |
| Budget env vars | `LARAVEL_LOOP_BUDGET_WARN`, `LARAVEL_LOOP_BUDGET_HARD` (spec-given). Accepted form: a bare non-negative decimal integer, no suffix, no exponent, no sign, no decimal point, no surrounding space. **No default, anywhere** | S4 | S5, S6, S8 |
| Per-phase env vars *(slicer-chosen)* | `LARAVEL_LOOP_BUDGET_PHASE_SPEC`, `_SLICE`, `_BUILD`, `_VERIFY` — same accepted form, same no-default rule | S5 | S8 |
| Gate state dir *(slicer-chosen)* | `.claude/loop-budget-state/<slug>/` — once-per-unit markers for BG7 and BG9, plus BG11's `hard-override`. Gitignored by S4 | S4 | S6 |
| BG11 mechanism *(slicer-chosen)* | Raising the cap writes `.claude/loop-budget-state/<slug>/hard-override` containing a bare integer. It **raises** an already-set threshold for that unit only; with `LARAVEL_LOOP_BUDGET_HARD` unset or unparseable it **never arms** the gate. Nothing ever writes an env var, `settings.json`, `.env`, or `CLAUDE.md` | S4 (read) / S6 (write) | — |
| Unavailable literal | the lowercase word `unavailable`. **Never `0`, never `0%`, never `-`, never blank, never an omitted row** | S2 | all |
| Coverage sentence | one line from `cost_coverage_sentence`, shape: `based on <p> of <n> invocations that carry a token figure (<u> unpriced, not counted)`. The report and the gate say the identical sentence because they call the identical function | S2 | S3, S4, S5, S7 |
| Report section order | `Coverage:` first, always, before any total (CV1) → `Tokens` → `Phases` → `Rework` → `Slices` → `Flags` → `Budget`. S2 establishes `Coverage`/`Tokens`/`Budget`-absent handling; S3 fills the middle at these anchors and **reorders nothing** | S2 | S3 |
| No wall-clock in output | the report prints no "generated at" time and no `$(date)` of its own, so identical ledger → **byte-identical** output (CV7). Test: run twice, `diff` | S2 | S3, S7 |
| `log.md` headings *(slicer-chosen)* | `## Cost` is written and **replaced in place** by S7's script. `## Budget events` (DL6) is a **separate** heading written by the conductor, and S7's replace must never touch it | S7 / S6 | — |
| Reassurance ban | no surface ever prints `within budget`, `under budget`, `✓`, `OK`, or any equivalent (BG6). Asserted as a **negative** case by S2, S3, S4, S5, S6, S7 | — | all |

**Lib interface, minimum pin** (S2 may add more; these names are fixed because four slices
consume them):

- `cost_scan <ledger-path> <slug-or-empty>` — sets `COST_N_INVOCATIONS`, `COST_N_PRICED`,
  `COST_N_UNPRICED`, `COST_N_INFLIGHT`, `COST_N_SKIPPED`, `COST_N_CAPTRIP`,
  `COST_TOKENS_PRICED`, and per-phase equivalents. Sets nothing outside the `COST_*` namespace.
- `cost_coverage_sentence` — prints the pinned sentence above.
- `cost_fmt <value>` — prints the number, or `unavailable` when the value is absent. Never `0`
  for an absence (v0.2 **L3**: a null means unavailable, a zero means measured).
- `cost_slice_rows` *(added by S3)* — per-slice priced totals, highest first, plus each slice's
  rework marking. **BG5 reads this**; it is the reason S4 depends on S3.

**No consumer re-parses the ledger itself.** Every figure any slice prints or compares comes
from these functions. That is CV7 and CV8 made structural rather than promised.

### One reconciliation, settled here so nobody reads it two ways

**BG1's silence and CO12's disclosure are not in conflict.** BG1 governs the *gate*: with both
variables unset, a `/loop` run is byte-for-byte indistinguishable from today's — no evaluation,
no message, no FLAG, no latency. CO12 governs `/cost`, which a human ran deliberately and which
must let someone who believes they set a limit discover that they did not. So:

- The **gate**, unconfigured: absolute silence.
- **`/cost`**: a `Budget` section stating either the thresholds it read, or that none are set and
  therefore nothing will gate.
- **Neither, ever**: a `✓`, a "within budget", or any other reassurance token (BG6). The spec's
  failure-mode row rejecting `no budget configured ✓` is rejecting the checkmark, not the fact.

A verifier reading BG1 and CO12 side by side would otherwise be entitled to call this a
contradiction, so it is recorded rather than left to each builder.

## Cross-cutting — asserted by every slice, owned by none

- **X1** — `bash tests/guardrails.test.sh` green with a case count **above 121**;
  `shellcheck -S warning scripts/*.sh` clean (including the sourced lib); executable bit set on
  anything new. Every slice adds cases, so every slice moves this.
- **X2** — both existing guards behave exactly as today; their existing cases pass
  **unmodified**. In every slice's `Do NOT`.
- **X3** — the refine cap's behaviour and `.claude/loop-refine-passes.tsv`'s format and meaning
  are untouched. Budget work may read cost state; it may never repurpose refine state. In every
  slice's `Do NOT`.
- **X4 / BG13** — `scripts/record-cost-event.sh` is **unchanged**: same record shape, same
  fields, same rework semantics, same registrations, still observe-only. Read it, copy its
  *shape*, never edit it. **A slice that concludes it needs a new ledger field returns
  `needs-decision` and stops — it does not add one**, because a field added mid-unit makes every
  record written before it structurally different from every record after it and nothing in the
  file says so. In every slice's `Do NOT`; S4 owns the durable test for it.
- **X5** — every script named in `hooks/hooks.json` exists and is executable; re-asserted by the
  harness's existing structure check on every run. Only S1 and S4 touch `hooks.json`.
- **BG6's reassurance ban** and **BG1/PE1's no-default rule** are cross-cutting prohibitions,
  not one slice's chore. Concretely, in every slice: **introduce no threshold number anywhere in
  a code path, a comment, a README line, or a suggested value.** A number inside a test fixture
  is not a default and is fine; a number anywhere a reader could take as a starting point is the
  thing G0-D1 forbids.
- **CO2** — nothing in this unit reads `.claude/agents-board.jsonl`, Guild's
  `emit-agent-events.sh`, the network, or any account. In every slice's `Do NOT`.

## Slices

### S1 — Warn, never block, when a builder runs an unfiltered test suite mid-slice

```
Owner:       loop-build
Context:     spec.md FS1–FS7, §E7 (greenfield — no LARAVEL_LOOP_ALLOW_FULL_SUITE anywhere),
               §E8 (the shape a third guard should take)
             scripts/block-untested-commit.sh — the guard idiom to copy: agent_type scoping
               so a human on the main thread is never affected, single-purpose escape hatch
               named in the message, exit 0 wherever it cannot be sure, why-this-event header
             scripts/record-cost-event.sh — its bash_target_and_failure() test-command regex
               and --filter/path extraction are the closest prior art. READ ONLY: copy the
               shape, never edit the file
             skills/laravel-validate/SKILL.md lines 16–40 — the runners actually prescribed,
               including the `./vendor/bin/sail` prefix and `--compact --filter=<Name>`
             tests/guardrails.test.sh — harness idiom: run_hook, expect, temp dirs
Constraints: - Zero dependency: bash + coreutils, degrading jq -> python3 -> safe no-op.
               Clean under `shellcheck -S warning`. Executable bit set.
             - PreToolUse / Bash, stderr, **exit 0 on every path**. This is the one guard in
               the repo that advises rather than refuses; a wrong block costs more than the
               suite run it prevents. Wired PreToolUse deliberately (state why in the header):
               a warning that arrives before the wait can change the next command; one that
               arrives after it is just a receipt.
             - Discriminator is the caller, not the command: warn only when agent_type is
               `loop-build`. Never on `loop-verify` (it re-runs broadly by design; narrowing
               that is R4.5, out of scope), never on an empty agent_type (main thread).
             - Filtered means: any `--filter`, `--group`, `--testsuite`, or a path/file
               argument. Sail-prefixed forms are the same command.
             - False positives are the failure mode that matters here. `ls tests/`, a grep,
               a git command naming a test file, a path that merely contains `tests/` — none
               warn. A warn-only guard that cries wolf gets tuned out, and then the real
               warning is free.
             - `LARAVEL_LOOP_ALLOW_FULL_SUITE=1` silences it, named inline in the warning
               itself where somebody reading the warning will see it.
Output:      - scripts/warn-full-suite.sh (new, executable)
             - hooks/hooks.json — one added PreToolUse/Bash registration; every existing
               entry byte-identical
             - tests/guardrails.test.sh — a new "full-suite guard" section
Done when:   New harness cases, each failing today because the script does not exist:
             (a) `php artisan test` from loop-build warns on stderr AND exits 0 — the exit
                 code and the stderr asserted as separate cases (FS1);
             (b) `./vendor/bin/sail artisan test` from loop-build warns (FS4);
             (c) `php artisan test --compact --filter=InvoiceTest` does not warn; nor does
                 `vendor/bin/pest tests/Feature/InvoiceTest.php` (FS4);
             (d) an unfiltered run from loop-verify does not warn; nor does one with no
                 agent_type at all (FS2) — two separate cases;
             (e) `LARAVEL_LOOP_ALLOW_FULL_SUITE=1` silences it, and the warning text names
                 that variable (FS3) — assert the name appears in the message;
             (f) `ls tests/`, `grep -r foo tests/`, `git add tests/InvoiceTest.php` produce
                 no warning (FS5) — asserted per command, not in aggregate;
             (g) exit 0 asserted individually for malformed payload, empty payload, and PATH
                 stripped of jq and python3 (FS6);
             (h) the harness's existing structure check still passes with the new
                 registration (X5), and every pre-existing case passes unmodified (X2).
Do NOT:      - Edit scripts/record-cost-event.sh in any way, including its regex — read it,
               copy the shape (X4/BG13). A ledger field is never added; needs-decision instead
             - Edit either existing guard script, its registrations, or its existing cases
             - Ever exit non-zero, or block, delay, or alter the command
             - Warn on loop-verify, on the main thread, or at integration time (FS2)
             - Touch scripts/cost-*.sh, commands/, agents/, skills/, README.md, .gitignore,
               or anything to do with budgets, thresholds, coverage, or the ledger
             - Read .claude/loop-cost.jsonl or .claude/agents-board.jsonl — this guard needs
               no cost data at all
Depends on:  nothing
```

**Five tests.** 1 — one owner, one script. 2 — one commit: "advise a builder not to run the
whole suite". 3 — named above; every case fails today, `grep -r LARAVEL_LOOP_ALLOW_FULL_SUITE`
returns nothing (E7). 4 — criteria are exit codes and stderr contents for named commands, not
"the guard is well tuned". 5 — no dependencies, and it reads nothing any other slice writes.

**Covers:** FS1, FS2, FS3, FS4, FS5, FS6, FS7.

---

### S2 — `/cost` exists and states what it can see before it states any total

```
Owner:       loop-build
Context:     spec.md CV1–CV3, CV5–CV7, CO1–CO3, CO8–CO10, CO13, §E1 (the ledger is absent
               from this tree today — the empty-state paths are the common case, not the edge),
               §E6 (three record shapes), §Failure modes rows for every degenerate state,
               and the pinned contract table above
             scripts/record-cost-event.sh — the record shape being read, and the
               jq -> python3 extract() ladder to copy. READ ONLY
             scripts/enforce-refine-cap.sh — the header-comment-explaining-why idiom
             commands/verify.md — the shape of a thin command that relays a script's output
             tests/guardrails.test.sh line ~1180 — the existing case "every commands/*.md has
               a row in README's Commands table". Adding commands/cost.md without that row
               turns a green case red: the row is part of this slice, not S8's
Constraints: - Zero dependency: bash + coreutils, jq -> python3 -> says so and exits 0. With
               neither parser it prints that it cannot read the ledger and exits 0 rather
               than a partial or wrong report (CO13).
             - `scripts/cost-ledger-lib.sh` holds every figure-producing function, exactly the
               interface pinned above, sourced by cost-report.sh. Functions only, no top-level
               side effects, safe under `set -uo pipefail`.
             - **Coverage before any total, unconditionally** (CV1), with the per-phase
               priced/unpriced split. A reader who stops after the first section has not been
               misled.
             - Totals cover the priced subset and say so, with the unpriced count in the same
               visual unit — not a footnote, not a legend (CV3). Every share is over priced
               invocations only and says so (CV5). No unpriced invocation is ever a zero in a
               numerator or a denominator.
             - Where **no** invocation is priced: no token table at all. Not a table of
               `unavailable`, not a table of zeros. A plain statement that nothing about this
               unit's token cost is observable, and why (CV6).
             - The three record shapes of E6 each handled: `cap_trip` contributes rework and
               slice information without counting as an invocation or as unpriced;
               `line_too_long` counts as an invocation whose tokens are unavailable; a start
               with no matching finish counts as **in flight**, never as unpriced-zero (CO10).
             - Three distinguishable empty states, none crashing, none printing a zeroed
               table: file absent (naming both likely causes — hooks not wired, or
               `LARAVEL_LOOP_COST_LEDGER=0`); present but empty; present with no record for
               the requested slug (listing the slugs it does have, because a typo and an
               unrun unit are different problems) (CO3).
             - `slug: "unknown"` is its own visible bucket, never merged, never hidden (CO9).
             - Deterministic: no `date`, no "generated at", no locale-dependent sort. Identical
               ledger -> byte-identical output (CV7).
             - Header comment explains why this reads and never writes, in the style of the
               three existing scripts.
Output:      - scripts/cost-ledger-lib.sh (new; not executable-as-hook, still shellcheck-clean)
             - scripts/cost-report.sh (new, executable)
             - commands/cost.md (new; `allowed-tools: Bash, Read`; relays stdout verbatim)
             - README.md — the one-line `/cost` row in the existing Commands table, nothing else
             - tests/guardrails.test.sh — a new "cost report" section, with committed fixture
               ledgers built inline in temp dirs (no fixture files added to the repo)
Done when:   New cases, all failing today because scripts/cost-report.sh does not exist:
             (a) mixed fixture (n invocations, few priced): the `Coverage:` line appears at a
                 lower line number than any token figure — asserted with grep -n, not by eye
                 (CV1);
             (b) all-unpriced fixture: no `Tokens` table is printed at all, the reason is
                 stated, and the output contains no token figure of `0` (CV6, CV2);
             (c) mixed fixture: the total is labelled as covering priced invocations only and
                 the unpriced count appears in the same section (CV3, CV5);
             (d) three empty states, three distinguishable messages, each exit 0, none
                 printing a table: absent (message names hooks-not-wired and
                 LARAVEL_LOOP_COST_LEDGER=0), empty, unknown-slug (lists present slugs) (CO3);
             (e) a fixture with 3 malformed/truncated lines: they are skipped, the skipped
                 count is printed, exit 0, and no total silently shrinks without saying so
                 (CO8);
             (f) `slug":"unknown"` records appear as their own bucket, not inside a named
                 unit (CO9);
             (g) one fixture carrying all three E6 shapes: cap_trip is not counted as an
                 invocation nor as unpriced; line_too_long counts as an invocation with tokens
                 `unavailable`; a start with no finish is counted and labelled in-flight (CO10);
             (h) `/cost` with no slug lists one line per unit, most recent first, each with
                 its coverage (CO1);
             (i) the same fixture run twice produces byte-identical stdout — asserted with
                 `diff` (CV7);
             (j) PATH stripped of jq and python3: says so, exits 0, prints no partial report
                 (CO13);
             (k) `grep -E 'curl|wget|nc |agents-board' scripts/cost-report.sh
                 scripts/cost-ledger-lib.sh` finds nothing (CO2);
             (l) `grep -iE 'within budget|under budget|✓' ` over the output of every fixture
                 above finds nothing (BG6);
             (m) commands/cost.md declares no write-capable tool (Write/Edit/Agent) — the
                 commands/ship.md case is the pattern;
             (n) the pre-existing case "every commands/*.md has a row in README's Commands
                 table" still passes (X2).
Do NOT:      - Write, prune, reshape, rotate, or take ownership of .claude/loop-cost.jsonl,
               or edit scripts/record-cost-event.sh (X4/BG13). A missing field is
               needs-decision, never a ledger change
             - Add the per-phase breakdown, rework figures, top slices, the 30% concentration
               flag, elapsed times, or the Budget section — S3 owns all six, at the anchors
               pinned above. Print the anchors' headings only if S3 can fill them without
               reordering
             - Add any budget threshold, evaluation, warning, gate, env var, or default (S4)
             - Add a `--json` mode, an export, a chart, a sparkline, a trend across units, or
               a notification — each explicitly rejected in §Non-goals
             - Print any dollar figure, rate, or currency; print any figure derived from
               `.claude/agents-board.jsonl`
             - Touch README beyond the single Commands-table row (S8), CHANGELOG, VERSION,
               .claude-plugin/*, hooks/hooks.json, agents/, skills/, or commands/loop.md
             - Modify either existing guard, the refine cap, or any pre-existing case
Depends on:  nothing
```

**Five tests.** 1 — one owner. 2 — one commit: "`/cost` tells the truth about what it can
see". The lib is not a second commit's worth — it is this slice's implementation, pinned as an
interface only because four later slices consume it. 3 — named above; every case fails today,
and E1 means even the absent-ledger path is exercised against reality. 4 — criteria are line
ordering, exit codes, and the presence or absence of literal strings for named fixtures, not
"the report is honest". 5 — no dependencies.

**Covers:** CV1, CV2, CV3, CV5, CV6, CV7, CO1, CO2, CO3, CO8, CO9, CO10, CO13.

---

### S3 — Add the breakdown sections, each conditioned on its own coverage

```
Owner:       loop-build
Context:     spec.md CV4, CO4–CO7, CO11, CO12, §E2 (~9 of 10 invocations unpriced; build 0 of
               14), §E4 (rework as counts is computable, rework as a token share is not),
               §E5 (elapsed is derivable; billed agent time is not), v0.2 D1/D3/L3/L11
             scripts/cost-ledger-lib.sh and scripts/cost-report.sh as S2 left them
             scripts/record-cost-event.sh — `model_source`, `phase_detail`, `refine_passes`,
               `rework_attribution`, `duration_ms` semantics. READ ONLY
             the pinned section order above — fill the anchors, reorder nothing
Constraints: - Every section is conditioned on the coverage that supports it. An unassessable
               check never renders as a passed one.
             - Per-phase breakdown of priced invocations with the model recorded per phase,
               and `model_source` shown wherever the model was **derived** rather than
               observed (CO4). A derived model presented as observed makes every future
               routing comparison a lie.
             - Rework is reported as **invocation counts** — n of m marked rework, with their
               refine-pass counts — and as a token share **only** where those invocations are
               priced. Each figure labelled as which it is; neither captioned so a reader can
               take one for the other (CO5). `rework_attribution: "ambiguous"` shows as
               ambiguous, never as definite.
             - The report states, in its own output, what its rework figure measures: the cost
               of slices that were not right first time, at whole-invocation granularity,
               deliberately over-attributing, **not** the cost of retrying, and **not**
               comparable to §10's <15% target. **No pass/fail verdict against that target is
               printed** (CO6). Lift the wording from record-cost-event.sh's header, which was
               written to be lifted.
             - Top slices by cost, and a flag for any single slice above 30% of the unit's
               total — printed only where slice-level coverage supports the comparison.
               Otherwise the Flags section states that concentration could not be assessed and
               what was missing (CO7).
             - Cache-read share reads `unavailable` when the field is absent from every
               record. **Never `0%`** — §10 sets a >40% target against it, and a target
               compared against a fabricated zero reads as a catastrophic miss of something
               never measured (CV4).
             - Any time figure is labelled as elapsed wall-clock derived from start/finish
               timestamps. Elapsed times of overlapping invocations are **never** summed into
               an "agent time" total (CO11, E5). Where `duration_ms` is present it may be
               reported as the distinct quantity it is.
             - `Budget` section per CO12 and the reconciliation pinned above: the thresholds
               read, or that none are set and therefore nothing will gate. No `✓`, no "within
               budget", no reassurance token, ever (BG6).
             - `cost_slice_rows` is added to the lib to the pinned interface, because S4's BG5
               consumes it. Do not compute slice totals inside cost-report.sh.
             - Determinism preserved: still no `date`, still byte-identical on a re-run.
Output:      - scripts/cost-ledger-lib.sh — cost_slice_rows and the rework/phase aggregates
             - scripts/cost-report.sh — the Phases, Rework, Slices, Flags, Budget sections
             - tests/guardrails.test.sh — cases appended to the "cost report" section
Done when:   (a) A mixed fixture prints per-phase rows for spec/slice/build/verify with the
                 model per phase, and the word `derived` wherever model_source is derived —
                 and a phase with no priced invocation reads `unavailable`, never 0 (CO4);
             (b) an all-unpriced-rework fixture (E4's real case) prints rework as counts
                 labelled as counts, and its token share as `unavailable`; a priced-rework
                 fixture prints a share labelled as a share (CO5);
             (c) the D3 granularity statement and the "not comparable to the <15% target"
                 statement both appear in the output, and no verdict string against that
                 target appears anywhere (CO6);
             (d) a fixture with one slice at >30% of the priced total prints the
                 concentration flag; a fixture whose slice-level coverage cannot support the
                 comparison prints "could not be assessed" plus what was missing, and prints
                 no flag either way that could read as a passed check (CO7);
             (e) a fixture with cache_read_tokens absent from every record prints
                 `unavailable`, and the string `0%` appears nowhere (CV4);
             (f) time figures are labelled elapsed, and no line matching /agent time/i is
                 printed even on a fixture with overlapping invocations (CO11);
             (g) Budget section: with both variables unset it states none are set and nothing
                 will gate; with `LARAVEL_LOOP_BUDGET_HARD` set it shows the value it read —
                 and in neither case does the output contain "within budget", "under budget",
                 or `✓` (CO12, BG6);
             (h) byte-identical output on a re-run of every fixture above (CV7);
             (i) every S2 case passes unmodified.
Do NOT:      - Reorder, rename, or restructure S2's sections or the pinned anchor order
             - Recompute anything S2's lib already computes, or parse the ledger outside the lib
             - Print a verdict, a pass/fail, a score, or a comparison against §10's targets
             - Print `0` or `0%` for anything unmeasured; collapse v0.2's L3 (null means
               unavailable, zero means measured) anywhere
             - Sum elapsed times into an agent-time total, or reproduce the requirements
               document's "18m agent time" headline (E5 — this ledger cannot honestly produce it)
             - Evaluate, compare against, or act on a threshold — showing configuration is
               CO12; deciding anything is S4
             - Write to the ledger or edit scripts/record-cost-event.sh (X4/BG13);
               needs-decision if a field is missing
             - Touch commands/, agents/, skills/, README.md, hooks/hooks.json, .gitignore
             - Weaken or delete any S2 case to make a new one pass
Depends on:  S2 — the lib's scan, the coverage sentence, the section anchors, and the
             `unavailable` literal all come from it. Nothing here re-derives them.
```

**Five tests.** 1 — one owner. 2 — one commit: "the report answers where the money went, each
answer fenced by its coverage". 3 — named above; each case fails against S2's tree because the
section does not exist. 4 — criteria are strings present or absent in output for named
fixtures. 5 — S2, named, with what it supplies.

**Covers:** CV4, CO4, CO5, CO6, CO7, CO11, CO12.

---

### S4 — A budget gate that exists, is configurable, and does nothing until a human sets a number

```
Owner:       loop-build
Context:     spec.md BG1–BG10, BG12–BG14, CV8, **G0-D1 in full including what was overruled
               and why**, §E8 (block-untested-commit.sh's shape; record-cost-event.sh must
               stay observe-only), §E9 (LARAVEL_LOOP_COST_MAX_LINES falls back to 5000 — the
               precedent this must NOT copy, sitting in the adjacent script where a builder
               will reasonably find it), §Failure modes rows for every budget state
             scripts/block-untested-commit.sh — the blocking idiom: agent_type scoping,
               escape hatch named in the message, exit 2 to stop a tool call, exit 0 wherever
               it cannot be sure
             scripts/cost-ledger-lib.sh as S3 left it — cost_scan, cost_coverage_sentence,
               cost_slice_rows
             the pinned contract table: env vars and their accepted form, the state dir, the
               BG11 hard-override mechanism, the reassurance ban
Constraints: - **No default value anywhere in the code.** Unset or empty means no evaluation,
               no gate, no warning, no FLAG, and no output of any kind about spend. With both
               unset a /loop run is indistinguishable from today's — no extra pause, no extra
               output, no extra latency.
             - An unparseable value **disables the gate and says so loudly**, naming the
               variable and the value it could not use. It never falls back to a number and it
               never fails silently. Deliberately unlike E9's line cap: a bound that fails
               open is fine; a spend gate that fails open *quietly* is the false-safety case,
               and a typo is the likeliest way anyone reaches it.
             - Evaluated on `PreToolUse` / `Agent|Task` only — before the next spawn. Nothing
               is ever killed, interrupted, or abandoned mid-invocation (BG4): a half-built
               worktree wastes everything already spent.
             - At the hard threshold: exit 2 with a message that presents **numbered options
               with a recommended default**, and the recommended option is re-slicing the most
               expensive slice, not raising the cap. Never silently continues; never silently
               aborts. Returns immediately — it reads no further input and waits for nothing
               (BG12), which is also what makes an unattended run stop and keep its artifacts
               rather than deadlock.
             - **Every comparison inherits CV1–CV7 (CV8).** The threshold is compared against
               the priced subset only; the breach message carries `cost_coverage_sentence`
               verbatim; no unpriced invocation is ever treated as zero tokens. Where coverage
               cannot support identifying the most expensive slice, say so rather than naming
               the most expensive *observed* slice as though it were the most expensive one
               (BG5).
             - **No unfired gate ever reads as "within budget"** (BG6) — not in a message, not
               in an exit code's meaning, nowhere.
             - Warn fires **once per unit** and does not gate (BG7). The partial-coverage
               notice fires **once per unit** (BG9). Both via the pinned state dir.
             - WARN above HARD is a misconfiguration: reported plainly, resolved by picking
               neither, and it never causes the hard gate to be skipped (BG8).
             - **A bug in the gate may never stop work** (BG10): any internal failure —
               unreadable ledger, no parser, its own error — exits 0, proceeds as if no
               threshold were set, and says so.
             - Lives entirely outside record-cost-event.sh (BG13). Nothing that can pause a
               spawn goes into the ledger writer, whose v0.2 spec forbids it from steering
               under any condition including its own failure.
             - Header comment explains why PreToolUse and not PostToolUse, and why no default
               ships (no baseline exists — E1/E2).
Output:      - scripts/check-budget-gate.sh (new, executable)
             - hooks/hooks.json — one added PreToolUse/`Agent|Task` registration alongside
               record-cost-event.sh's; every existing entry byte-identical
             - .gitignore — `.claude/loop-budget-state/`
             - tests/guardrails.test.sh — a new "budget gate" section
Done when:   Four directions first, then the rest — each a separate case:
             (a) HARD set below a fixture's priced total: exit 2; the message contains
                 numbered options; option 1 is re-slicing the most expensive slice; the
                 coverage sentence is present verbatim (BG3, BG5, CV8);
             (b) HARD set above the total: exit 0, no output;
             (c) **both unset, against a ledger far above any plausible threshold: exit 0 and
                 zero bytes on stdout and stderr** — asserted as emptiness, not as absence of
                 a block (BG1);
             (d) each of `400k`, `4e5`, `-1`, `1.5`, `" 100"`: gate disabled, exit 0, message
                 names the variable and the value, and a breach-sized ledger still does not
                 block — proving no numeric fallback happened (BG2);
             (e) WARN above HARD: misconfiguration reported, and a hard breach still exits 2
                 (BG8);
             (f) WARN crossed: one message on the first spawn, nothing on the next two (BG7);
             (g) threshold set with partial coverage: the coverage notice appears once with
                 the unpriced count, and not on the next spawn (BG9);
             (h) unreadable ledger, PATH stripped of jq+python3, and unwritable state dir:
                 each exits 0 and says it is proceeding as if no threshold were set (BG10) —
                 asserted per case;
             (i) the blocking path completes within a bounded time and consumes no further
                 stdin (BG12) — run under `timeout` and assert it returns;
             (j) a `PostToolUse` finish payload produces no gate output at all, and the script
                 appears under no event that fires mid-invocation (BG4);
             (k) `grep -iE 'within budget|under budget|✓'` over every message the script can
                 emit finds nothing (BG6);
             (l) the hard-override marker for a unit raises the effective threshold for that
                 unit only; with HARD unset the marker alone produces nothing (BG11 read half);
             (m) **`grep -q 'LARAVEL_LOOP_BUDGET' scripts/record-cost-event.sh` finds nothing,
                 and every pre-existing cost-ledger case passes unmodified** (X4, BG13, X2);
             (n) the harness's structure check passes with the new registration (X5).
Do NOT:      - Add, move, or copy any budget logic into scripts/record-cost-event.sh, or edit
               that file at all (BG13, X4). A needed ledger field is needs-decision
             - Bake in, comment out, suggest, or derive a default threshold — including from
               E2's two priced observations (60,787 / 99,124). Rejected at G0 and still
               rejected. A fixture value in a test is fine; a value in the code path or a
               comment is not
             - Copy LARAVEL_LOOP_COST_MAX_LINES's fallback-to-a-number pattern (E9)
             - Kill, interrupt, signal, or abandon an in-flight invocation; register on any
               event that fires mid-invocation (BG4)
             - Degrade the work to save money: no model switch, no context trim, no skipped
               phase, no reduced verification (§8)
             - Denominate anything in money, or print a dollar figure or rate table
             - Parse the ledger outside the lib, or produce a total by any arithmetic the
               report would not produce (CV7/CV8)
             - Write to `.claude/loop-refine-passes.tsv` or repurpose refine state (X3)
             - Edit commands/loop.md (S6), agents/ (S5), skills/, README.md (S8), or the
               report's output (S2/S3)
             - Persist a raised cap to settings.json, .env, CLAUDE.md, or any env var (S6
               writes the per-unit marker; this slice only reads it)
Depends on:  S3 — BG5 needs cost_slice_rows (most expensive slice + its rework share), which
             S3 adds to the lib; the coverage sentence and scan come from S2 through it.
```

**Five tests.** 1 — one owner, one script. 2 — one commit: "the loop can pause before the next
spawn when a human set a number". The "and also"s that would have made it two — presenting the
options, raising the cap, logging the event — are S6's. 3 — named above; every case fails today
because no LARAVEL_LOOP_BUDGET_* string exists anywhere in the repo. 4 — criteria are exit
codes, byte counts, and message contents for named env-var states. 5 — S3, named, with the
reason (BG5's most-expensive-slice figure).

**Covers:** CV8, BG1, BG2, BG3 (message half), BG4, BG5, BG6, BG7, BG8, BG9, BG10, BG12
(mechanism half), BG13, BG14 — and the durable X4 assertion.

---

### S5 — Per-phase expectations: a FLAG that carries its own coverage caveat, and blocks nothing

```
Owner:       loop-build
Context:     spec.md PE1–PE6, **G0-D2** (fields and mechanism documented, numbers not
               shipped), §E1/E2/E4 (why no number is derivable), BG1's proof obligation, the
               protocol's ≤10-line return shape
             skills/loop-protocol/SKILL.md §Return shape and §Task envelope — where the
               mechanism section goes, and the shape it must not extend
             agents/loop-spec.md, loop-slice.md, loop-build.md, loop-verify.md — each §Return
             scripts/check-budget-gate.sh as S4 left it — the threshold parser to reuse, not
               to duplicate
             tests/guardrails.test.sh — the "envelope attribution" section's
               prove-it-can-fail idiom (run against a stripped temp copy first)
Constraints: - **No per-phase number is shipped or defaulted**, anywhere. Unset means no
               comparison and no flag, ever — same discipline and the same proof obligation as
               BG1: proven by a test asserting zero output, not by reading the source.
             - One parser, not two: the `--phase` mode reuses S4's threshold parsing, so an
               unparseable per-phase value disables that phase's comparison **loudly**, the
               same way BG2 does.
             - Always exit 0. A configured overrun appears in that phase's return `FLAGS` and
               **never blocks anything** (PE3).
             - Any flag raised carries the coverage caveat **inside the flag itself** (PE4).
               A phase comparison drawn from a ledger that cannot see most of loop-build (E2)
               is not self-explanatory to whoever reads the return.
             - A phase whose invocations are all unpriced can never raise a flag — you cannot
               overrun an unobserved total — and the absence of a flag is never evidence a
               phase was within expectation (PE5, BG6 per phase).
             - **One line, inside the existing ≤10-line return** (PE6). It does not extend the
               shape.
             - **Mechanism, pinned so it is not designed mid-build:** the phase agent runs the
               `--phase` check before writing its return and pastes the line it prints, if any.
               Its consequence is load-bearing and must be documented rather than hidden: an
               invocation's own finish record is not written until after it returns, so the
               figure covers that phase's **recorded** invocations, not the one in flight. For
               a single-invocation phase that means the flag can only ever reflect earlier
               runs of that phase in the same unit. State this in PE2's documentation — a
               phase-cost mechanism that quietly excludes the invocation reading it is exactly
               the sort of half-visible figure this whole unit exists to refuse.
             - PE2's documentation names the four fields, how to set them, that nothing is set
               by default, and why not (no baseline exists — E1, E2, E4). **It documents no
               numbers** (G0-D2), including no illustrative one.
Output:      - scripts/check-budget-gate.sh — a `--phase <phase> --unit <slug>` mode
             - skills/loop-protocol/SKILL.md — one new section documenting the mechanism
             - agents/loop-spec.md, loop-slice.md, loop-build.md, loop-verify.md — the check
               and the FLAG wording in each §Return
             - tests/guardrails.test.sh — a new "phase expectations" section
Done when:   (a) `--phase build --unit <slug>` with LARAVEL_LOOP_BUDGET_PHASE_BUILD set below
                 that phase's priced total prints exactly one FLAG line, containing the
                 coverage caveat, and exits 0 (PE3, PE4, PE6);
             (b) with the variable unset: zero bytes of output, exit 0 (PE1 — asserted as
                 emptiness);
             (c) with an unparseable value: the loud disabled message, no comparison, exit 0;
             (d) a fixture whose phase invocations are all unpriced: no flag at any threshold,
                 and no "within expectation" or `✓` text anywhere (PE5, BG6);
             (e) the printed flag is one line — asserted with `wc -l`, so PE6 cannot regress;
             (f) all four agents/*.md instruct the check and carry the FLAG wording, and
                 SKILL.md's new section names all four field names, the how-to-set, the
                 nothing-is-default statement, its reason, and the in-flight limitation —
                 with a **prove-it-can-fail** case run first against a stripped temp copy;
             (g) SKILL.md's new section contains **no digit adjacent to a
                 LARAVEL_LOOP_BUDGET_PHASE_* name** — asserted by regex, so G0-D2 cannot be
                 quietly reversed by a helpful example;
             (h) every S4 case passes unmodified, and the ≤10-line return shape is unchanged
                 in all four agents.
Do NOT:      - Ship, default, suggest, comment out, or exemplify any per-phase number
               (G0-D2), in code, SKILL.md, an agent file, or a comment
             - Let the flag block, delay, pause, or gate anything (PE3)
             - Extend the return shape past ≤10 lines, or restructure the §Return sections
               beyond adding the flag (PE6)
             - Touch SKILL.md's §Task envelope or §Return shape structure, or the
               five-gate/slice-quality tables
             - Add a second threshold parser, or a second reading of the ledger outside the lib
             - Edit scripts/record-cost-event.sh, .claude/loop-refine-passes.tsv, either
               existing guard, commands/ (S6, S7), or README.md (S8)
             - Report a phase as within expectation, ever (BG6)
Depends on:  S4 — the threshold parser, the loud-disable path, and the state-dir convention.
             Reads S3's per-phase aggregates through the lib. Runs concurrently with S6:
             disjoint files, no shared surface.
```

**Five tests.** 1 — one owner. 2 — one commit: "a phase can flag its own overrun, if you set
one". 3 — named above; (b) and (f) fail today because no LARAVEL_LOOP_BUDGET_PHASE_* string
exists and SKILL.md has no such section. 4 — criteria are output emptiness, line counts, and
regex presence/absence in files. 5 — S4, named, plus the explicit statement that it is
concurrent-safe with S6.

**Covers:** PE1, PE2, PE3, PE4, PE5, PE6.

---

### S6 — The conductor at the gate: numbered options, a cap that does not outlive the unit

```
Owner:       loop-build
Context:     spec.md BG3, BG4, BG11, BG12, DL6, G0-D1's mitigation list, §Failure modes rows
               for "the cap is raised", "nobody is available to answer", "a slice is mid-flight"
             commands/loop.md — step 3 (Build, where spawns happen and the cap applies),
               step 4 (Verify), step 5 (Close — **S7's region, do not edit it**)
             skills/loop-protocol/SKILL.md §The five gates — the house style for presenting a
               gate as numbered options with a recommended default, never as a paragraph
             scripts/check-budget-gate.sh as S4/S5 left it — the message it emits, and the
               hard-override marker path it reads
             the pinned contract: the `## Budget events` heading is this slice's, `## Cost` is
               S7's
Constraints: - Markdown only. No script, no hook, no JSON. The mechanism exists (S4); this is
               how the conductor behaves when it fires.
             - The breach is presented as **numbered options with a recommended default**, in
               the repo's existing gate style, with re-slicing the most expensive slice as the
               recommendation and raising the cap listed last (BG3). Never a paragraph the
               human has to decode into a yes or no.
             - **A slice already in flight completes** (BG4). Stated explicitly, because the
               instinct at a spend breach is to stop everything, and abandoning a half-built
               worktree wastes everything already spent.
             - Raising the cap writes the per-unit `hard-override` marker and **nothing else**
               (BG11). Never an env var, never settings.json, never .env, never CLAUDE.md — a
               cap raised under pressure at 2am must not become the standing configuration.
               State plainly that it applies to this unit and dies with it.
             - **Unattended or non-interactive run:** the loop stops and keeps the artifacts
               and the log. It never continues past a breach on the grounds that nobody
               answered, and never waits forever (BG12).
             - Every budget event that occurred during the unit is recorded under a
               `## Budget events` heading in `docs/loop/<slug>/log.md`, **with the threshold in
               force at the time**: warn crossed, hard gate fired, cap raised (and to what),
               gate disabled by an unparseable value (DL6). A gate that fired and left no
               trace cannot be learned from; a raised cap that left no trace is how the next
               threshold gets set wrong.
             - **Nothing is ever reported as within budget** — not at the gate, not in a
               relay, not in the log (BG6). Silence from the gate means either no threshold
               was set or the observed total stayed under one, and `/cost` is where those two
               are distinguished (CO12).
             - Do not restate the coverage caveat in your own words: the gate's message
               already carries it (BG5, BG9). Relay it verbatim, like a FAIL verdict.
Output:      - commands/loop.md — step 3's build region gains the breach-gate behaviour and
               the BG11 rule; a `## Budget events` instruction added to the unit's log
               recording, written in step 3/4's region, not step 5's
             - tests/guardrails.test.sh — cases appended to the "budget gate" section
Done when:   (a) A grep case asserts commands/loop.md contains: the numbered-options gate
                 presentation, re-slicing named as the recommended option, raising the cap
                 listed as an option, the in-flight-completes rule, the per-unit
                 hard-override marker path, and the unattended-run behaviour — with a
                 **prove-it-can-fail** run against a stripped temp copy first (BG3, BG4,
                 BG11, BG12);
             (b) a case asserts commands/loop.md forbids persisting a raised cap, naming
                 settings.json, .env, and an env var explicitly — so a later editor cannot
                 soften it to "temporarily" (BG11);
             (c) a case asserts the `## Budget events` instruction names all four event kinds
                 and "the threshold in force at the time" (DL6);
             (d) a negative case: commands/loop.md nowhere instructs printing "within budget",
                 "under budget", or a `✓` for spend (BG6);
             (e) a case asserts step 5 (Close) is unedited by this slice — `git diff` on the
                 Close region is empty, so the S7 boundary is machine-checked rather than
                 trusted;
             (f) every S4 and S5 case passes unmodified.
Do NOT:      - Edit any script, hook, or JSON file. If the gate needs a behaviour change,
               return needs-decision — do not implement it here
             - Edit commands/loop.md step 5 (Close), or write a `## Cost` section — S7 owns
               both, and this is the only file two slices in this unit touch
             - Persist a raised threshold anywhere outside the per-unit marker, or instruct a
               human to export it permanently
             - Instruct the loop to kill, interrupt, or abandon an in-flight invocation (BG4),
               or to continue past a breach when nobody answered (BG12)
             - Instruct any cost-based degradation — cheaper model, trimmed context, skipped
               phase, reduced verification (§8)
             - Add a fifth agent, change what the four agents do beyond honouring the gate, or
               restructure the Board/Refusals sections
             - Add a threshold number, a suggested starting value, or a money figure
             - Edit agents/ (S5), skills/ (S5), README.md (S8), or scripts/record-cost-event.sh
Depends on:  S4 — the gate's message, exit semantics, and the hard-override marker path it
             reads. Runs concurrently with S5: disjoint files.
```

**Five tests.** 1 — one owner, one markdown file. 2 — one commit: "the conductor knows what to
do when the gate fires". 3 — named above; (a) fails today because commands/loop.md contains no
budget wording at all. 4 — criteria are strings present or absent in a file a human will read,
plus a machine-checked region boundary. 5 — S4, named; the S7 file-region split is asserted by
a case rather than left to goodwill.

**Covers:** BG3 (presentation half), BG4 (conductor half), BG11, BG12 (conductor half), DL6.

---

### S7 — Write the unit's cost into `log.md`, replacing rather than accumulating

```
Owner:       loop-build
Context:     spec.md DL1–DL5, DL7, CV1 (the coverage statement travels with the total), v0.2
               D3 (the rework definition that must travel with the figure), H1 (the ledger is
               never copied under docs/loop/)
             docs/loop/cost-measurement-v0.2/log.md and
               docs/loop/ship-observe-automation/log.md — the existing log shape and headings
               this must sit beside without disturbing
             scripts/cost-ledger-lib.sh and scripts/cost-report.sh as S3 left them
             commands/loop.md step 5 (Close) — this slice's only region in that file; step 3/4
               is S6's
             the pinned contract: `## Cost` is this slice's heading and is replaced in place;
               `## Budget events` belongs to S6 and must survive untouched
Constraints: - The section is generated by `scripts/write-cost-log-section.sh <slug>`, not by
               an agent composing prose. DL4's replace-not-append is mechanical work, and a
               deterministic figure written by hand stops being deterministic.
             - Re-running the close step **replaces** the `## Cost` section rather than
               appending a second one, and disturbs no other content in log.md — byte-identical
               everywhere else, `## Budget events` included (DL4).
             - The appended summary carries its coverage statement (DL2, CV1). A logged total
               without its coverage becomes, within a month, a historical figure someone
               trusts and cannot re-derive.
             - Rework is recorded per unit so the trend is visible across units without
               re-deriving it, **with its definition and coverage recorded alongside** (DL3).
               A bare percentage in a log will be compared against other bare percentages by
               someone who was not there, and D3's definition is not the obvious one.
             - Where the ledger holds no data for the unit, **the section is written anyway,
               saying so** (DL5). Omitting it is not acceptable: a missing cost section and a
               cheap unit look identical in a log, and the first is a wiring bug.
             - `log.md` is the only file written under `docs/loop/`. The ledger is never
               copied, moved, or mirrored there, and no new artifact type is introduced (DL7).
             - log.md absent: exit 0, write nothing, say so. The close step writes log.md
               first; this script never invents one.
             - Reassurance ban applies (BG6): nothing in the section reads as within budget.
Output:      - scripts/write-cost-log-section.sh (new, executable)
             - commands/loop.md — step 5 (Close) invokes it; that region only
             - tests/guardrails.test.sh — a new "cost in log.md" section
Done when:   (a) A fixture log.md plus a mixed fixture ledger: a `## Cost` section is written
                 carrying the coverage sentence, the priced-subset total labelled as partial,
                 and the rework figure with its definition (DL1, DL2, DL3);
             (b) run twice: exactly one `## Cost` section, and every other byte of the file —
                 including a seeded `## Budget events` block and the existing headings —
                 identical, asserted with `diff` (DL4);
             (c) a ledger with no record for the slug: the section is written and says so;
                 it is not omitted and contains no zeroed table (DL5);
             (d) after running, the only changed path under docs/loop/ is that log.md, and no
                 ledger content appears anywhere beneath docs/loop/ (DL7, H1);
             (e) log.md absent: exit 0, nothing written, a message saying why;
             (f) the section contains no "within budget", "under budget", or `✓` (BG6);
             (g) commands/loop.md step 5 names the script — with a prove-it-can-fail run
                 against a stripped temp copy;
             (h) S6's cases pass unmodified and its step-3/4 region is untouched by this
                 slice's diff;
             (i) byte-identical section content on a re-run of the same ledger (CV7).
Do NOT:      - Copy, move, mirror, summarise-into, or symlink the ledger under docs/loop/ (H1)
             - Introduce a new artifact type or a second file under docs/loop/<slug>/ (DL7)
             - Append a second `## Cost` section, or touch `## Budget events`, the
               phase-by-phase record, the gate decisions, or any other heading in log.md
             - Edit commands/loop.md outside step 5 (Close) — S6 owns step 3/4
             - Recompute any figure outside the lib, or produce a total the report would not
               produce (CV7)
             - Print a percentage without its definition and coverage (DL3), or a money figure
             - Write to the ledger, edit scripts/record-cost-event.sh, or add a ledger field
               (X4/BG13 — needs-decision instead)
             - Register this script as a hook; it runs only from the close step
             - Touch README.md (S8), CHANGELOG, VERSION, .claude-plugin/*, agents/, skills/
Depends on:  S6 — `## Budget events` must already be defined for DL4's "disturbs nothing else"
             to be a real assertion, and both slices edit commands/loop.md (different steps,
             serial by design). Reads S3's rework and coverage aggregates through the lib.
```

**Five tests.** 1 — one owner. 2 — one commit: "closing a unit records what it cost". 3 —
named above; (a) fails today because no log.md contains a `## Cost` section and the script does
not exist. 4 — criteria are file contents and `diff` results, not "the log is informative". 5 —
S6, named, with both reasons (heading coexistence and the shared file).

**Covers:** DL1, DL2, DL3, DL4, DL5, DL7.

---

### S8 — Document what shipped, and that no threshold default did

```
Owner:       loop-build
Context:     spec.md X6, X7, G0-D1 (no default ships, and why), §Non-goals ("a number in a
               repo acquires authority purely by being written down")
             README.md §Commands (the `/cost` row S2 already added), §Guardrails (the
               script/event/blocks table — where the full-suite guard belongs), §Cost ledger
               (the shape to match, and the section the new prose sits beside), §Development
             CHANGELOG.md — the existing entry shape; VERSION, .claude-plugin/plugin.json,
               .claude-plugin/marketplace.json — the three files ship-check.sh cross-checks
             scripts/ship-check.sh — the version-consistency gate that must stay green
             scripts/cost-report.sh, check-budget-gate.sh, warn-full-suite.sh,
               write-cost-log-section.sh as the earlier slices left them — every switch named
               in README must exist in one of them
Constraints: - Match the existing table and section idiom. Do not invent a documentation style.
             - Document `/cost`: that it reads `.claude/loop-cost.jsonl` and nothing else, no
               network, no account, no reading of Guild's feed; that coverage is **printed
               rather than assumed**; that no currency figure is ever produced.
             - Document the budget gate: both env var names, that **unset means disabled**,
               that an unparseable value disables it loudly, that a breach pauses before the
               next spawn and never kills an in-flight slice, and that a raised cap applies to
               one unit only.
             - **State that no threshold default ships, and why** — no baseline exists in this
               repo (E1), and most invocations currently carry no token figure at all (E2) —
               and that a threshold should be set from your own observed data rather than from
               any number in any document.
             - **No numeric example anywhere near either budget variable or any per-phase
               variable.** A suggested starting value is the same guess with an extra step.
             - Document the full-suite guard as a third row in the Guardrails table, noting it
               is the one guard that warns rather than refuses, with its escape hatch.
             - Version consistency: bump `VERSION`, `plugin.json`, `marketplace.json` to the
               same value and add the CHANGELOG entry, so ship-check.sh's gate stays green
               (X7).
             - `§Development`'s case count is stale (it says 57; the harness was at 121 before
               this unit). Correct it to the real count while you are in the file — a test
               count a reader can check is either right or worse than absent.
Output:      - README.md — a cost-reporting/budget section, the Guardrails table row, and the
               corrected case count
             - CHANGELOG.md — one entry
             - VERSION, .claude-plugin/plugin.json, .claude-plugin/marketplace.json — one
               consistent version
             - tests/guardrails.test.sh — cases appended to the "docs" section
Done when:   (a) A grep case asserts README names: `/cost`, `.claude/loop-cost.jsonl` as its
                 only source, `LARAVEL_LOOP_BUDGET_WARN`, `LARAVEL_LOOP_BUDGET_HARD`,
                 `LARAVEL_LOOP_ALLOW_FULL_SUITE`, the per-phase variable family, "unset means
                 disabled", the no-default statement with its reason, and the never-money
                 statement — each failing today (X6);
             (b) every env var and script path README names is asserted to exist in the
                 scripts, so the docs cannot describe a switch that was never built — the
                 existing `readme_ledger_check` is the pattern;
             (c) a **negative** case: no digit appears adjacent to any `LARAVEL_LOOP_BUDGET*`
                 name anywhere in README, so a helpful example cannot reintroduce a default
                 (G0-D1);
             (d) a negative case: README contains no "within budget"/`✓` framing for spend
                 (BG6);
             (e) `bash scripts/ship-check.sh` reports its version gate green, with VERSION,
                 plugin.json, and marketplace.json agreeing (X7);
             (f) the existing "every commands/*.md has a row in README's Commands table" case
                 still passes, and §Development's stated case count equals the harness's
                 actual total;
             (g) the full harness is green with a total above 121 (X1).
Do NOT:      - Suggest, exemplify, comment, or derive a threshold value — including from E2's
               two priced observations. Not in prose, not in a code fence, not in a table
             - Restructure README's Install snippet or the §Not included list; the snippet's
               pre-existing staleness (it omits record-cost-event.sh too) is a separate
               observation, not this unit's work
             - Change the four-agent claim, add a fifth agent, or restate any component's
               design in CHANGELOG beyond a normal entry
             - Edit any script, hook, agent, command, or skill file — if README would have to
               describe something that does not exist, that is needs-decision, not a code edit
             - Claim DC2 or DC3 are satisfied, or that the ledger's numbers have been believed
               across real units (that is v0.2's still-open DC1)
             - Document a dollar figure, a rate card, a hosted dashboard, or an export
Depends on:  S1, S3, S4, S5, S7 — it documents the guard (S1), the report (S2/S3), the gate
             and its env vars (S4), the per-phase family (S5), and the log section (S7).
             Naming each rather than just the last, because content comes from every one.
```

**Five tests.** 1 — one owner, docs plus metadata. 2 — one commit: "the README describes what
shipped". 3 — named above; (a) fails today because no budget variable name appears in README.
4 — criteria are strings present and, importantly, strings *absent*. 5 — five dependencies,
each named with what it supplies.

**Covers:** X6, X7.

## Cross-unit collisions — none live

Both other units under `docs/loop/` are **closed**: `cost-measurement-v0.2` and
`ship-observe-automation` each carry a `slices.md`, a `verify.md`, and a `log.md` with a
recorded G2 decision. So this unit owns the tree, and the only shared-surface discipline is
intra-unit, listed above:

| File | Slices | How it is kept safe |
|---|---|---|
| `tests/guardrails.test.sh` | all eight | Each appends its own named section; no case count is hard-coded, so "keep both blocks" always resolves a textual conflict |
| `scripts/cost-ledger-lib.sh` | S2 creates, S3 extends, S4/S5/S7 consume | Interface pinned above; serial by dependency, never concurrent |
| `scripts/cost-report.sh` | S2 creates, S3 extends | Serial; anchor order pinned so S3 fills rather than reorders |
| `scripts/check-budget-gate.sh` | S4 creates, S5 adds `--phase` | Serial |
| `commands/loop.md` | S6 (step 3/4), S7 (step 5) | Region ownership pinned **and machine-checked** by S6 case (e) and S7 case (h). Serial, never concurrent |
| `hooks/hooks.json` | S1, S4 | One registration each, existing entries byte-identical; S1 and S4 are never in flight together |
| `README.md` | S2 (one Commands row), S8 (everything else) | S2's `Do NOT` fences it to the single row |
| `scripts/record-cost-event.sh` | **none** | Every slice's `Do NOT`; S4 owns the durable grep assertion |

If a second unit is opened before this one closes, re-read this table: the markdown-touching
slices (S5, S6, S7, S8) are the collision-prone ones, and S1–S4 are effectively isolated.

## DC2 and DC3 — not slices, not G2 criteria

**DC2** (`/cost` run against a real `/loop` unit, and the coverage figure *recognised* by a
human who watched that run) and **DC3** (the gate observed doing nothing with both variables
unset on a real run, and observed firing on a total whose coverage was shown) are post-merge
conditions owned by the human. No builder can satisfy them and verify cannot check them.
**v0.2's DC1 also remains open and is not superseded** — this unit builds the instrument DC1
needs, which is not the same as satisfying it.

Passing G2 means it is built. DC2/DC3 mean it is trusted. DC1 means the ledger underneath it
is. Do not let any of the three be reported as another.

The one thing worth doing immediately after S3 merges: run `/cost` on the first real `/loop`
unit and read the coverage line. That is what settles the spec's single open question — whether
a synchronous run prices its `loop-build` invocations — and the answer determines how much of a
threshold's job a threshold can actually do.

## Self-audit

Every slice was checked against the five tests and against this phase's own refusals: no slice
has two owners; no title contains an "and also"; every slice names a test that fails on today's
tree; no `Do NOT` is empty, generic, or "nothing"; no slice depends on one later in the list;
and the ordering is by dependency, not by layer (S1, a script, runs first *alongside* S2 rather
than being sequenced by topic; S5 and S6 are markdown-and-script slices running concurrently
because their files are disjoint).

Six cuts were considered and rejected:

- **Merging R5 and R2 into one "cost tooling" slice.** Rejected on instruction and on merit:
  reporting states what was spent, gating decides whether to continue. The second can stop
  work, and it deserves its own review.
- **Splitting S2 into a library slice and a report slice.** Rejected: a library with no caller
  delivers nothing observable — that is a refactor, and refactors are their own slices. The
  interface is pinned instead, which buys the same parallel-safety at no commit cost.
- **Merging S3 into S2.** Rejected: 20 criteria in one slice, and the honesty spine (CV1–CV7)
  deserves a review that is not competing for attention with five breakdown tables.
- **Splitting S4 into "parse thresholds / prove inertness" and "evaluate and block".** Rejected:
  the first half's entire observable behaviour is *nothing happening*, which is not a slice, and
  BG1's proof obligation is only meaningful once there is something that could have fired.
- **Making S5 parallel to S4 with its own tiny script.** Rejected: two threshold parsers
  diverge, and BG2's loud-disable discipline must have exactly one home.
- **Merging S6 and S7** (both touch `commands/loop.md`). Rejected: two ideas, two commits.
  Sequenced serially with machine-checked region boundaries instead.

## Riskiest slice — S2

Not because it is the largest, though with S4 it is. Because **its failure mode is invisible to
every test that could be written for it, and to G2.**

Thirteen of S2's criteria are about output that must not mislead a human — a coverage line that
lands before the total, a partial total that reads as partial, an absent table where a table of
zeros would have been easier. A harness case can assert that the string `Coverage:` appears at a
lower line number than the first token figure. It cannot assert that a tired person reading the
output at 6pm comes away with the right belief about how much of their spend was observed. Every
S2 case can go green while the report still retires the question — which is, in the spec's own
words, worse than no number, and precisely the failure v0.2's D4 deferred to this unit to fix.

Two more reasons it carries the risk: **four slices consume its lib**, so a wrong interface or a
wrong `unavailable` convention is re-litigated four times and inherited by the budget gate,
where the same misreading becomes a spend decision (CV8); and the arithmetic is being written
against a ledger that **does not exist in this tree** (E1), so every fixture is a
reconstruction from `record-cost-event.sh`'s emit paths rather than a sample of real output.
A field this repo has never actually written is a field a fixture can get subtly wrong in a way
no test notices.

**Mitigation, already in its brief:** the three E6 record shapes are named as explicit cases
rather than left to be discovered; the empty-state paths are treated as the common case rather
than the edge, because E1 says they are; determinism is asserted by re-running and diffing; and
the reassurance ban is a negative case, not a hope. If a fixture cannot be built for a record
shape without inventing a field, that is `needs-decision` — never a ledger change (X4).

**Runner-up: S4.** It carries G0-D1's accepted residual risk directly — a threshold set today
is compared against a total that may omit most of the spend it exists to control. The spec
contains that risk with BG5, BG6, BG9 and CV8 rather than resolving it, so S4's real correctness
bar is *never issuing reassurance it cannot support*, which is a harder thing to test than a
threshold comparison. It is also the only slice in this unit that can stop work, and the one a
builder is most likely to mis-implement by copying the adjacent `LARAVEL_LOOP_COST_MAX_LINES`
fallback pattern sitting twelve lines away in the same repo (E9).

**Most likely to return `needs-decision`: S5.** Its mechanism is mine, not the spec's, and it
rests on a limitation I found while slicing rather than one the spec anticipated: an
invocation's finish record is not written until after it returns, so a phase cannot see its own
in-flight cost. PE3's flag therefore reflects a phase's *recorded* invocations only, which for a
single-invocation phase means it can never fire on itself. I have pinned that mechanism and
required PE2 to document the limitation, because a half-visible figure documented is in this
unit's spirit and a half-visible figure hidden is against it. If the human prefers the
conductor to surface the overrun instead, that is a re-slice of S5 alone and touches nothing
else.

## What a human may want to change at this gate

Five decisions below are mine, not the spec's. Each is cheap to reverse now and expensive later.

1. **`scripts/cost-ledger-lib.sh`** — a fourth, unregistered script in a repo whose scripts are
   all hooks. The alternative is the budget gate re-implementing the coverage arithmetic, which
   risks two totals for one file (CV7) and a gate that disagrees with the report it cites.
2. **S5's phase-flag mechanism and the `LARAVEL_LOOP_BUDGET_PHASE_*` names** — see the
   needs-decision note above. The limitation is real whichever mechanism you pick; the choice is
   whether the phase agent or the conductor surfaces it.
3. **BG11's per-unit `hard-override` marker file** — chosen because an env var cannot be raised
   mid-session in a way the hook can see, so "raise the cap and continue" needs a file or it
   needs a restart. The marker only ever *raises* an already-set threshold and never arms an
   unset gate.
4. **The `## Cost` / `## Budget events` split in `log.md`** — two headings, two owners, because
   one replaced-in-place section (DL4) cannot also hold events the conductor appends as they
   happen (DL6). A single heading would have S7's rewrite clobber S6's records.
5. **The BG1 / CO12 reconciliation** recorded above: the gate is silent when unconfigured;
   `/cost` still names the configuration it read. Read strictly, the spec's failure-mode table
   and CO12 can be taken to conflict, and a verifier would be right to raise it. If you read it
   the other way — that `/cost` must also say nothing about budgets when none are set — say so
   now, because CO12's test is written either way and only one is right.
