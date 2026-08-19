# resumed-invocation-never-reaches-the-ledger

Phase: Spec. **G0 held and approved 2026-08-19.** Written from `intent.md` in this directory, which
is the authoritative capture and is not re-derived or contradicted here.

The unit reached G0 via the backlog gate of 2026-08-19, which queued it third. That ordering is now
fixed and tightened — see Couplings: **this unit is last of the three**, behind
`cost-log-section-parse-error-on-macos-ci` and `stale-evict-lock-permanently-defeats-the-cap`.

**Read this before anything else in the file: this unit cannot raise pricing coverage.** Capturing a
resumed run yields a record and never a number (RE4, independently corroborated). It therefore does
**not** satisfy the "background pricing coverage rises materially" condition the backlog gate set for
the dropped cheaper-model routing item (cost `R3.1`/`R3.2`). This is the single expectation most
likely to be misread by someone skimming, which is why it is here, in Couplings, and as `RV8`.

## Decided at G0

Nothing below is reopened at G1 or by any slice. Each row is a decision taken, not a recommendation.

| # | Question | Decision |
|---|---|---|
| OQ-R5 | Spike first? | **Yes, and it is the unit's ordering spine.** Its only deliverable is which of three answers is true. **Nothing in group `RS` may be sliced until that answer exists.** "Does not fire" is a **success**, not a failed slice |
| OQ-R1 | Capture, or visibility only? | **Deferred to the spike's outcome, deliberately.** Both arms are written down below. Arm A (reference record) is the intended route if the matcher fires and carries the payload; Arm B (visibility only) is the standing fallback. The human did not commit to capture |
| — | What ships regardless? | **Group `RV`, and it ships first** — no hook behaviour, fully fixture-provable, and it addresses the defect that actually bit this repository (RE11) |
| OQ-R2 | Change the coverage sentence, or a separate statement? | **Append** to the existing sentence. The prefix `BG3` greps verbatim stays byte-identical — as a criterion (`RV9`), not as prose |
| OQ-R3 | Writer-side lookup or reader-side join? | **Reader-side join.** Keeps the hook off a ledger read on a path that must never delay a tool return |
| OQ-R4 | Carry the join key forward? Backfill? | **Carry `agentId` forward on finish records; no backfill.** The historical resumes stay unattachable and that is accepted |
| OQ-R6 | Does a lost run affect the coverage floor? | **No.** `LARAVEL_LOOP_COST_MIN_COVERAGE` is untouched; `RV2` does the work without adding a control |

---

## Problem

A run that a person restarted after it died is not counted as work at all. The tooling that exists
to answer "what did this unit of work cost" reports a unit where two runs happened as a unit where
one did, prints a coverage figure that says it can see everything, and says nothing about the run
whose tokens nobody can account for.

The one real occurrence in this repository's committed history shows both halves. In
`ship-gate-blind-to-ci`, an agent was killed by a machine sleep event and restarted; its figure was
attributed by hand to the original launch, and its predecessor's spend was lost. That unit's
`log.md` prints:

> `Coverage: based on 7 of 7 invocations that carry a token figure (0 unpriced, not counted) -- 100 % coverage`

and, forty lines earlier in the same committed file:

> "The tokens spent on the *failed first attempt* are reported nowhere at all, by anything."

Both sentences are in the repository, in one file, about one run. The first is the one a reader
believes. **A total that misses spend is presenting itself as complete**, which is the single thing
this repository's cost reporting says it will never do — coverage before any total, always.

Three consequences, in the order they cost something:

1. **The completeness claim is false and unqualified.** 100 % coverage is arithmetically correct over
   the invocations the ledger holds, and the ledger does not hold one of the runs that happened.
   Nothing in the output distinguishes this unit from one where nothing was lost.
2. **A run is silently folded into another run's figure.** After transcription, one
   `invocation_id` carries the tokens of the restarted run only. The record's shape says one run;
   the truth is two, one of them unpriced forever. Every per-invocation reading downstream — an
   average, a per-phase share, a rework attribution — is computed over a population that undercounts
   its own membership.
3. **A killed run is unpriceable, not merely unpriced.** The figure for a background run arrives in
   its completion notification. A run that died never sends one. No mechanism proposed here, or
   anywhere, can put a number on it. That must be stated rather than left to look like a gap
   somebody will close later.

## Users

- **The maintainer closing a unit that had a restart** — rare, five times in this repository's whole
  transcript history against ninety-eight launches (RE10). Today: transcribes the restarted run's
  figure against the original launch's id, because `docs/loop/conventions.md` tells them to and
  because `record-recovered-cost.sh` refuses the restarted run's own id (RC4). The transcription
  works. What they get back is a report claiming complete coverage of a unit they personally watched
  lose a run. What they do instead: remember it, and write it into `log.md` by hand — which is
  exactly what happened, and is why this defect is documented at all.
- **Anyone reading `/cost` or a committed `log.md` for such a unit.** Today: reads 100 % and has no
  way to reach the paragraph that contradicts it. They are the reason this is a defect and not a
  footnote.
