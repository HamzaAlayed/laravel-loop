# Slices — ship-gate-blind-to-ci

**Status: awaiting G1.** Spec approved at G0 with all three open questions resolved. Four
builder slices, one human action. No parallel lanes — see *Order and parallelism*, where the
reason is mechanical rather than a preference.

## What G0 settled — not reopenable here

- **OQ1 → narrow the check, with a marker comment inside the file.** `chmod +x` on the
  library is rejected. No rename of `scripts/cost-ledger-lib.sh`, no deletion of its shebang.
- **OQ2 → the parity check lives in `tests/guardrails.test.sh`.** `scripts/ship-check.sh`'s
  declared gate set stays **exactly three**. A fourth gate is rejected; "make ship-check state
  its blind spot" is rejected. `ship-check.sh` is not edited by any slice below.
- **OQ3 → A6 as written.** Name v0.2.0–v0.6.0, leave the earliest run's cause `unknown`, no
  investigation slice.

A slice that believes one of these is wrong returns `needs-decision`. It does not decide.

## The seam

The smallest change that delivers observable value is neither the file mode nor the document.
It is **a command a maintainer can run that fails on this tree today and names
`scripts/cost-ledger-lib.sh`** — A2 verbatim, and the thing that has been missing for twelve
runs. So S1 is the rule and its checker, and it lands with the harness green while the tree is
still non-conforming: the check exists and correctly reports the tree as wrong *before*
anything is fixed. S2 then conforms the tree, S3 makes the pushed-commit checks defer to the
same rule, S4 writes down what the two sets are.

## Contract pinned across slices

Every slice reads this table rather than inventing its own version of any row.

| Item | Value | Set by | Read by |
|---|---|---|---|
| Checker path | `scripts/check-script-modes.sh` ¹ | S1 | S2, S3, S4 |
| Library marker literal | `# laravel-loop:sourced-library` ¹ | S1 | S2 |
| Marker match rule | exact full line, **no leading whitespace**, within the file's **first 20 lines** ¹ | S1 | S2 |
| Mode basis | the **committed** mode from `git ls-files -s`, never the filesystem's `[ -x ]` ¹ | S1 | S2, S3 |
| Scope glob | `scripts/*.sh tests/*.sh` — nothing else, ever | S1 | S2, S3 |
| Program mode / library mode | `100755` / `100644` | S1 | S2 |
| Failure output | one line per offending file, containing the path as `git ls-files` prints it | S1 | S2, S3 |
| Parity doc path | `docs/loop/checks.md` ¹ | S4 | — |
| CI step name | `scripts are executable` — **unchanged**, deliberately not renamed ¹ | S3 | S4 |
| Configurables added | **none** — nothing this unit adds reads any environment variable | S1 | S3, S4 |

¹ slicer-chosen; listed again under *Slicer-chosen, overridable at G1*.

**The rule, stated once.** S1 copies this wording into the checker's own header; S4 copies it
into `docs/loop/checks.md`. Neither paraphrases it:

> A file matched by `scripts/*.sh` or `tests/*.sh` is a **library** if one of its first 20
> lines is exactly `# laravel-loop:sourced-library`; every other such file is a **program**. A
> program must be committed at mode `100755`. A library must be committed at mode `100644`.
> Any other combination fails, naming the file.

Applied to the eleven files under `scripts/` and `tests/` today: ten programs
(`block-untested-commit.sh`, `check-budget-gate.sh`, `cost-report.sh`,
`enforce-refine-cap.sh`, `record-cost-event.sh`, `record-recovered-cost.sh`, `ship-check.sh`,
`warn-full-suite.sh`, `write-cost-log-section.sh`, `tests/guardrails.test.sh`) and one library
(`cost-ledger-lib.sh`). Every one is classified; nothing falls through.

**Why one implementation and not two.** A4 says the pushed-commit checks and the local check
must never disagree. Two copies of the rule can only *promise* that; one program both sides
call makes it structural. This is the repository's own precedent, stated in
`scripts/cost-ledger-lib.sh`'s header for the same reason: a report and a gate that each
parsed the ledger independently "could silently disagree, which is exactly the *second
implementation* this file exists to prevent."

**Why the committed mode and not `[ -x ]`.** The runner checks out a commit, so the mode CI
sees is the mode git recorded. A local check reading the filesystem would pass on a
`chmod +x` that was never staged — a new divergence, in a unit whose whole point is closing
one. `git ls-files -s` is also exactly what A5's proof names.

