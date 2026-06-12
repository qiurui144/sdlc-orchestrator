---
description: Design CI/CD pipeline with canary/blue-green + rollback runbook. Dispatches cicd-designer (sonnet).
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent, Skill]
---

# /sdlc:cicd

Invokes **cicd-designer** (sonnet). Per spec G.2.6. Production requires canary or blue-green; rolling for staging-only. Rollback runbook mandatory.

## Behavior

1. Detect CI platform (GitHub Actions / GitLab CI / Jenkins / CircleCI)
2. Detect stack (language + runtime + containerisation)
3. Ask user service tier (critical / important / standard) if not in context
4. Pick CD strategy per tier:
   - critical -> canary (5% -> 25% -> 100%) with auto-rollback on error rate spike
   - important -> blue-green with smoke test before switch
   - standard -> rolling deploy (staging only acceptable)
5. Emit pipeline YAML + `docs/cicd-strategy.md` + `docs/rollback-runbook.md`
6. Embed dependency-auditor (`/sdlc:deps`) + performance-analyst (`/sdlc:perf`) gates in pipeline

## Preconditions

- Repo has `.git/`
- Docker or equivalent containerisation available (or pipeline adapted for bare-metal)

## Next step

Review emitted pipeline YAML; commit to `.github/workflows/` or equivalent.
Rollback runbook linked from release checklist.
