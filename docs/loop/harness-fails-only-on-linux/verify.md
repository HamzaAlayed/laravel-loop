# Verify — harness-fails-only-on-linux

**Unit:** harness-fails-only-on-linux **Slice:** S5–S8 (commits `68ece94`, `a7a3390`, `7a8aafb`,
`65f761b`, each `--no-ff` merged; range `f623c64..HEAD`, excluding `f64174a`'s unrelated `/observe`
capture, out-of-unit)

**Verdict: CONCERNS** — every criterion this pass owns is proven and every `Do NOT` holds, but S5
shipped a real, reproduced regression (unbounded evictor hang on a persistently-failing `mv`) that
no test in this repository exercises and that the pre-fix code did not have.

Relayed as issued. `loop-verify` is read-only by design, so this file was written by the
orchestrator from the returned verdict; the verdict itself was not edited, softened, or
re-derived. **The unit is NOT closed.** A CONCERNS verdict at G2 is the human's to resolve.

## Acceptance criteria

| Criterion | Proven by | Status |
|---|---|---|
| A1 (real run, `success` not `skipped`) | Nothing local can prove this. Confirmed `main` is 19 commits ahead of `origin/main`, all local, nothing pushed | **Not closed here — the human's, post-merge** |
| A2 (floor established, not assumed) | `spike-floor.md` reads run `32026220384`: 421/421 executed, 2 named failures, recorded as a lower bound. Resolved-tree count needs a real post-fix run | **Floor half proven; resolved-tree half out of scope** |
| A3 (per-case recorded decision, change matches) | `decisions.md`'s "Second G1" entry names case A → code, case B → the case. S5's diff touches only `append_and_evict()`; S6's only the fixture. One slice per case, never combined | **Proven** |
| A4 (no case silently absent) | S7 adds `guardrails-macos` with the identical suite invocation and zero platform conditionals; `checks.md` states the equal-totals expectation. The actual cross-job comparison is the human's, at A1 | **Structurally proven; the comparison itself out of scope** |
| A5 (claimed platforms + evidence producer) | `checks.md`'s "Claimed platforms" section states exactly `ubuntu-latest`/`macos-latest`, each with its job's own suite step as producer; citation-is-not-proof and rolling-image limits in the same section; the maintainer's host named as what `macos-latest` *approximates*, not a third claim; `grep -i "covered\|verified\|proven\|guaranteed"` finds only the sentence negating all four | **Proven** |
| A6 (`checks.md` matches both check sets) | S7 updates `checks.md` in the same commit (`7a8aafb`) as `ci.yml`; the iterated step-name parity case passed in the full run | **Proven** |
| A7 (nothing green by removing evidence) | `git diff … -- tests/guardrails.test.sh \| grep '^-'` → only 2 removed lines, both inside S6's case-B fixture body; zero removed `expect` lines in the whole range. Deltas verified against real README bumps: 421→423→424→424→426, each in the same commit as its case addition | **Proven** |
| A8 (existing guarantees hold) | Full suite green (426/0) on this bash-3.2 host; shellcheck clean; `ship-check.sh` untouched; ubuntu job's 3 step names/bodies/order byte-identical | **Proven for what is tested — see the blocking finding, which this proof does not reach** |
| A9 (configurable ships unset / vacuous) | No new `LARAVEL_LOOP_*`, env var, threshold, or default anywhere in the diff | **Confirmed vacuous, honestly** |

## The two handed-over concerns — the verifier's own findings, not taken on trust

**(a) `append_and_evict()`'s `while :;` loop can spin forever on a persistently-failing `mv -f`.**
**Real, and reproduced independently.** In a scratch dir the ledger file was made immutable
(`chflags uchg`) so `mktemp`/`tail` keep succeeding while `mv -f` keeps failing
(`Operation not permitted`) — the extracted loop body spun **209 iterations in 3 seconds with no
break reached**. Comparing against `git show f623c64:scripts/record-cost-event.sh` confirms this is
a **new** regression: the old loop was bounded to `attempt<5` and always exited that bound
regardless of `mv` failing, released the lock, and returned.

