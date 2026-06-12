# TEST_PLAN.md (SSOT per §6.1)

> This file is the single source of truth for sdlc-orchestrator test coverage.
> See [`docs/TESTING.md`](../docs/TESTING.md) for how to run tests.
> All test IDs are referenced in bats `@test` descriptions.

---

## Scope

End-to-end functional + structural validation of **sdlc-orchestrator v0.4.0**.

Covers: plugin manifest, skill scripts (including `onboard.sh` / `doctor.sh`), hook wiring,
handoff schema, stack adapters, spec/plan templates, agent frontmatter, command frontmatter,
multi-agent dispatch budget, sprint archival, and the full hello-world phase wiring (integration).

The real onboard E2E acceptance (Task 5 of the v0.4.0 plan) is zero-LLM and recorded in
`reports/2026-05-29-onboard.md` — it is not part of the automated CI suite but must be
re-run before any GA tag.

Out of scope: LLM-in-the-loop agent inference (planned v0.3), multi-user concurrency,
Windows compatibility (planned v0.2 CI matrix).

---

## Test matrix

### Unit tests (U1 – U15, in `tests/unit/`)

| ID | Scenario | Input | Expected | Layer | File |
|----|----------|-------|----------|-------|------|
| U1 | Plugin manifest has required fields | `plugin.json` | `name`, `version`, `description`, `commands`, `hooks` keys present | structural | test_plugin_manifest.bats |
| U2 | Plugin manifest version matches semver | `plugin.json` | `.version` matches `^[0-9]+\.[0-9]+\.[0-9]+` | structural | test_plugin_manifest.bats |
| U3 | Plugin manifest has ≥ 1 command | `plugin.json` | `.commands` array non-empty | structural | test_plugin_manifest.bats |
| U4 | Handoff schema — valid YAML exits 0 | `fixtures/handoff-valid.yaml` | exit 0 | happy path | test_handoff_schema.bats |
| U5 | Handoff schema — bad schema version exits 2 | `fixtures/handoff-bad-schema-version.yaml` | exit 2, stderr contains `schema-version` | error | test_handoff_schema.bats |
| U6 | Handoff schema — missing required field exits 2 | `fixtures/handoff-missing-field.yaml` | exit 2, stderr contains field name | error | test_handoff_schema.bats |
| U7 | Handoff schema — illegal phase transition exits 2 | inline YAML `spec→impl` | exit 2, stderr `phase-skip-not-allowed` | error | test_handoff_schema.bats |
| U8 | Handoff schema — all allowed transitions exit 0 | `spec:plan`, `plan:impl`, `impl:review`, `review:test`, `test:release` | exit 0 each | happy path | test_handoff_schema.bats |
| U9 | Disk audit — healthy disk exits 0 | `SDLC_DISK_FAKE_ROOT_GB=200` etc. | exit 0, stdout `disk_snapshot:` | happy path | test_disk_audit.bats |
| U10 | Disk audit — /tmp redline exits 1 (warn mode) | `SDLC_DISK_FAKE_TMP_GB=2` | exit 1, stderr `disk-redline-hit` | edge | test_disk_audit.bats |
| U11 | Disk audit — /tmp redline exits 2 (strict mode) | `SDLC_DISK_FAKE_TMP_GB=2 --strict` | exit 2 | error | test_disk_audit.bats |
| U12 | Pre-Create Gate — date-prefixed spec path exits 0 | `docs/superpowers/specs/2026-05-29-foo.md` | exit 0 | happy path | test_pre_create_gate.bats |
| U13 | Pre-Create Gate — spec without date prefix exits 2 | `docs/superpowers/specs/foo.md` | exit 2, stderr `date-prefix` | adversarial | test_pre_create_gate.bats |
| U14 | Pre-Create Gate — `.zh.md` outside README exits 2 | `docs/features/auth.zh.md` | exit 2, stderr `\.zh\.md` | adversarial | test_pre_create_gate.bats |
| U15 | Pre-Create Gate — `*-tasks.md` exits 2 | `docs/sprint-tasks.md` | exit 2, stderr `one-shot` | adversarial | test_pre_create_gate.bats |
| U16 | Pre-Create Gate — `*-report.md` exits 2 | `docs/audit-report.md` | exit 2, stderr `one-shot` | adversarial | test_pre_create_gate.bats |
| U17 | Stack adapter — Cargo.toml → rust | temp dir with `Cargo.toml` | stdout `rust` | happy path | test_stack_adapters.bats |
| U18 | Stack adapter — stack-rust.yaml has `test_unit` field | `config/stack-rust.yaml` | `.test_unit` contains `cargo test` | structural | test_stack_adapters.bats |
| U19 | Multi-agent dispatch — healthy disk exits 0 | `SDLC_DISK_FAKE_ROOT_GB=200` etc. | exit 0, stdout `max_parallel=` | happy path | test_multi_agent_dispatch.bats |
| U20 | Multi-agent dispatch — disk redline aborts (exit 2) | `SDLC_DISK_FAKE_TMP_GB=2` strict | exit 2, stderr `abort` | error | test_multi_agent_dispatch.bats |
| U21 | Sprint archival dry-run — lists actions, no delete | `--sprint X --dry-run` with plan file | exit 0, stdout `would`, plan file still present | edge | test_sprint_archival.bats |
| U22 | Sprint archival apply — removes plan, keeps spec | `--sprint X --apply` with spec+plan | exit 0, plan deleted, spec retained | happy path | test_sprint_archival.bats |
| U23 | Sprint archival — no-op when nothing to archive | `--sprint nonexistent --dry-run` | exit 0, stdout `nothing to archive` | edge | test_sprint_archival.bats |
| U24 | Agents frontmatter — all agents have Mission section | all `agents/*.md` | `## Mission` present in each | structural | test_agents_frontmatter.bats |
| U25 | Commands frontmatter — all commands have description | all `commands/*.md` | `description:` field in YAML frontmatter | structural | test_commands.bats |
| U26 | Hooks — pre-bash-build passes through non-build command | `{"tool_name":"Bash","tool_input":{"command":"ls -la"}}` | exit 0 | happy path | test_hooks.bats |
| U27 | Hooks — pre-bash-build blocks `cargo test` on disk redline | stdin JSON + `SDLC_DISK_FAKE_TMP_GB=2` | exit 2 | error | test_hooks.bats |
| U28 | Spec template — all 11 §3.1 sections present | `skills/spec-analyst/` or template | 11 `##` sections exist | structural | test_templates.bats |
| U29 | onboard.sh — happy path: scaffold created, state.json valid, doctor READY | fresh `git init` temp repo | dirs present, `.sdlc/state.json` phase=INIT, `doctor.sh` exit 0 | happy path | test_onboard.bats |
| U30 | onboard.sh — idempotency: re-run leaves git tree clean | onboarded repo re-onboarded | `git status --porcelain` empty after re-run | edge | test_onboard.bats |
| U31 | onboard.sh — non-git repo exits 1, error `onboard-not-git` | temp dir without `.git` | exit 1, stderr `onboard-not-git` | error | test_onboard.bats |
| U32 | onboard.sh — no-overwrite: existing state.json / config not touched | pre-seeded state+config | files unchanged after re-run | edge | test_onboard.bats |
| U33 | onboard.sh — never touches CLAUDE.md | repo with `CLAUDE.md` present | `CLAUDE.md` identical after onboard | adversarial | test_onboard.bats |
| U34 | doctor.sh — READY on fully onboarded repo | onboarded temp repo | exit 0, stdout `READY` | happy path | test_doctor.bats |
| U35 | doctor.sh — FAIL on un-onboarded repo (scaffold missing) | fresh git repo, no scaffold | exit 1, at least one FAIL line | error | test_doctor.bats |
| U36 | doctor.sh — FAIL on malformed state.json | `.sdlc/state.json` with invalid JSON | exit 1, stderr `doctor-state-invalid` | error | test_doctor.bats |
| U37 | doctor.sh — FAIL on unknown phase in state.json | state with `"phase":"UNKNOWN"` | exit 1, stderr `doctor-unknown-phase` | error | test_doctor.bats |
| U38 | doctor.sh — non-git repo exits 1 | temp dir without `.git` | exit 1, FAIL line for git repo check | error | test_doctor.bats |

