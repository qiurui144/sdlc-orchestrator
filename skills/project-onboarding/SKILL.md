---
name: project-onboarding
description: Use when adopting sdlc-orchestrator into a repo (the /sdlc:onboard command) or checking a repo's wiring (/sdlc:doctor). Deterministic, idempotent scaffolding — detects stack, creates docs/superpowers dirs, seeds .sdlc/state.json, gitignore, config stub. Never overwrites existing config or touches CLAUDE.md.
---

# project-onboarding

## When to use
- A repo wants to adopt the plugin → `onboard.sh` scaffolds everything (one command).
- Verify a repo is correctly wired → `doctor.sh` health-check.

## What onboard does (idempotent, zero-LLM)
1. Require a git repo (does NOT auto-init — surfaces the error).
2. Detect stack via `config/detect-stack.sh`.
3. Create `docs/superpowers/{specs,plans,handoffs}/` + `reports/` (only if missing).
4. Seed `.sdlc/state.json` (phase=INIT) — only if absent (preserves progress).
5. Append `.sdlc/` + `reports/runs/` to `.gitignore` (dedup).
6. Write `.claude/sdlc-orchestrator.local.md` config stub — only if absent.
7. **Never** overwrites existing files; **never** touches `CLAUDE.md`.

## What doctor does
Per-item PASS/WARN/FAIL: manifest loadable / tools (git FAIL, yq·jq·bats WARN) /
git repo / stack detected / scaffold dirs / state.json valid / gitignore. exit 1 on any FAIL.

## Steps
1. `skills/project-onboarding/onboard.sh [<repo>]` (default cwd)
2. `skills/project-onboarding/doctor.sh [<repo>]` to verify

## Linked
- [[task-orchestrator]] (reads `.sdlc/state.json` seeded here)
- `config/detect-stack.sh`, spec §3.3/§3.4, `tests/PORTABILITY.md`
