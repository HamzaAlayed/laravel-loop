# stale-evict-lock-permanently-defeats-the-cap

**Status: G0 held 2026-08-19 — approved, with one recommendation deliberately overruled.** All seven
questions this document opened are answered; the answers, and what each forecloses, are in *Decisions
taken at G0* below. The overrule is `OQ6`: the lock's **relocation is in this unit**, not a later
gate. My recorded caution — that relocating shared state deserves its own gate — is overruled on
purpose and is carried below rather than dropped, because it names the work relocation adds.

Source: `docs/loop/stale-evict-lock-permanently-defeats-the-cap/intent.md` (captured
2026-08-18T19:30:00Z), authoritative and not re-derived here. Prior art, read in full before writing
this: `docs/loop/eviction-cap-not-honoured-under-contention/spec.md` (the same mechanism, the
adjacent hole, and `OQ4` where this was last scoped out); the second G2 verdict in
`docs/loop/harness-fails-only-on-linux/verify.md` ("Stale-lock status — re-examined, not
re-litigated"); `docs/loop/decisions.md`'s convergence entry, its arrival-trim build-out, and its
`2026-08-19` backlog gate.

Amends nothing. This is not a continuation of the convergence unit: that hole is closed, this one is
a second route to the same observable and it is **pre-existing, structural, and never yet observed
failing in a real run** — established by reading `scripts/record-cost-event.sh`, not from a red.

**Build order, recorded because it is a real coupling.**
`docs/loop/resumed-invocation-never-reaches-the-ledger/` was specified in parallel, touches the same
`scripts/record-cost-event.sh`, and is ordered **after** this unit — partly so that it adds records to
a working cap rather than a defeated one. Nothing in this unit is edited in service of it, and the two
must not be built in the same lane.

## Problem

**The ledger's line cap can stop being enforced permanently, and nothing anywhere says so.** One
interrupted invocation is enough: the thing that was trimming the file leaves a marker behind that it
never clears, and from then on every later run adds a line and trims nothing, silently, for as long
as that marker sits on disk. There is no error, no warning, no output, and no route by which anyone
finds out other than reading the source or noticing the file is large.

Three things a person actually feels:

1. **A declared bound quietly stops being a bound, forever.** Not "for a moment", which the mechanism
   already documents and accepts, and not "until the next run", which the arrival trim already
   guarantees. Permanently, for the lifetime of that directory.
2. **The only recovery available today is one nobody has been told about.** A human who deletes one
   directory by hand fixes it completely. Nothing in the repository names the directory, the symptom,
   or the remedy, so the fix is available only to whoever already read the eviction code.
3. **The cost of being wrong about it points the other way from the cost of the fault.** An
   over-cap ledger loses nothing. A marker cleared while its owner was still working can cost
   records — and a lost finish record is the one thing in this system that cannot be reconstructed by
   any automatic route (only a human typing the figure by hand into
   `scripts/record-recovered-cost.sh`). So the naive fix is more expensive than the fault, which is
   why this has been declined three times rather than done quickly.

### What this unit actually achieves, in plain words

Written here, at the top, because with relocation in scope the honest summary changed shape and this
is the sentence most likely to be misread later.

**The leak is not fixed by this unit, and nothing in this repository may say it is.** Three things
change. An interrupted holder stops orphaning the lock for the kill classes a signal handler can
catch. An orphaned lock stops being permanent and becomes **bounded by the machine's uptime**. And if
one happens anyway, a person can find out. What remains, stated as plainly as the gains: there is a
kill class this repository cannot catch — and **the one kill it has actually recorded, a machine sleep
in `conventions.md`, is not established to be in the catchable class** — and a leak inside one boot
still defeats the cap for the rest of that boot, which on a laptop that sleeps rather than reboots can
be weeks. *Permanence bounded by uptime, and a silence ended.* Never "fixed", never "closed", never
"resolved".

## Users

- **Whoever's `.claude/` the ledger grows in.** Every `/loop` run appends to it, and the declared
  bound is what keeps a file nobody reads from growing without limit. Today they do nothing, because
  the state is silent and indistinguishable from a healthy ledger except by size. **Nobody has
  reported hitting this, and it has never been observed in a real run** — the failure rate, and
  whether interrupted evictions happen often enough to matter, are both unestablished and are not
  claimed here in either direction.
- **Whoever reads `/cost` or the budget gate output later.** Both read this file. Neither is known to
  misread an over-cap ledger and no such misreading is claimed — but the cap is a stated property of
  their input, and this is the route by which that property can be false indefinitely.
- **Whoever runs `scripts/record-recovered-cost.sh`.** A deliberate, human-typed CLI, at a prompt,
  where `Ctrl-C` is an ordinary thing to do — and it holds the same marker, at the same path, as the
  hook writer. Today they have no way to know an interrupted transcription left the hook writer's cap
  permanently unenforced.
- **Whoever picks this unit up next after it is declined again.** Today: rereads three units' records
  to rebuild the same question from scratch, because the question — can a lock be declared stale at
  all — has been asked three times and answered nowhere. As of this gate it is answered.

## The four things that make this hard, all first-class

None of these is an aside. A spec that files them as caveats produces a slice list that stalls on the
first one. §4 is new at this gate: it is the work relocation adds.

### 0. Read this before touching the lock: `rmdir` fails on a non-empty directory

Placed first, above everything, because it is the one fact that turns a plausible design into a
universal leak and it is exactly the kind of thing discovered on a third refine pass.

Release is `rmdir`, in three places: `scripts/record-cost-event.sh:311` (the append path),
`scripts/record-cost-event.sh:330` (the arrival trim), and `scripts/record-recovered-cost.sh:244`.
`rmdir` **fails on a non-empty directory**. So **anything written inside the lock directory breaks
every normal release** unless all three release sites change in the same commit — converting a leak
that needs a kill into a leak that happens on every single invocation. This is the recorded reason the
pid-in-the-lock design is rejected (see §1 and *Decisions taken at G0*), and it applies equally to a
timestamp, a marker, a heartbeat, or a note left for a human. **No builder needs to rediscover it.**

### 1. There is no liveness signal, and age is not one

Answered at G0: **no steal, ever.** The reasoning is ratified in full and recorded here because it is
what stops the question being asked a fifth time.

**Legitimate hold time is unbounded by design.** `converge_ledger()` is `while :;`
(`scripts/record-cost-event.sh:281`) with breaks only on real I/O conditions, deliberately:
`decisions.md` forecloses an attempt bound, an iteration counter, and a no-progress guard twice over,
because a bounded retry gives up while still over cap whenever appends land faster than a few passes
can absorb. A holder under sustained arrival pressure may therefore legitimately hold the lock far
longer than the measured ~16 ms of a quiet trim, with no stated ceiling. **Any finite age threshold is
therefore guaranteed to be wrong for some real workload** — and it would be a sixth tunable whose
correctness the design depends on, against a standing decision (`2026-08-19`) that all five existing
threshold variables stay unset with no defaults shipped. Age is the cheapest candidate and it is the
one this repository is least entitled to.

**The only liveness primitive available is `kill -0` on a recorded pid** — a bash builtin, no new
dependency, and, unlike age, no threshold at all. It is a real signal, and it is still not enough:
- *Safe direction:* pid reuse makes a dead holder look alive. Outcome: still over cap. Acceptable.
- *Unsafe direction:* a pid observed across a namespace or user boundary — the ledger written both
  inside a container and on the host, which this project's own investigations did routinely, or by a
  second uid — can make a **live** holder look dead. Outcome: a steal from a working evictor.
- *Structural gap:* `mkdir` and writing any identity into the lock cannot be one atomic act, so an
  observer can always see a lock that carries no identity yet. That state must be read as
  live-or-unknown, never as stale.
- *And it needs §0's write*, which breaks all three releases. Rejected on that alone.

**What a steal actually risks, precisely.** The intent states the asymmetry as *a torn ledger, worse
than a ledger over cap*, and that asymmetry stands. Read from the source, the concrete damage of two
simultaneous trims is **lost records** rather than partial lines: each trimmer writes a `tail -n
MAX_LINES` snapshot to a temp file (`record-cost-event.sh:286`) and `mv`s it over the ledger
(`:290`), so a line that lands between one trimmer's `tail` and its `mv` is gone. `H3`'s "retained
lines are complete, parseable, and the newest N in order" is the guarantee at risk, and per the
Problem section a lost finish record has no automatic recovery. This sharpens the intent's asymmetry
rather than softening it. *Not reproduced — read, like the fault itself.*

**The answer this section reaches, ratified at G0:** staleness cannot be *proved* with what this
repository has; it can at best be *inferred*, and every available inference either has an unsafe
direction or needs a threshold nobody can choose correctly. So **nothing in this unit ever infers
death.** What it does instead needs no staleness criterion at all: stop leaving the lock behind for
catchable kills, stop the state being silent, and bound how long a leak can survive rather than
judging whether it is one.

**Candidates, with their costs, kept so none is re-derived at G1:**

| Candidate | Needs | Cost, and how it can fail | G0 |
|---|---|---|---|
| Identity in the lock (pid + timestamp) + `kill -0` | A liveness read; a write inside the lock | §0: breaks all three `rmdir` releases; unsafe across pid namespaces and uids; a pre-identity window that must read as live; still only an inference | **Rejected** |
| Age-based expiry | A duration threshold | Legitimate hold is unbounded by design, so no correct value exists; a sixth tunable against a standing decision that ships none; `stat` flag spelling differs across the two guarding platforms | **Rejected** |
| Two-phase claim / heartbeat (liveness by observed progress) | A path licensed to **wait** | No such path exists: appenders may not (`L7`), and the arrival trim explicitly may not (`S5`, guarded by case (i)). Only a human-invoked path could host it — and it needs §0's write | **Rejected** |
| Detect and report only | Nothing beyond what an appender already evaluates | The cap stays unenforced until a human acts; needs somewhere to surface (`/cost` is read-only by charter — it can report, not repair); needs repeat-reporting bounded | **Taken** (`SL3`, `OQ4`/`OQ5`) |
| Release on catchable signals (trap while holding) | Nothing; no criterion, no threshold | Covers `INT`/`TERM`, not `KILL`, OOM, or power loss — and the one kill this repository has recorded is not established to be catchable. Narrows the window; does not close it. A mis-scoped trap could `rmdir` a lock this process does not own, reintroducing the steal risk as a bug | **Taken** (`SL3`, `SL5`) |
| Bound the leak by uptime (relocate the lock) | A location derived identically by both writers | Moves shared state; a partial relocation is a correctness regression; a reaped-by-age base smuggles back the age criterion §1 just rejected. All of §4 | **Taken** (`SL11`–`SL13`) |
| Do nothing but write the limit down | Nothing | The cheapest honest option, and it satisfies `SL1`/`SL2` alone. Leaves a stated bound that a single interrupted run disables forever | **Not taken alone**; `SL1`/`SL2` kept as part of the answer |

### 2. Two independent copies of the primitive, one shared lock path

`scripts/record-cost-event.sh` and `scripts/record-recovered-cost.sh` each carry their own
`append_and_evict()` with their own `mkdir`/`rmdir` pair — deliberately, per the recovered writer's
own header — but **both point at the same path**: `record-cost-event.sh:205` and
`record-recovered-cost.sh:99` are the identical `EVICT_LOCK="$DIR/loop-cost-evict.lock"`, over an
identically derived `DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude"`. Duplicated code, shared resource. So
the leak is symmetric and cross-cutting: a lock orphaned by the human-typed CLI permanently defeats
the hook writer's cap, and the reverse.

**Both writers are in scope, and the earlier decision is not being casually reversed.**
`decisions.md` rejected extending the arrival-trim obligation to `record-recovered-cost.sh` on the
grounds that it is human-typed with no contention. That rejection stands **for what it was about** —
an obligation to trim buys nothing where there is no contention. It does not transfer to lock
hygiene, for one reason stated plainly: **a leak needs an interruption, not contention**, and a
prompt is precisely where interruptions happen. Nothing about the earlier reasoning was wrong; it was
answering a different question.

### 3. Unlike its sibling, this one is cheap to prove

The convergence unit's hardest problem was that its failure could not be reproduced where a person
could watch it. This one is the opposite, and the harness already contains the construction: cases
(f), (g), and (i) of `tests/guardrails.test.sh` each `mkdir` the lock by hand, and case (i) already
asserts an over-cap ledger stays untrimmed while it is held. An orphaned lock is that same setup with
no releaser — **deterministic, no timing, no contention, no CI dependency**. Case (h) already asserts
the lock is *not* left behind after a failed `mv`, so "the lock must not outlive its holder" is
already an assertable property in this suite.

Consequence: `SL4`'s red-before-green is genuinely cheap here, and there is no excuse for a change to
this mechanism being believed without one. The residual platform exposure is in the *fix*, not the
fault — trap delivery, and whatever the relocated base turns out to be, differ between bash 3.2 on
macOS and bash 5.x on Linux. That is why `SL10` exists and why `SL11` demands evidence rather than a
citation.

### 4. Relocation is not a move, it is a shared contract (new at this gate)

`OQ6` was pulled into scope because it is the only option in the batch that attacks the **permanence**
directly, with no staleness criterion and no new threshold. What it adds:

**(a) Per-boot, and specifically not per-run.** The location must outlive an individual invocation —
a path that vanished mid-run would let a second party acquire a lock a live holder still holds, which
is the concurrent-trim loss this unit refuses to risk by stealing. It must also **not** outlive a
reboot, because that is the entire mechanism by which permanence becomes boundedness. Required
properties, which is what a builder is held to rather than a literal path: shared by every writer
guarding one ledger; distinct per checkout; surviving at least a whole run and normally a whole boot;
cleared by a reboot; creatable with bash + coreutils and no new dependency; and safe to `mkdir` in.

**(b) The candidate, and the thing that must be established rather than assumed.** The obvious base
is `${TMPDIR:-/tmp}` with a per-checkout name derived from the ledger's own resolved path. **Whether
that base is actually cleared by a reboot is not established in this repository, on either guarding
platform, and citing documentation is not establishing it** (`checks.md`'s own
citation-is-not-proof discipline). `SL11` requires the evidence, because the bounded-by-uptime claim
in the Problem section is worth nothing without it.

**(c) A reaped-by-age base would smuggle back exactly what §1 rejected.** If the chosen base is
cleaned by *age* rather than by boot — as a periodically-reaped temp directory is — then the OS is
applying an age-based staleness criterion on this project's behalf, with a threshold this project
does not choose, cannot see, and cannot test. That is the very design §1 rejected in principle, and
it can also delete a lock from under a **live** holder. It is tolerable only if `SL11`'s record states
it explicitly, states the reap interval observed, and states that it is orders of magnitude above any
hold ever measured here — and it is never described as the mechanism, only as a property of the base
that was accepted with its eyes open. **This is the weakest joint in the amendment and it is named,
not hidden.**

**(d) A world-writable base is a new permanent-defeat route.** If the base is shared between users
(the `/tmp` fallback when `TMPDIR` is unset, which is the common Linux case), another user can
pre-create the directory this project would create. Then `mkdir` fails forever, nobody ever trims, and
the cap is permanently unenforced — the same fault this unit exists to reduce, arriving by a new door,
and this time not clearable by the owner. `SL13` requires that an unusable or foreign-owned base
degrades to **today's behaviour** (the lock beside the ledger), never to running without a lock.

**(e) A partial relocation is a correctness regression, not an incomplete improvement.** Two writers
guarding one ledger through two different lock paths have **no mutual exclusion at all** — strictly
worse than the leak, because it makes the concurrent trim this unit refuses to risk reachable in
ordinary operation. Hence `SL12`: one derivation, and a case that fails if the two writers ever
disagree.

**(f) Relocation does **not** make the trap hygiene redundant, and the spec says so.** A leak inside
one boot defeats the cap for the rest of that boot; a machine that sleeps rather than reboots can hold
one for weeks. Relocation bounds the *duration* of a leak; the trap reduces how often one starts. They
address different halves and both ship, per `OQ7`.

**(g) The ledger does not move.** Only the lock. `.claude/loop-cost.jsonl` stays exactly where it is,
and so does every other `mkdir` marker (see Non-goals).

## Acceptance criteria

Each is observable, each names what would be checked, and none names a mechanism beyond what the G0
decisions fixed. `SL1` and `SL2` are first deliberately: they are satisfiable under every answer,
including "nothing changes in the code", and they are what stop the unit's own claim being overstated.

- [ ] **SL1 — the orphaned-holder case, and the honest limit of this unit, are written down where the
      cap's promise already lives.** The mechanism's own header states what happens to the cap when
      the thing holding the lock never releases it, next to the existing "eventual convergence, not a
      bound at rest" note, and names the remedy available to a human. *Checked by:* reading that note
      — the sentence promising convergence never appears without the orphan case beside it; and
      grepping the repository for any sentence that describes this leak as fixed, closed, resolved, or
      prevented, which must return nothing. "Bounded by uptime" is the strongest phrasing permitted.
- [ ] **SL2 — the staleness question is answered on the record.** `decisions.md` states that a lock
      cannot be declared stale with the signals available, records **no steal, ever** as the decision,
      and names each candidate in §1's table with the reason it was taken or declined — including
      §0's `rmdir` catch as the reason the pid-in-lock variant is rejected. *Checked by:* that entry
      existing and naming, by name, the alternatives it forecloses.
- [ ] **SL3 — an orphaned lock no longer leaves the cap unenforced *and* unannounced.** After the
      change: a holder killed by a catchable signal does not orphan the lock, and an orphaned lock
      that exists anyway is discoverable by a named human-facing route without reading the source.
      *Checked by:* constructing both cases — kill a holder mid-trim with a catchable signal and
      observe no lock left; create a lock with no holder and exercise the named route, which says so.
- [ ] **SL4 — the fault is reproduced red before anything is believed green.** An observation exists,
      reproducible by a second person, that is red against the pre-change scripts and green against
      the changed ones, with both shas and the trial count recorded. Given §3, a construction that
      cannot be made red locally is a failure of this criterion, not an excuse. *Checked by:* running
      it against both versions and reading the recorded evidence.
- [ ] **SL5 — no lock is ever taken from a live holder, by any route.** An observation exists in
      which a holder is mid-trim and a second party arrives: the holder keeps the lock, its trim
      completes, and the ledger afterwards is complete, parseable, and the newest N in order with no
      record lost. This covers the two new routes as well as the old one: a signal handler must
      release only a lock this process created, and the relocated base must not be one whose contents
      can be removed under a live holder within any interval this unit has observed (`SL11`(c)).
      *Checked by:* that case, plus `H3`'s existing cases unmodified, plus a read of the release path
      for its ownership condition.
- [ ] **SL6 — `L7` is not traded, and the cost is measured where it is paid rather than asserted.**
      Case (g) unchanged and green: an append lands its line while the lock is held and its wall clock
      does not scale with the hold. No appending path gains a wait, a second poll, a retry, or any
      work whose duration depends on another process. Case (i)'s never-waiting arrival is likewise
      unchanged. Whatever work the change adds to an appending invocation — including any path
      resolution the relocation introduces — is stated **as numbers**, before and after, on one host.
      *Checked by:* cases (g) and (i)'s results, a read of the diff for new waits on the append path,
      and the recorded timing observation. Never a claim that the added work is negligible.
- [ ] **SL7 — no new threshold, default, or suggested value ships.** `LARAVEL_LOOP_COST_MAX_LINES`
      stays the only cap at its existing default. Anything configurable introduced ships **unset** and
      is provably vacuous with it absent. No duration, interval, or margin is introduced by this
      unit's own code; the one age-like quantity in play belongs to the operating system, is not
      chosen here, and is recorded under `SL11`(c) rather than adopted. *Checked by:* grepping the
      diff for new environment names and numeric literals, plus a case asserting zero output and zero
      behaviour change with any new configurable unset.
- [ ] **SL8 — both writers are changed, and the record says why the earlier rejection does not
      transfer.** `scripts/record-recovered-cost.sh` holds the same lock contract as the hook writer,
      something checks **both**, and `decisions.md` states that the prior "no contention, human-typed"
      rejection was about a trim obligation and not about lock hygiene — a leak needs an interruption,
      not contention. *Checked by:* the diff covering both files, the case from `SL12`, and that
      sentence existing.
- [ ] **SL9 — nothing the ledger already guarantees regresses.** After the change: `L5` (concurrent
      finishes land intact), `L6` (exit 0 on every path, including the script's own errors), `L9` (one
      finish record per invocation via the `mkdir` marker), `H3` (never empty, never torn, newest N in
      order), `H5` (a deleted ledger is recreated by the next append), the non-numeric-cap fallback,
      the arrival trim's obligation and its never-waits contract, `shellcheck -S warning scripts/*.sh`
      clean, and the suite's case total does not drop. *Checked by:* the existing cases for each,
      unmodified, plus the before and after `total:` line.
- [ ] **SL10 — the change holds on both guarding platforms, on a real pushed commit, and one green
      run is read as one sample.** New and existing cases pass on both jobs, and the record states how
      many real runs were observed without treating a single green as a rate. This matters here
      specifically because trap delivery and the relocated base's own behaviour differ between bash
      3.2 on macOS and bash 5.x on Linux. *Checked by:* that run's own output for `guardrails` and
      `guardrails-macos`, both reporting an identical `total: N passed, M failed`. No container or
      local run substitutes.
- [ ] **SL11 — the relocated location is named, its per-boot property is established by observation,
      and any age-based reaping is recorded rather than relied on.** The record names the location and
      the rule that derives it; states why it is per-boot and not per-run, in the terms of §4(a);
      and carries **observed evidence** — on both guarding platforms — that a lock created there does
      not survive a reboot. A documentation citation is not evidence. If the base is instead cleared
      by age, that is stated explicitly with the interval observed, together with the fact that it is
      an OS-owned staleness threshold this project did not choose, and `SL5`'s live-holder guarantee
      is re-argued against it. *Checked by:* reading the record for the derivation, the properties, and
      the evidence; and by the reboot observation itself. Absent that evidence, the bounded-by-uptime
      claim in the Problem section is not made anywhere.
- [ ] **SL12 — the location comes from one place, and a divergence between the two writers is a red.**
      Both writers derive the lock's location by one rule, expressed once, such that two writers
      guarding the same ledger always agree and two guarding different ledgers never collide. A case
      exists that computes the location as each writer computes it and **fails if they differ** — so a
      future edit to one file alone cannot silently remove mutual exclusion. *Checked by:* that case,
      run and observed to fail when one writer's derivation is deliberately altered. A case that
      merely asserts a hard-coded expected path does not satisfy this.
- [ ] **SL13 — the old location, and an unusable new one, both have stated behaviour.** A lock left at
      the pre-change location by an earlier version is accounted for: the record states what happens
      to it, and it can never make the cap appear enforced when it is not, nor make a later version
      refuse to trim. And when the new base cannot be safely used — missing, unwritable, or owned by
      another user — behaviour degrades to **today's** arrangement, the lock beside the ledger, never
      to appending and trimming with no lock at all. *Checked by:* a case for each: a lock at the old
      path plus a normal run, and a base made unusable, asserting mutual exclusion still holds and
      exit 0 throughout.

## Non-goals

Read at G0 and unchanged by it, except where the relocation decision required a boundary to be drawn
more finely. Each is a direction this could plausibly wander, and several are directions adjacent
units already had to be pulled back from.

- **Not a reopening of `L7`.** Settled `2026-08-19`, not merely unexamined: the never-block guarantee
  is why cost accounting never delays a real tool return. No design here makes an appender block, wait
  longer, retry, or fail because of the lock — not temporarily, not "only when orphaned", not behind a
  flag. If `L7` is genuinely the thing to question, that is its own unit at G0.
- **Not a reopening of the cap's property or its obligation class.** `E1` property 3 (eventual
  convergence) and obligation class 3 (a later arrival trims unconditionally) stand as decided. This
  unit is about a lock that never releases, not about which property the cap promises.
