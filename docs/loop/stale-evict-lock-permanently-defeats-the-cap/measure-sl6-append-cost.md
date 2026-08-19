# S8 — what this unit costs an appending invocation, before and after S3's trap

Slice `S8`. Markdown only: this file, `git diff --name-only` confirms, is this slice's whole diff.
Method adapted point-by-point from
`docs/loop/eviction-cap-not-honoured-under-contention/measure-e8-after.md`'s own instrument.

**Host:** `Darwin 25.6.0 ... RELEASE_ARM64_T6000`, arm64 — the maintainer's own host, the same shape
`measure-e8-after.md` used. `GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)`.

**Post sha (with S3's trap):** `d7cdc40b4d82887d29d7195cd11eb8c7d337294d` — this unit's `S7`, merged.
**Pre sha (without S3's trap):** `27b4133` — `Merge stale-evict-lock S1`, the commit immediately
before `S3` landed (`37c5eb7`), obtained read-only with `git show 27b4133:scripts/record-cost-event.sh`
and `git show 27b4133:scripts/record-recovered-cost.sh` (plus `cost-ledger-lib.sh` at the same sha,
so the recovered CLI's `source` resolves against a self-consistent pre-change tree). No `checkout`,
no branch, no stash. `dea7408` (the G0 spec commit) is **not** the right pre-change sha here: `S1`
landed between `dea7408` and `S3` and only touches header comments (`git diff 27b4133 37c5eb7 --
scripts/`, isolated to the two writers, shows exactly the trap/ownership-flag addition and nothing
else) — so `27b4133` isolates `S3`'s change precisely, while `dea7408` would also have included `S1`'s
prose-only diff, which touches no code.

**n = 20 per arm per version, interleaved** (pre, post, pre, post, …) so host drift lands on both
sides rather than on one, per `measure-e8-after.md` §3's own control design. Every trial ran under a
fresh throwaway `CLAUDE_PROJECT_DIR`; this repository's own `.claude/` was never written to. No
`TMPDIR` is read anywhere on this path (relocation was declined at G1), so no throwaway `TMPDIR` is
needed for these arms specifically.

Every figure below is a count of milliseconds over 20 samples. One trial is one sample. No rate, no
percentage, and no extrapolation to CI or to any other host is stated anywhere in this file.

---

## 1. The headline, stated before the table

**The appending path's cost did not move, in either writer, in either ledger state.** Every arm's
mean and median delta (post minus pre) is under 3 ms on a ~65–150 ms baseline, and every delta
straddles or sits at zero rather than showing a consistent one-directional shift. `S3`'s actual diff
on this path is one `trap` builtin registration and two in-memory flag assignments
(`_evict_lock_owned=1` / `=0`) around the existing `mkdir`/`rmdir` pair — there is no loop, no
subprocess, and no I/O added — and the measurement is consistent with that: negligible work, stated
as numbers rather than asserted so.

**There is nothing to separate "the trap's cost" from "the path resolution's cost."** `SL6` asks for
that separation where the arms allow it; they do not apply here, because relocation (`S5`) was
dropped on `S4`'s evidence — there is no new derivation and no degraded branch on the append path.
The only code this unit added to the append path, in either writer, is `S3`'s trap and flag. All four
arms below measure exactly that, and nothing else.

**Arm (d) is redefined from the original envelope, and that is stated rather than hidden.** The
slice's original text scoped arm (d) as "an appending invocation with the base UNUSABLE, so the
degraded branch of the derivation is the one being timed" — a branch of `S5`'s relocation. `S5` was
dropped at G1 on `S4`'s evidence (both candidate bases are cleared by age, not at boot), so that
branch does not exist in this unit's shipped code. Inventing a case to time a code path that was never
built would misstate what this unit costs. Arm (d) is redefined here to measure the *other* writer
`S3` also changed — `scripts/record-recovered-cost.sh`'s own appending path — which arms (a)-(c) do
not exercise at all, and which `OQ2`/`SL8` place squarely in this unit's scope.

---

## 2. The four arms, same-driver interleaved control

| Arm | What it is | version | n | mean | median | min | max |
|---|---|---|---|---|---|---|---|
| **(a)** | `record-cost-event.sh`, appending, ledger **under** cap (cap 5000, 10 lines seeded once, unique `tool_use_id` per trial) | pre | 20 | 136.7 ms | 134.7 ms | 131.1 ms | 165.3 ms |
| | | post | 20 | **136.0 ms** | **134.5 ms** | 129.7 ms | 154.1 ms |
| **(b)** | `record-cost-event.sh`, appending, ledger **over** cap (cap 15, re-seeded to 5000 before each trial, unique `tool_use_id` per trial) | pre | 20 | 147.6 ms | 143.0 ms | 141.1 ms | 194.1 ms |
| | | post | 20 | **147.1 ms** | **145.7 ms** | 140.1 ms | 166.8 ms |
| **(c)** | `record-cost-event.sh`, arrival that appends nothing — a duplicate finish for an id already recorded, ledger **over** cap (cap 15, re-seeded to 5000 before each trial) | pre | 20 | 144.4 ms | 143.5 ms | 138.9 ms | 162.3 ms |
| | | post | 20 | **144.9 ms** | **143.1 ms** | 138.8 ms | 157.9 ms |
| **(d)** | `record-recovered-cost.sh` (the OTHER writer S3 also changed), appending, ledger **over** cap (cap 15, re-seeded to 4998 filler lines plus a fresh start/finish pair per trial so lookup succeeds) | pre | 20 | 66.1 ms | 65.9 ms | 64.5 ms | 69.3 ms |
| | | post | 20 | **66.1 ms** | **65.8 ms** | 64.6 ms | 69.4 ms |

Deltas (post minus pre):

| Arm | mean delta | median delta |
|---|---|---|
| (a) | **-0.7 ms** | **-0.2 ms** |
| (b) | **-0.5 ms** | **+2.7 ms** |
| (c) | **+0.5 ms** | **-0.4 ms** |
| (d) | **0.0 ms** | **-0.1 ms** |

Ledger end-state, confirmed for every arm (matching `measure-e8-after.md`'s own confirmation
practice): arm (a) ends at 30 lines (10 seeded + 20 appended, no eviction — cap is 5000) for both
versions; arms (b), (c), and (d) each end at exactly 15 lines for both versions (the cap the arm ran
under), confirming every trial in those arms genuinely ran a full convergence, not a no-op.

---

## 3. The falsifiable check, and what it actually shows

`SL6` requires stating plainly, arm by arm, whether the post figures sit inside the pre arm's own
observed min-max spread — and returning `needs-decision` if an appending arm shows a consistent,
one-directional cost the code did not have before. Read literally against the raw min/max, three of
four arms have a post-side extreme that sits marginally outside the pre-side range:

- (a): post min 129.7 ms is 1.4 ms below pre min 131.1 ms.
- (b): post min 140.1 ms is 1.0 ms below pre min 141.1 ms.
- (c): post min 138.8 ms is 0.1 ms below pre min 138.9 ms.
- (d): post max 69.4 ms is 0.1 ms above pre max 69.3 ms.

**None of these is evidence of added cost, and none licenses `needs-decision`, for a reason stated
plainly rather than rounded away: every one of them is on the FASTER side of the comparison, or
smaller than this instrument's own rounding (0.1 ms), except (d)'s 0.1 ms high-side edge, which is an
order of magnitude below the ~3-5 ms of scheduler jitter visible elsewhere in the same table (e.g.
(b)'s own pre max of 194.1 ms against its mean of 147.6 ms).** The check this criterion exists to
catch is a *consistent, one-directional* shift toward more work — S3 adding a wait, a poll, or I/O
that was not there before. What is observed instead is four mean deltas within ±0.7 ms and four
median deltas within ±2.7 ms, straddling zero, on baselines of 65-150 ms — the same shape
`measure-e8-after.md` §3 called "what no new work on the appending path looks like when it is
measured rather than asserted." `L7` is not traded: no appending arm's typical (mean/median) cost
moved in the direction that would mean added work, and the marginal min/max crossings above are
consistent with ordinary scheduler noise on a shared host, not with a code path that grew.

---

## 4. Method — where it matches `measure-e8-after.md`'s, and where it necessarily differs

Matched, point by point:

- **Payload built outside the timed interval**, once per trial, before the timed call.
- **One timed interval = one `bash <script>` invocation**, measured immediately before and after
  that single process returns, via `time.perf_counter()` around `subprocess.run` — the same
  instrument `measure-e8-after.md`'s Appendix records, reused rather than re-derived, so a future
  comparison against either file is like-for-like.
- **Fresh throwaway `CLAUDE_PROJECT_DIR`** per arm per version, never this repository's `.claude/`.
- **n = 20 per arm per version**, interleaved.
- **Unique id per appending trial** (arms a, b, d) so no trial silently becomes a duplicate-finish
  arrival instead of an append — the exact trap `measure-e8-after.md` §4 names and that a first
  control run there actually fell into.
- **Same host shape**: macOS on arm64, bash 3.2.57.
- **Serial trials only.** No trial contended the evict lock with another, so no lock was contended or
  left stale.

Differs, and why:

1. **Two writers instead of one.** `measure-e8-after.md` measured only `record-cost-event.sh`, the
   hook-wired path, because that unit's relocation touched only the derivation both writers shared.
   This unit's `S3` changed the trap/flag in *both* writers independently, and arm (d) is the only
   arm that exercises `record-recovered-cost.sh`'s own append path — without it, half of what `S3`
   changed would go unmeasured.
2. **No degraded-base arm.** The original slice envelope's arm (d) timed a relocation fallback branch
   that does not exist in this unit's shipped code (`S5` dropped). Substituted with the other writer's
   append path, per §1 above, rather than fabricated.
3. **`sha` differs from `measure-e8-after.md`'s by construction** — that file measured a different
   unit's before/after pair (`d883886`/`13d3407`) for a different change (`S5`'s relocation there,
   which this unit does not ship). This file's pair (`27b4133`/`d7cdc40`) isolates `S3`'s trap alone.

---

## 5. What this file does not claim

- Nothing about **CI's** cost. Every figure is this host, serial, at n=20.
- No rate, no percentage, no "usually", no extrapolation from 20 samples to a distribution.
- No claim that any figure is acceptable or unacceptable — reported as a number; what to do with it is
  not this slice's call.
- No change to `scripts/`, `tests/`, `README.md`, `.github/`, `spec.md`, `decisions.md`, the other
  `spike-*.md`/`measure-*.md` files, or any other unit's artifacts.
- Not a claim that this leak is fixed, closed, resolved, or prevented — this file is a cost
  measurement, not a status report on the leak; see `decisions.md` for that.
