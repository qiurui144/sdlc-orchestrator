---
description: Execute TDD plan task-by-task. Per-task commit. Dispatches implementer (sonnet).
argument-hint: "<plan-path> [--project <dir>]"
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent, Skill, TaskCreate, TaskUpdate]
---

# /sdlc:impl <plan-path>

Invokes the **implementer** agent (sonnet). Executes plan tasks sequentially with strict TDD (failing test first), per-task commit, and Pre-Create Gate + disk-self-audit on each step.

## Project root (`--project <dir>`)

By default all paths are relative to the cwd. `--project <dir>` operates on a target project
directory instead — for when Claude is launched from a **parent directory** holding several
projects. Resolve `<dir>` to an absolute path, export `SDLC_PROJECT_ROOT=<dir>` for the dispatched
agent + every Bash/script call, and root ALL paths there: reads the plan under
`<dir>/docs/superpowers/plans/`, runs the build/test commands from `<dir>/.sdlc/stack.yaml`
(which already `cd`s into the module subdir when needed), and **the per-task commits land in the
`<dir>` repo, not the cwd**. Evidence to `<dir>/reports/`. Same mechanism as `/sdlc:run --project`.
If `SDLC_PROJECT_ROOT` is already set, honor it. Default: cwd.

## Behavior

1. Verify plan state == PLAN_APPROVED.
2. For each plan task: read task content → Pre-Create Gate → disk audit (if Bash) → execute Steps N.1 through N.5 → write `reports/<date>_T<N>.md` → commit.
3. On scope drift (Step 4 fails 3× after retry): SCOPE_DRIFT escalate to architect (G2 reverse edge).
4. Use `model_tier` per task (per Appendix D); parallel batches gated by multi-agent-dispatch skill.
5. Emit handoff (impl → review) + commits[] + evidence_paths[] + self_score.
6. State: PLAN_APPROVED → IMPL_IN_PROGRESS → IMPL_COMPLETE.

## Next step

`/sdlc:review <branch>` for 2-round review.
