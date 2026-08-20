# Verify — stale-evict-lock-permanently-defeats-the-cap (S1–S9, the whole cut as amended)

**Verdict: PASS** — eleven of the thirteen criteria are met with cases that can fail, and the two
remaining (`SL11`, `SL13`) were **declined on evidence** at the G1 amendment rather than satisfied,
which is a legitimate outcome this pass confirms.

**Amended 2026-08-20.** This pass first issued **CONCERNS**, on the grounds that the reboot
observation the unit reserved for a human had been taken and contradicted the configuration reading
the decline rests on. **That contradiction is retracted on evidence:** the boot in question was a
macOS upgrade boot, which is a sufficient and now-confirmed alternative explanation. The verdict is
raised and the sequence is recorded rather than overwritten. See Finding 1. Nothing below claims the
orphaned-holder leak is anything other than narrowed.

**Scope, declared rather than implied:**

- **Changed surface:** `scripts/record-cost-event.sh`, `scripts/record-recovered-cost.sh`,
  `scripts/cost-report.sh`, `tests/guardrails.test.sh`, `README.md`, `docs/loop/decisions.md`, and
  this directory. Commits: `27b4133` (merge S1), `86fee09` (S2), `c29fbba` (S3), `37c5eb7` (merge
  S2–S3), `e8ea137` (S4, the spike), `35b4311` (G1 amendment), `671ce7e` (S6), `d7cdc40` (S7),
  `5c9320a` (S8), `93f2cb3` (S9), `f31bc1f` (merge S6–S9).
- **Full suite reproduced green** on this host: `total: 513 passed, 0 failed`.
  `shellcheck -S warning scripts/*.sh` clean.
- **Both guarding platforms, real pushed commit:** run `32366734933` on `1bd510b`, job `96417752555`
  (`guardrails`) and job `96417752188` (`guardrails-macos`), each reporting an identical
  `total: 513 passed, 0 failed`. **One green run on each platform is one sample per platform, not a
  rate**, and `SL10` is met on that basis and no stronger one.
- ⚠ **This gate ran after the merge.** `f31bc1f` merged 2026-08-19; this pass is a backfill written
  2026-08-20. It reports on merged code; it did not gate the merge.
- ⚠ **Same-session limit.** The two criteria whose evidence is an experiment (`SL4`, `SL12`) were
  re-executed here from mutated scripts in a disposable copy rather than accepted from the commit
  messages. That is the strongest form available to a same-session pass; it is not an independent one.

---

## Criteria, one row each