- **Whoever decides whether the loop's unpriced share is improving.** Today they cannot tell whether
  a coverage figure is 100 % because everything was measured or because the unmeasured runs were
  never counted into the denominator. This unit makes the denominator honest and **does not raise
  coverage** — see the note at the top of this file.
- **Whoever cuts slices in `scripts/record-cost-event.sh` and `scripts/cost-ledger-lib.sh`.** Two
  concurrent units own defects in those files and both land before this one. See Couplings.

---

## What the evidence already settles

Every item carries its **provenance** and whether it is **verified** or **inferred**, because a
future reader cannot re-run the transcript analysis — session transcripts rotate, and the ones read
here will be gone.

- **`[transcripts]`** — parsed from `~/.claude/projects/*/*.jsonl` on this machine, 2026-08-19, by
  JSON-parsing each line (not line grepping). Sample: 735 transcript files, 552 `Agent`/`Task`
  launches, **24 `SendMessage` tool_use blocks of which 20 were joinable to a result**.
- **`[source]`** — read directly in this repository's committed scripts, with line numbers.
- **`[committed docs]`** — read in this repository's committed markdown.

**Sample correction, made deliberately rather than quietly.** An earlier pass on this evidence
claimed 24 joinable results. An independent re-parse joined **20**, all 20 carrying
`resumedAgentId`, and could not join the remaining 4. **The corroborated sample is 20.** The 4
unjoined blocks were **not individually inspected** and are excluded from every count below. A spec
that overstates its own sample by 20 % invites a reader to distrust the part that matters, and the
part that matters here (RE4) is unanimous across all 20.

**RE1 — What a `SendMessage` carries. `[transcripts]` verified.** Its `tool_input` keys are exactly
`{to, recipient, summary, message, content, type}`. `to` and `recipient` hold the same value, and
that value is an **agent id** (`af634d31197b4289b`), not a `toolu_…` tool-use id. There is no
`subagent_type`, no `prompt`, and no `description` — the three fields `record-cost-event.sh`
currently reads to derive agent, phase, unit, and slice (`:602-606`).

**RE2 — The resumed run's own id is unknown to the ledger. `[transcripts]` verified**, confirming
`docs/loop/conventions.md` rather than restating it. The `SendMessage` tool-use id is a fresh
`toolu_…` appearing in no ledger record, because nothing writes one for it.

**RE3 — A resume is identifiable by the presence of one key, with no prose parsing.
`[transcripts]` verified on the positive branch, 20 of 20.** Every joinable result carried
`resumedAgentId`, alongside `{success, message, pin}`. Message text came in two variants — "had no
active task; resumed from transcript…" and "was stopped (completed); resumed it…" — and **both carry
`resumedAgentId`**, so the key-presence rule covers them without reading either.

**The negative branch is NOT corroborated and the design must not depend on it.** The earlier pass
observed a second response shape with no `resumedAgentId` and the message "Message queued for
delivery to … at its next tool round" — a message to an *already-running* agent, whose tokens belong
to the invocation already in flight. The re-parse did not join those results. **Consequence, and it
is a strengthening rather than a weakening:** the rule is *record only where `resumedAgentId` is
present*, which rests entirely on the 20-of-20 positive confirmation and needs no evidence about the
negative branch at all. `RS3` keeps the negative case as a defensive criterion, and its evidence is
explicitly marked thin. This repository's own sessions contained **zero** results of the second
shape.

**RE4 — No `SendMessage` result carries a token figure. `[transcripts]` verified, 20 of 20,
independently corroborated by a second parse.** Zero occurrences of `totalTokens`, `input_tokens`,
`output_tokens`, `usage`, `totalDurationMs`, or any `cache_*` field. **Capturing a resume yields a
record, never a number.** The figure for a resumed run travels the same channel as any background
run's — the completion notification, reachable only by a human typing it in. This is the strongest
fact in the batch and it binds scope twice: this unit cannot raise coverage, and no design here may
be justified by an expectation that it will.

**RE5 — The join key exists, in a payload the hook already receives. `[transcripts]` verified.** An
`Agent`/`Task` launch's `tool_response` carries `agentId`, in the same identifier space as
`SendMessage`'s `to`: 542 of the 551 paired results (347 background-launched, 142 `completed`, 53
explicitly `run_in_background: true`). The 9 without it carry no `status` either. Note also that 347
results had `run_in_background` false or absent and still came back `async_launched`: the response's
`status` is the reliable signal, not the input flag, which is why the writer already reads the former.

**RE6 — The join key is received and discarded. `[source]` verified, independently confirmed.**
`scripts/record-cost-event.sh:661-667` reads `.tool_response.status`, `.totalDurationMs`,
`.totalTokens`, `.usage.*`, and `.model`. It never reads `.tool_response.agentId`. No ledger record
holds an agent id. Consequence, and a real cost rather than a detail: **every record written before
this unit is unjoinable**, so the resumes already in this repository's history stay unattachable
whatever ships. Only `agentId` links the two payloads; there is no second route.

**RE7 — A resume cannot say which unit it belongs to. `[transcripts]` + `[source]` verified.** The
envelope lines the ledger depends on (`Unit:`, `Slice:`) live in `tool_input.prompt`, which a
`SendMessage` has no field for; its `message` is free-form human text. Run through today's writer, a
resume would resolve `SLUG="unknown"` and no slice. A resumed run's unit is reachable **only** by
joining on the agent id to the launch record that already holds it — the same shape as the phase join
the report already performs.

