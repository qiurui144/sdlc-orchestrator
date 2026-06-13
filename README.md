# sdlc-orchestrator

> [中文文档](./README.zh.md)

![ci](https://github.com/qiurui144/sdlc-orchestrator/actions/workflows/ci.yml/badge.svg)

Stack-agnostic SDLC orchestration plugin for Claude Code: **18 agents, 28 skills, 30 slash
commands, 3 hooks**. Drives `spec → plan → impl → review → test → release` plus common
software-engineering practices (ADR, threat modeling, performance, dependencies, tech debt,
incidents, CI/CD), enforcing the project's CLAUDE.md rules by construction.

---

## What it does

AI-assisted development collapses the whole SDLC into one session, which invites predictable
anti-patterns. This plugin wires each phase to an agent that prevents them — e.g.:

- **Spec drift** — blocks implementation until an 11-section spec is approved.
- **Multi-agent disk-full** — disk-redline guard before any build/test command.
- **Agent self-reporting PASS** — handoffs require an on-disk report + `self_score`, not chat text.
- **docs/ proliferation** — a Pre-Create Gate checks every new file (duplicate? one-shot? whitelisted?).

Full rationale + design: [DEVELOP.md](./DEVELOP.md) and the ADRs in `docs/adr/`.

---

## Install

This repo is a self-contained plugin **and** marketplace.

```bash
# 1. register the repo as a marketplace (local path or git URL)
claude plugin marketplace add /path/to/sdlc-orchestrator
# 2. install + enable, then restart Claude Code to load it
claude plugin install sdlc-orchestrator@sdlc-orchestrator
```

- **Try it for one session (no install):** `claude --plugin-dir /path/to/sdlc-orchestrator`
- **Update a local install:** `claude plugin marketplace update sdlc-orchestrator && claude plugin update sdlc-orchestrator@sdlc-orchestrator` — then restart (component reload needs a fresh session).
- **Verify:** `claude plugin validate /path/to/sdlc-orchestrator` and `claude plugin details sdlc-orchestrator`.

---

## Usage

**1. Adopt a repo (once per project):**

```
/sdlc:onboard    # detect stack, scaffold docs/superpowers/ + .sdlc/, materialize templates + stack adapter (idempotent)
/sdlc:doctor     # health-check the wiring → READY or a list of fixes
```

**2. Run a feature through the full chain (explicit, reviewable at each step):**

```
/sdlc:spec <slug>  →  /sdlc:plan  →  /sdlc:impl  →  /sdlc:review  →  /sdlc:test  →  /sdlc:release
```

Or let `/sdlc:run` drive the whole chain with human-gate pauses after each Challenger gate (G1–G4) and a GA hard-stop before the final tag:

```
/sdlc:run <slug>   # half-managed: pauses at G1/G2/G3/G4 and before GA tag
```

**3. One-shot tools (any time, no chain):**
`/sdlc:cost --sprint` · `/sdlc:status` · `/sdlc:adr` · `/sdlc:threat` · `/sdlc:deps` · `/sdlc:debt`
· `/sdlc:perf` · `/sdlc:incident` · `/sdlc:cicd` · `/sdlc:migrate` · `/sdlc:audit-docs` · `/sdlc:disk` · `/sdlc:eval` · `/sdlc:intake`

**Running from a parent directory:** if you launch Claude from a directory that holds several
projects, target one with `--project <dir>`:

```
/sdlc:run <slug> --project ./my-service     # full chain on the subdir, not the cwd
/sdlc:status --project ./my-service
/sdlc:spec <slug> --project ./my-service    # the granular phase commands honor it too (v0.23.0):
/sdlc:plan … / /sdlc:impl … / /sdlc:review … / /sdlc:test … --project ./my-service
/sdlc:onboard ./my-service                  # onboard/doctor take the dir positionally
```

The orchestrator exports `SDLC_PROJECT_ROOT=<dir>` for every dispatch and puts all state/specs/plans/
reports under it (a pre-set `SDLC_PROJECT_ROOT` env var is honored too). Note: the end-of-session
archival hook runs in the cwd — to have it target `<dir>`, either `cd` into the project first or set
`SDLC_PROJECT_ROOT` in your shell env.

**Polyglot / subdir build module (v0.23.0):** `/sdlc:onboard` detects the stack even when the build
module lives in a subdir (e.g. a Go backend in `go/`, chosen by a directory-name preference) — it
records `module_dir` in `.sdlc/state.json` and materializes `.sdlc/stack.yaml` with `cd <dir> && …`
commands so `/sdlc:test` runs the real toolchain instead of the generic adapter. Root-module repos
are unchanged. Edit `.sdlc/stack.yaml` if the primary module is elsewhere.

---

## Automatic vs explicit

| Layer | Triggered | What runs |
|-------|-----------|-----------|
| **Hooks** | 🟢 automatic, no action needed | `PreToolUse:Bash` disk-redline guard before build/test · `PreToolUse:Bash` **GA-tag guard** (blocks a major `vN.0.0` GA tag in an sdlc repo unless `SDLC_GA_APPROVED=1` / `.sdlc/ga-approved` — §7.2 hard-stop) · `PostToolUse:Write` Pre-Create Gate on new files · `Stop` disk audit + sprint-archival suggestion |
| **Guard skills** | 🟡 Claude may invoke when relevant | `pre-create-gate`, `disk-self-audit`, `multi-agent-dispatch` |
| **SDLC chain** | 🔴 you run `/sdlc:*` | `spec → release` and all one-shot commands |

Hooks are **global** once enabled (every session/dir). The full chain is **deliberately
manual** — it dispatches opus/sonnet sub-agents and costs real tokens, so it must never
auto-fire. Run `/sdlc:cost --sprint` first to see the estimate.

---

## Commands

| Command | Agent (tier) | Summary |
|---------|-------------|---------|
| `/sdlc:onboard` · `/sdlc:doctor` | project-onboarding | Bootstrap a repo / health-check wiring (zero-LLM, idempotent) |
| `/sdlc:cost` | cost-estimation | Zero-LLM token + USD estimate for a phase or sprint |
| `/sdlc:spec` | spec-analyst (opus) | 11-section spec; blocks impl until approved |
| `/sdlc:plan` | architect (opus) | G1 challenge + TDD plan from the approved spec |
| `/sdlc:impl` | implementer (sonnet) | Execute the plan, TDD, per-task commit |
| `/sdlc:review` | pr-reviewer (sonnet) | 2-round review (G3 gate) |
| `/sdlc:test` | tester (sonnet) | 6-category matrix + multi-seed (G4 gate) |
| `/sdlc:release` | releaser (opus) | RC 4 gates + local-deploy verify + tag |
| `/sdlc:adr` · `/sdlc:threat` · `/sdlc:migrate` | architecture-reviewer (opus) | ADR · STRIDE threat model · migration plan |
| `/sdlc:perf` | performance-analyst | SLI/SLO + bench + 2σ regression |
| `/sdlc:deps` · `/sdlc:debt` | dependency-auditor · tech-debt-tracker (haiku) | SBOM/CVE/license · TODO/FIXME registry |
| `/sdlc:incident` · `/sdlc:cicd` | incident-responder (opus) · cicd-designer | Runbook + postmortem · CI/CD + canary + rollback |
| `/sdlc:audit-docs` · `/sdlc:disk` | docs-curator · disk-monitor (haiku) | §3.2 doc audit · 3-disk audit |
| `/sdlc:status` · `/sdlc:eval` | task-orchestrator | Sprint state · behavioral conformance eval |
| `/sdlc:intake` | intake-orchestrator (opus) | One-command full inspection → project-health scorecard (light/standard/deep) |
| `/sdlc:pipeline` · `/sdlc:merge-queue` | pipeline-emit · merge-queue | Deterministic CI-yaml emitter · serial cross-feature merge + version/tag at merge (§7.1.7) |
| `/sdlc:hw-verify` | hardware-verify | SSH edge-device deploy verification (extends §7.3 本机部署 to hardware) |
| `/sdlc:web-ui-verify` | web-ui-verify | Real-browser render verify for web-UI repos (§2.2/§6.4/§7.3): detect-web-stack + MCP probe + per-route success-contract verdict (PASS/FAIL/UI-UNVERIFIED); MCP optional, real E2E PENDING-VERIFY |
| `/sdlc:ui-vision-judge` | ui-vision-judge | Provider-agnostic vision judge of a rendered screenshot (OpenAI-compat `SDLC_VISION_*` env): soft annotation, NEVER a verdict (deterministic-verdict-supremacy); degrades to `unavailable` if unconfigured; real provider call + multi-tier matrix PENDING-VERIFY |
| `/sdlc:web-ui-quality` | web-ui-quality | Web-UI quality gates on a UI-1-PASS page (a11y WCAG 2.1 AA / visual regression / responsive / Lighthouse CWV): deterministic verdicts, ui-vision-judge advisory-only; real chrome-devtools-mcp reads PENDING-VERIFY |
| `/sdlc:promote` | task-orchestrator (inline) | develop→main (#14): assert the main-bound commit's CI is green (`--require-known` → UNKNOWN blocks) + already tagged, then `--no-ff` merge |
| `/sdlc:run` | task-orchestrator (opus) | Drive the full chain with human-gate pauses (G1–G4) + GA hard-stop |

**Gates the drive auto-runs (capabilities, not separate commands):**
- **doc-audit content gate** (v0.24) — at the release gate, `doc-audit.sh --strict` checks inventory
  counts vs the filesystem, `/sdlc:` command-reference integrity, and a canonical-version anchor
  (also a CI hard-gate via `ci.yml`).
- **CI-green gate** (v0.25) — `ci-status.sh` (commit-bound `gh run` verdict) gates REVIEW (warn on
  UNKNOWN) and the release/`promote` tag (`--require-known` → UNKNOWN blocks; an unrelated branch's
  green run never reads PASS).
- **Bounded auto-remediation** (v0.25.1) — on a red CI the drive dispatches `ci-remediator`, which
  auto-fixes only 3 reversible classes (fmt / deny-license-allow / doc-sync), each authorized by a
  zero-LLM `diff-guard` against the real staged diff (any test/CI-yaml/assertion-weakening → revert
  + escalate); tests, logic, and security-advisory failures always escalate to a human.

Stacks auto-detected: Rust / TypeScript / Python / Go / generic (`Cargo.toml`, `package.json`,
`pyproject.toml`·`requirements.txt`, `go.mod`). A build module in a subdir (e.g. a Go backend in
`go/`) is detected too (v0.23). Agents use the adapter's commands, never hardcoded literals.

---

## Configuration (optional)

`/sdlc:onboard` seeds both, in the target repo:

- **`.claude/sdlc-orchestrator.local.md`** (YAML frontmatter) — model-tier overrides, `token_budget`, `multi_agent_max_parallel`.
- **`.sdlc/disk.conf`** (`KEY=VALUE`) — the **only** surface the disk-guard reads. Keys: `redline_root_gb` / `redline_data_gb` / `redline_tmp_gb`. Precedence: env var > project `.sdlc/disk.conf` > `~/.config/sdlc-orchestrator/disk.conf` > built-in `50/50/5`.

---

## Status

Per-version counts (agents / skills / commands / hooks / adapters) live in
[RELEASE.md](./RELEASE.md) — the single source of truth for version history.
The current build is summarized at the top of this README.

- [RELEASE.md](./RELEASE.md) — version history
- [DEVELOP.md](./DEVELOP.md) — architecture, agent/skill/hook internals, contributor guide
- [docs/adr/](./docs/adr/) — Architecture Decision Records (design rationale)
