# Spike — S4: is the approved two-directional contract buildable at all?

Read-only. This file is the entire deliverable; no workflow, matrix, or job was created, edited,
drafted, or branched to produce it. Everything below was gathered by reading `.github/workflows/ci.yml`
and `docs/loop/checks.md` as they stand, and by querying `github.com` (a public GitHub API, read-only,
authenticated as this session's own `gh` login) for the published software manifest of GitHub-hosted
runner images. No workflow was pushed, dispatched, or cancelled to produce any of it.

## The question

OQ2/OQ3's two-directional contract was approved at G0 **contingent** on this answer: can a hosted
runner available to this repository run the suite on a bash matching the maintainer's stock 3.2 —
`GNU bash, version 3.2.57(1)-release`, on macOS 26.6.1, arm64 (`intent.md`)?

## Headline answer

**A named hosted image/label exists, with a citable source for its bash version, that reports an
exact bash-version match and an exact architecture match to the maintainer's host. Its OS point-version
is close but not identical, and — this is the limit, not a footnote — none of this is proof that
`tests/guardrails.test.sh` would actually pass there. Only a real run does that.**

This answers the S4 question as: **a candidate is named and cited, not proven.** It is not "not
feasible" (a candidate exists) and it is not "not established" (a citable, reproducible source was
found and is quoted below) — but it must not be read as "covered." That is exactly the over-claim this
slice's `Do NOT` list and its own `Constraints` warn against.

## Method — how this was established, so a second person can redo it

This repository (`HamzaAlayed/laravel-loop`) is confirmed **public**:

```
$ gh api repos/HamzaAlayed/laravel-loop --jq '{private, visibility}'
{"private":false,"visibility":"public"}
```

Public repositories have standard access to GitHub's hosted runner catalogue, including its macOS
images, without further enablement. That catalogue's own published index
(`https://github.com/actions/runner-images`, its top-level `README.md`) is the source consulted below;
each image also publishes a per-image software manifest at
`images/macos/<image>-Readme.md`. Both were read live via the authenticated GitHub REST API
(`gh api repos/actions/runner-images/contents/...`), not from training-data recollection of what these
files say — the exact commands and the commit each answer was read at are given per row below, so a
second person opens the identical content rather than trusting this document's paraphrase.

Fetched 2026-08-17T15:28:48Z.

## What matches and what does not

