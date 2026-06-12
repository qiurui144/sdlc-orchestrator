---
description: Bootstrap the current repo to use sdlc-orchestrator — detect stack, scaffold docs/superpowers dirs, seed state, write config. Idempotent; never overwrites config or touches CLAUDE.md.
argument-hint: ""
allowed-tools: [Read, Write, Bash, Skill]
---

# /sdlc:onboard

Bootstraps the current repo via the deterministic `project-onboarding` skill.

## Behavior
1. Run `${CLAUDE_PLUGIN_ROOT}/skills/project-onboarding/onboard.sh` in the repo root.
2. It detects the stack, creates `docs/superpowers/{specs,plans,handoffs}/` + `reports/`,
   seeds `.sdlc/state.json` (phase=INIT), appends `.sdlc/` + `reports/runs/` to `.gitignore`,
   and writes `.claude/sdlc-orchestrator.local.md` (config stub) — all only if missing.
3. Idempotent: re-running fills only gaps; it never overwrites your config/state and never
   touches `CLAUDE.md`.
4. Prints the next step (`/sdlc:spec <feature-slug>`).

## Preconditions
- The repo must be a git repo. onboard does NOT auto-`git init` — it surfaces the error.

## Next
`/sdlc:doctor` to verify wiring, then `/sdlc:spec <slug>` to start the first sprint.
