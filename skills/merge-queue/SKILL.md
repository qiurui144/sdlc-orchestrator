---
name: merge-queue
description: Use when multiple independent features developed in isolated worktrees are complete and must be merged back to the mainline one at a time, each getting the next version tag. Performs a serial merge-queue — for each feature it merges via worktree-merge/merge.sh, then computes the next RELEASE version at merge time and tags it (§7.1.7). On conflict it STOPS and escalates (the blocked feature must rebase on the new baseline); it NEVER auto-resolves and NEVER force-tags or pushes. The feature-layer lift of v0.10 shard-then-merge.
---

# merge-queue

The cross-feature half of v0.11. Independent features each run a full SDLC sub-sprint
in an isolated worktree (feature-branch = "shard"); this skill merges those branches
back **serially**, assigning the next version + tag at the moment each one merges.

## When to use

- N independent features are complete (each its own branch, each already reviewed+tested)
  and must land on the mainline with sequential version tags.
- NOT for tasks inside a single plan — that is v0.10 [[worktree-merge]].
- NOT for features with a real dependency between them — serialize those at the roadmap
  layer (`addBlockedBy`); the queue only takes mutually-independent features.

## Contract

```
queue.sh --base <mainline-branch> --features <f1,f2,...> \
         [--repo <path>] [--bump patch|minor] [--tag-prefix v] [--dry-run]
```

- `--base` is the mainline **branch name** (e.g. `main`/`master`), constant across the
  whole queue. **Never pass HEAD or a SHA** — merge.sh checks the base out and advances
  its ref; a detached HEAD would orphan every tag (see Pitfalls).
- For each feature, in order: `merge.sh --base <branch> --branches <fi>` →
  - **clean** → next version from existing RELEASE tags (pre-release filtered) →
    `git tag <v>` on the advanced mainline tip → `merged=<fi> tag=<v>`. exit continues.
  - **conflict** → `conflict=<fi> files=...`, exit 1, queue STOPS.
  - **missing branch** → `missing-feature=<fi>`, exit 2.
  - **tag collision** → `tag-collision=<v>`, exit 2 (never force-overwrites, §7.2).
- `--dry-run` → prints `would-merge=<fi> would-tag=<v>` for the whole sequence, mutates nothing.

## Version-at-merge-time (§7.1.7)

The version is decided **when a feature merges**, not when it is dispatched. The first
feature to merge grabs `v0.X.1`, the next `v0.X.2`, … — so parallel development and a
strictly-increasing serial tag line coexist. `next_version` reads `git tag`, **filters
pre-release tags** (`-rc`/`-alpha`/`-beta` — otherwise `v1.0.0-rc.1` poisons the sort),
and bumps the patch (default) or minor segment. Because it returns `max+1`, the computed
tag never self-collides in single-driver use; the collision exit is a TOCTOU backstop.

## Conflict → rebase on new baseline (NEVER auto-resolve)

A conflict means the feature was not actually independent of an earlier-merged feature.
The queue aborts that merge (merge.sh restores a clean tree) and STOPS. The blocked
feature must be **rebased onto the new mainline baseline** (the tip after the earlier
features merged) and then re-submitted to the queue. The skill never runs merge tools,
never picks a side, never commits a conflicted tree (CLAUDE.md §5.1 — no silent resolution).
Earlier features that already merged keep their tags, which remain reachable from the mainline.

## Multi-repo — prototype only

`--repo <path>` runs the whole queue inside another repo's git-dir, proving the primitive
is repo-parameterized. Full multi-repo orchestration (cross-repo dependency ordering,
atomic synchronized tags across repos, multi-repo state) is **out of scope for v0.11**
and reserved for **ent-v1.0**.

## Lifecycle

Tags are created **locally only** — pushing is a user action (§7.2; tags are immutable).
After the queue, the driver removes merged feature worktrees (§1.1.6 disk hygiene).

## Pitfalls

- **Passing HEAD/SHA as `--base`** → detached HEAD → tags land on orphan commits and
  vanish on the next checkout. queue.sh refuses a non-branch base (exit 2), but callers
  must still pass the branch name.
- **Pre-release tags** in the repo → handled (filtered), but if you add a new pre-release
  scheme, extend the filter.

## Linked

- skill [[worktree-merge]] (the per-merge core this calls)
- skill [[multi-agent-dispatch]] (budget/counter gate for the parallel feature dispatch side)
- agent [[task-orchestrator]] (drives feature worktrees, then this queue)
