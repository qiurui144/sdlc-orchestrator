# sdlc-orchestrator

> [English](./README.md)

![ci](https://github.com/qiurui144/sdlc-orchestrator/actions/workflows/ci.yml/badge.svg)

面向 Claude Code 的、与技术栈无关的 SDLC 编排插件:**18 个 agent、28 个 skill、30 个斜杠命令、
3 个 hook**。驱动 `spec → plan → impl → review → test → release` 全链,外加常见软件工程实践
(ADR、威胁建模、性能、依赖、技术债、事故、CI/CD),并把项目 CLAUDE.md 的规则**以结构强制**落地。

---

## 它做什么

AI 辅助开发把整个 SDLC 压进一个会话,极易产生可预测的反模式。本插件把每个阶段接到一个
会建设性阻止这些反模式的 agent —— 例如:

- **Spec 漂移** —— spec(11 节)未批准前阻断实现。
- **多 agent 撑爆磁盘** —— 任何 build/test 命令前做磁盘红线守卫。
- **agent 自报 PASS** —— handoff 必须有落盘报告 + `self_score`,不认 chat 文本。
- **docs/ 膨胀** —— 每个新文件过 Pre-Create Gate(重复?一次性?在白名单?)。

完整动机与设计见 [DEVELOP.md](./DEVELOP.md) 以及 `docs/adr/` 下的架构决策记录。

---

## 安装

本仓库本身既是插件、也是 marketplace。

```bash
# 1. 把仓库注册为 marketplace(本地路径或 git URL)
claude plugin marketplace add /path/to/sdlc-orchestrator
# 2. 安装 + 启用,然后重启 Claude Code 加载
claude plugin install sdlc-orchestrator@sdlc-orchestrator
```

- **单次会话试用(不安装):** `claude --plugin-dir /path/to/sdlc-orchestrator`
- **更新本地安装:** `claude plugin marketplace update sdlc-orchestrator && claude plugin update sdlc-orchestrator@sdlc-orchestrator` —— 然后重启(组件重载需新会话)。
- **核验:** `claude plugin validate /path/to/sdlc-orchestrator` 与 `claude plugin details sdlc-orchestrator`。

---

## 用法

**1. 接入一个项目(每仓一次):**

```
/sdlc:onboard    # 检测栈、建 docs/superpowers/ + .sdlc/、物化模板与 stack adapter(幂等)
/sdlc:doctor     # 体检接线 → READY 或列出待修项
```

**2. 跑一个 feature 的完整链(显式,每步可审):**

```
/sdlc:spec <slug>  →  /sdlc:plan  →  /sdlc:impl  →  /sdlc:review  →  /sdlc:test  →  /sdlc:release
```

或用 `/sdlc:run` 驱动全链,在每个 Challenger 门(G1–G4)后暂停等待人工确认,并在 GA 打 tag 前硬停止:

```
/sdlc:run <slug>   # 半托管模式:在 G1/G2/G3/G4 及 GA tag 前暂停
```

**3. 单点工具(随时,不必走全链):**
`/sdlc:cost --sprint` · `/sdlc:status` · `/sdlc:adr` · `/sdlc:threat` · `/sdlc:deps` · `/sdlc:debt`
· `/sdlc:perf` · `/sdlc:incident` · `/sdlc:cicd` · `/sdlc:migrate` · `/sdlc:audit-docs` · `/sdlc:disk` · `/sdlc:eval` · `/sdlc:intake`

---

## 自动 vs 显式

| 层 | 触发 | 内容 |
|----|------|------|
| **Hooks** | 🟢 全自动,无需操作 | `PreToolUse:Bash` build/test 前磁盘红线守卫 · `PostToolUse:Write` 新文件过 Pre-Create Gate · `Stop` 磁盘自查 + sprint 完成归档建议 |
| **守卫类 skill** | 🟡 Claude 在相关场景自动考虑 | `pre-create-gate`、`disk-self-audit`、`multi-agent-dispatch` |
| **SDLC 全链** | 🔴 你显式 `/sdlc:*` | `spec → release` 及所有单点命令 |

Hooks 一经启用即**全局生效**(任何会话/目录)。全链是**有意做成手动**的 —— 它会派发
opus/sonnet 子代理、花真 token,绝不应自动触发。先 `/sdlc:cost --sprint` 看估算。

---

## 命令

| 命令 | Agent(tier) | 说明 |
|------|-------------|------|
| `/sdlc:onboard` · `/sdlc:doctor` | project-onboarding | 接入仓库 / 体检接线(零 LLM,幂等) |
| `/sdlc:cost` | cost-estimation | 零 LLM 估算某阶段或整 sprint 的 token + USD |
| `/sdlc:spec` | spec-analyst (opus) | 11 节 spec;未批准前阻断 impl |
| `/sdlc:plan` | architect (opus) | G1 挑战 + 从已批准 spec 出 TDD plan |
| `/sdlc:impl` | implementer (sonnet) | 按 plan 执行,TDD,逐任务 commit |
| `/sdlc:review` | pr-reviewer (sonnet) | 2 轮 review(G3 门) |
| `/sdlc:test` | tester (sonnet) | 6 类矩阵 + 多 seed(G4 门) |
| `/sdlc:release` | releaser (opus) | RC 4 门 + 本机部署验证 + 打 tag |
| `/sdlc:adr` · `/sdlc:threat` · `/sdlc:migrate` | architecture-reviewer (opus) | ADR · STRIDE 威胁建模 · 迁移方案 |
| `/sdlc:perf` | performance-analyst | SLI/SLO + bench + 2σ 回归 |
| `/sdlc:deps` · `/sdlc:debt` | dependency-auditor · tech-debt-tracker (haiku) | SBOM/CVE/license · TODO/FIXME 登记 |
| `/sdlc:incident` · `/sdlc:cicd` | incident-responder (opus) · cicd-designer | 运行手册 + 复盘 · CI/CD + 灰度 + 回滚 |
| `/sdlc:audit-docs` · `/sdlc:disk` | docs-curator · disk-monitor (haiku) | §3.2 文档审计 · 三盘审 |
| `/sdlc:status` · `/sdlc:eval` | task-orchestrator | sprint 状态 · agent 行为评测 |
| `/sdlc:intake` | intake-orchestrator (opus) | 一键全面检查 → 项目健康度评分卡(light/standard/deep) |
| `/sdlc:pipeline` · `/sdlc:merge-queue` | pipeline-emit · merge-queue | 确定性 CI-yaml 生成 · 跨 feature 串行 merge + merge 时定版本/tag(§7.1.7) |
| `/sdlc:hw-verify` | hardware-verify | SSH 边缘设备部署验证(把 §7.3 本机部署验证扩到硬件) |
| `/sdlc:web-ui-verify` | web-ui-verify | web-UI 真浏览器渲染验证(§2.2/§6.4/§7.3):detect-web-stack + MCP 探针 + 按路由 success-contract 判定(PASS/FAIL/UI-UNVERIFIED);MCP 可选,真 E2E PENDING-VERIFY |
| `/sdlc:ui-vision-judge` | ui-vision-judge | provider-agnostic 截图视觉判断(OpenAI-compat `SDLC_VISION_*` env):软注解,永不作判定(deterministic-verdict-supremacy);未配置则降级 `unavailable`;真 provider + 多 tier 矩阵 PENDING-VERIFY |
| `/sdlc:web-ui-quality` | web-ui-quality | web-UI 质量门(在 UI-1-PASS 页面上):a11y WCAG 2.1 AA / 视觉回归 / 响应式 / Lighthouse CWV;确定性判定,ui-vision-judge 仅旁注;真 chrome-devtools-mcp 读取 PENDING-VERIFY |
| `/sdlc:promote` | task-orchestrator(内联) | develop→main(#14):断言 main-bound commit 的 CI 绿(`--require-known` → UNKNOWN 拦)+ 已打 tag,再 `--no-ff` merge |
| `/sdlc:run` | task-orchestrator (opus) | 驱动全链,每个 Challenger 门(G1–G4)后暂停等待人工确认 + GA 硬停止 |

**drive 自动跑的门(是能力,不是单独命令):**
- **doc-audit 内容门**(v0.24)—— release 门跑 `doc-audit.sh --strict`:计数 vs 文件系统 + `/sdlc:` 命令引用完整性 + canonical-version 锚(经 `ci.yml` 也是 CI 硬门)。
- **CI-green 门**(v0.25)—— `ci-status.sh`(绑 commit 的 `gh run` 判定)在 REVIEW(UNKNOWN 警告)与 release/`promote` tag(`--require-known` → UNKNOWN 拦;别的分支的绿 run 不会读成 PASS)处把关。
- **有边界 auto-remediation**(v0.25.1)—— 红 CI 时 drive 自动 dispatch `ci-remediator`,只自动修 3 个可逆类(fmt / deny-license-allow / doc-sync),每个都经零-LLM `diff-guard` 对真实 staged diff 授权(任何碰 test/CI-yaml/弱化断言 → revert + 升级);test/逻辑/安全 advisory 失败一律升级人工。

自动识别栈:Rust / TypeScript / Python / Go / generic(`Cargo.toml`、`package.json`、
`pyproject.toml`·`requirements.txt`、`go.mod`);构建 module 在子目录(如 Go 后端在 `go/`)也能识别(v0.23)。agent 用 adapter 的命令,不硬编码字面量。

---

## 配置(可选)

`/sdlc:onboard` 会在目标仓播种以下两者:

- **`.claude/sdlc-orchestrator.local.md`**(YAML frontmatter)—— 模型 tier 覆盖、`token_budget`、`multi_agent_max_parallel`。
- **`.sdlc/disk.conf`**(`KEY=VALUE`)—— 磁盘守卫读取的**唯一**配置面。键:`redline_root_gb` / `redline_data_gb` / `redline_tmp_gb`。优先级:环境变量 > 项目 `.sdlc/disk.conf` > `~/.config/sdlc-orchestrator/disk.conf` > 内置 `50/50/5`。

---

## 状态

各版本的组件计数（agent / skill / 命令 / hook / adapter）见
[RELEASE.md](./RELEASE.md) —— 版本历史的唯一真相源（SSOT）。
当前构建的概要见本 README 顶部。

- [RELEASE.md](./RELEASE.md) —— 版本历史
- [DEVELOP.md](./DEVELOP.md) —— 架构、agent/skill/hook 内部、贡献指南
- [docs/adr/](./docs/adr/) —— 架构决策记录（设计理由）
