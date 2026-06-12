---
name: web-ui-verify
description: Use when verifying a web-UI deployment actually renders in a real browser (not just curl 200) — lands CLAUDE.md §2.2 user-first, §6.4 Playwright-Chrome E2E, §7.3 real-browser render verify for web-UI repos. verify.sh detects the frontend stack, probes the optional Playwright MCP (absent ⇒ honest UI-UNVERIFIED, never a false PASS), §6.4-lints, parses a per-target web-ui-verify.yaml success contract (absent/trivial ⇒ exit 7), and emits a PASS/FAIL/UI-UNVERIFIED verdict. Zero-LLM deterministic layer; MCP detected, never installed. Real browser reads are §7.3 PENDING-VERIFY (need a real app + connected MCP). Triggers on /sdlc:web-ui-verify.
---

# web-ui-verify

Web-UI counterpart to `scripts/verify-deploy.sh` and the v0.19 `hardware-verify` skill. Where
hw-verify proves a deploy runs on remote hardware, this proves a web app actually *renders* — the
§2.2 anti-pattern killer ("curl 200 → endpoint OK" while the page is a go:embed/JS-error blank).

## What it does

```
web-ui-verify.yaml (contract) + optional Playwright MCP ──► verify.sh [--repo D] [--url U] [--dry-run]
  0. parse web-ui-verify.yaml — absent/trivial ⇒ exit 7 (fail-closed)
  1. detect-web-stack → react|vue|svelte|next|angular|vanilla|not-a-web-app(exit 2)
  2. probe MCP: `timeout claude mcp list`; absent/timeout/CLI-absent ⇒ UI-UNVERIFIED (never PASS)
  3. §6.4 lint: Chrome-only / no-Bash-interleave / screenshot-dir legal (exit 6)
  4. verdict: PASS | FAIL | UI-UNVERIFIED   (keystone 7-part, deterministic source-of-truth)
```

## Convention — `<repo>/web-ui-verify.yaml` (lives in the TARGET repo)

Per route: a POSITIVE success assertion (selector + success-state text) AND ≥1 NEGATIVE
placeholder/error marker that must be ABSENT, plus a `build_id` freshness signal. Absent OR
trivial (generic selector, OR empty text, OR zero negatives, OR no build_id) ⇒ verify cannot prove
PASS (exit 7 / UI-UNVERIFIED). **The `positive.text` must be route-distinctive — use ≥ a word keyed
to the success state, not a single common char (`.`/`>`) which matches almost any HTML (RES-UI1).**
See spec §5 for the full schema.

## Vision annotation (v0.30, optional — provider-agnostic)

The `ui-vision-judge` skill can attach a SOFT vision judgment of a rendered screenshot (via the
user's configured OpenAI-compatible provider; `SDLC_VISION_*`). When the command layer sets
`SDLC_WEBUI_VISION_ANNOTATION`, verify.sh prints it ALONGSIDE the verdict and, if vision flags a
possible issue on a PASS, adds a non-binding `note: WARN`. **Deterministic-verdict-supremacy:** the
7-part engine is the sole source of truth — the vision annotation NEVER flips PASS↔FAIL (the engine
bytes are frozen and byte-diff-regression-tested vs v0.29.0). Provider unconfigured ⇒ no annotation.

## Boundaries (honest)

- Deterministic detect/probe/lint/contract/verdict layer is bats-tested with stub `claude`/`curl`.
- The live `browser_navigate/snapshot/console/network` reads + a real-app PASS are §7.3
  PENDING-VERIFY (mock ≠ real) until run on `examples/web-hello/` served + a connected MCP.
- MCP is detected, never installed (Hard constraint #4). MCP absent ⇒ UI-UNVERIFIED, never PASS.