**RE8 — One agent can be resumed more than once. `[transcripts]` verified.** One agent id appears
three times across the sample. Multiplicity is real, so "exactly once" cannot be keyed on the agent
id. It can be keyed on the `SendMessage` tool-use id, unique per resume — two distinct ids are two
runs; one id delivered twice is one run.

**RE9 — Killed-versus-finished is not determinable from the resume, and is determinable from the
ledger. `[transcripts]` + `[source]` verified.** RE3's two prose variants distinguish them, and
reading them is exactly the judgement the hook is not allowed to have. The same fact is already
present, structurally, in the record the ledger holds for the referenced invocation: a priced
`completed` finish means the original run ended; an `async_launched` finish with no figure means its
outcome was never observed. **The classification belongs to the reader, from ledger state, not to the
hook, from message text.**

**RE10 — Sizing, with its limits attached. `[transcripts]`, and excluding the 4 unjoined blocks.**
20 resumes confirmed across all projects against 552 launches; **5 of those in this repository's own
sessions against 98 launches** — roughly one resume per twenty launches. **These figures are evidence
for this spec and must never become a data source**, on the exact precedent by which Guild's
`agents-board.jsonl` was admitted as evidence and forbidden as an input (v0.3 CO2), and because
transcript reading was **declined permanently** on 2026-08-19. They are also incomplete: transcripts
on one machine are not the history of this repository's runs. `intent.md`'s statement stands
unqualified — **the ledger cannot size this gap**, and no acceptance criterion below depends on
knowing its size.

**RE11 — The honesty failure is committed, not hypothetical. `[committed docs]` verified.**
`docs/loop/ship-gate-blind-to-ci/log.md` prints `7 of 7 … 100 % coverage` for the run whose slicing
agent was killed and resumed, and states in the same file that the first attempt's tokens are
"reported nowhere at all, by anything." That file is the reference case this unit is measured against.

**RE12 — Whether a hook can see a `SendMessage` at all is UNKNOWN. Inferred, not verified, and
deliberately not asserted in either direction.** A `SendMessage` is an ordinary tool with a
tool_use/tool_result pair, so a matcher on it is plausible. Nothing in this repository has ever
exercised it, and `docs/loop/conventions.md` is explicit that a green harness never proves a hook is
live — a `hooks.json` change needs a plugin reinstall *and* a restart before it is in the loop.
**This is what the spike exists to answer, and it is the unit's ordering spine.**

**RE13 — Whether a resumed run's completion notification carries a token figure in the usual
`<subagent_tokens>` form is UNKNOWN. Inferred from the first-launch precedent (E2 of
`cost-ledger-blind-to-background-agents`), never observed for a resume.** If it does not, a resumed
run cannot be transcribed either, and the only truthful output is a statement that a run happened
whose cost is unavailable. No criterion below assumes it does.

---

## The route: three stages, in fixed order

This replaces the recommendation-with-a-caveat an earlier draft carried. A reader six weeks from now
should be able to take either arm without re-deriving any analysis.

```
Stage 1  RV  — visibility, unconditional          ships first, depends on no hook behaviour
                          │
Stage 2  SP  — the spike                          only deliverable: which of three answers is true
                          │
              ┌───────────┴───────────┐
        fires AND carries         anything else
        the payload              (fires without it, or does not fire)
              │                         │
Stage 3  ARM A: RS                ARM B: RB
        reference record          visibility only — RS is closed, permanently
```

**Stage 1 first, always.** `RV1`–`RV9` are fully provable from fixtures, need no live hook, and close
the defect in RE11. Ordering them first means the unit delivers value even if the spike returns the
worst answer.

**Stage 2 gates Stage 3 absolutely. No slice in group `RS` may be written, cut, or started until the
spike's answer exists.** A slice list that contains an `RS` slice before `SP` has returned is a G1
defect, not an optimisation.

**The branch condition is binary at the decision point, and the spike's deliverable is still
three-valued.** Arm A requires **both** that the matcher fires **and** that the payload carries the
target agent id (`to`/`recipient`, or `resumedAgentId` on the response). "Fires without the payload"
collapses to Arm B for a different reason than "does not fire" — `RS2`'s exact-match resolution is
unachievable without the id — and both reasons are recorded distinctly by `SP5`.

**"Does not fire" is a success.** It closes `RS` with a real answer, at the cost of one matcher, one
reinstall, one restart and one real resume. A spike that returns it has succeeded and is not retried,
worked around, or re-briefed.

---

## Acceptance criteria

Each criterion names what would check it. Groups `RV` and `SP` name no file, field, or function to
change. Every `RV` criterion is observable from a fixture ledger plus the tooling's own output, so
`tests/guardrails.test.sh` can prove it without a live session.

### RV — What may be claimed about a resumed run (unconditional, ships first)