- **Not a fix for the convergence hole.** The lock-losing last appender is closed by the arrival
  trim. Same observable, different mechanism, not reopened and not "improved while we are in here".
- **The ledger does not move, and nothing else moves.** Relocation applies to
  `loop-cost-evict.lock` and to nothing else. `.claude/loop-cost.jsonl`, the finished-marker
  directory, the open/pending/counts directories, and the eviction temp file that must stay on the
  ledger's own filesystem all keep their current locations. Their own orphan questions, if any, are
  separate intents; nothing is asserted about them here.
- **Not a redesign of the cost ledger.** Record shape, field set, JSONL format, oldest-first eviction
  order, the `mkdir` dedup marker, rework bookkeeping, `/cost`'s output, the budget gate, and
  recovered figures are all out of bounds beyond exactly what the G0 decisions require.
- **Not a change to the cap's value, default, or configurability**, and no new threshold, margin,
  interval, or suggested number anywhere in the repository.
- **Not an attempt bound, iteration counter, or no-progress guard on the trim loop.** Foreclosed
  twice. Shortening a legitimate hold is not a route to shortening a leak, and reaching for one owes
  an argument against the recorded reasoning rather than arriving as if it were not there.
- **No staleness criterion, no liveness inference, no steal.** Decided at G0. No pid, timestamp,
  heartbeat, age check, or "it has been there a while" heuristic, and nothing written **inside** the
  lock directory (§0). A design that infers a holder is dead is out of bounds even if it looks safe.
