---
name: model-router
description: Deterministic risk-to-provider router for SDLC multi-model routing. Reads risk-classify's tier (LOW/NORMAL/HIGH) plus a conservative config/model-routing.yaml and decides which provider (claude/deepseek) a task routes to. DEFAULT disabled means all claude (opt-in via config enabled true or SDLC_MULTI_MODEL=1). HIGH and uncertain ALWAYS claude. Zero-LLM, main-context.
---

# model-router

The deterministic risk-to-provider decision layer for SDLC multi-model routing (M1). It never calls
an LLM and never makes a network request — it reads the tier and emits a routing decision.

## Contract

```
route.sh (--tier T --model-class M | --staged | --names <f>) [--config <yaml>]
  -> tier=<T> model_class=<M> provider=<p> model=<id> reason=<kebab>   (exit 0 always)
```

When `--tier` is absent it runs `skills/risk-classify/risk-classify.sh` (`--staged`/`--names`); a
risk-classify exit 2 (unusable) resolves to HIGH (fail-safe).

## Routing policy

- disabled (default) -> claude for all tiers (`reason=multi-model-disabled`)
- LOW / mechanical   -> `low_provider` (deepseek) when enabled
- NORMAL             -> claude (`reason=normal-default-claude`); deepseek only after M2 eval clears a task-type >= floor
- HIGH               -> claude (`reason=high-never-externalized`) — never externalized
- unknown tier / risk-classify exit 2 -> claude (`reason=uncertain-tier-to-claude`)

## Opt-in (zero behavior change by default)

`SDLC_MULTI_MODEL=1` (env wins) OR `enabled: true` in the config. Otherwise every tier is claude, so a
repo with the plugin installed behaves exactly as before until the operator opts in.

## Linked

- reads `skills/risk-classify/risk-classify.sh`; config `config/model-routing.yaml`
- pairs with [[model-provider]] (router decides, call.sh calls)