- [ ] **RV1** The repository states plainly, where it already documents what the ledger can and
      cannot see, that a run resumed with `SendMessage` is not recorded as an invocation, that its
      tokens are in no total, and that a killed attempt's tokens are recorded nowhere by anything.
      Checked by: that statement being present in `README.md` beside the existing ledger
      documentation, in the same place and manner as the background-launch statement X5 already put
      there. Provable by grep; needs no live hook.
- [ ] **RV2** No coverage figure, per-phase figure, or unit total is described as complete, full, or
      verified anywhere in output or documentation while this gap is open. Checked by: a fixture at
      100 % priced coverage; its output asserts nothing beyond the arithmetic it can support. The
      house precedent is `docs/loop/checks.md`'s refusal to call a platform "covered, verified,
      guaranteed, or proven" — the same discipline, applied to a token total.
- [ ] **RV3** No token figure is fabricated, estimated, imputed, or apportioned for a resumed run or
      a killed attempt — not from the original launch's figure, not from a duration, not by halving
      or doubling anything, not from an average of priced invocations. Checked by: a fixture holding
      whatever this unit records for a resume; the priced total, the coverage share, and every
      per-phase and per-slice figure are byte-identical to the same fixture with that record
      removed. Extends CL7 to a new record class, and is the criterion most worth being strict
      about, because RE4 means a number here could only ever be invented.
- [ ] **RV4** A ledger with no resume information reads and reports byte-identically to today.
      Checked by: diffing the full report, the budget gate's output, and `log.md`'s cost section for
      a resume-free fixture before and after the change. (The RC6 / RD8 property, asserted per slice
      throughout this area.)
- [ ] **RV5** Every existing coverage-honesty, budget, and reporting criterion continues to hold
      unchanged, with its existing harness cases passing unmodified: CV1–CV8, BG1–BG14, PE1–PE6,
      CL1–CL9, RC1–RC7, RD1–RD11. Checked by: `bash tests/guardrails.test.sh` green at a case count
      above the current **466**, with no existing case edited.
- [ ] **RV6** A resumed run is never reported as a refine pass, and no per-pass token figure appears
      anywhere. Checked by: the existing "no per-pass token figure anywhere" assertion passing
      unmodified, plus a fixture with a resume present in which the rework count and the rework token
      share are unchanged. Per-pass granularity (cost `R1.3`) was dropped as satisfied by
      substitution on 2026-08-19; a restart is a run, not a pass, and this unit does not reopen it.
- [ ] **RV7** Nothing this unit adds can block, delay, reorder, or steer a spawn, a tool return, or a
      run — including under its own failure, a missing parser, an unresolvable reference, or a
      disabled ledger. Checked by: every new path asserted to exit 0 individually, per case rather
      than in aggregate, including with neither `jq` nor `python3` on `PATH`. (L7, RC7, X4 — settled
      on 2026-08-19 and not reopened.)
- [ ] **RV8** The finding that this unit cannot raise pricing coverage (RE4) is recorded in
      `docs/loop/decisions.md` with its date and its evidence. Checked by: that entry existing, and
      naming that capturing a resume yields no token figure, so this unit is **not** the thing that
      satisfies the "background pricing coverage rises materially" condition the backlog gate set for
      the dropped routing item. The existing routing decision is left standing and unedited.
- [ ] **RV9** The coverage sentence's existing prefix stays **byte-identical**, and any new wording is
      **appended** after it. Checked by: `grep -qF` for the existing verbatim string succeeding
      unchanged, BG3's coverage-honesty case passing unmodified, and the two consumers of that
      sentence printing identical strings and numbers for one fixture (CV7/CV8, RD10). This is
      OQ-R2's decision, and appending is how that sentence has already been extended twice — a
      coverage share and wholly-unobserved phase names, then a transcribed-figures clause.

### SP — The spike (Stage 2; gates all of `RS`)

- [ ] **SP1** The spike's **only** deliverable is which of three answers is true: the matcher fires
      and the payload carries the target agent id; it fires without it; or it does not fire. Checked
      by: its return naming exactly one of the three. It designs no record type, writes no reader
      change, and proposes no capture mechanism — a spike that returns a design has exceeded its
      brief.
- [ ] **SP2** "Does not fire" is recorded as a **success** that closes `RS` permanently. Checked by:
      that outcome being accepted without a retry, a workaround, a second matcher, or a re-brief, and
      by the unit continuing into Arm B rather than being reported blocked.
- [ ] **SP3** The answer is evidenced by **state on disk after a real run** — after the plugin
      reinstall and restart a `hooks.json` change requires — and never by the harness being green.
      Checked by: the evidence cited in the spike's return being a file's contents, per
      `docs/loop/conventions.md`.
- [ ] **SP4** The spike leaves the repository as it found it. Checked by: `git status` clean of any
      temporary matcher, and `hooks/hooks.json` containing nothing half-registered, whichever answer
      it returned.
- [ ] **SP5** The answer is recorded in `docs/loop/decisions.md` with its date and its evidence,
      whichever way it goes, and "fires without the payload" is recorded as distinct from "does not
      fire". Checked by: that entry existing and distinguishing the two.

### RS — Arm A: capturing the resumed run (only if `SP` returns *fires and carries the payload*)

**Not sliceable before `SP` returns.** Written mechanism-agnostically; each is provable from a
fixture, whatever wrote the record.

