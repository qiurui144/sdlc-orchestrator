---
name: model-provider
description: Provider-agnostic OpenAI-compat TEXT caller for SDLC multi-model routing. Ports the ui-vision-judge provider kernel (env <P>_BASE_URL/_MODEL/_API_KEY, schema-guided, retry-validate up to 3, degrade to claude, redact ALL loaded keys, stub seam). Output is raw model content; a gate verdict is NEVER derived here (deterministic-verdict-supremacy). Exit 0 ok, 6 unconfigured, 7 degraded.
---

# model-provider

The provider-agnostic OpenAI-compatible TEXT caller for SDLC multi-model routing (M1). Ports the
proven `ui-vision-judge/judge.sh` kernel to text — it does not embed any product logic; the model is
whatever the operator configured.

## Contract

```
call.sh --provider <deepseek|openai|qwen> --messages <file.json> [--model <id>] [--schema <f>] [--max-retries N] [--timeout S] [--stub <f>]
  -> stdout: model content (exit 0) | degrade marker {"model_status":"degraded","fallback":"claude",...} (exit 7)
  -> exit: 0 ok . 2 usage . 6 provider-unconfigured . 7 degraded
```

`--stub <f>` bypasses the network with a canned response (zero-network tests). The real `curl` path is
§7.3 PENDING-VERIFY (exercised in M2/test against the verified deepseek-v4 endpoint).

## Secrets (§1.4)

Keys come from env `<P>_API_KEY` (the caller loads them from `/tmp/secrets-<p>/key.env`). `redact()`
scrubs EVERY loaded provider key (literal substitution, metachar-safe) on all feedback/telemetry, plus
a broadened `Bearer` fallback. GPT enters via `OPENAI_BASE_URL` — either api.openai.com (key) or a
local codex-proxy reusing a ChatGPT Plus subscription (spec §6; ToS/reliability gray -> non-critical only).

## Deterministic-verdict-supremacy

The output is raw model content. A gate verdict (eval pass/fail, review BLOCK) is NEVER derived from a
routed model here — those stay deterministic/claude (spec §7).

## Linked

- ports `skills/ui-vision-judge/judge.sh` kernel
- pairs with [[model-router]]
