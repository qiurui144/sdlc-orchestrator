---
name: sdlc-orchestrator
version: v0.1.0-spec
status: DRAFT — pending user review
date: 2026-05-28
authors: qiurui144 + Claude Opus 4.7
---

# Spec: sdlc-orchestrator CC plugin

> 通用软件项目全生命周期(需求 → 设计 → 编码 → 测试 → 发布 → 文档)
> 在 Claude Code 内的可复用编排框架。任何仓接入即可获能力,不与业务仓耦合。

---

## 0. 目录 (TOC)

- [1. 目标定位](#1-目标定位)
- [2. 范围边界](#2-范围边界)
- [3. 架构数据流](#3-架构数据流)
- [4. 模块边界](#4-模块边界)
- [5. API 契约](#5-api-契约)
- [6. 扩展点 / 插件接口](#6-扩展点--插件接口)
- [7. 错误 + 边界 case](#7-错误--边界-case)
- [8. 成本契约](#8-成本契约)
- [9. 测试矩阵](#9-测试矩阵)
- [10. 向后兼容](#10-向后兼容)
- [11. 风险登记](#11-风险登记)
- [Appendix A. handoff schema 详](#appendix-a-handoff-schema-详)
- [Appendix B. 反模式映射表](#appendix-b-反模式映射表)

---

## 1. 目标定位

### 1.1 解决的用户痛点

在 real downstream projects 等真实业务仓开发过程中实际踩到的 SDLC 反模式:

| 痛点 | 现实表现 | 全局 CLAUDE.md 对应规则 |
|------|---------|------------------------|
| 单 session 自己包揽全部 SDLC | spec / plan / impl / review / test / release / docs 一锅炖 → drift | §3.1 架构级设计铁律 |
| spec drift / scope creep | implementation 偏离 spec,无 re-review | §3.1 反模式第 5/6 条 |
| 多 agent burst 盘满 | 4 cargo agent 同时 build → `/tmp` ENOSPC → bash sandbox 全瘫 | §1.1.6 任务后磁盘自查 |
| docs/ 顶层泛滥 | `*-report.md` / `v1.0-*.md` / `.zh.md` 满地 | §1.1.2 / §3.2 文档体系铁律 |
| Pre-Create Gate 跳过 | Write `.md` 前不查重 → 同主题多份 | §1.1.7 Pre-Create Gate |
| agent 自报 PASS 不重验 | "tests pass" 但 disk-full 污染 evidence | §6.3 Baseline 不轻易下结论 |
| uncommitted worktree work lost | agent 切分支前漏 commit → 改动消失 | §4.2.3 Git 风险与规范 |
| agent prompt 不带白名单约束 | dispatch 时忘提白名单 → 子 agent 无差别 Write | §3.2 白名单 + §1.1.7 |

### 1.2 产品 positioning

- **定位**:Claude Code 标准 plugin,**业务无关**,**stack 无关**(Rust / TS / Python / Go 通用)
- **范围**:仅做 SDLC 编排 + 反模式拦截,**不替代** superpowers 现有 skill(spec → 调 superpowers:writing-plans 出 plan;review → 调 superpowers:requesting-code-review 等)
- **接入方式**:目标仓不改一行,只需 `cp -r plugin → ~/.claude/plugins/sdlc-orchestrator/`(或 plugin marketplace install)即获能力
- **北极星**:"接入任意空仓后 30 min 内能从 `/sdlc:spec hello` 跑到 `/sdlc:release v0.1.0` 全链通"

### 1.3 与 CLAUDE.md 全局规范的对齐表

plugin **不创造**新规则,只**自动化执行** CLAUDE.md 已有规则。每个组件 1:1 映射:

| Plugin 组件 | 执行的全局规则 |
|------------|----------------|
| `spec-analyst` agent | §3.1 11 节 spec(目标/范围/数据流/边界/契约/扩展点/错误/成本/测试/兼容/风险) |
| `architect` agent | §3.1 spec → plan 评审流程 + 调 superpowers:writing-plans |
| `implementer` agent | §3.1 第 5 步 "implementation 严格按 plan;偏离回头改 plan" |
| `pr-reviewer` agent | §5.2 两轮 review 必查清单 |
| `tester` agent | §6.1 6 类下限 + §6.2 SOP 固化优先 + §6.3 multi-seed N=3 |
| `releaser` agent | §7.1 版本拆解 + §7.2 RC 四节门 + §7.3 本机部署验证 |
| `docs-curator` agent | §1.1.2 / §1.1.3 / §1.1.4 / §3.2 文档体系铁律 |
| `disk-monitor` agent | §1.1.6 任务后磁盘自查清理 |
| `task-orchestrator` agent | §1.1.7 Pre-Create Gate + 红线阻断 + handoff schema enforce |
| `pre-create-gate` skill | §1.1.7 3 问 |
| `sprint-archival` skill | §1.1.7 "Sprint 完成强制归档" |
| `disk-self-audit` skill | §1.1.6 / `df -h / /tmp /data` 三盘审 |
| `handoff-schema` skill | §3.1 5 步评审流程(spec → plan → impl → review → release 不漂移) |
| `multi-agent-dispatch` skill | §7.1.7 并行开发 + 串行 tag |
| `PostToolUse:Write` hook | §1.1.7 自动 trigger pre-create-gate |
| `Stop` hook | §1.1.6 sprint 完成 → disk audit + archival |
| `PreToolUse:Bash` hook | §1.1.6 build 前红线判 |

---

## 2. 范围边界

### 2.1 v0.1.0 做

| 类别 | 内容 |
|------|------|
| Agent (9) | spec-analyst / architect / implementer / pr-reviewer / tester / releaser / docs-curator / disk-monitor / task-orchestrator |
| Skill (5) | pre-create-gate / sprint-archival / disk-self-audit / handoff-schema / multi-agent-dispatch |
| Slash command (9) | /sdlc:spec /sdlc:plan /sdlc:impl /sdlc:review /sdlc:test /sdlc:release /sdlc:audit-docs /sdlc:disk /sdlc:status |
| Hook (3) | PostToolUse:Write / Stop / PreToolUse:Bash(build) |
| Example (1) | examples/hello-world/ Rust toy project(端到端 demo) |
| 文档 | README.md(产品入口 + 双语跳转) / README.zh.md / DEVELOP.md / RELEASE.md / CLAUDE.md(本 plugin 自身的 AI 工作指令) |
| Self-hosting | plugin 自身开发使用 plugin 自身的 SDLC 流程 |

### 2.2 v0.1.0 **不**做(写死,避免 scope creep)

| 不做 | 推迟到 |
|------|--------|
| 跨仓 multi-repo sprint 协调 | v0.2 |
| CI/CD 模板自动生成(GH Actions / GitLab CI) | v0.3 |
| bench / soak 框架化(criterion / locust 模板) | v0.4 |
| LLM 模型/tier 自动选(per §4.5 兜底) | v0.5 |
| 远程 dashboard / 状态可视化 | 不计划(违反隐私优先) |
| 替代 superpowers 现有 skill | 永不,只编排调用 |
| 内置具体业务 prompt(法律 / 医疗 / 教育) | 永不 — plugin stack/业务无关 |
| 上云组件 / SaaS 后端 | 永不 — 纯本地 plugin |

### 2.3 stack 边界

支持任意 stack 的"通用动作":git / file / process / disk audit。**stack 特定动作**(`cargo build` / `npm test` / `go test` / `pytest`)通过 **stack adapter 配置文件**(可选 `~/.claude/plugins/sdlc-orchestrator/config/stack-<lang>.yaml`)注入,plugin 不内置任何特定 stack 的 build / test 命令字面量。

---

## 3. 架构数据流

### 3.1 一图概括

```
                          ┌──────────────────────────┐
User: /sdlc:spec hello ──▶│   task-orchestrator      │ ──┐
                          │   (meta agent + 调度)    │   │
                          └────────────┬─────────────┘   │
                                       │ dispatch       │ Pre-Create Gate
                                       ▼                │ ↑ (PostToolUse:Write)
            ┌──────────────────────────────────────────┐ │ disk audit
            │ Phase 1: spec-analyst                    │ │ ↑ (PreToolUse:Bash)
            │  ▶ produces docs/specs/<date>-<f>.md     │ │ sprint archival
            │  ▶ 11 sections enforced                  │ │ ↑ (Stop)
            └────────────┬─────────────────────────────┘ │
                         │ handoff.yaml (spec→plan)     │
                         ▼                              │
            ┌──────────────────────────────────────────┐│
            │ Phase 2: architect                       ││
            │  ▶ invoke superpowers:writing-plans      ││
            │  ▶ produces docs/plans/<date>-<f>.md     ││
            └────────────┬─────────────────────────────┘│
                         │ handoff.yaml (plan→impl)    │
                         ▼                             │
            ┌──────────────────────────────────────────┐│
            │ Phase 3: implementer (TDD test-first)   ││
            │  ▶ per-task commit pinning              ││
            │  ▶ deviation → re-route to architect    ││
            └────────────┬─────────────────────────────┘│
                         │                              │
                         ▼                              │
            ┌──────────────────────────────────────────┐│
            │ Phase 4: pr-reviewer (2 rounds)         ││
            │  ▶ invoke superpowers:requesting-review ││
            │  ▶ adversarial-reviewer optional        ││
            └────────────┬─────────────────────────────┘│
                         │                              │
                         ▼                              │
            ┌──────────────────────────────────────────┐│
            │ Phase 5: tester                          ││
            │  ▶ 6 categories + multi-seed N=3         ││
            │  ▶ stack adapter for build/test cmd     ││
            └────────────┬─────────────────────────────┘│
                         │                              │
                         ▼                              │
            ┌──────────────────────────────────────────┐│
            │ Phase 6: releaser                        ││
            │  ▶ RC 4 gates + 本机部署验证             ││
            │  ▶ RELEASE.md 4 sections + tag           ││
            └────────────┬─────────────────────────────┘│
                         │                              │
                         ▼                              │
            ┌──────────────────────────────────────────┐│
            │ Cross-cutting (always-on):               ││
            │  ▶ docs-curator (audit-docs on demand)  ││
            │  ▶ disk-monitor (auto + on demand)      ││
            └──────────────────────────────────────────┘│
                                                        │
            ◀───────────────────────────────────────────┘
              hooks fired throughout
```

### 3.2 Handoff artifact 物理表现

每个 phase 输出一份结构化 markdown(`docs/superpowers/handoffs/<date>-<phase>.yaml` + `<phase>.md`):

```yaml
# spec → plan handoff
schema_version: 1
phase_from: spec
phase_to: plan
spec_path: docs/superpowers/specs/2026-05-28-sdlc-orchestrator.md
spec_sha: abc123  # git blob SHA
deliverables_proposed:
  - agents/spec-analyst.md
  - agents/architect.md
  ...
risks_to_flag_in_plan: [...]
estimated_minor: v0.1.0
```

### 3.3 状态机

phase 转换严格单向,**回头必须经 architect re-review**:

```
[INIT] → [SPEC_DRAFT] → [SPEC_APPROVED] → [PLAN_DRAFT] → [PLAN_APPROVED]
       → [IMPL_IN_PROGRESS] → [IMPL_COMPLETE] → [REVIEW_R1] → [REVIEW_R2]
       → [TEST_RUN] → [TEST_PASS] → [RC_CANDIDATE] → [GA_TAG]

任一阶段发现上游缺陷:
  [IMPL_IN_PROGRESS] --deviation--> 必须 → [PLAN_DRAFT] (走 architect 改)
  [PLAN_APPROVED] --insufficiency--> 必须 → [SPEC_DRAFT] (走 spec-analyst 改)
```

### 3.4 数据存储(零外部依赖)

| 数据类 | 位置 | 生命周期 |
|--------|------|----------|
| spec | `docs/superpowers/specs/<date>-<feature>.md` | 长期 SSOT |
| plan | `docs/superpowers/plans/<date>-<feature>.md` | 实施完成后删除 |
| handoff | `docs/superpowers/handoffs/<date>-<phase>.yaml` | 实施完成后归档到 RELEASE.md |
| state | `.sdlc/state.json` (gitignored) | 当前 sprint 状态机 |
| disk audit log | `.sdlc/disk-audit.log` (gitignored) | rolling 7 天 |
| sprint metadata | `.sdlc/sprints/<date>.yaml` (gitignored) | rolling 30 天 |

**禁止**:DB / Redis / 外部服务。完全 file-based。

---

## 4. 模块边界

```
sdlc-orchestrator/                 # git 仓根
├── plugin.json                    # CC plugin manifest (entry point)
├── README.md                      # 英文产品入口 + 双语跳转
├── README.zh.md                   # 中文跳转副本
├── DEVELOP.md                     # 开发者文档
├── RELEASE.md                     # 版本历史 SSOT
├── CLAUDE.md                      # 本 plugin 自身 AI 工作指令
├── LICENSE                        # MIT
├── .gitignore                     # 含 .sdlc/state.json + reports/runs/
├── agents/
│   ├── spec-analyst.md
│   ├── architect.md
│   ├── implementer.md
│   ├── pr-reviewer.md
│   ├── tester.md
│   ├── releaser.md
│   ├── docs-curator.md
│   ├── disk-monitor.md
│   └── task-orchestrator.md
├── skills/
│   ├── pre-create-gate/SKILL.md
│   ├── sprint-archival/SKILL.md
│   ├── disk-self-audit/SKILL.md
│   ├── handoff-schema/SKILL.md
│   └── multi-agent-dispatch/SKILL.md
├── commands/
│   ├── spec.md            # /sdlc:spec
│   ├── plan.md            # /sdlc:plan
│   ├── impl.md            # /sdlc:impl
│   ├── review.md          # /sdlc:review
│   ├── test.md            # /sdlc:test
│   ├── release.md         # /sdlc:release
│   ├── audit-docs.md      # /sdlc:audit-docs
│   ├── disk.md            # /sdlc:disk
│   └── status.md          # /sdlc:status
├── hooks/
│   ├── hooks.json         # CC hook 注册
│   ├── post-write.sh      # PostToolUse:Write
│   ├── stop.sh            # Stop
│   └── pre-bash-build.sh  # PreToolUse:Bash(cargo/npm/go/pytest build)
├── templates/
│   ├── spec-template.md   # 11 节空白模板
│   ├── plan-template.md   # implementation plan 模板
│   ├── release-template.md # RELEASE.md 4 节模板
│   ├── dispatch-template.md # agent dispatch 注入白名单/Pre-Create
│   └── handoff-template.yaml
├── config/
│   ├── stack-rust.yaml    # cargo build / test 命令
│   ├── stack-ts.yaml      # npm / pnpm
│   ├── stack-python.yaml  # pytest
│   ├── stack-go.yaml      # go test
│   └── stack-generic.yaml # fallback
├── docs/
│   ├── superpowers/
│   │   ├── specs/         # 本 plugin 自身的 spec(self-hosting)
│   │   ├── plans/
│   │   └── handoffs/
│   ├── INSTALL.md         # 接入新仓 3 步流程
│   └── TESTING.md         # plugin 自身测试方法
├── examples/
│   └── hello-world/       # Rust toy: cargo new hello-world 后接入演示
│       ├── README.md
│       └── SDLC_DEMO.md   # 从 /sdlc:spec hello 到 /sdlc:release v0.1.0 录屏
└── tests/
    ├── unit/              # 各 skill / hook 单测
    ├── integration/       # toy project 端到端
    └── TEST_PLAN.md       # 测试大纲 SSOT (§6.1)
```

**模块边界硬约束**:

1. agents/ 内容 = 各 agent 的 prompt + 工具 scope,**不含**业务代码
2. skills/ 内容 = 各 skill 的触发条件 + 步骤,**可调用** agents 但不可反向
3. commands/ 内容 = slash command 定义,**只能** dispatch agent,不直接做事
4. hooks/ 内容 = bash 脚本,**纯 read-only** 决策,不修改业务文件
5. templates/ 内容 = 静态模板,**任何 agent / skill 必须 reference 模板而不重写**
6. config/stack-*.yaml = stack 抽象,**唯一**含 build/test 命令字面量的地方

---

## 5. API 契约

### 5.1 Slash command 接口

每个 command 是 `commands/<name>.md`,frontmatter 声明参数 + 必备 agent + handoff 期望:

```markdown
---
description: Draft an 11-section spec for a new feature
argument-hint: <feature-slug>
allowed-tools: [Read, Write, Glob, Grep]
required-agents: [spec-analyst]
---

# /sdlc:spec <feature-slug>

...command body...
```

| Command | 参数 | 主 agent | 输出 |
|---------|------|---------|------|
| `/sdlc:spec <slug>` | feature slug (kebab-case) | spec-analyst | `docs/superpowers/specs/<date>-<slug>.md` |
| `/sdlc:plan <spec-path>` | spec 文件路径 | architect | `docs/superpowers/plans/<date>-<slug>.md` |
| `/sdlc:impl <plan-path>` | plan 文件路径 | implementer (subagent-driven) | 多 commit 进 branch |
| `/sdlc:review <branch>` | branch 名 | pr-reviewer | 2 轮 review report |
| `/sdlc:test <scope>` | unit/integration/e2e/all | tester | `reports/<date>-test.md` |
| `/sdlc:release <minor>` | semver minor (`v0.1.0`) | releaser | tag + RELEASE.md 节 |
| `/sdlc:audit-docs` | (无) | docs-curator | `reports/<date>-doc-audit.md` |
| `/sdlc:disk` | (无) | disk-monitor | `.sdlc/disk-audit.log` 追加 |
| `/sdlc:status` | (无) | task-orchestrator | stdout 状态机当前 phase |

### 5.2 Agent dispatch handoff schema (v1)

所有 agent 间 handoff 走统一 YAML:

```yaml
schema_version: 1
sprint_id: <date>-<slug>
phase_from: spec | plan | impl | review | test
phase_to: plan | impl | review | test | release
artifact_path: <relative path to .md>
artifact_sha: <git blob SHA>  # 用 git hash-object 算
deliverables: [...]           # 上一 phase 承诺的输出
deviations: []                 # 若有偏离,记录原因
risks_carry_over: []
disk_snapshot_before:          # df 输出 snapshot
  root_avail_gb: 20
  data_avail_gb: 161
  tmp_avail_gb: ...
timestamp_utc8: 2026-05-28T14:30:00+08:00
```

handoff **缺字段** → handoff-schema skill 直接 reject,不允许下游 phase 启动。

### 5.3 Hook input/output 契约

**PostToolUse:Write** input(per CC hook spec):

```json
{ "tool_name": "Write", "tool_input": { "file_path": "...", "content": "..." } }
```

output(stdout):

- exit 0 = pass
- exit 1 + stderr msg = 警告(继续)
- exit 2 + stderr msg = 阻断(per Pre-Create Gate)

**PreToolUse:Bash(build)** 触发条件:`command` 含 `cargo build` / `npm run build` / `go build` / `pytest --collect-only` 等;判断 `/` `/tmp` `/data` 任一 < 50G 即 exit 2。

### 5.4 stack adapter 契约

`config/stack-<lang>.yaml`:

```yaml
language: rust
build: cargo build --release
test_unit: cargo test --lib
test_integration: cargo test --test '*'
test_all: cargo test --workspace
lint: cargo clippy --workspace --all-targets -- -D warnings
clean: cargo clean
target_size_estimator: |
  find target -maxdepth 2 -name "release" -o -name "debug" -exec du -sh {} +
```

stack 自动探测:仓根有 `Cargo.toml` → rust;`package.json` → ts;`go.mod` → go;`pyproject.toml` → python;否则 `stack-generic.yaml`。

---

## 6. 扩展点 / 插件接口

### 6.1 加新 agent

`agents/<name>.md` 用 CC agent frontmatter 标准格式:

```markdown
---
name: my-custom-agent
description: <一句话描述,用于自动 routing>
tools: [Read, Write, Bash, Grep]
---

<agent system prompt>
```

注册时 plugin 自动发现 `agents/*.md`,无需改 plugin.json。

### 6.2 加新 skill

`skills/<name>/SKILL.md` 标准格式:

```markdown
---
name: my-custom-skill
description: <触发条件 + 用途>
---

<skill 触发条件 + 步骤>
```

### 6.3 加新 slash command

`commands/<name>.md`(命名空间 `/sdlc:<name>`)。

### 6.4 加新 stack adapter

新建 `config/stack-<lang>.yaml`,按 §5.4 契约填字段。

### 6.5 加新 hook

编辑 `hooks/hooks.json` + 新 `hooks/<name>.sh`。

### 6.6 配置覆盖

接入仓可在自身 `.claude/sdlc-orchestrator.local.md` 覆盖默认行为(per plugin-dev:plugin-settings 模式)。例:

```markdown
---
disk_redline_root_gb: 30    # 默认 50,关键服务器调小
disk_redline_data_gb: 100   # 默认 50
multi_agent_max_parallel: 3 # 默认 4
spec_template: ./my-team-spec-template.md
---
```

### 6.7 第三方 plugin 协作

- 调用 superpowers:writing-plans / requesting-code-review / brainstorming(显式)
- 调用 engineering-skills:adversarial-reviewer / tdd-guide(显式)
- 调用 hookify(显式)
- **不允许**隐式依赖未列出的第三方 skill(每个 agent prompt 必须明示依赖)

---

## 7. 错误 + 边界 case

### 7.1 错误码体系(kebab-case,per §3.1 第 7 节)

| code | 含义 | 退出动作 |
|------|------|---------|
| `spec-missing-section` | spec 11 节有缺 | spec-analyst 报告缺哪节,等用户补 |
| `plan-not-found` | `/sdlc:impl <path>` 路径不存在 | implementer fail graceful + 列已有 plan |
| `phase-skip-not-allowed` | 试图从 INIT 跳到 IMPL | task-orchestrator 拒绝 + 提示走 spec |
| `handoff-schema-invalid` | YAML 缺字段 | handoff-schema skill reject |
| `disk-redline-hit` | 三盘任一 < 红线 | disk-monitor 阻断,提示 cargo clean |
| `pre-create-gate-fail` | Write 三问任一为否 | hook exit 2,要求用户 confirm |
| `scope-drift` | impl 偏离 plan | implementer 强制 re-route 到 architect |
| `evidence-missing` | agent 报 PASS 但无 raw log | task-orchestrator reject claim |
| `stack-adapter-unknown` | 没匹配的 stack | fallback generic,警告用户配 stack-<lang>.yaml |

### 7.2 边界 case 矩阵

| Case | 行为 |
|------|------|
| 空仓(无 .git) | plugin 提示 `git init` 后再用 |
| 仓有 .git 但无 docs/ | 自动 mkdir docs/superpowers/{specs,plans,handoffs} |
| 多 feature 同时 spec | 各自独立 sprint_id,互不干扰 |
| spec 写到一半中断 | 状态 `SPEC_DRAFT`,下次 `/sdlc:status` 提示恢复 |
| plan 文件被用户手改 | architect 复 review 时 diff vs handoff.spec_sha,差异 > 30% 警告 |
| impl 时 disk full | implementer 不切分支,先 commit 当前 step,触发 disk-monitor |
| review 时发现 spec 错 | pr-reviewer 标 `scope-drift`,task-orchestrator 回 spec phase |
| release 时 RELEASE.md 缺节 | releaser 阻断 tag,要求补齐 4 节 |
| 接入仓有自己的 CLAUDE.md | plugin CLAUDE.md 与目标仓 CLAUDE.md 不冲突时合用;冲突时目标仓优先(per superpowers 优先级) |
| stack 未识别 | 用 generic adapter + 警告 |
| 跨平台(Win / Mac / Linux) | hook 脚本用 POSIX shell + 测过 macOS bash 3.2 兼容 |
| Unicode / emoji 路径 | 路径全 quote;feature slug 仅 kebab-case `[a-z0-9-]`,emoji 拒绝 |

### 7.3 graceful degradation

| 缺失 | 降级行为 |
|------|---------|
| 无 superpowers plugin | architect 警告 + 用内置 plan-template.md 起草(降级版) |
| 无 engineering-skills | adversarial review 跳过(标 SKIPPED) |
| 无 hookify | hook 仍可手动注册,只警告 |
| LLM weak tier | per §4.5 兜底:agent 调 schema-guided + retry 3,失败 disable 该 agent + RELEASE.md 标 |

---

## 8. 成本契约

### 8.1 磁盘开销

| 项 | 大小估算 |
|----|---------|
| plugin 本体(agents/skills/commands/hooks/templates/config/docs) | < 1 MB |
| 单 sprint 产生物(spec + plan + handoffs) | < 100 KB |
| examples/hello-world/ 全量 | < 5 MB(含 Cargo.lock + target/ gitignored) |
| `.sdlc/state.json` rolling | < 50 KB |
| `.sdlc/disk-audit.log` 7 天 rolling | < 200 KB |

**plugin 不允许**单文件 > 1 MB(防 LLM 上下文炸)。

### 8.2 LLM token 估算(单 sprint 端到端)

| Phase | input tokens | output tokens | 备注 |
|-------|-------------|--------------|------|
| spec | 5K (CLAUDE.md + 模板) | 3-5K (11 节) | 一次性 |
| plan | 5K (spec) + 2K (模板) | 3-5K | 一次性 |
| impl | 10-30K(代码 context) | 5-20K(diff) | per task,N task 累计 |
| review | 10-30K(diff + spec) | 2-5K(report) | 2 轮 |
| test | 5K(plan) | 2-3K(report) | per scope |
| release | 5K(RELEASE.md + plan) | 2K(release notes) | 一次性 |

单 sprint 端到端约 **80-200K tokens**。Opus / Sonnet 都吃得下;Haiku 走兜底(per §4.5 多 tier)。

### 8.3 时间金钱归属

- **零成本路径**:offline 操作(/sdlc:disk / /sdlc:audit-docs / /sdlc:status)纯 file IO,无 LLM call
- **付费路径**:spec / plan / impl / review / test / release(需 LLM)
- **UI 显示**:每个 phase 启动前 `/sdlc:status` 列预估 token + 当前模型,用户 confirm 才执行(后续 v0.5 兜底)

### 8.4 本地算力

零 GPU 依赖。disk audit / docs audit / hook 全 CPU + IO,< 5 秒 budget。

---

## 9. 测试矩阵

### 9.1 6 类下限(per §6.1)

| 类别 | 用例 | 通过判据 |
|------|------|---------|
| happy path | toy hello-world 全链 spec→release | 端到端 0 error,生成的 spec / plan / RELEASE.md 符合模板 |
| edge case | 空 feature slug / 超长 slug / Unicode slug | 拒绝并报正确 error code |
| error case | plan 不存在 / handoff 缺字段 / stack 未识别 | 报正确 error code,exit 非 0 |
| adversarial | `feature; rm -rf /` / path traversal in spec path | 全部 quote,无注入 |
| 多用户/多并发 | 2 sprint 并行(不同 slug) | sprint_id 隔离,handoff 不串 |
| 资源耗尽 | mock `df -h` 返回 30G(< 50G 红线) | disk-monitor 阻断 build hook |
| 国际化 | 中英混合 spec 内容 | 正常 |
| 降级 | superpowers / engineering-skills 不存在 | 降级用内置模板 |

### 9.2 单测层(`tests/unit/`)

| 测什么 | 工具 |
|--------|------|
| skill 触发逻辑 | bash + bats(POSIX 测) |
| hook 决策 | bash + 模拟 input JSON |
| handoff schema 验证 | yq / python-yaml + 反例 fixture |
| stack adapter 探测 | mock 仓根文件结构 |

### 9.3 集成测(`tests/integration/`)

- examples/hello-world/ 端到端跑通(`/sdlc:spec hello` → ... → `/sdlc:release v0.1.0`)
- multi-seed N=3(per §2.3 调研纪律):跑 3 次 toy,handoff artifact 字段一致

### 9.4 plugin self-hosting 验证

- plugin 自身的开发也用本 plugin(self-eating dogfood)
- 自身 SDLC 跑过 = 实证 capability

### 9.5 TEST_PLAN.md SSOT(per §6.1)

落 `tests/TEST_PLAN.md`,含:
- 矩阵(场景 × 输入 × 期望)
- 视角划分(白 / 灰 / 黑盒)
- 通过判据(可量化)
- v 历史 trace

### 9.6 测试人员心智

不是"证明对",是"证明会挂":
- 喂 plugin 错误 spec 路径,看 fail-fast
- 同时跑 5 个 sprint,看资源管理
- 故意 disk full,看 hook 阻断
- 注入 invalid handoff YAML,看 schema reject

---

## 10. 向后兼容

### 10.1 plugin SemVer 策略

- patch(`v0.1.1`):bug fix,handoff schema 不变,接入仓无需改
- minor(`v0.2.0`):加新 agent / skill / command,handoff schema 可加字段(默认值),旧 sprint 仍跑通
- major(`v1.0.0`):breaking change(如 handoff schema_version 1→2),需 migration script

### 10.2 handoff schema versioning

```yaml
schema_version: 1   # 必填,第一行
```

handoff-schema skill 见 unknown `schema_version` → 友好提示升级 plugin,**不**自动转换(per §3.1 第 10 节)。

### 10.3 老 client 行为

- 用户在装了 sdlc-orchestrator v0.5 的环境收到一份 v0.1 schema handoff → 仍能解(向下兼容)
- 用户在 v0.1 环境收到 v0.5 handoff → handoff-schema skill 报 `handoff-schema-future-version`,提示升级

### 10.4 spec / plan / RELEASE.md 模板演进

模板 frontmatter 加 `template_version: <semver>`。spec-analyst 写 spec 时 pin 当时 template_version。后续 plugin 升级模板加新节 → 老 spec 不强制改;但用户主动 re-spec 时用新模板。

### 10.5 文件路径稳定性

`docs/superpowers/specs/<date>-<slug>.md` 路径**永久稳定**,任何版本不改名。

### 10.6 stack adapter 演进

`config/stack-<lang>.yaml` 字段加(向后)兼容;字段删走 major bump。

---

## 11. 风险登记

| # | 风险 | 概率 | 影响 | 缓解 |
|---|------|------|------|------|
| R1 | CLAUDE.md 全局规则更新但 plugin 未同步 → drift | High | High | DEVELOP.md 列出与 CLAUDE.md 的 1:1 映射表;季度审 |
| R2 | hook 阻断过严 → 用户烦躁关 hook | Medium | High | 默认 hook 仅 warn(exit 1),用户主动开 strict(exit 2);Pre-Create Gate 跳过时 log warn 不阻断 |
| R3 | disk monitor 算 cargo target 累积量不准 | Medium | Medium | 用 conservative 估算(2 × release target size);config 可调阈值 |
| R4 | multi-agent dispatch 资源冲突(per parallel-agent disk-full incident) | Medium | Critical | multi-agent-dispatch skill 默认 max_parallel=2;dispatch 前必跑 disk audit;sandbox `/tmp` 紧时降到 1 |
| R5 | superpowers / engineering-skills 升级断 API | Low | High | 调用前 version check;降级用内置模板;集成测周跑 |
| R6 | plugin 自身 build / test 与宿主项目共用 `/tmp` | Low | High | 例 toy 用 `--target-dir /tmp/sdlc-toy/`,gitignored |
| R7 | 跨平台 bash 兼容(macOS bash 3.2 / Win WSL) | Medium | Medium | hook 脚本 POSIX-only;CI 在 ubuntu + macOS 跑 |
| R8 | 接入仓 CLAUDE.md 与 plugin CLAUDE.md 冲突 | Medium | Medium | plugin CLAUDE.md 显式 "目标仓优先";INSTALL.md 写明并存规则 |
| R9 | Unicode / 中文 slug 误用 | Low | Low | slug 强制 kebab-case `[a-z0-9-]`;非法字符 reject |
| R10 | agent prompt 含 secrets 误推 | Low | Critical | per §1.4 + CI gitleaks 进 pre-commit;PR template 强制 secrets check |
| R11 | 用户跳过 spec 直接 /sdlc:impl | High | High | task-orchestrator 拒绝;phase-skip-not-allowed error |
| R12 | examples/hello-world/ 过时(stack 升级) | Medium | Low | 跟 stack adapter 同步演进;CI 跑 hello-world demo |
| R13 | plugin "捆绑过严"反而拖慢 hotfix | Low | Medium | hotfix 路径走 §5.1 决策树:typo / 一行 fix 不走 plugin |
| R14 | 用户用 plugin 写"虚假 evidence" agent 自动报 PASS | Low | Critical | tester agent 强制 raw log path + sha;evidence-missing 自动 reject;per §6.3 SOP |
| R15 | docs-curator 误删用户人工写的合法 .md | Low | High | 默认 dry-run 模式;`/sdlc:audit-docs --apply` 才真动;每次先 git status 干净检查 |
| R16 | 主仓 / 96% 满 → 本 plugin dev 撞墙 | High(已发生) | High | 本 plugin 仓在 `/data` 不在 `/`;build target 全 `/data`;dev session 启 disk-monitor 强制 |
| R17 | sprint 完成后 plan 未删 → docs/ 顶层污染 | High(历史踩坑) | Medium | sprint-archival skill 在 Stop hook 自动跑;PR description 列归档清单 |
| R18 | agent 自报 "5 报告" 但仅 2 个 .md(per R18 教训) | Medium | High | dispatch-template.md 强制 agent prompt 含 "Write `.md` 报告" + commit 前 `ls reports/<date>_*.md` 验数量 |

### 11.1 关键 mitigation 落到 v0.1

R4 / R11 / R14 / R16 / R17 / R18 已是 plugin v0.1 强制 feature(per §1.3 映射表)。

R1 季度审,R5 加 CI version check 进 v0.2 backlog。

---

## Appendix A. handoff schema 详

### A.1 spec → plan handoff

```yaml
schema_version: 1
sprint_id: 2026-05-28-sdlc-orchestrator
phase_from: spec
phase_to: plan
artifact_path: docs/superpowers/specs/2026-05-28-sdlc-orchestrator.md
artifact_sha: <git hash-object output>
deliverables_proposed:           # spec 第 2 节范围内列出的所有交付
  - agents/spec-analyst.md
  - agents/architect.md
  - ...
risks_to_flag_in_plan:           # spec 第 11 节高优 risk
  - R4 multi-agent disk full
  - R11 phase skip
  - R16 / 96% full
estimated_minor: v0.1.0
estimated_tokens: 120000
estimated_duration_hours: 6      # 真 wall-clock,per §1.2
disk_snapshot_before:
  root_avail_gb: 20              # ⚠️ 红线
  data_avail_gb: 161
  tmp_avail_gb: <to fill>
timestamp_utc8: 2026-05-28T14:30:00+08:00
```

### A.2 plan → impl handoff

```yaml
schema_version: 1
sprint_id: 2026-05-28-sdlc-orchestrator
phase_from: plan
phase_to: impl
artifact_path: docs/superpowers/plans/2026-05-28-sdlc-orchestrator.md
artifact_sha: <sha>
task_list:                       # plan 拆出的 task,每个含 commit msg 模板
  - task_id: T01
    desc: scaffold plugin.json
    files: [plugin.json]
    commit_msg: "feat: scaffold plugin manifest"
    test_strategy: unit-test bash schema check
  - ...
parallelizable_groups:           # 哪些 task 可 multi-agent dispatch
  - [T01, T02]
  - [T03]
  - [T04, T05, T06]
ordered_dependencies:            # 真依赖链
  - T03 -> T01
  - T07 -> [T04, T05, T06]
```

### A.3 impl → review handoff

```yaml
schema_version: 1
sprint_id: 2026-05-28-sdlc-orchestrator
phase_from: impl
phase_to: review
branch: feat/sdlc-orchestrator-v0.1
base_branch: master
commits:                          # 完整 SHA + msg
  - sha: abc123
    msg: "feat: scaffold plugin manifest"
  - ...
test_results:
  unit_pass: 42
  unit_fail: 0
  integration_pass: 8
  integration_fail: 0
  evidence_paths:                 # per §6.3 必含
    - reports/runs/2026-05-28-1500/unit.log
    - reports/runs/2026-05-28-1500/integration.log
deviation_from_plan: []           # 若有偏离,内容必填 + 已 re-route to architect
```

### A.4 review → test / test → release handoff

(类似格式,略;v0.1 实现时按 templates/handoff-template.yaml 标准化)

---

## Appendix B. 反模式映射表

把用户列的 7 个反模式 → plugin 防护点,逐条交叉验证:

| # | 反模式(real-project practice) | plugin 防护点 | spec 节 |
|---|------------------|--------------|---------|
| 1 | 多 agent burst 盘满灾 | disk-monitor agent + PreToolUse:Bash hook + multi-agent-dispatch skill max_parallel | §3.1 R4 / §5.3 / §11 R4 |
| 2 | uncommitted worktree work lost | implementer agent per-step commit;不允许"全 step 一个 commit" | §3.3 状态机 / §11 R6 |
| 3 | silent scope drift | implementer 偏 plan → 强制 re-route architect;state machine 反向边 | §3.3 / §7.1 scope-drift |
| 4 | agent 自报 PASS 不本机重验 | task-orchestrator 完成后跑关键测试子集;evidence-missing error code | §7.1 evidence-missing / §11 R14 |
| 5 | docs/ 顶层泛滥 | docs-curator + PostToolUse:Write hook 自动审 → reports/ | §1.3 映射 / §11 R15 |
| 6 | Pre-Create Gate 跳过 | hook 挂在 Write 前;exit 2 阻断;pre-create-gate skill | §5.3 / §7.1 pre-create-gate-fail |
| 7 | agent prompt 不强制白名单 | templates/dispatch-template.md 自动注入;每 dispatch 必 reference | §1.3 / §4 dispatch-template / §11 R18 |

---

## Appendix C. 五层设计理念

> 为什么单独一节:之前 spec 把 plugin 看作机械装配,把 6 大反模式各自怼一个 agent / skill / hook 顶上去。问题是产出的 agent prompt **稀薄** —— bullet list、无 example、无决策树、无失败模式。这一节固化"产品级 SDLC 编排"的五层设计理念,后续 agent / skill / template 必须**逐层**对照。

### C.1 协作模式(Collaboration Mode)

| 子层 | 强制 |
|------|------|
| **Handoff = 不可绕开的契约** | 每 phase 的输出必须经 `handoff-schema` skill 校验。"我已经发邮件告诉你了"不算 handoff;handoff.yaml 文件入库才算 |
| **Challenger 角色配对** | 每个 producer agent 配一个 challenger:spec-analyst ↔ architect(architect 必须 challenge spec 矛盾)、implementer ↔ pr-reviewer(reviewer 必须 challenge impl 偏离 plan)、tester ↔ releaser(releaser 必须 challenge evidence 不足)。**Challenger 不通过 = 上游回炉**,不允许甜面包 |
| **Escalation 三级** | (a) Subagent BLOCKED → controller 提供更多 context 同 tier 重试 1 次;(b) 仍 BLOCKED → 升级 tier(haiku→sonnet→opus);(c) opus 仍 BLOCKED → 升级给人 + 写 issue |
| **跨 session 续命** | spec / plan / handoffs 全 git 化。任何 fresh session `git log + cat docs/superpowers/handoffs/<latest>.yaml` 即可接着干。**禁止**关键状态只在 chat memory 里 |

**反模式**(都是 real downstream projects 实战见过):
- ❌ Agent 完成 = 自动通过(没 Challenger 一票否决权)
- ❌ Handoff 用 chat 描述传递(无 schema,下游 retry 漫无目的)
- ❌ BLOCKED 后同 tier 同 prompt 重试 5 次(浪费 token)

### C.2 流程方式(Process Methodology)

线性 phase 推进 → **加 4 个 explicit gate** + iteration budget + 收敛判据:

```
[INIT]
  ↓
[SPEC_DRAFT] ───┐ iteration budget = 3 轮
  ↓             │ convergence = 每轮新覆盖一类边界 case
[Gate G1 Design Review] ← architect 当 challenger,output ADR 入 docs/adr/
  ↓
[SPEC_APPROVED]
  ↓
[PLAN_DRAFT] ───┐ iteration budget = 2 轮  
  ↓             │ convergence = 每轮粒度更细 ≥ 20% 任务数增加 OR 减少
[Gate G2 Interface Freeze] ← 锁 API + handoff schema 后 impl 不能再改
  ↓
[PLAN_APPROVED]
  ↓
[IMPL_IN_PROGRESS] ───┐ iteration budget = 5 轮 per task
  ↓                    │ convergence = 测试 PASS + 无 regression
[IMPL_COMPLETE]
  ↓
[REVIEW_R1] → [REVIEW_R2]
  ↓
[Gate G3 Test Pass] ← tester 当 challenger,evidence 必须可 grep
  ↓
[TEST_PASS]
  ↓
[Gate G4 GA Readiness] ← releaser 当 challenger,RC 4 节门全过
  ↓
[RC_CANDIDATE] → [GA_TAG]
```

**Gate 强制实现**:每 gate 由 task-orchestrator 阻断式调用对应 challenger,exit 非 0 → 状态机不前进。

**Rollback playbook**(每 gate 必带):
| Gate | 失败判据 | 回到哪个 phase |
|------|---------|---------------|
| G1 | spec 缺节 / 1-3 mapping 不全 / 风险 < 3 | SPEC_DRAFT |
| G2 | plan 含 TBD / 任务 file-grained 而非 acceptance-grained | PLAN_DRAFT |
| G3 | 6 类测试覆盖不全 / multi-seed N<3 / evidence path 缺 | IMPL_IN_PROGRESS(回到失败 task) |
| G4 | RELEASE.md 缺节 / 本机部署 fail / known limitations 空 | TEST_PASS(补测) |

### C.3 细节拆解(Detail Decomposition)

**任务粒度不是文件,是 acceptance criterion**。

每 task 必含 7 个字段:

| 字段 | 内容 |
|------|------|
| `behavioral_contract` | "Given X, when Y, then Z" 形式描述(可量化) |
| `edge_case_matrix` | 表格:空/超长/Unicode/concurrent/error 各一行 |
| `failure_modes` | 列出可能失败模式 + 各自 graceful degradation |
| `worked_example_positive` | 完整正向 case(从 input 到 output 端到端) |
| `worked_example_negative` | 完整负向 case(典型 anti-pattern + 为什么不行) |
| `acceptance_judges` | 量化通过判据(N 测过 / coverage ≥ X% / latency ≤ Y) |
| `linked_artifacts` | 涉及的其他 task / spec § / skill / rubric 引用 |

**反模式**:
- ❌ "Step 5.4: 写 plugin.json"(文件粒度,无 contract / edge / judge)
- ✅ "Step 5.4: 写 plugin.json,使其满足 (a) jq 可解析,(b) version 符合 semver,(c) 包含 6 个 required field;negative case: 漏 description 字段会让 plugin marketplace reject"

### C.4 模型分级(详见 Appendix D)

每个 agent / skill / task 显式声明 `model_tier`,orchestrator 强制按 tier dispatch。**禁止** "全用 haiku 省 token" 反模式。

### C.5 验收 / 代码 / 文档 规范(详见 Appendix E)

- **每类产物有 rubric**(spec / plan / agent / skill / code / doc,各 5 criterion × 5 分量表)
- **每类产物有 golden example**(`templates/golden/`,referenceable 样本)
- **每类产物有 auto-lint**(docs-curator `--quality-rubric` mode)
- **每次 phase 完成 self-score**:agent 在 handoff 中携带自评分;若 < 3/5 任一项,Challenger 必须验证修复

---

## Appendix D. 模型分级矩阵

### D.1 工作类型 ↔ tier

| 工作类型 | tier | 理由 |
|---------|------|------|
| **Spec design / 11 节起草** | opus | 多领域 trade-off,scope reasoning |
| **Architecture decision (ADR)** | opus | 边界判断,长期影响 |
| **GA gate decision** | opus | 不能出错,需 conservative 判断 |
| **Security review (adversarial)** | opus | 反向创造力(攻击面想象) |
| **设计 review (G1 challenger)** | opus | 与 spec-analyst 平起平坐 |
| Plan writing (TDD 拆解) | sonnet | 结构化细节 |
| 代码 review(实质,non-skim) | sonnet | nuance + 跨 file context |
| Multi-file refactor / 集成 | sonnet | 跨边界 reasoning |
| Single-agent .md write | sonnet | 散文质量,worked example 设计 |
| Skill SKILL.md write | sonnet | 散文 + 决策树 |
| Slash command 描述写作 | sonnet | 文案精炼 |
| Frontmatter 一致性检查 | haiku | pattern match |
| 文件 copy / boilerplate 填空 | haiku | 机械 |
| Test stub generation | haiku | 模板填字段 |
| Lint / format / spell-check | haiku | 规则匹配 |
| bats grep 关键字断言 | haiku | 单一 assertion |

### D.2 编码方式

**agent / skill / command 的 frontmatter 必含 `model_tier`**:

```yaml
---
name: spec-analyst
description: ...
tools: [Read, Write, Edit, Glob, Grep, WebFetch]
model_tier: opus           # ← 新增字段,task-orchestrator dispatch 时 enforce
---
```

**task-orchestrator dispatch 协议**:

```bash
# 伪代码
agent_meta=$(yq -r '.model_tier' agents/<name>.md)
case "$agent_meta" in
  opus|sonnet|haiku) ;;
  *) echo "agent missing model_tier" >&2; exit 1 ;;
esac
dispatch_agent --model="$agent_meta" ...
```

**override 机制**:用户可在 `.claude/sdlc-orchestrator.local.md` 设 `force_tier_floor: opus`(全程不用 haiku),或个别 agent 用 `<agent>.local.md` 个别override。

### D.3 默认 tier 分配(v0.1.0 9 agents + 5 skills)

| Component | model_tier |
|-----------|-----------|
| task-orchestrator | opus(meta agent,触发 challenger 多) |
| spec-analyst | opus |
| architect | opus |
| pr-reviewer | sonnet(细节多但 review 非创造) |
| releaser | opus(GA gate) |
| implementer | sonnet(TDD 整合) |
| tester | sonnet |
| docs-curator | haiku(规则匹配) |
| disk-monitor | haiku(数字检查) |
| pre-create-gate skill | haiku |
| handoff-schema skill | haiku |
| disk-self-audit skill | haiku |
| sprint-archival skill | sonnet(决定哪些 archive 需判断) |
| multi-agent-dispatch skill | haiku |

### D.4 成本预算(单 sprint v0.1 例)

| 阶段 | tier | 调用数 | input tokens | output tokens | 累计 input | 累计 output |
|------|------|--------|--------------|---------------|------------|------------|
| Spec 起草 | opus | 1 | 8K | 8K | 8K | 8K |
| G1 challenger | opus | 1 | 12K(读 spec) | 4K | 20K | 12K |
| Plan 起草 | sonnet | 1 | 12K | 12K | 32K | 24K |
| G2 challenger | sonnet | 1 | 16K | 4K | 48K | 28K |
| Impl 27 task | sonnet | 27 | 8K avg | 5K avg | 264K | 163K |
| R1 review | sonnet | 1 | 30K | 6K | 294K | 169K |
| R2 review | sonnet | 1 | 30K | 4K | 324K | 173K |
| 6-cat 测试 | sonnet | 6 | 6K | 4K | 360K | 197K |
| G3 challenger | sonnet | 1 | 10K | 3K | 370K | 200K |
| GA gate | opus | 1 | 20K | 5K | 390K | 205K |
| **总计** | mix | ~41 | ~390K input | ~205K output |  |  |

按 2026-05 价目大致估算:opus $15/M input + $75/M output;sonnet $3/M input + $15/M output;haiku $0.8/M input + $4/M output。单 sprint **约 $5-8**。

### D.5 反模式

- ❌ "全 haiku 省钱"(已踩,见本会话 T1-T14 重写原因)
- ❌ "全 opus 保险"(浪费 ~10x token)
- ❌ Mechanical task 升 sonnet("以防万一")
- ❌ 设计 task 降 haiku("它能做就好")
- ❌ Override 不带审计(`.local.md` 改 tier 不入 commit log)

---

## Appendix E. 规范 + golden examples + rubrics

### E.1 Rubric: spec 评分卡(5 criterion × 5 scale)

| Criterion | 1 (poor) | 3 (acceptable) | 5 (exemplary) |
|-----------|---------|----------------|----------------|
| **Scope clarity** | "做 feature X" 模糊 | bounded list + 非 goals | bounded + 非 goals + 推迟到 v.next 列表 |
| **Risk register** | < 3 | 3-5,泛泛 | ≥ 10,每个绑实战 incident + prob + impact + mitigation |
| **Test matrix** | 一句"会测试" | 6-cat sketch | 6-cat + multi-seed N=3 + per-cat worked case |
| **Migration** | "向后兼容" 口号 | versioning 标 | full migration path + old→new worked example |
| **Cost contract** | "开销不大" | 一行 ballpark | 分项(disk / token / wall-clock)+ audit 命令 |

**通过线**:任一 criterion < 3 → spec 回炉。所有 = 5 → spec 成为 golden example 候选。

### E.2 Rubric: agent .md 评分卡

| Criterion | 1 | 3 | 5 |
|-----------|---|---|---|
| **Mission statement** | 缺失 | 1 句 | 1 段 + 关联 spec § + 北极星量化 |
| **Hard rules** | 缺失 / 漂浮 | bullet list | 编号 + 每条带 §-ref + 反模式对照 |
| **Decision tree** | 缺失 | 散文描述 | ASCII flowchart |
| **Worked examples** | 0 | 1 (positive) | 2 (positive + negative) |
| **Output contract** | 模糊 | yaml 展示 | yaml + validation script reference |
| **Escalation paths** | "ask user" | 模糊 | 编号阶梯(retry → tier-up → human) |
| **Linked components** | 缺 | 提名 | `[[name]]` 完整双向 |

**通过线**:总分 ≥ 25/35(5 项及格)。

### E.3 Rubric: skill SKILL.md 评分卡

| Criterion | 1 | 3 | 5 |
|-----------|---|---|---|
| **When to use** | 模糊 | 列触发条件 | 触发条件 + 不触发条件(boundary) |
| **What it does** | "做 X" | 步骤 | 步骤 + 失败模式 + 退化 |
| **Linked** | 缺 | 提及 | `[[name]]` 双向 |
| **Tests reference** | 缺 | "见 tests/" | 显式 test 文件路径 + 用例数 |

### E.4 Rubric: code 评分卡

| Criterion | 1 | 3 | 5 |
|-----------|---|---|---|
| **Correctness** | 已知 bug | 跑通 happy | 6-cat 全过 + adversarial 加固 |
| **Robustness** | crash on bad input | graceful error | graceful + retry 策略 + fallback |
| **Readability** | 难读 | 标准命名 | 标准 + 每非显然处带 WHY 注释 |
| **Testability** | 无测试 | unit | unit + integration + property test |
| **Docs sync** | 与代码漂移 | README 提及 | README + DEVELOP + RELEASE 全同步 |

### E.5 Golden examples 位置

`templates/golden/`(v0.1 不强制全配齐,作 v0.2 backlog):
- `golden-spec-example.md` — 本 plugin 自身 spec(self-host 起点,达 rubric ≥ 4/5)
- `golden-plan-example.md` — 本 plugin 自身 plan(达 rubric ≥ 4/5)
- `golden-agent-example.md` — task-orchestrator 重写版(quality bar)
- `golden-handoff-example.yaml` — 完整字段的样本

### E.6 Auto-lint:docs-curator `--quality-rubric` mode(v0.2)

```
$ /sdlc:audit-docs --quality-rubric
agents/spec-analyst.md       — score 23/35 (Decision tree=1)  ⚠️ FAIL
agents/task-orchestrator.md  — score 31/35                    ✅ PASS
skills/disk-self-audit/...   — score 14/20                    ✅ PASS
```

v0.1 先**人工 rubric pass**;v0.2 docs-curator 自动评分。

### E.7 self-score 上交机制

每个 producer agent 在 handoff YAML 中携带自评分:

```yaml
self_score:
  rubric: spec | plan | agent_md | skill_md | code
  criteria_scores:
    scope_clarity: 4
    risk_register: 5
    test_matrix: 3      # ← below 4, will trigger challenger deep dive
    ...
  overall: 4.0
  weak_points:
    - "test matrix 仅覆盖 4 类 (happy/edge/error/concurrent), 缺 adversarial / resource"
```

Challenger 拿到 self_score 后:
- 任一 criterion < 4 → 必针对那项深审
- self_score 与 challenger score 差 ≥ 1 → "self-assessment drift",retry 同 tier;再差 → escalate

---

## Appendix F. 反模式快速参考表(扩展版,基于 Appendix C/D/E)

> 把所有 Appendix C/D/E 强调的反模式聚合,便于 review 时快速 grep 检查产物是否撞红线。

| # | 反模式 | 应在哪层防 | 检测方式 |
|---|--------|----------|---------|
| AC1 | producer 自我宣布通过 | Appendix C.1 Challenger | gate exit 必 ≠ 0 才能进 |
| AC2 | handoff 走 chat 不走 YAML | C.1 Handoff 契约 | handoff-schema 强制 |
| AC3 | BLOCKED 同 tier 同 prompt retry > 1 | C.1 Escalation | task-orchestrator 计数 + 阻断 |
| AC4 | phase 跳过 gate | C.2 Process | task-orchestrator 状态机 phase-skip-not-allowed |
| AC5 | iteration 超 budget 不收敛 | C.2 收敛判据 | task-orchestrator 强制 escalate human |
| AC6 | task 文件粒度而非 contract 粒度 | C.3 Detail | architect challenger reject |
| AC7 | 任务缺 acceptance_judges | C.3 量化判据 | plan-template required field |
| AC8 | 全 haiku / 全 opus | D 模型分级 | agent frontmatter `model_tier` enforce |
| AC9 | self-score 与 challenger drift > 1 | E.7 self-score | challenger 自动 escalate |
| AC10 | agent .md < rubric 通过线 | E.2 rubric | docs-curator `--quality-rubric` |
| AC11 | RELEASE.md 缺 4 节之一 | E.4 code rubric "Docs sync" | releaser G4 gate |
| AC12 | spec 改但 plan / impl 未同步 | C.2 Rollback + E.4 | docs-curator 周审 |

---

## Appendix G. SE 实践广覆盖(post-v2 反思)

> v2 retro 完成后,用户指出 v1+v2 设计 over-index 在我们踩过的 R1-R18 prior incidents,under-index 在**通用软件工程实践**。本 Appendix 把 plugin 的 scope 从 "SDLC phase 管理" 拓到 "通用 SE 实践编排",**作为 v0.1.0 必含**(不是 roadmap)。

### G.1 通用 SE 实践 20 领域覆盖矩阵

| # | 领域 | v0.1.0 状态 | 体现 |
|---|------|------------|------|
| 1 | **Requirements engineering**(user story + stakeholder map + acceptance criteria) | v0.1 部分 | spec-analyst 11 节;**v0.2** 加 user-story 专属模板 |
| 2 | **Architecture Decision Records (ADR)** | v0.1 新加 | architecture-reviewer agent + `/sdlc:adr <slug>` |
| 3 | **Threat modeling (STRIDE / DFD)** | v0.1 新加 | architecture-reviewer threat mode + threat-model-stride skill + `/sdlc:threat` |
| 4 | **Performance engineering / SLO / SLI** | v0.1 新加 | performance-analyst agent + `/sdlc:perf` |
| 5 | **Observability**(log / metric / trace / alert) | v0.1 新加 | observability-baseline skill + 嵌 architecture-reviewer / performance-analyst |
| 6 | **Dependency / SBOM / vuln scan / license** | v0.1 新加 | dependency-auditor agent + `/sdlc:deps` |
| 7 | **Migration / refactor patterns (strangler / parallel-run / blue-green)** | v0.1 新加 | migration-strategy skill + 嵌 architecture-reviewer + `/sdlc:migrate` |
| 8 | **Incident management / runbook / postmortem**(per CLAUDE.md §9) | v0.1 新加 | incident-responder agent + `/sdlc:incident` |
| 9 | **Tech debt tracking / budget**(每 sprint 给 refactor 预算) | v0.1 新加 | tech-debt-tracker agent + `/sdlc:debt` |
| 10 | **CI/CD pipeline 设计**(multi-stage / canary / feature flag) | v0.1 新加 | cicd-designer agent + `/sdlc:cicd` |
| 11 | **API design / versioning / deprecation**(SemVer policy + deprecation cycle) | v0.1 部分 | architecture-reviewer 含 API contract review;**v0.2** 加 api-versioning agent |
| 12 | **Data engineering / schema migration / ETL**(backfill / dual-write / cutover) | **v0.2** | (deferred — sdlc 与 data ops 边界单写) |
| 13 | **Onboarding / Developer Experience**(first-90-days / golden path) | v0.1 部分 | README+INSTALL+DEVELOP;**v0.2** 加 onboarding agent |
| 14 | **Code complexity / SOLID / cyclomatic** | v0.1 部分 | pr-reviewer 含;**v0.2** 加 code-metrics skill |
| 15 | **License compliance / SPDX** | v0.1 新加 | dependency-auditor 子职责 |
| 16 | **Feature flag / canary / progressive rollout** | v0.1 新加 | cicd-designer 子职责 |
| 17 | **Disaster recovery / backup-restore drill**(per CLAUDE.md §8.1) | **v0.2** | (deferred — 需 sysadmin 编排) |
| 18 | **i18n / l10n** | **v0.3** | (deferred — 场景特异) |
| 19 | **Compliance**(SOC2/GDPR/HIPAA/PCI) | **v0.3** | (deferred — 行业特异 + 外部审计依赖) |
| 20 | **Accessibility (a11y)**(WCAG/ARIA/semantic HTML) | **v0.3** | (deferred — UI-only project 才相关) |

**v0.1 覆盖率从 20% → 75%**(15 领域 built-in / 3 deferred v0.2 / 2 deferred v0.3 + 1 not applicable)。

### G.2 6 个新 SE agent 设计契约

#### G.2.1 architecture-reviewer (model_tier=opus)

**北极星**:每个新 component / 新数据流 / 新外部依赖 引入前必有 ADR + threat model;0 个 silent architecture decision。

**双角色**:
- **ADR producer**(`/sdlc:adr <decision-slug>` 触发):产 `docs/adr/<NNNN>-<title>.md`
- **Threat modeler**(`/sdlc:threat <component>` 触发):产 `docs/security/<component>-threat-model.md`
- **Migration strategist**(`/sdlc:migrate <pattern>` 触发):产 `docs/migrations/<date>-<slug>.md`,选 strangler-fig / parallel-run / blue-green / dark-launch 等

**Hard rules**:
- ADR 必含 5 节(Context / Decision / Status / Consequences / Alternatives considered)
- Threat model 必走 STRIDE 全 6 字母 + DFD diagram(ASCII OK)
- Migration plan 必含 reversibility analysis + rollback runbook
- Pre-Create Gate on docs/adr/ + docs/security/ + docs/migrations/
- 自评分入 handoff

**Output**:ADR markdown + threat model YAML + migration plan markdown

#### G.2.2 performance-analyst (model_tier=sonnet)

**北极星**:0 silent perf regression;每 release SLI/SLO 量化,unmeasured 性能 claim 拒绝。

**职责**:
- 定义 SLI / SLO(per service / per endpoint / per critical path)
- 设计 baseline benchmark(criterion / locust / k6 / wrk 之一,per stack)
- 检测 regression(对比上版本 +/- σ)
- 报告 budget burn-down

**Hard rules**:
- SLO 必含 4 项:metric + target + window + budget(e.g. "p99 latency < 500ms over 28 days, 0.1% budget")
- baseline 必含 multi-seed N=3
- regression 判据 = `current_p99 > baseline_p99 + 2σ` ⇒ FAIL
- 禁止 anecdotal claim("感觉变快了")
- 用 §6.3 evidence 纪律,raw run log 必引

**Output**:`reports/<date>-perf.md` + baseline YAML + SLO YAML

#### G.2.3 dependency-auditor (model_tier=haiku)

**北极星**:0 unpinned major dependency in release;0 known CVE >= High severity 流入 main;100% SPDX license tracked。

**职责**:
- SBOM 生成(`cargo audit / npm audit / pip-audit / govulncheck` per stack)
- Vuln scan(GHSA / CVE 库)
- License compliance(SPDX list / forbidden-list per org policy)
- Outdated detection(dep major behind > N → flag)

**Hard rules**:
- Block PR if CVE >= High in transitive dep
- License forbidden(GPL in commercial / unknown license)→ block
- 100% deps 必有 SPDX id 或 explicit "no-license" exception
- pin policy:production deps semver minor pin;dev deps可松

**Output**:`reports/<date>-deps.md`(SBOM + vuln + license + outdated 4 节)

#### G.2.4 tech-debt-tracker (model_tier=haiku)

**北极星**:0 untagged TODO/FIXME in main;每 sprint debt budget 报告(burn-down / burn-up)。

**职责**:
- Grep TODO/FIXME/HACK/XXX + verify each tagged owner + due date + reason
- Maintain `docs/tech-debt.md` 注册表
- Budget per sprint(debt-pay vs feature-build ratio,默认 20/80)
- Trend(月度 debt size)

**Hard rules**:
- TODO/FIXME 必带 `// TODO(@<owner>, <YYYY-MM-DD>): <reason + link to issue if any>` 格式
- 无 owner / 无 due → pr-reviewer 拒绝
- debt budget 超(实际 debt-pay < target)→ release 时 known limitations 列出

**Output**:`docs/tech-debt.md` + `reports/<date>-debt.md`(sprint burn-down)

#### G.2.5 incident-responder (model_tier=opus)

**北极星**:每次 SEV1/2 incident 24h 内有 postmortem 入库;5-Why 分析必完整;action item 必有 owner+deadline。

**职责**:
- Severity classify(SEV1-4)
- Runbook 起草(reproducible diagnose + fix steps)
- Postmortem 撰写(per CLAUDE.md §9.3 模板)
- Action item 跟踪

**Hard rules**:
- Postmortem 必含 7 节(Summary / Timeline / Impact / Root cause / Resolution / Lessons / Action items)
- Root cause 5-Why 必完整,**禁止**停在"code bug"
- Action item 必有 owner+deadline,无 owner = 永远不会做
- Postmortem 入 `docs/postmortems/<YYYY-MM-DD>-<slug>.md`

**Output**:postmortem markdown + runbook markdown + action item YAML 列表

#### G.2.6 cicd-designer (model_tier=sonnet)

**北极星**:接入任意 stack 仓 30 min 内能 generate CI/CD pipeline template;0 production push without CI gate。

**职责**:
- CI pipeline 设计(build → lint → test → security scan → publish)
- CD strategy 选(rolling / blue-green / canary / feature flag)
- Rollback playbook 起草
- 嵌入 dependency-auditor / performance-analyst gate

**Hard rules**:
- CI 每 stage 必有 fail criteria + retry policy
- CD 必有 rollback runbook
- Production deploy 必有 canary 或 blue-green(直接 rolling 仅允许 staging)
- Secrets 通过 vault 注入,不 hardcode

**Output**:`.github/workflows/<stack>.yml` / `.gitlab-ci.yml` / `Jenkinsfile` 模板 + `docs/cicd-strategy.md`

### G.3 3 个新 SE skill 设计契约

#### G.3.1 threat-model-stride

**Trigger**:architecture-reviewer threat mode OR `/sdlc:threat` invocation
**Steps**:
1. Load DFD(Data Flow Diagram)of target component
2. For each element(actor / process / data store / data flow)enumerate STRIDE threats:
   - **S**poofing identity
   - **T**ampering with data
   - **R**epudiation
   - **I**nformation disclosure
   - **D**enial of service
   - **E**levation of privilege
3. For each threat:assess likelihood × impact → risk score
4. For each risk ≥ Medium:propose mitigation
5. Output threat model YAML

#### G.3.2 observability-baseline

**Trigger**:implementer 或 releaser 涉及 service deploy 时 OR `/sdlc:obs` invocation
**Steps**:
1. Pick metrics framework(RED:Rate/Errors/Duration for request-driven;USE:Utilization/Saturation/Errors for resource-driven)
2. Define structured log schema(JSON / key=value)+ sampling策略
3. Define traces / spans + correlation IDs
4. Define alert thresholds + alert routing(PagerDuty / Slack)
5. Output observability spec YAML + sample Prometheus/Grafana config

#### G.3.3 migration-strategy

**Trigger**:architecture-reviewer migration mode OR `/sdlc:migrate <pattern>`
**Steps**:
1. Classify migration:schema / API / runtime / data
2. Pick pattern:
   - **Strangler-fig**:old & new coexist,gradual cutover
   - **Parallel-run**:new shadows old,compare outputs
   - **Blue-green**:atomic switch,instant rollback
   - **Dark-launch**:new code runs but output discarded,measure perf
   - **Feature-flag**:gradual enable per user cohort
3. Write migration plan:steps / data backfill / rollback / monitoring
4. Reversibility analysis:can we go back? cost?
5. Output migration plan markdown + cutover runbook

### G.4 Updated agent matrix(9 → 15 agents)

| # | Agent | Phase / Command | model_tier | 解决什么 |
|---|-------|-----------------|-----------|---------|
| 1 | task-orchestrator | meta / `/sdlc:status` | opus | SDLC 编排 |
| 2 | spec-analyst | `/sdlc:spec` | opus | 11 节 spec 起草 |
| 3 | architect | `/sdlc:plan` | opus | TDD plan + G1 challenger |
| 4 | implementer | `/sdlc:impl` | sonnet | TDD per-task per-commit |
| 5 | pr-reviewer | `/sdlc:review` | sonnet | 2 round review |
| 6 | tester | `/sdlc:test` | sonnet | 6 类 + multi-seed |
| 7 | releaser | `/sdlc:release` | opus | RC 4 gates + GA |
| 8 | docs-curator | `/sdlc:audit-docs` | haiku | docs whitelist |
| 9 | disk-monitor | `/sdlc:disk` | haiku | 3 mount audit |
| **10** | **architecture-reviewer** | `/sdlc:adr` `/sdlc:threat` `/sdlc:migrate` | **opus** | **ADR + threat model + migration plan** |
| **11** | **performance-analyst** | `/sdlc:perf` | **sonnet** | **SLI/SLO + regression** |
| **12** | **dependency-auditor** | `/sdlc:deps` | **haiku** | **SBOM + vuln + license** |
| **13** | **tech-debt-tracker** | `/sdlc:debt` | **haiku** | **TODO/FIXME 注册 + budget** |
| **14** | **incident-responder** | `/sdlc:incident` | **opus** | **runbook + postmortem (§9)** |
| **15** | **cicd-designer** | `/sdlc:cicd` | **sonnet** | **CI/CD pipeline + canary/blue-green** |

### G.5 Updated command matrix(9 → 17 commands)

| 命令 | 分发 agent | 用途 |
|------|-----------|------|
| `/sdlc:spec` | spec-analyst | 起草 spec |
| `/sdlc:plan` | architect | 出 plan |
| `/sdlc:impl` | implementer | 执行 plan |
| `/sdlc:review` | pr-reviewer | 2 round |
| `/sdlc:test` | tester | 6 类测试 |
| `/sdlc:release` | releaser | RC 4 gates |
| `/sdlc:audit-docs` | docs-curator | 文档审计 |
| `/sdlc:disk` | disk-monitor | 磁盘审计 |
| `/sdlc:status` | task-orchestrator | 状态查询 |
| **`/sdlc:adr <slug>`** | **architecture-reviewer** | **ADR 起草** |
| **`/sdlc:threat <component>`** | **architecture-reviewer** | **STRIDE threat model** |
| **`/sdlc:migrate <pattern>`** | **architecture-reviewer** | **迁移策略** |
| **`/sdlc:perf <target>`** | **performance-analyst** | **SLI/SLO + benchmark** |
| **`/sdlc:deps`** | **dependency-auditor** | **SBOM/vuln/license** |
| **`/sdlc:debt`** | **tech-debt-tracker** | **debt 注册 + budget** |
| **`/sdlc:incident <sev>`** | **incident-responder** | **runbook + postmortem** |
| **`/sdlc:cicd`** | **cicd-designer** | **CI/CD pipeline 设计** |

### G.6 Updated skill matrix(5 → 8 skills)

| Skill | 触发 | 用途 |
|-------|------|------|
| pre-create-gate | Write 前 | §1.1.7 3 问 |
| sprint-archival | sprint 完 | 删 plan / inline handoff |
| disk-self-audit | dispatch/build 前 | 3 mount redline |
| handoff-schema | phase 边界 | YAML 校验 |
| multi-agent-dispatch | ≥2 并行 | budget gate |
| **threat-model-stride** | architecture-reviewer 调用 | **STRIDE 6 字母穷举 + risk score** |
| **observability-baseline** | service deploy | **RED/USE + log/trace/alert 模板** |
| **migration-strategy** | architecture-reviewer 调用 | **strangler/parallel/blue-green/dark/flag 选型 + plan** |

### G.7 SE 风险登记(扩展 §11 R 系列,SE1-SE20)

| # | 风险 | 覆盖 agent | 缓解 |
|---|------|----------|------|
| SE1 | 新组件无 ADR silent decision | architecture-reviewer | spec → plan 必 ADR pass |
| SE2 | 新数据流无 threat model | architecture-reviewer + threat-model-stride | STRIDE 全 6 字母强制 |
| SE3 | Perf regression silent | performance-analyst | regression 判据 σ-quantitative |
| SE4 | Untracked tech debt 雪球 | tech-debt-tracker | TODO 格式强制 + budget burn-down |
| SE5 | Vuln dep ≥ High 入 main | dependency-auditor | PR block + CVE 数据库每日刷新 |
| SE6 | License 不合规 | dependency-auditor | SPDX 白名单 enforce |
| SE7 | Production 直推无 canary | cicd-designer | rolling-only 仅 staging 允许 |
| SE8 | Incident 后无 postmortem | incident-responder | 24h SLA + 7 节模板 |
| SE9 | Migration 不可回滚 | architecture-reviewer + migration-strategy | reversibility analysis 强制 |
| SE10 | 无 observability 上线 | observability-baseline | service deploy 必跑 skill |
| SE11 | SLO 不量化("感觉快") | performance-analyst | 拒绝 anecdotal claim |
| SE12 | API breaking change silent | architecture-reviewer | deprecation cycle 强制(v0.2 加 api-versioning agent) |
| SE13 | Secret 硬编码 / 不轮换(§1.4) | dependency-auditor | trufflehog/gitleaks 进 pre-commit;泄露走 §9.1 轮换 SOP |
| SE14 | 无 backup / restore 演练(数据丢失) | incident-responder | 周期 restore drill + evidence(§8.1);容器 trap cleanup(§4.3) |
| SE15 | Config/env 漂移、secret 进 config(非 12-factor) | project-onboarding + cicd-designer | config 外置 + secret 走 env(§1.4);make secrets-check 占位符自检 |
| SE16 | Flaky test 不隔离 / 无稳定性追踪 | tester | multi-seed N=3(§2.3);flaky quarantine;#[ignore] 突增 Gate2 拦 |
| SE17 | 可访问性 / i18n 未验证 | i18n | SDLC_LANG 本地化已覆盖;a11y 子项 planned深化(edge/web 版) |
| SE18 | 无 load / capacity / 资源耗尽测试 | performance-analyst + tester | capacity SLO;§6.1 "资源耗尽" 类必测 |
| SE19 | 文档漂移 / 无 doc audit | docs-curator | §1.1.2/§3.2 白名单 audit(/sdlc:audit-docs) |
| SE20 | 供应链 provenance / 无 SBOM | dependency-auditor | SBOM 生成;dep/submodule commit-pin(§8.1) |
| SE21 | 无 error-code 编号 taxonomy(error 散落字面量 / 不稳定 / 无文档,调用方无法据码判别) | architecture-reviewer + observability-baseline | 项目须有**文档化、稳定、编号**的 error/return-code 体系(如 nginx return codes / bluez error enums);spec §7 设计 error-code 表;reviewer 检查存在性 + 稳定性;无 → 标缺失 |
| SE22 | 无结构化/分级日志(裸 print 散落,无 level/timestamp/error-code 关联,不可 grep/不可关联) | observability-baseline + pr-reviewer/codebase-reviewer | 项目须有**结构化分级日志**(level + 时间戳 + 关联 error-code);**不止 request-service** —— 库/daemon/CLI 同样要(如 nginx `error_log` 分级 / bluez 结构化);observability-baseline 给 schema;reviewer 检查 |
| SE23 | commit 纪律差(碎 `wip/fix` churn 直推 / 压成 milestone 大 blob / message 无 body / 历史不可读) | pr-reviewer | commit **原子 + 有意义**(学 kernel/gcc patch-series);message 祈使句 subject + body 讲 WHY;推公开 main 前 `rebase -i` 收拾成原子序列(§4.2.4);reviewer 检查 commit 质量,既反碎 churn 也反过度 squash |

---

## Spec 评审请求

请就以下决策点确认或修正:

1. **plugin 名**:`sdlc-orchestrator` ✓?
2. **落点**:仓在 `<repo>/`,plugin install 到 `~/.claude/plugins/sdlc-orchestrator/` ✓?
3. **v0.1.0 范围**:§2.1 / §2.2 边界划得对?有要加 / 拿掉的?
4. **三 hook 阻断 vs 警告**:默认 warn (exit 1),strict mode 才 block (exit 2) — 是否合理?
5. **stack adapter**:rust/ts/python/go/generic 5 个够吗?需要加 cpp / kotlin?
6. **handoff schema_version 1**:YAML 字段命名是否合你直觉?
7. **disk redline 默认值**:root/data 50G,要不要按 / 当前 20G 紧迫度调更低保底?
8. **R18 agent .md 落档**:已纳入 `dispatch-template.md` 强制 → 是否还有遗漏的"R 系列教训"要补?
9. **examples/hello-world**:Rust toy 合适吗?(若想换 TS / Python 我改)
10. **self-hosting**:plugin 自己用 plugin 流程开发 — 是否过严(可能 chicken-and-egg)?

评审通过后我才走下一步:`superpowers:writing-plans` 出 implementation plan。