- [ ] **RS1** A resumed run is recorded as an event that **references** the original launch's
      invocation, and is counted as an invocation nowhere. Checked by: a fixture of one launch plus
      one resume; the invocation count, the priced count, the coverage share, the in-flight count,
      every per-phase figure, every per-slice row, and both rework figures are identical to the same
      fixture without the resume — the only difference in the output is the new statement. This is
      `intent.md`'s "without inventing a second invocation", made checkable.
- [ ] **RS2** The reference resolves by exact match on an identifier both payloads already carry,
      and by nothing else. Checked by: a fixture with two invocations open concurrently and a resume
      naming one of them — it attaches to the named one; and a fixture whose resume names an
      identifier no record holds — it attaches to nothing and is reported as unattached. No
      nearest-by-time, most-recently-launched, per-slug, per-phase, or only-other-invocation guess
      passes this. (The `--invocation-id` selector was rejected on 2026-08-17 on these grounds; that
      rejection is extended here, not reopened.)
- [ ] **RS3** A message delivered to an agent that was already running is not recorded as a resumed
      run. Checked by: a payload lacking the resumed-agent marker — no new record, no count moves,
      no statement printed. **Evidence note: this criterion's negative branch is the one part of the
      evidence base that is not corroborated (RE3).** It is kept as a defensive criterion precisely
      because the safe rule — record only where the marker is present — is confirmed 20 of 20 and
      needs no evidence about the negative case.
- [ ] **RS4** Two resumes of one agent are two resumed runs; one resume delivered twice is one.
      Checked by: a fixture with two distinct resume events against one agent → a count of two; the
      same event duplicated → a count of one. Exactly-once holds per resume, not per agent (RE8).
- [ ] **RS5** A resumed run's unit is taken from the invocation it references and never from its own
      payload. Checked by: a resume whose message text names a different unit — it is attributed to
      the referenced invocation's unit; and a resume referencing an unknown invocation — it is
      attributed to no unit at all, and never folded into any unit's report as `unknown` (RE7).
- [ ] **RS6** Whether the original run finished or was killed is stated only where the referenced
      invocation's own records support it, and is never read out of the resume's message text.
      Checked by: two fixtures — a referenced invocation with a priced `completed` finish, and one
      with an `async_launched` finish and no figure. The statements differ, and neither depends on
      prose (RE9).
- [ ] **RS7** A unit with no resumed run says nothing about resumed runs. Checked by: RV4's
      byte-identity, plus the absence of any resume wording in a resume-free fixture's output. Under
      this arm the appended clause is **factual and conditional**, never boilerplate carried by every
      report.
- [ ] **RS8** A resume arriving for an invocation the ledger has no record of writes nothing that
      can later be mistaken for an invocation, is not dropped silently, and errors nothing. Checked
      by: that fixture — the resume is counted as unattached and the report says so. (The RC4 shape,
      applied to a new arrival.)
- [ ] **RS9** The killed attempt is never given a figure and never presented as priceable. Checked
      by: a fixture where the referenced invocation is itself unpriced and a resume exists — the
      output names what it knows about both runs and prints no figure for either, substituting no
      zero and no dash. (CV5, L3: null means unavailable; zero means measured.)
- [ ] **RS10** A record this unit introduces is read without error by a consumer that predates it,
      and a ledger written before this unit is read without error by every consumer after it.
      Checked by: both directions, on one fixture each. No record is dropped, and no historical
      record is reclassified into a category it cannot support (CL9). Any parser change lands in
      **both** the `jq` and the `python3` program or the two disagree by construction. **This
      criterion rebases onto a `cost-ledger-lib.sh` that two earlier units will have changed** — see
      Couplings.
- [ ] **RS11** The join key is carried forward and never backfilled, and resolution happens on the
      reader's side. Checked by: `agentId` present on newly written finish records and absent from
      every pre-existing one, with no path that rewrites, mutates, or reorders an existing ledger
      line; a resume record carrying the raw identifier rather than a resolved one; and no ledger
      read inside the hook's own path. (OQ-R3 and OQ-R4's decisions, made checkable. Note the
      mechanical constraint: `agentId` arrives on `tool_response`, so it can only reach the **finish**
      record, not the start.)

### RB — Arm B: visibility only (if `SP` returns *fires without the payload* or *does not fire*)

- [ ] **RB1** The spike's negative answer is recorded in `docs/loop/decisions.md` with its date and
      its evidence, and `RS` is marked **closed, not deferred**. Checked by: that entry existing and
      saying which of the two negative answers it was. A closed item stops being a coupling other
      units carry.
- [ ] **RB2** The appended clause is worded as a **standing limitation**, not as a pending fix.
      Checked by: its text naming what is not captured and why, and containing no wording implying a
      figure is forthcoming, in progress, or recoverable later. A reader must not be left waiting for
      a number that provably cannot arrive (RE4).
- [ ] **RB3** Nothing half-built is left registered or shipped. Checked by: `hooks/hooks.json`
      unchanged from today, no new record type in either parser program, no unreferenced script, and
      every script named in `hooks.json` existing and executable (X4).

### The conditions for calling this done

