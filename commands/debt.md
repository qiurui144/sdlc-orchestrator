---
description: Tech debt registry + sprint budget burn-down. Dispatches tech-debt-tracker (haiku).
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent]
---

# /sdlc:debt

Invokes **tech-debt-tracker** (haiku). Per spec G.2.4. Grep TODO/FIXME with required format `// TODO(@owner, YYYY-MM-DD): reason`. Regenerates `docs/tech-debt.md`.

## Behavior

1. Grep markers in repo (TODO / FIXME / HACK / XXX)
2. Validate format: owner + due-date + reason; malformed markers flagged
3. Categorize by severity / age / cost-to-fix
4. Regen `docs/tech-debt.md` registry (Pre-Create Gate: extend if exists)
5. Update `.sdlc/debt-budget.yaml` burn-down (sprint budget remaining)
6. Report `reports/<date>_debt.md`

## Preconditions

- Repo has `.git/`

## Next step

Items with severity=critical or overdue -> file in task tracker before next sprint.
Budget exhausted -> pause new features; dedicate sprint to debt paydown.
