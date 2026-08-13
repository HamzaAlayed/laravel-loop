# Slices — cost-measurement-v0.2

Cuts `docs/loop/cost-measurement-v0.2/spec.md` (G0 approved, D1–D5 recorded, no open
questions) into seven slices. Every acceptance criterion in the spec is assigned to exactly
one slice, or named below as cross-cutting or as a post-merge condition. Nothing is dropped.

**7 slices · 3 can start immediately · critical path S2 → S3 → S4 → S5 → S6 (5 deep)**

## The seam

The smallest change that delivers observable value is **a ledger file that appears after a
run and contains one start and one finish record per invocation** (S2). Everything else is
either hardening that file (S3, S4), enriching it (S5), explaining it (S6), or independent
of it (S1, S7).

Deliberately *not* the seam: `Unit:`/`Slice:` propagation (S1). It is a prerequisite for the
ledger being *useful*, but on its own it produces no observable artifact — a change whose
only effect is that two extra lines appear in briefs nobody reads. It runs first in parallel
because it is cheap, not because it delivers first.

## Order and concurrency

```
t0  ├── S1  Unit/Slice propagation      (docs + grep test)
    ├── S2  Ledger hook — records       ← critical path starts
    └── S7  Cache-friendly ordering     (docs + grep test)

         S2 ─→ S3  exactly-once + concurrency
                 └─→ S4  bound + gitignore
                       └─→ S5  rework attribution
                             └─→ S6  README
```

- **Genuinely parallel at t0:** S1, S2, S7 — three separate builders, three worktrees. This
  matches `/loop`'s 2–3 in-flight cap exactly; do not try to start more.
- **S3, S4, S5 are serial and that is a real dependency, not layer habit.** All three edit
  the same script, and each needs a behaviour the previous one establishes: S4's H3
  (eviction must not corrupt a concurrent append) is meaningless without S3's append
  guarantee, and S5 must find "open invocations" by reading start records that only S3's
  invocation key makes matchable.
- **Merge in path order.** S1 and S7 may merge at any point before S6; both touch files S6
  does not.

## Contract pinned across slices

These are fixed here, at G1, so two builders in two worktrees cannot invent two versions of
the same thing. **No slice may change any of these; a slice that believes one is wrong
returns `needs-decision`.** Items marked *(slicer-chosen)* are not in the spec and are open
to human override at this gate.

| Thing | Value | Set by | Read by |
|---|---|---|---|
| Envelope lines, verbatim | `Unit:  <slug>` and `Slice: S<n>` at line start, one per line, `Slice` omitted for spec/slice phases | S1 | S2 |
| Where those lines must appear | In the **prompt text passed to the Agent/Task tool** (the envelope, verbatim), not only in the tool's `description` | S1 | S2 |
| Ledger path | `.claude/loop-cost.jsonl` | S2 | S3–S6 |
| Script name *(slicer-chosen)* | `scripts/record-cost-event.sh` — deliberately not `emit-agent-events.sh`, which is Guild's | S2 | S3–S6 |
| Disable switch *(slicer-chosen)* | `LARAVEL_LOOP_COST_LEDGER=0\|off` disables all writing; matches the `LARAVEL_LOOP_REFINE_CAP=0` convention | S2 | S6 |
| Line cap env var *(slicer-chosen)* | `LARAVEL_LOOP_COST_MAX_LINES`, default `5000` | S4 | S6 |
| Correlation field *(slicer-chosen, required by L1/L9)* | every record carries `invocation_id`, stable across the start and finish of one invocation | S2 | S3, S5 |
| Model honesty fields | `model` plus `model_source: "observed" \| "derived" \| "unknown"` (L11) | S2 | S6 |
| Rework fields | `phase_detail: "rework"` (present only when true) and `refine_passes: <int>` | S5 | S6 |
| Unavailable value | JSON `null`, or the key absent. **Never `0`** (L3) | S2 | all |

## Cross-cutting — asserted by every slice, owned by none

