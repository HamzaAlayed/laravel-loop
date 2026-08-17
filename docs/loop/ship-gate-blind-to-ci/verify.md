# Verify — ship-gate-blind-to-ci

**Unit:** ship-gate-blind-to-ci **Slice:** S1–S4 (merge commits 47480af, 1f56824, 3b98ffe,
7bde10f over base 6458355; commits d37a6bb, a80b899, 42f625b, 8027099)

**Verdict:** PASS — scoped to S1–S4 (the four builder slices). A1/H1 is explicitly and
deliberately out of scope, per the slice list's own design, not a gap in this verify pass.

Relayed as issued. `loop-verify` is read-only by design (`Edit`/`Write` removed), so this file
was written by the orchestrator from the returned verdict; the verdict itself was not edited,
softened, or re-derived.

## Acceptance criteria

| Criterion | Proven by | Status |
|---|---|---|
| A1 — real CI run concludes success | No slice claims this; H1 is the maintainer's post-merge action and nothing has been pushed. | **Not closed here — declared out of scope, not folded into the PASS** |
| A2 — local check fails pre-fix, names the file | `scripts/check-script-modes.sh`, harness case 1 (S1 section). Reproduced live: checked out merge commit 47480af (post-S1, pre-S2) in a scratch clone and ran the checker directly — exit 1, `wrong mode: scripts/cost-ledger-lib.sh is a program (committed 100644, expected 100755)`. | PASS |
| A3 — one place enumerating both sets and both deltas | `docs/loop/checks.md`, harness cases 1–3 (S4 section, iterated over `ci.yml` step names and `ship-check.sh` gate names). Read the doc directly: names version-consistency absent from pushed-commit side, names the mode rule absent as a declared G3 gate and reachable only indirectly via gate 1's harness. | PASS |
| A4 — pushed-commit and local answers never disagree | `ci.yml`'s `scripts are executable` step now runs `scripts/check-script-modes.sh` and nothing else; harness cases 2–4 (S3 section) extract the step's live `run:` body via `extract_ci_step_run` (bash+sed) and diff it against a direct run on two fixtures. Confirmed non-tautological by hand: probed `extract_ci_step_run` with a nonexistent step name — returns rc=1 with empty output (fails, does not skip), matching S3 case 1's assertion. | PASS |
| A5 — rule written down and mechanically checkable | Rule stated verbatim in `check-script-modes.sh`'s header and `slices.md`'s pinned table; S2 case 2 iterates `git ls-files -s scripts/*.sh tests/*.sh` (12 files today) and asserts 0 mismatches against the rule's classification — confirmed by re-running that loop directly at the repo root. | PASS |
| A6 — red release history recorded, earliest cause unknown | `docs/loop/checks.md` names v0.2.0, v0.3.0, v0.3.1, v0.4.0, v0.5.0, v0.6.0, cites run `31696279581` and records its cause as `unknown` — matches `intent.md` exactly, no cause inferred from a later run. Harness case 4 (S4 section) asserts all six versions present and `unknown` stated. | PASS |
| A7 — any configurable ships unset, asserted not claimed | `check-script-modes.sh` contains no `LARAVEL_LOOP` literal, no `env()`-equivalent, no default. Harness case 7 (S1 section) exports `LARAVEL_LOOP_FOO`/`LARAVEL_LOOP_SHIP_GATE_TIMEOUT` and asserts byte-identical output/exit code plus `grep -c 'LARAVEL_LOOP' "$CSM"` == 0. `docs/loop/checks.md` introduces no env var either. | PASS |
| A8 — nothing already guaranteed regresses | `git diff 6458355...HEAD -- tests/` shows zero removed lines (pure addition, no weakened/deleted assertion). Case count went up (404→421), never down. `shellcheck -S warning scripts/*.sh` clean. `ship-check.sh` run twice against the unchanged tree → byte-identical output, `verdict: go` both times. | PASS |
| A9 — verdict stays a function of exactly the declared gates | `git diff 6458355...HEAD -- scripts/ship-check.sh` is empty — untouched. Gate set unchanged at exactly three. Grepped README, `scripts/ship-check.sh`, and `docs/loop/ship-observe-automation/` for any "fourth gate" / declared-count restatement — the two hits found (`ship-check.sh` line 39, `ship-observe-automation/slices.md` line 178) both pre-date this diff and are outside the changed-file set. | PASS |

## `Do NOT` audit

Walked all four slices' lists against `git diff 6458355..HEAD` and the per-commit diffs
(`d37a6bb`, `a80b899`, `42f625b`, `8027099`):

- No `chmod` of any tracked file — `git diff --summary` shows only two `create mode` lines (new
  files `check-script-modes.sh` at 100755, `checks.md` at 100644); no mode-change line on any
  existing tracked file.
