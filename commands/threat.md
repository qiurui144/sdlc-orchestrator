---
description: STRIDE threat model for a component / data flow. Invokes threat-model-stride skill via architecture-reviewer (opus).
argument-hint: <component-slug>
allowed-tools: [Read, Write, Edit, Glob, Grep, Agent, Skill]
---

# /sdlc:threat <component-slug>

Invokes **architecture-reviewer** (opus) in threat mode. Runs `threat-model-stride` skill (6 STRIDE letters enumerated). Produces `docs/security/<component>-threat-model.md`.

## Behavior

1. Pre-Create Gate on `docs/security/<component>-threat-model.md`
2. Architecture-reviewer dispatches threat-model-stride skill
3. STRIDE enumeration for each DFD element (no silent skip)
4. Risk scored (Likelihood x Impact); scale 1-25
5. Mitigations required for risks >= Medium (>= 8)
6. Emits handoff YAML with self_score

## Preconditions

- component-slug is kebab-case
- At minimum a description of the component's data flows exists in context

## Next step

After threat model approval, action items feed into spec §11 (risk register) or `/sdlc:adr` for security design decisions.
