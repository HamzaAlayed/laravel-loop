# Spike — SL11: what clears the candidate lock base, on both guarding platforms

Slice `S4`. Read-only. This file is the whole diff: no code, no case, no script, no workflow.

Observed 2026-08-19. The guarding platforms are `ubuntu-latest` and `macos-latest`, read from
`.github/workflows/ci.yml:9` and `:25`.

## What this spike was asked to settle

`spec.md` §4(a) requires the relocated lock to live somewhere with a **per-boot** property, so that
an orphaned lock is bounded by uptime instead of being permanent. §4(b) records that the candidate
`${TMPDIR:-/tmp}` has **no established clearing property in this repository on either platform**, and
that citing documentation is not establishing one. `SL11` requires the property be *observed*.

**The proof here is a set of observations, not a harness case, and this file says so rather than
disguising it.** No case in this suite can observe a reboot, and a case asserting a property of the
host's temp directory would be asserting something about the machine rather than about this
repository.

## Verdict

**The per-boot property FAILS on the maintainer's host, for both candidate bases, and is UNKNOWN on
both guarding platforms.** Neither base is cleared at boot; both are cleared **by age, at 3 days**,
by an interval this project did not choose, cannot see from its own code, and cannot test.

Per `S4`'s own constraint, this returns **`needs-decision`**: `SL11` now forbids the
bounded-by-uptime claim anywhere, and whether relocation still earns its costs is the human's call
before `S5` is briefed. This is not softened to "cleared eventually", and no third base is proposed
— proposing one would itself be a `needs-decision`, not a fix.

## macOS — the maintainer's host

Every row below is **evidence about the maintainer's host only**. This host is `Darwin 25.6.0`
arm64. It is *not* evidence about `macos-latest`.

| What | Observed | Label |
|---|---|---|
| Base a run gets | `TMPDIR` **is set**, so `${TMPDIR:-/tmp}` resolves to `/var/folders/65/fwmwydjj2ml5rwf5x45x6mc80000gn/T/` | evidence about this host |
| That base's mode/owner | `drwx------` `developer:staff` — **private, not squattable** | evidence about this host |
| Fallback base | `/tmp` → symlink to `/private/tmp`, mode `drwxrwxrwt` `root:wheel` — **world-writable, sticky** | evidence about this host |
| Per-uid parents | `/var/folders/65/…0000gn` `drwxr-xr-x developer:staff`; `/var/folders/65` and `/var/folders` both `drwxr-xr-x root:wheel` | evidence about this host |
| Backing store | Both bases on `/dev/disk3s5`, the APFS Data volume — **disk-backed** | evidence about this host |
| Memory-backed filesystems | **Zero** `tmpfs`/`devtmpfs` mounts exist on this machine | evidence about this host |
| Boot-clearing by construction | **Does not apply.** A disk-backed base cannot be cleared merely by being memory-backed, which is the only clearing mechanism a builder can establish without a reboot | evidence about this host |

How both bases were determined: `$TMPDIR` read from the environment a run actually inherits, then
`ls -ld` on each base and on every parent up to `/var/folders`, `df` for the backing store, and
`mount` for the absence of any memory-backed filesystem.

### What clears them, read from this machine's own configuration

Both facts below come from configuration files and a binary **on this machine**. No man page, vendor
page, or runner-image manifest is cited as evidence anywhere in this file.

**`/private/tmp` — `/System/Library/LaunchDaemons/com.apple.tmp_cleaner.plist`**

```
ProgramArguments      => [ /usr/libexec/tmp_cleaner ]
StartCalendarInterval => { Hour => 0 }      # daily at midnight, NOT at boot
```

Read out of `/usr/libexec/tmp_cleaner` itself:

```
daily_clean_tmps_days="3"
args="-atime +$daily_clean_tmps_days -mtime +$daily_clean_tmps_days"
args="${args} -ctime +$daily_clean_tmps_days"
dargs="-empty -mtime +$daily_clean_tmps_days"
```

**`$TMPDIR` (`/var/folders/*/T`) — `/System/Library/LaunchDaemons/com.apple.bsd.dirhelper.plist`**

```
EnvironmentVariables  => { CLEAN_FILES_OLDER_THAN_DAYS => "3" }
StartCalendarInterval => { Hour => 3, Minute => 35 }
RunAtLoad             => true
```

`/etc/periodic/daily/` does not exist on this machine, so the older periodic path is not the
mechanism here.

### The interval, as a number, and what it means

**3 days**, on both bases, from the two configurations above.

`dirhelper` carries `RunAtLoad => true`, so it *does* run at boot — but it runs with the same
3-day age filter, so **it does not clear the base at boot regardless of age.** A lock created
minutes before a reboot survives that reboot. This is the specific reason the per-boot property
fails rather than merely being unproven: the mechanism that runs at boot is age-filtered.

An evict lock is an **empty directory** (`mkdir`, no contents), which is what `tmp_cleaner`'s
`dargs` targets: `-empty -mtime +3`.

**This is an OS-owned staleness threshold this project did not choose, cannot see from its own code,
and cannot test.** `SL7`'s last clause is satisfied only by recording it; nothing here adopts it,
and no threshold, interval, or margin of this project's own is proposed.

### `SL5` re-argued against the 3-day threshold

