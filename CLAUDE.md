# CLAUDE.md — sdlc-orchestrator plugin

> AI working instructions specific to this plugin repo. Inherits global CLAUDE.md
> at `~/.claude/CLAUDE.md`. When in conflict, this file wins over global defaults,
> which win over built-in defaults.

---

## Project identity

- **Name**: sdlc-orchestrator
- **Type**: Claude Code plugin (markdown + bash + yaml — no compiled code)
- **Purpose**: automate CLAUDE.md global SDLC rules across spec → plan → impl → review → test → release
- **Stack**: bash (POSIX) + bats + yq + jq
- **License**: MIT
- **Repo**: `~/.claude/plugins/sdlc-orchestrator` (or wherever you cloned it)

---

## North star

接入任意空仓后 30 min 内能从 `/sdlc:spec hello` 跑到 `/sdlc:release v0.1.0` 全链通。

This means: stack detection works, all 9 agents load, all 5 skills fire, handoff
YAMLs are emitted and validated, the RC 4 gates pass, and the Stop hook archives
the plan. If any step requires manual intervention not described in the README,
it is a bug.

---

## Hard constraints

1. **No business coupling** — agents/skills/commands use generic terms only.
   `spec-analyst` is correct; `myapp-spec-analyst` is forbidden.
   Stack adapters reference config files, never project-specific tool versions.

2. **Self-hosting** — this plugin's own development must use its own SDLC commands.
   Eat your own dogfood: `/sdlc:spec`, `/sdlc:plan`, `/sdlc:impl`, `/sdlc:review`, `/sdlc:test`, `/sdlc:release`.

3. **Keep artifacts inside the repo** — never write build / node_modules / target to `/`.
   Per §1.1.6, disk audit fires before builds; clean up worktrees after use.

4. **No external services** — file-based only. No DB, no Redis, no SaaS, no HTTP
   calls inside agents or skills.

5. **POSIX bash only** — every `.sh` must pass `shellcheck` with no warnings.
   No bashisms beyond arrays. Test on macOS bash 3.2 before claiming "works".

6. **Every agent has model_tier** — Appendix D.3 rule (added in T15/v2 retro).
   Agents without `model_tier` frontmatter fail to load; no silent defaults.

7. **Every producer agent self_scores in handoff** — `self_score` block with
   `rubric_ref` is mandatory. The G1 Challenger verifies against Appendix E.

8. **Pre-Create Gate applies to this repo too** — self-hosting means we eat the
   gate. Before any Write of a new `.md` file, the 3 questions apply:
   (1) duplicate? (2) one-shot sprint artifact? (3) whitelist match?

---

## Anti-patterns specific to this repo

- **Hardcoding tool versions in stack adapters** — `stack-rust.yaml` must not say
  `rustc 1.78.0`; it says `cargo test`. Versions change; the adapter must not.

- **Writing `cargo`/`npm` literals inside agent `.md` files** — all build commands
  come from `config/stack-*.yaml` at dispatch time. Hardcoding `cargo build` in
  an agent prompt means the agent breaks for non-Rust repos.

- **A hook referencing a non-existent skill** — broken references cause the hook
  to silently no-op. After adding a hook entry in `hooks/hooks.json`, always verify
  the skill path exists with `ls skills/<name>/`.

- **Bypassing Pre-Create Gate for "my own plan file"** — the gate exists for all
  files including plans and specs in this repo. There are no exceptions for
  "I know what I'm doing." The gate is 3 grep/ls commands; it takes 5 seconds.

- **All-haiku tier** — picking haiku for all agents to save cost is wrong.
  Appendix D is explicit: design tasks (spec, plan, release) require opus.
  Downgrading spec-analyst to haiku produces 11-section specs that fail rubric E.1.

- **Agent `.md` < 250 lines** — rubric E.2 requires structural depth. An agent
  that is 80 lines is a stub, not a production agent. Expand Purpose, Instructions,
  edge cases, and Handoff schema before merging.

- **Committing a plan file without deleting it after completion** — plan lifecycle
  rule (§3.2): plans are deleted by sprint-archival when all tasks are committed.
  A plan file that survives a completed sprint is undead; delete it.