This directly contradicts the script's own header contract, unchanged by S5: *"Exits 0 on every
path, including its own internal errors: cost accounting must never block, delay, or alter a
spawn."* A stuck evictor never reaches `rmdir`/`return 0`, so the invocation holding the lock hangs
indefinitely. Plausibly reachable via EDR/anti-ransomware rename interception, SELinux/AppArmor
rename denial, or a mandatory NFS lock — not purely academic. **Finding: real defect,
narrow-but-plausible reachability, not covered by any test in this pass.**

*Independently re-confirmed by the orchestrator after the verdict was returned: the same loop body
under the same conditions ran 501 iterations without reaching any break, while the pre-fix
5-attempt form exited silently.*

**(b) Stale-lock window widened.** **Agree it is pre-existing, not introduced.** Both old and new
code strand `EVICT_LOCK` forever if the evictor is killed mid-loop — `rmdir` is on the far side of
the loop in both versions — so that failure class predates S5. What changed is the window's size:
the old loop's was at most 5 fast syscalls; the new one's is unbounded under sustained contention
and, per (a), *infinite* under a persistent `mv` failure, which collapses "evictor killed mid-loop"
and "evictor never reaches its own exit" into the same outcome — permanent eviction disablement.
Given the slicer explicitly refused to prescribe stale-lock handling, the widening itself is
acceptable as a named gap — but **(a) and (b) compound: two independent paths now reach the same
permanently-stuck-lock state where before there was one.**

## `Do NOT` audit — every slice

- `scripts/ship-check.sh` — untouched across the whole range. ✓
- No gate added/removed; shellcheck policy (`-S warning`, `scripts/*.sh` scope) unchanged. ✓
- Ubuntu job's 3 step names/bodies/order byte-identical. ✓
- No `continue-on-error`, no `if:` platform skip, no known-failures list, no gate-softening
  `|| true` (the single hit is a shell-variable assignment inside S6's test fixture). ✓
- No badge, no CI-health section. ✓
- No case weakened/deleted/skipped/renumbered; case A's `yes` and case B's `yes yes 1` unchanged. ✓
- `decisions.md`, `slices.md`, `spec.md`, all four `spike-*.md` — none touched. ✓
- No new env var / threshold / default. ✓

## Out-of-bounds touched

None within this unit's fix group. `f64174a` (transcript-scraping intent capture) sits inside the
commit range but is an unrelated `/observe` capture for a different unit — excluded per the brief,
not reported as scope creep.

## Scope declaration — what this verdict does not cover

- **A1**, **A2's resolved-tree count**, and **A4's actual cross-job total comparison** are not
  closed and are not folded into this verdict. They require a real pushed run, which has not
  happened (`main` 19 ahead of `origin/main`, all local, confirmed).
- No real GitHub Actions run on either job was observed. The macOS-job claim rests on S7/S8's
  construction plus this local arm64/bash-3.2 host as the nearest available approximation —
  explicitly not proof, per the unit's own pinned discipline.
- The `mv`-failure finding was investigated for reachability by one mechanism only (filesystem
  immutability). EDR/SELinux/NFS-lock triggers were not attempted; only that the code path, once
  entered, does not terminate.

## Evidence

```
git log --oneline f623c64..HEAD            → 8 commits, incl. 1 unrelated observe capture, excluded
git diff f623c64..HEAD --stat              → 6 files, 308(+)/18(-)
bash tests/guardrails.test.sh              → total: 426 passed, 0 failed / ALL GREEN
shellcheck -S warning scripts/*.sh         → exit 0, no output
git diff … -- tests/guardrails.test.sh | grep '^-'  → 2 lines removed, both S6 fixture body, 0 expect lines
scratch repro, pre-fix f623c64 copy, x5    → no (14642) / no (15118) / no (15102) / no (15048) / no (15559)
scratch repro, fixed HEAD copy, x5         → yes (15) x5
scratch repro, mv -f under chflags uchg    → 209 iterations / 3s, no break reached
orchestrator re-confirmation, same shape   → 501 iterations, no break; pre-fix form exits at 5
git rev-list --count origin/main..HEAD     → 19 (nothing pushed)
README.md:167 progression                  → 421→423 (S5)→424 (S6)→424 (S7)→426 (S8)
```
