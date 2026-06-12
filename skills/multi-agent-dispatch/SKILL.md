---
name: multi-agent-dispatch
description: Use BEFORE dispatching ≥2 subagents in parallel. Enforces CLAUDE.md §7.1.7 + spec R4 (disk-full incident from parallel agents). Computes resource budget (disk + token + concurrent shells), aborts dispatch if budget cannot be met.
---

# multi-agent-dispatch

## When to use

- `implementer` agent wants to dispatch ≥2 task subagents (per plan parallelizable_groups)
- Any orchestrator wants to run multiple Read/Edit/Bash agents concurrently
- NOT for sequential subagent chains

## Resource budget rules

| Resource | Default cap | Override env |
|----------|------------|--------------|
| max_parallel | 2 | `SDLC_MAX_PARALLEL` |
| min_root_avail_gb | 50 | `SDLC_DISK_REDLINE_ROOT_GB` |
| min_tmp_avail_gb | 5 | `SDLC_DISK_REDLINE_TMP_GB` |
| min_data_avail_gb | 50 | `SDLC_DISK_REDLINE_DATA_GB` |

## Failure mode (budget.sh)

- Exit 2 = disk redline → do not dispatch; surface cleanup advice (never relaxed, §1.1.6)
- Exit 1 = no free slot (`avail=0`) → wait and retry; never exceed the cap
- Exit 0 = `avail>0` → may dispatch up to `avail` agents this batch

## dispatch-batch protocol (v0.9)

True agent parallelism happens ONLY when the orchestrator issues N Agent calls in
ONE turn (the harness runs them concurrently). bash cannot spawn an LLM agent — so
this is an orchestrator *behavior* protocol, not a job pool. One batch:

1. Call `budget.sh` → read `avail` (= cap − in_flight); disk redline → exit 2 → abort.
2. `. counter.sh; counter_acquire <N>` (N ≤ avail) → atomically reserve N slots.
3. In ONE turn, issue N Agent tool calls (the harness runs them concurrently).
4. Each sub-agent does its work and writes ONLY its own shard
   `reports/runs/<ts>/<slot>.json` via `atomic.sh` — it NEVER touches shared state.
5. Collect the N returns → `counter_release <N>`.
6. Run a SERIAL merge (`consolidate.sh` / `panel.sh --consensus`) over the shards.
7. Write the merged result to shared state ONCE, serially, via `atomic_write`.

**shard-then-merge** is what eliminates the race: parallel sub-agents write separate
shards; only the orchestrator writes shared state, serially. The lock primitives
(`atomic.sh`/`counter.sh`) guard the multi-writer futures of v0.11/v0.12.

## Config

| Env | Default | Meaning |
|-----|---------|---------|
| `SDLC_MAX_PARALLEL` | 2 | concurrency cap (slots) |
| `SDLC_LOCK_TIMEOUT` | 5 | seconds before mkdir-lock gives up |
| `SDLC_COUNTER_FILE` | `.sdlc/counter` | in-flight counter path |

## Linked
- skill [[disk-self-audit]]
- skill [[challenger-panel]] (panel fan-out reuses this protocol)
- `atomic.sh` / `counter.sh` (concurrency primitives)
- spec §3.2 / §7.1.7 / §11 R4
