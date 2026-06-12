---
description: Draft an Architecture Decision Record for a new component / data flow / external dep. Dispatches architecture-reviewer (opus) in ADR mode.
argument-hint: <decision-slug>
allowed-tools: [Read, Write, Edit, Glob, Grep, Agent, Skill]
---

# /sdlc:adr <decision-slug>

Invokes the **architecture-reviewer** agent (opus) in ADR mode. Produces `docs/adr/<NNNN>-<decision-slug>.md` per spec G.2.1.

## Behavior

1. Validate decision-slug is kebab-case
2. Pre-Create Gate on `docs/adr/<NNNN>-<slug>.md` path (auto-increment NNNN)
3. Dispatch architecture-reviewer with mode=adr + slug + chat context
4. Agent produces 5-section ADR (Context / Decision / Status / Consequences / Alternatives)
5. Emits handoff YAML with sha + self_score

## Preconditions

- Repo has `.git/`
- User has provided decision context (otherwise architecture-reviewer refuses and asks)

## Next step

After ADR is approved, link from affected spec sections or implementation plan.
