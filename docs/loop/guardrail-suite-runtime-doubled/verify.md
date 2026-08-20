# Verify — guardrail-suite-runtime-doubled (S1–S2, the whole cut)

**Verdict: CONCERNS** — seven of the eight criteria are met, `RT3` in the strongest form available,
and the measured saving **exceeds** what G0 accepted the scope on. The concern is one criterion that
is genuinely unmet rather than out of scope: **`RT7` requires both guarding platforms' figures from a
real pushed run, and nothing has been pushed.** Everything below is one host.

**The claim this unit is allowed to make, stated so the verdict is not over-read:** the fork per entry
is gone and the suite runs measurably faster proving byte-identically the same things. **The runtime
problem is reduced, not settled** — option (b)'s ~92s was knowingly left on the table at G0.

**Scope, declared rather than implied:**

- **Changed surface:** `tests/guardrails.test.sh` (three lines), plus this unit's own markdown, one
  appended entry in `docs/loop/decisions.md`, and one new captured intent at
  `docs/loop/suite-path-farms-rebuilt-twelve-times/`. **Zero scripts changed** —
  `git diff --name-only -- scripts/` is empty.
- **Suite green** at `total: 513 passed, 0 failed`; `shellcheck -S warning scripts/*.sh` clean.
- ⚠ **Not pushed.** No CI run exists for this work, so `RT7` is open. See Finding 1.
- ⚠ **Same-session limit.** This pass was run by the session that built both slices. `RT3`'s check is
  mechanical and reproducible by anyone from the artefacts, which is what carries the weight here
  rather than the pass's independence.

---

## Criteria, one row each

| Criterion | Verdict | Proven by, and does it run |
|---|---|---|
| **RT1** — no case removed, weakened, skipped, renumbered, or made conditional | **MET** | `git diff tests/guardrails.test.sh` is exactly three hunks, each one line, each inside a helper's per-entry loop — no `expect` line added, deleted, reworded, or wrapped in a condition. Case total **513 before and after**, on all six measured runs |
| **RT2** — every `PATH` fixture still presents the genuine absence its case depends on | **MET, by the fixtures' own self-checks** | The three self-check cases pass **unmodified** and green: `(S1-1)` (`new_grep_absent_path` resolves bash/awk/mktemp/mv/tr/a-parser and **not** grep), `(S2-1)` (`new_stub_parser_path` resolves the **stub** jq, python3 stays absent, grep still resolves), `(S2-1)` (`new_jq_absent_path` resolves python3 and not jq). These are the cases that would fail if a helper's resolvability changed, and none of the three is touched by the diff. No allow-list introduced; the bin-directory list and every skip condition are byte-identical |
| **RT3** — no case's outcome changes | **MET, strongest form** | The full ordered list of case titles **and** results was captured from all six runs — three pre, three post — and every one hashes to `6e90cf1f95d7`, 513 lines. `diff` between each pair is empty. Not the same count and colour: the same titles, same results, same order, byte for byte, across both arms and all three trials |
| **RT4** — the before figure is a measurement, not a bound | **MET** | `spec.md` §1.1 replaced the intent's 2-minute-timeout bound with a paired measurement (88.53s @ 466 vs 218.79s @ 513, same host, back to back). `measure-rt5-suite-runtime.md` §2 states its host, its `n`, and that the arms were interleaved |
| **RT5** — measured where it is paid, interleaved, stated as numbers | **MET** | Six runs alternating pre/post/pre/post/pre/post — not two blocks. n=3 per arm. **pre: mean 257.66s, median 247.51s** (min 240.45, max 285.03); **post: mean 160.73s, median 158.35s** (min 150.96, max 172.87). Per-pair deltas 112.16s / 89.15s / 89.49s, every pair the same sign, none straddling zero. The words "significant" and "negligible" appear nowhere |
| **RT6** — one green run is one sample; CI figures labelled as upper bounds | **MET** | `measure-rt5-suite-runtime.md` §2 states the host was **not idle** (load 28–42) and that neither arm is comparable to `spec.md` §1.1's quieter-host baseline; §5 states 160.73s is a mean of three loaded-host runs and **not a new baseline**. `spec.md` §1.2's job durations are labelled upper bounds on the suite's own share, and are never compared against a §1.1-style figure |
| **RT7** — the saving is real on **both** guarding platforms, from a real pushed commit | **NOT MET — outstanding** | Nothing has been pushed, so no job durations exist for this change. This is the one criterion a local run cannot substitute for, and the criterion itself says so: per-fork cost differs between bash 3.2 on macOS and bash 5.x on Linux, which is precisely the cost this unit removed. **Finding 1** |
| **RT8** — nothing new ships set | **MET** | `git diff --name-only -- scripts/` is **empty** — no script changed at all, so no threshold, timeout, budget, or suggested runtime could have shipped. A grep of the diff's added lines for new environment names and numeric literals returns nothing. Per `OQ-RT2`, the figures are **recorded** in markdown and asserted nowhere; no check was added, removed, or renamed, so `docs/loop/checks.md` correctly gains no row |

