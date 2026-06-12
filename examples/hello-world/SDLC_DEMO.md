# SDLC_DEMO — hello-world end-to-end walkthrough

> This file traces a complete sdlc-orchestrator session applied to the `hello-world`
> toy project. Every `/sdlc:*` command is demonstrated in sequence. Use this as the
> integration-test narrative for T24.

---

## 0. Prerequisites

```bash
# Start inside this directory (a clean git repo already committed)
cd examples/hello-world
git log --oneline
# → abc1234 feat: initial hello-world skeleton
```

The sdlc-orchestrator plugin is installed and active in `~/.claude/settings.json`.
Run `/sdlc:status` to confirm:

```
[sdlc-orchestrator] status
  plugin_version : 0.1.0
  stack_detected : rust (Cargo.toml present)
  agents         : 9 loaded
  skills         : 5 loaded
  hooks          : 3 wired
  last_handoff   : none
```

---

## Phase 1 — `/sdlc:spec hello`

Invoke:

```
/sdlc:spec hello
```

The **spec-analyst** agent (model_tier=opus) activates. It reads the project root,
detects `Cargo.toml`, infers the Rust stack adapter (`config/stack-rust.yaml`), and
opens a Socratic dialogue to clarify scope. For this toy the session is minimal:

> "What does `hello-world` need to do?"
> "Print a greeting to stdout. One function, one test."

The agent drafts `docs/superpowers/specs/2026-05-28-hello.md` (11 sections, §3.1):

```
1. 目标定位  — print "hello, sdlc-orchestrator" to stdout; exit 0
2. 范围边界  — single binary; no lib crate; no CLI args in v0.1
3. 架构数据流 — main() → println!() → stdout
4. 模块边界  — one file: src/main.rs
5. API 契约  — binary stdout contract (no REST)
6. 扩展点    — argv parsing reserved for v0.2
7. 错误 + 边界 — process always exits 0 for this toy
8. 成本契约  — zero external cost; local cargo build only
9. 测试矩阵  — cargo test passes; output matches expected string
10. 向后兼容 — n/a (v0.1.0 initial)
11. 风险登记 — none material
```

Handoff YAML emitted to `docs/superpowers/handoffs/2026-05-28T10:00-spec-hello.yaml`:

```yaml
phase: spec
agent: spec-analyst
spec_path: docs/superpowers/specs/2026-05-28-hello.md
self_score:
  completeness: 5
  clarity: 5
  rubric_ref: "Appendix E.1"
next_phase: plan
```

User approves by replying `ok` or invoking the next command. The Pre-Create Gate
(`PostToolUse:Write` hook) fires on the spec write, confirms spec path matches
`docs/superpowers/specs/<date>-<slug>.md` pattern, and allows the write.

---

## Phase 2 — `/sdlc:plan hello`

Invoke:

```
/sdlc:plan docs/superpowers/specs/2026-05-28-hello.md
```

The **architect** agent (model_tier=opus) reads the approved spec and emits a plan.
The G1 Challenger pass runs: a second internal call cross-checks the plan against
the spec's 11 sections. For hello-world, the plan is trivially small:

```markdown
## Implementation plan — hello v0.1.0

| Task | File | Description | Commit |
|------|------|-------------|--------|
| T1   | src/main.rs | Write main() with println! | feat(hello): implement greeting |
| T2   | src/main.rs | Add #[test] placeholder | test(hello): placeholder unit test |
| T3   | (disk audit) | Run cargo clean after build | chore: disk cleanup |
```

Plan written to `docs/superpowers/plans/2026-05-28-hello.md`.

Handoff YAML (`2026-05-28T10:10-plan-hello.yaml`):

```yaml
phase: plan
agent: architect
spec_path: docs/superpowers/specs/2026-05-28-hello.md
plan_path: docs/superpowers/plans/2026-05-28-hello.md
tasks:
  - id: T1
    description: "implement main() greeting"
  - id: T2
    description: "add placeholder unit test"
  - id: T3
    description: "disk audit + cargo clean"
self_score:
  alignment_with_spec: 5
  task_granularity: 4
  rubric_ref: "Appendix E.2"
next_phase: impl
```

The G1 Challenger scores `self_score.alignment_with_spec: 5/5` — all 11 spec
sections are addressed or explicitly noted as N/A.

---

## Phase 3 — `/sdlc:impl hello T1`

