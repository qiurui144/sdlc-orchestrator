---
name: async-dispatch
description: Use when the orchestrator wants to dispatch long, independent audits/tasks with the harness run_in_background capability and collect their results asynchronously instead of blocking. Maintains a file-based job registry (jobs.sh) of in-flight background jobs so /sdlc:status can show them and crashed jobs can be reaped. The async dispatch/collect counterpart of the synchronous dispatch-batch; the serial merge-queue (v0.11) stays serial.
---

# async-dispatch

The async half of dispatch. v0.9 [[multi-agent-dispatch]] fans out N agents in one turn
but **blocks** until all return (a barrier). This skill lets the orchestrator dispatch a
long, independent task with `run_in_background: true`, register it in a file-based job
registry, keep working, and collect the result later — with in-flight visibility and a
crash-reap backstop.

## When to use

- A long, **independent** audit/task (threat model, perf bench, whole-repo review) would
  otherwise block the orchestrator's turn.
- NOT for the serial merge-queue (v0.11 stays serial — tagging cannot be concurrent).
- NOT a replacement for results: the background agent still writes its result to
  `reports/runs/<ts>/<id>.md` (R18); the registry only tracks STATUS.

## Contract — jobs.sh

```
jobs.sh register --id <id> --label <t>      # → .sdlc/jobs/<id>.job status=running
jobs.sh complete --id <id> [--status done|failed]
jobs.sh list [--status running|done|failed|orphaned|all]   # id=<> status=<> label=<>
jobs.sh inflight                            # integer count of running jobs
jobs.sh reap --max-age <s>                  # stale running → orphaned, prints reaped=<id>
```

`SDLC_JOBS_DIR` (default `.sdlc/jobs`), `SDLC_NOW_OVERRIDE` (test-injectable clock). id is
validated `^[A-Za-z0-9._-]+$` and `.`/`..` rejected (blocks `../`, `/`, shell metachars → exit 2).

## Dispatch/collect pattern

1. Pass the [[multi-agent-dispatch]] `budget.sh` gate (disk redline + slot) → `counter_acquire`.
2. `jobs.sh register --id <jid> --label <task>`.
3. `Agent(run_in_background: true, …)` — the agent writes its result to `reports/runs/<ts>/<jid>.md` (R18).
4. Orchestrator continues other work (no barrier).
5. On completion: `jobs.sh complete --id <jid>` → **`counter_release`** → read the result file.
6. `/sdlc:status` → `jobs.sh list --status running`.
7. Periodically `jobs.sh reap --max-age 1800` → orphan crashed jobs, and **`counter_release`
   for each `reaped=<id>`** (symmetric to step 5 — a crashed job must not leak its slot).

## Slot-release invariant (G1 correctness)

A counter slot is freed on **any** exit from running — `complete` *and* `reap`→orphaned.
jobs.sh stays orthogonal to counter.sh (it never edits the counter); it just prints the id
leaving running (`completed=<id>` / `reaped=<id>`) so the orchestrator releases exactly one
slot per exit. Releasing only on complete would leak a slot for every crashed job — which is
the exact path reap exists for.

## Degrade to synchronous

With no harness `run_in_background`, dispatch synchronously and `complete` immediately after
the agent returns — the registry still records the job (register→done), so behavior is a
strict superset of the v0.9 synchronous barrier. Nothing about the registry requires async.

## Linked

- skill [[multi-agent-dispatch]] (budget/counter gate + atomic.sh this reuses)
- agent [[task-orchestrator]] / [[intake-orchestrator]] (callers)
- command `/sdlc:status` (reads `jobs.sh list --status running`)