| Criterion | Verdict | Proven by, and does it run |
|---|---|---|
| **SL1** — the orphaned-holder case and this unit's honest limit are written where the cap's promise lives | **MET, both directions** | `S1` case one: the hook writer's header and the recovered CLI's header both name the effect on the cap, the lock's path, and the human's remedy. `S1` case two is the **claim-word guard** — every sentence in this directory's markdown, plus both writers, `cost-report.sh`, `README.md` and `decisions.md`, that names the lock file, an orphan, or a stale lock is scanned for the four bare claim-words and fails unless a negation token governs one within three words. Those four are the past participles of *fix*, *close*, *resolve* and *prevent*. The guard scans **this file and `log.md` too**, and both were re-run green against it after being written |
| **SL2** — the staleness question is answered on the record | **MET** | `decisions.md` carries **no steal, ever**, naming each candidate from §1's table with the reason it was taken or declined, including §0's `rmdir`-on-non-empty catch as the reason the pid-in-lock variant is rejected |
| **SL3** — an orphaned lock is no longer both unenforced and unannounced | **MET, both halves** | Kill-half: `S3 (k)` hook writer and `S3 (l)` recovered writer, each killed mid-trim by `TERM`, release the lock, leave the ledger complete and parseable, and exit 0. Discovery-half: `(S6-1)` `/cost` names the path, the not-trimmed effect, the live-trim-vs-orphan limit, and the human's remedy; `(S6-2)` with no lock present none of those strings appear and the report is byte-identical to the pre-change rendering; `(S6-3)` the reader repairs nothing — lock still there, ledger byte-identical, nothing new created under `.claude` |
| **SL4** — the fault is reproduced red before anything is believed green | **MET, re-reproduced in this pass** | Removing the single line `trap _release_evict_lock_on_signal INT TERM HUP` from `record-cost-event.sh` in a disposable copy reddens `S3 (k)`: `total: 511 passed, 2 failed`. The second red is `(S9-7)`, another unit's guard asserting that file is untouched — it caught the mutation independently, which is a point in its favour |
| **SL5** — no lock is ever taken from a live holder, by any route | **MET** | `S3 (m)`: a process that never acquired the lock, killed the same way, releases nothing and another holder's lock survives untouched — the ownership condition (`_evict_lock_owned` guarding the `rmdir`) asserted rather than read. `H3`'s existing cases unmodified and green. The relocated-base route named in this criterion **does not exist**, relocation having been declined |
| **SL6** — `L7` is not traded, and the cost is measured where it is paid | **MET, as numbers** | `measure-sl6-append-cost.md`: four arms, same-driver interleaved control, n=20 per version per arm. Every **mean** delta within 0.7 ms and every **median** within 2.7 ms on a ~65–150 ms baseline, deltas straddling zero — consistent with `S3`'s trap being one registration plus two flag assignments. Cases (g) and (i) unchanged and green. Stated as numbers, never as "negligible" |
| **SL7** — no new threshold, default, or suggested value ships | **MET** | `LARAVEL_LOOP_COST_MAX_LINES` remains the only cap at its existing default. No duration, interval, or margin is introduced by this unit's code. The one age-like quantity in play — the OS's 3 days — is **recorded, not adopted**, and belongs to the operating system. Relocation being declined, no new base and no new configurable arrived at all |
| **SL8** — both writers changed, and the record says why the earlier rejection does not transfer | **MET** | `c29fbba` changes both `record-cost-event.sh` and `record-recovered-cost.sh`; `S3 (l)` exercises the recovered writer specifically; `(S7-1)`–`(S7-3)` check both. `decisions.md` states the prior "no contention, human-typed" rejection was about a trim obligation, not lock hygiene — a leak needs an interruption, not contention |
| **SL9** — nothing the ledger already guarantees regresses | **MET** | Suite green at 513/0 with the case total having risen, not dropped, across the unit. `shellcheck -S warning scripts/*.sh` clean. `L5`, `L6`, `L9`, `H3`, `H5`, the non-numeric-cap fallback and the arrival trim's never-waits contract all still carry their original cases, unmodified |
| **SL10** — holds on both guarding platforms, on a real pushed commit, one green run read as one sample | **MET** | The two job logs quoted in Scope: identical `total: 513 passed, 0 failed` on `ubuntu-latest` and `macos-latest`, on pushed commit `1bd510b`. Read as one sample per platform. No container or local run was substituted |
| **SL11** — the relocated location's per-boot property established by observation | **DECLINED ON EVIDENCE at G1 — and now contradicted** | `e8ea137` returned `needs-decision`: the per-boot property **fails** on the maintainer's host, both bases cleared by age at 3 days, `UNKNOWN` on both guarding platforms. The human took it and relocation went out (`35b4311`), so there is no relocated location whose property could be established. `spike-sl11-base-clearing.md` correctly records the unobservable half as the human's, with both marker paths, the command, and a validity deadline. **That observation has now been taken and it does not match the prediction — Finding 1** |
| **SL12** — the location comes from one place, and a divergence between the two writers is a red | **MET, re-reproduced in this pass** | `extract_evict_lock_path()` evaluates each writer's *own* `ROOT`/`DIR`/`EVICT_LOCK` assignment lines — never a second copy of the formula, never a hard-coded literal, which is what this criterion explicitly refuses. Mutating `record-recovered-cost.sh`'s `EVICT_LOCK` alone in a disposable copy reddens `(S7-1)` and `(S7-2)`: `total: 510 passed, 3 failed`. `(S7-3)` stays green under that mutation **correctly** — it asserts two different project dirs never collide, which a renamed-but-still-distinct path does not break |
| **SL13** — the old location, and an unusable new one, both have stated behaviour | **DECLINED ON EVIDENCE at G1** | Both halves presuppose a new location. Relocation having been declined, the lock stays beside the ledger: there is no old location to migrate from and no new base to degrade to. `35b4311` records this as declined rather than satisfied or deferred, which is the honest disposition and the one this pass confirms |