Neither is a G2 criterion, for the reason `docs/loop/conventions.md` records: the harness invokes
hook scripts over stdin and can never prove a hook is registered or that a live session behaves as
expected.

- [ ] **DC-R1** *(Arm A only)* On one real run, a resume writes whatever this unit says it writes —
      proven by state on disk after that run, not by the suite being green.
- [ ] **DC-R2** On one real unit that had a resume, the coverage statement matches what a human who
      watched that run believes — recognised, not merely executed. `ship-gate-blind-to-ci`'s `log.md`
      is the reference case (RE11). **Reachable under either arm.**

`cost-measurement-v0.2`'s DC1 and `cost-reporting-v0.3`'s DC2/DC3 all remain open and are not
superseded, closed, or reported as either of these two.

---

## Non-goals

**Read these out loud at G0.** Each is something a reasonable slice could drift into from here.

**Because the evidence forbids it:**

- **No token figure for a resumed run or a killed attempt, from any source.** Not estimated,
  imputed, extrapolated, scaled, averaged, split, or inherited from the original launch. RE4 settles
  that this unit has no number to record; RV3 and RS9 make the absence checkable.
- **Coverage does not rise from this unit, and no slice may be justified by an expectation that it
  will.** Anything presented as progress toward the backlog gate's "background pricing coverage
  rises materially" condition is out of bounds.
- **No transcript reading, scraping, prototyping, or re-opening of that question.** Declined
  **permanently** on 2026-08-19. The transcript figures in this spec's evidence section are evidence
  and must never become a data source (RE10).
- **No `SubagentStop` registration.** Closed by measurement (E3) and unchanged.
- **No reading of Guild's `.claude/agents-board.jsonl`,** as an input or as a cross-check.

**Because it is settled and is not being reopened:**

- **No second invocation.** A resume never enters the invocation count, the priced count, the
  coverage denominator, the in-flight count, the per-slice rows, or either rework figure (RS1).
- **No per-pass granularity.** Cost `R1.3` stays dropped; whole-invocation attribution stays
  deliberate; the harness's "no per-pass token figure anywhere" assertion stays unedited (RV6).
- **No automatic transcription.** `S11` was **cancelled** on 2026-08-19, partly because the
  deliberately human-typed CLI keeps a transcribed figure honestly labelled — automation removes the
  person who vouches for each figure. Nothing here auto-writes a figure, prompts for one, or wires
  `record-recovered-cost.sh` into any spawn or hook path. `RC7` is binding.
- **No change to the `recovered` record's pinned shape,** to `record-recovered-cost.sh`'s RC4
  refusal, to the observed-beats-transcribed precedence (RC3/S8), or to what counts as priced.
  Transcribing a resumed run's figure against the original launch's id already works and is what
  `conventions.md` instructs; this unit does not replace, automate, or forbid it.
- **No threshold, default, or suggested value ships anywhere** — not for the coverage floor
  (`LARAVEL_LOOP_COST_MIN_COVERAGE`, untouched per OQ-R6), not for either budget field, not for the
  four per-phase fields, not commented out, not as a starting point. All five stay unset. The
  existing 30 % concentration threshold is neither raised, lowered, nor made configurable.
- **No new selector, and no `--agent-id` flag on any CLI.** RS2's exact-match rule is not a licence
  to add a way for a human to nominate which invocation a figure belongs to.
- **`/loop`'s concurrency is not changed.** Launching foreground to avoid resumes is not on the
  table; that trade was already kept out of bounds as OQ4 of the background-agents unit.
- **No backfill and no rewriting of existing ledger lines** (RS11). `.claude/loop-cost.jsonl` is
  gitignored local state and is not hand-edited to make output look right. The historical resumes
  stay unattachable, and that is accepted rather than engineered around.
- **No writer-side ledger lookup** inside the hook path (OQ-R3).

**Because another unit owns it:**

- **The eviction-cap defect in `scripts/record-cost-event.sh` is out of bounds.**
  `stale-evict-lock-permanently-defeats-the-cap` owns it and lands first.
- **The parser fix in `scripts/cost-ledger-lib.sh` is out of bounds.**
  `cost-log-section-parse-error-on-macos-ci`'s scope grew at its own G0 to include that
  neighbourhood, and it lands first. `RS10` rebases onto its result.
- **No fix for the other known report gaps**: cache-read share `unavailable` on transcribed records,
  and elapsed wall-clock. Neither is this defect and neither is silently absorbed.

**Never, per §8 of the requirements document:**

- **No pricing in currency.** Tokens, counts, and durations only.
- **No SaaS, dashboard, network call, account, or export.** Local files only.
- **No control.** A resume triggers no gate, no block, no warning that stops anything, and no
  cost-based degradation. Nothing terminates a run.
- **No new agent.** The team is four. **No fourth `ship-check` gate.**

---

## Failure modes

