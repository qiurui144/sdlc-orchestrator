---
name: worktree-merge
description: Use when the implementer finishes a parallel wave of tasks that ran in isolated git worktrees and their branches must be merged back to the mainline. Performs a serial topological merge with conflict detection — on conflict it aborts and reports, NEVER auto-resolving (a conflict means the DAG was mis-marked; escalate to the architect). The git-layer counterpart of v0.9 shard-then-merge.
---

# worktree-merge

The merge half of v0.10 parallel implementation. Parallel tasks run in isolated
worktrees (each on its own branch = a "shard"); this skill merges those branches
back serially, in topological order, detecting conflicts.

## When to use

- The implementer dispatched a wave of no-dependency tasks via `Agent isolation:'worktree'`
  (per [[multi-agent-dispatch]] dispatch-batch) and all returned with their own branch.
- NOT for sequential single-task impl (nothing to merge).
- NOT for cross-feature merges yet — that is v0.11 (this skill is the reusable core).

## Contract

```
merge.sh --base <branch> --branches <b1,b2,...>   # branches in topological order
```

- Checks out `<base>`, then `git merge --no-ff --no-edit` each branch in order.
- **Clean** → prints `merged=<b>` per branch, exit 0.
- **Conflict** → `git merge --abort` (restores a clean tree), prints
  `conflict=<b> files=<f1,f2>`, exit 1. Stops at the first conflicting branch.
- Bad args / not-a-git-repo / bad base → exit 2.

## Conflict → escalate (NEVER auto-resolve)

A merge conflict means two "parallel" tasks touched the same lines — i.e. the
`parallelizable_with` DAG was mis-marked (they were not actually independent). The
implementer writes an `impl:plan` MERGE_CONFLICT handoff and escalates to the
architect to re-mark the DAG. The skill never runs merge tools, never picks a side,
never commits a conflicted tree (spec §5.1 / CLAUDE.md §5.1 — no silent resolution).

## Wave / topological ordering

The implementer layers the plan's tasks into waves (Kahn): wave 0 = no-dependency
tasks, wave k depends only on waves < k. Tasks within a wave run in parallel; this
skill merges a wave's branches in a deterministic topological order so the merge is
reproducible.

## Lifecycle

After a clean merge the implementer `git worktree remove`s the merged worktrees
(§1.1.6 disk hygiene). A failed task's worktree is kept for diagnosis and marked
degraded; sprint-archival cleans up leftovers.

## Config

| Env | Default | Meaning |
|-----|---------|---------|
| `SDLC_MERGE_STRATEGY` | (not read in v0.10) | hardcoded `merge --no-ff`; rebase/squash reserved for v0.11 — setting this has NO effect yet |
| `SDLC_MAX_PARALLEL` | 2 | wave size cap (shared with [[multi-agent-dispatch]]) |

## Linked

- skill [[multi-agent-dispatch]] (dispatch-batch + counter cap that feeds the wave)
- agent [[implementer]] (caller; layers waves, dispatches, merges, escalates)
