# Slices — guardrail-suite-runtime-doubled

**G1 held 2026-08-20.** Two slices, both small, and the pass deliberately stops at two. Approved
scope is `spec.md`'s option **(a)**: the fork-per-entry removed. Option (b)'s build-once redesign is
**out of bounds for every slice here** and leaves as a captured intent, not as a comment.

Order: **S1 → S2.** `S2` records what `S1` measured, so it cannot be written first. They share no
file: `S1` touches `tests/guardrails.test.sh` and adds a measurement file; `S2` touches
`docs/loop/decisions.md` and creates one intent directory.

## Field evidence, so no slice re-derives it

1. Three helpers build a `PATH` farm: `new_grep_absent_path` (`tests/guardrails.test.sh:3107`),
   `new_stub_parser_path` (`:3133`), `new_jq_absent_path` (`:3082`).
2. Each contains `base="$(basename "$f")"` inside the per-entry loop. That is the whole defect.
3. 2043 candidate entries → 2002 links, per build, on the maintainer's host.
4. Call sites: `new_stub_parser_path` **10**, `new_grep_absent_path` **1**, `new_jq_absent_path` **1**.
   Twelve builds per suite run.
5. Measured, n=3 per arm: fork arm **10.17s** mean, builtin arm **4.75s** mean, both producing 2002
   links. `spec.md` §1.3.
6. `${f##*/}` is a bash 3.2 builtin and was exercised on bash 3.2.57 in §1.3's own measurement.
7. `basename` and `${f##*/}` differ only on a trailing slash, which a glob expansion of `"$bindir"/*`
   cannot produce.

---

### S1 — remove the fork per entry from all three `PATH`-farm helpers, and measure what it bought

```
Owner:       loop-build
Unit:  guardrail-suite-runtime-doubled
Slice: S1
Context:     - spec.md RT1-RT8; §1.3 (the two-arm measurement), §1.4 (twelve builds,
               three distinct shapes), §1.5 (why the farms symlink everything, and
               the 2026-08-18 false-green finding that is the reason).
             - Field evidence 1-7 above. Do not re-derive them.
             - docs/loop/stale-evict-lock-permanently-defeats-the-cap/
               measure-sl6-append-cost.md is the SHAPE the measurement file follows:
               interleaved arms, n stated, mean AND median, min/max, one host named.
Constraints: - THE CODE CHANGE IS EXACTLY THREE LINES. One per helper:
               `base="$(basename "$f")"` -> `base="${f##*/}"`. Nothing else in those
               helpers changes -- not the bin-directory list, not the skip conditions,
               not the `[ -e ]` guards, not the `ln -s`, not `mktemp -d`.
             - DO NOT build any farm once and reuse it. That is option (b), it is out
               of scope at G0, and S2 captures it as its own intent. A slice that
               introduces a shared base farm has exceeded its brief.
             - DO NOT introduce a curated allow-list, narrow the bin-directory list, or
               skip any entry that is symlinked today (§1.5). The 2026-08-18 finding is
               why, and it is the failure this whole area exists to avoid.
             - NO CASE IS TOUCHED (RT1). No expect line added, removed, reworded,
               renumbered, or made conditional. The case total stays exactly 513.
             - NO THRESHOLD, timeout, budget, or runtime figure ships in any script or
               case (RT8, OQ-RT2). The numbers go in the measurement file only.
             - RT3 IS THE LOAD-BEARING CHECK AND IT IS MECHANICAL: capture the full
               ordered list of case titles and results before and after, and diff them.
               Byte-identical, INCLUDING ORDER. A faster suite that changes what any
               case proves has failed, whatever colour it reports.
             - The measurement is INTERLEAVED, not two blocks (RT5). Alternate
               pre/post/pre/post on one idle host. State n, mean, median, min, max.
               Never the word "significant", never "negligible".
             - Measure the SUITE, not just the helper. §1.3 already has the per-build
               figure; what this slice owes is what the whole run costs before and
               after, because that is where the cost is actually paid.
Output:      - tests/guardrails.test.sh: three one-line edits.
             - docs/loop/guardrail-suite-runtime-doubled/measure-rt5-suite-runtime.md:
               the interleaved before/after, in measure-sl6's shape, plus the RT3
               case-list diff result quoted (expected: empty).
             - The standard return, carrying the before/after `total:` lines.
Done when:   The three helpers contain no `basename` call; the suite reports
             `total: 513 passed, 0 failed`; the RT3 ordered case-list diff is empty;
             shellcheck -S warning scripts/*.sh is clean; and the measurement file
             carries interleaved arms with n, mean and median stated.
Test set:    NO NEW CASES (+0), and that is stated rather than disguised: RT8 and
             OQ-RT2 forbid asserting a wall clock, so a case here could only assert a
             threshold this gate refused. The proof of this slice is a MEASUREMENT plus
             the RT3 diff, not a case.
             The existing cases that must pass UNMODIFIED, and which are the real guard
             on RT2 -- each is a fixture's own self-check, and each would fail if a
             helper's resolvability changed:
               1. (S1-1) new_grep_absent_path resolves bash/awk/mktemp/mv/tr/a-parser
                  and does NOT resolve grep
               2. (S2-1) new_stub_parser_path resolves the STUB jq (not the real one),
                  python3 stays absent, and bash/awk/mktemp/tr/grep still resolve
               3. (S2-1) new_jq_absent_path resolves python3 and not jq
             Fails now: nothing fails now -- the suite is green and this is a cost
             change, not a defect fix. That is why RT3, not a red-before-green, is what
             makes this slice believable, and why the measurement is the deliverable.
Do NOT:      - Do not touch .github/workflows/ci.yml, any job, matrix, or timeout.
             - Do not parallelise anything.
             - Do not touch docs/loop/checks.md -- no check is added, removed, or
               renamed, so it gains no row.
             - Do not change any script under scripts/.
             - Do not remove basename calls anywhere else in the repository. Out of
               scope; a repo-wide fork audit is its own intent.
             - Do not claim the runtime problem is settled. Option (b)'s ~92s is
               knowingly left on the table and the record says so.
Depends on:  nothing.
```

