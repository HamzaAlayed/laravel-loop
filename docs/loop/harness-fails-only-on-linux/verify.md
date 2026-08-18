# Verify — harness-fails-only-on-linux

**Unit:** harness-fails-only-on-linux **Slice:** S5–S9 (commits `68ece94`, `a7a3390`, `7a8aafb`,
`65f761b`, `22779f8`, each `--no-ff` merged; range `f623c64..HEAD`, excluding `f64174a`'s unrelated
`/observe` capture, out-of-unit)

**Verdict: PASS** — scoped to everything checkable without a push.

Relayed as issued. `loop-verify` is read-only by design, so this file was written by the
orchestrator from the returned verdict; the verdict was not edited, softened, or re-derived.

> **This is the second G2 pass.** The first, over S5–S8, returned **CONCERNS** for one reason:
> S5's eviction loop had no break on a persistently failing `mv -f` and looped forever — a new
> regression, not pre-existing. S9 is the one-line fix. The prior verdict is preserved in this
> file's git history and its finding (b) on the stale lock is carried forward below.

## Prior finding (a) — resolution established on the verifier's own evidence

A repro independent of the harness's own new case (same trigger class — a `PATH`-stubbed `mv`
exiting non-zero — but a separate script, separate payload, separate bounding mechanism):

| Script under test | Result (3 runs each) |
|---|---|
| `f623c64` (pre-S5, bounded 5-attempt loop) | returns, exit 0, lock released — 3/3 |
| `cca5e6f` (post-S5, pre-S9 — the regression) | hangs past an 8s bound, no break reached — 3/3 |
| `22779f8` (post-S9 — the fix) | returns, exit 0, lock released — 3/3 |

`git diff cca5e6f..22779f8 -- scripts/record-cost-event.sh` is exactly the one line named in
`decisions.md`'s G2-follow-up entry. **Finding (a) is resolved**, not merely claimed.

## Convergence did not regress

The added `break` fires only inside the `mv`-failure branch, which is dead code under normal
operation — read from the diff, not inferred. The full suite, including S5's own convergence case,
is green (427/0), and the change touches no other line of `append_and_evict()`. No evidence of an
early-exit disguised as a fix.

## Stale-lock status — re-examined, not re-litigated

`rmdir "$EVICT_LOCK"` is still on the far side of the loop, unconditionally, for every `break`
including the new one. So the prior verdict's **compounding** — two independent routes to a
permanently-stuck lock — is now back down to **one**. The persistent-`mv`-failure route is closed
by S9. The evictor-killed-mid-loop route is **unchanged and still pre-existing**, exactly as before
S5 landed, deliberately left alone per S9's own `Do NOT` and the second G1's explicit refusal to fix
it here. Not a defect of this pass — stated so a future reader does not mistake "compounding
removed" for "stale lock fixed."

## Acceptance criteria

| Criterion | Proven by | Status |
|---|---|---|
| A1 (real run, `success` not `skipped`) | Nothing local can prove it; 23 commits ahead of `origin/main`, nothing pushed | **Not closed here — the human's, post-merge** |
| A2 (floor established, not assumed) | `spike-floor.md`'s observed-floor half stands. Resolved-tree half needs a real post-fix run | **Floor half proven; resolved-tree half out of scope** |
| A3 (per-case recorded decision, change matches) | `decisions.md`'s two entries name case A → code (S5, then S9's follow-up to that same code), case B → the fixture (S6). S9 touches only the code its decision names | **Proven, including S9** |
| A4 (no case silently absent) | S7's structural proof stands: identical suite invocation, no platform conditional. The cross-job comparison is the human's, at A1 | **Structurally proven; the comparison out of scope** |
| A5 (claimed platforms + evidence producer) | `checks.md`'s "Claimed platforms" section re-read: exact names, named producers, citation-is-not-proof and rolling-image limits travelling with the claim, no covered/verified/proven language | **Proven** |
| A6 (`checks.md` matches both check sets) | Unchanged by S9, correctly — S9 changes nothing about what runs where. S7's commit holds it | **Proven** |
| A7 (nothing green by removing evidence) | No removed assertion lines beyond S6's already-audited fixture setup; S9 adds one case and modifies zero; case A's `yes` and case B's `yes yes 1` unchanged; deltas 421→423→424→424→426→**427**, each bump in the same commit as its case addition | **Proven** |
| A8 (existing guarantees hold) | 427/0 on bash 3.2; shellcheck clean; `ship-check.sh` untouched, three gates unchanged; ubuntu job's block byte-identical to `f623c64`; both guardrail hooks untouched | **Proven — and now covers the `mv`-hang path the prior pass could only flag** |
| A9 (configurable ships unset / vacuous) | Only the pre-existing `LARAVEL_LOOP_COST_MAX_LINES` reused; two new shell variables are test-local to the harness, not the script | **Confirmed vacuous, honestly, including S9** |