Invoke:

```
/sdlc:impl docs/superpowers/plans/2026-05-28-hello.md T1
```

The **tdd-driver** agent (model_tier=sonnet) takes over. It follows the TDD cycle:

1. **Red** — writes a failing test first (the test checks stdout contains the
   expected string, using `assert_cmd` or equivalent). In this toy the existing
   `placeholder` test serves as the red step.
2. **Green** — implements `main()` with `println!("hello, sdlc-orchestrator")`.
3. **Refactor** — nothing to refactor; confirms `cargo test` passes.

`PostToolUse:Write` hook fires on each file write. For `src/main.rs` it checks:
- Does the file path match the plan's declared file list? YES.
- Is the filename one of the Pre-Create Gate forbidden forms? NO.
- Disk gate: runs `df -h /data` — still well above 50 GB headroom.

Commit emitted:

```
feat(hello): implement greeting + placeholder test

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

Handoff YAML (`2026-05-28T10:20-impl-T1.yaml`):

```yaml
phase: impl
agent: tdd-driver
task_id: T1
files_written:
  - src/main.rs
tests_passed: true
cargo_test_output: "test tests::placeholder ... ok"
self_score:
  tdd_cycle_followed: 5
  rubric_ref: "Appendix E.3"
next_phase: impl
next_task: T2
```

### T2 and T3

`/sdlc:impl ... T2` adds the explicit string-match test. `T3` invokes the disk
monitor: `cargo build --release && cargo clean` + `df` confirmation. The
`PostToolUse:Write` hook fires 0 times (no files written in T3 — pure shell ops).

---

## Phase 4 — `/sdlc:review master`

Invoke:

```
/sdlc:review master
```

The **code-reviewer** agent (model_tier=sonnet) performs Round 1 of the two-round
review mandated by §5.2. It reads all modified files in the current diff:

**Round 1 findings** (for this toy, none critical):
- No silent failures (Result/Err not applicable for println!).
- No hardcoded secrets.
- Test coverage: placeholder passes; no edge/adversarial needed for toy.
- Commit message format: correct.

**Round 2** cross-cutting pass:
- Documentation sync: README.md references `cargo run`; output matches code. ✓
- No regression: `cargo test` still passes. ✓
- `#[ignore]` count: 0 → 0. ✓

Handoff YAML (`2026-05-28T10:35-review.yaml`):

```yaml
phase: review
agent: code-reviewer
round_1_findings: []
round_2_findings: []
verdict: PASS
self_score:
  coverage_breadth: 4
  rubric_ref: "Appendix E.4"
next_phase: test
```

---

## Phase 5 — `/sdlc:test all`

Invoke:

```
/sdlc:test all
```

The **qa-engineer** agent (model_tier=sonnet) runs the 6-category test matrix
from §6.1 against the toy. Because it is a pure Rust binary with no LLM and no
network, several categories are trivially short:

| Category | Result | Notes |
|----------|--------|-------|
| happy path | PASS | `cargo run` prints expected string |
| edge case | PASS | binary ignores all argv (no parsing) |
| error case | PASS | always exits 0 — no error paths |
| adversarial | PASS | no user input accepted; nothing to inject |
| multi-user/concurrency | N/A | single-binary, not a server |
| resource exhaustion | PASS | cargo clean confirms no disk growth |

Multi-seed requirement (§2.3.7): the toy has no LLM paths, so N=3 seed runs
collapse to "run `cargo test` 3 times". All 3 pass deterministically.

The disk-monitor (`Stop` hook) fires when the agent session ends, confirming
`/data` headroom > 50 GB and no orphaned `target/` directories.

Handoff YAML (`2026-05-28T10:50-test.yaml`):

```yaml
phase: test
agent: qa-engineer
categories_run: [happy, edge, error, adversarial, resource]
categories_skipped:
  - id: multi-user
    reason: "not a server — N/A for toy"
multi_seed:
  n: 3
  all_pass: true
self_score:
  category_coverage: 5
  rubric_ref: "Appendix E.5"
next_phase: release
```

---

## Phase 6 — `/sdlc:release v0.1.0`

Invoke:

