# DEVELOP.md — sdlc-orchestrator contributor guide

## 0. Table of contents

- [1. Architecture](#1-architecture)
- [1.5. SE practice coverage](#15-se-practice-coverage)
- [1.6. Project onboarding (how adoption works)](#16-project-onboarding-how-adoption-works)
- [2. Component matrix (1:1 with global CLAUDE.md rules)](#2-component-matrix-11-with-global-claudemd-rules)
- [Design principle: zero-LLM-first (runtime cost)](#design-principle-zero-llm-first-runtime-cost)
- [3. Model tiering policy](#3-model-tiering-policy)
- [4. Adding a new agent](#4-adding-a-new-agent)
- [5. Adding a new skill](#5-adding-a-new-skill)
- [6. Adding a new slash command](#6-adding-a-new-slash-command)
- [6.5. Adding an eval fixture (behavioral conformance)](#65-adding-an-eval-fixture-behavioral-conformance)
- [7. Adding a new stack adapter](#7-adding-a-new-stack-adapter)
- [8. Handoff schema bump (breaking)](#8-handoff-schema-bump-breaking)
- [9. Testing](#9-testing)
- [10. Coding conventions](#10-coding-conventions)
- [11. CI (planned for v0.2)](#11-ci-planned-for-v02)
- [12. License](#12-license)

---

## 1. Architecture

Architecture rationale is captured in the ADRs under `docs/adr/`.

The plugin is a **3-layer stack**:

```
┌──────────────────────────────────────────────┐
│  Layer 3 — Orchestration surface             │
│  30 slash commands + 3 hooks                 │
│  (commands/*.md, hooks/hooks.json)            │
├──────────────────────────────────────────────┤
│  Layer 2 — Agent + Skill engine              │
│  18 agents (markdown prompts)                │
│  27 skills (bash scripts + prompts)          │
│  (agents/*.md, skills/*)                     │
├──────────────────────────────────────────────┤
│  Layer 1 — Config + adapters                 │
│  Stack detection + per-stack commands        │
│  Handoff schema + templates                  │
│  (config/*.yaml, templates/*.yaml)           │
└──────────────────────────────────────────────┘
```

Data flows via **handoff YAML files** written to `docs/superpowers/handoffs/`.
No runtime database; no network services. Everything is file-based.

The `eval/` directory holds the behavioral eval harness: `eval/grade.sh` is pure
(no LLM calls) and CI-tested; `eval/run-eval.sh` is human-triggered and dispatches
real LLM agent runs against fixtures in `eval/fixtures/`.

---

## 1.5. SE practice coverage

Beyond the core SDLC loop, v0.1 ships six SE-practice agents and three SE skills,
covering 15 of 20 common SE areas per spec Appendix G:

- **v0.1 built-in (15 areas)** — ADR, threat modeling (STRIDE), migration patterns,
  performance (SLI/SLO + regression), dependencies (SBOM/CVE/license), tech debt,
  incident response, CI/CD (canary/blue-green + rollback), and the core SDLC nine.
- **v0.2 planned (3 areas)** — accessibility (a11y), data engineering pipelines,
  internationalization (i18n).
- **v0.3 planned (2 areas)** — disaster recovery (DR) drills, regulatory compliance
  (HIPAA / SOC 2 / GDPR templates).

Each SE agent maps 1:1 to a spec Appendix G.2.x section; each SE skill maps to
Appendix G.3.x. Roadmap and rationale see spec Appendix G.1.

---

## 1.6. Project onboarding (how adoption works)

`skills/project-onboarding/onboard.sh [<repo>]` is a deterministic, idempotent
scaffolder (zero-LLM): detect stack → create `docs/superpowers/{specs,plans,handoffs}/`
+ `reports/` → seed `.sdlc/state.json` (phase=INIT) → dedup-append gitignore → write
`.claude/sdlc-orchestrator.local.md`. It never overwrites existing files or touches
`CLAUDE.md`. `doctor.sh [<repo>]` health-checks the wiring (PASS/WARN/FAIL per item).
Both are CI-tested (`test_onboard.bats`, `test_doctor.bats`) like `grade.sh`.

The pair is exposed as `/sdlc:onboard` and `/sdlc:doctor` slash commands, both invoking
the `project-onboarding` skill directly (not a phase/SE agent). Both scripts accept an
optional `<repo-root>` argument defaulting to `$PWD`, making them testable against
isolated temp repos without touching the live working tree.

---

## 1.7 Parallelism + Challenger Panel (v0.9)

Agent parallelism is realized by the orchestrator issuing N Agent calls in ONE turn
(the harness runs them concurrently) — bash cannot spawn an LLM agent, so the plugin
provides a *behavior protocol* + safety primitives, not a job pool:

- **Concurrency primitives** (`skills/multi-agent-dispatch/`): `atomic.sh` (mkdir-based
  portable lock — no flock, macOS-safe — + temp+rename atomic write/rmw), `counter.sh`
  (cross-turn in-flight slot counter), `budget.sh` (real gate: `avail = cap − in_flight`,
  disk redline = hard abort).
- **dispatch-batch protocol** (SKILL.md): budget → `counter_acquire` → N Agent calls in
  one turn → each writes its OWN shard → `counter_release` → serial merge → atomic write
  to shared state. **shard-then-merge** is what eliminates the race.
- **Challenger Panel** (`skills/challenger-panel/`): one parallel primitive, two uses —
  audit fan-out (N different agents) and gate panel (N lenses on one artifact). `panel.sh`
  reuses `eval/judge.sh parse_verdict`; consensus-auto auto-advances on high-confidence
  agreement, escalating only on disagreement / the four high-risk classes / non-convergence.
  GA is always a hard stop.

Tests: `test_atomic.bats` (20-process race), `test_counter.bats`, `test_panel.bats`.
See `docs/adr/` for the design rationale.

**v0.10 parallel impl (impl DAG):** `implementer` layers the plan's `parallelizable_with`
tasks into waves, dispatches each via `Agent isolation:'worktree'`, then merges the branches
serially with `skills/worktree-merge/merge.sh` (conflict → abort + escalate to architect,
never auto-resolve). branch = shard, git merge = serial merge — the same shard-then-merge
pattern at the git layer.

---

## 2. Component matrix (1:1 with global CLAUDE.md rules)

Each component enforces one or more rules from `~/.claude/CLAUDE.md`. This table
is the authoritative mapping; keep it in sync whenever you add/modify a component.

| Component | Type | Global rule(s) enforced |
|-----------|------|------------------------|
| `spec-analyst.md` | agent | §3.1 — 11-section spec before code |
| `architect.md` | agent | §3.1 — G1 Challenger; spec ↔ plan alignment |
| `implementer.md` | agent | §5.3 — code change forced flow; §6.1 — TDD cycle; §4.1 — comments |
| `pr-reviewer.md` | agent | §5.2 — 2-round review SOP |
| `tester.md` | agent | §6.1 — 6-category test matrix; §2.3.7 — multi-seed |
| `releaser.md` | agent | §7.2 — RC 4 gates; §7.3 — 本机部署 verify |
| `docs-curator.md` | agent | §3.2 — doc whitelist; §1.1.2 — product docs |
| `disk-monitor.md` | agent | §1.1.6 — disk self-audit; cargo clean |
| `task-orchestrator.md` | agent | §6.2 — agent 落档强制; model_tier routing |
| `architecture-reviewer.md` | agent | Appendix G.2.1 — ADR + threat (SE1/SE2) + migration (SE9/SE12) |
| `performance-analyst.md` | agent | Appendix G.2.2 — SLI/SLO (SE3) + anti-anecdotal (SE11) |
| `dependency-auditor.md` | agent | Appendix G.2.3 — SBOM + vuln (SE5) + license (SE6) |
| `tech-debt-tracker.md` | agent | Appendix G.2.4 — debt registry + budget (SE4) |
| `incident-responder.md` | agent | Appendix G.2.5 — CLAUDE.md §9 + postmortem (SE8) |
| `cicd-designer.md` | agent | Appendix G.2.6 — CI/CD + canary (SE7) |
| `ci-remediator.md` | agent | §4.2.4 #13 — bounded CI auto-remediation (3 reversible classes; LLM proposes, diff-guard authorizes) |
| `pre-create-gate` | skill | §1.1.7 — Pre-Create Gate 3 questions |
| `sprint-archival` | skill | §3.2 — plan lifecycle (delete on complete) |
| `handoff-schema` | skill | §3.1 §5.3 — phase transition validation |
| `multi-agent-dispatch` | skill | §6.2 — Write .md mandate; disk pre-check |
| `disk-self-audit` | skill | §1.1.6 — /data, /, /tmp three-disk check |
| `threat-model-stride` | skill | Appendix G.3.1 — STRIDE 6-letter enumeration |
| `observability-baseline` | skill | Appendix G.3.2 — RED/USE + logs/traces/alerts |
| `migration-strategy` | skill | Appendix G.3.3 — 5-pattern + reversibility |
| `ci-status` (`ci-status.sh` + `diff-guard.sh`) | skill | §4.2.4 #13/#14 — commit-bound CI-green verdict + zero-LLM diff-guard safety core (whitespace-only A1 + broad test detection) |
| `secret-scan` | skill | §1.4 §9.1 — secret detection (SE13); paired with the `secret-guard` commit/push hook |
| `risk-classify` (`risk-classify.sh` + `config/risk-rules.yaml`) | skill | accurate-fast B (v0.28.0) — deterministic zero-LLM change-risk tier (LOW/NORMAL/HIGH) → path depth + panel size + model tier; default-deny, LOW = prose-doc basename allowlist ONLY (behavior-bearing markdown → NORMAL); 21-fixture evasion suite (BLOCKING) + adversarial-reviewer G3 |
| `web-ui-verify` (`verify.sh` + `config/detect-web-stack.sh` + `config/stack-web.yaml`) | skill | web-ui UI-1 (v0.29.0) — §2.2/§6.4/§7.3 real-browser render verify: detect frontend stack + optional Playwright-MCP probe (degrade → UI-UNVERIFIED) + §6.4 lint + per-route success-contract verdict (PASS/FAIL/UI-UNVERIFIED, blank→FAIL); fail-closed exit 7; mechanical `ui_verified` handoff. Deterministic layer bats-tested (18-case evasion suite BLOCKING + adversarial G3); real-browser E2E PENDING-VERIFY (`/sdlc:web-ui-verify`) |
| `scripts/doc-audit.sh` content gate | script | §1.1.4 §3.2 — inventory-count vs FS + `/sdlc:` command-ref + canonical-version anchor (CI hard-gate via `ci.yml`) |
| `/sdlc:promote` | command | §4.2.4 #14 — develop→main: CI-green `--require-known` + tagged, `--no-ff` |
| `PostToolUse:Write` hook | hook | §1.1.7 — Pre-Create Gate on every write |
| `Stop` hook | hook | §3.2 — plan archival; §1.1.6 — disk audit |
| `PreToolUse:Bash` hook | hook | §1.1.6 — disk abort before build |
| `stack-rust.yaml` | config | §4.3 — no hardcoded build commands in agents |
| `stack-ts.yaml` | config | §4.3 — same |
| `stack-python.yaml` | config | §4.3 — same |
| `stack-go.yaml` | config | §4.3 — same |
| `stack-generic.yaml` | config | §4.3 — same |

---

## Design principle: zero-LLM-first (runtime cost)

The cost that matters is per-invocation **user** cost. The strongest lever is to do
deterministic work in bash (zero user tokens), reaching for an LLM agent only when the
task needs judgment. Proven: onboarding (`onboard.sh`/`doctor.sh`), grading (`grade.sh`),
disk/pre-create/handoff/archival skills, and cost estimation (`cost.sh`) are all zero-LLM.
When adding a component, ask: can this be deterministic bash? If yes, it must be.
Where an LLM is genuinely needed, assign the cheapest `model_tier` that passes its eval
(see `reports/*-tier-matrix.md`); judgment-critical agents change tier only with sign-off.

---

## 3. Model tiering policy

Model tiers follow **Appendix D** of the plugin spec. The rules are:

| Tier | Models | Use for |
|------|--------|---------|
| `opus` | claude-opus-4 and above | Design phases (spec, plan, release); tasks requiring full architectural reasoning; RC gate decisions |
| `sonnet` | claude-sonnet-4-5 and above | Implementation, review, testing; tasks with clear rubric but complex output |
| `haiku` | claude-haiku-3-5 and above | Lightweight audits (disk, docs whitelist); yes/no gate decisions; format validators |

**How to set frontmatter:**

Every agent markdown must have a frontmatter block:

```yaml
---
model_tier: opus   # or sonnet or haiku
---
```

**How task-orchestrator enforces it:**

`task-orchestrator.md` reads each agent's frontmatter `model_tier` before
dispatching a sub-call and maps it to the concrete model name via
`config/model-tier.yaml` (created in T15/v2 retro). If no `model_tier` key is
present, the agent fails to load with an error (no silent default).

**Downgrade policy:**

A user may override tiers in `.claude/sdlc-orchestrator.local.md`:

```markdown
spec_analyst_tier: sonnet
```

This is allowed but triggers a RELEASE.md Known Limitations entry if pushed to
production: "spec-analyst running on sonnet tier — rubric E.1 pass rate may
degrade for complex features."

---

## 4. Adding a new agent

1. **Create `agents/<name>.md`** — must contain frontmatter `model_tier`, a `##
   Purpose` section, a `## Handoff output` section with the YAML schema, and a
   `## Rubric` section referencing Appendix E (or adding a new appendix entry).
   Minimum 250 lines to satisfy rubric E.2 ≥ 4/5.

2. **Add component row** to the matrix in §2 of this file.

3. **Write unit test** in `tests/unit/test-<name>.bats` — at minimum one happy
   path and one error case.

4. **If the agent writes files**, wire `pre-create-gate` into its handoff by
   listing expected file paths; the PostToolUse:Write hook will validate them
   automatically.

5. **Add `model_tier` to frontmatter** — no exceptions (per §3 above).

6. **Commit** as `feat(agents): <name> — model_tier=<tier>, <§ rule(s)> enforce`.

---

## 5. Adding a new skill

1. **Create `skills/<name>/`** — include a `SKILL.md` (entrypoint description)
   and one or more `.sh` scripts (POSIX bash).

2. **Register** the skill name in `plugin.json` under `"skills"` array (if
   applicable to your version of the plugin manifest).

3. **Add a trigger row** to the Skill triggers table in `README.md`.

4. **Write a unit test** in `tests/unit/test-skill-<name>.bats`.

---

## 6. Adding a new slash command

1. **Create `commands/<slug>.md`** — format mirrors existing commands (frontmatter
   with `name`, `description`, `usage`; body is the agent prompt fragment).

2. **Add a row** to the slash-command documentation in `README.md` if it exposes
   new user-facing functionality.

3. **Add bats smoke test** in `tests/integration/`.

---

## 6.5. Adding an eval fixture (behavioral conformance)

1. Create `eval/fixtures/<agent>/<case>.input.md` — the real task fed to the agent.
2. Create `eval/fixtures/<agent>/<case>.expect.yaml` — the agent's hard rules as
   mechanical assertions (kinds: `all_present` / `any_present` / `count_at_least`;
   see spec §3.4). Keep assertions anchored to reduce grep false-positives.
3. `bats tests/unit/test_eval_fixtures.bats` — confirms the fixture is well-formed.
4. `eval/run-eval.sh <agent> --dry-run` — confirms dispatch plan + tier resolution.
5. Human-triggered real run: `/sdlc:eval <agent>` or `eval/run-eval.sh <agent>`.
   The grader (`eval/grade.sh`) is independent — it never reads the agent's self-score.

### grep vs llm_judge (when to use which)

Assert **structure** with grep (`all_present` / `any_present` / `count_at_least` in
`grade.sh` — pure, deterministic, runs in CI). Assert narrative **quality** with
`kind: llm_judge` (`eval/judge.sh` — a real LLM judge, N=3 majority, human-triggered,
NEVER in CI) — for the dimension grep can't reach (e.g. "does the 5-Why descend to a
process root?", "are the ADR Consequences real trade-offs?").

**Every `llm_judge` rubric MUST be calibrated before it is trusted.** Add a `<case>.good.out`
and a deliberately planted `<case>.bad.out`, then run
`eval/judge.sh --calibrate <expect> <good.out> <bad.out>` — the judge must PASS the good and
FAIL the bad. A judge that can't distinguish them is unusable; rewrite the rubric (sharper,
demand a quoted line). The judge is a **signal, not a proof**, and is eval-time cost only —
zero impact on a user's per-invocation cost.

---

## 6.6. Updating a locally-installed copy (local-path marketplace)

When the plugin is installed from a local-path marketplace (`claude plugin marketplace add
<repo>`), the bare `claude plugin update <name>` fails with "not found" — it needs the
fully-qualified `<name>@<marketplace>` form, and the marketplace must be re-read first:

```sh
claude plugin marketplace update sdlc-orchestrator        # re-read the local source
claude plugin update sdlc-orchestrator@sdlc-orchestrator  # bump the installed version
# then RESTART Claude Code — component reload requires a fresh session
```

The cache lives at `~/.claude/plugins/cache/<mp>/<name>/<version>/`. Hooks resolve
`${CLAUDE_PLUGIN_ROOT}` to that cached copy, so an un-restarted session keeps running the
old version. For same-session iteration on a hook/script, edit the cached file directly
(it's read fresh each invocation) and then do a proper release + update to resync.

### Disk redline config (per-machine)

The disk-guard hook hard-blocks builds below the `/` redline. On a box with a small `/` and a
dedicated work disk, calibrate via a config file (env doesn't reach the hook subprocess):
`~/.config/sdlc-orchestrator/disk.conf` (machine) or `<repo>/.sdlc/disk.conf` (project), with
`redline_root_gb=20` etc. Precedence: env > project > machine > built-in 50/50/5.

---

## 7. Adding a new stack adapter

1. **Create `config/stack-<name>.yaml`** — must include `build`, `test`, `lint`,
   `clean` keys. Mirror the structure of `config/stack-rust.yaml`.

2. **Update `config/detect-stack.sh`** — add a clause for the new stack's
   sentinel file inside the `lang_of()` helper (e.g., `pubspec.yaml` for
   Flutter). Adding it there covers BOTH root-module and subdir-module
   detection (since v0.23.0 the script descends one level when the root has no
   marker, picking the primary module by directory-name preference).

---

## 8. Handoff schema bump (breaking)

Handoff YAML files are the cross-agent contract. A bump is breaking if:
- A required field is removed or renamed.
- The `phase` enum gains a new mandatory value.

**Migration policy:**

1. Bump `handoff_schema_version` in `templates/handoff.yaml`.
2. Update `skills/handoff-schema/` validator to accept both old and new version.
3. Add a migration note to `RELEASE.md` under the new version's Breaking section.
4. Deprecation window: old schema supported for one minor version, then removed.

---

## 9. Testing

```bash
cd ~/.claude/plugins/sdlc-orchestrator
./tests/run-all.sh
```

`run-all.sh` runs:
1. `bats tests/unit/` — unit tests for individual agents/skills/commands.
2. `bats tests/integration/` — integration tests (requires bats ≥ 1.7).

**bats overview:**

Each `.bats` file is a bash test file. Each `@test` block is a named test case.
Assertions use `run <command>` + `assert_output` / `assert_success` / `assert_failure`
from the `bats-support` and `bats-assert` libraries (vendored in `tests/fixtures/`).

**Fixture layout:**

```
tests/
  fixtures/          ← bats helper libs + sample handoff YAMLs
  unit/              ← one file per agent/skill/command
  integration/       ← end-to-end command tests
  run-all.sh         ← entry point
```

---

## 10. Coding conventions

| Item | Convention |
|------|-----------|
| Shell | POSIX bash (no bashisms beyond arrays); test with `shellcheck` |
| Indentation | 2 spaces for YAML; 4 spaces for bash |
| YAML | kebab-case keys; quoted strings when value contains `:` or `#` |
| Filenames | kebab-case; no version suffixes; no spaces |
| Commit messages | `<type>(<scope>): <summary>` — type: feat/fix/docs/chore/test/refactor |
| Agents | Every agent `.md`: frontmatter `model_tier`, sections Purpose/Instructions/Handoff/Rubric |
| Handoff files | Written to `docs/superpowers/handoffs/<date>T<time>-<phase>-<slug>.yaml` |
| Plan files | Written to `docs/superpowers/plans/<date>-<slug>.md`; **deleted** by sprint-archival on completion |
| Spec files | Written to `docs/superpowers/specs/<date>-<slug>.md`; permanent |

---

## 11. CI (planned for v0.2)

The following CI matrix is planned once the plugin reaches v0.2:

| Job | Trigger | Steps |
|-----|---------|-------|
| `unit-tests` | push / PR | `bats tests/unit/` on ubuntu-latest |
| `integration-tests` | push to main | `bats tests/integration/` with Claude Code installed |
| `shellcheck` | push / PR | `shellcheck hooks/*.sh skills/**/*.sh config/*.sh` |
| `yaml-lint` | push / PR | `yamllint config/*.yaml templates/*.yaml` |
| `doc-audit` | push to main | check root `.md` count ≤ 8; check no `*-report.md` |

---

## 12. License

MIT. See [LICENSE](./LICENSE).