## Findings

**1. `SL11`'s reserved observation was taken; its apparent contradiction is confounded.
(Raised as CONCERNS, then retracted on evidence — 2026-08-20)**

`spike-sl11-base-clearing.md` left two empty marker directories and stated its decision rule in
advance: *"Both still listed → confirms the per-boot property fails… Either absent → contradicts the
configuration reading and is worth investigating rather than believing immediately."*

The host rebooted 2026-08-20 at 14:22, inside the validity window, with the markers roughly 20.5 hours
old against a 3-day age filter. **Both were absent** — the contradicting branch, and what this pass
first reported.

**Then the investigation the rule asked for was done, and it dissolved the contradiction.**
`/Library/Receipts/InstallHistory.plist` records `macOS 26.6.2` installed at **11:24 the same day**,
three hours before that boot, alongside `RosettaUpdateAuto` via `bootinstalld`; the running system is
now `26.6.2` (`25G83`). **The boot window contains an OS upgrade**, and a major macOS install
recreates the per-user `/var/folders` tree and can clear `/private/tmp` during installation.

So the markers' absence is explained by an upgrade rather than by ordinary boot behaviour. An upgrade
boot is not the observation the spike designed for, and the configuration reading — both bases cleared
by age at 3 days, `dirhelper` running at boot under the same age filter — stands **unchallenged**. The
per-boot property still **fails**, as `e8ea137` recorded, and the relocation decline rests on ground
that was never actually contradicted.

**What remains unobserved, and why it is optional:** whether an *ordinary* reboot leaves the markers
in place. The configuration predicts it does, nothing contradicts that, and nothing shipped depends on
it — the lock stays beside the ledger either way. Worth sampling only if relocation is reopened.

**Why this is in the record at all:** believing the contradicting branch immediately would have put a
false contradiction against a decision two configuration files argued for. The spike's advance rule
was right, and the investigation cost one read of the install history.

## `Do NOT` check — clean

No steal of any lock by any route (`S3 (m)` asserts the ownership condition). No threshold, interval
or margin introduced. No age rule adopted — the OS's 3 days is recorded and left where it is.
No sentence in the changed surface makes a bare claim about the orphaned-holder leak: the `S1`
claim-word guard scans this file and `log.md` alongside the scripts, `README.md` and `decisions.md`,
and passes with both in place. The leak is narrowed by `S3`'s hygiene — it is not closed, because
`SIGKILL` is uncatchable and the one kill on record has an unestablished signal class.

## Reproduction

Both experiments were run in a disposable copy (`git archive HEAD | tar -x`), never in the working
tree, with a pristine control first.

```
# Control, pristine, in the copy:                 total: 513 passed, 0 failed
# SL4  — trap registration deleted from the hook writer:
#                                                 total: 511 passed, 2 failed
#   FAIL S3 (k)   ... releases the lock; the ledger stays complete ...
#   FAIL (S9-7)   ... record-cost-event.sh untouched by this slice   <- another unit's guard
# SL12 — record-recovered-cost.sh's EVICT_LOCK alone renamed:
#                                                 total: 510 passed, 3 failed
#   FAIL (S7-1), FAIL (S7-2)                       <- the divergence, caught
#   FAIL S3 (l)                                    <- and caught a second, independent way
```

## What this pass cannot tell you

- **Whether the base is cleared at boot.** Finding 1 contradicts the recorded reading; it does not
  replace it. One host, one sample.
- **Anything about either guarding platform's temp-directory behaviour.** Still `UNKNOWN`, exactly as
  `e8ea137` recorded. A CI runner cannot be rebooted, and a fresh VM is a different machine rather
  than a cleared one.
- **Whether an orphaned lock has ever actually stranded the cap in real use.** Not observed; the leak
  is reasoned from the mechanism, and `S3` narrows the catchable-signal routes without addressing
  `SIGKILL`.
- **Independence.** Same-session pass, as declared in Scope.
