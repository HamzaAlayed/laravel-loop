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