| When | Expected behaviour |
|---|---|
| A run is resumed and its figure is never transcribed | The unit's output does not claim complete coverage; what is unaccounted for is stated, and no figure is invented (RV2, RV3) |
| A run is resumed and its figure *is* transcribed against the original launch's id | Today's behaviour for that figure is unchanged; the output additionally states that a second run's spend sits inside that one figure and that the killed attempt's does not (RV1, RS6) |
| A killed attempt's tokens are asked for | Refused, and named as unavailable rather than pending. No path produces a number for it (RV3, RS9, RB2) |
| A message is delivered to an agent that is still running | Not a resumed run. Nothing recorded, nothing counted, nothing said (RS3) |
| One agent is resumed twice | Two resumed runs (RS4) |
| One resume event is delivered to the hook twice | One resumed run (RS4) |
| A resume names an invocation the ledger has no record of | Counted as unattached, reported as unattached, attributed to no unit, nothing fabricated, nothing errors (RS2, RS8) |
| A resume names an invocation whose records carry no slice | No slice invented; the resume is reported against the invocation and no per-slice row moves (RS1, RD5's rule) |
| The referenced invocation's own records cannot say whether it finished | The output says only what those records support, and never reads the resume's message text (RS6) |
| A resume happens for a unit whose ledger predates this unit | Unattachable, said so, not guessed at, and no historical record rewritten (RE6, RS11) |
| **The spike finds the matcher does not fire** | **A success. `RS` is closed permanently, Arm B ships, nothing is retried or worked around, and the answer is recorded (SP2, RB1)** |
| **The spike finds it fires but without the target id** | Arm B ships, for a distinct recorded reason: exact-match resolution is unachievable (SP5, RB1) |
| An `RS` slice is proposed before the spike has returned | Out of bounds. A G1 defect to record, not a chore to resolve |
| No resume happens on a run | Indistinguishable from today: no error, no warning, no incomplete state, no claim that anything is pending, byte-identical output (RV4, RS7) |
| A resume's own recording path errors internally | Exits 0, writes nothing corrupt, leaves no permanent block or stale marker, and the run is unaffected (RV7) |
| Neither `jq` nor `python3` is on `PATH` | Today's message, exit 0, no partial figure and no partial statement (RV7) |
| The ledger is disabled via `LARAVEL_LOOP_COST_LEDGER=0` | Nothing is written for a resume either. The disable switch remains total |
| The ledger is at its line cap when a resume arrives | The cap is honoured by the existing mechanism, unchanged by this unit — see Couplings |
| The same ledger is read twice | Identical output and identical verdict. CV7 unchanged |
| A commit is prepared after a run | No ledger and nothing new under `.claude/` in the diff |

---

## Constraints

**Settled inputs, not decisions to revisit at slice time.** Reopening any is a new intent.

- **From `cost-measurement-v0.2`:** D1–D5, L1–L11 — in particular **L3** (null means unavailable,
  zero means measured), **L7** (never block; upheld and recorded as settled on 2026-08-19), **L9**
  (exactly once), **L11** (a derived value declares itself derived), and the ledger's location,
  shape, line cap, and `LARAVEL_LOOP_COST_LEDGER=0` switch.
- **From `cost-reporting-v0.3`:** G0-D1 (no threshold default anywhere), G0-D2, CV1–CV8, BG1–BG14,
  PE1–PE6, CO1–CO13, DL1–DL7. **CV1** — coverage before any total — is the criterion this unit
  exists to restore, not to amend.
- **From `cost-ledger-blind-to-background-agents`:** CL1–CL9, RC1–RC7, X1–X6, and its existing
  unpriced-reason vocabulary (`unpriced_backgrounded`, `unpriced_no_usage`, `unpriced_truncated`,
  `unpriced_unstated`) — a new statement extends that vocabulary's discipline rather than replacing
  it.
- **From `recovered-figure-drops-slice-and-model`:** RD1–RD11, and its `OQ5` answer that a
  transcribed figure stays permanently distinguishable from an observed one.
- **From `docs/loop/decisions.md`, 2026-08-19:** routing is dropped and not reopened; per-pass
  granularity is dropped; `S11` is cancelled; transcript scraping is declined permanently; all five
  threshold variables stay unset; `ship-check` stays at exactly three gates; and any future target
  must name the figure that computes it and where that figure comes from.
- **From `docs/loop/conventions.md`:** a resumed invocation is a different invocation to the ledger,
  and its figure is attributed to the original launch's id — this unit does not contradict that
  instruction; a green harness never proves a hook is live; a `hooks.json` change needs a plugin
  reinstall *and* a restart; an agent killed mid-response may have written nothing.

**Existing behaviour that must not change:**

- The ledger writer observes and never steers — no blocking, delaying, reordering, or altering
  anything, including under its own failure.
- The append-only JSONL ledger. Nothing rewrites, mutates, or reorders an existing line. A second
  record reusing `event:"finish"` for one invocation is already argued against in the RC group's
  pinned-contracts table, on the ground that last-wins token assignment could silently overwrite an
  observed figure — that argument stands and is why OQ-R1's "extend the existing record" option was
  never viable.
- The coverage sentence's existing prefix, byte-identical (RV9).
- All three existing guards: exit codes, `LARAVEL_LOOP_REFINE_CAP` /
  `LARAVEL_LOOP_ALLOW_UNTESTED` / `LARAVEL_LOOP_ALLOW_FULL_SUITE` handling, subagent-only scoping,
  and never blocking a human on the main thread.
- `hooks/hooks.json`'s existing entries, every one of which a current script depends on. The spike
  may add a matcher temporarily and must leave none behind (SP4).
- The four-agent team, and README's and CHANGELOG's claim that it is four.
- The protocol's ≤10-line return shape.
- Standalone from Laravel Guild: separate agents, skills, env vars, state files.

**Repo conventions and hard limits:**

- Zero-dependency bash plus coreutils, degrading `jq` → `python3` → a safe no-op. Clean under
  `shellcheck -S warning scripts/*.sh`; script modes per `scripts/check-script-modes.sh`; covered by
  `tests/guardrails.test.sh`, currently **466 cases, all green**. CI runs exactly these on
  `ubuntu-latest` and `macos-latest` with identical invocations, so both totals must match.
- A harness case count added here must be reflected in README — one existing case asserts that
  README's stated count equals the harness's actual total.
- Any change to `scripts/cost-ledger-lib.sh` lands in **both** parser programs, `jq` and `python3`,
  or they disagree by construction. That file is the most dangerous in this area for that reason.
- Every script named in `hooks/hooks.json` exists and is executable; hook scripts carry a header
  comment explaining *why* they are wired to the event they are wired to.
- Nothing leaves the machine. A budget is denominated in tokens, never money. Report and threshold
  arithmetic stay deterministic. G4 is not crossed.

---

## Couplings — build order, now fixed

**This unit is last of the three approved units.** Both of the others land first, and both change
files this unit's Arm A would touch.

1. **`cost-log-section-parse-error-on-macos-ci` — first.** Newest and least understood fault, and its
   scope **grew at its own G0** to include a fix in the `cost-ledger-lib.sh` parser neighbourhood.
   **Consequence for this unit: `RS10` will rebase onto a changed library**, in both parser programs.
   Whoever cuts Arm A reads that unit's landed diff before writing a slice, not after.
2. **`stale-evict-lock-permanently-defeats-the-cap` — second.** Same file as this unit's writer half,
   `scripts/record-cost-event.sh`. Two interactions are real: any new record type consumes ledger
   lines against the very cap that unit repairs — **more records means more pressure on a mechanism
   currently known to be defeated** — and the arrival-trim path is the writer's most frequent code
   path, sitting immediately above the `Agent|Task` gate a new matcher would extend. This ordering
   was recommended by this spec at G0 and **accepted**: Arm A adds records to a working cap rather
   than a broken one.
3. **This unit — third**, and internally ordered `RV` → `SP` → (`RS` | `RB`).

Other couplings, named and not decided:

- **The dropped routing item (`R3.1`/`R3.2`).** Its revisit condition is that background pricing
  coverage rises materially. **RE4 establishes that this unit does not raise it.** Named here, at the
  top of this file, and as `RV8`, so nobody reads this unit's completion as satisfying that
  condition. This unit neither reopens nor advances that decision.
- **`record-recovered-cost.sh`'s RC4 refusal.** Today it correctly refuses a resumed run's own id,
  which is what forces attribution to the original launch. This unit does not relax that refusal;
  whether a resume record should ever become an addressable target for transcription is deliberately
  **not** asked here, because RE4 means there would still be no figure to attach without a human
  typing it, and `S11` is cancelled.
- **`docs/loop/transcript-scraping-as-a-recovery-path/` is declined permanently.** This spec's
  evidence came from transcripts, which makes the boundary worth restating: reading them by hand to
  write a spec is not the same act as a plugin reading them at runtime. The decline stands untouched.

---

## Open questions

**All seven questions raised at G0 are decided** — see *Decided at G0*. `OQ-R1` is not open in the
sense of awaiting a human: it is **branch-resolved by `SP`'s outcome**, with both arms specified
above. What follows is the residue: things genuinely not known, each with what it would cost to be
wrong.

- **RU1 — The negative branch of RE3 is uncorroborated.** An earlier parse observed a
  queued-delivery response shape; a re-parse could not join those four blocks, and they were not
  individually inspected. **Cost of being wrong: low, by design.** The rule is *record only where the
  resumed-agent marker is present*, confirmed 20 of 20 on the positive branch and needing no evidence
  about the negative one. `RS3` keeps the defensive criterion and marks its own evidence thin. If the
  queued shape turns out not to exist, `RS3` is trivially satisfied; if it exists in a form not yet
  seen, `RS3` is what catches it.
- **RU2 — Whether a resumed run's completion notification carries a token figure (RE13).** Unknown,
  inferred only from the first-launch precedent. Bears on whether a resumed run can be transcribed at
  all. **Cost of being wrong: none for `RV`, and none for the arms** — no criterion assumes it, and
  RE4 already establishes that no *hook* will ever see the figure. Worth checking opportunistically
  the next time a real resume happens, not worth a slice.
- **RU3 — Under Arm A, how a partly-attributable unit words its appended clause.** A unit with one
  attached and one unattached resume has two facts to state in one sentence that must not grow into a
  paragraph. `RS7`, `RS8`, and `RV9` constrain it from three directions but do not fix the wording.
  **Recommended: settle it at G1 against a real fixture rather than in prose here**, because the
  wording is only checkable once the fixture exists. Named so it is not discovered at G2.
