# Conventions

Rules the team has taught the loop. Every agent treats these as overrides on default behavior.

Add one entry per rule, in the shape: what to do, and the correction that produced it.

<!-- Example:
## Migrations
Always add a down() that reverses the up() exactly, even for additive-only changes.
Taught after: a rollback on staging left an orphaned column because down() was a no-op.
-->

## Confirm a lane's base before it writes code

Every build brief tells the lane to run `git log --oneline -1` against its own branch and
against local `main`, and to merge `main` in first if they differ.

Taught after: four consecutive lanes in `cost-ledger-blind-to-background-agents` forked from
a commit that predated already-merged work — one was fourteen commits behind. Each
self-corrected, so nothing broke, but `worktree-merge` already says to check the base *on
entry* precisely because a conflict resolved against an empty diff is a one-line decision
and the same conflict after 300 lines is archaeology. Discovering it per-agent wastes the
discovery every time.

## "Already up to date" after a lane reported work is an error, not a no-op

Before removing any worktree, confirm the merge actually took: `git log --oneline
main..<branch>` must be non-empty, and the diff stat must be non-zero. Only then remove the
worktree and delete the branch.

Taught after: a lane in `cost-ledger-blind-to-background-agents` committed its work to a
branch it named itself rather than the worktree branch it was checked out on. `git merge
worktree-agent-<id>` reported "Already up to date" and merged nothing, and cleanup ran
anyway. The work survived only because the agent's own branch still held it, and `git branch
-d` refused nothing because the stale branch genuinely was an ancestor. This fails quietly
in the direction of losing work rather than breaking a build, which is the worse direction.

Two halves to the fix, and both are needed: briefs tell the lane to commit on the worktree
branch it is already on and not to create a differently-named one; the orchestrator verifies
a non-empty merge before cleaning up regardless.

## A build agent may finish green and leave the work uncommitted

Check the branch tip before merging. A lane can return `STATUS: done` with a passing suite
while its changes sit as unstaged working-tree modifications, leaving the branch at its base
commit.

Taught after: the first two lanes of `cost-ledger-blind-to-background-agents` both did this.
Later briefs added an explicit "commit your work on your worktree branch before returning"
line, which fixed it.

## A green harness never proves a hook is live

Treat "the tests pass" and "the hook is registered" as independent claims. A hook is proven
live only by state it writes during a real run.

Taught after: the cost ledger's 334-case suite was green for three days while
`record-cost-event.sh` had never once fired — the tests invoke hook scripts directly over
stdin and never exercise the registration path. Installing from a marketplace snapshots the
plugin, so a repo-side `hooks.json` change needs a reinstall *and* a restart before it is in
the loop.
