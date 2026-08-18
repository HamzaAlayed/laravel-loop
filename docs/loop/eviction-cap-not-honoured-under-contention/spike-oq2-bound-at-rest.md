# Spike — OQ2: is a bound at rest achievable without giving up L7?

**Slice:** S1. **Read-only.** This file names no fix, sketches no mechanism, and picks neither of
`OQ1`'s two options. It answers exactly one question: can `E1`'s property 2 ("at rest") hold at the
same time as `L7` as documented and as guarded — achievable / not achievable / unknown.

Base confirmed against `main` before writing: `main` and this worktree both at `d24e2ce`
(`eviction-cap-not-honoured-under-contention/slices.md` and `spec.md` present); no merge was needed.

---

## 1. L7's guarantee, quoted verbatim from both places that define it

**The header** (`scripts/record-cost-event.sh`, the "Bound + oldest-first eviction" block, lines
95–98):

> "Appenders never contend for that lock and
> never block on it (L7) -- they poll briefly for it to clear, then append
> regardless of whether it did, because cost accounting that can stall a
> spawn is worse than a ledger that sits slightly over cap for a moment."

**Case (g)'s own comment** (`tests/guardrails.test.sh`, lines 467–471):

> "-- (g) L7 regression guard (S5): with the evict lock held by another
> process for far longer than any appender should ever wait, an append still
> completes -- its own line lands, and its wall clock does not scale with how
> long the lock stays held. GREEN before and after this slice's fix: it
> proves the fix did not cost L7, not that the fix works (that is case (f))."

**Case (g)'s assertion string**, verbatim (line 484):

> "L7: an append lands its line while the evict lock is held, and its own wall clock stays well
> under the hold time"

So "giving up L7" has one fixed meaning for the rest of this document: making an appending
invocation's own wall clock scale with (or otherwise gate on) another invocation's hold of
`.claude/loop-cost-evict.lock`, in place of the poll-briefly-then-append-regardless behaviour these
three quotations describe and guard.

---

## 2. Verdict

**OQ2: not achievable.** `E1`'s property 2 (at rest — the file is at or under cap once the last
append of a run has landed and its invocation has returned) cannot be *guaranteed* at the same time
as `L7` as documented and as guarded. It can, and today usually does, hold by the accident of which
invocation happens to win the eviction race — that is exactly what makes it look intermittently true
— but "usually true by race outcome" is not the same claim as "achievable," and the difference is
the whole reason this spike exists.

### The structural argument

1. `L7` says every appender polls the lock briefly and then **appends regardless of whether it
   cleared** — it never waits, retries, or otherwise gates its own return on the lock's
   availability.
2. `append_and_evict()`, read literally (`scripts/record-cost-event.sh:253-288`), gives every
   appending invocation exactly **one** `mkdir "$EVICT_LOCK"` attempt (line 265). An invocation that
   loses that attempt runs no eviction code at all and returns immediately after its own `>>`
   (line 263) — there is no second attempt, no queue, no signal to anything else that trimming is
   still owed.
3. spec.md's own structural fact (`eviction-cap-not-honoured-under-contention/spec.md`, "1. L7 and
   the last appender") states it plainly: "some invocation always appends last, after the final
   trim, with no later appender obliged to re-evict."
4. Whether that last-appending invocation happens to be the one that also won the lock (and
   therefore ran a convergent trim before returning) is a **race outcome**, not something the
   invocation can know or control at append time — no invocation can tell, from inside its own
   single event, whether it is the run's last append. A run is only "over" in hindsight.
5. Therefore any obligation that would guarantee property 2 must be dischargeable by *whichever*
   invocation turns out to be last, unconditionally — including the case where that invocation lost
   the lock race (or won it but hit one of the loop's own I/O-failure breaks, `:276`, `:279-282`,
   `:283`, before reaching cap). Discharging that obligation for a lock-loser requires it to either
   wait for the lock to become available, or retry until it acquires it — both of which are the
   literal thing `L7`'s quotations above say never happens.

So the incompatibility is not "L7 makes property 2 unlikely" — it is that **property 2, read as an
unconditional guarantee, requires exactly the behaviour L7's own header rules out**: a returning
invocation certain enough of the file's state to promise it, when the one way to be certain under
contention is to wait for the lock. Every candidate obligation-carrier examined in §3 either
reduces to this same wait (and gives up `L7`) or does not actually deliver property 2 at the moment
of return (and delivers property 3 instead, sometimes with a much shorter window, but a window
nonetheless).

