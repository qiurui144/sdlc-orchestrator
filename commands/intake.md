---
description: One-command full project inspection — fan out audits (deps/debt/docs/disk/review/threat/perf) + whole-codebase review, consolidate into a single project-health scorecard. Dispatches intake-orchestrator (opus). Read-only by default; cost-gate before the paid phase.
argument-hint: "[--depth light|standard|deep] [--apply] [--yes] [--only deps,debt,...]"
allowed-tools: [Read, Bash, Glob, Grep, Agent, Skill]
---

# /sdlc:intake

Invokes the **intake-orchestrator** agent (opus). Adopts the repo if needed
(`onboard` + `doctor`), then runs the audit dimensions for the chosen `--depth` and writes
`reports/<date>-project-health.md` (scorecard + overall verdict + P0/P1/P2 fix list).

## Depth
- `light` — deps/debt/docs/disk only (haiku/read-only, ~free, no cost-gate).
- `standard` (default) — + whole-codebase review (two-pass) + threat (top trust-boundaries) + perf baseline.
- `deep` — + full STRIDE across components + perf across all targets + line-level review of all qualifying hotspots.

## Flags
- `--apply` — forwarded to docs-curator only; code defects are never auto-fixed.
- `--yes` — skip the cost-gate pause before the paid phase (trusted/CI).
- `--only <csv>` — restrict to listed dimensions (e.g. `deps,review`).

## Cost
The free phase runs immediately. Before the paid (sonnet/opus) phase the orchestrator prints
a `/sdlc:cost` estimate and pauses for confirmation (unless `--yes`). Per CLAUDE.md §1.3.

## Output
`reports/<date>-project-health.md`. Exit 0 even when the project is unhealthy (verdict is
advisory); operational aborts (not-a-git-repo, disk-redline) exit non-zero.

## Next
Fix P0/P1 items, or start a sprint with `/sdlc:spec <slug>`.