### Eval harness tests (E1 – E5, in `tests/unit/` and `tests/integration/`)

| ID | Scenario | Input | Expected | Layer | File |
|----|----------|-------|----------|-------|------|
| E1 | grade.sh — all assertions pass | fixture with matching agent output | exit 0, stdout `PASS` | happy path | test_eval_grade.bats |
| E2 | grade.sh — `all_present` assertion fails | fixture with missing keyword | exit 1, stdout `FAIL`, missing keyword named | error | test_eval_grade.bats |
| E3 | grade.sh — `count_at_least` threshold not met | fixture output with fewer matches than threshold | exit 1, stdout reports count | edge | test_eval_grade.bats |
| E4 | Fixture validity — well-formed expect.yaml exits 0 | valid `eval/fixtures/**/*.expect.yaml` | exit 0, all fixtures parse | structural | test_eval_fixtures.bats |
| E5 | run-eval.sh dry-run — dispatch plan emitted, no LLM call | `eval/run-eval.sh <agent> --dry-run` | exit 0, stdout `dry-run`, no real model call | happy path | test_run_eval.bats |

> **Behavioral acceptance (real LLM, human-triggered):** run `/sdlc:eval <agent>` or
> `eval/run-eval.sh <agent>` for each of the 5 agents with N=3 repetitions per fixture.
> Results are recorded in `reports/<date>-eval.md` and are NOT part of the automated CI suite.

