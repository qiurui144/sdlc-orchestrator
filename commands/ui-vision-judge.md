---
description: Judge a UI screenshot with a provider-agnostic vision LLM (soft annotation, never a verdict). Dispatches skills/ui-vision-judge/judge.sh; provider via SDLC_VISION_* env; degrades to unavailable if unconfigured. Real provider call PENDING-VERIFY.
argument-hint: "<screenshot> [--question <q>] [--kind looks_ok|classification|score]"
allowed-tools: [Read, Bash, Skill]
---

# /sdlc:ui-vision-judge

Run the **ui-vision-judge** skill over a rendered screenshot and return a SCHEMA-BOUNDED soft
judgment via the user-configured OpenAI-compatible vision provider.

## Deterministic-verdict-supremacy

The output is a SOFT annotation only — it NEVER decides PASS/FAIL. The `web-ui-verify` 7-part
deterministic engine remains the source of truth; this only ANNOTATES (and is byte-diff-regression
tested to never flip the verdict). Provider unconfigured ⇒ `vision_status: unavailable` (advisory).

## Steps

1. Confirm the screenshot lives under `docs/screenshots/<topic>/` or `.playwright-mcp/` (§6.4) — a
   path elsewhere is rejected (exit 2).
2. Confirm the provider is configured in env: `SDLC_VISION_BASE_URL`, `SDLC_VISION_MODEL`,
   `SDLC_VISION_API_KEY` (OpenAI-compatible; e.g. Qwen-VL via DashScope). **Never echo the key** — it
   is read from env only and redacted (`sk-***`) everywhere (§1.4). Unconfigured ⇒ graceful degrade.
3. Recommend `--dry-run` first to show the resolved config + request shape without any provider call.
4. Invoke the skill:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/ui-vision-judge/judge.sh" \
     --image "$1" --question "${question:-does this UI look visually broken?}" --kind "${kind:-looks_ok}"
   ```

5. Interpret the output (always exit 0 — the judge never gates):
   - `vision_status: ok` — judgment populated (`looks_ok` | `classification` | `score` + reason).
   - `vision_status: unavailable` — degraded (`reason`: unconfigured / retries-exhausted / timeout /
     http-error); advisory only, the deterministic verdict is unaffected.

## Honesty (§7.3 / §4.5)

The real `curl` provider call and the §4.5-D multi-tier compatibility matrix are **PENDING-VERIFY**
(need a real key; the zero-network bats suite exercises only the `--stub` seam). The deterministic
driver (config, base64 round-trip, request build, validate, retry, degrade, redaction) is fully tested.
