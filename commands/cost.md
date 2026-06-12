---
description: Estimate the token + USD cost of an SDLC phase or full sprint at current model tiers, with budget check. Zero-LLM estimate (not a precise bill).
argument-hint: "[phase-name | sprint]"
allowed-tools: [Read, Bash, Skill]
---

# /sdlc:cost [phase-name | sprint]

Runs the deterministic `cost-estimation` skill.

## Behavior
1. Run `${CLAUDE_PLUGIN_ROOT}/skills/cost-estimation/cost.sh` (`--phase <name>` or `--sprint`).
2. Reads `config/pricing.yaml` + `config/cost-model.yaml` + each agent's `model_tier`;
   prints per-agent and total token + USD estimate, labelled ESTIMATE with the pricing date.
3. If the project config sets `token_budget`, reports within/over; with `budget_strict`,
   over-budget exits non-zero.

## Examples
- `/sdlc:cost --sprint` — full spec→release chain estimate.
- `/sdlc:cost spec` — just the spec phase (spec-analyst).

## Honest limit
Estimate only — prices drift (see `as_of`), token counts are typical-case. Not metered.
