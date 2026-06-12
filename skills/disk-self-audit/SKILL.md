---
name: disk-self-audit
description: Use after every sprint / agent dispatch / before any build. CLAUDE.md §1.1.6 three-mount audit (/ /tmp /data) — exit 2 below the avail floor in strict mode is ENOSPC build-safety. `--reclaim [--apply]` does VALUE-BASED periodic reclamation of build/worktree scratch (cargo target*/ + worktrees + .tmp*) — reclaims what is stale beyond a retention window and not an active worktree, regardless of disk fullness (no usage-% threshold). Dry-run by default.
---

# disk-self-audit

## When to use

- After every agent dispatch completion (per §1.1.6)
- After every sprint completion (Stop hook)
- Before any build command (PreToolUse:Bash hook with cargo/npm/go/pytest)
- On-demand via `/sdlc:disk`

## What it does

1. `df -h / /tmp /data` (or simulate via `SDLC_DISK_FAKE_*` env vars for testing)
2. Compare each mount's available GB against redline thresholds
3. Defaults: root=50G, /data=50G, /tmp=5G (per §1.1.6); overridable via config
4. `data_used_pct` is reported **informationally only** — there is **NO usage-% gate** (a 20T disk shouldn't wait until 19T to act). Routine fullness is handled by **value-based `--reclaim`** (below), not by a threshold.

## Action on redline

- Avail-floor hit (a mount's free GB below `redline_*_gb`): strict → exit 2 (BLOCK the tool call); warn → exit 1.
  This is the **only** blocking condition and it is **ENOSPC build-safety** (a build needs absolute headroom
  regardless of disk size) — NOT a "how full" gate.
- Print suggested cleanup commands + the `--reclaim [--apply]` pointer.

## Reclaim (`--reclaim [--apply]`) — value-based, periodic, NOT fullness-gated

Classifies each top-level entry under `SDLC_SCRATCH_ROOTS` (colon-list; default
`/data/tmp-sdlc:/data/tmp-cargo`; override via env or disk.conf `scratch_roots=`):

- **no value ⇒ RECLAIM**: mtime older than the retention window (`SDLC_SCRATCH_RETENTION_DAYS`, default 7)
  AND not an active git worktree.
- **value ⇒ KEEP**: recent (within retention — may be in use), OR a git worktree with **uncommitted
  changes** (never reclaimed — no work is ever lost).

This is **independent of disk fullness** — valueless scratch is reclaimed whether /data is 10% or 90%
full. `--reclaim` alone is **dry-run** (lists KEEP/RECLAIM with age + size); `--reclaim --apply` does the
`rm -rf` (and reminds you to `git worktree prune`).

**Periodic** (the real prevention — continuous, not threshold-triggered): run
`bash <audit> --reclaim --apply` on a schedule (cron / scheduled agent / Stop hook). Set
`SDLC_SCRATCH_AUTORECLAIM=1` to have the **Stop hook auto-apply** at session end. So stale build/worktree
scratch is reclaimed by value continuously, and can never silently grow to 253G again.

## Steps

1. Read `df` (or fake env)
2. Compare to thresholds
3. Emit YAML snapshot to stdout (consumed by handoff schema)
4. Exit with right code

## Linked
- spec §1.1.6 / §11 R4 R16
- hook `PreToolUse:Bash(build)`
- hook `Stop`
