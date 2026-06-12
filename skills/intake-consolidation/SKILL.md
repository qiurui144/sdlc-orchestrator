---
name: intake-consolidation
description: Use during /sdlc:intake to plan which audit dimensions run (plan.sh), normalize each sub-agent result into a header-tagged report (emit-subreport.sh), and merge them into a single project-health scorecard (consolidate.sh). Deterministic, zero-LLM, bash-3.2-safe.
---

# intake-consolidation

Deterministic spine of `/sdlc:intake`: 3 bash scripts, zero-LLM, bats-tested.

## Machine-readable sub-report header (the contract)

Every sub-report must begin with exactly this line on line 1:

```
<!-- sdlc-intake: dim=<dim> verdict=<PASS|WARN|FAIL|BLOCK|INCONCLUSIVE> score=<0.0-1.0|N/A> top="<one-line>" -->
```

`consolidate.sh` parses **only** this line; the rest of the file is human prose.
`emit-subreport.sh` sanitizes `"` → `'` in `top` before writing the header.
`consolidate.sh` sanitizes `|` → `/` in `top` when building the scorecard table.

## Scripts

### `plan.sh --depth <light|standard|deep> [--only <csv>]`

Outputs an ordered, tab-separated plan of dimensions to run:

```
dim<TAB>tier<TAB>paid<TAB>scope
```

Exit 0 on success; exit 2 on bad input (unknown depth, unknown dimension, dimension requires deeper depth, unknown arg).

**Registry** (in output order):

| dim | tier | paid | available from |
|-----|------|------|----------------|
| deps | haiku | free | light+ |
| debt | haiku | free | light+ |
| docs | haiku | free | light+ |
| disk | haiku | free | light+ |
| review | sonnet | paid | standard+ |
| threat | opus | paid | standard+ |
| perf | sonnet | paid | standard+ |

`scope` for paid dimensions: `sampled` at standard depth, `full` at deep. Free dimensions are always `full`.

---

### `emit-subreport.sh <out> <dim> <verdict> <score> <top> [<native-body-file>]`

Writes `<out>` with the machine-readable header on line 1, followed by a markdown body.
If `<native-body-file>` is given and exists, its content is embedded as the body; otherwise a one-line `_top issue:_ <top>` placeholder is written.

Rejects unknown verdicts with exit 2.

---

### `consolidate.sh <reports-dir> [<out>]`

Scans `<reports-dir>/*.md` for the sdlc-intake header, then writes `project-health.md` (or `<out>`) with:

- **Scorecard** — markdown table of all parsed dimensions
- **Overall verdict** — derived from parsed verdicts:
  - any `BLOCK` → `AT-RISK`
  - else any `FAIL` → `NEEDS-ATTENTION`
  - else `HEALTHY`
  - all `INCONCLUSIVE` or empty → appends ` (low-signal)` suffix
- **Prioritized fixes** — P0=BLOCK, P1=FAIL, P2=WARN
- **Per-dimension links** — relative links to each sub-report file
- **Run metadata** — loaded from `<reports-dir>/intake-meta.env` (KEY=VALUE pairs) if present; otherwise `(not recorded)`

Prints the output file path to stdout on completion.

## Linked

- `[[intake-orchestrator]]` — the agent that calls these scripts in sequence
- `[[multi-agent-dispatch]]` — budget guard invoked before fan-out