- **Not a fix for anything the lock never protected against.** The append-versus-trim loss window
  described in §1 and in *Handoff* below is pre-existing, unreproduced, and explicitly not in scope.
- **No background process, daemon, sweeper, cron entry, launchd or systemd unit, or periodic cleaner.**
  There is no evictor process in this design and this unit does not introduce one. Relocation is
  chosen precisely because the operating system already clears the base without this project running
  anything.
- **Not a change to `/cost`'s read-only charter.** It reports; it does not repair, delete, or release.
- **No new command, agent, hook, phase, or release gate**, and `scripts/ship-check.sh` stays at
  exactly three gates. `OQ4` is answered with documentation plus `SL3`'s report, and `OQ5` with
  surfacing where a human already looks — **no new record type is minted** for this.
- **Not a portability fix and no new dependency.** No `flock`, no vendored coreutils, no compatibility
  shim library, no raising the minimum above bash 3.2.
- **Not a CI change**, and **not making red acceptable**: no `continue-on-error`, no known-failures
  list, no quarantine, no advisory step.
- **No case weakened, deleted, skipped, or renumbered** as a route to green.
- **Not the sibling unit's territory.** `resumed-invocation-never-reaches-the-ledger` is ordered after
  this one and touches the same file. No edit is made in service of it, and no shared refactor is
  undertaken to accommodate it.