---

### S1 — Add the script-mode rule and the check that enforces it
Owner:       loop-build
Context:     - `docs/loop/ship-gate-blind-to-ci/spec.md` — A2, A5, A7, and the failure-mode row
               "The local check runs outside a git work tree"
             - The pinned contract table above — the rule's wording is not the builder's to choose
             - `.github/workflows/ci.yml` lines 18–22 — the logic this replaces. **Read only**; S3 edits it
             - `scripts/ship-check.sh`'s `run_bounded()` header — house precedent for "bash job
               control only, no GNU `timeout`, holds on bash 3.2"
             - `tests/guardrails.test.sh` — `expect()` near line 27; new cases go in their own
               section at the end, *before* the final `docs (case count)` case, which must stay last
Constraints: - bash 3.2 + coreutils only. No `mapfile`/`readarray`, no associative arrays, no
               `grep -P`, no GNU-only flags, no jq, no python3
             - `shellcheck -S warning scripts/*.sh` stays clean, the new file included
             - The new script is a program: commit it at mode `100755`
             - Read-only: no write outside `mktemp` scratch, no network, no mutating git command
             - The marker literal must never appear as a column-0 comment line inside the
               harness — write fixture files with `printf`, not a column-0 heredoc body, or the
               harness classifies *itself* as a library. The anchor exists for this reason
             - Introduces no environment variable, no threshold, no exempt list, no escape
               hatch, no `--fix` mode (A7; an exempt list is the rot OQ1 rejected)
             - Add **no** case that runs the checker against this repository's own tree — the
               tree does not conform until S2, and a red harness cannot be committed
             - Bump README's Development-section case count by the number of cases added
Output:      - `scripts/check-script-modes.sh` (new, mode 100755, rule in its header verbatim)
             - one new section in `tests/guardrails.test.sh` — 7 cases
             - `README.md` Development case count bumped
Done when:   Run at the repo root today the checker exits non-zero and prints a line containing
             `scripts/cost-ledger-lib.sh`; run against a conforming fixture it exits 0 and names
             no file.
Test set:    7 cases. Selection: file-kind × committed-mode is 2×2, taken exhaustively (cheaper
             than pairwise at this size), plus one anchoring negative, one environment guard,
             one A7 assertion.
             1. unmarked program at `100644` → non-zero, output names the path
             2. unmarked program at `100755` → exit 0
             3. marked library at `100644` → exit 0 (the exemption OQ1 chose)
             4. marked library at `100755` → non-zero, output names the path (the rule is
                bidirectional: a library asserting it is runnable is also wrong)
             5. marker present but unanchored — indented, or below line 20 → classified as a
                program, so `100644` fails (closes the self-exemption trap)
             6. run outside a git work tree → says so, exits non-zero, names no file
             7. `LARAVEL_LOOP_*` exported with arbitrary values → byte-identical output and exit
                code to the run without them, and no `LARAVEL_LOOP` literal appears in the script
             Fails today: `scripts/check-script-modes.sh` does not exist, so all seven error.
Do NOT:      Edit `scripts/ship-check.sh`, `.github/workflows/ci.yml`,
             `scripts/cost-ledger-lib.sh`, `CHANGELOG.md`, or any existing harness case. Do not
             `chmod` any tracked file. Do not create `docs/loop/checks.md` (S4 owns it). Do not
             add an env var, an exempt list, or a repair mode.
Depends on:  nothing

---

### S2 — Declare `cost-ledger-lib.sh` a library and make the tree conform
Owner:       loop-build
Context:     - `scripts/cost-ledger-lib.sh` lines 1–8 — shebang, `# shellcheck shell=bash`,
               `# shellcheck disable=SC2034` and the paragraph explaining why SC2034 is file-wide
             - The pinned marker literal and anchor
             - A5's proof command: `git ls-files -s scripts/*.sh tests/*.sh`
Constraints: - Insert the marker as its own full-line comment, after the shebang and within the
               first 20 lines. Do not delete or alter the shebang (G0). Do not rename the file
               (G0). Do not change its mode — `100644` is the conforming state under the rule
             - Do not drop or reorder the two `# shellcheck` directives; SC2034 is file-wide and
               load-bearing. A comment sitting between them and the code is fine
             - No behaviour change: the file is sourced, and a comment cannot change what it
               sets. `bash scripts/cost-report.sh` still runs and every existing cost-report /
               cost-lib case passes unmodified
             - Bump README's Development-section case count by 2
