# Log — stale-evict-lock-permanently-defeats-the-cap

**What this unit achieved, in the words the spec insisted on:** an orphaned evict lock's effect on
the cap is now written down where the cap's promise already lives, a holder killed by a *catchable*
signal no longer strands the lock, and a lock that is stranded anyway is discoverable by a named
human-facing route. The leak is **narrowed, not closed** — `SIGKILL` is uncatchable, and the one kill
on record has an unestablished signal class. No sentence anywhere claims uptime bounding, because
uptime bounding was never obtained.

## Where it came from

The eviction cap converges eventually rather than being bounded at rest, and convergence depends on
whichever invocation holds `.claude/loop-cost-evict.lock` releasing it. If that holder dies without
releasing, every later invocation skips the trim — permanently, with nothing said. Two independent
copies of the primitive (`record-cost-event.sh` and `record-recovered-cost.sh`) guard one shared
path, so the hygiene had to land in both.

`spec.md` §0 is the constraint that shaped everything: `rmdir` fails on a non-empty directory, which
is why the pid-in-lock variant — write a pid inside the marker, read it to test liveness — was never
available. §1 is the harder one: **there is no liveness signal, and age is not one.**

## Phase 1 — Spec (G0), approved 2026-08-19 · `dea7408`

Specified in parallel with two other units, decided in one gate. Thirteen criteria, and `SL1`/`SL2`
deliberately first because they are satisfiable under *every* answer — including "nothing changes in
the code". They are what stop the unit's own claim being overstated, and they are the reason this log
can be honest about what was not achieved.

The load-bearing G0 decision was **no steal, ever**: a lock cannot be declared stale with the signals
available, so no route may take one from a holder that might be alive. Every candidate in §1's table
is recorded with the reason it was taken or declined, so none of them has to be rediscovered.

## Phase 2 — Slice (G1), 2026-08-19 · `b43fb20`, amended `35b4311`

Cut alongside two other units: three cuts, 18 slices, two evidence gates reserved for a human. The
original cut ran S1 → S2 → S3 → **S4 (spike)** → S5 (relocation) → S6 ‖ S7 → S8 → S9, with S5
gating S6 and S7.

**The amendment is the story of this unit.** `S4` was a spike asking one question: does the candidate
base `${TMPDIR:-/tmp}` have a per-boot property, established by observation rather than by citing
documentation? It returned **`needs-decision`**, and the human took it: **relocation is out.**

What `S4` found, read from the maintainer's own host rather than from any vendor page:

- `dirhelper`'s `CLEAN_FILES_OLDER_THAN_DAYS => "3"`, and `tmp_cleaner`'s
  `daily_clean_tmps_days="3"` with `dargs="-empty -mtime +3"` — precisely what an empty `mkdir`
  marker matches.
- `dirhelper` carries `RunAtLoad => true`, so it *does* run at boot — **but with the same age
  filter**, so the mechanism that runs at boot does not clear the base at boot.
- Therefore: not bounded by uptime. Bounded by **3 days**, under a threshold this project did not
  choose, cannot see from its own code, and cannot test.

Relocation had been approved to convert *permanent* into *bounded-by-uptime*. What it would actually
deliver is an age rule owned by the OS — the very rule `decisions.md` had already rejected in
principle — with the removal performed by the operating system instead of by this project's code. And
because the filter reads `atime`/`mtime`/`ctime` on a directory that is **held** rather than written,
while legitimate hold time is unbounded by design, a holder holding past three days would have its
lock deleted while alive. That is the wrong side of this unit's founding asymmetry, so `S5` was
dropped (text retained, not work), `SL11` and `SL13` were **declined on evidence** rather than
satisfied or deferred, and `S6`/`S7` were freed of their dependency on it.

## Phase 3 — Build, 2026-08-19

