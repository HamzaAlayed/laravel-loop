# Verify — ship-observe-automation

**Verdict: CONCERNS** — accepted as-is at G2 (human decision, 2026-08-13). No blocking findings; concerns are test-coverage gaps on documentation/prose claims whose actual content was independently confirmed correct.

## Proven (independently reproduced by loop-verify, not taken on builder report)

- D2's core guarantee: a `not-run` gate never reads as `go`. Confirmed both by harness case and a live run at the real repo root (`gate 1: passed`, `gate 2: passed`, `gate 3: passed`, `verdict: go`).
- No mutation: `git show-ref` / `git tag` / `git status --porcelain` byte-identical before and after a real run.
- No push, tag, publish, or version-bump anywhere in the diff or scripts (grepped).
- `commands/ship.md` declares no write-capable tool (`Bash, Read, Glob, Grep, AskUserQuestion` only).
- No fifth agent — `agents/` unchanged, zero diff.
- README's untouched "Not included in v0.1" bullets (Gemini/Codex, specialist-agent) are byte-identical; only the two Ship/Observe bullets were retired.
- Harness reproduces clean: 57/57 passed, `shellcheck -S warning scripts/*.sh` exit 0, zero lines removed from the original 22 cases.

## Concerns (accepted, not fixed) — filed as follow-up

1. Ship's "own release readiness / not a downstream check" disclaimer is asserted against `commands/ship.md`'s prose but never against `scripts/ship-check.sh`'s own stdout (only "deploys/publishes nothing" is checked there). Fix: add a case in the same style as `SHIP6`.
2. `commands/observe.md`'s O4 (attribution as a followable link), O5 (no credentials/telemetry), O6 (project-agnostic) have no harness assertions, unlike O1–O3. Fix: grep-based cases in the same style as the existing six observe cases.
3. `skills/loop-protocol/SKILL.md`'s claim that the `↺` resolves to Observe's capture step is correct by inspection but untested — only README is checked by the harness.

None of the three affect go/hold correctness; they're coverage gaps on already-correct content.

## Out-of-bounds check

Confirmed clean via `git diff a48ed14..HEAD --name-status`: no scripts beyond `ship-check.sh`, no hook/CI changes, `CHANGELOG.md`/`VERSION`/`.claude-plugin/plugin.json` untouched by this unit.

---

## The three concerns are closed — verified 2026-08-18

All three were filed above as accepted-not-fixed coverage gaps. Each now has the case it wanted, and
the citations are line numbers in `tests/guardrails.test.sh` as it stands at this commit:

1. **Ship's disclaimer against `ship-check.sh`'s own stdout** — closed. `:2901` matches the script's
   summary for *"own release readiness" … "not a check of a" … "downstream Laravel application"*, and
   `:2910` asserts it, so the claim is checked where the concern said it was not: against the
   script's output, not only `commands/ship.md`'s prose.
2. **`observe.md`'s O4, O5 and O6** — closed, one case each: `:2648` (O4, attribution recorded as a
   followable reference, never a guess), `:2654` (O5, no credentials, no telemetry client, no network
   call), `:2661` (O6, project-agnostic, assumes nothing about language or toolchain). Previously
   only O1–O3 had assertions.
3. **`loop-protocol`'s `↺` claim** — closed. `:2670` asserts directly that the outer-loop diagram's
   `↺` resolves to `/observe`'s capture step, reading `skills/loop-protocol/SKILL.md` itself rather
   than README's equivalent sentence.

The verdict above (`CONCERNS`, go) is unchanged as history. What changed is that its three follow-ups
are no longer outstanding, and this file now says so rather than leaving a reader to discover it by
grepping the harness.