- `scripts/ship-check.sh` — empty diff, untouched (S1's, S3's, and OQ2's Do NOT).
- `CHANGELOG.md` — empty diff, untouched (S4's Do NOT).
- No status badge, no README CI-health section — `docs/loop/checks.md` explicitly disclaims
  both; README's only new line is a one-line pointer, as S4 specified.
- No added CI step or job — `ci.yml` diff is 5 lines, all inside the existing
  `scripts are executable` step body; step name unchanged, job count unchanged, step count
  unchanged (still 3).
- No env var, no exempt list, no second marker convention — confirmed above under A7; only one
  marker literal (`# laravel-loop:sourced-library`) exists anywhere in the diff.
- Self-exemption trap closed: the marker literal appears inside both `check-script-modes.sh` (in
  its header prose and in `MARKER='...'`) and `tests/guardrails.test.sh` (inside `printf`-built
  fixture content and a `grep` pattern) — never as a bare, unindented, first-20-lines comment
  line in either file. Verified `head -20` of both files contains no literal marker occurrence;
  the checker's own header explicitly notes it avoided writing the literal as a bare line for
  this reason.
- S1's committed mode is 100755 (`git ls-files -s scripts/check-script-modes.sh` confirms), and
  S1 added no case running the checker against the repo's own tree — confirmed the S1 harness
  section only uses throwaway `mktemp -d` fixtures; the real-tree case is in S2's section, as
  specified.
- S2 did not `chmod +x` `cost-ledger-lib.sh` — its committed mode stays `100644`; only a comment
  line was added, after the shebang and the two `# shellcheck` directives, both retained in
  original order.
- S3 touched only the `scripts are executable` step body; the other two steps (`shellcheck`,
  `guardrail tests`) are byte-identical in the diff; no `fetch-depth` or checkout option added;
  no invocation of `ship-check.sh` from CI.

## Out-of-bounds touched

None found.

## Scope declaration

This verdict covers S1–S4 as merged (6 files, 468 insertions, matching the brief exactly) and
the full harness/shellcheck/checker re-run. It does **not** cover A1 — the only proof of A1 is a
real GitHub Actions run concluding success on a real pushed commit, and nothing from this unit
has been pushed (`git status` shows the branch 11 commits ahead of `origin/main`, all local).
Per `docs/loop/cost-ledger-blind-to-background-agents/verify.md`'s precedent holding DC4/DC5 out
of a PASS, A1/H1 is held out here the same way: it is the maintainer's action, explicitly not
`loop-build`'s or this verify pass's to claim, and no slice asserts it.

## Evidence

```
git diff 6458355..HEAD --stat
 .github/workflows/ci.yml      |   5 +-
 README.md                     |   4 +-
 docs/loop/checks.md           |  66 +++++++++
 scripts/check-script-modes.sh |  79 +++++++++++
 scripts/cost-ledger-lib.sh    |   1 +
 tests/guardrails.test.sh      | 319 +++++++++++++++++++++++++++++
 6 files changed, 468 insertions(+), 6 deletions(-)

bash tests/guardrails.test.sh  → total: 421 passed, 0 failed, ALL GREEN
shellcheck -S warning scripts/*.sh → exit 0, no output
bash scripts/check-script-modes.sh  (repo root, HEAD) → exit 0
git diff 6458355..HEAD -- tests/ | grep '^-' | grep -v '^---'  → empty (no removed test lines)
git diff 6458355..HEAD -- scripts/ship-check.sh → empty (untouched)
git diff 6458355..HEAD -- CHANGELOG.md → empty (untouched)
git diff 6458355..HEAD --summary → only 2 "create mode" lines, no chmod of existing file

Scratch-clone (mktemp -d) revert ladder, main left untouched throughout (confirmed via
`git status`/`git log -1` on the real repo before and after):
  6458355 (base, pre-S1)  → harness 404 passed; no check-script-modes.sh; ci.yml has old inline [ -x ] loop
  47480af (post-S1)       → harness 411 passed; checker run directly → exit 1, names scripts/cost-ledger-lib.sh
  1f56824 (post-S2)       → checker run directly → exit 0; harness 413 passed
  3b98ffe (post-S3)       → harness 417 passed; ci.yml step body is `scripts/check-script-modes.sh` only; docs/loop/checks.md absent
  7bde10f (post-S4, HEAD) → harness 421 passed; docs/loop/checks.md present

bash scripts/ship-check.sh (x2, unchanged tree) → byte-identical output both runs, verdict: go, rc 0 both times

Manual probe of extract_ci_step_run() with a nonexistent step name → rc=1, empty output (fails, not a silent skip)
```
