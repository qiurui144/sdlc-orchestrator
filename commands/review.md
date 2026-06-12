---
description: 2-round PR review per §5.2. Dispatches pr-reviewer (sonnet).
argument-hint: "<branch> [--project <dir>]"
allowed-tools: [Read, Glob, Grep, Bash, Agent, Skill]
---

# /sdlc:review <branch>

Invokes the **pr-reviewer** agent (sonnet). Runs Round 1 (functional / edge / security / coverage / convention / perf), waits for implementer fixes, then Round 2 (verify each finding closed + cross-cutting + doc sync + commit hygiene).

## Project root (`--project <dir>`)

By default all paths are relative to the cwd. `--project <dir>` operates on a target project
directory instead — for when Claude is launched from a **parent directory** holding several
projects. Resolve `<dir>` to an absolute path, export `SDLC_PROJECT_ROOT=<dir>` for the dispatched
agent + every Bash/script call, and root ALL paths there: the diff is read with `git -C <dir>`, the
spec/plan context under `<dir>/docs/superpowers/`, and review notes to `<dir>/reports/`. Same
mechanism as `/sdlc:run --project`. If `SDLC_PROJECT_ROOT` is already set, honor it. Default: cwd.

## Behavior

1. Read base...HEAD diff for `<branch>`.
2. Round 1: 7-item checklist; emit `reports/<date>-review-r1.md` with findings categorized Critical/Important/Nit.
3. Wait for implementer fixes.
4. Round 2: line-by-line verify; check no new issues; check docs sync.
5. Optional: adversarial-review skill if branch touches auth/data/security paths.
6. Emit handoff (review → test) with findings_r1/r1_closed/r2 + self_score.
   **pr-reviewer is read-only (no Write tool) by design** — it RETURNS the handoff YAML in its
   reply; the orchestrator (this command) persists it to
   `docs/superpowers/handoffs/<sprint>_review_done.yaml`. Do not give the reviewer Write.
7. State: IMPL_COMPLETE → REVIEW_R1 → REVIEW_R2.

## Next step

`/sdlc:test all` for the 6-category test matrix.