- **Adding a stack adapter that monkey-patches another project's config** — adapters
  are read-only references to the target project's config. They must not write to
  the target repo's files.

- **`set -o pipefail` + an intentional early pipe close = flaky SIGPIPE** (SE16 — the v0.17
  flake). `printf "$x" | grep -q P` (grep matches early) and `… | head -n N` (head exits at N)
  CLOSE the pipe before the producer finishes → the producer gets SIGPIPE → under `pipefail` the
  pipeline exits 141 → a RACE that fails intermittently (worse under load). Never use an
  early-closing consumer on the right of a pipefail pipe for control flow. Use a no-pipe form:
  `case "$x" in *P*) ;; *) … ;; esac` instead of `grep -q`; `awk 'NR<=N'` (reads to EOF) instead
  of `head -n N`. (Single-match `grep | head -1` is low-risk: the producer hits EOF before head
  closes.) Verify any "is it flaky?" claim by stress-running ≥20×, not once (§2.3 multi-seed).

### SE-practice anti-patterns (Appendix G expansion)

> 完整 SE 风险登记 = **SE1–SE23**(主 spec Appendix G.7);以下列出代表性反模式。SE13–SE20
> (secrets/backup-drill/config-drift/flaky/a11y/load/doc-drift/SBOM)v0.15 定义补齐;**SE21–SE23
> (error-code 编号 / 结构化分级日志 / commit 纪律 —— 学 nginx/bluez/kernel/gcc 的软件项目质量要求)v0.22 补齐**。

- **Skipping ADR for new component** (SE1) — every new long-lived component, library
  dependency, or architectural divergence requires an ADR via `/sdlc:adr`. "It's
  obvious" is not a reason; six months later it won't be.

- **STRIDE letters incomplete** (SE2) — threat model output must enumerate all six
  STRIDE letters (Spoofing / Tampering / Repudiation / Information disclosure /
  Denial of service / Elevation of privilege). Omitting any letter without explicit
  "N/A — reason" is a fail.

- **Anecdotal perf claims without bench** (SE11) — "feels faster" / "should be
  faster" / "compiler probably optimizes this" are not measurements. `/sdlc:perf`
  requires SLI/SLO baseline + N≥3-seed bench + 2σ regression check before any perf
  claim ships.

- **TODO/FIXME without owner+due** (SE4) — every debt marker must follow
  `// TODO(@<owner>, YYYY-MM-DD): <reason> [#<issue>]`. Untagged debt accumulates
  forever; `/sdlc:debt` blocks PRs that introduce untagged markers.

- **Incident closed without 5-Why descent** (SE8) — postmortem must walk root cause
  through five "why" levels minimum; stopping at "the code had a bug" is not a root
  cause. Same incident class will recur.

- **Production rolling deploy without canary** (SE7) — production deploys require
  canary or blue-green per `/sdlc:cicd`. "Just push to prod" is not a deploy
  strategy; rollback runbook is mandatory.

---

## Linked specs and docs

| Document | Path |
|----------|------|
| Architecture Decision Records | `docs/adr/` |
| Global CLAUDE.md | `~/.claude/CLAUDE.md` |
| Appendix E rubrics | `DEVELOP.md` §Appendix E |
| Appendix D model tiering | `DEVELOP.md` §Appendix D |
| DEVELOP.md (contributor guide) | `DEVELOP.md` (this repo root) |
| README (user-facing) | `README.md` + `README.zh.md` |
| RELEASE notes | `RELEASE.md` |

---

## Version roadmap

> Shipped through **v1.2.0** (2026-06-13): 18 agents, 30 commands, 28 skills, 3 hook entries (5 scripts).
> v1.0.0 GA rolled up ui-vision-judge + web-ui quality gates + multi-model-routing M1 (provider layer, opt-in).
> **v1.2.0** adds cost-measurement (C-1): real `usage`-token capture + `cost.sh --compare` that prints a
> measured-vs-estimated routing net (null≠0 honest, coverage-tagged) — closing M2's "savings unmeasured" gap.
> **v1.1.0** adds multi-model-routing **M2** (eval-gated routing): the `model-eval` skill + a closed
> task-type map → eval-proven allowlist → online correctness oracle → circuit breaker, so deepseek can
> auto-handle one mechanically-verifiable task type under `SDLC_MULTI_MODEL=1` (opt-in). See RELEASE.md.
> `/sdlc:run` full-chain DRIVE; `/sdlc:intake` inspection; SE1–SE23 risk register; concurrency foundation +
> Challenger Panel (v0.9) + impl-DAG worktree-per-task (v0.10) + cross-feature merge-queue (v0.11)
> + background-job registry / async dispatch (v0.12) + i18n SDLC_LANG layer (v0.13) + handoff
> schema v2 (v0.14). Per-version: RELEASE.md.

