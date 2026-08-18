# E8, after-half — what S5's change costs, and where

`S6` of the fix group. Companion to `spike-oq2-bound-at-rest.md` §4, which holds E8's before-half.
Markdown only: this file is this slice's whole diff.

**Host:** `Darwin 25.6.0 ... RELEASE_ARM64_T6000`, arm64 — macOS on the maintainer's own host shape;
`GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)`.
**sha measured:** `13d3407d55854a8f79f40711e583392c2a30d71f` (`main`, S5 merged).
**Pre-change script for the control:** `d883886` — `main` immediately before S5, obtained read-only
with `git show d883886:scripts/record-cost-event.sh`. No `checkout`, no branch, no stash.
**n = 20 per arm per version**, every trial against a fresh throwaway `CLAUDE_PROJECT_DIR`. This
repository's own `.claude/` was never written to.

Every figure below is a count of milliseconds over 20 samples. One trial is one sample. No rate, no
percentage, and no extrapolation to CI or to any other host is stated anywhere in this file.

---

## 1. The headline, stated before the tables

- **The appending path's cost did not move.** In a same-driver, interleaved before/after control,
  arm (a) moved by **-0.5 ms mean / +0.9 ms median** and arm (b) by **-2.6 ms mean / +4.6 ms
  median**, with the two versions' min-max ranges overlapping in both arms (a: pre 113-141, post
  113-133; b: pre 123-230, post 123-164). Both deltas straddle zero across mean and median, which is
  what "no new work on the appending path" looks like when it is measured rather than asserted.
- **The newly-obliged arrival path pays, and here is the number.** A `PostToolUse`/`Bash`
  arrival that appends nothing costs **+16.1 ms mean / +15.7 ms median** more than before when the
  ledger is over cap (it converges a 5000-line ledger to 15), and **+6.7 mean / +7.1 median** more
  when the ledger is under cap (it pays one `wc -l` and stops).
- **The trim is provably the new part.** In every over-cap arrival arm, the pre-change script left
  the ledger at **5000 lines** and the post-change script left it at **15**. The cost above buys
  exactly that difference.
- ⚠ **One flag, stated plainly rather than rounded away** — see §4: arms (a) and (b) measured here
  sit **below** `spike-oq2-bound-at-rest.md` §4's observed min for the same arms. The direction is
  the opposite of a regression, and both arms move together, which points at the timing instrument
  and host load rather than at the code — but the literal min-max spread check S6 asks for against
  S1's figures is therefore **inconclusive**, and the same-driver control in §3 is what actually
  tests the claim. That substitution is the decision this file surfaces.

---

## 2. The three arms S6 asks for, at the measured sha

Figures are the post-change (`13d3407`) side of the control run in §3, so each arm's baseline was
gathered by the same driver in the same session.

| Arm | What it is | n | mean | median | min | max |
|---|---|---|---|---|---|---|
| **(a)** | appending invocation, ledger **under** cap (cap 5000, 10 lines seeded, unique `tool_use_id` per trial) | 20 | **118.0 ms** | **116.7 ms** | 113 ms | 133 ms |
| **(b)** | appending invocation, ledger **over** cap (cap 15, re-seeded to 5000 lines before each trial, unique `tool_use_id` per trial) | 20 | **136.6 ms** | **131.9 ms** | 123 ms | 164 ms |
| **(c-over)** | arrival that appends nothing — `PostToolUse`/`Bash`, ledger **over** cap (cap 15, re-seeded to 5000 before each trial) | 20 | **70.8 ms** | **70.1 ms** | 69 ms | 75 ms |
| **(c-under)** | arrival that appends nothing — `PostToolUse`/`Bash`, ledger **under** cap (cap 5000, 10 lines seeded) | 20 | **61.1 ms** | **61.0 ms** | 59 ms | 64 ms |
| **(d-over)** | the *second* obliged arrival — duplicate finish for an already-recorded id, ledger **over** cap | 20 | **152.2 ms** | **153.3 ms** | 128 ms | 189 ms |
| **(d-under)** | duplicate-finish arrival, ledger **under** cap | 20 | **127.6 ms** | **120.6 ms** | 113 ms | 217 ms |

Arm (c) is reported in **both** ledger states because the over-cap state is the only one where the
new work is actually paid; the under-cap state is what the path costs whenever the ledger is
already within cap, which is the state a `Bash` arrival finds it in except after a lock-losing
append.

Arms (d-over) and (d-under) were **not** asked for by S6. They are included because S5 obliged *two*
arrival sites, not one, and a record that timed only the `Bash` site would understate what was
changed. A duplicate finish costs more than a `Bash` arrival in both ledger states because it does
the full Agent/Task-shaped extraction before reaching the dedup discard — work that predates S5.

---

## 3. The same-driver before/after control — the falsifiable part

Twenty trials per arm per version, **interleaved** (pre, post, pre, post …) so host drift lands on
both versions rather than on one. Identical driver, identical payloads, identical seeding, one timed
interval per `bash <script>` invocation.