### What would refute this verdict

A demonstration — an observation or a structural argument — of a way for the invocation that turns
out to be a run's last appender to guarantee, **without ever waiting for, retrying, or otherwise
gating its return on `.claude/loop-cost-evict.lock`**, that the file is at or under cap by the
instant it returns. No such way is identified below: every non-blocking class considered either
does nothing for the appending path at all (and so only ever converges *if* something later happens
to run — property 3, not 2) or reaches for lock-waiting to make the guarantee real (and gives up
`L7`). A single surviving counter-example to that split would refute "not achievable" outright, and
none is asserted to exist here — this is `unknown`'s companion, not `unknown` itself, because the
argument in §2 is a closed one given `L7`'s wording as quoted, not an absence of search.

**Preliminary, applying to every class in §3:** none of them delivers `E1`'s property 1 ("at every
instant"), and none is examined for it. spec.md already establishes that property 1 is incompatible
with the unconditional `>>` on its own (`record-cost-event.sh:263` lands the line before any trim
could run), independent of who is obliged to trim afterward — that conflict is with the append
order itself, not with `L7`, and it is not re-litigated here.

---

## 3. Per-class table of obligations

Each row: which of `E1`'s three properties the class would deliver, its status against `L7` as
quoted in §1, and the work it adds to an **appending** invocation. Naming a class is not designing a
fix — none of these is sketched, sized, or recommended.

