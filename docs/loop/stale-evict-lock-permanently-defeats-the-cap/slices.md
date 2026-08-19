# Slices — stale-evict-lock-permanently-defeats-the-cap

Cuts `spec.md` (G0 held 2026-08-19, committed `dea7408`, criteria `SL1`–`SL13`) into **nine slices**:
two that write down what is true today, one behaviour slice that stops catchable kills orphaning the
lock, one read-only evidence spike that the relocation's whole premise rests on, three that relocate
the lock and make its location checkable and discoverable, one measurement, one closing record.

**9 slices · 3 genuinely parallel at t0 (S1 ∥ S2 ∥ S4) · critical path S1 → S3 → S5 → S6 → S7 → S8 → S9
· group case-count delta +16 (deltas only — two neighbour units are moving the literal)**

**One evidence gate inside the order, and it is not a re-slice.** `S5`–`S7` are fully cut below —
nothing about relocation is deferred in design terms — but they are **held until `S4` returns**,
because `SL11` says outright that absent observed evidence of the base's per-boot property *"the
bounded-by-uptime claim in the Problem section is not made anywhere"*. Building the relocation before
that observation exists would be building against an unestablished premise, using the spec's own
words as the licence. `S4` is licensed to return `needs-decision`, and if it does, `S5`–`S7` go back
to the human before a builder is briefed. This is not the deferral G0 overruled: `OQ6` stays **in this
unit**, with its envelopes written.

The G0 decisions this cut is written against, restated so no slice re-derives or reopens one:

| Question | G0 decision (not reopened by any slice here) |
|---|---|
| **OQ1** — can a lock be declared stale? | **No, and no steal, ever.** No pid, no `kill -0`, no age inference by this project's own code, nothing written **inside** the lock directory (§0). |
| **OQ2** — is `record-recovered-cost.sh` in scope? | **In.** Both writers change. Anything touching the derivation touches **both files in the same commit**. |
| **OQ3** — one shared primitive or two parallel edits? | **Two parallel edits, one *checked* derivation.** No `source` on the hook path, no `append_and_evict()` moved into `cost-ledger-lib.sh`. Agreement is asserted by a case (`S7`), never promised by a comment. |
| **OQ4** — where does a human repair route live? | **Documentation plus `SL3`'s report.** No new command; `/cost` stays read-only. |
| **OQ5** — a ledger record for an orphaned lock? | **No new record type.** Surface it where a human already looks; bound the repeat reporting. **Settled at this gate — see *`SL3`'s reporting shape, settled here*.** |
| **OQ6** — relocate the lock? | **In this unit.** `SL11`–`SL13` are what it added; `S4`–`S7` are what it costs. |
| **OQ7** — ship the catchable-signal hygiene? | **Yes**, and it is **not** made redundant by relocation (§4(f)). `S3`. |
| **`L7`** | **Settled, not merely unexamined.** No slice makes an appending invocation wait, poll twice, retry, or fail because of the lock. Cases (g) and (i) keep their assertions unedited. |

---

## The seam

**`S1` — write the orphaned-holder case, and this unit's honest limit, into the mechanism's own
header.** It is the smallest change that leaves a reader better off, it lands with or without
everything after it, and it is the one thing `spec.md` puts deliberately first: `SL1` and `SL2` are
*"satisfiable under every answer, including 'nothing changes in the code'"*. If this unit stalled at
`S4`'s evidence and nothing else ever shipped, `S1` + `S2` would still be the honest minimum the spec
calls *"the cheapest honest option"* — and that is exactly why they go first rather than last.

It is documentation, and the ordering is chosen so that it is never documentation ahead of code:
**`S1` states only what is true of today's scripts.** An interrupted holder leaves the lock behind,
the cap is not enforced again for that lock's lifetime, and a human can remove the directory. `S3`
then amends that block to say catchable kills are released; `S5` amends it again for the location;
`S6` for the report. No slice ever leaves either header describing behaviour its script does not have.

The alternative opening — relocate first, document afterwards — was considered and refused for the
reason `SL1` exists: it would put the biggest behaviour change in the repository's riskiest shared
primitive in a commit where nothing anywhere says what the mechanism actually promises when its lock
is orphaned.

---

## `SL3`'s reporting shape, settled here

`spec.md` records this as *"unresolved in shape, decided in principle"*. It is settleable at G1 and
so it is settled, because leaving it open would put the choice in a builder's envelope where `OQ5`'s
two refusals (no new record type; nothing that can itself be orphaned) are one convenience away from
being violated.

**The route is `scripts/cost-report.sh` — `/cost` — and nothing else.** `S6` owns it.

Why this settles both halves of the question:

- **Where a human already looks.** `/cost` is the repository's only human-facing reader of this
  ledger, and `spec.md`'s own candidate table names it: *"`/cost` is read-only by charter — it can
  report, not repair"*.
- **Repeat reporting is bounded structurally, with nothing minted.** The flooding risk `OQ5` names is
  *"one orphaned lock flagging on every invocation for its lifetime"* — an invocation-frequency
  problem. `/cost` is human-invoked, so the report fires once per human read and **zero times per
  hook invocation**. No one-shot marker is needed, and none is permitted: a marker would be another
  orphanable `mkdir` directory with the same failure mode this unit exists to reduce. No new record
  type, per `OQ5`.
- **It cannot touch `L7`.** Nothing is added to any hook path; no appending invocation gains output,
  a read, or a branch on the lock's presence beyond the `mkdir` it already attempts.

**What a builder may not do, whichever wording it lands on:** no output from `record-cost-event.sh` or
`record-recovered-cost.sh` on any path; no new ledger record type; no marker file or directory to
remember "already reported"; no removal, release, or repair of the lock from the reader (`/cost` is
read-only by charter); no sentence that determines the holder is dead, stale, crashed, or gone — the
report states the lock is present, what its presence means for the cap, that a live trim and an orphan
are **indistinguishable from there**, and what a human may do when no run is active.

**One thing deliberately *not* settled, and it is a question for the human, not the builder** — see
*Open questions* below: whether the block should be gated on the ledger being **over** cap, which
`spec.md`'s failure-mode table hints at (*"under cap … nothing worth alarming anyone about"*). `S6` is
pinned **not** to gate it, because gating needs the cap's value inside the reader — a fourth copy of
the `LARAVEL_LOOP_COST_MAX_LINES` parser, in a file whose own charter says every figure comes from
`cost-ledger-lib.sh`. Informational wording instead of an alarm is what carries the under-cap case.

---

## The reboot-property evidence is its own slice (`S4`), and here is why

It could have been a step inside `S5`. It is not, for three reasons, in ascending order of weight:

1. **It is read-only and produces no diff in `scripts/` or `tests/`.** Folding it into the relocation
   slice would put an evidence-gathering task inside the one commit that changes the repository's
   shared mutual-exclusion primitive.
2. **Its honest answer may be `unknown` or `no`, and that answer must survive.** `spec.md` names this
   as an open question *"in either direction"*. A builder holding both the evidence and the
   implementation has every incentive to read the evidence as licensing the implementation it is
   halfway through — the fused-narrative failure this repository has already had to slice around once
   (`eviction-cap-not-honoured-under-contention`, `S2`/`S3`).
3. **It can invalidate `S5`'s premise, so it must be readable before `S5` is briefed.** This is
   decisive. If neither candidate base has a boot-clearing property, relocation buys only `SL11`(c)'s
   age-reaping concession — the spec's own *"weakest joint"* — and `SL11` then forbids the
   bounded-by-uptime claim outright. That is a human's call at a gate, not a builder's on a refine
   pass.

**One observation already made at this gate, on one host, one sample — evidence for the shape of the
question and explicitly NOT a substitute for `S4`'s work.** On the maintainer's host
(macOS/arm64/bash 3.2.57), `df` and `ls -ld` report:

```
$TMPDIR   = /var/folders/65/.../T/    drwx------  developer:staff   → /dev/disk3s5 (APFS data volume)
/tmp      → /private/tmp              drwxrwxrwt  root:wheel        → /dev/disk3s5 (APFS data volume)
```

Both candidate bases are **disk-backed on the same volume** — neither is memory-backed, so on this
platform "cleared by a reboot" is not a property of the filesystem and would have to come from
something that runs at boot. And §4(d)'s squatting surface is **not Linux-only**: `/private/tmp` here
is world-writable and sticky, exactly as the spec describes for the Linux `/tmp` fallback.

`S4` must reproduce this rather than inherit it, on both platforms, and say what clears each base and
on what schedule. It is named here because the human should see at this gate that the unit's
bounded-by-uptime premise is in genuine doubt on the maintainer's own platform.

**The half no builder can reach, named rather than left to be discovered:** a *real reboot* of the
maintainer's host is the human's action, and a reboot of a CI runner is obtainable by nobody — a
runner is a fresh VM per run, which is not the same observation as "the base was cleared". `S4`
therefore lands its evidence in two labelled classes (observed-here / not-obtainable-by-a-builder) and
leaves a named marker in each base so the human's post-reboot look is one `ls`. This is `SL11`'s
weakest coverage and it is called out again under *Open questions*.

---

## Order and concurrency

```
t0 ├── S1  say what an orphaned holder does to the cap, today          ← the seam
   │        script headers ×2, +2 cases
   │    └─→ S3  release the lock on a catchable signal, both writers
   │             (textual: same header block, same literal; semantic: S3 amends S1's sentence)
   │             scripts ×2, +3 cases
   │              │
   ├── S2  answer the staleness question on the record (decisions.md)   │
   │                                                                    │
   └── S4  establish what the base does with a lock across a reboot     │
            and across time — read-only, markdown, BOTH platforms       │
             │                                                          │
             └────── EVIDENCE GATE: S4's answer is read before S5 is briefed
                          │
                          └─→ S5  relocate: one derivation per writer, degrading to
                              │    today's path when the base is unsafe   ← riskiest
                              │    scripts ×2, harness sweep, +5 cases
                              └─→ S6  report a present lock in /cost (the third deriver)
                                  └─→ S7  make a divergence between the derivations red
                                      └─→ S8  measure the appending path, before/after
                                          └─→ S9  record it (decisions.md, after S2)
```

- **Genuinely parallel at t0: `S1`, `S2`, `S4`.** Three distinct surfaces — script headers + harness,
  `decisions.md` alone, one new markdown file. Zero shared files between them.
- **`S3` depends on `S1`** textually (both edit the same eviction header block, and both add cases, so
  both move `README.md`'s case-count literal) **and semantically** (`S3` amends the sentence `S1`
  writes). Not a layer habit: if `S3` landed first, one commit would exist in which the code releases
  on `TERM` while nothing anywhere states what an orphan does to the cap.
- **`S5` depends on `S3` and on `S4`.** On `S3` textually and semantically — both change the
  `mkdir`/`rmdir` region of both writers, and the trap's ownership flag is what makes the relocated
  path's release provably its own. On `S4` for the premise, per the evidence gate above.
- **`S6` depends on `S5`.** A reader that derived the pre-change path would confidently report the
  wrong directory. There is nothing correct for it to derive until `S5` lands.
- **`S7` depends on `S6`, not on `S5`.** Cutting the divergence guard before the reader exists would
  freeze a two-deriver list and leave the third deriver free to diverge silently — the exact failure
  `SL12` is for.
- **`S8` depends on `S6`** (the last slice that changes code) and **`S9` on `S8`** (its entry carries
  `S8`'s number) **and on `S2`** (it appends beneath `S2`'s entry, never rewriting it).
- **Two `decisions.md` touches in one unit, deliberately.** `S2` early carries what G0 already
  decided — the answer that stops the staleness question being asked a fifth time, and which stands
  even if the unit halts at `S4`. `S9` appends what only the build can know. They share an insertion
  point, so they are ordered, and `S9` appends rather than rewrites.

---

## Case-count deltas — pinned as DELTAS, never as absolutes

⚠ **`README.md:169` reads `466 cases` at this gate, and it will not stay there.**
`cost-log-section-parse-error-on-macos-ci` and `resumed-invocation-never-reaches-the-ledger` are both
being sliced concurrently and both add cases. Any absolute written here would be wrong the moment a
neighbour merges, turning the harness's own last case red on a diff this lane never touched.

| Slice | Delta | What produces it |
|---|---|---|
| **S1** | **+2** | one conjoined flattened-header case over both writers; one claim-word guard |
| **S2** | **0** | `decisions.md` only — checked by a read, deliberately not by a grep case |
| **S3** | **+3** | hook writer killed on `TERM` mid-trim; recovered CLI killed on `INT`; a non-holder's handler releases nothing |
| **S4** | **0** | markdown only |
| **S5** | **+5** | relocated happy path with mutual exclusion at the new path; three degradation arms; the old-path lock's inertness |
| **S6** | **+3** | lock present → reported; absent → no false alarm; the reader repairs nothing |
| **S7** | **+3** | the derivations agree (usable base); they agree (degraded); different ledgers never collide |
| **S8** | **0** | markdown only |
| **S9** | **0** | markdown only |
| **group** | **+16** | |

