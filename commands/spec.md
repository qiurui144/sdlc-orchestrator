---
description: Draft an 11-section spec for a new feature (per CLAUDE.md §3.1). Dispatches spec-analyst (opus).
argument-hint: "<feature-slug> [--project <dir>]"
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent, Skill]
---

# /sdlc:spec <feature-slug>

Invokes the **spec-analyst** agent (model_tier=opus) to draft an 11-section spec at rubric E.1 ≥ 4/5.

## Project root (`--project <dir>`)

By default all paths are relative to the cwd. `--project <dir>` operates on a target project
directory instead — for when Claude is launched from a **parent directory** holding several
projects. Resolve `<dir>` to an absolute path, export `SDLC_PROJECT_ROOT=<dir>` for the dispatched
agent + every Bash/script call, and root ALL paths there (the spec lands in
`<dir>/docs/superpowers/specs/`, the Pre-Create Gate greps `<dir>`). Same mechanism as
`/sdlc:run --project` and the deterministic scripts (onboard / doctor / archive). If
`SDLC_PROJECT_ROOT` is already set in the env, honor it. Default (no flag): cwd.

## Behavior

1. Validate `<feature-slug>` matches kebab-case `[a-z0-9-]+`; reject Unicode / spaces / underscores.
2. Pre-Create Gate on `docs/superpowers/specs/<YYYY-MM-DD>-<feature-slug>.md`.
3. Dispatch `spec-analyst` agent with the slug + current chat context.
4. spec-analyst produces 11 sections (per §3.1) + Appendix C/D-style mappings.
5. Emits handoff YAML (spec → plan) including `self_score`.
6. State machine: INIT → SPEC_DRAFT.

## Preconditions

- Repo has `.git/`
- User has provided feature intent (otherwise spec-analyst refuses and asks)

## Next step

After user approves spec, invoke `/sdlc:plan <spec-path>`.
