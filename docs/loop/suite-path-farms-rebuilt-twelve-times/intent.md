# Intent — suite-path-farms-rebuilt-twelve-times

Captured: 2026-08-20T14:52:00Z

Captured by `guardrail-suite-runtime-doubled`'s `S2` as the work its G0 deliberately deferred. This
file carries **no acceptance criteria, no non-goals, and no slices**; nothing builds from it directly.

## What was observed

`tests/guardrails.test.sh` builds an isolated `PATH` fixture **twelve times** per run, across only
**three distinct shapes**:

| Helper | Call sites | Base shape |
|---|---|---|
| `new_stub_parser_path` | **10** | every resolvable entry except `jq` **and** `python3`, then one stub planted at the requested name |
| `new_grep_absent_path` | 1 | every resolvable entry except `grep` |
| `new_jq_absent_path` | 1 | every resolvable entry except `jq` |

**The ten `new_stub_parser_path` calls perform a byte-identical symlink pass.** They differ only in
which single stub file is written after the loop — the helper takes the stub's body as a parameter.
Nine of the twelve builds are therefore repetitions of work already done in the same run.

Each build symlinks every resolvable entry of `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`,
`/opt/homebrew/bin` and `/usr/local/bin`: **2043 candidate entries → 2002 links** on the maintainer's
host.

## Where it surfaced

The maintainer's host — `Darwin 25.6.0` arm64, bash 3.2.57. Also paid by CI on every push, on both
`ubuntu-latest` and `macos-latest`, where the per-build cost is **unknown** — no per-helper timing has
ever been taken on either platform.

## When

2026-08-20, while specifying `guardrail-suite-runtime-doubled`. The twelve-builds/three-shapes count
was read from the call sites; it was not inferred from a timing.

## What was already tried

- **Measured, n=3 per arm, one host:** one build costs **10.17s** mean with a `basename` fork per
  entry, **4.75s** mean with `${f##*/}`, both producing 2002 links.
- **The fork was removed** — that is `guardrail-suite-runtime-doubled`'s option (a), landed
  2026-08-20, measured at mean 257.66s → 160.73s at suite level on a loaded host.
- **Not tried:** building any shape once and reusing it. That is this intent. At the post-fix rate of
  ~4.75s per build, collapsing twelve builds to three is roughly **43s**; against the pre-fix rate it
  was the ~92s recorded at that unit's G0. **Neither figure has been measured after the fact**, and
  the second is now stale — it was computed against a rate that no longer applies.
- **Not tried:** any per-helper or per-case timing on Linux or in CI.

## The open question a human owns before any build

**Does "genuine absence" have to be literal for the ten stub-parser fixtures?** Today the real `jq`
and `python3` are *never symlinked* into a stub fixture, and `new_stub_parser_path`'s own comment
states that stricter property explicitly, so that "the other parser is genuinely ABSENT from this
PATH — never symlinked, never stubbed".

A shared base excluding both, with a small per-case directory ahead of it on `PATH` holding only the
stub, would give identical resolution order. **Whether that satisfies the stated property or
reinterprets it is not a builder's call**, and this intent proposes no mechanism — naming that
candidate is only naming the thing the question has to be answered about.

The constraint that governs any answer is not negotiable and predates this intent: the farms symlink
*everything* because a curated allow-list makes a fixture pass for the wrong reason. A sparser `PATH`
missing `grep`/`sed` made the library report a parse error, recorded at
`tests/guardrails.test.sh:2770-2775` on 2026-08-18. Any design here that narrows what a fixture
resolves re-opens that route.

## The risk this carries that option (a) did not

A base farm built once and reused is **shared fixture state**. A case that writes into it — a stub, a
`chmod`, a removal — contaminates every later case using it. `guardrail-suite-runtime-doubled`'s
`RT3` (the ordered case-title-and-result list, byte-identical) is the check that would catch it, and
it is cheap: it caught nothing on option (a) because option (a) had no shared state to get wrong.

## Suspected unit or commit

Not a defect and no commit is suspected. The twelve builds are the accumulated result of three units
each correctly following the pinned `PATH`-fixture contract; no single one of them is wrong.

## Next step

Normal entry at G0 — run `/loop` on this intent. The open question above is the first thing a spec
pass has to put in front of a human.
