---
description: Generate TDD implementation plan from approved spec (G2 gate). Dispatches architect (opus) which invokes superpowers:writing-plans.
argument-hint: "<spec-path> [--project <dir>]"
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent, Skill]
---

# /sdlc:plan <spec-path>

Invokes the **architect** agent (opus). Architect first acts as G1 Challenger on the spec (rubric E.1), then if pass, invokes `superpowers:writing-plans` skill to produce a TDD plan at rubric E.2.

## Project root (`--project <dir>`)

By default all paths are relative to the cwd. `--project <dir>` operates on a target project
directory instead — for when Claude is launched from a **parent directory** holding several
projects. Resolve `<dir>` to an absolute path, export `SDLC_PROJECT_ROOT=<dir>` for the dispatched
agent + every Bash/script call, and root ALL paths there (reads the spec under
`<dir>/docs/superpowers/specs/`, writes the plan to `<dir>/docs/superpowers/plans/`, reads
`<dir>/.sdlc/stack.yaml` for test commands). `<spec-path>` may be given relative to `<dir>`. Same
mechanism as `/sdlc:run --project`. If `SDLC_PROJECT_ROOT` is already set, honor it. Default: cwd.

## Behavior

1. Verify spec exists + state == SPEC_APPROVED.
2. **Plan adoption check** (before regenerating): `ls docs/superpowers/plans/` and look for an existing
   plan file whose name contains the spec slug (e.g., `*<slug>*.md`). If found:
   - Print "Adopting existing plan: <path> — skipping regeneration"
   - Update `.sdlc/state.json`: set `plan_self_built` to `false`
   - Skip steps 3–5; go straight to step 6.
   This prevents re-invoking `superpowers:writing-plans` when the user already has a plan (e.g., from
   a prior session or a manually written plan). If no existing plan is found, continue to step 3.
3. Pre-Create Gate on `docs/superpowers/plans/<date>-<slug>.md` (only when generating a NEW plan).
4. Architect G1 Challenger: scores spec rubric. If < 4/5 on any criterion → reject, return to spec-analyst.
5. If G1 pass: invoke `superpowers:writing-plans` skill with spec path. Mark `.sdlc/state.json`
   `plan_self_built: true`.
6. Per-task acceptance_judges, model_tier, commit_msg required (no placeholders).
7. Emit handoff YAML (plan → impl) + self_score.
8. State: SPEC_APPROVED → PLAN_DRAFT → (user review) → PLAN_APPROVED.

## Next step

After user approves plan, invoke `/sdlc:impl <plan-path>`.