Output:      - one comment line in `scripts/cost-ledger-lib.sh`
             - 2 new harness cases; `README.md` count bumped
Done when:   `bash scripts/check-script-modes.sh` exits 0 at the repo root, and the rule's
             classification of every file the scope glob matches equals the mode
             `git ls-files -s` reports for it.
Test set:    2 cases. One input, one meaningful state each — the small end of the dial, correctly.
             1. checker exits 0 over this repository's own tree — fails today, because
                `cost-ledger-lib.sh` is unmarked at `100644`
             2. A5: for every file the glob matches, **iterated not hardcoded**, the rule's
                classification and `git ls-files -s`'s mode agree — fails today for the same
                file. Iterated deliberately: the count is eleven today and twelve once S1's
                script lands, so a literal `11` would be wrong the moment it was typed
Do NOT:      `chmod +x` this file (the rejected OQ1 option 1 — the whole point is that a file
             which must never be run directly must not claim to be runnable). Mark any other
             file. Edit `ci.yml`, `ship-check.sh`, or any existing harness case. Add a second
             marker convention (a naming rule, a shebang rule, an exempt list) alongside this one.
Depends on:  **S1** — the marker is inert without the rule that reads it, and both of this
             slice's cases invoke the checker. Not file overlap: a genuine ordering dependency.

---

### S3 — Point the pushed-commit check at the same rule, and prove the two answers cannot differ
Owner:       loop-build
Context:     - `.github/workflows/ci.yml`, `guardrails` job, step `scripts are executable`
               (lines 18–22) — the only step this slice touches
             - A4 and its proof; the spec's non-goal "keeps the one job and the same three steps"
             - `tests/guardrails.test.sh` — the `ship-check.sh` section near line 2418 shows the
               house pattern for git-repo fixtures under `mktemp -d`
Constraints: - One job, three steps, same three step names. Do **not** rename
               `scripts are executable`: the run history stays comparable and S4's document
               names it as-is
             - The step body becomes an invocation of `scripts/check-script-modes.sh` and
               nothing else. No second copy of the rule anywhere in the YAML
             - The parity cases must execute the step's **own `run:` body, extracted from
               `ci.yml` at run time** (bash + sed, no YAML parser), never a retyped copy. A
               retyped copy makes A4 tautological and lets `ci.yml` drift in silence. Extraction
               yielding nothing is a failure, not a skip
             - `actions/checkout@v4` already gives a real git work tree, so `git ls-files -s`
               works on the runner. Do not add `fetch-depth` or any other checkout option
             - bash 3.2 safe (the extractor too); shellcheck clean; existing cases unmodified;
               bump README's case count by 4
Output:      - edited `scripts are executable` step in `.github/workflows/ci.yml`
             - 4 new harness cases; `README.md` count bumped
Done when:   For both fixtures below, the extracted step body and a direct
             `scripts/check-script-modes.sh` run return the same exit code and name the same
             files — the answers are equal by construction and a case proves the construction.
Test set:    4 cases.
             1. extraction of the step's `run:` body from `ci.yml` yields a non-empty command
                (fail-closed guard on the extractor itself)
             2. parity, fixture holding a marked library at `100644`: extracted-CI answer ==
                direct answer (both exit 0, both silent). Fails today — today's inline loop
                rejects the file the checker accepts
             3. parity, fixture holding an unmarked program at `100644`: extracted-CI answer ==
                direct answer (both non-zero, both naming the same path)
             4. structural: the step invokes `scripts/check-script-modes.sh` and retains no
                `[ -x` loop of its own — catches an inline copy that happens to agree on these
                two fixtures. Fails today: `ci.yml` names no checker
Do NOT:      Add, remove, or rename a step or a job. Add a matrix, a cache, a runner change, a
             linter, a coverage step, a scheduled trigger, or a status badge. Edit
             `scripts/ship-check.sh` (no fourth gate — OQ2). Make CI invoke `ship-check.sh`.
             Touch the `shellcheck` or `guardrail tests` steps. Add a network call anywhere.
