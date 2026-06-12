---
name: sprint-archival
description: Use when a sprint completes (ship-merged to master OR tag pushed). Per CLAUDE.md §1.1.7, plans get DELETED, verification reports get INLINED into RELEASE.md, temp scripts integrated into official CLI deleted. Sprint not archived = sprint not finished.
---

# sprint-archival

## When to use

- After `/sdlc:release` completes successfully (tag pushed)
- On `Stop` hook if state machine reaches `GA_TAG`
- Manually `/sdlc:audit-docs --archive-sprint <sprint-id>` (advanced)

## What it does

| File | Action |
|------|--------|
| spec (`docs/superpowers/specs/<date>-<slug>.md`) | KEEP |
| plan (`docs/superpowers/plans/<date>-<slug>.md`) | DELETE |
| handoffs (`docs/superpowers/handoffs/<date>-<slug>-*.yaml`) | INLINE into RELEASE.md, then DELETE |
| test reports (`reports/<date>-test.md`) | INLINE evidence row into RELEASE.md |
| sprint metadata (`.sdlc/sprints/<date>.yaml`) | rotate |
| temp scripts | review + consolidate + DELETE |

## Linked
- spec §1.1.7 / §3.2 / §11 R17
- skill [[pre-create-gate]]
