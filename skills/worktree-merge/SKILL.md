---
name: worktree-merge
description: "Bringing worktree-isolated parallel slices back together — deriving merge order from the slice dependency graph, running the full suite after every merge rather than only the last, who owns which conflict, migration timestamp collisions across branches, and why a conflict between slices the graph called independent is a G1 defect to record rather than a chore to resolve. Use before merging the first parallel lane, when a builder's branch has fallen behind main, when two lanes conflict in a shared file, or when cleaning up after an abandoned lane."
---

# Worktree Merge

Integration is where parallelism fails, and it fails at the end — when every lane's budget is already spent. Merge deliberately.

## Check the base before building, not at merge time

The commonest integration cost is a lane that branched from a stale commit and only discovers it hours later. Check on **entry** to the lane:

```bash
git merge-base main HEAD     # where this worktree actually branched
git rev-parse main           # where main is now
```

Different → bring main in **before** writing code, not after:

```bash
git merge main               # resolve now, while the diff is empty
bash tests/guardrails.test.sh # confirm green on the merged base
```

A conflict resolved against an empty diff is a one-line decision. The same conflict resolved after 300 lines of new work is an archaeology exercise.

## Merge order comes from the dependency graph

Merge in the order `slices.md` declared, not in the order lanes finished. A lane that finished first but depends on a lane still running merges second.

```bash
git checkout main
git merge --no-ff worktree-agent-<id> -m "Merge S1: <slice title> (<unit>)"
bash tests/guardrails.test.sh          # after THIS merge, not just the last
shellcheck -S warning scripts/*.sh
git worktree remove .claude/worktrees/agent-<id> --force
git branch -d worktree-agent-<id>
```

`--no-ff` always: the merge commit is where a bisect lands when an interaction bug surfaces later, and a fast-forward erases the lane boundary that makes it findable.

## Full suite after each merge, not only the last

A two-slice interaction breaks at the merge that introduces it. Finding it after merge 4 means four candidate causes and no way to tell which; finding it at merge 2 means one.

Green after merge N is the only thing that makes merge N+1's failure attributable. Skipping the intermediate runs converts four cheap questions into one expensive one.

## Conflict ownership

| Conflict in | Who resolves | How |
|---|---|---|
| **App code** | The **owning builder**, never the orchestrator | Re-brief with both sides described and the merge state. The orchestrator has no context for either intent and will guess. |
| **Append-only shared files** (a test harness, a changelog) | Orchestrator | Resolution is always **keep both blocks**. There is no semantic conflict — two lanes appended at the same offset. |
| **A self-referential count** (e.g. a README case count the suite asserts) | Orchestrator | Never pick a side. Merge, re-run, write the **actual** number. Both sides are stale by construction. |
| **Lock files** (`composer.lock`, `package-lock.json`) | Orchestrator | Never hand-merge. Take either side, then regenerate: `composer update --lock` / `npm install`. A hand-merged lock file is a dependency set nobody has ever resolved. |
| **Generated files** (compiled assets, IDE helpers, cached manifests) | Orchestrator | Discard both sides, regenerate after the merge. |
| **Migrations** | See below — ordering, not text |

The rule behind the table: the orchestrator resolves conflicts where **correctness is mechanical**, and routes conflicts where correctness requires knowing what the code was for.

## A conflict between "independent" slices is a G1 defect

This is the one worth stopping for. If `slices.md` said two slices were independent and their diffs conflict in app code, the graph was wrong — the slices shared a seam nobody declared.

Resolve the merge, then **record it**, because the same cut will otherwise be made again next unit:

```markdown
## Slicing S3 and S5 as independent (cost-reporting-v0.3)
Tried: cutting the report's aggregation (S3) and the gate's threshold read (S5)
as parallel slices, on the stated basis that one writes and one reads.
Rejected: both had to edit the same lib function signature; they conflicted at
integration and S5 needed re-briefing against S3's merged shape.
Instead: when two slices touch one function's signature, they are one slice or
they are strictly sequential. Declare the shared symbol, not just the file.
```

Append it to `docs/loop/decisions.md`. A merge conflict fixed silently is a lesson thrown away; the cost is paid again by the next unit at full price.

## Migration ordering across worktrees

Two lanes each running `make:migration` produce two timestamps generated in isolation, and the timestamps reflect **when each agent ran**, not the order the schema needs.

Before merging the second one:

```bash
git diff main...HEAD --name-only -- database/migrations/
php artisan migrate:status
```

Check three things:

1. **Does either migration depend on the other's table or column?** If yes, the filename timestamps must sort in dependency order. Rename the later one; it has never run anywhere, so renaming is free.
2. **Do both alter the same table?** Two `ALTER`s on one table in one release is a lock-duration question, not just an ordering one — merge them or sequence them deliberately.
3. **Does `down()` still reverse cleanly in the new order?** A rollback runs in reverse filename order, which the rename just changed.

Run `php artisan migrate:fresh` on a scratch database after merging both. A migration set that only works forward from an existing state is a set that fails on the next fresh environment.

## Cleanup

```bash
git worktree list                                    # what still exists
git worktree prune                                   # drop records of deleted dirs
git worktree remove .claude/worktrees/agent-<id> --force
git branch -d worktree-agent-<id>                    # -d, not -D: refuses if unmerged
```

Use `-d` deliberately. Its refusal to delete an unmerged branch is the last guard against discarding a lane's work.

**When a lane was abandoned** — blocked at the cap, or re-sliced at G1 — preserve before removing:

- The `blocked` return's hypotheses and classification → into the re-brief, or `docs/loop/<slug>/log.md`
- Any genuine finding the lane surfaced about the codebase → `docs/loop/decisions.md`
- The branch itself, until the replacement slice is green: `git branch -m worktree-agent-<id> abandoned/<slice>`

The work is discardable. What the lane **learned** is the expensive part, and removing the worktree deletes it silently.
