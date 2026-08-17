# Spike — Case B (`tests/guardrails.test.sh:2520`)

`ship: shellcheck absent from PATH reads not-run, verdict hold` — expected `yes yes 1`, got
`no no 0` on CI run `32026220384`, commit `a528f6a`.

Scope: case B only, read alone, per the slice's constraint. No statement here about case A or
a shared cause.

## 1. Which of OQ1's three answers the evidence supports

**Answer 1 — the case is wrong.** It asserts something that was only ever true on the
maintainer's platform. Resolution, if taken, is in the test file, not in `scripts/ship-check.sh`.

### Mechanism

The case (`tests/guardrails.test.sh:2508-2522`) builds a fixture with `new_ship_fixture`, then
tries to force `scripts/ship-check.sh`'s gate 2 (`gate2_shellcheck`) into its `not-run` path by
running the gate under a hand-picked, hard-coded PATH:

```
PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash scripts/ship-check.sh
```

`gate2_shellcheck` decides `not-run` with exactly one check: `command -v shellcheck` against
whatever `PATH` is in effect at call time (`scripts/ship-check.sh:143`). That check is not
platform-dependent in itself — it does exactly what a PATH lookup is defined to do on both
platforms. What differs across platforms is **where each platform's package manager puts the
`shellcheck` binary**, and the fixture's four-directory allow-list was sized to the maintainer's
own layout, not to every layout:

- On the maintainer's macOS host, `shellcheck` (via Homebrew) resolves outside
  `/usr/bin:/bin:/usr/sbin:/sbin`, so the pruned PATH genuinely excludes it and the case's
  fixture correctly forces `not-run` there.
- On the CI runner (`ubuntu-latest`), the `guardrails` job's earlier `shellcheck` install step
  uses `apt-get`, and Debian/Ubuntu's `shellcheck` package installs the binary to `/usr/bin`,
  which is **inside** the fixture's allow-list. The pruned PATH therefore fails to exclude it,
  `command -v shellcheck` still resolves, and gate 2 runs shellcheck for real instead of going
  `not-run`.

### Observation (investigation-grade — Docker `ubuntu:latest`, not the real runner)

Reproduced the case's own fixture-building steps verbatim (same `new_ship_fixture` contents,
same versions, same pruned-PATH invocation) inside a throwaway `ubuntu:latest` container with
`shellcheck` installed via `apt-get install -y shellcheck` (the same tool CI's `guardrails` job
uses):

```
$ dpkg -L shellcheck | grep bin
/usr/bin
/usr/bin/shellcheck
$ PATH="/usr/bin:/bin:/usr/sbin:/sbin" command -v shellcheck
/usr/bin/shellcheck        # found -- the pruned PATH does not exclude it here
```

Running the fixture's exact ship-check invocation under that PATH on that container:

```
gate 1: guardrail test harness (tests/guardrails.test.sh) -- passed
gate 2: shellcheck (scripts/*.sh) -- passed
gate 3: version consistency -- passed
verdict: go
(exit 0)
```

`G2_NOTRUN=no G2_VERDICT_HOLD=no exit=0` — reproduces the CI record's `no no 0` exactly. This is
investigation-grade (a container, not `ubuntu-latest` itself) and is cited only as a reproduction
of the mechanism, never as proof of A1/A2.

### Falsifiable

**Hypothesis:** the case fails on Linux because apt's `shellcheck` package installs into
`/usr/bin`, one of the fixture's own allow-listed directories, so the pruned PATH does not
achieve absence there the way it does on the maintainer's host.

**What would refute it:** if `shellcheck` installed via `apt-get` on `ubuntu-latest` resolved to
a directory *outside* `/usr/bin:/bin:/usr/sbin:/sbin` (e.g. `/usr/local/bin`, `/snap/bin`), the
pruned PATH would exclude it and the case would read `not-run` there too — contradicting the
observed CI failure. Checked directly above via `dpkg -L shellcheck` and a PATH-scoped
`command -v`; both show installation squarely inside the allow-list, which is what the fixture
missed.

