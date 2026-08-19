# Intent — budget-gate-payload-path-dead-without-jq

Captured: 2026-08-19T21:11:25Z

## What was observed

`scripts/check-budget-gate.sh`'s `extract()` returns empty for every field on its `python3`
arm, so on any host that has `python3` but not `jq`, `HOOK_EVENT` and `TOOL_NAME` are always
empty and the `PreToolUse` payload path does not run.

The call sites pass their Python expression inside **single** quotes with escaped inner quotes:

```
scripts/check-budget-gate.sh:244  HOOK_EVENT="$(extract '.hook_event_name' 'd.get(\"hook_event_name\",\"\")')"
scripts/check-budget-gate.sh:245  TOOL_NAME="$(extract '.tool_name'        'd.get(\"tool_name\",\"\")')"
scripts/check-budget-gate.sh:263  PROMPT="$(extract '.tool_input.prompt'   'd.get(\"tool_input\",{}).get(\"prompt\",\"\")')"
scripts/check-budget-gate.sh:264  DESCRIPTION="$(extract … 'd.get(\"tool_input\",{}).get(\"description\",\"\")')"
```

Inside single quotes a backslash is literal, so `$py_expr` carries the backslashes into the
`python3 -c` program text, which then reads `v=d.get(\"hook_event_name\",\"\")`. Observed
output when the redirection is removed:

```
  File "<string>", line 4
    v=d.get(\"hook_event_name\",\"\")
             ^
SyntaxError: unexpected character after line continuation character
```

Two properties make it silent rather than noisy: the `SyntaxError` is raised while compiling
the program, so the `try:` / `except Exception:` **inside** that program never runs; and
`extract()` ends the arm with `2>/dev/null || true`, which discards the message and the
non-zero status.

`scripts/record-cost-event.sh:702` passes the same idiom **without** the backslashes
(`'d.get("tool_response",{}).get("status","")'`) and works.

## Where it surfaced

`scripts/check-budget-gate.sh` — the `extract()` function and its four call sites above. On
the maintainer's host (`Darwin 25.6.0` arm64, bash 3.2.57), by direct execution of the same
program text the script builds, not by a failing run of the gate itself.

Not observed in CI. No shipped environment is known to lack `jq`; whether one exists is
`unknown`.

## When

2026-08-19, while validating slice `S3` of
`docs/loop/resumed-invocation-never-reaches-the-ledger/` against the `python3` arm, per that
slice's own instruction to confirm a frozen block reproduces there.

## What was already tried

- **Reproduced directly**: set a shell variable to the literal string the call sites pass, and
  interpolated it into the same `python3 -c` program text `extract()` builds. Raises the
  `SyntaxError` above and exits 1 with empty stdout.
- **Compared against the working form**: the same expression without backslashes prints the
  field correctly, which is what `record-cost-event.sh:702` does.
- **Located why it is silent**: the compile-time error precedes the in-program `try`, and the
  arm's own `2>/dev/null || true` discards both the message and the status.
- **Not tried:** whether any environment this plugin ships into actually lacks `jq`; whether
  the gate has ever silently no-opped in practice; whether `PROMPT` and `DESCRIPTION` at
  `:263`/`:264` have any additional consequence beyond the two fields above; and whether
  `scripts/` holds the same escaping anywhere else.

No fix is proposed here and no cause is assigned to a commit.

## Suspected unit or commit

`unknown` as a cause — pre-existing, and no commit was identified as introducing it as a
regression.

Found during work on `docs/loop/resumed-invocation-never-reaches-the-ledger/` (slice `S3`,
commit `df25b34`), which did not touch `scripts/` and did not cause this.

## Next step

Normal entry at G0 — run `/loop` on this intent. This file carries **no acceptance
criteria, no non-goals, and no slices**; nothing builds from it directly.
