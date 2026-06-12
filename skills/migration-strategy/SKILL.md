---
name: migration-strategy
description: Use when architecture-reviewer is in migration mode OR user invokes /sdlc:migrate <pattern>. Selects from 5 patterns (strangler-fig / parallel-run / blue-green / dark-launch / feature-flag) per risk profile. Produces migration plan + cutover runbook + reversibility analysis.
---

# migration-strategy

## When to use

- architecture-reviewer migration mode
- `/sdlc:migrate <pattern>` (auto-select pattern if not specified)
- Any schema / API / runtime change that touches production data or breaking interface

## When NOT to use

- New greenfield component (no migration needed)
- Internal refactor (no data movement)

## 5 migration patterns

| Pattern | When | Reversibility | Cost |
|---------|------|---------------|------|
| **Strangler-fig** | Legacy system gradual replace | High (per-piece rollback) | Medium |
| **Parallel-run** | New algorithm shadow validates | High (no cutover yet) | High (2x compute) |
| **Blue-green** | Atomic switch needed | High (instant rollback) | High (2x infra) |
| **Dark-launch** | Want perf data without exposing | High (off by default) | Medium |
| **Feature-flag** | Per-user/cohort gradual rollout | High (toggle off) | Low |

## Selection criteria

- Schema migration with data backfill -> **parallel-run** + **dual-write** until cutover
- API breaking change -> **feature-flag** for gradual cohort migration + **blue-green** at end
- Algorithm replacement -> **parallel-run** then **strangler-fig** retire old
- Major version upgrade -> **blue-green** with smoke test before switch
- Performance-sensitive change -> **dark-launch** measure then **feature-flag** rollout

## Steps

1. **Classify migration**: schema / API / runtime / data / dependency
2. **Pick pattern** per selection criteria
3. **Write migration plan** with steps:
   - Pre-flight checks
   - Data backfill (if needed)
   - Cutover execution
   - Verification
   - Monitoring period
4. **Write rollback runbook**: explicit per-step undo
5. **Reversibility analysis**: at which step is rollback no longer possible? document the point of no return
6. **Monitoring period** define: minimum N days post-cutover before considered stable
7. **Output**: `docs/migrations/<date>-<slug>.md` containing all above

## Output schema

```yaml
schema_version: 1
migration_slug: <slug>
migration_type: schema | api | runtime | data | dependency
pattern: strangler-fig | parallel-run | blue-green | dark-launch | feature-flag
steps:
  - id: 1
    name: pre-flight
    actions: [...]
    rollback: [...]
  - id: 2
    name: data-backfill
    actions: [...]
    rollback: [...]
point_of_no_return:
  step_id: 5
  reason: <prose>
monitoring_period_days: 7
reversibility_score: 4  # 1-5; 5 = trivially reversible at any point
self_score:
  pattern_selection_justified: 5
  rollback_completeness: 5
  reversibility_explicit: 5
```

## Failure modes

1. Pattern selection ambiguous -> ask user explicitly
2. Point-of-no-return unclear -> reject plan; require explicit step
3. Rollback runbook missing for any step -> reject
4. Monitoring period < 3d -> require justification

## Linked

- [[architecture-reviewer]] (invokes this)
- [[releaser]] (cutover during release)
- spec §11 SE9 / SE12
