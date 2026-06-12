---
name: ui-vision-judge
description: Provider-agnostic vision judge for rendered-screenshot understanding. Use when a web-UI or design task needs an LLM to look at a screenshot and answer a soft question (does this look rendered, what category, how good) via a user-configured OpenAI-compatible vision endpoint. Returns a soft annotation only — never a pass/fail verdict.
---

# ui-vision-judge

`judge.sh` takes a screenshot + a question and returns a **soft, schema-bounded judgment** from
the user's configured OpenAI-compatible vision model. It is a deterministic bash driver: env-config
parse, base64 data-URI build, request build, response validate, retry, graceful degrade, secret
redaction, and telemetry are all zero-LLM. Only the single vision call is non-deterministic, and it
sits behind a `--stub <fixture>` seam so the test suite runs with **zero network**.

## Deterministic-verdict-supremacy (load-bearing invariant)

The output schema has **no `verdict` / `pass` / `fail` field**. It is `vision_status` +
(`looks_ok` | `classification` | `score`) + `confidence` + `reason`. Consumers that DO produce a
verdict — `web-ui-verify/verify.sh` — keep their deterministic 7-part engine byte-unchanged and
attach this annotation *alongside* the verdict. A vision model can never flip a deterministic FAIL
to PASS. This is the whole point: vision adds explanation, never authority.

## Provider configuration (§4.5 — no plugin-side tier assumed)

The plugin installs nothing and assumes no model tier. The user points it at any
OpenAI-compatible chat/vision endpoint (Qwen-VL via DashScope, GPT-4o, Gemini via a compat shim,
a local llava, …) through three env vars:

| Env var | Meaning | Example |
|---------|---------|---------|
| `SDLC_VISION_BASE_URL` | OpenAI-compatible base | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| `SDLC_VISION_MODEL` | vision-capable model id | `qwen-vl-max` |
| `SDLC_VISION_API_KEY` | bearer token | (env only — never echoed, never committed) |

The API key is read from the environment only (CLAUDE.md §1.4) and is **redacted in every line**
of output, including fed-back error bodies during retry (a provider 401 body can echo the
`Authorization` header — that is scrubbed before it re-enters the prompt or the log).

## Graceful degrade (§4.5-E)

| Situation | `vision_status` | `reason` | Exit | Caller effect |
|-----------|-----------------|----------|------|---------------|
| Provider not configured | `unavailable` | `unconfigured` | 0 | annotation advisory; verdict path unaffected |
| Configured, model answers + grounded | `ok` | (model's reason) | 0 | annotation populated |
| Retries exhausted (malformed/ungrounded) | `unavailable` | `retries-exhausted` | 0 | annotation advisory; **never** a false PASS |
| Timeout / transport error after retry | `unavailable` | `timeout` / `http-error` | 0 | annotation advisory; **never** a false PASS |

`vision_status` is coarse (`ok` | `unavailable`); `reason` carries the detail. Degrade never raises
a hard error to the caller and never fabricates a judgment.

## Usage

```bash
# advisory look at a captured screenshot (config via env)
skills/ui-vision-judge/judge.sh \
  --image docs/screenshots/login/rendered.png \
  --question "Is the login form fully rendered with both fields and a submit button visible?" \
  --kind looks_ok

# offline / CI: use a captured fixture instead of a live call
skills/ui-vision-judge/judge.sh --image docs/screenshots/login/rendered.png \
  --question q --stub examples/vision-fixtures/good.json
```

Screenshots must live under `docs/screenshots/` or `.playwright-mcp/` (§6.4); a path elsewhere is
rejected (exit 2).

## Honesty (§7.3)

The real `curl` transport was **manually verified this session** against the DashScope
OpenAI-compatible API (`qwen3.7-plus` + `qwen3.6-flash`; qwen-vl is retired): a rendered screenshot
⇒ grounded `looks_ok:true`, a blank page ⇒ `looks_ok:false` (it discriminates), a bad model ⇒
`vision_status:unavailable/http-error`, and the key never leaks. Per §6.3 this is a manual spot-check
(raw log not archived); the **formal §4.5-D multi-tier F1 matrix** (N≥10 cases × weak/mid/strong,
spread ≤ 0.15) + archived evidence remain **PENDING** (tracked in the roadmap). The deterministic
driver (config, base64 round-trip, request build, validate, retry, degrade, redaction) is fully
covered by the zero-network bats suite.