| Arm | pre (`d883886`) mean / median / min / max | post (`13d3407`) mean / median / min / max | delta post-pre (mean, median) | ledger left at |
|---|---|---|---|---|
| **(a)** appending, under cap | 118.5 / 115.8 / 113 / 141 | 118.0 / 116.7 / 113 / 133 | **-0.5 ms, +0.9 ms** | 30 lines both |
| **(b)** appending, over cap | 139.3 / 127.3 / 123 / 230 | 136.6 / 131.9 / 123 / 164 | **-2.6 ms, +4.6 ms** | 15 lines both |
| **(c-over)** Bash arrival, over cap | 54.7 / 54.4 / 53 / 57 | 70.8 / 70.1 / 69 / 75 | **+16.1 ms, +15.7 ms** | **pre 5000, post 15** |
| **(c-under)** Bash arrival, under cap | 54.4 / 53.9 / 53 / 57 | 61.1 / 61.0 / 59 / 64 | **+6.7 ms, +7.1 ms** | 10 lines both |
| **(d-over)** duplicate finish, over cap | 130.9 / 131.6 / 115 / 145 | 152.2 / 153.3 / 128 / 189 | **+21.3 ms, +21.7 ms** | **pre 5000, post 15** |
| **(d-under)** duplicate finish, under cap | 118.4 / 114.3 / 108 / 148 | 127.6 / 120.6 / 113 / 217 | **+9.2 ms, +6.2 ms** | 11 lines both |

**The verdict this control licenses, and its limit.** On this host, at this trial count, with this
driver: the appending path's cost did not move (arms (a) and (b), deltas straddling zero across mean
and median, ranges overlapping), and the arrival path now pays the trim it was obliged to pay (arms
(c) and (d), the over-cap ones each paying for a 5000 → 15 convergence the pre-change script did not
perform at all). What would refute it: an arm (a) or (b) delta that a repeat run reproduces as
consistently positive and outside the overlapping ranges — that would mean S5 put cost on an
appending invocation's own path, which is the one thing the second G1's decision forbids, and it
would be `needs-decision`, not a rounding note. No such delta was observed here.

---

## 4. Method — where it matches S1's, and where it could not

Matched, point by point:

- **Payload built outside the timed interval.** Each payload is built once, before any trial.
- **One timed interval = one `bash record-cost-event.sh` invocation**, measured immediately before
  and after that single process returns.
- **Fresh throwaway `CLAUDE_PROJECT_DIR`**, never this repository's `.claude/`.
- **n = 20 per arm.**
- **Under-cap arm:** `LARAVEL_LOOP_COST_MAX_LINES=5000`, ledger pre-seeded to 10 lines, no
  re-seeding — confirmed by the ledger holding exactly 30 lines (10 seeded + 20 appended) after the
  arm, the same confirmation S1 recorded.
- **Over-cap arm:** `LARAVEL_LOOP_COST_MAX_LINES=15`, ledger re-seeded to 5000 lines before *each*
  trial so every trial wins the lock and runs a full `wc -l` → `tail -n 15` → `mv` convergence —
  confirmed by the ledger holding exactly 15 lines after every post-change trial.
- **Same host shape** as S1's: macOS on arm64, bash 3.2.57.
- **Serial trials only.** No trial contended the evict lock with another, so no lock was contended or
  left stale, and `OQ4` was not tripped over.

Could not be matched, and why — each of these is a reason a figure here is **not** interchangeable
with a figure in `spike-oq2-bound-at-rest.md` §4:

1. **The timing instrument is not S1's.** S1's file records *that* wall clock was taken immediately
   around the invocation, not *with what*. This run used a Python driver taking
   `time.perf_counter()` around `subprocess.run`. A driver that measures a tighter interval reports
   smaller absolute numbers for identical work, and that is the most likely reading of §1's flag:
   **both** arms (a) and (b) land below S1's recorded min (a: 113-133 here vs 136-216 there; b:
   123-164 here vs 145-180 there), in the same direction, on a host whose load is not S1's either.
2. **Therefore the spread check S6 specifies — "does arm (a)/(b) sit inside the baseline arm's own
   observed min-max spread" — answers *no*, and that answer is not evidence about the code.** It is
   stated here rather than smoothed over, and §3's same-driver control is offered in its place:
   there, each arm's baseline was gathered by the same instrument, in the same session, interleaved
   trial by trial. Reconstructing S1's exact instrument for a like-for-like re-measure is possible
   and is the alternative this file's reader may prefer.
3. **A dedup trap the before-half never had to avoid.** A finish payload reused across trials is
   discarded as a duplicate after the first, so trials 2-20 would silently measure the
   *duplicate-finish arrival* path instead of the appending path. A first control run made exactly
   that mistake; every appending arm above uses a unique `tool_use_id` per trial, and the arms that
   deliberately reuse one are labelled (d) and reported as arrivals, not appends. Anyone re-running
   this must do the same or they will measure a different path than they think.
4. **`sha` differs from S1's by construction.** S1 measured `d24e2ce`; the after-half must measure
   the sha that contains S5.

---

## 5. What this file does not claim

- Nothing about **CI's** cost. Every figure is this host, serial, at n=20. `E2` remains outstanding
  and is the human's, post-merge.
- No rate, no percentage, no "usually", no extrapolation from 20 samples to a distribution.
- No claim that the arrival path's cost is acceptable or unacceptable — it is reported as a number,
  and what to do with it is not this slice's call.
- No change to `scripts/`, `tests/`, `README.md`, `.github/`, `spec.md`, `decisions.md`, the three
  `spike-*.md` files, or any other unit's artifacts.