## Failure modes

| When | Expected behaviour |
|---|---|
| The lock's holder is killed mid-trim by a **catchable** signal (`INT` at a prompt, `TERM` from a harness) | The lock is released by the dying holder. `SL3`. Today it survives and the cap is never enforced again |
| The holder dies by an **uncatchable** route (`KILL`, OOM, power loss, or the machine-sleep class this repository has actually recorded) | The lock survives — **this is not fixed**. It is bounded: cleared at the next reboot, and discoverable before then. Nothing describes this case as closed |
| The lock is present with **no live holder** and the ledger is over cap; an appender arrives | It appends, does not trim, does not wait, and does not infer death. The state is reported by the route `SL3` names, not repaired by the appender |
| The lock is present with no live holder; an arrival that appends nothing | One `mkdir` attempt, immediate return, no trim, no inference. The arrival trim is defeated exactly as an appender is, by design |
| The lock is held by a **live** holder that is genuinely trimming | The holder keeps it. No second party trims, steals, waits, or blocks. `SL5` |
| A signal handler runs in a process that never acquired the lock | It releases nothing. A handler that could `rmdir` another holder's lock is the steal risk arriving as a bug, and `SL5` covers it |
| Anything is written inside the lock directory | Must not be reachable: `rmdir` at `record-cost-event.sh:311`, `:330`, and `record-recovered-cost.sh:244` would then fail and every release would leak (§0) |
| The machine reboots while a lock is orphaned | The lock is gone and the cap is enforced again on the next run. This is the whole value of relocation and the only automatic clearance in the design |
| The relocated base is cleaned by **age** while a live holder holds the lock | An OS-owned staleness criterion this project did not choose, capable of removing a lock from a live holder. Tolerated only under `SL11`(c), with the interval observed and recorded, and re-argued against `SL5` |
| The relocated base is missing, unwritable, or owned by another user (a squatted world-writable `/tmp`) | Degrade to today's arrangement — the lock beside the ledger — never to appending and trimming with no lock. `SL13`. Otherwise a stranger can permanently defeat the cap |
| The two writers derive different lock locations | Must be impossible by construction and red by test. Two writers guarding one ledger with two locks have no mutual exclusion at all — worse than the leak. `SL12` |
| The two writers resolve **different ledgers** (`CLAUDE_PROJECT_DIR` set for the hook, `$PWD` for a CLI run elsewhere) | Different ledgers correctly get different locks. The invariant is that the lock is a function of the ledger it guards — not that one lock exists per machine |
| A lock left at the **old** location by a pre-change version | Inert, and it must never make the cap look enforced when it is not, nor stop a later version trimming. `SL13` states what happens to it |
| Two trims somehow run simultaneously | Never observed: a lost record, a reordered line, a partial line, or an empty file. `H3` unchanged |
| `.claude/` — or the relocated base — is unwritable, so no lock can be created | Exit 0, no block, no delay, nothing written. `L6`, unchanged |
| A human deletes the lock by hand while a holder is live | Out of the mechanism's control by construction. The route `SL3` names says what is safe to do and when |
| `record-recovered-cost.sh` is interrupted at a prompt while holding the lock | Same hygiene as the hook writer: the lock is released for catchable signals, and bounded by uptime otherwise. In scope, per `OQ2` |
| The lock is present and the ledger is **under** cap | Nothing to trim, and nothing worth alarming anyone about. Reporting is bounded so a single orphaned lock does not flag on every invocation for its lifetime (`OQ5`) |

