# Checks — what runs where

Two check sets exist for this repository, and until now the only way to compare them was to
read two files and diff them by eye. This is that one place. It is a map of the two sets, not
a health report — it claims nothing about current CI colour, carries no badge, and adds no
CI-health section. See `docs/loop/ship-gate-blind-to-ci/spec.md` for the problem this was
written to close, and that unit's `intent.md` for the run ids and versions cited below.

Add a row here, on both sides, whenever a check is added, removed, or renamed on either side.
An enumeration that drifts from the files it enumerates is worse than no enumeration.

## What runs on the pushed commit

`.github/workflows/ci.yml`, on every `push` and `pull_request`. **Two jobs**, both running the
same suite file with the identical invocation and no platform conditional anywhere — the same
three checks, run twice, once per platform:

### `guardrails` — `ubuntu-latest`

1. **`shellcheck`** — `shellcheck -S warning scripts/*.sh`
2. **`scripts are executable`** — runs `scripts/check-script-modes.sh`, the script-mode rule
   (every `scripts/*.sh` / `tests/*.sh` file is a program at `100755` or a declared library at
   `100644` — see that script's own header for the rule verbatim)
3. **`guardrail tests`** — `bash tests/guardrails.test.sh`

### `guardrails-macos` — `macos-latest`

1. **`shellcheck (macos)`** — installs `shellcheck` via Homebrew first (the image's own
   manifest lists none — see `spike-platforms.md`), then runs the identical
   `shellcheck -S warning scripts/*.sh`
2. **`scripts are executable (macos)`** — runs `scripts/check-script-modes.sh`, the same script
   as the ubuntu step
3. **`guardrail tests (macos)`** — `bash tests/guardrails.test.sh`, the same invocation as the
   ubuntu step

**A4 — no case silently absent on either platform.** Because both jobs run the identical file
with the identical invocation and neither job carries a platform conditional, their reported
`total: N passed, M failed` lines must match exactly. Any case deliberately not run on one
platform would have to be named here, explicitly — none currently is.

**The `macos-latest` label is a rolling image.** Its OS point-version moves on GitHub's own
update cadence and is not a fixed contract; see `spike-platforms.md` for the pinned manifest
commit this was checked against and its own statement that a manifest is not proof the suite
passes there — only a real run on that platform is.

**Absent from this side:** version consistency. Nothing that runs on the pushed commit
compares `VERSION`, `plugin.json`'s version, and `marketplace.json`'s version. A release can
push with all three disagreeing and every pushed-commit check still concludes success.

## What runs locally at G3

`scripts/ship-check.sh`, run by hand (or via `/ship`) before tagging a release. Three declared
gates, hard-coded, in this order — see that script's own header for the rule verbatim:

1. **the guardrail test harness** (`tests/guardrails.test.sh`)
2. **shellcheck over `scripts/*.sh`**
3. **version consistency** across `VERSION` / `plugin.json` / `marketplace.json`

**Absent from this side, as its own declared gate:** the script-mode rule. This is a chosen
cost, not an oversight — OQ2 fixed `ship-check.sh`'s gate set at exactly three and rejected
adding a fourth for the mode rule, precisely so the release action's declared count would not
grow every time a pushed-commit step does. The mode rule still reaches the G3 verdict, but only
**indirectly**: gate 1 is the same `tests/guardrails.test.sh` file the pushed commit runs, and
that harness carries cases asserting the mode rule holds over this repository's own committed
tree (the `ship-gate-blind-to-ci` unit's S2 case, iterated over every file the glob matches,
plus S3's parity cases). A tree that stops conforming to the mode rule fails gate 1 and the G3
verdict turns `hold` — the same file, the same assertion, read by both sides, not a second
implementation of it and not a gap nobody noticed.

## Both deltas, side by side

| Check | Pushed commit (`ubuntu-latest`) | Pushed commit (`macos-latest`) | Local G3 |
|---|---|---|---|
| shellcheck (`scripts/*.sh`) | step `shellcheck` | step `shellcheck (macos)` | gate 2 |
| guardrail test harness | step `guardrail tests` | step `guardrail tests (macos)` | gate 1 |
| script-mode rule | step `scripts are executable` | step `scripts are executable (macos)` | not a declared gate — reached only indirectly, through gate 1's harness |
| version consistency | absent | absent | gate 3 |

## The red release history (A6)

Every release through v0.6.0 shipped while the pushed-commit checks were failing:
**v0.2.0, v0.3.0, v0.3.1, v0.4.0, v0.5.0, v0.6.0.** From the v0.3.0 cycle onward the failing
step was `scripts are executable`, reporting `not executable: scripts/cost-ledger-lib.sh` —
the file the script-mode rule now names by the same mechanism, deliberately.

The earliest of the twelve surviving runs, `31696279581` (v0.2.0, 2026-08-13T11:36Z), predates
`cost-ledger-lib.sh`'s existence, and its surviving log does not yield a filename. Its cause is
recorded here as **unknown**, and it stays unknown: no cause is inferred for it from any later
run's cause, and none is inferred here.