## Findings

**1. `RT7` is unmet, and it is the only thing standing between this unit and a PASS. (CONCERNS)**

Every figure in this unit is from one host — `Darwin 25.6.0` arm64, bash 3.2.57 — and `RT7` exists
because that is not enough. The mechanism removed is a **fork per entry**, ~2043 of them per farm
build, and fork cost is exactly the kind of thing that differs between bash 3.2 on macOS and bash 5.x
on Linux. A local delta cannot stand in for either job's.

**What closes it:** push, then read both jobs' durations on the pushed commit and set them beside
`spec.md` §1.2's table — which already holds five runs of before-figures on both platforms, so the
comparison is ready to make the moment a run exists. Nothing needs to be re-measured locally.

**Not a defect, and not a reason to hold the code:** the change is three lines, `RT3` proves it
changes no case's outcome, and the suite is green. `RT7` is an evidence gap that a push closes, not a
fault in the diff.

**2. The projection under-predicted, and the reason is unverified. (Noted, not blocking)**

G0 accepted the scope on a projected ~65s (§1.3's 5.4s × 12 builds). The suite-level arms show
89–112s. The measurement file states this plainly and labels the candidate explanation — idle-host
benchmark versus loaded-host arms, with per-fork cost rising under load — as **consistent with the
evidence and unverified**. It was not chased, because verifying it means re-running the whole
interleaved set on an idle host, which the slice does not owe. Recorded so that nobody later reads
96.94s as a precise figure: it is the mean of three pairs on one loaded host.

## `Do NOT` check — clean

No shared base farm built once and reused — that is option (b), and `git diff` shows the twelve build
sites untouched. No curated allow-list, no narrowed bin-directory list, no entry skipped that is
symlinked today. No case touched. No threshold. `.github/workflows/ci.yml` untouched — not in the
diff at all. No parallelism. `docs/loop/checks.md` untouched. No `scripts/` file changed. The two
`basename` calls remaining in the suite file (`:3554`'s two-argument suffix form, `:5876`'s
small-N loop in the claim-word guard) were **deliberately left**, are outside the three helpers, and
are recorded as such in the measurement file — a repo-wide fork audit is out of scope and noted in
`spec.md`'s non-goals as its own worthwhile intent.

`S2` added no acceptance criteria, non-goals, or slices to the new captured intent, and proposes no
mechanism in it — the build-once candidate is named there only as the thing `OQ-RT3` has to be
answered about.

## Reproduction

Anyone can re-derive the whole of `RT3` and `RT5` from the artefacts:

```
# RT3, the one that matters, and it needs no timing:
#   for each arm: bash tests/guardrails.test.sh | grep -E '^  (ok|FAIL) ' > cases.<arm>.txt
#   diff cases.pre.txt cases.post.txt          -> empty
#   shasum cases.*.txt                         -> 6e90cf1f95d7 for all six captures
#
# RT5, interleaved, n=3 per arm, one host, load 28-42:
#   pre :  285028, 247506, 240448 ms   mean 257.66s  median 247.51s
#   post:  172866, 158353, 150958 ms   mean 160.73s  median 158.35s
#   per-pair deltas: 112.16s, 89.15s, 89.49s   (same sign in every pair)
#   all six runs: total: 513 passed, 0 failed
```

## What this pass cannot tell you

- **Either guarding platform's figure.** `RT7`, open. One host only.
- **The suite's runtime.** 160.73s is a loaded-host mean of three runs, not a baseline. The suite is
  still well above the 88.53s it measured at `18289f2`.
- **Whether option (b)'s ~92s is still ~92s.** It is not: that number was computed against the
  pre-fix per-build rate, which no longer applies. The captured intent says so and re-states the
  figure as roughly 43s at the post-fix rate, **unmeasured**.
- **Why the projection under-predicted.** Finding 2. Unverified by design.
- **Independence.** Same-session pass, as declared in Scope.