## Constraints

**Existing behaviour that must not change** (each has a guard today; regressing one is a failure of
`SL6`/`SL9`, not a trade):

- `L7` — appenders never block on the evict lock, and its documented precedence over `L9`. Guarded by
  case (g). **Settled, not merely unexamined** (`decisions.md`, `2026-08-19`), and not revisable
  inside this unit.
- `L6` — the hook exits 0 on every path. Cost accounting never blocks, delays, or alters a spawn.
- `L5` — concurrent finishes land as intact lines; no interleaving, no tearing.
- `L9` — one finish record per invocation, via the `mkdir` marker.
- `H3` — eviction never truncates the ledger, not even transiently; retained lines are complete,
  parseable, and the newest N in order.
- `H5` — an absent ledger is normal; the next append recreates it.
- The cap's property (`E1` property 3) and obligation class 3's arrival trim, including its
  never-waits contract, guarded by case (i).
- Case (h): the lock is released even when `mv -f` fails persistently.
- Both CI jobs run the identical suite with the identical invocation and no platform conditional;
  `docs/loop/checks.md` stays a true map of both check sets.
- `/cost` reads only and computes nothing itself.
- **The hook writer sources nothing.** `scripts/record-cost-event.sh` has no `source`/`.` of any
  library, deliberately; `scripts/record-recovered-cost.sh` does source `cost-ledger-lib.sh` and
  *refuses* when it is absent (`:145`–`:147`). A refusal is acceptable for a human CLI and is not
  acceptable on the hook path, where the degraded state would be running without a lock. This
  asymmetry is what `OQ3` was re-decided against.

