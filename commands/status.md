---
description: Show current sprint state + recent handoffs + recommended next step. Dispatches task-orchestrator (opus) in read-only mode.
argument-hint: "[--project <dir>]"
allowed-tools: [Read, Bash, Agent]
---

# /sdlc:status

Invokes the **task-orchestrator** agent (opus, read-only mode). Prints sprint state machine position + last handoff + recommended next `/sdlc:<command>`.

`--project <dir>` reads the state of a target project directory instead of the cwd (Claude launched from a parent dir) — resolve `<dir>` to an absolute path, export `SDLC_PROJECT_ROOT=<dir>` for the dispatched orchestrator, and read `<dir>/.sdlc/state.json` + `<dir>/docs/superpowers/handoffs/` (see [[task-orchestrator]] "Project root"). If `SDLC_PROJECT_ROOT` is already set in the env, honor it.

## Output (stdout)

```
Sprint: 2026-05-29-<slug>
Phase:  PLAN_APPROVED
Last handoff: docs/superpowers/handoffs/2026-05-29-<slug>-plan-impl.yaml
Stack:  rust (auto-detected from Cargo.toml)
Disk:   / 18G (RED — see /sdlc:disk), /data 161G, /tmp 12G
Recommended next: /sdlc:impl docs/superpowers/plans/2026-05-29-<slug>.md
```

## In-flight background jobs (v0.12)

Surface any background jobs still running, via the [[async-dispatch]] registry:

```bash
skills/async-dispatch/jobs.sh list --status running    # id=<> status=running label=<>, or "none"
skills/async-dispatch/jobs.sh list --status orphaned   # crashed jobs a reap flagged
```

Print an `In-flight (background)` section so long async audits (threat/perf/whole-repo review)
are visible rather than silently stuck; orphaned jobs (from `jobs.sh reap`) are shown so a
crashed dispatch surfaces instead of hiding.

## No state mutation

Read-only; does not advance phase or modify files.
