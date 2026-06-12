---
description: Run 6-category test matrix + multi-seed N=3 (per §6.1 + §2.3). Dispatches tester (sonnet).
argument-hint: "<scope: unit|integration|e2e|all> [--project <dir>]"
allowed-tools: [Read, Glob, Grep, Bash, Agent, Skill]
---

# /sdlc:test <scope>

Invokes the **tester** agent (sonnet). Auto-detects stack via `config/detect-stack.sh`. Loads adapter yaml. Runs `test_unit / test_integration / test_all` per `<scope>` against 6-category matrix (happy/edge/error/adversarial/concurrent/resource). Multi-seed N=3 for any LLM-driven test.

## Project root (`--project <dir>`)

By default all paths are relative to the cwd. `--project <dir>` operates on a target project
directory instead — for when Claude is launched from a **parent directory** holding several
projects. Resolve `<dir>` to an absolute path, export `SDLC_PROJECT_ROOT=<dir>` for the dispatched
agent + every Bash/script call, and root ALL paths there: the tester reads `<dir>/.sdlc/stack.yaml`
and runs its `test_*` commands (which already `cd` into the module subdir when the build module is
below the root — see onboard), with evidence to `<dir>/reports/runs/`. Same mechanism as
`/sdlc:run --project`. If `SDLC_PROJECT_ROOT` is already set, honor it. Default: cwd.

## Behavior

1. Load `.sdlc/stack.yaml` (materialized in-repo by onboard from the detected stack adapter).
2. Pre-Create Gate on report paths.
3. Disk audit before resource-exhaust scenario.
4. For each category: capture raw → `reports/runs/<ts>/<category>.log` + summary in `reports/<date>_test.md`.
5. For LLM tests: 3 seeds, report mean ± std (improvement < 2σ not counted).
6. Emit handoff (test → release) with category_pass + multi_seed_runs + evidence_paths + self_score.
   **tester is read-only-ish (no Write tool)** — it may add/append tests via Bash and RETURNS the
   handoff YAML; the orchestrator (this command) persists it to
   `docs/superpowers/handoffs/<sprint>_test_pass.yaml`.
7. State: REVIEW_R2 → TEST_RUN → TEST_PASS.

## Next step

`/sdlc:release v<X.Y.Z>` after TEST_PASS.
