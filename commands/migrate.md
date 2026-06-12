---
description: Design migration with pattern (strangler-fig/parallel-run/blue-green/dark-launch/feature-flag) + rollback runbook + reversibility analysis. Dispatches architecture-reviewer (opus) in migration mode.
argument-hint: <slug> [pattern]
allowed-tools: [Read, Write, Edit, Glob, Grep, Agent, Skill]
---

# /sdlc:migrate <slug> [pattern]

Invokes **architecture-reviewer** (opus) in migration mode. Runs `migration-strategy` skill. Produces `docs/migrations/<date>-<slug>.md` with pattern + steps + rollback runbook + reversibility analysis.

## Behavior

1. Pre-Create Gate on `docs/migrations/<date>-<slug>.md`
2. If pattern not specified -> architecture-reviewer auto-selects per migration type + risk
3. Migration plan with explicit point-of-no-return step
4. Rollback runbook per step (no step may lack a rollback)
5. Monitoring period defined (default 7d; minimum 3d with justification)
6. Emits handoff YAML with reversibility_score + self_score

## Preconditions

- slug is kebab-case
- Migration context described (what is changing, what is affected)

## Next step

After approval, migration steps feed into `/sdlc:plan` or `/sdlc:release` cutover checklist.