### Editions (corrected 2026-06-03 — drop cross-project coupling, Hard constraint #1)

sdlc-orchestrator is a **standalone Claude Code plugin**. **两个 plugin-native edition** 共享并行
内核:**Personal**(插件直装,Track-1 已到 GA candidate)/ **Edge·HW-Verify**(SSH 验证软件部署
到指定硬件)。

**❌ 撤回"Enterprise = cloud 接入"版**:pluginhub / official-web / wiki-web / llm-gateway /
accounts / `make deploy` 属 **cloud 项目,与本插件无关** —— 旧 product-matrix spec 的"复用 cloud
栈"是**跨项目错觉**(违 Hard constraint #1),撤回。若需企业级"多 repo 编排",作**插件原生通用
能力**(复用 v0.11 merge-queue 原语),**不接 cloud / 不碰 pluginhub**。
(旧 spec `specs/2026-06-02-product-matrix-roadmap.md` 的 cloud-接入章节据此作废。)

### Track 1 — Personal to v1.0 GA (serial main line)

| Version | Theme | Status |
|---------|-------|--------|
| v0.9.0 | 并发地基 + fan-out + Challenger panel (consensus-auto 降人机交互) | **shipped 2026-06-02** |
| v0.10.0 | 并行实现 impl-DAG (worktree-per-task) | **shipped 2026-06-02** |
| v0.11.0 | 跨 feature 编排 (worktree-per-feature + 串行 tag merge-queue + 多 repo 雏形) | **shipped 2026-06-02** |
| v0.12.0 | 后台/异步审计 (run_in_background) | **shipped 2026-06-02** |
| v0.13.0 | i18n / 中文交互层 (SDLC_LANG=zh\|en\|bilingual) | **shipped 2026-06-02** |
| v0.14.0 | handoff schema v2 (producer + model_tier + self_score 边界校验) | **shipped 2026-06-02** |
| v0.15.0 | SE13–SE20 定义补齐 (SE 风险登记 12→20,清诚信缺口) | **shipped 2026-06-02** |
| v0.16.0 | /sdlc:pipeline (确定性 stack-config CI yaml emitter,补 cicd-designer) | **shipped 2026-06-02** |
| v0.17.0 | 多组件并行**自动触发**增强(③,conservative;auto-fanout)| **shipped 2026-06-03** |
| v0.17.1 | panel high-risk 分类器校准(去 `${{ secrets }}`/LLM-token/schema wrong-sense 误报 + 修 'breaking API' 漏报;SE16-safe `grep -c`)| **shipped 2026-06-03** |
| v0.18.0 | **harness 强制 GA 门**(`ga-tag-guard` PreToolUse hook:major GA tag = harness 硬停,补"门是 prompt 固化非 harness 强制"弱点)| **shipped 2026-06-03** |
| v0.19.0 | Edge·HW-Verify(②,GA 前):`hardware-verify` skill + `/sdlc:hw-verify`(确定性层 stub-ssh 验证)| **scaffold shipped 2026-06-03**;真硬件 E2E PENDING-VERIFY(§7.3 需真设备) |
| v0.19.1 | hygiene:shellcheck+doc-audit 进 CI + `scripts/doc-audit.sh` + 自治理(删 undead plan / untrack reports) | **shipped 2026-06-04** |
| v0.20.0 | 指定项目目录:`SDLC_PROJECT_ROOT` + `/sdlc:run --project <dir>`(母目录跑指定子项目) | **shipped 2026-06-04** |
| v0.21.0 | **密钥+文件权限卫生(SE13 owner)**:`secret-scan` skill + `secret-guard` 提交/推送拦截 hook + 并入 /sdlc:deps + intake secrets 维度 | **shipped 2026-06-04** |
| v0.22.0 | **软件项目质量要求**(用户澄清=对被管理项目的要求,非给插件脚本编号):SE21 error 编号 taxonomy + SE22 结构化分级日志(含库/daemon)+ SE23 commit 纪律(kernel/gcc 原子提交);接 observability-baseline + codebase-reviewer + SE 登记 | **shipped 2026-06-04** |
| v0.23.0 | **跨项目 dogfood 加固**(driving 全链于真实下游项目真挖出):detect-stack 子目录下钻 + `--module-dir`(子目录 module 不再误判 generic)+ onboard cd-prefix + state.module_dir;`--project`/`SDLC_PROJECT_ROOT` 扩到 granular 命令(spec/plan/impl/review/test);修复 v0.21 漏更新的 intake spine e2e(7→8 维)。suite 389→399 | **shipped 2026-06-05** |
| v0.24.0 | **内容感知 doc-audit 门**(self-enforce doc-sync;v0.23 文档漂移真挖出):doc-audit.sh 加 3 个零误报内容检查([6] inventory 计数 vs FS + [7] /sdlc: command-ref 完整 + [8] canonical-version anchor),挂 `--strict` → CI 硬门;接 releaser/docs-curator(E2)。诚实标:prose 能力漂移机械不可抓,留 §7.2 review + docs-curator 兜底。suite 402→419 | **shipped 2026-06-05** |
| v0.25.0 | **CI-green 门 + 有边界 auto-remediation**(#13/#14;真实托管仓库 CI 红 12 天真挖出):`ci-status.sh`(gh run **绑 commit-SHA** 判定、reduce 所有 checks,red 不再读成绿)+ 接 releaser/pr-reviewer/`/sdlc:promote`(红→拦,tag gate 默认 require-known)+ **确定性 zero-LLM diff-guard**(A1=whitespace-only 不变量 + 广谱测试检测;auto-fix 仅 A1/A3/A4,绝不碰 test/CI-yaml/删断言/中和)。**G3 双验收对抗岗 BLOCK(CI 门没绑 commit + 安全核心可中和绕过)→ 重设计 → re-G3 逐条复跑闭环**。suite 419→506 | **shipped 2026-06-05** |
| v0.26.0 | **doc-audit 反向门**(本会话文档漂移真挖出 v0.24 门两盲点):[9] 命令列表完整性(commands/ 每个须在 README 被列,反向 [7])+ [10] 双语计数 parity(README.zh tuple == README.md == FS,§1.1.3);plugin-self gated、零误报、exemption 走 `.sdlc/doc-audit-allow`。suite 506→521 | **shipped 2026-06-05** |
| v0.27.0 | **accurate-fast A3**(准而快):parallel-by-default(config flip on shipped impl-DAG v0.10)+ spot-check-don't-full-re-run(producer-self_score'd artifact;HIGH/missing→full;net 永不 spot-check)。零准确性风险。G1 5→3 lens 抓 3 真问题(A1/A2 不可控、命令执行 bypass、docs/*.py denylist);`/sdlc:eval` 行为门 PENDING(无 fixture,§6.3)| **shipped 2026-06-06** |
| v0.28.0 | **accurate-fast B**(准而快):确定性 zero-LLM `risk-classify.sh` → 按改动风险跳过低风险的慢 LLM ceremony(default-deny 正向 basename allowlist;命令承载 config 永不 LOW;11-fixture evasion 套件 BLOCKING + adversarial-reviewer G3)| **shipped 2026-06-06** |
| v0.29.0 | **web-ui UI-1**:`web-ui-verify` skill — §2.2/§6.4/§7.3 真浏览器渲染验证(detect-web-stack + 可选 Playwright-MCP 探针降级→UI-UNVERIFIED + §6.4 lint + 按路由 success-contract verdict,blank→FAIL,fail-closed exit 7);18-fixture evasion BLOCKING + 2-round adversarial G3(抓 false-green keystone + empty-text P0)。真浏览器 E2E PENDING-VERIFY | **shipped 2026-06-08** |
| v0.30.0 | **ui-vision-judge**:provider-agnostic 视觉理解后端(OpenAI-compat env;§4.5 schema-guided/retry-validate/redact/degrade)+ UI-1 browser-judge retrofit(vision 注解 rides alongside,verdict 逻辑字节冻结 vs v0.29.0);deterministic-verdict-supremacy(vision 永不入判定)。真 provider + 多 tier 矩阵 PENDING-VERIFY | **shipped 2026-06-10** |
| v0.31.0 | **web-ui UI-2**:质量门 a11y(lighthouse WCAG 2.1 AA)/ 视觉回归(diff-ratio+max-region,vision 旁注)/ 响应式(overflow+bbox 真布局)/ perf(trace CWV mean-vs-SLO,FAIL>NOISY);新 web-ui-quality skill + /sdlc:web-ui-quality;UI-1 引擎字节冻结;deterministic-verdict-supremacy。G1 panel BLOCK(6)→fix→PASS;G2 CONCERNS(C-1 perf-noise-masks-FAIL/I-1 write-baseline 接线/I-2 a11y 序数门/I-3 per-commit-green)→fix。真 chrome-devtools-mcp 读取 PENDING-VERIFY | **shipped 2026-06-10** |
| v0.32.0 | **web-ui UI-3**:frontend-design 接入 impl(UI-task 规则);消费 ui-vision-judge | planned |
| v0.33.0 | superpowers 互通:已有 plan adoption(不重生成)+ 归档只删自建 + DEVELOP 映射/切换说明 | planned |
| v0.34.0 | 让并行"看得见+强制":dispatch manifest → `runs/<ts>/dispatch.json` + 断言 inflight==N 测试 + 诚实声明 | planned |
| v0.35.0 | 质量治理:**双岗位双验收**(§5.2.0b)+ **agent did-vs-said 打分**(#7,扩 /sdlc:eval + R18)+ **显式记忆链**(#8) | planned(governance) |
| v1.0.0 | 个人版 GA (RC 四节门 §7.2 + 本机部署验证 §7.3 + 北极星 30min 全链;**GA tag 人工硬停**;含 ②③)| planned |

### ②③ 详情(用户 2026-06-03:GA 前,已并入 Track-1;③=v0.17、harness-门=v0.18、②=v0.19)

- **v0.17.0 ③ 多组件并行自动触发增强**:orchestrator **自动识别**无依赖的组件/审计/feature 并
  **自动 fan-out 触发**(强化 v0.9 dispatch-batch + v0.10 DAG 解析 + v0.12 async),减少人工逐个编排。
  scope 待定(保守:自动 fan-out 已知独立单元 / 激进:自动依赖分析 + 跨 feature 调度)。
- **v0.18.0 harness 强制 GA 门(shipped)**:`hooks/ga-tag-guard.sh`(PreToolUse:Bash)—— major GA
  tag(`vN.0.0`,无 pre-release 后缀)在 sdlc-gated repo 中**被 harness 硬拦**(exit 2),除非
  `SDLC_GA_APPROVED=1` 或 `.sdlc/ga-approved`。把 §7.2 "GA tag 人工硬停" 从 prompt 规则升为 harness
  不变量(补竞品评估指出的 #1 弱点)。非侵入:非 GA tag / pre-release / 非 sdlc repo → no-op。
- **v0.19.0 ② Edge·HW-Verify(scaffold shipped)**:`skills/hardware-verify/verify.sh`(SSH §4.4
  scp+nohup+`ssh cat log` + 部署验证 §7.3 + `devices/<dev>/` §8.2 IP/密码走 env)+ `/sdlc:hw-verify
  <device>`。**确定性层**(dry-run / 判据
  解析 / verdict PASS-FAIL-TIMEOUT / 传输-鉴权错误 / secret 脱敏)= 12 stub-ssh 测试已验证;**真硬件
  E2E = PENDING-VERIFY**(mock≠real §7.3,需真设备 + SSH 触达)。v.next:`health.port` 探针 +
  `hardware-deploy-verifier` agent(解释真日志)。

~~ent-v1.0(cloud/pluginhub 接入)~~ **撤回**(跨项目错觉,Hard constraint #1;归 cloud 项目)。
各 minor 走各自 §3.1 spec→plan→impl。「进一步评估优化」= 每版重跑 `/sdlc:eval` 行为回归(§7.2 Gate 2)。