**Whether the guarded behaviour is genuinely platform-dependent:** no. `gate2_shellcheck`'s own
logic (a PATH lookup) is identical code running identically on both platforms; only the
*fixture's chosen way of forcing absence* is not portable. This is why the finding is answer 1,
not answer 2.

## 2. The safety property's own status on the runner — stated separately from (1)

**Question:** could `scripts/ship-check.sh` report `go` on the runner while gate 2 (or any gate)
did not actually run?

**Answer: no — the property holds on Linux.** This is a separate claim from (1) and rests on its
own observation, not on the case's outcome.

### Observation (investigation-grade — same Ubuntu container, shellcheck genuinely removed)

Rather than relying on the fixture's (flawed) PATH-pruning trick, `shellcheck` was actually
deleted from the container (`rm -f /usr/bin/shellcheck /bin/shellcheck`, confirmed absent with
`command -v shellcheck` exiting 1 against the container's full, unmodified PATH), then
`scripts/ship-check.sh` was run unmodified, with no PATH override at all:

```
gate 1: guardrail test harness (tests/guardrails.test.sh) -- passed
gate 2: shellcheck (scripts/*.sh) -- not-run (shellcheck not found on PATH)
gate 3: version consistency -- passed
verdict: hold
(exit 1)
```

When shellcheck is genuinely unavailable on this Linux platform, `gate2_shellcheck` correctly
reports `not-run` and `ship_verdict` correctly reports `hold` with a non-zero exit — the same
outcome the case wanted, just reached by a portable trigger (real absence) instead of the
fixture's non-portable one (a hard-coded allow-list).

**Corroborating, non-investigation-grade evidence from the real runner itself:** the sibling case
at `tests/guardrails.test.sh:2524-2538` (`ship: a missing gate file reads not-run by name,
verdict hold`) exercises the identical `not-run` → `hold` pathway for gate 1, via a
platform-independent trigger (deleting the gate's target file rather than manipulating PATH), and
it **passed on the same CI run** that failed case B. That is a real-runner data point, not a
container one, and it points the same way: the `not-run`/`hold` aggregation in
`scripts/ship-check.sh` is intact on `ubuntu-latest`; only case B's specific method of producing
`not-run` for gate 2 is not.

### Falsifiable

**Hypothesis:** `gate2_shellcheck` and `ship_verdict` correctly force `not-run`/`hold` on Linux
when shellcheck is genuinely absent, independent of how the absence is produced.

**What would refute it:** if, with shellcheck actually removed from PATH, gate 2 read anything
other than `not-run`, or the overall verdict read anything other than `hold` with a non-zero
exit, on this or any Linux host. Not observed — the run above shows the expected `not-run`/`hold`
pair with a genuine absence.

## Cost of each candidate resolution (artifact only, no fix written here)

- **If the case is edited (answer 1, the one the evidence supports):** the artifact is
  `tests/guardrails.test.sh` — specifically the fixture invocation at the case's own lines
  (2508-2522). The case would need a way of forcing shellcheck's absence that does not depend on
  guessing which directories a platform's package manager does *not* use (e.g. discovering
  wherever `shellcheck` actually resolves on the host running the suite and excluding that
  directory specifically, rather than allow-listing a fixed set). `scripts/ship-check.sh` would
  need no change under this resolution — its own not-run detection is already correct on Linux,
  per (2) above.
- **If the code it exercises is treated as wrong (answer 2):** the evidence in (2) does not
  support this. Named for completeness only, per the envelope's format: it would live in
  `scripts/ship-check.sh` (`gate2_shellcheck`). No observation here shows a defect there to fix.
- **"Both, or neither yet" (answer 3):** not applicable — reading case B, its own fixture, and
  the gate it exercises was sufficient to settle (1) and (2) directly; no further investigation
  is needed before a human decision at A3.

## Scope note

This file states no cause for case A and draws no inference of a shared cause between the two
cases, per this slice's constraint.
