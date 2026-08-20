# Verify — guardrail-suite-runtime-doubled (S1–S2, the whole cut)

**Verdict: PASS** — all eight criteria met, `RT3` in the strongest form available, and the measured
saving **exceeds** what G0 accepted the scope on.

**Amended 2026-08-20:** this pass first issued **CONCERNS** with `RT7` unmet, because nothing had been
pushed. `6282775` has since been pushed and run: both guarding platforms got faster and both stayed
green at 513. `RT7` is now met and the verdict is raised. The amendment is recorded rather than
overwritten, so the sequence stays legible.

**The claim this unit is allowed to make, stated so the verdict is not over-read:** the fork per entry
is gone and the suite runs measurably faster proving byte-identically the same things. **The runtime
problem is reduced, not settled** — option (b)'s ~92s was knowingly left on the table at G0.

**Scope, declared rather than implied:**

- **Changed surface:** `tests/guardrails.test.sh` (three lines), plus this unit's own markdown, one
  appended entry in `docs/loop/decisions.md`, and one new captured intent at
  `docs/loop/suite-path-farms-rebuilt-twelve-times/`. **Zero scripts changed** —
  `git diff --name-only -- scripts/` is empty.
- **Suite green** at `total: 513 passed, 0 failed`; `shellcheck -S warning scripts/*.sh` clean.
- **Pushed and run:** `6282775`, run `32382823972`, jobs `96469963076` (`guardrails`, 212s → **125s**)
  and `96469962803` (`guardrails-macos`, 223s → **195s**), both `total: 513 passed, 0 failed`.
  One sample per platform, and job durations are upper bounds on the suite's own share.
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
| **RT7** — the saving is real on **both** guarding platforms, from a real pushed commit | **MET (amended)** | `6282775` vs `1bd510b`, identical 513 cases, so the rows differ only by this unit's three lines: `guardrails` **212s → 125s (−87s)**, `guardrails-macos` **223s → 195s (−28s)**, both `total: 513 passed, 0 failed`. Real and green on both platforms. The saving is **markedly larger on Linux** — the asymmetry this criterion existed to detect, recorded as observed with no mechanism claimed, and the opposite of the naive guess. The two deltas are **not** comparable to each other: one sample each, and job duration carries fixed overhead plus a Homebrew install on macOS. §6 of the measurement file |
| **RT8** — nothing new ships set | **MET** | `git diff --name-only -- scripts/` is **empty** — no script changed at all, so no threshold, timeout, budget, or suggested runtime could have shipped. A grep of the diff's added lines for new environment names and numeric literals returns nothing. Per `OQ-RT2`, the figures are **recorded** in markdown and asserted nowhere; no check was added, removed, or renamed, so `docs/loop/checks.md` correctly gains no row |

## Findings

**1. `RT7` was unmet at first issue, and is now closed. (Resolved 2026-08-20)**

This pass originally issued CONCERNS: every figure was from one host, and `RT7` exists because that is
not enough — the mechanism removed is a fork, ~2043 per farm build, and fork cost differs between
bash 3.2 on macOS and bash 5.x on Linux.

`6282775` was pushed and run. Both platforms got faster, both green at 513, and the Linux saving is
roughly three times the macOS one — which is precisely the platform-dependence a local delta could not
have shown, and the reason the criterion refused a local substitute. Figures in §6 of the measurement
file and in the `RT7` row above.

**It was never a fault in the diff:** three lines, `RT3` proving no case's outcome changed, suite
green. It was an evidence gap, and a push closed it.

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

- **Any ratio between the two platforms' savings.** `RT7` is met, but with one sample per platform and
  job durations that include fixed overhead plus a Homebrew install on macOS. −87s and −28s are two
  observations, not a measured platform ratio.
- **The suite's runtime.** 160.73s is a loaded-host mean of three runs, not a baseline. The suite is
  still well above the 88.53s it measured at `18289f2`.
- **Whether option (b)'s ~92s is still ~92s.** It is not: that number was computed against the
  pre-fix per-build rate, which no longer applies. The captured intent says so and re-states the
  figure as roughly 43s at the post-fix rate, **unmeasured**.
- **Why the projection under-predicted.** Finding 2. Unverified by design.
- **Independence.** Same-session pass, as declared in Scope.
