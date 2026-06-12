---
description: Health-check the current repo's sdlc-orchestrator wiring — manifest loadable, tools present, stack detected, scaffold + state valid. Reports READY or lists issues with fixes.
argument-hint: ""
allowed-tools: [Read, Bash, Skill]
---

# /sdlc:doctor

Runs the deterministic `project-onboarding` doctor health-check.

## Behavior
1. Run `${CLAUDE_PLUGIN_ROOT}/skills/project-onboarding/doctor.sh` in the repo root.
2. Per-item PASS/WARN/FAIL: manifest loadable / tools (git=FAIL, yq·jq·bats=WARN) /
   git repo / stack detected / scaffold dirs / `.sdlc/state.json` valid + known phase /
   gitignore.
3. Prints `READY` (exit 0) or lists the FAIL items with fix suggestions (exit 1).

## When to use
- Right after `/sdlc:onboard` to confirm wiring.
- Anytime a `/sdlc:*` command behaves unexpectedly — doctor localizes the misconfiguration.
