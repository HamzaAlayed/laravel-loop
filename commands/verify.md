---
description: Check built work against the spec's acceptance criteria and the slice's out-of-bounds list, reproduce the evidence, and issue a PASS / CONCERNS / FAIL verdict. Gate G2 on its own.
argument-hint: [slug or base branch]
allowed-tools: Agent, Read, Bash, Grep, Glob, Skill, AskUserQuestion
---

# Verify — `{{args}}`

> **Delegation:** spawn `loop-verify` by its registered agent type as it appears in your available-agents list — prefixed when installed as a plugin (`laravel-loop:loop-verify`), unprefixed when installed manually.

G2 without the rest of the loop. Use it before opening or merging a PR, or any time someone claims a slice is done — including when that someone is you.

## What you do

1. **Locate the contract.** `{{args}}` resolves to a slug under `docs/loop/`, a base branch, or both. Read `spec.md` for the acceptance criteria and `slices.md` for every `Do NOT`. No spec on disk → say so plainly and verify against the diff alone, flagging that the acceptance-criteria check was **not** performed. An unverifiable claim of done is worth reporting as exactly that.

2. **Get the diff.**

```
BASE="${ARGS:-main}"
git fetch origin "$BASE" --quiet
git diff "$BASE"...HEAD --stat
git log --oneline "$BASE"..HEAD
```

3. **Brief `loop-verify`** with the diff, the spec path, and the slice list. Require it to reproduce the evidence itself rather than trusting any build report, and to diff for **deleted or weakened test lines** specifically.

4. **Relay the verdict verbatim.** Do not soften a FAIL, do not summarize away a Blocking finding, and do not add reassurance the verifier did not write.

5. **⏸ Gate G2.** The human reads the diff. Then:

```
1. Approve — merge
2. Route findings back to loop-build  (recommended on FAIL)
3. Accept concerns and file them as slices
```

6. **On FAIL**, convert each Blocking finding into its own re-brief for `loop-build` — one finding, one envelope, one `Do NOT` — then re-verify. Findings are not a to-do list to hand over wholesale; that is how a fix for one thing quietly changes three.
