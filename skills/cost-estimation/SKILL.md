---
name: cost-estimation
description: Use to estimate the token + USD cost of an SDLC phase or full sprint (the /sdlc:cost command) at current model tiers, with a per-project budget check. Pure deterministic, zero-LLM. Estimate only — not a precise bill.
---

# cost-estimation

## When to use
- Before starting a sprint/phase, to see what it will cost at current tiers.
- To check a sprint estimate against a per-project `token_budget`.

## What it does (zero-LLM)
`cost.sh [--phase <name> | --sprint]` reads `config/pricing.yaml` (per-tier $/M, dated
ESTIMATE), `config/cost-model.yaml` (per-agent token estimate), and each agent's
`model_tier`, then sums input×in-price + output×out-price. Prints per-agent + total +
budget status. Over budget → warn (or exit 2 if `budget_strict`).

## Honest limits
- ESTIMATE: prices drift (see `as_of`), token counts are typical-case approximations.
- Not a metered bill — CC has no per-call token hook yet (v0.6).

## Linked
- [[task-orchestrator]] / [[releaser]] (cost-aware dispatch); `config/pricing.yaml`,
  `config/cost-model.yaml`, spec §3.3/§3.4