`SL5` guarantees no lock is ever taken from a live holder. The OS threshold does not honour that
guarantee, and the comparison that matters is not the quiet case:

- **Against the measured quiet trim (~16 ms, `spec.md` §1):** 3 days exceeds 16 ms by roughly seven
  orders of magnitude. In the quiet case a live holder is never reaped. This is the comparison that
  makes the concession *look* free.
- **Against unbounded legitimate hold — the comparison that actually matters:** `converge_ledger()`
  is `while :;` with I/O-only breaks, so legitimate hold time is **unbounded by design**. A holder
  legitimately holding beyond 3 days would have its lock deleted **while alive**, by the OS, on a
  schedule this project cannot observe. Worse, the filter is `-atime`/`-mtime`/`-ctime` on an empty
  directory that is *held* rather than written, so holding does not refresh those timestamps: a
  long-held lock's age keeps increasing while it is legitimately in use.
- **Consequence:** relocation does not merely fail to deliver uptime bounding — it introduces, by
  proxy, exactly the age-based staleness rule `spec.md` §1 rejected in principle, with the steal
  performed by the OS instead of by this project's code. Two simultaneous trimmers is the failure
  `spec.md` describes as lost records, and this is a route to it that no code in this repository
  can see.

Unobserved, and stated as such: no run in this repository has been seen holding the lock for 3 days.
The mechanism is read from configuration; the *occurrence* is not evidence, it is inference from the
unbounded-hold design.

## Linux — `ubuntu-latest`

| What | Observed | Label |
|---|---|---|
| Base a run gets | **unknown** — depends on whether `TMPDIR` is set in the runner's environment | not obtainable by a builder |
| Mode/owner of either base | **unknown** | not obtainable by a builder |
| Backing store of `/tmp` | **unknown** — whether it is `tmpfs` decides the boot property outright | not obtainable by a builder |
| What clears it, and when | **unknown** | not obtainable by a builder |
| Per-boot property | **unknown** | not obtainable by a builder |

Why no row here is filled in, rather than filled in cheaply:

- **A CI runner cannot be rebooted.** A fresh VM per run is *not* the same observation as "the base
  was cleared" — it is a different machine, not a cleared one.
- **A container is investigation-grade only** and is never evidence about `ubuntu-latest`, so
  running one would produce a row this file would have to label as not-evidence anyway.
- Reading a runner-image manifest or distro documentation is explicitly not an observation.
- Gathering it inside CI would require editing `.github/workflows/ci.yml`, which this slice's
  `Do NOT` forbids and which the unit's own non-goals exclude.

**What would settle it:** on a real `ubuntu-latest` host — not a container — read `findmnt /tmp` for
the backing store, `/usr/lib/tmpfiles.d/tmp.conf` and `/etc/tmpfiles.d/` for the clearing rules and
their age fields, and `printenv TMPDIR` for which base a run gets. Three commands, on the right
machine.

## The half no builder can reach: yours

A real reboot of this host is the human's action. Two marker directories are left in place — empty,
so they mimic the real lock, which is also an empty `mkdir` marker:

```
/var/folders/65/fwmwydjj2ml5rwf5x45x6mc80000gn/T/loop-evict-sl11-reboot-marker
/private/tmp/loop-evict-sl11-reboot-marker
```

Created `2026-08-19T15:30:39Z`. Nothing else was left in either base.

After the next reboot, one command:

```bash
ls -ld /var/folders/65/fwmwydjj2ml5rwf5x45x6mc80000gn/T/loop-evict-sl11-reboot-marker \
       /private/tmp/loop-evict-sl11-reboot-marker
```

- **Both still listed** → confirms the per-boot property fails, matching what the configuration above
  already predicts.
- **Either absent** → contradicts the configuration reading and is worth investigating rather than
  believing immediately.

**The observation is only valid if the reboot happens before `2026-08-22T15:30:39Z`.** After that the
3-day age threshold can remove the markers on its own, and absence would no longer distinguish
"cleared at boot" from "cleared by age" — the exact confound this spike exists to separate. If the
reboot happens later, delete both markers and recreate them first.

## The four checks this record is held to

Stated as observations, because that is what they are:

1. **Every row is labelled** evidence-about-this-host / investigation-grade / not-obtainable-by-a-builder.
   No row is unlabelled. — `SL11`
2. **Both candidate bases are covered per platform, with mode and owner**, because §4(d)'s squatting
   exposure differs between them: `$TMPDIR` is `drwx------` and private on this host, while
   `/private/tmp` is `drwxrwxrwt` and world-writable. That difference is the reason the fallback
   exists. — `SL11`, `SL13`
3. **The age interval is a number read from this machine's configuration** — 3 days, from
   `com.apple.bsd.dirhelper.plist`'s `CLEAN_FILES_OLDER_THAN_DAYS` and `tmp_cleaner`'s
   `daily_clean_tmps_days` — and `SL5` is re-argued against it in the same section, including
   against the unbounded-hold case and not only the ~16 ms one. — `SL11(c)`, `SL5`
4. **The unobservable half is named as the human's**, with both marker paths, the exact command, and
   the validity deadline — not left as "would need a reboot". — `SL11`

## Counts, never rates

One host. One sample. Two bases. Nothing here is a rate, and no row is generalised from this host to
either guarding platform.