**Build-time computation rule, binding on every lane:**

1. Merge local `main` in first (`docs/loop/conventions.md`, *Confirm a lane's base*).
2. Read the live literal from `main`, never from this document:
   `sed -n '/^## Development/,/^## /p' README.md | grep -oE '[0-9]+ cases'`.
3. Write `that number + this slice's delta` back into that same line. Nothing else in `README.md`
   changes — **`README.md` prose is out of bounds for every slice in this unit.**
4. The arbiter is the harness's own **last** case, `docs (case count)`, whose `PASS + FAIL + 1` must
   equal the new literal. Green there is the proof; this table is a forecast.
5. **New cases go before that last case**, which stays last in the file.
6. A lane whose **honest delta differs** states the real delta in its return and computes the literal
   from it. The table is not a licence to write the wrong number.

---

## Pinned contracts

Decided here because discovering any of them at build time costs a rewrite. A builder that believes
one is wrong returns `needs-decision` rather than changing it.

| Contract | Value | Why it is pinned |
|---|---|---|
| **Nothing inside the lock directory. Ever.** | No pid, timestamp, marker, heartbeat, or note is written inside `$EVICT_LOCK`, by any slice, on any path | §0: release is `rmdir` at `record-cost-event.sh:311`, `:330`, `record-recovered-cost.sh:244`, and `rmdir` fails on a non-empty directory. One write there converts a leak that needs a kill into a leak on **every** invocation |
| **No steal, by any route** | No pid, no `kill -0`, no age comparison, no `stat`, no "it has been there a while". A signal handler releases **only** a lock the same process created. The reader reports and never removes | `OQ1`, `SL5`. Staleness is not provable with what this repository has, and the unsafe direction costs records that have no automatic recovery |
| **The derivation is marker-delimited in each file that needs it** | Each deriver wraps its derivation between two fixed marker comments — `# >>> evict lock derivation (SL12)` / `# <<< evict lock derivation (SL12)` — containing **only** assignments computable from `ROOT`/`DIR`, with no side effects beyond creating the parent directory. Derivers, pinned as an exhaustive list: `scripts/record-cost-event.sh`, `scripts/record-recovered-cost.sh`, and (from `S6`) `scripts/cost-report.sh` | This is what makes `SL12` mechanically checkable rather than aspirational: `S7`'s case extracts each block and evaluates it under identical inputs, so a hard-coded expected path is not even the easy option. It also keeps `OQ3` intact — no `source` on the hook path, no shared function, agreement asserted by a case |
| **The hook writer still sources nothing** | `scripts/record-cost-event.sh` gains no `source`, no `.`, no library read, no `command -v` on a new tool that the lock's existence depends on | Spec *Constraints*: a refusal is acceptable for a human CLI and never on the hook path, where the degraded state is running without a lock |
| **Base candidate and portable digest** | Base is `${TMPDIR:-/tmp}`. The per-checkout name is derived from the **ledger's own resolved absolute path** using `cksum` (POSIX, present on both guarding platforms). **Never** `sha256sum`, `shasum`, `md5`, or `md5sum` — the spelling differs across the two guarding platforms, the same trap the spec already records for `stat`'s flags | A portability difference discovered on a pushed macOS run costs a red run whose cause reads as the platform rather than the choice |
| **The safety predicate — this is `SL13`, expressed as the derivation itself** | Use the relocated path only when: the base exists, is a directory, and is writable (`-d`, `-w`); **and** the per-uid parent inside it (`mkdir -m 700`) is, after creation, a directory (`-d`), not a symlink (`! -L`), owned by the current uid (`-O`), and writable (`-w`). Any check failing → the lock is `$DIR/loop-cost-evict.lock`, **today's path**. Never no lock, on any branch | §4(d) and (e). The fallback is not a separate feature bolted on afterwards — it is a clause of the one rule, which is why it cannot be a separate slice (see *How `SL12` and `SL13` are cut apart*) |
| **Degradation arms that must be constructible without root** | Required arms: base absent; base present but a **regular file**; per-uid parent name pre-occupied by a **regular file** and by a **symlink**. The `chmod 000` arm is **explicitly not required** — a suite run as root would defeat it, and no case here may depend on the runner's uid | `-d`/`! -L`/`-O` are all falsifiable without a second uid or `sudo`; a permission-bit arm is not |
| **The true second-uid squat is argued, not observed** | A directory owned by **another user** is not constructible in this suite. The case set covers its observable proxy (a name occupied by something that fails `-d`/`! -L`/`-O`), and the residual is argued from the same predicate and **recorded as a limit** in `S5`'s return and in `S9` | Better a named gap than a case that quietly proves something narrower than it claims |
| **The TOCTOU stays open, deliberately** | Between the predicate and the `mkdir` of the lock, another party could replace the parent. **No slice closes this**, and none may reach for a pid, an age, a retry loop, a rename dance, or a second check to do so. A builder that believes it must be closed returns `needs-decision` | `spec.md` names it and deliberately does not specify it away. Closing it with an inference is the steal `OQ1` forbids, arriving as a bug fix |
| **Every case that exercises the relocated path sets its own throwaway `TMPDIR`** | No case may create a lock in the real temp base. `TMPDIR` is set per case to a `mktemp -d` under the case's own control and removed afterwards | Two reasons: the suite must not collide with a concurrent real run's lock on the same machine, and it must not leave state in the maintainer's temp base that a later trial reads as evidence |
| **`TMPDIR` is not a new configurable** | Reading `${TMPDIR:-/tmp}` introduces no threshold, default, or suggested value, and **no `LARAVEL_LOOP_*` variable is added by this unit** — in particular no opt-out for relocation and no interval | `SL7`. Evidence it by grepping your own diff for `LARAVEL_LOOP_` and for new numeric literals, and reporting the result |
| **The four claim-words** | No sentence anywhere in this repository describes this leak as **fixed**, **closed**, **resolved**, or **prevented**. Strongest phrasing permitted: *"permanence bounded by uptime, and a silence ended"* — and even that only once `S4`'s evidence supports it. Before `S4` returns, the honest phrasing is *"not enforced again until the lock is removed"* | `SL1`. `S1` ships the guard case; every later slice keeps it green |
| **`L7` and the arrival trim are untouched** | Cases (g) and (i) keep their assertions unedited and green. No appending path and no arrival path gains a wait, a second poll, a retry, or work whose duration depends on another process. `converge_ledger()`'s `while :;` shape and its break set are unchanged; no attempt bound, iteration counter, or no-progress guard | Settled `2026-08-19`; foreclosed twice. Questioning `L7` is its own unit at G0 |
| **Both writers move together** | Any commit that changes the derivation changes **both** `scripts/record-cost-event.sh` and `scripts/record-recovered-cost.sh`. A partial relocation is a correctness regression, not an incomplete improvement | §4(e): two writers guarding one ledger through two paths have **no mutual exclusion at all** |
| **Only the lock moves** | `.claude/loop-cost.jsonl`, `loop-cost-finished/`, `_recovered/`, `_rework/{open,pending,counts}`, and the `.evict.` temp file (which must stay on the ledger's own filesystem for `mv` to be atomic) all keep their locations. No slice adds trap release for any of those markers | Non-goals. Their own orphan questions are separate intents |
| **Red before green, per behaviour slice** | `S3`, `S5`, `S6`, `S7` each reproduce their **own** red: obtain the pre-change script read-only with `git show <rev>:path` into a temp file — never `checkout`, `branch`, `stash`, or `reset` — and record **5 trials against each version, both shas, in the return**. Citing another slice's red is not a substitute | `SL4`, and §3: red-before is cheap here, so a construction that cannot be made red locally is a failure of the criterion, not an excuse |
| **Counts, never rates** | Every figure is `N/M`. One trial is one sample; one green CI run is one sample | `SL10` |
| **The repository's own `.claude/` is never written to** | Every trial and measurement runs under a throwaway `CLAUDE_PROJECT_DIR` **and** a throwaway `TMPDIR` | The real ledger is other units' recorded evidence |
| **Nobody pushes** | No lane pushes, dispatches, re-runs, cancels, or tags. `SL10`'s two-platform run is the human's, after the group merges | A builder cannot produce evidence about the guarding platforms |
| **Out of bounds for every slice** | `hooks/hooks.json`, `scripts/ship-check.sh`, `scripts/cost-ledger-lib.sh`, `scripts/write-cost-log-section.sh`, `scripts/check-budget-gate.sh`, `.github/`, `docs/loop/checks.md`, `README.md` prose, `spec.md`, and every other `docs/loop/<unit>/` directory | Nothing new runs, so the checks map stays true without being edited; `cost-ledger-lib.sh` and `write-cost-log-section.sh` belong to a concurrently-sliced neighbour |

---

## How `SL12` and `SL13` are cut apart

`spec.md`'s author flagged these as *"the two cuts most likely to be got wrong if they are bundled"*.
They are cut apart — but not where a first reading suggests, and the reason is worth stating because
the obvious split ships a defect on purpose.

**What cannot be separated: `SL12`'s derivation and `SL13`'s fallback are one rule.** The safety
predicate is a *clause of the derivation*, not a feature beside it. Cut them into "relocate" then
"degrade" and there is one merged commit in which a stranger with write access to a world-writable
base can pre-create the lock name and permanently defeat the cap — §4(d)'s new door, the very fault
this unit exists to reduce, shipped deliberately and unclearable by the owner. Cut them the other way
and there is nothing to degrade from. So `S5` carries the derivation **and** its predicate **and** all
of `SL13`'s cases, and `SL13` is protected from being got wrong inside that slice by three things
decided here rather than by the builder: the predicate is **pinned** above, each degradation arm is
**named as a case** in the envelope, and `Do NOT` forbids *"degrade to no lock"* in words.

**What is separated, and it is `SL12`'s load-bearing half: the *check*.** `SL12` is not really "pick
one path" — one commit touching both writers satisfies that trivially. `SL12` is *"a future edit to
one file alone cannot silently remove mutual exclusion"*, which is a **structural guard** with a
different owner, a different file, and a different proof: `S7` touches only
`tests/guardrails.test.sh`, extracts each deriver's marker-delimited block, evaluates them under
identical inputs, and is proven by **mutation** — deliberately altering one writer's block and
observing red. That is exactly what `spec.md` demands (*"run and observed to fail when one writer's
derivation is deliberately altered. A case that merely asserts a hard-coded expected path does not
satisfy this"*), and it is unbuildable in `S5`'s commit for a concrete reason: at `S5` the third
deriver does not exist yet, so a divergence case written there would freeze a two-file list and leave
`S6`'s reader free to diverge in silence.

So: **`S5` owns the rule and the degradation. `S7` owns the guard that keeps them one rule.** `S6`
sits between them because it *adds a deriver*, and `S7` is what makes that safe.

---

## Slices

### S1 — Say what an orphaned holder does to the cap, in the mechanism's own header, for both writers
```
Owner:       loop-build
Context:     scripts/record-cost-event.sh -- the eviction header block, specifically the
             mkdir-mutex paragraph naming .claude/loop-cost-evict.lock (~:99-104) and the
             property block that states eventual convergence and L7's limit (~:107-116).
             The three release sites, so the note is accurate: :311 (append path), :330
             (arrival trim), and scripts/record-recovered-cost.sh:244.
             scripts/record-recovered-cost.sh's header note on holding the same lock with an
             independent copy of append_and_evict() (~:72-78), and EVICT_LOCK at :99.
             spec.md SL1, the section "What this unit actually achieves, in plain words", and
             the failure-mode rows for a catchable and an uncatchable death.
             tests/guardrails.test.sh ~:3239-3244 -- the existing eviction-header docs case
             (EVICTION_HEADER_FLAT), which is the house shape for this: flatten with
             `tr '#' ' ' | tr '\n' ' ' | tr -s ' '`, then grep labelled tokens in ONE
             conjoined expect. tests/guardrails.test.sh's final `docs (case count)` case,
             which stays last in the file.
Constraints: - STATE, NEXT TO THE EXISTING CONVERGENCE NOTE, what happens to the cap when the
               holder never releases: every later appender polls, gives up, appends anyway
               (L7), and never evicts -- so the cap is not enforced again for as long as that
               directory exists. Name the directory. Name the remedy a human has: remove that
               directory when no run is active.
             - STATE ONLY WHAT IS TRUE OF TODAY'S SCRIPTS. Do not write that catchable signals
               release the lock (S3), that the location is bounded by uptime (S4/S5), or that
               /cost reports it (S6). Each of those slices amends this block itself. Today's
               strongest honest phrasing is "not enforced again until the lock is removed".
             - THE FOUR CLAIM-WORDS NEVER APPEAR ABOUT THIS LEAK, anywhere: fixed, closed,
               resolved, prevented. Your second case is the guard for that and it must stay
               green for every later slice in this unit.
             - PUT THE SAME NOTE, ONE SENTENCE, IN scripts/record-recovered-cost.sh's HEADER.
               It holds the same lock at the same path; a reader of that file must not have to
               read the other one to learn that a Ctrl-C at its own prompt can leave the hook
               writer's cap unenforced.
             - Documentation only: `git diff main -- scripts/` shows comment lines and nothing
               else. No function, no branch, no call site, no behaviour.
             - README.md prose is OUT OF BOUNDS. Only the `## Development` case-count literal
               changes, computed from main per the delta rule (+2).
             - bash 3.2; `shellcheck -S warning scripts/*.sh` stays clean; script modes
               unchanged.
Output:      scripts/record-cost-event.sh (header comment), scripts/record-recovered-cost.sh
             (header comment), tests/guardrails.test.sh (+2 cases), README.md (literal only).
Done when:   A reader of either writer's header learns that an interrupted holder leaves the
             cap unenforced for that lock's lifetime and what a human can do about it -- and a
             case fails if any sentence in this repository ever calls this leak fixed, closed,
             resolved, or prevented.
Test set:    2 cases. Selection rule: one per surface that can drift independently -- the
             headers' content, and the repository's claim about itself. The house shape for
             the first is one CONJOINED case with labelled tokens (the existing eviction-header
             case's own form), chosen because two separate header cases would let one writer's
             note drift while the other stayed green.
               1. conjoined, over BOTH flattened headers, four labelled tokens:
                  orphan-case (the header says a lock nobody releases leaves the cap
                  unenforced), remedy (it names removing the directory when no run is
                  active), lock-path (it names the lock's location), recovered (the recovered
                  writer's header carries the same note)                            [SL1]
               2. claim-word guard: over pinned surfaces -- scripts/record-cost-event.sh,
                  scripts/record-recovered-cost.sh, scripts/cost-report.sh, README.md,
                  docs/loop/decisions.md, docs/loop/stale-evict-lock-permanently-defeats-the-
                  cap/*.md -- no SENTENCE containing the lock's name (or "orphan"/"stale
                  lock") also contains fixed / closed / resolved / prevented. Sentence-scoped
                  (flatten, then split on '. '), never file-scoped: a file-wide grep for
                  "fixed" matches half the repository and would be red for the wrong reason
                                                                                    [SL1]
             Fails now: neither header mentions an unreleased lock, the cap's exposure to one,
             or any remedy -- the mkdir-mutex paragraph stops at L7's accepted cost ("a ledger
             that sits slightly over cap for a moment"), which is the moment case, not the
             permanent one. Falsify it rather than assuming: run both cases against the
             pre-change files (`git show HEAD:` into a temp path) and record RED in your
             return before making them green.
             Passes after: both cases green, `docs (case count)` green on the recomputed
             literal, and every other case in the suite unmodified.
Do NOT:      - Do not change one line of behaviour in either script. No trap (S3), no
               relocation (S5), no reporting (S6).
             - Do not claim, imply, or pre-announce anything S3, S4, S5 or S6 delivers --
               including "bounded by uptime", which SL11 forbids until S4's evidence exists.
             - Do not edit README.md prose, the /cost paragraph, or the hooks table. Literal
               only.
             - Do not edit, weaken, delete, skip, reletter, renumber, or reorder any existing
               case, and do not move the final `docs (case count)` case.
             - Do not touch scripts/cost-report.sh, scripts/cost-ledger-lib.sh,
               scripts/ship-check.sh, scripts/write-cost-log-section.sh, hooks/hooks.json,
               .github/, docs/loop/checks.md, spec.md, or any other docs/loop/<unit>/
               directory -- two of them are being sliced by other agents right now.
             - Do not introduce an env var, threshold, default, or suggested value.
             - Do not pin an absolute case count read from this document; compute it from main.
             - Do not write to this repository's own .claude/.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  nothing
```

### S2 — Answer the staleness question on the record: no steal, ever, with every candidate and why
```
Owner:       loop-build
Context:     docs/loop/decisions.md -- append at the end, beneath the "Backlog gate: one queue,
             four drops, and six questions closed (2026-08-19)" entry. Read that entry's
             last section ("Two consequences for work already queued"), which is what queued
             this unit, and the two eviction entries above it ("Second G1: the ledger promises
             convergence..." and "Build-out of that decision...") whose arrival-trim reasoning
             this entry must not contradict.
             spec.md: SL2, SL8, section 0 (rmdir fails on a non-empty directory), section 1 in
             full INCLUDING its candidate table with all seven rows, section 2 (two copies of
             the primitive, one shared lock path, and why the earlier rejection does not
             transfer), and "Decisions taken at G0" OQ1-OQ7.
             scripts/record-cost-event.sh:205 and scripts/record-recovered-cost.sh:99 (the
             identical lock path, independently derived); :311, :330, :244 (the three rmdir
             releases); :281 (converge_ledger's `while :;`).
Constraints: - RECORD THE ANSWER, NOT A SUMMARY OF THE QUESTION: a lock cannot be declared
               stale with the signals available, and the decision is NO STEAL, EVER -- no pid,
               no `kill -0`, no age inference by this project's own code, and nothing written
               inside the lock directory.
             - NAME EVERY CANDIDATE IN SECTION 1's TABLE, BY NAME, with the reason it was taken
               or declined: identity-in-the-lock + `kill -0`; age-based expiry; two-phase
               claim / heartbeat; detect-and-report-only; release-on-catchable-signals;
               bound-the-leak-by-uptime (relocation); and write-the-limit-down-only. An entry
               that records the decision but not the alternatives is how a rejected design gets
               re-proposed in three months.
             - CARRY THE TWO REASONS THAT DO THE MOST WORK, because they are the ones a future
               session will otherwise re-derive: (a) section 0 -- `rmdir` fails on a non-empty
               directory, so anything written inside the lock breaks all three releases and
               turns a kill-only leak into a per-invocation one; this is WHY pid-in-lock is
               rejected, not a detail of it. (b) legitimate hold time is UNBOUNDED BY DESIGN
               (`while :;` with I/O-only breaks, and an attempt bound foreclosed twice), so no
               finite age threshold can be correct for some real workload -- age is not "not
               tuned yet", it is wrong in principle.
             - RECORD SL8's SENTENCE PLAINLY: the earlier rejection of extending the arrival-
               trim obligation to record-recovered-cost.sh stands on its own terms and does NOT
               transfer to lock hygiene, because A LEAK NEEDS AN INTERRUPTION, NOT CONTENTION,
               and a human-typed prompt is precisely where interruptions happen. Nothing about
               the earlier reasoning was wrong; it answered a different question.
             - STATE WHAT THIS UNIT DOES NOT DO, in the same entry: the leak is not fixed. A
               kill class this repository cannot catch remains, and the one kill it has actually
               recorded -- a machine sleep, in conventions.md -- is NOT established to be in the
               catchable class. Never fixed, closed, resolved, or prevented (S1's guard case
               covers this file).
             - Do NOT pre-record anything the build has not established: not the relocated
               location, not the base's clearing property, not a reap interval, not a measured
               cost. Those are S9's, after S4 and S8. If you find yourself writing "the lock
               now lives in", stop -- that is S9's sentence and S4 may yet make it false.
             - APPEND. Do not rewrite, reword, reorder, or re-date any existing entry.
             - Markdown only, one file, no case, no literal change.
Output:      docs/loop/decisions.md (one new entry, appended).
Done when:   A future session reading decisions.md alone can see that the staleness question is
             ANSWERED -- no steal, ever -- which seven candidates were weighed, why each was
             taken or declined, why age is wrong in principle rather than untuned, why nothing
             may be written inside the lock, why both writers are in scope, and that the leak
             itself is not claimed as fixed.
Test set:    1 check, and it is a READ, not a harness case -- and that is a deliberate choice,
             not an omission: nothing in this suite greps decisions.md, and adding a grep case
             would freeze the prose of the one file whose value is being written freely. The
             precedent is this repository's own (the arrival trim's closing slice made the same
             call for the same reason). Selection rule: the single thing this entry can fail at
             is silence about a rejected alternative, so the check is completeness against a
             list.
               1. all seven candidates from spec.md section 1's table appear by name with a
                  reason; section 0's `rmdir` catch appears as the reason pid-in-lock is
                  rejected; the unbounded-hold argument appears as the reason age is wrong in
                  principle; SL8's interruption-not-contention sentence is present; and the
                  entry states the leak is not fixed              [SL2, SL8, and SL1's guard]
             Fails now: decisions.md records the backlog gate that QUEUED this unit and the two
             eviction entries that preceded it; the staleness question is asked in three units'
             records and answered in none, which is the exact gap spec.md's Users section
             names.
             Passes after: one appended entry, seven named candidates, four load-bearing
             reasons, one plain statement of what is not fixed.
Do NOT:      - Do not rewrite, reword, reorder, or re-date any existing decisions.md entry.
             - Do not record the relocated path, the base's clearing property, a reap interval,
               or any measured figure -- S4, S8 and S9 own those, and S4 may invalidate them.
             - Do not describe the leak as fixed, closed, resolved, or prevented, and do not
               write "bounded by uptime" -- unestablished until S4 returns.
             - Do not reopen L7, the cap's property, the arrival trim's obligation class, or the
               convergence unit's decisions.
             - Do not edit scripts/, tests/, README.md, .github/, docs/loop/checks.md, spec.md,
               or any other docs/loop/<unit>/ directory.
             - Do not add a harness case over decisions.md.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  nothing
```

### S3 — Release the lock on a catchable signal, in both writers, and only a lock this process created
```
Owner:       loop-build
Context:     scripts/record-cost-event.sh: append_and_evict() (:297-315) -- the L7 poll
             (:301-304), the unconditional `>>` (:307), `mkdir "$EVICT_LOCK"` (:309),
             converge_ledger (:310), `rmdir` (:311); trim_on_arrival() (:327-332) with its
             single mkdir attempt (:328) and `rmdir` (:330); converge_ledger() itself
             (:271-293) -- the `while :;` at :281, `tail` at :286, `mv -f` at :290 -- whose
             loop is the window a kill lands in.
             scripts/record-recovered-cost.sh: append_and_evict() (:218-247), its bounded
             (attempt < 5) trim loop, and `rmdir` at :244. Note it runs at a human's prompt
             where Ctrl-C is ordinary, and that it already releases its own
             `_recovered/<id>` marker explicitly on an internal parser failure (:207-211) --
             the shape to follow, not to extend.
             tests/guardrails.test.sh: case (h) (~:507-556) -- the PRECEDENT CONSTRUCTION for
             this slice: a stub `mv` first on PATH to hold the loop, bash job control with
             `set -m`, a pid file, `kill -0` polling, and TERM/KILL to the whole process group
             (never GNU `timeout`, absent on the maintainer's bash 3.2 macOS host). Case (g)
             (~:482-505) and case (i) (~:557-585), which must stay green with their assertions
             UNEDITED. The `cost()` helper at :70 and `finish_json`.
             spec.md SL3 (first half), SL5, SL4, SL6, SL9, and the failure-mode rows for a
             catchable death, an uncatchable death, and "a signal handler runs in a process
             that never acquired the lock".
Constraints: - THE BEHAVIOUR: a process that currently holds $EVICT_LOCK and is killed by a
               CATCHABLE signal (INT, TERM, HUP) releases it before dying. Both writers.
             - ONLY A LOCK THIS PROCESS CREATED. Keep an in-process ownership flag set
               immediately after a successful `mkdir "$EVICT_LOCK"` and cleared at the release,
               and make the handler a NO-OP when it is not set. A handler that `rmdir`s
               unconditionally is the steal risk arriving as a bug -- SL5 covers it and case 3
               below asserts it.
             - NO UNCONDITIONAL EXIT TRAP. An EXIT trap that releases without consulting the
               flag can remove a lock a DIFFERENT process acquired in the window after this one
               released -- the concurrent-trim record loss this unit refuses to risk.
             - NOTHING IS WRITTEN INSIDE THE LOCK DIRECTORY, on any path, including by the
               handler. `rmdir` fails on a non-empty directory (section 0), so a note left for a
               human there would break all three releases.
             - EXIT 0 ON EVERY PATH (L6), including from the handler. The hook must not turn a
               signal into a non-zero exit that a host could read as a failed command.
             - NO NEW WAIT ANYWHERE (L7): no poll, no sleep, no retry added to any path.
               Cases (g) and (i) keep their assertions unedited and stay green.
             - DO NOT TOUCH converge_ledger()'s BREAK SET or its `while :;` shape, and do not
               add an attempt bound, iteration counter, or no-progress guard. Foreclosed twice.
             - AMEND S1's HEADER SENTENCE IN THIS COMMIT: it currently says an interrupted
               holder leaves the lock behind. After this slice that is true only for
               UNCATCHABLE deaths, and the header must say exactly that -- naming INT/TERM/HUP
               as released and KILL, OOM, power loss, and the machine-sleep class this
               repository has actually recorded as NOT released and NOT established to be
               catchable. Still never "fixed", "closed", "resolved", or "prevented": S1's
               claim-word case is your guard.
             - SL4 IS YOURS: reproduce your own red. `git show <rev>:scripts/...` into a temp
               file (never checkout/branch/stash), 5 trials against the pre-change script and 5
               against the changed one, both shas and both counts in your return.
             - Case count: +3, computed from main per the delta rule.
             - bash 3.2 only (trap semantics differ from 5.x -- this is exactly why SL10 wants
               both platforms); `shellcheck -S warning scripts/*.sh` clean; script modes
               unchanged.
Output:      scripts/record-cost-event.sh (ownership flag, handler, header amendment),
             scripts/record-recovered-cost.sh (the same, independently), tests/
             guardrails.test.sh (+3 cases), README.md (literal only).
Done when:   A holder killed mid-trim by INT, TERM, or HUP leaves no lock behind and leaves the
             ledger complete, parseable, and the newest N in order -- in BOTH writers -- while a
             process that never acquired the lock, killed the same way, removes nothing.
Test set:    3 cases. Selection rule: one per thing this handler can get wrong that no existing
             case would catch -- it fails to fire (the hook writer), it fires in only one of the
             two writers (the recovered CLI), or it fires too broadly (a non-holder). The
             "killed by KILL" arm was CONSIDERED AND NOT TAKEN: the spec states outright that
             KILL is not addressed, so a case asserting the lock survives a KILL would pin a
             non-goal as behaviour and would read as a claim that the surviving lock is
             acceptable rather than unfixed.
               1. hook writer, killed mid-trim by TERM: hold the trim inside converge_ledger
                  with case (h)'s stub-`mv`-on-PATH technique, confirm the lock exists, TERM
                  the process group, then assert -- no lock directory remains, the ledger is
                  non-empty and every line parseable, and the runner exited 0     [SL3, SL5, H3]
               2. record-recovered-cost.sh, killed by INT while holding: same shape, driven
                  through the CLI's own arguments, asserting no lock remains and the ledger is
                  intact. This is the interruption class the CLI actually lives in -- a human at
                  a prompt -- and it is the one case (h) can never cover        [SL3, SL8, OQ2]
               3. a handler in a process that never acquired the lock releases NOTHING: with a
                  lock present and held by another process, TERM a real hook invocation while it
                  is polling or appending, then assert the lock is STILL THERE and the other
                  holder's directory is untouched                                       [SL5]
             Fails now: neither script installs a handler of any kind, so 1 and 2 have no code
             path and both leave the lock behind -- which is the fault itself, constructed. 3
             passes today trivially (there is no handler to fire) and is kept as the regression
             guard for the path 1 and 2 add; say so in its comment rather than presenting it as
             red-before.
             Passes after: 1-3 green; the eviction section's cases (a), (b), (f), (g), (h),
             (i), (j) unmodified and
             green; `docs (case count)` green on the recomputed literal.
Do NOT:      - Do not write anything inside the lock directory -- not a pid, not a timestamp,
               not a marker, not a note for a human.
             - Do not infer a holder is dead, anywhere, by any signal. No pid file, no
               `kill -0` on a recorded pid, no age check, no `stat`.
             - Do not add an unconditional EXIT trap, and do not release without consulting the
               ownership flag.
             - Do not add a trap release for the finished marker, `_recovered/<id>`, or any
               `_rework/` directory. Their orphan questions are separate intents (non-goals).
             - Do not relocate the lock, derive a new path, or read TMPDIR -- that is S5, and
               doing it here makes both slices unmeasurable and unmergeable.
             - Do not add output to any hook path. The report is S6's and lives in /cost.
             - Do not add a wait, poll, sleep, or retry to any path, and do not edit case (g)'s
               or case (i)'s assertions.
             - Do not alter converge_ledger()'s break set or add a bound, counter, or
               no-progress guard.
             - Do not weaken, delete, skip, reletter, renumber, or reorder any case.
             - Do not touch scripts/cost-report.sh, scripts/cost-ledger-lib.sh,
               scripts/ship-check.sh, hooks/hooks.json, .github/, docs/loop/checks.md,
               README.md prose, spec.md, decisions.md, or any other docs/loop/<unit>/ directory.
             - Do not introduce an env var, threshold, default, or suggested value.
             - Do not use GNU `timeout` to bound anything; follow case (h)'s job-control shape.
             - Do not write to this repository's own .claude/; throwaway CLAUDE_PROJECT_DIR.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  S1 -- textual (same eviction header block; both slices add cases and so both move
             README's case-count literal) AND semantic (this slice amends the sentence S1
             writes, narrowing it from "an interrupted holder" to "an uncatchably killed one").
             Not a layer habit: landing this first would leave one commit in which the code
             releases on TERM while nothing anywhere states what an orphan does to the cap.
```

### S4 — Establish by observation what the candidate base does with a lock across a reboot, and across time, on both guarding platforms
```
Owner:       loop-build   (read-only; markdown only; this lane runs experiments and writes no
                           code, no case, and no script)
Context:     spec.md section 4(a) (the required properties of the location, which is what a
             builder is held to rather than a literal path), 4(b) (the candidate
             `${TMPDIR:-/tmp}` and the statement that its reboot-clearing is NOT established in
             this repository on either platform, and that citing documentation is not
             establishing it), 4(c) (a reaped-by-age base smuggles back exactly what section 1
             rejected), 4(d) (a world-writable base is a new permanent-defeat route); SL11 in
             full, SL5, SL7's last clause (the OS's interval is RECORDED, never adopted), SL10's
             note that temp-directory location and clearing policy differ between the two
             guarding platforms.
             spec.md section 1's measured hold time (~16 ms for a quiet trim) and the reason
             legitimate hold is UNBOUNDED by design (converge_ledger's `while :;`) -- both are
             what SL5 must be re-argued against.
             docs/loop/checks.md and .github/workflows/ci.yml, READ ONLY, for which two
             platforms are the guarding ones (ubuntu-latest, macos-latest) -- do not edit
             either.
             This slices.md's section "The reboot-property evidence is its own slice" -- it
             carries a one-host, one-sample observation already made at this gate (both
             candidate bases disk-backed on the same APFS volume; /private/tmp drwxrwxrwt
             root:wheel; $TMPDIR drwx------ and per-user). REPRODUCE IT, do not inherit it.
Constraints: - THE ONLY DELIVERABLE IS SL11's EVIDENCE: for each guarding platform, which base
               a run actually gets (TMPDIR when set, /tmp when not), that base's mode and
               owner, what clears it, and on what schedule -- established by OBSERVING THE
               MACHINE, never by citing documentation.
             - WHAT COUNTS AS AN OBSERVATION HERE, since a reboot mostly is not available: the
               backing store (`df`, mount type -- a memory-backed base cannot survive a reboot
               and that IS evidence); the mode and owner of the base and of any per-uid parent;
               and the machine's OWN clearing configuration READ FROM THAT MACHINE (e.g. the
               tmpfiles configuration files present on a Linux host, or the periodic-cleanup
               scripts present on macOS) -- reading a config file off the machine is an
               observation of that machine; quoting a man page or a vendor doc is not.
             - LABEL EVERY OBSERVATION BY WHAT IT IS EVIDENCE ABOUT. The maintainer's host is
               evidence about the maintainer's host. A container or VM is INVESTIGATION-GRADE
               and is never evidence about ubuntu-latest or macos-latest. Say which is which in
               every row.
             - NAME THE HALF NO BUILDER CAN REACH, PLAINLY, AND HAND IT OVER: a real reboot of
               the maintainer's host is the human's action, and a CI runner cannot be rebooted
               at all -- a fresh VM per run is NOT the same observation as "the base was
               cleared". Leave ONE clearly-named marker directory in each base on the
               maintainer's host, record its exact absolute path, and state the single `ls` the
               human runs after their next reboot. Do not reboot, restart, sleep, or otherwise
               interrupt the host yourself.
             - IF THE BASE IS CLEARED BY AGE RATHER THAN AT BOOT: state the interval, read from
               that machine's own configuration, as a number; state that it is an OS-OWNED
               STALENESS THRESHOLD THIS PROJECT DID NOT CHOOSE, CANNOT SEE FROM ITS OWN CODE,
               AND CANNOT TEST; and RE-ARGUE SL5's live-holder guarantee against it explicitly
               -- against the ~16 ms quiet trim AND against the fact that legitimate hold is
               unbounded by design, which is the comparison that actually matters. SL11(c)
               tolerates this only if the record says all of it.
             - IF NEITHER BASE HAS A BOOT-CLEARING PROPERTY ON EITHER PLATFORM, SAY SO PLAINLY
               AND RETURN `needs-decision`. SL11 then forbids the bounded-by-uptime claim
               anywhere, and whether relocation still earns its costs is the human's call before
               S5 is briefed. Do not soften this into "cleared eventually", and do not go
               looking for a third base to rescue the design -- proposing one is a
               `needs-decision`, not a fix.
             - `unknown` IS A COMPLETE ANSWER for any row, recorded with what was tried and what
               would settle it.
             - Counts, never rates. One observation is one sample.
             - Never the repository's own .claude/, and clean up everything you create except
               the two named reboot markers.
Output:      docs/loop/stale-evict-lock-permanently-defeats-the-cap/spike-sl11-base-clearing.md
Done when:   That file states, per platform: the base a run gets and how that was determined;
             its mode and owner; its backing store; what clears it and on what schedule, from
             the machine's own configuration; whether the per-boot property of section 4(a)
             holds, fails, or is unknown; the exact marker paths and the one command the human
             runs after a reboot; and -- if any age-based reaping is found -- the interval as a
             number, the statement that it is an OS-owned threshold this project did not choose,
             and SL5's guarantee re-argued against it.
Test set:    4 checks. THE PROOF IS A SET OF OBSERVATIONS, NOT A HARNESS CASE, and the file says
             so rather than disguising it: no case in this suite can observe a reboot, and a
             case asserting a property of the host's temp directory would be asserting something
             about the machine rather than about this repository. Selection rule: one check per
             way this record could mislead a reader who cannot re-run it.
               1. every row is labelled evidence-about-this-host / investigation-grade /
                  not-obtainable-by-a-builder -- no row is unlabelled                  [SL11]
               2. both candidate bases are covered per platform WITH mode and owner, because
                  section 4(d)'s squatting exposure differs between them and the exposure is
                  the reason the fallback exists                                 [SL11, SL13]
               3. any age interval found is a NUMBER read from that machine's configuration,
                  and SL5 is re-argued against it in the same paragraph -- including against
                  the unbounded-hold case, not only the ~16 ms one            [SL11(c), SL5]
               4. the unobservable half is named as the human's, with the marker paths and the
                  exact command -- not left as "would need a reboot"                   [SL11]
             Fails now: spec.md records this as unestablished in either direction, on both
             platforms; nothing in this repository states what clears either candidate base;
             and the unit's entire bounded-by-uptime claim currently rests on nothing.
             Passes after: one file, both platforms, every row labelled -- or `needs-decision`
             with the negative stated plainly.
Do NOT:      - Do not write, edit, or prototype any code, case, script, or workflow. This
               lane's whole diff is one new markdown file.
             - Do not reboot, restart, sleep, shut down, or otherwise interrupt the maintainer's
               host, and do not suggest doing it mid-run.
             - Do not cite documentation, a man page, a vendor page, or a runner-image manifest
               as evidence of the clearing property. Read the machine.
             - Do not report a container observation as evidence about a guarding platform.
             - Do not choose, propose, or imply a threshold, interval, or margin of this
               project's own.
             - Do not propose a different base to rescue the design; return `needs-decision`.
             - Do not write to this repository's own .claude/, and do not leave anything in the
               temp bases except the two named markers.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  nothing  (runs in parallel with S1, S2 and S3; blocks S5)
```

### S5 — Relocate the lock by one derivation per writer, degrading to today's path when the base cannot be safely used
```
Owner:       loop-build
Context:     HELD UNTIL S4 RETURNS AND THE HUMAN HAS READ IT. If S4 returned `needs-decision`,
             this envelope is not briefed.
             scripts/record-cost-event.sh:203-205 (DIR/OUT/EVICT_LOCK, derived from
             ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"), append_and_evict() (:297-315),
             trim_on_arrival() (:327-332), converge_ledger() (:271-293) and its temp file
             (`mktemp "$OUT.evict.XXXXXX"`, :285 -- which MUST stay on the ledger's own
             filesystem so `mv` is an atomic rename; it does not move).
             scripts/record-recovered-cost.sh:95-99 (the identically derived DIR and
             EVICT_LOCK) and append_and_evict() (:218-247).
             spec.md section 4 in full -- (a) required properties, (b) the candidate, (c) the
             age concession, (d) the squatting route, (e) why a partial relocation is a
             regression, (f) why the trap is still needed, (g) only the lock moves; SL12's
             derivation half, SL13 in full, SL5, SL4, SL7, SL9; the failure-mode rows for a
             missing/unwritable/foreign-owned base, for a lock at the OLD location, and for two
             writers resolving DIFFERENT ledgers (which correctly get different locks).
             spike-sl11-base-clearing.md (S4's output) -- the base actually chosen, and any
             recorded age concession.
             tests/guardrails.test.sh: EVERY existing reference to the lock path -- ~:386, :410,
             :454, :456, :482, :483, :507, :545, :557, :559, :591, :640 -- i.e. the section
             cleanups plus cases (f) CONV_LOCK, (g) L7_LOCK, (h) MVFAIL_LOCK, (i) NOWAIT_LOCK.
             This slices.md's "Pinned contracts" table: the marker-delimited derivation, the
             cksum choice, the safety predicate, the root-free degradation arms, and the
             throwaway-TMPDIR rule.
Constraints: - ONE RULE, EXPRESSED ONCE PER FILE, BETWEEN THE PINNED MARKERS:
               `# >>> evict lock derivation (SL12)` ... `# <<< evict lock derivation (SL12)`.
               Inside the markers: assignments computable from ROOT/DIR only, no side effect
               beyond creating the per-uid parent, no `source`, no library read, no new tool
               dependency. Both writers get the block, in the SAME COMMIT. A partial relocation
               is a correctness regression, not a partial improvement (section 4(e)).
             - THE DERIVATION, as pinned at G1: base `${TMPDIR:-/tmp}`; a per-uid parent inside
               it created with `mkdir -m 700`; the lock name derived from the LEDGER'S OWN
               RESOLVED ABSOLUTE PATH via `cksum` (POSIX, both platforms -- never sha256sum,
               shasum, md5, md5sum: the spelling differs between the guarding platforms).
               Different ledgers therefore get different locks; the same ledger always gets the
               same lock. If you believe cksum is unsuitable, return `needs-decision`.
             - THE SAFETY PREDICATE IS PART OF THE RULE, NOT A FEATURE BESIDE IT. Use the
               relocated path only when the base is `-d` and `-w`, AND the per-uid parent is,
               after creation, `-d`, `! -L`, `-O`, and `-w`. Any check failing -> the lock is
               `$DIR/loop-cost-evict.lock`, TODAY'S PATH. NEVER no lock, on any branch, for any
               reason -- appending and trimming without a lock is the record loss this whole
               unit refuses to risk.
             - THE TOCTOU IN THAT PREDICATE STAYS OPEN, DELIBERATELY. Between the check and the
               `mkdir` of the lock, another party could replace the parent. spec.md names this
               and deliberately does not specify it away. Do not close it with a pid, an age, a
               retry, a rename dance, or a second check; if you believe it must be closed,
               return `needs-decision`.
             - NOTHING IS WRITTEN INSIDE THE LOCK DIRECTORY (section 0). The per-uid parent is
               not the lock; the lock is a directory inside it and stays empty.
             - NO NEW WAIT, POLL, RETRY, OR SLEEP ANYWHERE (L7). Cases (g) and (i) keep their
               assertions unedited. The path resolution you add runs on the appending path, so
               S8 measures it -- do not make it unmeasurable, and do not put a subprocess in it
               that you have not counted.
             - THE HARNESS SWEEP IS PART OF THIS SLICE AND IS THE MOST DANGEROUS PART OF IT.
               Every existing lock-path reference must become the DERIVED path, computed by
               extracting the hook writer's own marker-delimited block -- never by a second
               hand-written copy of the rule in the test file. TWO CASES CAN GO GREEN FOR THE
               WRONG REASON IF YOU GET THIS WRONG, and neither would fail to tell you: case (g)
               (an append lands while the lock is held) and case (h) (the lock is not left
               behind after a failed `mv`) both still pass if they hold or inspect a path the
               writer no longer uses -- they simply stop asserting anything. For each of (f),
               (g), (h), (i), state in your return what you did to confirm it still constructs
               what it claims.
             - EVERY CASE THAT EXERCISES THE RELOCATED PATH SETS ITS OWN THROWAWAY TMPDIR
               (`mktemp -d`, removed afterwards). No case may create a lock in the real temp
               base: the suite must not collide with a concurrent real run on the same machine.
             - AMEND THE HEADERS IN THIS COMMIT: both writers' notes must state where the lock
               now lives, the rule that derives it, that an unsafe base degrades to the ledger-
               side path, and -- only if S4's evidence supports it -- that an orphan is bounded
               by uptime. If S4 recorded an age concession instead, the header says THAT, in
               S4's terms. Still never fixed, closed, resolved, or prevented; S1's claim-word
               case is your guard.
             - SL4 IS YOURS: your own red, 5 trials per version, both shas, in your return.
             - Case count: +5, computed from main per the delta rule.
             - bash 3.2 only; `shellcheck -S warning scripts/*.sh` clean; exit 0 on every path;
               script modes unchanged.
Output:      scripts/record-cost-event.sh (marker-delimited derivation, header amendment),
             scripts/record-recovered-cost.sh (the same, independently),
             tests/guardrails.test.sh (lock-path sweep + 5 cases), README.md (literal only).
Done when:   Both writers guard the same ledger through the same relocated lock; a lock held at
             that derived path defeats a trim exactly as a lock beside the ledger used to; a
             base that is missing, not a directory, or occupied by something this process does
             not own degrades to today's path with mutual exclusion intact and a lock always
             present; and a lock left at the old path by a pre-change version is inert without
             being removed.
Test set:    5 cases. Selection rule: one per branch of the one rule that a later reader could
             break without any other case noticing -- the relocated branch, and each degradation
             arm that is constructible without root -- plus the migration state a real user will
             actually have on disk. The `chmod 000` base arm was CONSIDERED AND NOT TAKEN: a
             suite run as root would defeat it, and no case here may depend on the runner's uid;
             the pinned arms falsify the same predicate without that dependency. The
             second-uid squat is NOT constructible in this suite -- record it as a named limit
             rather than simulating it and claiming it.
               1. relocated, and mutual exclusion moved with it: with a throwaway TMPDIR, a lock
                  held at the DERIVED path makes a real appending invocation lose its trim (the
                  ledger is over cap at rest), and no lock directory is created beside the
                  ledger                                                       [SL12, SL5, H3]
               2. degrade -- base absent: TMPDIR points at a path that does not exist. The lock
                  is created BESIDE THE LEDGER, and a lock held there defeats the trim (mutual
                  exclusion is real at the fallback path, not merely a path choice)     [SL13]
               3. degrade -- base is not a directory: TMPDIR points at a regular file. Same
                  assertions as 2                                                       [SL13]
               4. degrade -- the per-uid parent name is occupied by something we do not own in
                  the -d / ! -L / -O sense (a regular file, and a symlink): the lock is created
                  beside the ledger, and A LOCK EXISTS SOMEWHERE -- assert that explicitly,
                  because "never lockless" is the half of SL13 that a passing test can most
                  easily fail to check                                            [SL13, 4(d)]
               5. a lock left at the OLD ledger-side path by a pre-change version, with a usable
                  base: inert. A normal appending run trims to cap (it is not read as held), and
                  the old directory is STILL THERE afterwards -- this code removes nothing it
                  did not create                                                  [SL13, SL5]
             Fails now: today both writers use the ledger-side path unconditionally, so 1 is red
             (a lock at the derived path is ignored and the appender trims), 2-4 have no code
             path at all (there is no predicate and no fallback), and 5 is red in the direction
             that matters (a lock at that path is read as held and blocks the trim).
             Passes after: 1-5 green; the eviction section's (a), (b), (f), (g), (h), (i), (j)
             green with the swept paths and unedited assertions; `docs (case count)` green on the recomputed literal.
Do NOT:      - Do not degrade to running without a lock, on any branch, for any reason.
             - Do not move the ledger, the finished marker, `_recovered/`, any `_rework/`
               directory, or the `.evict.` temp file. Only the lock moves (section 4(g)); the
               temp file must stay on the ledger's filesystem for `mv` to be atomic.
             - Do not write anything inside the lock directory.
             - Do not add a pid, timestamp, age check, `stat`, `kill -0`, or any staleness
               inference, and do not remove a lock this process did not create.
             - Do not close the predicate's TOCTOU; return `needs-decision` if you think you
               must.
             - Do not `source` anything from scripts/record-cost-event.sh, and do not move
               either append_and_evict() into scripts/cost-ledger-lib.sh.
             - Do not hand-write a second copy of the derivation in tests/guardrails.test.sh;
               extract the writer's own marker-delimited block.
             - Do not let any case create a lock in the real temp base.
             - Do not add a wait, poll, retry, or sleep, and do not edit case (g)'s or case
               (i)'s assertions.
             - Do not change converge_ledger()'s break set, or add a bound, counter, or
               no-progress guard.
             - Do not add an env var, threshold, default, or suggested value -- including any
               opt-out for the relocation.
             - Do not add output to any hook path (S6 owns the report), and do not touch
               scripts/cost-report.sh in this slice.
             - Do not touch scripts/cost-ledger-lib.sh, scripts/write-cost-log-section.sh,
               scripts/ship-check.sh, hooks/hooks.json, .github/, docs/loop/checks.md,
               README.md prose, spec.md, decisions.md, or any other docs/loop/<unit>/ directory.
             - Do not claim bounded-by-uptime unless S4's evidence supports it, and never write
               fixed, closed, resolved, or prevented.
             - Do not weaken, delete, skip, reletter, renumber, or reorder any case.
             - Do not write to this repository's own .claude/.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  S3 (textual and semantic: the same mkdir/rmdir region in both writers, the same
             header block, the same case-count literal; and the ownership flag S3 installs is
             what makes the relocated lock's release provably its own) AND S4 (the evidence
             gate: SL11 forbids the bounded-by-uptime claim without it, and S4 can invalidate
             the base choice outright).
```

### S6 — Report a present evict lock where a human already looks, without ever inferring the holder is dead
```
Owner:       loop-build
Context:     scripts/cost-report.sh -- its header (read-only formatter, reads only
             .claude/loop-cost.jsonl, every figure from cost-ledger-lib.sh, always exits 0,
             everything to stdout because commands/cost.md relays stdout verbatim); ROOT_DIR
             and LEDGER at :24-25; the Coverage block (~:201-232) as the neighbourhood a
             ledger-health line belongs beside; print_absent()/print_empty() for the shape of a
             plain statement.
             commands/cost.md -- READ ONLY, to confirm it relays stdout verbatim and to check
             that no change to it is needed.
             scripts/record-cost-event.sh's marker-delimited derivation block as landed by S5 --
             this file gets the SAME RULE, between the SAME markers, as the third and last
             deriver.
             spec.md SL3 (second half), OQ4, OQ5, the failure-mode rows for "the lock is present
             with no live holder" and "the lock is present and the ledger is under cap", and the
             non-goal that /cost's read-only charter does not change.
             This slices.md's "SL3's reporting shape, settled here" -- the settlement you are
             building, including what you may not do.
             tests/guardrails.test.sh's cost-report section (~:1000-1080), especially the
             `report_exit` helper and case (k)'s CO2 grep, for the house shape.
Constraints: - THE ROUTE IS /cost AND NOTHING ELSE. No output from either writer, on any path.
             - PRINT A BLOCK WHEN THE LOCK DIRECTORY EXISTS, and say four things: that it is
               present, and where (the absolute path); what its presence means for the cap (no
               invocation trims the ledger while it is held); that a live trim and an orphan are
               INDISTINGUISHABLE FROM HERE -- this reader cannot and does not judge which; and
               what a human may do when no run is active (remove that directory).
             - NEVER INFER DEATH. No sentence determines the holder is dead, stale, crashed,
               gone, or hung. No pid, no age, no `stat`, no `kill -0`, no elapsed-time hint, no
               "probably". The wording is informational, not an alarm -- that is also how the
               under-cap case is carried (spec.md: under cap there is "nothing worth alarming
               anyone about").
             - THE READER REPAIRS NOTHING. No rmdir, no rm, no touch, no mkdir of the lock
               itself, no write of any kind. /cost's read-only charter is unchanged, and a case
               below asserts the lock is still there after the report runs.
             - REPEAT REPORTING IS BOUNDED STRUCTURALLY, WITH NOTHING MINTED. /cost is
               human-invoked, so this prints once per human read and zero times per hook
               invocation. Do NOT mint a one-shot marker, a state file, a new ledger record
               type, or any "already reported" memory -- a marker would be another orphanable
               `mkdir` directory with the failure mode this unit exists to reduce (OQ5).
             - NO CAP PARSER IN THE READER, and the block does not judge whether the cap is
               currently violated. Gating the block on an over-cap ledger would need a fourth
               copy of the LARAVEL_LOOP_COST_MAX_LINES parser in a file whose charter says every
               figure comes from cost-ledger-lib.sh. Recorded as the human's open question at
               G1; if you believe it must be gated, return `needs-decision`.
             - THE PATH COMES FROM THE SAME RULE, between the same markers, as S5's writers.
               You are the third and last deriver; S7 asserts all three agree. Do not invent a
               variant, do not read the writers at runtime, and do not fall back to the
               ledger-side path unconditionally.
             - EXIT 0 ON EVERY PATH, everything to stdout, including when the base is unusable
               or the lock cannot be inspected. A reporting tool that can crash is worse than
               one that says plainly what it could not read.
             - SL4 IS YOURS: your own red, 5 trials per version, both shas, in your return.
             - Case count: +3, computed from main per the delta rule.
             - bash 3.2; `shellcheck -S warning scripts/*.sh` clean.
Output:      scripts/cost-report.sh (marker-delimited derivation + the ledger-health block),
             tests/guardrails.test.sh (+3 cases), README.md (literal only).
Done when:   A person who runs /cost with an orphaned lock on disk learns that it is there,
             where it is, that the cap is not being enforced while it is, that nothing here can
             tell a live trim from an orphan, and what they may do about it -- and a person with
             no lock on disk sees nothing new at all.
Test set:    3 cases. Selection rule: one per way a report can fail its reader -- it stays
             silent when there is something to say, it speaks when there is nothing, or it acts
             when it was only ever allowed to look. A "reports it once and then never again"
             case was CONSIDERED AND NOT TAKEN: bounding is structural here (the only route that
             prints is human-invoked) and asserting it would require the marker OQ5 forbids.
               1. lock present at the derived path -> /cost's output names the path, says the
                  ledger is not being trimmed while it is held, says a live trim and an orphan
                  cannot be told apart from here, and names the human's remedy; exit 0
                                                                                [SL3, OQ4, OQ5]
               2. no lock present -> none of those strings appears anywhere in the output, and
                  the rest of the report is byte-identical to the same fixture's output without
                  this change. No false alarm, and no drift in what /cost already prints  [SL3]
               3. the reader repairs nothing: after running /cost with the lock present, the
                  lock directory STILL EXISTS, the ledger is byte-identical, and nothing new was
                  created anywhere under the base or beside the ledger        [/cost read-only]
             Fails now: /cost has no notion of the evict lock; the state is discoverable only by
             reading scripts/record-cost-event.sh, which is exactly the silence SL3 names.
             Passes after: 1-3 green, the cost-report section's existing cases unmodified and
             green, `docs (case count)` green on the recomputed literal.
Do NOT:      - Do not remove, release, repair, rename, or write anything -- /cost reads only.
             - Do not print from any hook path, and do not touch scripts/record-cost-event.sh or
               scripts/record-recovered-cost.sh in this slice.
             - Do not mint a marker, state file, new record type, or "already reported" memory.
             - Do not add a cap parser, threshold, default, interval, or env var to the reader.
             - Do not say, imply, or hedge that the holder is dead, stale, crashed, gone, or
               hung, and do not print an age, elapsed time, or timestamp about the lock.
             - Do not use the words fixed, closed, resolved, or prevented about this leak.
             - Do not write a second variant of the derivation; use the pinned markers.
             - Do not edit commands/cost.md, scripts/cost-ledger-lib.sh,
               scripts/write-cost-log-section.sh, scripts/ship-check.sh, .github/,
               docs/loop/checks.md, README.md prose, spec.md, decisions.md, or any other
               docs/loop/<unit>/ directory.
             - Do not change any existing /cost output line, ordering, or wording.
             - Do not weaken, delete, skip, reletter, renumber, or reorder any case.
             - Do not write to this repository's own .claude/.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  S5 -- there is no correct path for this reader to derive until the writers' rule
             exists. A reader that derived the pre-change path would confidently report the
             wrong directory, which is worse than the silence it replaces.
```

### S7 — Make a divergence between the three derivations red
```
Owner:       loop-build
Context:     The marker-delimited derivation blocks as landed by S5 and S6, in
             scripts/record-cost-event.sh, scripts/record-recovered-cost.sh, and
             scripts/cost-report.sh -- the exhaustive list of derivers, pinned in this
             document's contracts table.
             spec.md SL12 in full, especially "A case exists that computes the location as each
             writer computes it and FAILS IF THEY DIFFER" and "A case that merely asserts a
             hard-coded expected path does not satisfy this"; section 4(e) (two writers, two
             paths, no mutual exclusion at all); the failure-mode rows for "the two writers
             derive different lock locations" and "the two writers resolve DIFFERENT ledgers".
             tests/guardrails.test.sh -- the sweep helper S5 added (which already extracts the
             hook writer's block), and the file's final `docs (case count)` case.
Constraints: - THE CASES COMPUTE, THEY DO NOT ASSERT A LITERAL. Extract each deriver's
               marker-delimited block, evaluate each in its own subshell under IDENTICAL inputs
               (the same ROOT/ledger, the same TMPDIR), and compare the resulting paths. A
               hard-coded expected path fails SL12 by the spec's own words.
             - COVER EVERY DERIVER THAT EXISTS -- all three. If you find a fourth, that is a
               finding: report it rather than quietly extending the list.
             - PROVE IT BY MUTATION, AND RECORD THE PROOF: deliberately alter ONE deriver's
               block in your working tree, run the case, observe RED, revert. Report the exact
               mutation and the failing output in your return. A guard nobody has seen fail is a
               guard nobody knows works -- and this is the only red available to this slice,
               since the paths agree the moment they are written.
             - THE MUTATION IS NOT COMMITTED, and no case in the suite may depend on a mutated
               file existing.
             - Cover BOTH branches of the rule: the derivers must agree with a usable base AND
               agree when the base is unusable and all three degrade. A guard that only checks
               the happy branch lets the fallback diverge, which is the same defect with a
               quieter arrival.
             - Cover the collision direction too: two DIFFERENT ledgers must never derive the
               same lock. spec.md's failure-mode table is explicit that the invariant is "the
               lock is a function of the ledger it guards", not "one lock per machine".
             - Harness only: `git diff main --name-only` shows tests/guardrails.test.sh and
               README.md's literal, and nothing else. No script changes.
             - Every case sets its own throwaway TMPDIR and CLAUDE_PROJECT_DIR.
             - Case count: +3, computed from main per the delta rule.
             - bash 3.2 only.
Output:      tests/guardrails.test.sh (+3 cases), README.md (literal only).
Done when:   Editing the lock's derivation in one script and not the others turns this suite
             red -- so mutual exclusion cannot be silently removed by a future edit to one file.
Test set:    3 cases plus one recorded mutation observation. Selection rule: one per branch of
             the rule that could diverge (usable base, degraded base) plus the one direction a
             divergence guard can get backwards (two ledgers must NOT collide). A fourth case
             asserting the path's literal shape was CONSIDERED AND NOT TAKEN: it is precisely
             the hard-coded assertion SL12 refuses, and it would freeze a path the spec
             deliberately expressed as properties rather than a literal.
               1. usable base: all three derivers, evaluated under identical inputs, produce the
                  IDENTICAL path                                                       [SL12]
               2. unusable base: all three degrade to the identical ledger-side path
                                                                                 [SL12, SL13]
               3. two different ledgers (two different CLAUDE_PROJECT_DIRs) produce two
                  different locks, in every deriver                                    [SL12]
             Fails now: nothing anywhere compares the writers' derivations; before S5 they were
             two independent literals that agreed by coincidence of text, and after S5/S6 there
             are three blocks whose agreement is asserted by no case at all.
             Passes after: 1-3 green, the recorded mutation observed RED and reverted, and the
             whole suite green with `docs (case count)` on the recomputed literal.
Do NOT:      - Do not assert a hard-coded expected path, in any case, in any form.
             - Do not commit a mutated script, and do not leave a case depending on one.
             - Do not edit any script in scripts/ -- if a deriver's block cannot be extracted
               cleanly, that is a finding about S5/S6's markers: report `needs-decision` rather
               than editing the script to suit the case.
             - Do not add a fourth deriver, and do not "helpfully" refactor the three into one.
             - Do not let any case create a lock in the real temp base.
             - Do not weaken, delete, skip, reletter, renumber, or reorder any case.
             - Do not touch README.md prose, .github/, docs/loop/checks.md, spec.md,
               decisions.md, or any other docs/loop/<unit>/ directory.
             - Do not introduce an env var, threshold, default, or suggested value.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  S6 -- cutting this before the reader exists would freeze a two-deriver list and
             leave the third free to diverge in silence, which is the exact failure SL12 is for.
             (And S5 transitively, for the blocks themselves.)
```

### S8 — Measure what this unit costs an appending invocation, before and after, on one host
```
Owner:       loop-build   (read-only against the code; markdown only)
Context:     spec.md SL6 in full -- "Whatever work the change adds to an appending invocation --
             INCLUDING ANY PATH RESOLUTION THE RELOCATION INTRODUCES -- is stated AS NUMBERS,
             before and after, on one host", and "Never a claim that the added work is
             negligible"; SL10's one-green-run-is-one-sample discipline.
             docs/loop/eviction-cap-not-honoured-under-contention/measure-e8-after.md -- READ
             IT FOR METHOD ONLY (payload built OUTSIDE the timed interval; one `bash
             record-cost-event.sh` per trial under a fresh throwaway CLAUDE_PROJECT_DIR; the
             over-cap arm re-seeded before each trial so every trial runs a full convergence
             loop; n=20 per arm; host and sha stated). ITS FIGURES ARE NOT YOUR BASELINE: they
             were measured at a different sha. Measure your own before-half.
             The pre-change sha for this unit is dea7408 (the G0 spec commit) unless a neighbour
             unit has since changed scripts/record-cost-event.sh -- check, and state the sha you
             actually measured against.
             scripts/record-cost-event.sh as changed by S3 and S5; hooks/hooks.json (read only)
             for which arrival is the frequent one in a real session.
Constraints: - FOUR ARMS, n=20 each, same host, method identical to measure-e8-after.md's:
                 (a) appending invocation, ledger under cap
                 (b) appending invocation, ledger over cap (full convergence loop)
                 (c) an arrival that appends nothing (a duplicate finish), ledger over cap --
                     the arrival path now resolves the relocated path too
                 (d) an appending invocation with the base UNUSABLE, so the degraded branch of
                     the derivation is the one being timed -- the branch a squatted or missing
                     base puts every real invocation on, and the one nobody would otherwise
                     measure
             - BEFORE AND AFTER, BOTH MEASURED BY YOU, at two named shas. Obtain the pre-change
               scripts read-only with `git show <sha>:path` into a temp file; never checkout,
               branch, stash, or reset.
             - A NUMBER, NEVER AN ADJECTIVE. mean, median, min, max, n per arm per version.
               "Negligible", "small", "no measurable difference" are refused outright.
             - FALSIFIABLE, AND YOU MAY FALSIFY IT: if an appending arm's after-figures sit
               outside the before arm's own observed min-max spread, SAY SO PLAINLY and return
               `needs-decision`. L7 is not traded, and a cost this unit put on the append path
               without noticing is a decision for a human at a gate, not a rounding exercise.
             - NAME WHAT IS PAID FOR WHAT: separate the trap's cost (S3) from the path
               resolution's (S5) if the arms let you, and say plainly if they do not.
             - Counts, never rates. 20 trials is 20 samples, not a distribution to extrapolate.
             - Markdown only: one new file, no code, no case, no literal change.
             - Never the repository's own .claude/; throwaway CLAUDE_PROJECT_DIR and throwaway
               TMPDIR per trial.
Output:      docs/loop/stale-evict-lock-permanently-defeats-the-cap/measure-sl6-append-cost.md
Done when:   That file states, in numbers, four arms before and after with n/mean/median/min/max
             each, both shas, the host, the method and where it matches measure-e8-after.md's,
             and one explicit verdict on whether an appending invocation's own cost moved.
Test set:    4 checks. THE PROOF IS A MEASUREMENT, NOT A HARNESS CASE, and the file says so: a
             timing assertion in this suite would be flaky on a shared runner and would go red
             for reasons no diff explains. Selection rule: one check per way this record could
             mislead someone who cannot re-run it.
               1. every arm carries n, mean, median, min, max, for BOTH versions -- no arm
                  summarised in prose                                              [SL6]
               2. the verdict states whether each appending arm's after-figures sit inside the
                  before arm's own min-max spread, arm by arm                      [SL6, L7]
               3. arm (d) is present -- the degraded branch is timed, not assumed equal to the
                  relocated one                                                   [SL6, SL13]
               4. the method section names each point where it matches measure-e8-after.md's
                  and each where it could not, so a second person can re-run it     [SL6]
             Fails now: no before-figure exists at this unit's own sha, no figure exists for a
             path that resolves a relocated lock, and SL6 has nothing to be answered with except
             an adjective.
             Passes after: four arms, two versions, forty figures, one method section, one
             explicit verdict.
Do NOT:      - Do not change any script or case to improve a number; report it and return
               `needs-decision`.
             - Do not cite measure-e8-after.md's figures as your before-half.
             - Do not measure in a container or VM, or on another host, and present it as
               comparable.
             - Do not state a rate, a percentage, or an expectation.
             - Do not `git checkout`, branch, stash, or reset to obtain the pre-change scripts.
             - Do not write to this repository's own .claude/, and do not leave locks in the
               real temp base.
             - Do not edit scripts/, tests/, README.md, .github/, docs/loop/checks.md, spec.md,
               decisions.md, or any other docs/loop/<unit>/ directory.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  S6 -- the last slice that changes code. Logical, not textual: this slice shares no
             file with any other. (S3 and S5 are what it measures; S7 adds no code.)
```

### S9 — Record what this unit foreclosed, what it did not fix, and whose the remaining evidence is
```
Owner:       loop-build
Context:     docs/loop/decisions.md -- APPEND beneath S2's entry, which this one extends and
             never rewrites.
             spike-sl11-base-clearing.md (S4) and measure-sl6-append-cost.md (S8), for the
             evidence and the number.
             This slices.md -- the Pinned contracts table and "How SL12 and SL13 are cut apart",
             which is where the choices being recorded were actually made.
             spec.md SL2, SL6, SL7, SL10, SL11, SL13, and the Handoff section (the
             append-versus-trim loss window, which this unit deliberately does not open).
Constraints: - RECORD WHAT S2's ENTRY COULD NOT KNOW, because these were G1's and the build's
               choices, not the gate's:
                 * the location, the rule that derives it, and why it is per-boot and not
                   per-run, in section 4(a)'s terms;
                 * S4's evidence, including -- if the base clears by AGE -- the interval as a
                   number, the statement that it is an OS-owned staleness threshold this project
                   did not choose, cannot see from its own code, and cannot test, and SL5's
                   live-holder guarantee RE-ARGUED against it (SL11(c): the weakest joint in the
                   amendment, named rather than hidden);
                 * what happens to a lock at the OLD path: inert, not removed by this code
                   (SL13);
                 * S8's measured figure, as a number, and whether an appending invocation's own
                   cost moved;
                 * the marker-delimited derivation chosen INSTEAD of a shared library function,
                   and why: the hook writer sources nothing, and putting the lock's existence
                   behind a file read that can fail leaves only "no trim" or "trim without a
                   lock" as degradations (OQ3);
                 * /cost as the report's home, and the refusal of a one-shot marker -- it would
                   be another orphanable `mkdir` directory with the failure mode this unit
                   exists to reduce (OQ5);
                 * the two limits this unit accepted knowingly: the predicate's TOCTOU, left
                   open deliberately, and the second-uid squat, argued from the predicate rather
                   than observed because it is not constructible in this suite;
                 * the `chmod 000` degradation arm not required, because a suite run as root
                   would defeat it.
             - STATE WHAT IS STILL NOT FIXED, IN THE SAME ENTRY: a kill class this repository
               cannot catch remains; the one kill it has actually recorded (a machine sleep,
               conventions.md) is NOT established to be catchable; and a leak inside one boot
               defeats the cap for the rest of that boot, which on a machine that sleeps rather
               than reboots can be weeks. Never fixed, closed, resolved, or prevented. The
               strongest phrasing available is "permanence bounded by uptime, and a silence
               ended" -- and only if S4's evidence supports it; if it does not, say THAT.
             - STATE SL10 AS OUTSTANDING AND WHOSE IT IS: a real pushed run on both guarding
               platforms is the human's, after the group merges, and ONE GREEN RUN IS ONE
               SAMPLE. Do not write a sentence that reads as though merging closed it. Same for
               SL11's reboot half: the marker paths S4 left, and the human's `ls`.
             - STATE THAT THE HANDOFF IS STILL NOT OPENED: the append-versus-trim loss window
               (a line landing between a trimmer's `tail` and its `mv`) is a different fault
               with a different mechanism, unreproduced, and this unit did not touch it.
             - APPEND. Do not rewrite, reword, reorder, or re-date S2's entry or any other.
             - Markdown only, one file, no case, no literal change.
Output:      docs/loop/decisions.md (appended beneath this unit's earlier entry).
Done when:   A future session reading decisions.md alone can see where the lock lives and why,
             what evidence the per-boot claim rests on and what it does not, what this unit cost
             an appending invocation as a number, which alternatives were foreclosed at G1 and
             why, which two limits were accepted knowingly, and that the two-platform run and
             the reboot observation are the human's and still open.
Test set:    1 check, and it is a READ, not a harness case -- same reason as S2's: nothing greps
             decisions.md, and a grep case would freeze the prose of the file whose value is
             being written freely. Selection rule: this entry's only failure mode is silence
             about something the build learned, so the check is completeness against the list
             above.
               1. every bullet in the Constraints list appears with its reason; S8's figure is
                  present AS A NUMBER; any age interval is present as a number with SL5
                  re-argued; SL10 and SL11's reboot half are named as the human's with
                  one-green-run-is-one-sample stated; and the Handoff is named as still closed
                                                  [SL2, SL6, SL7, SL10, SL11, SL13, and SL1]
             Fails now: S2's entry records what G0 decided and none of the build's own choices,
             because none of them had been made when it was written; no figure and no evidence
             about the base exists in decisions.md at all.
             Passes after: one appended entry carrying the location and its rule, S4's evidence
             with its limits, S8's number, the G1 foreclosures, the two accepted limits, and two
             outstanding human actions.
Do NOT:      - Do not rewrite, reword, reorder, or re-date any existing entry, including this
               unit's own earlier one.
             - Do not describe the leak as fixed, closed, resolved, or prevented, and do not
               write "bounded by uptime" if S4's evidence does not support it.
             - Do not claim SL10 as met, and do not describe the change as verified on CI.
             - Do not state a rate or a percentage anywhere.
             - Do not adopt, recommend, or make configurable the OS's reaping interval; record
               it.
             - Do not open the Handoff observation, and do not fold it into this entry as work.
             - Do not edit scripts/, tests/, README.md, .github/, docs/loop/checks.md, spec.md,
               the two evidence files, or any other docs/loop/<unit>/ directory.
             - Do not add a harness case over decisions.md.
             - Do not push, dispatch, re-run, cancel, or tag anything.
Depends on:  S8 (the entry carries its number) and S2 (it appends beneath that entry, never
             rewriting it). S4's evidence transitively.
```

---

## Self-audit against the five-point G1 test

Run on my own bench before this reached the gate. Anything with two owners, no nameable test set,
obvious multi-commit scope, an empty `Do NOT`, or a dependency on something later in the list went
back.

| Test | S1 | S2 | S3 | S4 | S5 | S6 | S7 | S8 | S9 |
|---|---|---|---|---|---|---|---|---|---|
| **1. One owning agent** | `loop-build` | `loop-build` | `loop-build` | `loop-build` | `loop-build` | `loop-build` | `loop-build` | `loop-build` | `loop-build` |
| **2. One commit's worth** | Two header comments + 2 cases. The second header is the same sentence for a reader of the other writer, not a second deliverable | One appended entry | Handler + flag in both writers + the 3 cases that prove it. Splitting code from cases would commit either a red suite or an untested fix | One markdown file | One rule, one predicate, two writers, one harness sweep — indivisible, see below | Reader + 3 cases | Harness only, 3 cases | One markdown file | One appended entry |
| **3. Independently testable** | 2 cases; red today because neither header mentions an unreleased lock and no claim-word guard exists | 1 check, declared a **read** rather than dressed as a case | 3 cases; 2 have no code path today, the 3rd is declared a regression guard rather than presented as red | 4 checks; red today because `spec.md` records the property unestablished in either direction | 5 cases; 1 and 5 red today, 2–4 have no code path | 3 cases; red today because `/cost` has no notion of the lock | 3 cases + a **mutation** observation, which is the only red available and is required in the return | 4 checks; red today because no figure exists at this unit's sha | 1 check, declared a read |
| **4. Criteria as observable behaviour** | What a reader of each header learns; what no sentence in the repo may say | What a future session can reconstruct from `decisions.md` alone | A killed holder leaves no lock; a non-holder removes nothing | What the record states and how each row is labelled | A lock held at the derived path defeats a trim; an unsafe base still yields a lock, beside the ledger | What a person running `/cost` learns, and that nothing changed on disk | One file's edit turns the suite red | Forty figures and one explicit verdict | What a future session can reconstruct |
| **5. Dependencies explicit** | `nothing` | `nothing` | `S1`, both reasons named | `nothing` | `S3` + `S4`, both reasons named | `S5`, reason named | `S6`, reason named | `S6`, named logical-not-textual | `S8` + `S2` |

**Set sizes: 2, 1, 3, 4, 5, 3, 3, 4, 1.** `S5` at five is `test-design`'s *"large, worth a second
look"* band and it got one. The five are **branches of one rule** (relocated; base absent; base not a
directory; parent occupied) plus **one migration state a real user will actually have on disk** (a
lock at the old path) — not five behaviours. The cut that would split it is exactly the one
*How `SL12` and `SL13` are cut apart* refuses: shipping the derivation before its predicate leaves a
merged commit in which a stranger can permanently defeat the cap, and shipping the predicate untested
leaves `SL13` as a comment.

**Sent back to myself during this pass, recorded because the rejected cut is the useful part:**

- **A "relocate" slice and a separate "degrade" slice.** The obvious reading of the spec's warning,
  and wrong: the predicate is a clause of the derivation, so one order ships §4(d)'s new door on
  purpose and the other has nothing to degrade from. `SL12`'s *check* is what separates cleanly, and
  that is `S7`.
- **One "hygiene" slice covering the trap and the relocation.** Rejected: two mechanisms addressing
  different halves (§4(f) — frequency and duration), two independent red-before constructions, and a
  diff nobody could read as one commit.
- **Folding `S4`'s evidence into `S5`.** Rejected for the three reasons under *The reboot-property
  evidence is its own slice* — decisively, because `S4` can invalidate `S5`'s premise and a builder
  holding both will read the evidence as licensing the code it is halfway through.
- **A single `decisions.md` slice at the end.** Rejected: `SL2` is fully determined at G0 and is the
  honest minimum that stands even if the unit halts at `S4`'s gate. Two touches of one file's tail,
  ordered, is the cost of that and it is worth paying.
- **A harness case over `decisions.md`'s prose.** Rejected, following this repository's own precedent:
  it would freeze the wording of the one file whose value is being written freely.
- **A "reports it only once" case for `S6`.** Rejected: bounding is structural (only a human-invoked
  route prints), and asserting it would require the marker `OQ5` forbids.

---

## Open questions — recorded, not resolved

The human is not available to this pass. Each of these is surfaced in the return rather than decided
quietly.

1. **`SL11`'s reboot half cannot be fully observed by any builder, and this is the unit's thinnest
   evidence.** A real reboot of the maintainer's host is the human's action; a CI runner cannot be
   rebooted at all, and a fresh VM per run is not the same observation. `S4` splits its rows into
   observed-here / investigation-grade / not-obtainable-by-a-builder and leaves named markers so the
   human's part is one `ls`. **If the human is unwilling to reboot, `SL11` is met only in part, and
   `SL1`'s wording must stay at "not enforced again until the lock is removed" rather than reaching
   "bounded by uptime".**
2. **The one-host observation already made at this gate points the wrong way.** Both candidate bases
   on the maintainer's host are disk-backed on the same APFS volume, and `/private/tmp` is
   world-writable and sticky — so on macOS the per-boot property is not a property of the filesystem,
   and §4(d)'s squatting surface is not Linux-only. `S4` must reproduce and settle this; it is the
   most likely route by which relocation turns out to buy only `SL11`(c)'s age concession.
3. **The predicate's TOCTOU is deliberately open.** Between the safety check and the `mkdir` of the
   lock, another party could replace the parent. `spec.md` names it and declines to specify it away;
   `S5` is forbidden from closing it with any inference, and a builder that believes it must be closed
   returns `needs-decision`. *This is a real residual: on a world-writable base it is a narrow window
   onto the same permanent-defeat route the fallback exists to prevent.*
4. **The true second-uid squat is argued, not observed.** A directory owned by another user is not
   constructible in this suite without a second uid or `sudo`, so `S5` covers its observable proxy and
   `S9` records the gap. A human who wants it observed is asking for a privileged fixture, which would
   be its own decision.
5. **Should `/cost`'s block be gated on the ledger being over cap?** `spec.md`'s failure-mode table
   hints at it (*"under cap … nothing worth alarming anyone about"*). `S6` is pinned **not** to gate
   it, because gating needs the cap's value inside a reader whose charter says every figure comes from
   `cost-ledger-lib.sh` — a fourth copy of that parser. Informational wording carries the under-cap
   case instead. **Reversible at the human's word; a builder may not reverse it.**
6. **`cksum` is pinned as the digest, and it is a G1 choice rather than the spec's.** It is POSIX and
   present on both guarding platforms, unlike `sha256sum`/`shasum`. If the human prefers a different
   derivation the pin moves; a builder returns `needs-decision` rather than substituting one.

---

## Cross-unit landing order

Three units are live at once, and two of them are being sliced by other agents **right now**.

| Shared surface | This unit | `cost-log-section-parse-error-on-macos-ci` | `resumed-invocation-never-reaches-the-ledger` |
|---|---|---|---|
| `tests/guardrails.test.sh` | eviction section (~:380–600), cost-report section (~:1000–1080) | its `cost_scan` / `write-cost-log-section` sections | its ledger-writer sections |
| `README.md:169`'s case-count literal | S1 +2, S3 +3, S5 +5, S6 +3, S7 +3 | every case-adding slice | every case-adding slice |
| `docs/loop/decisions.md`'s end-of-file | **S2 and S9** | its own closing entry | its own closing entries (`SP5`, `RB1`) |
| `scripts/record-cost-event.sh` | S1, S3, S5 | — | **yes** — which is why it is ordered after |
| `scripts/cost-report.sh` | **S6** | reads `cost-ledger-lib.sh`, does not edit `cost-report.sh` | — |

- **`cost-log-section-parse-error-on-macos-ci` — safe in parallel, on the scripts.** Its files
  (`scripts/cost-ledger-lib.sh`, `scripts/write-cost-log-section.sh`) are disjoint from every file
  this unit touches, and both are on every slice's `Do NOT`. **The harness, the README literal, and
  `decisions.md`'s tail are NOT disjoint** — the delta rule is what makes those safe, not luck. Two
  lanes from different units in flight at the same moment is the one unsafe arrangement; if it is
  unavoidable, land the harness-touching one first and merge `main` into the other before it writes a
  line.
- **`resumed-invocation-never-reaches-the-ledger` — after this unit, deliberately.** It touches
  `scripts/record-cost-event.sh`, and it is ordered after so it adds records to a working cap rather
  than a defeated one. No slice above is edited in service of it, and no shared refactor is undertaken
  to accommodate it.
- **Either order survives, because of the delta rule.** No slice above carries an absolute case count.
  A lane building after a neighbour's merge computes `<live literal> + <its delta>` without being
  told.

---

## Criterion traceability — assigned, human-owned, or explicitly cross-cutting

Nothing is dropped, and nothing is claimed as assigned that is not.

| Criterion | Where it stands after this cut |
|---|---|
| **SL1** — the orphan case and this unit's honest limit written where the cap's promise lives; nothing calls the leak fixed | **`S1`**, which also ships the **claim-word guard case** that every later slice must keep green. `S3` and `S5` each amend the sentence as they change what is true; `S9` restates the limit in `decisions.md`. |
| **SL2** — the staleness question answered on the record, every candidate named | **`S2`**, with all seven of §1's candidates, §0's `rmdir` catch as the reason pid-in-lock is rejected, and the unbounded-hold argument as the reason age is wrong in principle. **`S9`** adds what the build learned. |
| **SL3** — an orphaned lock is no longer unenforced *and* unannounced | **Split, both halves named.** Hygiene: **`S3`** (a catchable kill releases). Discoverability: **`S6`** (`/cost`), whose shape is **settled at this gate** — see *`SL3`'s reporting shape, settled here*. |
| **SL4** — red before green, both shas, trial count | **Cross-cutting and per-slice: `S3`, `S5`, `S6`, `S7`.** Each reproduces its **own** red, 5 trials per version, pre-change scripts obtained read-only via `git show`. Citing another slice's red is explicitly not a substitute. `S7`'s red is a **mutation**, recorded in its return, because its paths agree the moment they are written. |
| **SL5** — no lock ever taken from a live holder, by any route | **`S3`** (the handler releases only a lock this process created — case 3), **`S5`** (the old-path lock is not removed; the fallback never runs lockless), **`S4`** (the base's own reaping re-argued against a live holder), and structurally by the pinned no-steal contract. The eviction section's cases (f), (g), (h), (i) are unmodified in assertion throughout. |
| **SL6** — `L7` not traded, and the cost measured where it is paid, as numbers | **`S8`**, four arms before and after at two named shas, including the **degraded branch** nobody would otherwise time; falsifiable, with `needs-decision` if an appending arm moved outside its own before-spread. `S3` and `S5` are forbidden from adding any wait, and cases (g)/(i) are the standing guard. |
| **SL7** — no new threshold, default, or suggested value | **Vacuous by construction, evidenced rather than asserted.** No slice adds a `LARAVEL_LOOP_*` variable — including no opt-out for relocation; `S3`, `S5`, `S6` each grep their own diff for `LARAVEL_LOOP_` and new numeric literals and report the result. The one age-like quantity is the OS's, **recorded by `S4` and `S9`, never adopted**. |
| **SL8** — both writers changed, and the record says why the earlier rejection does not transfer | **`S1`** (both headers), **`S3`** (both handlers), **`S5`** (both derivations, same commit), **`S7`** (the case that covers both), **`S2`** (the sentence: a leak needs an interruption, not contention). |
| **SL9** — nothing already guaranteed regresses | **Cross-cutting, per slice.** Every lane returns the full suite green with the eviction section's cases (a), (b), (f), (g), (h), (i), (j) unmodified, `shellcheck -S warning scripts/*.sh` clean, exit 0 on every path, and the case total **up** by its stated delta — never down. |
| **SL10** — green on both guarding platforms, on a real pushed commit, one green read as one sample | **The human's, post-merge. No slice claims it.** A builder does not push, and no container or local run substitutes. What to read: `guardrails` and `guardrails-macos` both reporting an identical `total: N passed, M failed`. `S9` records it as outstanding so merging cannot be mistaken for closing it. **This matters more here than usual: bash 3.2's trap delivery and each platform's temp base are exactly what differ.** |
| **SL11** — the location named, its per-boot property observed on both platforms, any age reaping recorded | **`S4`** for the evidence, **`S9`** for the record — and **partly the human's**, which is stated rather than glossed: the reboot observation is not obtainable by a builder on either platform. `S4` is licensed to return `needs-decision`, and absent the evidence the bounded-by-uptime claim is made nowhere. |
| **SL12** — one derivation, and a divergence is red | **Split deliberately: `S5`** owns the rule (marker-delimited, both writers, one commit), **`S7`** owns the *check* (extract each deriver's block, evaluate under identical inputs, prove by mutation). `S6` adds the third and last deriver, which is why `S7` follows it. |
| **SL13** — the old location and an unusable new one both have stated behaviour | **`S5`**, with its five cases: the relocated branch, three root-free degradation arms, and the old-path lock's inertness. Its two named limits — the second-uid squat argued rather than observed, and the predicate's TOCTOU left open — are recorded by **`S9`** rather than hidden. |

---

## Riskiest slice: **S5**

Not `S4`, and the distinction is the same one this repository drew once before: `S4` carries the
highest *uncertainty* — it may well find the base has no per-boot property at all — but its output is
an argument in a markdown file that lands back at a human gate, and its worst outcome is that `S5` is
never briefed. Uncertainty that has been deliberately contained is not the risk to nominate.

**`S5` is riskiest because it is the only slice that can make things worse in three different ways,
two of which a green suite would not reveal.**

1. **It can ship a new permanent-defeat route.** Get the predicate wrong — or make it lenient because
   a case is awkward — and on a world-writable base a stranger pre-creates the lock name, `mkdir`
   fails forever, nobody trims, and the owner cannot even remove it. That is the same observable this
   unit exists to reduce, arriving by a new door, and this time not clearable by the person affected.
   The mitigations are the pinned predicate, the named degradation arms, and a `Do NOT` that forbids
   "no lock" in words — none of which removes the risk, all of which make it visible.
2. **It can make two existing cases vacuous, and they will still be green.** The harness holds the
   lock by hand in twelve places. After relocation, **case (g)** (an append lands while the lock is
   held) and **case (h)** (the lock is not left behind after a failed `mv`) both still *pass* if they
   hold or inspect a path the writer no longer uses — they simply stop asserting anything, silently.
   Cases (f) and (i) would go red and announce themselves; (g) and (h) would not. This is the line
   worth reading twice at this gate, and it is why the envelope requires the lane to state, per case,
   what it did to confirm each still constructs what it claims.
3. **The tidiest-looking implementation is the one this cut forbids.** Two writers, one rule — the
   obvious tidy answer is a shared function in `cost-ledger-lib.sh`, and it is the answer `OQ3`
   rejected twice, because it puts the lock's very existence behind a file read that must not be able
   to fail on the hook path, whose only degradations are "no trim" (the leak) or "trim without a lock"
   (the loss). It will look like simplification. Hence the marker-delimited pin and a `needs-decision`
   instruction rather than a hope.

**Runner-up: `S4`**, for the quieter failure — a record that reads as evidence but is a citation in
observation's clothing. The unit's whole bounded-by-uptime claim rests on it, `spec.md` says outright
that citing documentation is not establishing it, and the one observation already available points
toward "no boot-clearing property on macOS". Its envelope demands per-row labelling and explicitly
licenses `needs-decision` for exactly this reason.

**Not nominated, and worth saying why: `S6`.** It is the slice most likely to be *wordsmithed* at G2
— but its worst outcome is a sentence a human rewrites, and its `Do NOT` list makes the two ways it
could actually do harm (repairing something, or determining the holder is dead) unmissable.

**And one honest residual nobody's slice closes:** the append-versus-trim loss window in `spec.md`'s
*Handoff* — a line landing between a trimmer's `tail` and its `mv` is lost today, with the lock
working exactly as designed. It is not folded into any slice, it is not fixed in passing, and `S9`
records that it stays closed. It bears on `H3` and a lost finish record has no automatic recovery, so
it reads like its own intent — which is exactly what `spec.md` says it is.

---

# G1 — Slices — stale-evict-lock-permanently-defeats-the-cap

```
Slices: 9  ·  Parallel: 3 at t0 (S1 ∥ S2 ∥ S4)  ·  Critical path: S1 → S3 → S5 → S6 → S7 → S8 → S9
Case-count deltas: S1 +2 · S2 0 · S3 +3 · S4 0 · S5 +5 · S6 +3 · S7 +3 · S8 0 · S9 0  (group +16,
                   computed from main at build time — never an absolute: README.md:169 reads 466
                   now and two neighbour units are moving it)
Riskiest: S5 — the only slice that can make things worse. A lenient safety predicate ships §4(d)'s
          squatting route as a NEW permanent defeat, unclearable by the owner; and after the lock
          moves, cases (g) and (h) still pass while asserting nothing if they hold the old path.
          Its tidiest-looking implementation (a shared function in cost-ledger-lib.sh) is the one
          OQ3 rejected twice.

S1 · say what an orphaned holder does to the cap, in both writers' headers — true of today's
     scripts; ships the claim-word guard (SL1)                            · depends on nothing
S2 · answer the staleness question on the record: no steal, ever, seven candidates, why age is
     wrong in principle (SL2, SL8)                                        · depends on nothing
S3 · release the lock on INT/TERM/HUP, both writers, only a lock this process created
     (SL3 hygiene, SL5)                                                        · depends on S1
S4 · establish by OBSERVATION what the base does with a lock across a reboot and across time,
     both platforms — read-only; may return needs-decision (SL11)         · depends on nothing
S5 · relocate: one marker-delimited derivation per writer, degrading to today's path when the
     base is unsafe (SL12 rule, SL13)                                    · depends on S3 + S4
S6 · report a present lock in /cost, never inferring death (SL3 discoverability)· depends on S5
S7 · make a divergence between the three derivations red, proven by mutation (SL12 check)
                                                                               · depends on S6
S8 · measure the appending path before/after, four arms, two shas (SL6)         · depends on S6
S9 · record the location, S4's evidence and its limits, S8's number, the G1 foreclosures
     (SL11 record, SL2 addendum)                                          · depends on S8 + S2

EVIDENCE GATE inside the order: S5–S7 are cut but HELD until S4 returns and you have read it.
   SL11 forbids the bounded-by-uptime claim without observed evidence, and S4 can invalidate the
   base outright. This is not the deferral G0 overruled — OQ6 stays in this unit, envelopes written.

Human-owned, no slice claims it: SL10 — a real pushed run, both platforms, identical totals, after
   the group merges (one green run is one sample). And SL11's reboot half — S4 leaves named markers
   in each base; the observation itself is your `ls` after your next reboot.

Settled at this gate: SL3's reporting shape — /cost, human-invoked, bounded structurally, no
   marker, no record type, no repair, and no sentence that determines the holder is dead.

Open, recorded, not decided: the reboot half above; the predicate's TOCTOU (deliberately open);
   the second-uid squat (argued, not observable here); whether /cost's block should be gated on an
   over-cap ledger (pinned NOT gated — gating needs a fourth cap parser in the reader); cksum as
   the digest (a G1 choice, not the spec's).

⚠ One observation already made at this gate, one host, one sample: on macOS both candidate bases
   ($TMPDIR and /tmp) are disk-backed on the same APFS volume, and /private/tmp is world-writable
   and sticky. The unit's bounded-by-uptime premise is in genuine doubt on your own platform, and
   §4(d)'s squatting surface is not Linux-only. S4 must settle it, not inherit it.

1. Approve — brief S1, S2 and S4 in parallel now; S3 after S1; read S4 before briefing S5
    (recommended)
2. Re-slice — say which, and why
3. Spec is wrong — back to loop-spec
```
