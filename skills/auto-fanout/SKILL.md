---
name: auto-fanout
description: Use when the orchestrator reaches a point with multiple independent units to run in parallel (a Challenger-panel gate, the intake audit set, or an impl wave). fanout.sh enumerates the units (panel delegates to challenger-panel; intake = the 7 audit dims; waves = v0.10 implementer); the orchestrator then fires ALL of them in ONE budget-gated dispatch-batch turn instead of dispatching one-by-one. Conservative scope — only already-enumerable units (no auto dependency-analysis).
---

# auto-fanout

Turns "the driver hand-writes N `Agent` calls one at a time" into "enumerate → fire all at once,
budget-gated". The enumeration is a single SSOT; the firing is a codified one-turn batch.

## Contract — fanout.sh

```
fanout.sh groups                          # available groups: panel, intake (waves: implementer v0.10)
fanout.sh intake [--free-only]            # 7 audit dims (deps debt docs disk review threat perf); free = first 4
fanout.sh panel --artifact A --handoff H  # delegates to challenger-panel/panel.sh; prints first <size> lenses
fanout.sh panel --size N                  # direct: first N of correctness,security,scope,rubric,performance
```

One unit per line. `--size 0` → empty (no units). bad group / missing panel args / non-numeric size → exit 2.

## The auto-batch rule (orchestrator MUST follow)

1. Get the unit list: `fanout.sh <group> …`.
2. **Gate FIRST**: `skills/multi-agent-dispatch/budget.sh` — disk redline = hard abort (§1.1.6);
   `counter_acquire min(units, avail)`. Never bypass.
3. **Fire ALL units in ONE turn** (dispatch-batch — multiple `Agent` calls in a single response),
   NOT one-by-one.
4. List > avail slots → split into cap-sized waves (v0.9 behavior). Collect → `counter_release` →
   the existing next step (panel→consensus / intake→consolidate / impl→merge).

## Reuse, not rebuild

- **panel** → delegates to [[challenger-panel]] `panel.sh --dispatch` (size + high-risk + lenses);
  fanout only slices the first `size`.
- **waves** → [[multi-agent-dispatch]] + the v0.10 implementer topological layering; fanout does
  NOT re-implement topo.
- **gate** → [[multi-agent-dispatch]] `budget.sh`/`counter`; fanout never bypasses it.

## Conservative boundary

Only **already-enumerable** units. NO auto dependency-analysis, NO cross-feature/phase
auto-scheduling (deferred to a future aggressive version). 1 unit → degrades to a single dispatch.

## Linked

- skill [[challenger-panel]] / [[multi-agent-dispatch]]
- agent [[task-orchestrator]] / [[intake-orchestrator]]