**Environment:** bash 3.2 and coreutils only, zero dependencies, **no `flock`** (absent on macOS by
default). `kill -0` is the only liveness primitive available and is not used, per `OQ1`. Maintainer's
host is macOS/arm64/bash 3.2.57; guarding platforms are `ubuntu-latest` and `macos-latest`, the latter
a rolling image whose point version is not a fixed contract. Trap delivery, temp-directory location,
and temp-directory clearing policy all differ between those two, which is why `SL11` demands
observation on both rather than one.

**Configurability:** all five existing threshold variables stay unset with no defaults shipped
(`decisions.md`, `2026-08-19`). This unit introduces no threshold of its own; the only age-like
quantity in play is the operating system's own reaping interval, which is recorded under `SL11`(c),
never chosen, and never made configurable here.

**Evidence status:** pre-existing and structural, established by reading the source. **Never observed
failing in a real run**, no reproduction previously attempted, and no staleness criterion previously
proposed anywhere in this repository. No urgency is claimed from frequency, because none is known.

**Already rejected, and reaching for one owes an argument against the recorded reasoning:** an
attempt bound, an iteration counter, and a no-progress guard on the trim loop; arrival-trimming on
every invocation including appenders; a second copy of the trim loop; obliging the two unregistered
early exits; amending `L7`; a hard bound at rest; and now, from this gate, every staleness criterion
in §1's table.