Depends on:  **S2** — merging this before the tree conforms turns the pushed-commit checks red
             on the checker's very first run, which is the exact state this unit exists to end.

---

### S4 — Write the one place that says which checks run where, and what the gap already cost
Owner:       loop-build
Context:     - A3 and A6; `docs/loop/ship-gate-blind-to-ci/intent.md` for the version list, the
               run ids, and the `unknown` earliest cause
             - `.github/workflows/ci.yml` as S3 leaves it; `scripts/ship-check.sh`'s header
               lines 4–16, the three declared gates — **read only**
             - `docs/loop/conventions.md` and `docs/loop/decisions.md` — the new file sits beside
               them and matches their tone: the rule, then why it exists
Constraints: - New file `docs/loop/checks.md`. Two enumerations — what runs on the pushed commit,
               what runs locally at G3 — each naming the deltas **in both directions**:
               version-agreement is absent from the pushed-commit side; the mode rule is not a
               ship-check gate and reaches the verdict only indirectly, through gate 1's harness.
               State that indirection as OQ2's chosen cost, not as an oversight
             - The A6 record names v0.2.0, v0.3.0, v0.3.1, v0.4.0, v0.5.0, v0.6.0 as having
               shipped with the pushed-commit checks failing, and records run `31696279581`'s
               cause as `unknown`. Infer no cause for it, from a later run or otherwise
             - The document claims nothing about current CI colour. It is a map of two check
               sets, not a health report (non-goal: no CI-health section, no badge)
             - Link to `spec.md` for the problem statement; do not restate it
             - One pointer line may be added to README's Development section, which today says
               "CI runs both on every push" and is wrong — there are three steps. One line, a
               pointer, nothing more
             - Bump README's case count by 4
Output:      - `docs/loop/checks.md`
             - one pointer line in `README.md`'s Development section; 4 new harness cases;
               `README.md` count bumped
Done when:   Every step name in `ci.yml`'s `guardrails` job and every gate `ship-check.sh`
             declares appears in the document; the document states both deltas and names all six
             affected versions with the earliest cause left `unknown`.
Test set:    4 cases — one per thing that could rot independently.
             1. every `- name:` in `ci.yml`'s `guardrails` job, extracted from the YAML, appears
                in `docs/loop/checks.md` (iterated, so a future fourth step fails this)
             2. all three gate names, extracted from `ship-check.sh`'s own header list, appear
                in the document
             3. the document names the version-agreement check as absent from the pushed-commit
                side, and names gate 1's harness as the only path by which the mode rule reaches
                the G3 verdict
             4. the document names all six versions and records `unknown` for the earliest run
             Fails today: the file does not exist, so all four fail.
Do NOT:      Edit `CHANGELOG.md` or any released entry — no release is amended to have been
             green, and anything touching a published artifact is G4. Add a status badge or a
             README CI-health section. Edit `ci.yml`, `ship-check.sh`, or `spec.md`. State a
             cause for the v0.2.0 run. Restate the spec's problem statement in the new file.
Depends on:  **S3** — the enumeration must match `ci.yml` as resolved, and case 1 reads that file.

---

### H1 — Confirm the pushed-commit checks conclude success (A1)
Owner:       **the maintainer, post-merge. Explicitly not `loop-build`.**

**Why this is not a slice.** A1's only proof is a real run on a real pushed commit. A builder
in a worktree cannot produce one, and a local re-implementation of CI is precisely the evidence
this unit exists to stop people accepting — `docs/loop/conventions.md`: *a green harness never
proves a hook is live*; here, a green local check never proves the pushed-commit checks agree.
No slice below claims A1, and none may be marked as satisfying it.

Done when: S1–S4 are merged to `main`, the merge commit is pushed, and the `guardrails` job
concludes **success** on that commit with all three steps green. The human records the run id
in `docs/loop/ship-gate-blind-to-ci/log.md`.

If it concludes failure, that is not automatically a re-slice: read the failing step first. A
failure in `shellcheck` or `guardrail tests` is a different fault from a failure in
`scripts are executable`, and only the third is this unit's.

## Order and parallelism

```
S1 → S2 → S3 → S4 → H1 (human)
```

Critical path is the whole list. **Parallel set: none** — a finding, not an omission, with two
mechanical reasons:

