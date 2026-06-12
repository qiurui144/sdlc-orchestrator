---
description: Serial cross-feature merge-queue — merge completed feature branches one at a time, assign the next version + tag at merge time (§7.1.7). Reuses worktree-merge/merge.sh.
argument-hint: <f1,f2,...>
allowed-tools: [Read, Glob, Grep, Bash, Skill]
---

# /sdlc:merge-queue <f1,f2,...>

Drives the **merge-queue** skill over completed, mutually-independent feature branches.
For each feature in completion order: merge to the mainline, compute the next RELEASE
version at merge time, tag it. On conflict it stops and reports which feature must rebase
on the new baseline.

## Behavior

1. Determine the mainline branch name (`git symbolic-ref --short HEAD` or the repo default —
   never a SHA/HEAD literal).
2. Run `skills/merge-queue/queue.sh --base <mainline-branch> --features <args>`
   (add `--bump minor` / `--tag-prefix <p>` / `--repo <path>` / `--dry-run` as needed).
3. Report the `merged=<f> tag=<v>` sequence, or the `conflict=<f>` / `missing-feature=<f>` /
   `tag-collision=<v>` that stopped the queue.
4. On clean completion, remove the merged feature worktrees (§1.1.6).

## Constraints

- Tags are created **locally only**. **Do not push** — pushing tags is a user action (§7.2;
  tags are immutable once pushed).
- Only mutually-independent features go in one batch; real dependencies are serialized at the
  roadmap layer (`addBlockedBy`).
- Multi-repo `--repo` is a v0.11 **prototype** (one repo at a time); full multi-repo is ent-v1.0.
