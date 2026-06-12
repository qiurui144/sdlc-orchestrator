---
description: Define SLI/SLO + run baseline benchmark + detect regression (2-sigma). Dispatches performance-analyst (sonnet).
argument-hint: <target>
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent, Skill]
---

# /sdlc:perf <target>

Invokes **performance-analyst** (sonnet). Stack-aware bench tool selection. Multi-seed N=3. SLO-driven verdict. Per spec G.2.2.

## Behavior

1. Detect stack -> pick bench tool (criterion / locust / k6 / wrk / hyperfine)
2. Load baseline from `.sdlc/perf-baseline.yaml` if exists; else create
3. Run N=3 seeds
4. Compute mean +/- std
5. Compare to baseline; `current > baseline + 2sigma` -> FAIL (regression)
6. Output `reports/<date>_perf.md` + updated baseline YAML + SLO YAML

## Preconditions

- target is a valid benchmark name or service endpoint
- Build artifacts exist (or performance-analyst builds them)

## Next step

PASS -> baseline updated, unblock `/sdlc:release`.
FAIL -> regression filed; implementer fixes before re-run.