## Decisions taken at G0 (2026-08-19)

Recorded here in the spec so a builder reads them with the criteria; `SL2` requires the same answers
in `decisions.md`, which is where they bind.

- **OQ1 — can a lock be declared stale?** **No, and no steal, ever.** Staleness is not provable with
  the signals available; age cannot work in principle because legitimate hold time is unbounded by
  design; `kill -0` fails unsafely across pid namespaces this project has actually used; and any
  identity written into the lock breaks all three `rmdir` releases (§0). The unit buys hygiene,
  discoverability, and boundedness instead. Forecloses: pid-in-lock, age expiry, heartbeat/two-phase
  claim, and any future "it has been there a while" heuristic.
- **OQ2 — is `record-recovered-cost.sh` in scope?** **In.** Both writers share one lock path
  (`:205` / `:99`), so a leak from either defeats the other. The earlier rejection of extending the
  *trim obligation* there stands on its own terms and does not transfer: a leak needs an interruption,
  not contention.
- **OQ3 — one shared primitive, or two parallel edits?** **Two parallel edits, one checked
  derivation** — re-examined at this gate now that the location is shared, and now held firmly rather
  than weakly, on evidence this document did not have before: the hook writer sources nothing at all,
  while the recovered CLI already refuses without `cost-ledger-lib.sh`. Sourcing a library from the
  hook path would put the lock's very existence behind a file-read that must not be able to fail,
  and the only available degradations are "no trim" (the leak) or "trim without a lock" (the loss).
  The requirement that mattered was **one place, checked** — not one program. `SL12`'s divergence case
  delivers that structurally: a future edit to one writer alone turns the suite red. Forecloses:
  moving either `append_and_evict()` into `cost-ledger-lib.sh`, and any arrangement where the two
  writers' agreement is promised by a comment rather than asserted by a case.