| Slice | Commit | What it settled |
|---|---|---|
| S1 | `27b4133` (merge) | Both writers' headers name the orphaned-holder effect on the cap, the lock's path, and the human's remedy — beside the existing convergence note, never without it. Plus the **claim-word guard**: any sentence naming the lock or an orphaned holder is scanned for the four bare claim-words and fails unless a negation governs one within three words. The four are the past participles of *fix*, *close*, *resolve* and *prevent* — named here in a sentence that mentions neither, which is the guard's own rule being obeyed rather than described. It scans this directory's markdown, so it governs this file too |
| S2 | `86fee09` | The staleness answer on the record: **no steal, ever**, with every declined candidate named — including §0's `rmdir` catch as the reason the pid-in-lock variant is rejected |
| S3 | `c29fbba` | `trap _release_evict_lock_on_signal INT TERM HUP` in **both** writers, releasing only a lock this process created (`_evict_lock_owned`). Cases `(k)`, `(l)` and `(m)`: hook writer, recovered writer, and a process that never acquired it and so releases nothing |
| S4 | `e8ea137` | The spike above. Its whole diff is one markdown file, and it says so |
| — | `35b4311` | The G1 amendment: relocation declined, `S5` dropped, `SL11`/`SL13` declined on evidence |
| S6 | `671ce7e` | `/cost` reports a present evict lock — naming the path, the not-trimmed effect, the live-trim-vs-orphan limit, and the remedy — and **never infers death** from the lock's existence. With no lock present its output is byte-identical to before |
| S7 | `d7cdc40` | A divergence between the two writers' derivations is red, by evaluating each writer's *own* assignment lines rather than a second copy of the formula |
| S8 | `5c9320a` | What `S3`'s trap costs an appending invocation, as numbers: four arms, n=20 per version, every mean delta within 0.7 ms and every median within 2.7 ms on a ~65–150 ms baseline, straddling zero |
| S9 | `93f2cb3` | The record completed with `S8`'s number and an explicit list of what remains the human's — appending beneath the relocation entry rather than rewriting it |

Merged at `f31bc1f`.

## Phase 4 — Verify (G2), 2026-08-20 — **CONCERNS**

`verify.md` carries the pass. Eleven criteria met with cases that can fail; `SL11` and `SL13`
confirmed as declined-on-evidence rather than quietly deferred. Suite green at
`513 passed, 0 failed`, `shellcheck` clean, and both CI jobs on pushed commit `1bd510b` reporting the
identical `total: 513 passed, 0 failed` — one sample per platform, read as one sample.

Two experiments were re-executed rather than accepted from the commit messages: deleting `S3`'s trap
registration reddens `S3 (k)`, and renaming `record-recovered-cost.sh`'s `EVICT_LOCK` alone reddens
`(S7-1)` and `(S7-2)`. Both criteria that rest on an experiment now rest on one run in this pass.

**The concern is `SL11`'s, and it belongs to the human.** The reboot observation this unit
deliberately reserved has now been taken, and it does not match the prediction: both marker
directories were **absent** after the 2026-08-20 reboot, at roughly 20.5 hours old against a
three-day age filter. The spike's own decision rule calls that the branch which *contradicts* the
configuration reading and is worth investigating rather than believing. It does not establish
boot-clearing — one host, one sample, and several other mechanisms fit — but it is live input to the
relocation entry's own "What would reopen it", because leg one of the decline (no per-boot property)
is what leg two (an age filter reaping a held lock) was arguing against.

## What this unit foreclosed

- **Declaring a lock stale.** No steal, ever, by any route. Not deferred — decided.
- **The pid-in-lock liveness variant.** Foreclosed by §0: `rmdir` fails on a non-empty directory.
- **Relocation, pending the evidence named in "What would reopen it"** — not for all time, and
  Finding 1 above is now part of that evidence.
- **Adopting the OS's 3-day threshold.** Recorded, never adopted; no interval, duration or margin
  ships from this unit's own code.
- **Any sentence claiming the leak is dealt with.** The claim-word guard makes overclaiming a red,
  including in this file.

## What this unit did not close

- **The `SIGKILL` route.** Uncatchable by construction. The leak is narrowed, not closed, and the one
  kill on record has an unestablished signal class.
- **`SL10` beyond one sample per platform.** Both jobs green on `1bd510b`; that is two samples, not
  a rate.
- **The temp-base question on either guarding platform.** Still `UNKNOWN`. A runner cannot be
  rebooted and a fresh VM is a different machine rather than a cleared one.
- **The Handoff's append-versus-trim loss window.** Deliberately left unopened, as `spec.md`'s
  Handoff section states.
- **An independent G2.** This pass is a same-session backfill, written the day after the merge.

## Cost

No records for this unit ("stale-evict-lock-permanently-defeats-the-cap") in the cost ledger. Not evidence the unit was free --
the ledger simply has nothing filed under this slug.