## `Do NOT` audit — every slice, S5–S9

`ship-check.sh` untouched ✓ · no gate added/removed, shellcheck policy unchanged on both jobs ✓ ·
ubuntu job's three step names/bodies/order byte-identical ✓ · no `continue-on-error`, `if:` platform
skip, known-failures list, or gate-softening `|| true` ✓ · no badge, no CI-health section ✓ · no case
weakened/deleted/skipped/renumbered, both expected strings unchanged ✓ · **new for S9: no attempt
bound, iteration counter, or no-progress guard — grepped, zero hits; the fix is exactly the one line
the decision named** ✓ · `spec.md` and all four `spike-*.md` untouched ✓ · no new env var, threshold,
or default ✓

## Out-of-bounds touched

None within S5–S9. `f64174a` (`transcript-scraping-as-a-recovery-path/intent.md`) sits inside the
range but is an unrelated `/observe` capture for a different unit — excluded per the brief, not
reported as scope creep.

## Scope declaration — what this verdict does not cover

- **A1**, **A2's resolved-tree count**, and **A4's cross-job comparison** are not closed and are not
  folded in, following `cost-ledger-blind-to-background-agents/verify.md`'s DC4/DC5 precedent. They
  need a real pushed run, which had not happened when this verdict was issued (23 ahead, confirmed
  by `git fetch` + `git rev-list`).
- No real Actions run on either job was observed for this pass. All evidence is local-host
  (bash 3.2, macOS arm64) plus a scratch repro; per the unit's own discipline that is not proof of
  A1 or A5.
- The `mv`-failure fix was re-verified with one trigger mechanism (`PATH`-stubbed `mv`). The
  EDR/SELinux/NFS-lock triggers named in the prior verdict were not re-attempted — not needed to
  establish the fix works against the mechanism the decision named.
- The evictor-killed-mid-loop stale-lock route was read, not experimentally reproduced this pass;
  it was already established as pre-existing and out of bounds.

## Evidence

```
git diff f623c64..HEAD --stat                        → 10 files, 711(+)/19(-)
git diff cca5e6f..22779f8 -- scripts/record-cost-event.sh → exactly 1 line changed (the named fix)
bash tests/guardrails.test.sh                        → total: 427 passed, 0 failed / ALL GREEN
shellcheck -S warning scripts/*.sh                   → exit 0, no output
diff (ubuntu job block, f623c64 vs HEAD)             → identical
README.md case-count per merge commit                → 421→423→424→424→426→427
scratch repro, pre-S5 (f623c64), x3                  → returned, exit 0, lock released
scratch repro, pre-S9 (cca5e6f), x3                  → TIMED OUT after 8s, no break reached
scratch repro, post-S9 (22779f8), x3                 → returned, exit 0, lock released
git rev-list --count origin/main..HEAD               → 23 (nothing pushed at verdict time)
```