- **OQ4 — where does a human repair route live?** **Documentation plus whatever `SL3`'s report says.**
  No new command; `/cost` stays read-only by charter.
- **OQ5 — a ledger record for an orphaned lock?** **No new record type.** Surface it where a human
  already looks, and bound repeat reporting so one orphaned lock does not flag on every invocation for
  its lifetime.
- **OQ6 — relocate the lock?** **In this unit** — overruling this document's own recommendation to
  defer it. It is the only option that attacks the permanence directly, with no staleness criterion
  and no new threshold. The deferral's reasoning — that relocating shared state deserves its own gate
  — is not discarded: it is why §4, `SL11`, `SL12`, and `SL13` exist.
- **OQ7 — ship the catchable-signal hygiene?** **Yes, and never describe the leak as fixed.** `SL1`
  and `SL3` land with it. Relocation does **not** make it redundant (§4(f)); the two address different
  halves, duration and frequency.

## Open questions

**None blocking G1.** Two residuals are recorded so they are answered by evidence during the build
rather than assumed, and both are already attached to a criterion rather than left loose:

- **Is the chosen base actually cleared by a reboot, on both guarding platforms?** *Unestablished
  here, in either direction, and a citation is not an answer.* `SL11` requires the observation. If the
  honest answer turns out to be "no, it is cleared by age instead", that is not a blocker — it is
  `SL11`(c)'s recorded caveat, and the Problem section's bounded-by-uptime wording changes to match
  rather than being quietly kept.
- **How is repeat reporting bounded without minting a marker that can itself be orphaned?**
  *Unresolved in shape, decided in principle:* `OQ5` rules out a new record type, and a one-shot
  marker would be another `mkdir` directory with the same failure mode this unit exists to reduce.
  Attached to `SL3`; whichever shape is chosen, the flooding risk is recorded either way.

## Handoff — an observation this unit deliberately does not act on

Stated here in an actionable form because it reads like its own intent, and **this unit does not open
it.** Do not fold it into a slice; do not fix it in passing.

**The lock buys mutual exclusion between trimmers, not loss-freedom.** Because `L7` appenders do not
hold the lock while appending, a line appended between a trimmer's `tail -n MAX_LINES`
(`record-cost-event.sh:286`) and its `mv -f` (`:290`) is overwritten and lost — today, with the lock
working exactly as designed. **Read from the source and not reproduced**; whether it is reachable at
real arrival rates is unestablished, and no rate is claimed. What would establish it: a construction
holding a trimmer between its `tail` and its `mv` while an append lands, then checking whether that
record survives. Whoever picks it up should note that it bears on `H3`'s "newest N in order" and that
a lost finish record has no automatic recovery — and that it is a different fault from this one, with
a different mechanism and a different fix.

## G0 — held, and what it decided

Held 2026-08-19. The human approved the framing and the non-goals, ratified `OQ1`–`OQ5` and `OQ7` as
recommended, and **overruled the recommendation to defer `OQ6`**, pulling the lock's relocation into
this unit. The seven answers are above; `SL11`–`SL13` are what relocation added, and `SL1` is what
keeps the unit's claim about itself honest.

Approval at G0 was approval of the **problem** and its boundaries. It is not approval of a mechanism
and not permission to build: the next step is `/slice`, where `SL12`'s single derivation and `SL13`'s
degradation path are the two cuts most likely to be got wrong if they are bundled.
