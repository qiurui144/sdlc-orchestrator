---
description: Verify a web-UI deployment actually renders in a real browser (not just curl 200) — lands §2.2/§6.4/§7.3 for web-UI repos. detect-web-stack + MCP probe + §6.4 lint + per-route success-contract verdict (PASS/FAIL/UI-UNVERIFIED). Zero-LLM deterministic layer; real browser reads are §7.3 PENDING-VERIFY.
argument-hint: "[--url <url>] [--criteria <web-ui-verify.yaml>] [--dry-run] [--require-mcp] [--lint-only]"
allowed-tools: [Read, Bash, Skill]
---

# /sdlc:web-ui-verify

Run the **web-ui-verify** skill against the target web app and report a §7.3-style render verdict.

## Steps
1. Confirm `web-ui-verify.yaml` exists (or `--criteria <file>`). Absent ⇒ exit 7 — point the user to
   the SKILL.md Convention; do not guess a contract.
2. Recommend `--dry-run` first (prints stack + routes + MCP-probe, no browser).
3. Invoke: `bash "${CLAUDE_PLUGIN_ROOT}/skills/web-ui-verify/verify.sh" [--url U] [--dry-run] ...`
4. If MCP present, dispatch the sonnet browser-judge to drive Chrome (`channel="chrome"`) and read
   console/network; the deterministic verdict is source-of-truth, the judge only annotates.
5. Interpret exit: 0 PASS or UI-UNVERIFIED-WARN · 3 FAIL (browser-broken) · 6 §6.4 lint · 7 no contract.

## Honesty (§7.3 / PENDING-VERIFY)
The deterministic layer (detect/probe/lint/contract/verdict over stubbed reads) is shipped + bats-
tested. A real-browser PASS is real only against a real app + connected MCP — state which you ran.
MCP absent ⇒ UI-UNVERIFIED, never a false PASS.