| Candidate label (from the index's own table) | Arch | Manifest commit (permalink base: `github.com/actions/runner-images/blob/<sha>/...`) | Bash reported | OS / kernel reported | vs. maintainer (macOS 26.6.1, arm64, bash 3.2.57(1)-release) |
|---|---|---|---|---|---|
| `macos-latest`, `macos-26`, `macos-26-xlarge` (path: `images/macos/macos-26-arm64-Readme.md`) | **arm64** | `8d3ea005fa2d87f3cbc9255c27fdfed9e901a043` | `Bash 3.2.57(1)-release` | macOS 26.5.2 (25F84) / Darwin 25.5.0 | **Bash: exact match. Architecture: exact match. OS: same major/minor train (26.x), one build behind (25F84 vs. the host's later build) — not identical.** |
| `macos-26-intel`, `macos-latest-large` (path: `images/macos/macos-26-Readme.md`) | x64 | `4d36b3c7d1d34ebd612efea6831078db6adfa1f0` | `Bash 3.2.57(1)-release` | macOS 26.6 (25G72) / **Darwin 25.6.0** | Bash: exact match. **Architecture: does NOT match** (x64, host is arm64). OS build is closer (Darwin 25.6.0 matches the host's own kernel version exactly), which is irrelevant given the architecture mismatch. |
| `macos-15`, `macos-15-xlarge` (path: `images/macos/macos-15-arm64-Readme.md`) | arm64 | `1fe6f11765eedf01d0f944f935fda7fa94389510` | `Bash 3.2.57(1)-release` | macOS 15.7.7 (24G720) / Darwin 24.6.0 | Bash: exact match. Architecture: exact match. **OS: different major version** (15, not 26). |
| `macos-14` (deprecated) (path: `images/macos/macos-14-arm64-Readme.md`) | arm64 | `1ba8a97c29950272cd3be535f0f33e6a0ef8ba6c` | `Bash 3.2.57(1)-release` | macOS 14.8.7 (23J520) / Darwin 23.6.0 | Bash: exact match. Architecture: exact match. OS: different major version, and the label is flagged deprecated by the index itself. |

Two things worth stating plainly rather than leaving implicit:

- **Every currently-listed macOS image, at every OS major version checked, reports the identical
  `Bash 3.2.57(1)-release`.** This is consistent with Apple's system `/bin/bash` having been frozen at
  the last GPLv2 release since Mac OS X Leopard for licensing reasons, and is not a coincidence of one
  image. None of these manifests lists a second, newer "Bash (Homebrew)" entry the way they do for e.g.
  Clang/LLVM (`Clang/LLVM (Homebrew) 18.1.8`) — so nothing in the published manifest suggests a newer
  bash shadows the system one on `PATH` for these images, but this is read off the manifest's own
  listing convention, not observed on a live runner.
- **These are rolling images.** Each manifest carries its own `Image Version:` build stamp
  (e.g. `20260728.0273.1`) and updates on its own cadence — the OS point-version cited above is what
  that specific commit recorded, not a fixed contract. By the time any real workflow run executed
  against `macos-26` or `macos-latest`, the exact point release could already have moved. This is
  exactly why the OS-version column above is reported as "close, not identical" rather than rounded up
  to a match, and it is a second, independent reason the citation cannot stand in for a run.

## The limit, stated in the finding itself, not left to be inferred

**A citable image manifest is not proof that the suite passes there.** It documents what software the
image's build process installed; it says nothing about how `tests/guardrails.test.sh` actually behaves
under that bash, that coreutils, and that `PATH` ordering, on a real invocation. The manifest bash
version and architecture matching the maintainer's host is evidence that a *relevant* platform can be
named and cited — it is not evidence that the guardrails suite is portable to it. Per A1 and A5, **only
a real run of the suite on that named runner, reporting its own pass/fail totals, would be evidence for
that claim.** No such run has been requested, dispatched, or performed by this slice, and none is
proposed here.

## OQ3 — what would produce evidence for the second direction, per answer, choosing none

The choice among these is the human's, at the second G1. Nothing below is a recommendation.

1. **One platform, as today.** Under this answer the guarding checks stay Linux-only, so nothing
   automated ever reports a pass/fail for the older-shell direction. The only thing that could still
   produce evidence here is a **human-run procedure outside the guarding checks** — someone running
   `bash tests/guardrails.test.sh` on a bash-3.2 host and recording the result somewhere durable. That
   is not a new mechanism; it is the maintainer's existing local run, made into a recorded artifact
   instead of a private observation.
2. **More than one platform.** Evidence would be produced by an actual CI job added to the workflow,
   targeting one of the named-and-cited labels above (or another with an equivalent citation), whose
   own run reports `success`/`failure` for `tests/guardrails.test.sh` — a real execution, not the
   citation table above. That run's own conclusion, read the same way A1 already reads the Linux job's,
   is what would turn "matches on paper" into evidence.
3. **Something short of a second platform.** Evidence would be produced by a written, recorded human
   procedure — e.g., a checklist step executed and logged at release time — whose output is kept
   (not merely asserted from memory) and is checkable the way this repository already treats other
   claims that depend on a human step.

## What this slice did not do

Per its `Do NOT` list: no workflow file, matrix, or job was created, edited, drafted, commented-out, or
branched; no probe branch was pushed; no workflow was dispatched; no compatibility shim, vendored
coreutils, wrapper, or minimum-shell-version change was proposed; no caching, linter, coverage step,
scheduled run, artifact upload, or job restructure was proposed; `docs/loop/checks.md`,
`.github/workflows/ci.yml`, `scripts/`, `tests/`, `README.md`, and `spec.md` were read, not edited. No
OQ2 or OQ3 answer was chosen, and the approved decision was not downgraded to "enforced by convention"
— this finding does the opposite of that failure mode by insisting the citation and its limit travel
together.

## Handback

This returns OQ2/OQ3's contingency to the human at the second G1 with a citable, reproducible answer
rather than a guess: a candidate hosted platform is named and sourced, its match is reported exactly
(bash: match; architecture: match; OS point-version: close, not exact, and inherently a moving target),
and the fact that citation is not proof is stated as part of the finding itself, not left for someone
else to discover after the contract is already believed covered.