| Class | What it would mean | E1 property delivered | L7 status | Cost added to an appending invocation |
|---|---|---|---|---|
| **1. The appender itself, before it returns** | Every appending invocation — not only the one that wins the lock today — is obliged to guarantee cap compliance before returning: confirm the file is already at/under cap, or complete a trim, first. | Property 2, but only for the run whose last appender actually reaches that guarantee. | **Gives up `L7`.** When the lock is already held elsewhere, discharging the guarantee needs either waiting for it (the literal thing `L7`'s header rules out) or trimming without it, which reopens the single-writer premise `H3`/`L5` and the `mkdir` mutex exist to hold. | Unbounded in the waiting form — bounded only by however long the current holder's own convergence loop runs, which `append_and_evict()`'s own comment (`:270-273`) already says has no fixed bound ("converges only if concurrent appends land slower than the loop can absorb them"). Paid by *every* appending invocation, not only the ones that happen to hit contention. |
| **2. A lock-loser that retries** | An invocation that fails its `mkdir` attempt does not return immediately (as it does today, `:265` `if`-false path) but polls or retries until it acquires the lock and can trim, before returning. | Property 2, under the same condition as class 1. | **Gives up `L7`.** "Poll briefly... then append regardless" becomes "poll until acquired, then act" — from the caller's side this is indistinguishable from blocking on the lock, which is exactly the trade the header names and rejects ("cost accounting that can stall a spawn is worse than a ledger that sits slightly over cap for a moment"). | Unbounded, and compounding under a burst: several losers retrying for the same lock queue behind one another and behind whichever invocation is trimming, so a spawn-stalling effect can now cascade across concurrently spawned invocations instead of touching only the rare one that loses today. |
| **3. A later invocation** | Some subsequent invocation — whenever the next one happens to run — is obliged to check and trim on arrival, unconditionally, regardless of what its own append needs. | Property 3 only. spec.md's own definition of property 3 **is** "at or under cap once some later invocation happens to run" — this class does not close the gap between 2 and 3, it names 3. | Fully compatible — it changes nothing about any appending invocation's own path. | Zero on the invocation that made the run's last append; it has already returned by the time this could fire, if it ever does — the whole cost lands on whichever invocation runs next, contingent on one running at all. |
| **4. The run's end** | A mechanism tied to the run concluding, rather than to any one append, runs a single final sweep. | At best a tighter-latency variant of property 3, not property 2 — the file is only known-compliant once that mechanism has actually executed, which is strictly after the last appending invocation already returned, so the wording "once...its invocation has returned" is not satisfied at the instant of return. The window between return and the sweep is nonzero by construction, however small. | Compatible with every appending invocation's own path — none of them changes. Whether such a mechanism reliably fires at all is a separate, unestablished question this lane does not investigate (out of scope by this envelope's Constraints; not the same question as `L7`). | Zero on every appending invocation; the entire cost is externalised to a once-per-run mechanism whose own cost and reliability are not measured here. |
| **5. Anything else the reading suggests — a detached continuation the appending invocation does not wait for** | The invocation that made the (possibly-last) append forks off trimming work and returns without waiting on it. | Property 3 at best, for the identical reason as class 4: the trim may still be incomplete at the instant of return, so property 2's wording is not met — it is a latency variant of "later invocation," not a different property. | Arguably preserves `L7`'s letter (the returning invocation itself never waits) but reopens the fragility `L7`'s own design deliberately avoided: a short-lived hook process's child may be reaped before finishing, and multiple detached continuations from a burst of appenders would race the single-attempt `mkdir` mutex against each other with no coordinator. | Non-zero even in the best case: at minimum the cost of spawning an additional process, layered on top of the invocation's own already-measured cost (§4). Paid by every appending invocation that reaches this path, not only the ones under contention. |

**Reading the table as a whole:** every class that delivers property 2 (1 and 2) gives up `L7`
exactly as quoted in §1. Every class that keeps `L7` intact (3, 4, 5) delivers property 3, not
property 2 — sometimes with a much shorter window than "indefinitely," but a window all the same.
No row occupies the cell "delivers property 2 and keeps `L7`," and §2's structural argument is the
reason none does: that cell is where the incompatibility lives, not a gap this table happened not to
fill.

---

## 4. E8's before-half — what an append costs today

Measured on a **throwaway `CLAUDE_PROJECT_DIR`**, never the real repository's `.claude/`. Older
script versions were not needed for this measurement; the script measured is today's HEAD, copied
read-only into the throwaway directory.

- **Host:** macOS 26.6.1, arm64 (`Darwin ... 25.6.0 ... RELEASE_ARM64_T6000`), `GNU bash, version
  3.2.57(1)-release (arm64-apple-darwin25)` — the maintainer's own host shape.
- **sha:** `d24e2ce500ad00f241e17ffd6b2d04fc1910b98e` (this worktree, fast-forwarded to `main`
  before any file was written).
- **Method:** for each trial, a pre-built `PostToolUse` "finish" payload (built outside the timed
  interval) is piped to `bash record-cost-event.sh` under a fresh `CLAUDE_PROJECT_DIR`, with wall
  clock measured immediately before and after that one `bash` invocation returns. 20 trials per
  ledger state.

**Under cap** (`LARAVEL_LOOP_COST_MAX_LINES=5000`, ledger pre-seeded to 10 lines — no eviction
attempted; confirmed by the ledger holding exactly 30 lines, 10 seeded + 20 appended, after all 20
trials):

- n=20, mean **148.0 ms**, median **144.5 ms**, min 136 ms, max 216 ms

**Over cap** (`LARAVEL_LOOP_COST_MAX_LINES=15`, ledger re-seeded to 5000 lines before *each* trial
so every one of the 20 calls wins the lock and runs the full `wc -l` → `tail -n 15` → `mv`
convergence loop; confirmed by the ledger holding exactly 15 lines after every trial):

- n=20, mean **153.2 ms**, median **149.5 ms**, min 145 ms, max 180 ms

**Delta attributable to a real eviction (5000 → 15 lines) on this host:** approximately **5 ms**
mean, **5 ms** median, on top of the ~148 ms baseline dominated by process/interpreter startup for
the hook invocation itself (both arms pay that startup cost; only the over-cap arm pays the
eviction loop). This is `E8`'s before-half only — what today's mechanism costs where it is paid, on
the maintainer's host, at this trial count. It is not a claim about CI's cost, about any other
concurrency level, or about what a closing mechanism (if `OQ1`/the second G1 produces one) would
cost — that after-half belongs to whatever slice changes the appending path, measured against this
baseline in the same commit.

---

## 5. What this spike does not do

- It does not pick between `OQ1`'s two options, recommend either, or phrase §2 so that revising
  `L7` reads as the only remaining choice. If a bound at rest is wanted, §3's classes 1 and 2 are
  where that revision would have to land, and §3 states their cost; whether that trade is worth
  making is the human's, at the second G1.
- It does not sketch, size, or prototype any of the five classes beyond the table above.
- It did not investigate or fix the stale evict lock (`OQ4`); no trial in §4 involved lock
  contention (all 40 trials ran serially, one invocation at a time, so no lock was ever contended
  or left stale), and none was tripped over.
- It re-tests neither the platform nor the shell-dialect question, both closed twice per
  `spike-case-a.md` §1 and the macOS CI job.
