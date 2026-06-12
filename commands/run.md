---
description: Drive the full SDLC chain (spec → plan → impl → review → test → release) via task-orchestrator in DRIVE mode. Default consensus-auto — a Challenger Panel votes at each gate (G1–G4) and auto-advances on high-confidence agreement, escalating to a human only on disagreement / the four high-risk classes / non-convergence; the GA tag is always a hard stop. Single idempotent entry — starts or resumes a sprint.
argument-hint: "[<feature-slug>] [--project <dir>] [--fast] [--full] [--interactive] [--auto] [--intake] [--from <phase>]"
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent, Skill]
---

# /sdlc:run [<feature-slug>]

Invokes the **task-orchestrator** agent (opus) in **drive mode** — the active counterpart to
`/sdlc:status` (read-only). It runs the state machine forward, dispatching each producer agent
and Challenger, persisting `docs/superpowers/handoffs/<sprint>_state.yaml` after every transition.

## Idempotent start / resume
- No active sprint → `<feature-slug>` is required; starts at INIT.
- Active sprint exists → resumes from the persisted phase; `<feature-slug>` may be omitted (if
  given and it mismatches the active sprint, the orchestrator asks: resume or start new).

## Flags
- `--interactive` — pause after EVERY Challenger gate (the pre-v0.9 behavior). Use for full control.
- `--auto` — most aggressive: skip even consensus ESCALATE pauses. **The four high-risk classes
  (secret/auth · schema/migration · irreversible/prod · STRIDE) and the GA tag hard-stop are NOT
  skippable even with `--auto`** (a release tag is irreversible, CLAUDE.md §7.2).
- `--intake` — before INIT, run `/sdlc:intake --depth light --yes` as a project pre-flight.
- `--from <phase>` — override the resume phase (one of the state-machine phases); used for rollback re-runs.
- `--project <dir>` — operate on a target project directory instead of the cwd. For when Claude is
  launched from a **parent directory** holding several projects. The orchestrator resolves `<dir>` to
  an absolute path, **exports `SDLC_PROJECT_ROOT=<dir>` for every Bash/script/agent dispatch**, and
  treats it as the root for ALL project paths (specs, plans, `docs/superpowers/handoffs/<sprint>_state.yaml`,
  reports). Default (no flag): cwd. The deterministic scripts (onboard / doctor / ga-tag-guard /
  sprint-archival) already honor `SDLC_PROJECT_ROOT`. **Caveat**: the `Stop` archival hook runs in
  the session cwd — to archive the right repo at session end, either launch Claude inside `<dir>` or
  export `SDLC_PROJECT_ROOT` in the session env (not just per-command).
- `--full` — force full rigor (override the risk classifier). Always wins (safe direction): it can
  never be demoted. Use when you want the full spec→plan→impl→review→test ceremony regardless of how
  safe the change looks.
- `--fast` — request the fast-path. **Advisory only**: the risk classifier may still escalate to full
  rigor and `--fast` can NEVER demote a NORMAL/HIGH change to LOW. A genuinely high-risk change
  (auth/migration/CI/source) always runs full rigor even with `--fast`.

By **default** (no flag, `SDLC_RISK_GATE=on`), the path depth is **classifier-driven**:
`skills/risk-classify/risk-classify.sh --staged` picks LOW (fast-path: impl+review, the deterministic
net still runs in full) / NORMAL / HIGH (full rigor). `SDLC_RISK_GATE=off` forces full rigor on every
change (exact pre-v0.28 behavior). See [[risk-classify]].

## Challenger Panel + consensus-auto (default)
At each gate (G1 spec, G2 plan, G3 test, G4 RC) a Challenger Panel of N experts (3 normally, 5 on a
high-risk class) votes on the artifact. On high-confidence agreement the orchestrator writes the
`panel_score` block and **advances without pausing** — the default `SDLC_DRIVE_MODE=consensus-auto`
that lowers human-interaction frequency. It pauses for `continue` / `stop` / `redo` ONLY when the
panel ESCALATEs (disagreement, a high-risk class, or non-convergence). `stop` saves state and exits
(re-run `/sdlc:run` to resume); `redo` re-runs the current phase. `--interactive` restores a pause
at every gate.

## Gates the drive auto-triggers (no manual `/sdlc:*` needed)
The drive doesn't only advance phases — it auto-runs the deterministic gates wired into the phase
agents, so every feature is reachable from this one entry point:
- **doc-audit content gate (v0.24)** — releaser RC Gate 1 runs `doc-audit.sh --strict` (inventory
  counts vs filesystem + `/sdlc:` command-ref integrity + canonical-version anchor). Content drift
  → Gate 1 FAIL → return upstream.
- **CI-green gate (v0.25)** — `ci-status.sh` is consulted at REVIEW (pr-reviewer, WARN on UNKNOWN —
  reversible) and RC (releaser, `--require-known` → UNKNOWN BLOCKs the irreversible tag).
- **Bounded auto-remediation (v0.25.1)** — on a ci-status **FAIL**, the orchestrator dispatches
  [[ci-remediator]] before hard-blocking: it auto-fixes only the 3 reversible classes (fmt /
  deny-license-allow / doc-sync), each authorized by the zero-LLM `diff-guard.sh` against the real
  staged diff (any test/CI-yaml/assertion-weakening → revert + ESCALATE); a security advisory or a
  test/logic failure always escalates. `--interactive` pauses before remediation; consensus-auto
  relies on the diff-guard. See task-orchestrator rule 15.
- **Not in the drive (separate command):** `/sdlc:promote` (develop→main, #14) is a deliberate
  post-release step, not part of the spec→…→release chain.

## Cost
Drive start prints a `/sdlc:cost --sprint` estimate and pauses once (CLAUDE.md §1.3 / §8). `--auto`
still prints the estimate but does not second-pause.

## Output
`docs/superpowers/handoffs/<sprint>_state.yaml` (state SSOT). Exit 0 on completion or user `stop`;
non-zero when a BLOCKED condition is escalated past budget.

## Next
`/sdlc:status` to view state read-only; re-run `/sdlc:run` to continue.