- **X1** — `bash tests/guardrails.test.sh` green, `shellcheck -S warning scripts/*.sh`
  clean, executable bit on anything new, harness case count above **22** (today's count).
  Every slice adds cases, so every slice moves this.
- **X2** — both existing guardrails behave exactly as today; their 22 cases pass
  **unmodified**. This appears in every slice's `Do NOT`.
- **X3** — satisfied by S2 (the only slice touching `hooks/hooks.json`) and re-asserted by
  the harness's existing structure check on every run.

## Slices

### S1 — Propagate `Unit:` and `Slice:` through the envelope, the commands, and the returns

```
Owner:       loop-build
Context:     skills/loop-protocol/SKILL.md (§Task envelope, §Return shape)
             commands/loop.md (steps 1, 2, 3, 4 — every place an agent is briefed)
             commands/slice.md (step 2), commands/verify.md (step 3)
             agents/loop-spec.md, loop-slice.md, loop-build.md, loop-verify.md (§Return)
             spec.md §Attribution (P1–P4), §E3, and the pinned-contract table above
Constraints: - Markdown only. No script, no hook, no JSON.
             - The envelope lines are exactly `Unit:  <slug>` / `Slice: S<n>` at line
               start. No bold, no backticks, no reordering — a hook greps them literally.
             - `Slice` is omitted (not blank, not "n/a") for the spec and slice phases.
             - The return shape stays ≤10 lines. Unit/Slice fit inside the existing DID or
               a single added line — they do not extend the shape (spec §Constraints).
             - Commands must place the lines in the prompt passed to the Agent/Task tool,
               because that is the only place the ledger hook can read them.
             - An agent briefed without them says so in its return (P4) — pin the wording
               so it is greppable, e.g. `FLAGS: briefed without Unit/Slice`.
Output:      - skills/loop-protocol/SKILL.md — envelope gains both fields, documented as
               mandatory, with the spec/slice omission rule stated
             - commands/loop.md, slice.md, verify.md — both set, everywhere they brief
             - all four agents/*.md — both echoed in the return
             - tests/guardrails.test.sh — a new "envelope attribution" section
Done when:   A new harness case fails on today's tree and passes after: it asserts
             `Unit:` appears in SKILL.md's envelope block, in all three commands/*.md, and
             that all four agents/*.md name Unit and Slice in their return section — and
             it asserts the P4 no-brief wording exists in each agent. Prove it can fail:
             the case runs against a temp copy with the lines stripped and expects a
             failure there, then against the real tree and expects a pass.
Do NOT:      - Touch scripts/, hooks/hooks.json, .gitignore, README.md, or .claude/
             - Add a third envelope field, a context budget (R4.2, v0.3), or any cost
               wording to the envelope
             - Modify either existing guardrail script or its 22 existing cases
             - Reorder or restructure the existing envelope/return sections beyond adding
               the two fields — S7 owns ordering, and a reorder here collides with it
Depends on:  nothing
```

**Five tests.** 1 — one owner, `loop-build`, all markdown. 2 — one commit: eight small
edits, one idea ("briefs carry the unit they belong to"). 3 — named test above; fails today
because the string `Unit:` does not occur in SKILL.md's envelope block. 4 — criteria are
observable text in files a grep can read, not "attribution is improved". 5 — no
dependencies; the literal format it must produce is pinned in the table above, not implied
by S2.

**Covers:** P1, P2, P3, P4.

---

### S2 — Add the cost ledger hook: one start and one finish record per invocation

```
Owner:       loop-build
Context:     spec.md §The ledger (L1–L11), §E1–E7, §Failure modes, D1/D4
             .claude/agents-board.jsonl — real payload evidence: one `start`, then TWO
               ends for one invocation (`subagent_stop` with null tokens, then `completed`
               with tokens 60787 / ms 239271)
             scripts/enforce-refine-cap.sh — copy its shape verbatim: `set -uo pipefail`,
               the `extract()` jq→python3→empty ladder, the raw-payload fallback, the
               why-am-I-wired-here header comment, `CLAUDE_PROJECT_DIR:-$PWD` state root
             hooks/hooks.json — existing Bash registrations that must survive untouched
             tests/guardrails.test.sh — harness idiom: `run_hook`, `expect`, temp dirs
             docs/loop/laravel-loop-cost-requirements.md §R1.1 — the field list
Constraints: - Zero dependency: bash + coreutils, degrading jq → python3 → safe no-op.
               Clean under `shellcheck -S warning`. Executable bit set.
             - Registers PreToolUse and PostToolUse on matcher `Agent|Task`.
               **Do not register SubagentStop in this slice** — E4 shows it is a second
               finish signal carrying no tokens, and deduping it is S3's job. One finish
               signal here means L1 holds by construction rather than by luck.
             - Exit 0 on every path, unconditionally, including its own internal error.
               Never blocks, delays, or alters a spawn (L6, L7).
             - Unavailable is `null` or absent. Never `0` (L3). No arithmetic invents an
               input/output split (D1). Async-launched invocations record their status and
               null tokens (D4) — never a zero.
             - `model_source` states whether the model was observed or derived (L11).
             - Slug resolution order: `Unit:` line in the invocation prompt → the same
               line in `description` → `"unknown"`. Never inferred from cwd or last-seen
               unit. Same chain for `Slice:`.
             - Header comment explains why this event, in the style of both existing
               scripts.
             - **Early exit rule:** before writing the extraction logic, establish whether
               the payload actually carries the invocation prompt (E1/E2 prove
               `tool_input.description` and `subagent_type`; they prove nothing about the
               prompt). If it does not, every real record is `slug: "unknown"` and the
               resolution design is a decision, not an implementation — return
               `needs-decision` with the observed payload keys rather than inventing a
               path. Do not spend refine passes on this.
Output:      - scripts/record-cost-event.sh (new, executable)
             - hooks/hooks.json — two added registrations, existing Bash entries byte-identical
             - tests/guardrails.test.sh — a new "cost ledger" section
Done when:   New harness cases, all against a temp CLAUDE_PROJECT_DIR:
             (a) a simulated four-phase run (spec, slice, build, verify) yields exactly one
                 start and one finish record per invocation and every L2 field is present
                 in each — asserted per phase (L10, L1);
             (b) a payload with no `Unit:` line yields a record with `slug":"unknown"` and
                 no dropped record (L4);
             (c) exit 0 asserted individually for: valid, malformed, empty payload,
                 unwritable ledger dir, and PATH stripped of jq and python3 — and in the
                 stripped case the ledger contains no partial line (L6, L8);
             (d) an `async_launched` payload records null tokens and a status saying why,
                 with no `0` anywhere in the record (L3, D4);
             (e) a payload with cache-read tokens records them; one without omits the field
                 rather than zeroing it (C4);
             (f) the ledger is created at `.claude/loop-cost.jsonl` and nothing is written
                 under `docs/loop/` (H1);
             (g) `LARAVEL_LOOP_COST_LEDGER=0` writes nothing and exits 0.
             Plus: `shellcheck -S warning scripts/*.sh` clean, and the harness's existing
             structure check still passes with the new registrations (X3).
Do NOT:      - Read, write, import, or depend on `.claude/agents-board.jsonl` or Guild's
               `emit-agent-events.sh` — copy the *shape*, never the file (spec §Non-goals)
             - Register SubagentStop, implement dedupe, or implement eviction — S3 and S4
             - Tag rework or read `.claude/loop-refine-passes.tsv` — S5
             - Touch .gitignore (S4), README.md (S6), agents/*.md, commands/*.md,
               skills/ (S1, S7)
             - Modify either existing guardrail script, its registrations, or its 22 cases
             - Add pricing, a dollar figure, a rate table, a report, a `/cost` command, a
               budget, or any network call
Depends on:  nothing. Shares the pinned `Unit:` / `Slice:` literal with S1 — that literal
             is fixed in the contract table above, so neither slice waits on the other.
             Until S1 merges, real runs legitimately record `slug: "unknown"` (L4).
```

**Five tests.** 1 — one owner, one script. 2 — one commit: a new hook, its registration,
its tests; the "and also"s that would have made it two are pushed to S3/S4/S5. 3 — named
above; every case fails today because the script does not exist. 4 — criteria are file
contents and exit codes, not "the hook is well structured". 5 — no dependencies, and the
shared literal is named rather than assumed.

**Covers:** L1 (single-signal path), L2, L3, L4, L6, L7, L8, L10, L11, C4, H1, X3.

---

### S3 — Make the ledger exactly-once and safe under concurrency

```
Owner:       loop-build
Context:     spec.md L1, L5, L9, §Failure modes (double registration; PostToolUse +
               SubagentStop for one invocation), §E4
             .claude/agents-board.jsonl — the two-ends-for-one-invocation evidence
             scripts/record-cost-event.sh as S2 left it
Constraints: - Zero dependency. **No `flock`** — it is not present on macOS by default and
               this repo is bash + coreutils only.
             - Recommended approach, deviate only with a FLAG saying why: build the whole
               record in memory and emit it with a single `>>` append, keeping every line
               under 4096 bytes so the append is atomic on a local filesystem; truncate or
               omit an oversize field rather than splitting a line.
             - Dedupe keys on the `invocation_id` S2 established. A second finish signal
               for a key already finished is discarded silently, exit 0.
             - Registering SubagentStop is optional. If it is registered, its record must
               be deduped against the PostToolUse finish; if it is not, say so in the
               header comment and in the return, because a reader will ask.
             - Still exits 0 on every path and still never blocks (L6, L7 must not regress
               — re-run S2's exit-code cases).
Output:      - scripts/record-cost-event.sh — dedupe + atomic append
             - hooks/hooks.json — only if SubagentStop is added
             - tests/guardrails.test.sh — cases appended to the "cost ledger" section
Done when:   (a) A forced-concurrency case: N ≥ 20 finish events for distinct invocations
                 fired in parallel with `&` and `wait` produce exactly N lines, each a
                 complete parseable JSON object, with no interleaved or truncated line —
                 the concurrency is forced, not hoped for (L5);
             (b) the same finish payload delivered twice yields one finish record (L9);
             (c) a PostToolUse finish and a SubagentStop finish for one `invocation_id`
                 yield one finish record, and it is the one carrying tokens (L1, E4);
             (d) the script invoked twice on the same event — simulating plugin plus manual
                 install — yields one record (L9);
             (e) all of S2's exit-0 cases still pass unmodified.
Do NOT:      - Change the record shape, the field list, or the slug resolution chain S2 set
             - Add eviction or a line cap (S4), or any rework tagging (S5)
             - Introduce a dependency on flock, jq, python3, or a lock daemon
             - Touch either existing guardrail script or its 22 cases
             - Weaken any S2 case to make a new one pass
Depends on:  S2
```

**Five tests.** 1 — one owner, one script. 2 — one commit: "make it exactly-once". 3 — the
forced-concurrency and double-signal cases fail against S2's script and pass after. 4 —
criteria are line counts and record counts in a file, not "the append is safe". 5 — S2,
named.

**Covers:** L1 (duplicate-signal path), L5, L9.

---

### S4 — Bound the ledger, evict oldest-first, and keep it out of git

```
Owner:       loop-build
Context:     spec.md §Hygiene (H2–H5), §Failure modes (cap hit mid-run; human deletes the
               ledger mid-run)
             .gitignore — three existing entries, same shape
             scripts/enforce-refine-cap.sh `write_count()` — the existing bounded-file
               idiom in this repo (`tail -200` into a temp, then move)
Constraints: - `LARAVEL_LOOP_COST_MAX_LINES`, default 5000, non-numeric falls back to the
               default (the cap parser in enforce-refine-cap.sh is the pattern).
             - Oldest-first eviction. Never truncate the file to empty, not even
               transiently — a reader that catches it mid-eviction must see either the old
               content or the new (H3).
             - Recommended approach, deviate only with a FLAG: a `mkdir`-based mutex held
               only by the evictor; appenders never block on it — they retry with a short
               bounded backoff and then append regardless. Cost accounting that can stall a
               spawn is worse than a slightly-over-cap file (L7 outranks H2).
             - The ledger being absent is normal, not an error: the next event recreates it
               (H5).
             - `.gitignore` must also cover any sidecar state file S3 introduced.
Output:      - scripts/record-cost-event.sh — cap + eviction
             - .gitignore — ledger and any sidecar state
             - tests/guardrails.test.sh — cases appended to the "cost ledger" section
Done when:   (a) With `LARAVEL_LOOP_COST_MAX_LINES=50`, firing 80 events leaves exactly 50
                 lines, the newest 50, in order (H2);
             (b) eviction running concurrently with appends leaves every line intact and
                 the file never observed empty; assert a non-zero line count throughout
                 (H3);
             (c) `git check-ignore .claude/loop-cost.jsonl` succeeds, and a
                 `git status --porcelain` in a fixture repo after events shows no ledger
                 (H4);
             (d) deleting the ledger mid-sequence: the next event recreates it, exit 0,
                 nothing errors, and earlier events are simply gone rather than the run
                 failing (H5);
             (e) a non-numeric `LARAVEL_LOOP_COST_MAX_LINES` falls back to 5000 rather than
                 disabling the bound or crashing.
Do NOT:      - Add a cleanup command, a prune subcommand, or anything covering the other
               two `.claude/` state files — explicitly raised and rejected at G0
             - Delete, rotate, compress, or archive to a second file; eviction is in-place
             - Touch `.claude/loop-refine-passes.tsv` or `.claude/agents-board.jsonl` or
               their gitignore entries
             - Change the record shape or dedupe behaviour (S2, S3)
             - Document any of this in README (S6)
Depends on:  S3
```

**Five tests.** 1 — one owner. 2 — one commit: "the ledger stays small and stays out of
git". 3 — the 80-events-into-a-50-line-cap case fails today (no cap exists) and passes
after. 4 — criteria are line counts and `git check-ignore` exit codes. 5 — S3, named, with
the reason stated (H3 needs S3's append guarantee).

**Covers:** H2, H3, H4, H5.

---

### S5 — Attribute rework at whole-invocation granularity

```
Owner:       loop-build
Context:     spec.md §Rework (W1–W8), **D3 in full including its three consequences**,
               §Failure modes (red→green→red→green is not rework; one refine pass then
               green is rework in full)
             scripts/enforce-refine-cap.sh — the definition being reused: a *second
               consecutive failing run of the same target*, with a green run resetting;
               plus its target-extraction and is_failure logic
             tests/guardrails.test.sh — its existing red/green sequence cases show the
               fixture shape for simulating a refine sequence
             scripts/record-cost-event.sh as S4 left it
Constraints: - **Never write to, reset, reshape, or take ownership of
               `.claude/loop-refine-passes.tsv`.** Reading it is permitted; relying on it
               is not, because enforce-refine-cap.sh zeroes the counter at the moment of a
               trip, which is exactly the moment W6 needs to observe. Keep an independent
               counter in the cost hook's own state file, applying the same rule and
               honouring the same `LARAVEL_LOOP_REFINE_CAP` value.
             - This requires registering the cost script on PostToolUse / Bash as well.
               That is an added registration alongside enforce-refine-cap.sh, not a change
               to it — W8 must hold byte-for-byte.
             - Attribution rule, pinned here so it is not designed mid-build: key a refine
               observation to an open invocation by `session_id` + `agent_type` (+ `cwd`
               when the payload carries it). When it cannot be narrowed to exactly one open
               invocation, mark **every** open invocation of that agent in that session as
               rework and record `rework_attribution: "ambiguous"`. Over-attribution is the
               accepted bias (D3); silent mis-attribution is not.
             - `refine_passes` is a count and is **never** multiplied, divided, or
               converted into a token figure (W5). No estimated split, ever (D3 rejected).
             - The script's header comment states, in prose, what the rework figure
               measures — *the cost of slices that were not right first time*, not *the cost
               of retrying* — that it deliberately over-attributes, and that it is not
               comparable to the source document's <15% target (W4). S6 lifts this wording
               into README; write it so it can be lifted.
Output:      - scripts/record-cost-event.sh — refine detection, `phase_detail`,
               `refine_passes`, cap-trip terminal record, W4 header prose
             - hooks/hooks.json — PostToolUse / Bash registration added
             - tests/guardrails.test.sh — a new "rework attribution" section
Done when:   (a) A simulated red → red → red build invocation: the finish record carries
                 `phase_detail":"rework"` and `refine_passes` ≥ 1 (W1, W7);
             (b) a simulated red → green invocation carries no `phase_detail` (W7);
             (c) red → green → red → green carries no `phase_detail` — the discriminating
                 case, because the loose reading marks it and would read 100% rework
                 forever (W2, W7);
             (d) rework and first-attempt records are separable by reading the ledger alone
                 — assert a grep over the file partitions the records with no external
                 input (W3);
             (e) no test asserts any per-pass token figure anywhere, and `refine_passes`
                 never appears multiplied into a token field (W5);
             (f) a tripped cap produces a terminal record naming the slice and its rework
                 total at whole-invocation granularity (W6);
             (g) `grep` finds the D3 granularity statement in the script header (W4);
             (h) **all 22 existing guardrail cases pass unmodified and
                 `git diff -- scripts/enforce-refine-cap.sh` is empty** (W8, X2).
Do NOT:      - Edit scripts/enforce-refine-cap.sh at all, or change the format or meaning
               of `.claude/loop-refine-passes.tsv`
             - Divide, estimate, prorate, or interpolate tokens across refine passes
             - Compute or store a rework percentage, ratio, or any aggregate — v0.3 reports
             - Add a budget, threshold, warning, or anything that stops or prompts on spend
             - Touch README.md (S6), .gitignore (S4), agents/, commands/, skills/
Depends on:  S3
```

**Five tests.** 1 — one owner. 2 — one commit: "the ledger knows what was rework". It is
the largest of the five ledger slices; the alternative split (tagging vs. cap-trip record)
would leave W6 as a two-line commit whose test needs everything in W1–W5 anyway. 3 — the
red→red→red and red→green→red→green cases fail today and pass after. 4 — criteria are
strings present or absent in ledger records for named input sequences. 5 — S3, named.

**Covers:** W1, W2, W3, W4 (script half), W5, W6, W7, W8.

---

### S6 — Document the ledger in README the way the other state files are documented

```
Owner:       loop-build
Context:     README.md §Guardrails (the script/event/blocks table) and §Project memory
               (the file/holds table) — the two existing shapes to match
             spec.md X4, W4, §Non-goals ("the person who did not ask for telemetry"),
               §Constraints, D4
             scripts/record-cost-event.sh header as S5 left it — the W4 wording to lift
Constraints: - Match the existing table idiom; do not invent a new documentation style.
             - State all of: what writes it, where it lives (`.claude/loop-cost.jsonl`),
               what it records, how to disable it (`LARAVEL_LOOP_COST_LEDGER=0`), how to
               bound it (`LARAVEL_LOOP_COST_MAX_LINES`), that deleting it is safe at any
               time, and **that it never leaves the machine**.
             - State that it counts tokens and durations and is **not** money, that a
               `null` means unavailable and never zero, that async-launched invocations may
               be unpriced and why, and the W4 rework wording lifted from the script header.
             - State that it is separate from and never reads Guild's
               `.claude/agents-board.jsonl`, since both may be installed.
             - No `/cost` command, no report, no example output that looks like a report.
Output:      - README.md — one new section plus a row in the existing state-file table
             - tests/guardrails.test.sh — one case appended
Done when:   A harness case greps README for: the ledger path, both env var names, the
             "never leaves the machine" claim, the not-money statement, and the D3 rework
             wording — and fails today on every one of them. Every env var and path the
             README names is asserted to exist in `scripts/record-cost-event.sh`, so the
             docs cannot describe a switch that was never built.
Do NOT:      - Touch README's "Not included in v0.1" list or its Commands table — those are
               the sibling unit `ship-observe-automation`'s edit surface (see below)
             - Add a `/cost` command, a sample report, a rate table, or a dollar figure
             - Restate the ledger's design in CHANGELOG, or change the four-agent claim
             - Edit any script, hook, agent, command, or skill file
Depends on:  S2, S4, S5 — it documents the path and record shape (S2), the bound and the
             disable/delete story (S4), and the rework semantics (S5). Naming all three
             rather than just S5 because content comes from each.
```

**Five tests.** 1 — one owner, one file plus its test. 2 — one commit: one README section.
3 — the grep case fails today because "loop-cost.jsonl" does not appear in README. 4 —
criteria are strings a human will read, cross-checked against the script so they cannot
drift. 5 — S2, S4, S5, each named with what it supplies.

**Covers:** X4, W4 (README half).

---

### S7 — State the cache-friendly prompt ordering as a hard rule and test for violations

```
Owner:       loop-build
Context:     skills/loop-protocol/SKILL.md — where the rule goes
             spec.md §Cache-friendly ordering (C1–C3), **D2** (ships on rationale alone;
               its payoff is deliberately unmeasured in v0.2), **D5** (`{{args}}` in a
               command title is explicitly *not* a violation — R4.1's scope is its literal
               wording: timestamp, run id, counter)
             agents/*.md and commands/*.md — the files the test scans
Constraints: - The ordering is the five-level one already fixed by the spec: system prompt,
               loop-protocol contract, conventions/decisions, spec/slice list, task
               envelope last. Do not re-derive or re-order it.
             - The rationale ships **with** the rule, in the same place: a single volatile
               token near the front invalidates the whole cached prefix behind it. C1 makes
               the reason load-bearing, because a rule without its reason gets reordered by
               the next person who finds it inconvenient.
             - The test's violation set is the literal one: timestamp, run id, counter.
               `{{args}}` is not a violation (D5) and the test must not flag it — assert
               that explicitly, or the first run of the harness fails on today's clean tree.
             - "Top half" needs one definition, stated in the test: use the first 50% of
               the file's lines and say so in a comment.
Output:      - skills/loop-protocol/SKILL.md — a new ordering section with its rationale
             - tests/guardrails.test.sh — a new "prompt ordering" section
             - agents/*.md or commands/*.md — only if a real violation exists today (C2);
               expected to be none
Done when:   (a) The grep case passes against the real tree unchanged (C2 — no violation
                 exists today, and `{{args}}` in the command titles does not trip it);
             (b) **the case is proven able to fail**: it runs against a temp copy of
                 `agents/` with `{{timestamp}}` injected into the top half of one file and
                 expects a failure there. A grep test that has never been seen red is an
                 assertion that cannot fail, and loop-verify treats that as a FAIL (C3);
             (c) `grep` finds both the ordering rule and its stated reason in SKILL.md (C1).
Do NOT:      - Touch the Task envelope or Return shape sections of SKILL.md — S1 owns those,
               and both slices editing one file is only safe while they edit different
               sections
             - Move `{{args}}` in commands/loop.md, or reorder any command file's content —
               explicitly settled by D5
             - Add cache-hit-rate measurement, reporting, or any cache field to the ledger
               (C4 lives in S2)
             - Touch scripts/, hooks/hooks.json, README.md, or .gitignore
Depends on:  nothing. Deliberately independent of the ledger: it is a documentation rule
             plus a grep test, it reads nothing the hook writes, and blocking it behind
             L/P/W would be sequencing by topic rather than by dependency.
```

**Five tests.** 1 — one owner. 2 — one commit: one section, one test section. 3 — the C1
grep fails today; the C3 case is required to demonstrate a red before its green. 4 —
criteria are text presence and a test's behaviour against a seeded violation. 5 — none, and
the SKILL.md section-level split from S1 is named rather than left to chance.

**Covers:** C1, C2, C3.

## Cross-unit collisions — `ship-observe-automation`

That unit's spec is G0-approved and sits in `docs/loop/ship-observe-automation/`. It has
**no `slices.md` yet**, so this is a file-level read of its spec, not of its cuts. Naming
these now rather than discovering them at merge:

| File | This unit | `ship-observe-automation` | Risk |
|---|---|---|---|
| `tests/guardrails.test.sh` | every slice appends a section | X2 appends ship cases | **Highest.** Textual conflict at the append point. Resolution is always "keep both blocks" — no case count is hard-coded anywhere, so nothing else breaks |
| `skills/loop-protocol/SKILL.md` | S1 (envelope), S7 (new ordering section) | O7 (Observe phase + the `↺` in the diagram) | Different sections; do not run S1 or S7 concurrently with that unit's protocol slice in separate worktrees |
| `README.md` | S6 (new ledger section + state-file table row) | X1 ("Not included in v0.1", Commands table) | Different sections, and S6's `Do NOT` fences it off explicitly |
| `commands/loop.md` | S1 (briefs carry Unit/Slice) | likely step 5 "Close" → Observe capture | Different regions |
| `hooks/hooks.json` | S2, S5 | none stated | None |
| `scripts/` | one new script | one new ship script | None |

**Recommendation:** land one unit's markdown-touching slices before starting the other's.
Concretely — S1, S6, S7 are the collision-prone ones; S2–S5 are effectively isolated and can
run alongside anything that unit does.

## DC1 — not a slice, not a G2 criterion

**DC1** (believable numbers across 5+ real units of work, with the unpriced share stated)
is a post-merge condition owned by the human, not a slice. No builder can satisfy it, and
verify cannot check it. Passing G2 means this is built; DC1 means it is trusted. Do not let
the first be reported as the second.

The one thing worth doing early: on the first real `/loop` run after S2 merges, look at the
share of finish records with null tokens. If that share is large (E5/D4 say it may be, and
build is the biggest spender), closing it becomes its own intent — not a patch to this unit.

## Self-audit

Each slice was checked against the five tests above and the following, all clean: no slice
has two owners; no slice's title contains an "and also"; every slice names a test that fails
today; no `Do NOT` is empty or generic; no slice depends on one later in the list. Two cuts
were considered and rejected:

- **Splitting S5 into tagging (W1–W5, W7) and the cap-trip record (W6).** Rejected: W6's
  test needs the counter W1–W5 build, so the second slice would be two lines of code behind
  a full fixture setup — a commit boundary that costs more than it isolates.
- **Merging S3 into S2.** Rejected: it makes the largest slice larger, and the concurrency
  and double-signal work is exactly where a refine cap would trip. It deserves its own
  review.

Two things a human may want to change at this gate, flagged because they are mine and not
the spec's: the four *(slicer-chosen)* names in the contract table, and S5's ambiguous-
attribution rule (mark all open invocations of that agent in that session, record
`rework_attribution: "ambiguous"`).

## Riskiest slice — S2

Not because it is the biggest, though it is. Because **it rests on one thing this
repository cannot confirm**: that the hook payload carries the invocation's prompt text.
E1 and E2 establish that `tool_input.description`, `subagent_type`, `session_id`,
`totalTokens`, and `totalDurationMs` are all populated — they establish nothing about the
prompt. If the prompt is not in the payload, the hook cannot read the `Unit:` line S1 puts
in the envelope, every record is legitimately `slug: "unknown"` (L4 passes), every listed
test still goes green, and **the unit ships a ledger of anonymous charges** — the exact
outcome §Problem says is useless. That failure is invisible to G2 and only surfaces at DC1,
weeks later.

Two more reasons it carries the risk: it is the only slice three others depend on, so a
wrong record shape here is re-litigated four times; and its correctness bar is unusually
wide — eleven criteria, five of which are about behaving well when something is broken.

Mitigation is already in its brief as an early-exit rule: establish the payload's real
shape first, and return `needs-decision` with the observed keys rather than spending refine
passes designing around an unknown. That same capture settles E6 (the input/output split
and cache-read tokens) at zero extra cost.

Runner-up: **S5** — the only slice that must reproduce another script's semantics without
touching it, and the only one whose correctness depends on an attribution rule invented at
G1 rather than given by the spec.