```
/sdlc:release v0.1.0`
```

The **releaser** agent (model_tier=opus) runs the RC 4-Gate checklist (§7.2):

### Gate 1 — Documentation audit

- `Cargo.toml` version = `0.1.0` ✓
- `README.md` references `cargo run` ✓
- `RELEASE.md` (in the parent plugin repo) has a `hello-world` example entry ✓
- No `.zh.md` files except README ✓

### Gate 2 — Code audit

```
cargo test --workspace --release   → all pass
cargo clippy -- -D warnings        → 0 warnings
#[ignore] count: 0                 → no spike
```

### Gate 3 — Feature/expectation alignment

Every item in the spec's §1 (目标定位) is verified:
- Binary prints `hello, sdlc-orchestrator` ✓  (captured with `cargo run 2>&1`)
- Exit code 0 ✓  (`echo $?`)

Screenshot/log evidence written to `docs/screenshots/v010-hello-verification/`.

### Gate 4 — Known limitations

```markdown
## Known Limitations

- No argv parsing (reserved for v0.2)
- No integration with an external LLM (toy is deterministic)
```

Tag command (user executes manually after agent confirms all 4 gates):

```bash
git tag v0.1.0
git push origin v0.1.0
```

Handoff YAML (`2026-05-28T11:05-release-v0.1.0.yaml`):

```yaml
phase: release
agent: releaser
version: v0.1.0
gate_1: PASS
gate_2: PASS
gate_3: PASS
gate_4: PASS
self_score:
  gate_completeness: 5
  rubric_ref: "Appendix E.6"
tag_pushed: false   # user manually executes
next_phase: done
```

---

## Phase 7 — Sprint archival (Stop hook)

When the Claude Code session ends (user closes terminal or types `/exit`), the
`Stop` hook fires the **sprint-archival** skill:

1. Finds `docs/superpowers/plans/2026-05-28-hello.md` (the plan created in Phase 2).
2. Confirms all tasks T1/T2/T3 are committed (checks git log).
3. Inlines a one-paragraph summary into `RELEASE.md` under `## v0.1.0`:
   > "hello-world toy: initial greeting binary; placeholder test; disk-audit T3 confirmed cargo clean."
4. **Deletes** `docs/superpowers/plans/2026-05-28-hello.md` (§3.2 plan lifecycle).
5. Leaves the spec at `docs/superpowers/specs/2026-05-28-hello.md` (permanent ADR-adjacent).

Console output:

```
[sdlc-orchestrator] Stop hook — sprint archival
  plan deleted  : docs/superpowers/plans/2026-05-28-hello.md
  release entry : RELEASE.md § v0.1.0 updated
  disk audit    : /data 312G free — OK; /tmp 18G free — OK
  handoffs      : 6 YAML files in docs/superpowers/handoffs/ (kept)
```

---

## Summary

| Phase | Command | Agent | Handoff file |
|-------|---------|-------|-------------|
| 1 Spec | `/sdlc:spec hello` | spec-analyst (opus) | `2026-05-28T10:00-spec-hello.yaml` |
| 2 Plan | `/sdlc:plan ...` | architect (opus) | `2026-05-28T10:10-plan-hello.yaml` |
| 3 Impl T1 | `/sdlc:impl ... T1` | tdd-driver (sonnet) | `2026-05-28T10:20-impl-T1.yaml` |
| 3 Impl T2 | `/sdlc:impl ... T2` | tdd-driver (sonnet) | `2026-05-28T10:25-impl-T2.yaml` |
| 3 Impl T3 | `/sdlc:impl ... T3` | disk-monitor (haiku) | `2026-05-28T10:30-impl-T3.yaml` |
| 4 Review | `/sdlc:review master` | code-reviewer (sonnet) | `2026-05-28T10:35-review.yaml` |
| 5 Test | `/sdlc:test all` | qa-engineer (sonnet) | `2026-05-28T10:50-test.yaml` |
| 6 Release | `/sdlc:release v0.1.0` | releaser (opus) | `2026-05-28T11:05-release-v0.1.0.yaml` |
| 7 Archive | *(Stop hook)* | sprint-archival (haiku) | *(inline to RELEASE.md)* |

Total elapsed: ~65 minutes wall-clock for a complete SDLC cycle on a trivial
project. The real value is the **structure**: every decision is traceable via
handoff YAMLs, every file write was gated, disk was audited twice, and the plan
was automatically archived on session close.

This walkthrough is the **integration test target** for T24: a bats script will
replay each command against a fresh clone of `hello-world` and assert that the
corresponding handoff YAML files exist with the expected `phase` and `verdict`
fields.