### S2 — record the decision, and capture the deferred 92s as an intent rather than a comment

```
Owner:       loop-build
Unit:  guardrail-suite-runtime-doubled
Slice: S2
Context:     - spec.md's G0 decisions, all four, and the OQ-RT1 option table with its
               measured costs.
             - S1's measured figures (read them from S1's measurement file; do not
               re-measure).
             - docs/loop/conventions.md and the shape of an existing intent.md --
               e.g. docs/loop/guardrail-suite-runtime-doubled/intent.md itself, or
               budget-gate-payload-path-dead-without-jq/intent.md.
Constraints: - ONE appended dated entry in docs/loop/decisions.md. Appended at
               end-of-file; nothing above it is edited, superseded, annotated, or
               marked revisited.
             - The entry states: option (a) taken and what it measured; option (b)
               DEFERRED with its ~92s named as a number; OQ-RT2's record-don't-assert
               and the cost that accepts (the next silent increase is again caught by a
               person, not a check); and that the runtime problem is reduced, NOT
               settled.
             - THE DEFERRED WORK BECOMES A REAL INTENT, not a sentence. Create
               docs/loop/suite-path-farms-rebuilt-twelve-times/intent.md carrying: what
               was observed (twelve builds, three distinct shapes, ten of them a
               byte-identical symlink pass), the measured cost, what was already tried,
               OQ-RT3 restated as the open question a human owns before any build, and
               explicitly NO acceptance criteria, NO non-goals, NO slices.
             - That intent may NOT propose a mechanism. Naming "build once and layer a
               per-case override dir" as the obvious candidate is fine ONLY as the thing
               OQ-RT3 has to be answered about first -- never as a design.
             - No case, no script, no README change.
Output:      - docs/loop/decisions.md: one appended dated entry.
             - docs/loop/suite-path-farms-rebuilt-twelve-times/intent.md: new.
             - The standard return.
Done when:   decisions.md carries the dated entry naming (a) taken, (b) deferred with
             its number, and "reduced, not settled"; the new intent exists with no
             criteria and no slices; the suite is still green at 513.
Test set:    NO CASES (+0), stated rather than disguised: this slice's whole diff is two
             markdown files and there is nothing in it a fixture can exercise. The
             existing guard that DOES cover it is the case-count case (README's
             Development count equals the harness total), which must stay green at 513.
Do NOT:      - Do not write acceptance criteria, non-goals, or slices into the new
               intent. It is a capture, and G0 has not been held on it.
             - Do not edit or annotate the S1 measurement file.
             - Do not phrase the entry as if the runtime problem is dealt with.
Depends on:  S1 (its measured figures are quoted in both outputs).
```

## Not cut, and why

**No slice collapses the twelve builds into three.** That is option (b). `spec.md`'s G0 took (a)
alone and recorded the ~92s it leaves on the table; `S2` turns that into a captured intent with
`OQ-RT3` attached, so the next unit starts from a human's answer rather than from a builder's
reinterpretation of a helper's stated contract.

**No slice adds a runtime guard.** `OQ-RT2` decided record-don't-assert. A slice adding a wall-clock
assertion would be introducing the threshold `RT8` forbids.