Also covered in CI (already listed above but noted here for completeness):

| File | Scope |
|------|-------|
| `test_plugin_structure.bats` | Manifest structure, agent/command counts, required fields |
| `test_portability.bats` | POSIX portability lint across all shell scripts including `eval/` |

### Integration tests (I1 – I10, in `tests/integration/`)

| ID | Scenario | Input | Expected | Phase | File |
|----|----------|-------|----------|-------|------|
| I1 | Phase 0 — disk audit snapshot emitted | real filesystem | stdout `disk_snapshot:` | 0: bootstrap | test_hello_world_e2e.bats |
| I2 | Phase 1 — Pre-Create Gate allows valid spec path | date-prefixed path in temp repo | exit 0 | 1: spec | test_hello_world_e2e.bats |
| I3 | Phase 1 — Pre-Create Gate rejects no-date spec path | non-prefixed path | exit 2 | 1: spec | test_hello_world_e2e.bats |
| I4 | Phase 2 — handoff validates spec→plan transition | inline YAML with matching SHA | exit 0 | 2: plan | test_hello_world_e2e.bats |
| I5 | Phase 2 — handoff rejects spec→impl skip | inline YAML spec→impl | exit 2, `phase-skip-not-allowed` | 2: plan | test_hello_world_e2e.bats |
| I6 | Phase 3 — multi-agent dispatch OK on healthy disk | env vars fake healthy disk | exit 0 | 3: impl | test_hello_world_e2e.bats |
| I7 | Phase 5 — stack detect → rust in hello-world | `examples/hello-world` with Cargo.toml | stdout `rust` | 5: test | test_hello_world_e2e.bats |
| I8 | Phase 5 — stack-rust.yaml `test_unit` references cargo | `config/stack-rust.yaml` yq read | value contains `cargo test` | 5: test | test_hello_world_e2e.bats |
| I9 | Phase 5 — pre-bash-build hook blocks build on disk redline | SDLC_DISK_FAKE_TMP_GB=2 | exit 2 in output | 5: test | test_hello_world_e2e.bats |
| I10 | Phase 6 — sprint archival dry-run then apply | temp repo + spec + plan | dry-run lists, apply deletes plan keeps spec | 6: release | test_hello_world_e2e.bats |

---

## Pass criteria

| Tier | Criterion |
|------|-----------|
| All U* unit tests | Exit 0 (`bats tests/unit/` all green) |
| All I* integration tests | Exit 0 (`bats tests/integration/` all green) |
| Unit coverage | ≥ 80% @test branches of each skill script |
| Agent frontmatter | 100% — every `agents/*.md` has `## Mission` |
| Command frontmatter | 100% — every `commands/*.md` has `description:` |
| Hook coverage | 100% — match path + skip path both tested |
| LLM paths (planned v0.3) | F1 ≥ 0.85 on weak tier (gpt-4o-mini class); ≤ 0.15 delta between tiers |

---

## History

| Date | Version | Change |
|------|---------|--------|
| 2026-05-28 | v1 | Initial plan — 25 unit IDs + 8 integration IDs |
| 2026-05-29 | v2 | Quality bar raised: added U26–U28 (hooks, templates), I9–I10; pass criteria table; LLM tier note |
| 2026-05-29 | v3 | Eval harness section: E1–E5 (grade.sh, fixture validity, run-eval dry-run); test_plugin_structure + test_portability cross-reference; behavioral acceptance note |
| 2026-05-29 | v4 | Added U29–U38 (test_onboard.bats + test_doctor.bats); scope note for zero-LLM E2E acceptance (reports/2026-05-29-onboard.md); version bump v0.1.0→v0.4.0 |