1. **README's case count is a single shared literal.** The Development section hard-codes the
   harness total (`404 cases` today) and the harness's own final case asserts that number
   equals the live tally. Every slice here adds cases, so every slice edits that one number.
   Two lanes doing it conflict by construction, and the loser's merge leaves the suite red on a
   case whose diff nobody touched.
2. **The chain is real, not layer habit.** S2's cases call S1's script; S3 turns the pushed
   commit red unless S2 has landed; S4 enumerates `ci.yml` as S3 leaves it.

A worktree fan-out would buy nothing: the unit totals one new script, one comment line, four
lines of YAML, one document, and 17 harness cases.

## Traceability

| Criterion | Satisfied by |
|---|---|
| A1 — real CI run concludes success | **H1 — the human, post-merge.** No slice. |
| A2 — a local check that fails and names the file | S1 |
| A3 — one place enumerating both sets, both deltas | S4 |
| A4 — pushed-commit and local answers never disagree | S3 (by construction; S3's cases prove the construction) |
| A5 — the rule is written down and mechanically checkable | S1 (rule + checker), S2 (classification matches the committed tree, iterated) |
| A6 — the red release history is recorded, earliest cause `unknown` | S4 |
| A7 — any configurable ships unset | S1 — none is introduced, asserted by case 7 rather than claimed in a comment |
| A8 — nothing already guaranteed regresses | every slice's Constraints (existing cases unmodified, count never down, shellcheck clean) + the full re-run at G2 |
| A9 — the verdict stays a function of exactly the declared gates | no slice edits `ship-check.sh`. The gate set stays **exactly three**, so no declared-count restatement is due anywhere — not in that file's header, not in README, not in `ship-observe-automation`'s S1/S6. A builder that finds itself wanting to restate a count returns `needs-decision`. |

## Riskiest slice

**S3.** It is the only slice whose correctness cannot be observed before the push. Every other
slice is fully provable by `bash tests/guardrails.test.sh` on the maintainer's own machine;
S3's real subject is a runner nobody here can run, and its cases prove the two answers agree on
fixtures — not that the runner's own invocation succeeds. If S3 is subtly wrong, the local
suite goes green and A1 stays unclosable: this unit's own failure mode, reproduced one layer in.
The mitigation is inside its test set rather than bolted on afterwards — the parity cases
execute `ci.yml`'s extracted `run:` body instead of a retyped copy, so a wrong command line
fails locally rather than on push.

**Runner-up, and the thing I was least sure about: S1's marker match rule.** Anchored
full-line, within the first 20 lines, is chosen so that the two files which must contain the
literal — the checker and the harness — cannot exempt themselves. If a different marker or a
different anchor is wanted, change it here, where it costs one table row; after S2 it is
committed convention inside a shipped file.

## Slicer-chosen, overridable at G1

- `scripts/check-script-modes.sh` as the path and name.
- `# laravel-loop:sourced-library` as the literal, and its anchor.
- The committed mode (`git ls-files -s`) as the basis, rather than the filesystem's `[ -x ]`.
- `docs/loop/checks.md` as the document, with A6 living in it rather than in `CHANGELOG.md`.
- Leaving the CI step name `scripts are executable` unchanged.
- **The shared-script shape itself.** The alternative considered and not taken: keep the rule
  inline in `ci.yml` and have the harness extract and execute it, adding no twelfth script.
  Rejected because a shared program makes A4 true by construction, and because it is this
  repository's own stated precedent (`cost-ledger-lib.sh`'s header, on refusing a second
  implementation). The cost of my choice, which the human should see rather than discover:
  `scripts/` gains a twelfth file, so A5's "all eleven files" reads as twelve on the resolved
  tree. The spec said "currently", and S2's case iterates rather than hardcoding, so nothing is
  falsified — but the number moves.

## Collisions with other units

None live: every other unit under `docs/loop/` carries a `log.md` and is closed, so this unit
owns the tree. If that changes, the shared surfaces are `tests/guardrails.test.sh` and
`README.md` — and note that README's case count is now a hard-coded number asserted by the
harness, so "keep both blocks" no longer resolves a harness collision on its own.

## G1 — what the human decides

1. **Approve** — proceed to build, S1 first, one lane. *(recommended)*
2. **Re-slice** — most likely targets: S3, if the parity check belongs somewhere other than an
   extracted `run:` body; or S1, if the marker literal or its anchor should be different.
3. **Spec is wrong** — back to `loop-spec`.
