---
name: ci-green-gate
version: v0.2.0-spec
status: G3-REMEDIATED (impl 2026-06-05; addressed G3 adversarial BLOCK C1/C2/C3/C4 + W4. C1 — verdict bound to commit SHA via `git rev-parse` + `gh run list -c`; C2 — reduce over ALL checks; C3 — token-count REMOVED, A1=whitespace-only invariant, A2 lint-autofix DROPPED (4→3 auto-fix classes); C4 — test detection broadened across Go/Py/Java/JS/C# (path+content); W4 — deny-classify case-insensitive + empty-log→ESCALATE. Prior: G1-REVISED rev2 (B1/B2/B3))
g1_review_ref: docs/superpowers/specs/2026-06-05-ci-green-gate.G1-review.md
revision_summary: "B1 — added deterministic zero-LLM post-fix diff-guard (component 4, skills/ci-status/diff-guard.sh) as MANDATORY: inspects real `git diff --cached`, rejects test-touch/skip-ignore/assert-removal/CI-yaml/footprint-overrun → revert+ESCALATE (§3/§5/§7/§9 REAL-diff tests). B2 — A3 license-vs-advisory now a deterministic pre-gate on cargo-deny output class, advisory/RUSTSEC → ESCALATE-security BEFORE the LLM; A3 footprint = [licenses].allow append only (§2/§3/§5/§7). B3 — --require-known (UNKNOWN→BLOCK) PINNED as default at releaser RC gate + /sdlc:promote (irreversible), WARN-default kept on pr-reviewer/dev (reversible); asymmetry justified by reversibility (§2/§3/§5/§7/§10/§11). Nits: N1 releaser rule 12/130-145 cited precisely; N2 run-view --log-failed mock; N3 rerun=re-query same run id; N4 META counts pinned (agents 17→18, commands 26→27, skills 20→21)."
date: 2026-06-05
authors: qiurui144 + Claude
template_version: fallback-CLAUDE.md-§3.1 (no .sdlc/templates/spec-template.md present in repo — used canonical 11-section structure per spec-analyst hard rule 11 / failure-mode 2)
---

# Spec: ci-green-gate (+ bounded auto-remediation)

> Make "GitHub CI is green" a **checkable, harness/gate-enforced** invariant in the SDLC,
> with a **conservative, bounded auto-remediation loop** for a tiny allowlist of reversible
> infra failures and **mandatory human-escalation for everything else** (tests, logic,
> security, mid-refactor compile errors). This is the **#13 (CI hard gate) / #14 (develop↔main
> promote)** roadmap item from global CLAUDE.md §4.2.4 — the third "prompt rule → enforced
> gate" conversion after `ga-tag-guard` (v0.18, GA-tag) and `doc-audit-content-gate` (v0.24,
> doc-sync). This feature **CONSUMES** CI results and **enforces/remediates**; it does NOT
> emit CI yaml (that is `pipeline-emit` / `cicd-designer` — boundary pinned in §1/§2).

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
- [Appendix A — 出处映射 (a real CI failure → taxonomy; §4.2.4 #13/#14 → this feature)](#appendix-a--出处映射)

## 1. 目标定位

**用户痛点 (the originating failure — grounded 2026-06-05)**: 用户报 "GitHub CI 一直报问题，没人修"。
落地证据:一个真实托管仓库的 `develop` 分支 CI 已**红 12+ 天** —— `cargo deny check`(license/ban/source
policy)跨多个 commit 持续 fail(含最新 commit),`cargo test --workspace` fail(与进行中的 B4
`AppError` 重构纠缠),外加 Docker Publish + nightly Stress + main-scheduled CI 全红。

**5-why 根因**:
1. 为什么红 CI 没人修?→ 没有任何东西**断言**"CI 必须绿才能推/合"。
2. 为什么没断言?→ 全局 CLAUDE.md §4.2.4 #13("CI 硬门:promote/merge to main 前 `gh run list` /
   `gh pr checks` 确认绿;红→不推")**只是一条 prompt 规则**,从未 harness/gate 化。
3. 为什么 prompt 规则被绕过?→ prompt 规则靠 LLM 自觉,operator 手动推送时无机制拦截(与 doc-sync
   v0.24 / GA-tag v0.18 完全同病)。
4. 为什么红了不自动修?→ 没有任何自动诊断/补救回路;红 CI 就静静红着。
5. 为什么这条不变量从没被升级?→ 历史上只有 `ga-tag-guard`(v0.18,`ga-tag-guard.sh:48`)和
   `doc-audit-content-gate`(v0.24)把 prompt 规则升成 enforced gate;CI-green 还没轮到。

**本 feature 的双重目标**:
1. **检测 + 强制(deterministic,zero-LLM)**:一个确定性脚本 `skills/ci-status/ci-status.sh`
   回答"给定 repo + ref,最新 CI 结论是什么"(PASS / FAIL / IN_PROGRESS / UNKNOWN / NONE +
   failing run id/url),并把这个判定**接进** RC gate / pr-reviewer / 新 `/sdlc:promote` 流,红→拦。
2. **有界自动补救(LLM 仅做分类,确定性脚本守门写操作)**:红 CI 时派诊断 agent 读
   `gh run view --log-failed`,按**钉死的 taxonomy** 分类 —— **极小、可逆、低风险 infra 类** 自动修;
   **但 LLM 永远只产生分类 + 候选 fix,真正落地前必经一个 zero-LLM 的确定性 diff-guard 审实际 staged
   diff**(见目标 3);通过才 commit + 重验 + 人可见 commit;**其余一切**(测试 / 逻辑 / 安全 / 进行中
   重构)**永不自动修,升级人工**。
3. **确定性 diff-guard(zero-LLM,本 feature 的安全核心)**:任何 auto-fix 跑完并 stage 后、
   remediation commit **之前**,一个**纯脚本、零 LLM** 的 guard 审 `git diff --cached` 实际内容。
   命中以下任一即**拒绝 auto-fix → revert staged changes → 强制 ESCALATE**:碰任何 test 路径 / 加
   skip-or-ignore 标记 / A1 非 whitespace-only(改 token)/ 碰 `.github/workflows/*` / 超出该 fix class 声明的 file footprint。
   **这把"NEVER weaken a test"从一条 LLM prompt 规则升级为机器不变量** —— 与 v0.18/v0.24
   "prompt 规则 → enforced gate" 同一招,且正用在本 feature 最危险的操作(红仓里自动编辑代码)上。

**关键设计原则(本 feature 的灵魂,必读)**:
> auto-fix 的 allowlist 必须 **小到可以背诵 + 每一类都可逆 + 每次都重验**。任何"改了可能让别人重构
> 烂掉 / 可能掩盖真 bug / 含糊不清" 的失败 —— **一律升级,绝不自动碰**。real-world cases span both sides:
> `cargo deny` license 缺口 = auto-fixable(allowlist + reason);`cargo test` 撞 B4 重构 = ESCALATE。
>
> **但"allowlist 小 + 每类可逆"是 LLM 分类的设计意图,不能靠 LLM 自觉来兑现。** 因此本 feature 的
> 真正不变量是**确定性 diff-guard**(目标 3):无论 LLM 把失败分成哪类,实际落地的 staged diff 必须
> 通过零-LLM 脚本审查(不碰 test〔path+content〕/ 不加 ignore / A1 必 whitespace-only / 不碰 CI yaml / 不超 footprint),否则
> revert + ESCALATE。**LLM 可以分错;diff-guard 不允许放过。**

**与 `pipeline-emit` / `cicd-designer` 的边界(Hard constraint #1 反耦合)**:
- `pipeline-emit`(`skills/pipeline-emit/emit.sh`)+ `cicd-designer`(`agents/cicd-designer.md`)=
  **PRODUCE** —— 生成 CI pipeline yaml + CD 策略(写 `.github/workflows/*.yml`)。
- `ci-green-gate`(本 feature)= **CONSUME + ENFORCE + REMEDIATE** —— 读 CI **运行结果**,断言绿,
  红时有界补救。**绝不写/改 CI yaml**(那会越界到 pipeline-emit;auto-fix 也禁止编辑 workflow 文件,
  见 §2 out-of-scope)。

**北极星对齐**: "接入任意空仓 30 min 全链通" 隐含 "推到 main / tag 的 commit 必须 CI 绿"。本 feature
把这条**机器可验**的不变量从 prompt 升为 enforced gate —— 与 v0.18 `ga-tag-guard` / v0.24
`doc-audit-content-gate` 同一招。

**与全局 CLAUDE.md 规则映射**:

| 规则 | 本 feature 如何落地 |
|------|--------------------|
| §4.2.4 #13 CI 硬门(promote/merge 前确认绿,红→不推) | `ci-status.sh` 提供确定性判定;E2 接进 releaser **rule 12 / lines 130-145**(OBSERVED-GREEN real CI)+ pr-reviewer + `/sdlc:promote`;tag/promote 门 **default `--require-known`**(UNKNOWN→BLOCK,见 §2 B3) |
| §4.2.4 #14 develop↔main 回合(main 只收 CI 绿 + tagged commit) | 新 `/sdlc:promote` 流在 promote 前断言 ref CI 绿(strict)+ 已 tag |
| §4.5 LLM agent 兜底(weak-model degrade + schema-guided + 3-retry) | 诊断/修复 agent 走 §4.5;分类失败/含糊 → 默认 ESCALATE(fail-safe);**LLM 只分类,写操作由零-LLM diff-guard 守门** |
| §1.1.7 Pre-Create Gate / "stop trusting prompt rules for irreversible actions" | auto-edit 红仓代码是不可逆操作 → 不靠 prompt 规则,靠**确定性 diff-guard**(§3/§5)兜底,与 ga-tag-guard(`ga-tag-guard.sh:48`)/ doc-audit-content-gate 同范式 |
| §2.3 / §6.1 多 seed 验证 flaky | flaky CI 重跑 N≥3 才下"红"结论;不把单次红当定论 |
| 本仓 Hard constraint #1(无业务耦合) | 通用任意 GitHub repo;不依赖特定下游项目工具版本;generic — no project-specific coupling |
| 本仓 Hard constraint #4(no external service)| `ci-status.sh` 只调用户已 auth 的本地 `gh` CLI;不内嵌任何 HTTP/SaaS client;mock 可注入 |
| 本仓 Hard constraint #5(POSIX bash / shellcheck clean / SE16-safe)| 纯 bash + `case`/`awk` no-pipe 控制流 + 进 CI shellcheck(`ci.yml:15-21`) |

## 2. 范围边界

### v0.X.0 做 (pinned — 恰好这 5 个组件,allowlist 写死且极小,diff-guard 是钉死的安全核心)

**[组件 1] CI-status 确定性检查 (MANDATORY) — `skills/ci-status/ci-status.sh`**:
- 输入:repo(默认 cwd)+ ref(默认当前 commit SHA / 当前分支 HEAD)。
- 输出:**单一 verdict** ∈ {PASS, FAIL, IN_PROGRESS, UNKNOWN, NONE} + 结构化细节(failing run
  id / url / conclusion)。
- 查询源:`gh run list`(branch/commit 关联最新 run 的 conclusion)+ `gh pr checks`(PR 上下文)。
- **Zero-LLM,完全确定性。**
- **`gh` 必须可注入/可 mock**:honor `SDLC_GH_BIN`(覆盖 `gh` 可执行路径)+ 兼容 PATH stub
  (单测无法打真 GitHub)。详见 §5。
- **必须优雅处理 gh-unavailable / GitHub-API-EOF**(本环境间歇 EOF on `gh`):报 **UNKNOWN**,
  且 **UNKNOWN 默认 = WARN-not-BLOCK**(见下"UNKNOWN policy",pinned)。

**[组件 2] Gate wiring (MANDATORY, #13/#14)** —— push-to-main / tag / promote 前断言相关 commit
CI 绿,红→拦。获得本检查的 commands/agents(钉死清单):
- `agents/releaser.md` **rule 12 / lines 130-145**(N1 —— 已有"OBSERVED-GREEN real CI run"硬规则,
  `releaser.md:130-145` 实测 verified;rule 12 恰好 span 130-145)→ 从 prompt 描述升级为**显式调用
  `ci-status.sh --require-known`**(tag 门 strict default,B3)并消费其 verdict。
- `agents/pr-reviewer.md` R2 收尾(REVIEW_DONE @ `pr-reviewer.md:188`,verified)→ 前断言 branch
  HEAD CI 非红;**UNKNOWN=WARN(可逆路径,B3),IN_PROGRESS 见 policy**。
- **新 `/sdlc:promote` 流(#14)**:develop→main promote 前 `ci-status.sh --require-known`(strict
  default,UNKNOWN→BLOCK,B3)断言 main-bound commit CI 绿 + 已 tag;红/UNKNOWN → 拒绝 promote。
  (新 command `commands/promote.md` + 可选 `agents/promoter.md` —— 见 §4;若不新增 agent 则逻辑内联
  releaser。)

**[组件 3] 有界自动补救 taxonomy (MANDATORY — allowlist 显式且极小)**:
红 CI → 派诊断 agent(LLM,走 §4.5)读 `gh run view --log-failed`,**分类**后按 taxonomy 行动。
**LLM 只产出分类 + 候选 fix;真正落地由组件 4 的确定性 diff-guard 守门。**

**AUTO-FIXABLE allowlist —— 恰好 THREE auto-fix 类(G3 remediation:A2 lint-autofix 已 DROPPED,
见下)。可逆 / 低风险 infra;别的都不在内;每类钉死 EXPECTED FILE FOOTPRINT,diff-guard 据此审实际
diff**:
| 类 | 动作 | 可逆性 | EXPECTED FILE FOOTPRINT(diff-guard 据此判越界) |
|----|------|--------|----------------------------------------------|
| **A1 formatting** | `cargo fmt` / `prettier --write` / `gofmt -w`(从 stack-config 取 fmt 命令) | 完全可逆(纯格式) | **WHITESPACE-ONLY invariant(G3)**:staged diff 去掉所有空白后必须与 HEAD token 全等(formatter 只 reflow,绝不改 token);**禁** test 路径(path+content marker)/ `.github/workflows/*` / `*.md` / `deny.toml` |

> **G3:A2 lint-autofix 已从 allowlist 移除。** 理由:`cargo clippy --fix` / `eslint --fix` 做的是
> **语义改写**,无法用"whitespace-only"不变量守门,也无法在没有完整工具可复现性的前提下证明安全。
> 因此 lint `--check` 失败现在**和任何代码改动一样 ESCALATE 给人**。diff-guard `--class` 只接受
> `A1|A3|A4`,`A2` 返回 usage error。**inventory 计数不变**(无文件增删,只是 auto-fix allowlist
> 4→3)。原 token-count(`assert`/`expect` 出现次数)规则也**整条删除**——它被 neutering / 注释噪声 /
> 括号灌水 / 仅-Rust 击穿(G3 adversarial 实证);A1 改用 whitespace-only 不变量,从构造上 tamper-proof。
| **A3 cargo deny LICENSE policy gap** | **仅当**确定性 pre-gate 判定失败 class=`licenses`(见下)时:把缺失的 SPDX 加进 `deny.toml [licenses].allow` **并写 documented reason**(参照 `deny.toml [licenses].allow` 的 allow + reason 注释形态) | 可逆(只增配置行) | **唯一**允许动的文件 = `deny.toml`,且**只追加 `[licenses].allow`**;**禁**写 `[advisories].ignore` / `[bans]` / 任何其它文件 |
| **A4 doc-sync drift** | 跑 v0.24 `doc-audit.sh --strict` 的 3 个机械 fix 类(inventory count / command-ref / canonical anchor) | 可逆(改文档计数/锚) | 仅 docs(`*.md` 计数/锚/命令引用),**禁**源/test/CI yaml/`deny.toml` |

**A3 license-vs-advisory 的确定性 pre-gate(B2 — 不让 LLM 决定 license 还是 advisory)**:
`cargo deny check` 可能同时报 license 与 advisory。**在 LLM 被询问之前**,一个 zero-LLM 的脚本检查
`cargo deny` 输出的 **check class**:
- 输出含 `advisories` / `RUSTSEC-` error code → **强制 ESCALATE-security,LLM 连分类都不被调用**
  (`deny.toml:45-56` pattern 每条 ignore 都需人写 rationale —— 机器无法判定"我们没走那条 path")。
- 输出**仅** `licenses`(SPDX-not-in-allow,无 advisory)→ A3 eligible,LLM 提出"加哪个 SPDX +
  reason",随后仍要过组件 4 diff-guard(footprint = 只追加 `[licenses].allow`)。
- license + advisory **同时红** → advisory 优先 → 整体 ESCALATE-security(不偏修 license 掩盖
  advisory)。

每个 auto-fix 后:**stage → 过组件 4 diff-guard → 通过则重跑 CI → 绿则用清晰 message commit
(标注 auto-remediation + run url)+ 开人工知会**;diff-guard 拒绝 → revert staged + ESCALATE;
重跑不绿 → 退回 ESCALATE。

**MUST-ESCALATE list(永不自动修 —— 这是安全核心)**:
- 任何**失败/变更的 test**(包括 `cargo test` tangled with a refactor —— 碰它会损坏别人重构)。
- **编译错误**且与进行中重构纠缠(碰它 = blind-edit mid-refactor)。
- 任何**逻辑 bug**。
- 任何**安全 advisory**(如 `cargo deny [advisories]` 命中 RUSTSEC —— `deny.toml:45-56` pattern
  的 ignore 每条都需人写 rationale,**禁止机器自动 ignore**)。
- **任何含糊 / 无法自信归类** 的失败 → 默认 ESCALATE(fail-safe;§4.5 分类失败也走这)。

**铁律(由组件 4 机器强制,不只是 prompt)**:**NEVER auto-weaken / disable / skip / `#[ignore]`
a test。NEVER blind-edit code mid-refactor。NEVER 机器自动加 security-advisory ignore。NEVER 自动
改 CI yaml。** —— 这些不再靠 LLM 自觉,**由组件 4 的确定性 diff-guard 在 commit 前审实际 staged diff
强制**;命中即 revert + ESCALATE。

**[组件 4] 确定性 post-fix diff-guard (MANDATORY — zero-LLM,本 feature 安全核心,B1)** ——
`skills/ci-status/diff-guard.sh`:
auto-fix 跑完并 `git add` 后、remediation commit **之前**,guard 审 `git diff --cached`(零 LLM,
纯脚本)。命中以下任一 → **拒绝(exit 非 0)→ 调用方 `git reset --hard` revert staged + 强制
ESCALATE**:
1. **碰任何 test 文件**(C4 broadened — path **和** content marker,适用所有 class):
   - **path**:`**/tests/**`、`*_test.*`(含 Go `*_test.go`)、`test_*.*`、`*.test.*`、`*.spec.*`、
     `*.bats`、`*.t.ts`/`*.t.tsx`/`*.t.js`、`conftest.py`、`*Test.java`/`*Tests.java`、
     `*Test.cs`/`*Tests.cs`、`*Spec.scala`。
   - **content marker**(文件**内容**带每语言 test 签名,无视路径):Rust `#[test]`/`#[cfg(test)]`、
     Go `func Test…`/`func Benchmark…`、Python `def test_`/`class Test`、Java `@Test`/
     `@ParameterizedTest`、JS `it(`/`describe(`/`test(`。**这关掉了 C4 击穿**(testify/`t.Fatal`/
     JUnit 在非 `*_test.*` 路径的 src 文件里削弱 test)。
2. **加/扩 skip-or-ignore 标记**(W1 broadened,净增 > 0):`#[ignore]` / `#[cfg(ignore)]` /
   `.skip(` / `.only(` / `it.skip` / `describe.skip` / `xit(` / `fit(` / `fdescribe(` / `xfail` /
   `.xfail` / `@pytest.mark.skip` / `pytest.skip(` / `@unittest.skip` / `t.Skip(` / `t.Skipf(` /
   `@Disabled` / `@Ignore` / `// nolint`。
3. **A1 = WHITESPACE-ONLY 不变量**(G3,取代已删除的 token-count 规则):A1 的 staged diff 去掉
   **所有空白**(含换行)后必须与 HEAD token 全等。任何非空白 token 变化(neutering 把
   `expect(auth(pw))`→`expect(true)`、加注释噪声、灌括号、掏空函数体)→ 拒绝。
   **从构造上 tamper-proof** —— 真 formatter 只 reflow,绝不改/删 token;新增/删除文件无 whitespace-only
   对应物 → 也拒绝。**(原"net assertion count"出现次数规则已整条移除,它被 G3 adversarial 实证击穿。)**
4. **碰 CI yaml**:`.github/workflows/*`(R8,绝不越界写 CI,撞 pipeline-emit)。
5. **超出该 fix class 声明的 EXPECTED FILE FOOTPRINT**(见组件 3 表):A1 → 见 rule 3 whitespace-only
   + 禁 `*.md`/`deny.toml`;A3 动了非 `deny.toml` 文件、或 A3 改到 `[advisories].ignore`;A4 改了非
   `*.md` —— 任何越界 → 拒绝。**`--class A2` 直接 usage error(A2 已 DROP)。**

> **设计意旨**:LLM 可以把 test 编辑误标成 "A1-fmt"(R6,本 feature 自评 Crit);但 diff-guard 审的
> 是**实际产出的 diff**,不是 LLM 自报的 `proposed_fix` 字符串 —— 误分类无法穿透。这把"NEVER weaken
> a test"从 prompt 规则升为脚本不变量(B1)。**G3 把它从一个可被注释/括号/不支持框架击穿的 token
> 计数,升级为 whitespace-only 不变量 + 跨生态 test 文件检测——不再是 advisory,而是 load-bearing。**
> SE16-safe:用 `git diff --cached --name-only` + `case`/`awk` no-pipe 控制流,绝不 `| grep -q`。
> 详见 §5 契约 + §9 GUARD 真-diff 测试。

**[组件 5] 可选 harness guard (E3-class) —— 推荐:本版 DEFER(见下决策)**:
类比 `ga-tag-guard.sh` 的 PreToolUse:Bash hook,拦 `git push origin main` / `git tag`(当该 ref
最新 CI 红)。

> **Ship-or-defer 决策(spec-analyst 推荐:DEFER 到 v.next)**。理由:
> (a) **gh-EOF/UNKNOWN 误拦风险**:本环境间歇 EOF on `gh` → guard 会在 UNKNOWN 时误拦合法 push;
> (b) **CI in-progress 合法态**:push 后 CI 才跑,push 当下 ref 往往"还没有 run / 正在跑" →
>     guard 极易 false-block(与 R4=ga-guard 经验不同,GA-tag 是单点动作,push-main 是高频动作);
> (c) **检测 push target 成本**:从 `git push` 命令行准确判定"目标是 main 且该 commit 已红"需谨慎
>     parse(见 R5)。
> 先靠 E1(`ci-status.sh`)+ E2(gate wiring)收敛;E3 作为 v.next governance 强化项,在
> `SDLC_CI_APPROVED=1` / `.sdlc/ci-approved` 逃生门 + UNKNOWN-不拦 设计成熟后再 ship。precedent =
> `ga-tag-guard.sh:48`。

**Enforcement 层(钉死哪些上)**:
- **E1(必做,本版 ship)**:`ci-status.sh` + 12+ bats(mock gh)。
- **E2(必做,本版 ship)**:gate wiring 进 releaser rule 12 / lines 130-145 + pr-reviewer +
  `/sdlc:promote`。**tag/promote 门 default `--require-known`(UNKNOWN→BLOCK);pr-reviewer/dev 门
  default WARN**(asymmetry 见下 UNKNOWN policy + B3)。
- **E2.5(必做,本版 ship)= 确定性 diff-guard(组件 4)**:`diff-guard.sh`,在每个 auto-fix commit
  前强制审实际 staged diff;**zero-LLM,不可绕过**。这是 B1 的兑现。
- **E3(本版不做,DEFER v.next)**:PreToolUse:Bash CI-guard(理由见上 + R4/R5)。

**UNKNOWN policy (pinned — 这是最易出错处;path-asymmetric per B3)**:
- `gh` 不可用 / GitHub-API EOF / 无 auth → verdict = **UNKNOWN**。
- **判定按路径不对称(pinned,非"建议"):由 *可逆性* 决定**:
  - **可逆路径(pr-reviewer / dev)→ UNKNOWN = WARN(default)。** 理由:本环境 `gh` 间歇 EOF;
    PR check 是可逆的(挡错了重跑即可),false-block 比漏拦更伤"30 min 全链通"北极星。
  - **不可逆路径(releaser RC gate / `/sdlc:promote` / tag push)→ `--require-known` 是 DEFAULT,
    UNKNOWN = BLOCK。** 理由:tag / main-push **不可逆**(§7.1.2 "tag 一旦 push 视为不可撤销");
    一次 EOF→UNKNOWN 若 WARN-and-ship,就把一个真红 tag 放了出去 —— 正是本 feature 要消灭的失败
    模式。被拦的 tag 只是多 retry 一次(代价小且可逆),远小于发出一个红 tag。
- **opt-out(不是 opt-in)**:不可逆门若想放宽,需显式 `--allow-unknown` / `SDLC_CI_LAX=1`(默认
  不开),与逃生门同范式(`ga-tag-guard.sh:48` 的 `SDLC_GA_APPROVED=1`)。可逆门若想收紧,可
  `--require-known` opt-in。**默认值本身已对称地选了各自更安全的一侧。**

### v0.X.0 不做(写死 — explicit out-of-scope)

- **❌ 非 GitHub CI(GitLab CI / Jenkins / CircleCI / Buildkite)** → v.next。本版只懂 `gh` /
  GitHub Actions。
- **❌ 自动修 test / logic / refactor** → **NEVER**(不是 v.next,是永久 out-of-scope;碰它损坏
  正确性 + 别人重构)。
- **❌ 修一个 flaky test 的 *内容*** → 不做(flaky 内容修复是 tester/implementer 的活;本 feature
  只做"重跑 N 次确认是否真红",见 §7 + R7)。
- **❌ 机器自动加 security-advisory ignore**(`deny.toml [advisories].ignore`)→ NEVER(每条需人写
  rationale;A3 的确定性 pre-gate + diff-guard footprint 双重把它挡在 `[licenses].allow` 之外)。
- **❌ 写/改 CI yaml**(那是 `pipeline-emit` / `cicd-designer` 的边界;auto-fix 禁止编辑
  `.github/workflows/*` —— 由组件 4 diff-guard 机器强制,非仅 prompt)。
- **❌ E3 harness guard(组件 5)** → DEFER v.next(见上决策 + R4/R5)。**注意:组件 4 diff-guard
  ≠ E3;diff-guard 是本版 MANDATORY ship,E3 才是 defer 的那个。**
- **❌ 在单测里打真 GitHub** → 永不(违 Hard constraint #4;§9 全程 mock gh)。
- **❌ 记录/打印 gh token / auth**(零 secret,§1.4;gh auth 是用户的,绝不 log)。

### 推迟到 v.next

- 非 GitHub CI provider 适配(GitLab/Jenkins,经 stack-config 抽象)。
- E3 PreToolUse CI-guard(governance 批次)。
- auto-fix allowlist 谨慎扩展(仅当新类被证明可逆 + 工具保证语义 + §9 覆盖)。

## 3. 架构数据流

```
 ┌─────────────────────────── E1: deterministic status ───────────────────────────┐
 │ ci-status.sh [--repo R] [--ref REF] [--require-known] [--json]                   │
 │   GH = ${SDLC_GH_BIN:-gh}      (injectable / PATH-stub-able — §5, mock in §9)    │
 │        │                                                                          │
 │        ▼  resolve ref (default = git rev-parse HEAD)                              │
 │   $GH run list --branch/--commit ... --json conclusion,status,databaseId,url      │
 │   (PR ctx) $GH pr checks --json ...                                               │
 │        │                                                                          │
 │        ├─ gh missing / non-zero / EOF / empty(parse fail) ─→ verdict=UNKNOWN     │
 │        ├─ no runs found for ref ──────────────────────────→ verdict=NONE         │
 │        ├─ latest run status != completed ─────────────────→ verdict=IN_PROGRESS  │
 │        ├─ conclusion == success ──────────────────────────→ verdict=PASS         │
 │        └─ conclusion ∈ {failure,timed_out,cancelled,...} ─→ verdict=FAIL         │
 │             (+ failing run id + url on FAIL/IN_PROGRESS)                          │
 │   exit: 0=PASS · 1=FAIL · 3=IN_PROGRESS · 4=UNKNOWN · 5=NONE  (§5)               │
 └──────────────────────────────────────────────────────────────────────────────────┘
        │ verdict
        ▼
 ┌──────────────── E2: gate decision (path-asymmetric per reversibility, §2/B3) ────┐
 │  PASS  → proceed                                                                  │
 │  FAIL  → BLOCK + (optionally) enter remediation loop ↓                            │
 │  IN_PROGRESS → poll up to MAX_WAIT (timeout policy §7) → re-verdict; timeout→WARN │
 │  UNKNOWN → reversible path (pr-reviewer/dev): WARN (default)                      │
 │           irreversible path (releaser RC gate / /sdlc:promote / tag): BLOCK       │
 │           (--require-known is the DEFAULT there; opt-out only via --allow-unknown)│
 │  NONE  → SKIP gate (no CI configured = not a failure, §7)                         │
 └──────────────────────────────────────────────────────────────────────────────────┘
        │ FAIL → remediate (bounded)
        ▼
 ┌──────────────── 组件3+4: bounded auto-remediation w/ deterministic diff-guard ───┐
 │  attempt = 0                                                                      │
 │  while verdict==FAIL and attempt < MAX_REMEDIATION (=2):                          │
 │     $GH run view <id> --log-failed   →  [det. pre-gate, ZERO-LLM]                 │
 │        │  if log has `advisories`/`RUSTSEC-` → ESCALATE-security (LLM not asked)   │
 │        ▼                                                                          │
 │     CATEGORIZE (schema-guided JSON, §4.5)   ← LLM ONLY proposes a class+fix       │
 │        │                                                                          │
 │        ├─ class ∈ {A1 fmt, A3 deny-LICENSE(license-only), A4 doc}  (A2 lint DROPPED)│
 │        │      apply tool/edit  →  git add (STAGE)                                  │
 │        │         │                                                                 │
 │        │         ▼  ┌──────── diff-guard.sh (组件4, ZERO-LLM, on `git diff        │
 │        │            │         --cached`): touches test? adds skip/ignore? nets    │
 │        │            │         assertions DOWN? touches .github/workflows/*?       │
 │        │            │         exceeds class FOOTPRINT? ──┐                          │
 │        │            └──────────────────────────────────┘                          │
 │        │           guard PASS → commit (clear msg + run url) → re-run ci-status    │
 │        │                          PASS→done(human-visible); FAIL→attempt++         │
 │        │           guard REJECT → `git reset --hard` (revert staged) → ESCALATE   │
 │        │                          (LLM mislabel cannot pass — it's the ACTUAL diff)│
 │        │                                                                          │
 │        └─ class ∈ {test, compile-mid-refactor, logic, security, AMBIGUOUS}        │
 │               → ESCALATE to human with diagnosis; STOP (never loop, never edit)   │
 │  attempt == MAX_REMEDIATION and still FAIL → ESCALATE (bounded — no infinite loop)│
 └──────────────────────────────────────────────────────────────────────────────────┘
```

**关键不变量**:(a) auto-fix XOR escalate —— 每个失败要么落在极小 allowlist 自动修,要么升级,**无
第三条路**;(b) 自动修后**必重验**;(c) 补救**有界**(MAX_REMEDIATION=2,防无限回路);(d) UNKNOWN
**按可逆性不对称**(可逆门 warn,不可逆 tag/promote 门 block,B3);(e) NONE = skip 不 fail(无 CI ≠
红);(f) **每个 auto-fix commit 前必经 zero-LLM diff-guard 审实际 staged diff —— LLM 只分类,写操作
由脚本守门;guard reject → revert + ESCALATE,误分类穿不透**(B1);(g) **advisory/RUSTSEC 在 LLM
被询问之前就被确定性 pre-gate 强制 ESCALATE-security,license↔advisory 不由 LLM 区分**(B2)。

## 4. 模块边界

| New/changed | Path | Role |
|-------------|------|------|
| Skill (new) | `skills/ci-status/ci-status.sh` | E1 deterministic verdict;zero-LLM;`SDLC_GH_BIN` 注入点 |
| Skill (new) | `skills/ci-status/diff-guard.sh` | **组件4** zero-LLM post-fix diff-guard:审 `git diff --cached`,touches-test/skip-ignore/net-assert-down/CI-yaml/超 footprint → exit 非0(调用方 revert+ESCALATE);SE16-safe(`case`/`awk` no-pipe) |
| Skill (new) | `skills/ci-status/SKILL.md` | skill 描述(plugin loads skill via SKILL.md;库存计数 §3 doc-audit-content-gate 要求) |
| Tests (new) | `tests/ci-status.bats` | §9 矩阵;gh stub fixtures(含 `run view --log-failed` stub,N2)+ **diff-guard 真-staged-diff fixtures** |
| Agent (new) | `agents/ci-remediator.md` | 组件3 诊断+分类 agent(LLM,model_tier=sonnet per §4.5);**只产分类+候选 fix,落地前必调 `diff-guard.sh`**;§9 taxonomy + never-weaken 真-diff guard 测 |
| Agent (edit) | `agents/releaser.md` | E2:**rule 12 / lines 130-145**(OBSERVED-GREEN real CI)从 prompt-described 升级为显式 `ci-status.sh --require-known` 调用 + verdict 消费(tag 门 strict default,B3) |
| Agent (edit) | `agents/pr-reviewer.md` | E2:R2 收尾前断言 branch HEAD verdict 非 FAIL |
| Command (new) | `commands/promote.md` | `/sdlc:promote`(#14 develop→main):promote 前 `ci-status.sh --require-known`(strict default,B3)断言 CI 绿 + 已 tag;UNKNOWN→BLOCK |
| Agent (new, optional) | `agents/promoter.md` | 若 promote 逻辑超出 releaser scope 则独立(否则内联 releaser);spec-analyst 倾向**先内联 releaser**,promoter 留 v.next |
| Docs (edit) | `README.md` / `DEVELOP.md` / `RELEASE.md` | 文档 5 个组件(含 diff-guard)+ path-asymmetric UNKNOWN policy;**dogfood**:这些 edit 必须过 v0.24 doc-audit 内容门(inventory count **pinned**:agents 17→18、commands 26→27、skills 20→21,N4 无 `?`) |
| Reuse (read-only) | `config/stack-*.yaml` / `config/detect-stack.sh` | A1 auto-fix 的 fmt 命令从 stack-config 取(不硬编码 `cargo fmt`,Hard constraint:no build-literal in agent;A2 lint 已 DROP,无 lint 命令消费) |
| Reuse (read-only) | `skills/handoff-schema/validate.sh` | handoff v2 校验(`validate.sh:60-80`:producer/model_tier/self_score) |

**Cross-repo boundary**: **none** —— `ci-status.sh` 只调本机 `gh`(查任意 GitHub repo,但脚本本身
不写目标 repo,除非 auto-fix —— 而 auto-fix 只动 **当前 SDLC-driven repo** 的 fmt/deny/doc 文件,
绝不写 CI yaml,绝不写第三方 repo)。No external service(`gh` 是本机 CLI,Hard constraint #4)。No
business coupling(任意 GitHub repo;used as example only,Hard constraint #1)。

## 5. API 契约

### `ci-status.sh` CLI 契约 (typed)

```
ci-status.sh [--repo <owner/name>] [--ref <sha|branch>] [--pr <num>]
             [--require-known] [--json] [--gh-bin <path>] [--poll <secs>] [--max-wait <secs>]

env:
  SDLC_GH_BIN     # override the `gh` executable (default: `gh`); the §9 mock injection point
  SDLC_CI_STRICT  # =1 ⇒ UNKNOWN is treated as BLOCK (same as --require-known)
  SDLC_CI_LAX     # =1 ⇒ UNKNOWN is treated as WARN even on the irreversible path (opt-OUT; default off)
  SDLC_PROJECT_ROOT  # repo root when Claude runs from a parent dir (v0.20 convention)

# gate-default asymmetry (B3, pinned — NOT a recommendation):
#   reversible path  (pr-reviewer / dev)              → UNKNOWN = WARN  (default)
#   irreversible path(releaser RC gate / promote/tag) → --require-known is the DEFAULT ⇒ UNKNOWN = BLOCK
#   the releaser + promote callers invoke `ci-status.sh --require-known` unconditionally;
#   override to relax only with --allow-unknown / SDLC_CI_LAX=1 (off by default).

exit codes (verdict → exit):
  0  PASS         # latest run for ref: conclusion=success
  1  FAIL         # latest run: conclusion ∈ {failure,timed_out,cancelled,startup_failure,action_required}
  3  IN_PROGRESS  # latest run: status != completed (queued/in_progress)
  4  UNKNOWN      # gh missing / non-zero / EOF / unparseable / no auth  (default = WARN, not block)
  5  NONE         # no CI runs found for ref (no workflow / never ran) — skip, NOT a failure
  2  USAGE        # bad argument (reserve 2 for usage, matching scan.sh:23 convention)

stdout (human): one line verdict, e.g.
  "ci-status: FAIL  ref=a1b2c3d  run=12345678  https://github.com/o/r/actions/runs/12345678"
  "ci-status: UNKNOWN  (gh unavailable or API EOF) — treated as WARN; use --require-known to block"
stdout (--json): {"verdict":"FAIL","ref":"a1b2c3d","run_id":"12345678","url":"...","conclusion":"failure"}
```

**gh-mock 注入点 (§9 single source)**: 脚本**第一行决议** `GH="${SDLC_GH_BIN:-gh}"`,之后**只**经
`"$GH"` 调用 —— 单测把 `SDLC_GH_BIN=tests/fixtures/gh-stub.sh`(或在 `PATH` 前置 stub 目录)即可
注入 PASS/FAIL/in-progress/EOF fixtures,**永不打真 GitHub**(Hard constraint #4)。

**解析契约 (SE16-safe)**: 用 `$GH ... --json conclusion,status,databaseId,url` → `jq` 取字段;
**no `| grep -q` / `| head -n` 控制流**(用 `case "$conclusion" in success) ;; ...` no-pipe 形式)。
`jq`/`gh` 缺失 → verdict=UNKNOWN(优雅降级,不 crash;jq 已是 CI dep `ci.yml:41,47`)。

### `diff-guard.sh` CLI 契约 (组件4 — zero-LLM,B1 安全核心,typed)

```
diff-guard.sh --class <A1|A3|A4> [--staged]    # default inspects `git diff --cached`
                                               # A2 is REJECTED as usage (lint-autofix DROPPED, G3)

logic (zero-LLM, deterministic, SE16-safe — name-only + case/awk, no `| grep -q`):
  files = git diff --cached --name-only
  REJECT (exit 1) if ANY:
    (1) any file matches a test FILE — path OR content marker (C4, ALL classes):
        path:    **/tests/** · *_test.* (incl Go *_test.go) · test_*.* · *.test.* · *.spec.*
                 · *.bats · *.t.ts/*.t.tsx/*.t.js · conftest.py · *Test.java/*Tests.java
                 · *Test.cs/*Tests.cs · *Spec.scala
        content: Rust #[test]/#[cfg(test)] · Go func Test/func Benchmark · Py def test_/class Test
                 · Java @Test/@ParameterizedTest · JS it(/describe(/test(
    (2) the +added lines net-ADD any skip/ignore marker (W1 broadened):
        #[ignore] · #[cfg(ignore)] · .skip( · .only( · it.skip · describe.skip · xit( · fit(
        · fdescribe( · xfail · .xfail · @pytest.mark.skip · pytest.skip( · @unittest.skip
        · t.Skip( · t.Skipf( · @Disabled · @Ignore · // nolint
    (3) A1 = WHITESPACE-ONLY invariant (G3, replaces the deleted token-count rule):
        for class A1, the staged diff with ALL whitespace (incl newlines) stripped MUST be
        token-identical to HEAD. Any non-ws token change (neuter / comment-noise / bracket-
        inflate / logic-gut) → REJECT. Added/removed files → REJECT (no ws-only equivalent).
    (4) any file matches .github/workflows/*           (R8 — never edit CI yaml)
    (5) any file is OUTSIDE the --class EXPECTED FILE FOOTPRINT (§2 组件3 表):
        A1 → whitespace-only source reflow, NO *.md / NO deny.toml; A3 → deny.toml ONLY and
        only `[licenses].allow` appended (never [advisories]/[bans]); A4 → docs (*.md) only
  else PASS (exit 0)

exit codes:
  0  PASS   # diff is within footprint and weakens nothing → caller proceeds to commit
  1  REJECT # caller MUST `git reset --hard` (revert staged) + force ESCALATE
  2  USAGE  # bad/missing --class
```

**调用契约(钉死)**:ci-remediator 的 auto-fix 步骤 = `apply fix` → `git add` →
`diff-guard.sh --class <A*>` → **exit 0 才允许 commit**;**exit 1 → `git reset --hard` + ESCALATE**。
diff-guard **绝不**读 LLM 输出,只读真实 staged diff —— 误分类(把 test 编辑标成 A1)无法穿透。
A3 的 `[advisories].ignore` 由两道确定性闸门挡:`ci-status.sh`/remediator 入口的 advisory-pre-gate
(B2)+ diff-guard footprint 规则 (5)。

### A3 license-vs-advisory 确定性 pre-gate 契约 (B2 — LLM 之前)

```
deny_classify(log_text)  # zero-LLM, runs BEFORE the LLM classifier is invoked
  # W4 (G3): empty/missing log → fail-safe ESCALATE (cannot prove benign);
  #          match is CASE-INSENSITIVE (lowercase the log first).
  if [ "$#" -lt 2 ] || [ -z "$log_text" ]; then echo "ESCALATE-security"; exit 10; fi
  log_lc = lowercase(log_text)
  case "$log_lc" in
    *advisories*|*rustsec-*) echo "ESCALATE-security"; exit 10 ;;  # advisory wins; LLM not asked
    *licenses*)              echo "A3-eligible";        exit 0  ;;  # license-only → A3 path
    *)                       echo "DEFER-LLM";          exit 0  ;;  # other classes → normal LLM flow
  esac
```
license + advisory 同红 → advisory 分支命中优先 → 整体 ESCALATE-security(不偏修 license 掩盖 vuln)。
**W4(G3):** 大小写不敏感(`ADVISORIES`/`RUSTSEC` 大写也命中)+ 空/缺日志 → fail-safe ESCALATE
(缺日志无法证明无害,绝不 DEFER-LLM)。

### ci-remediator agent 契约 (LLM, schema-guided per §4.5)

输入:failing run id + `gh run view --log-failed` 文本(**已过 B2 advisory pre-gate;命中 advisory
则 LLM 根本不被调用**)。输出(schema-guided JSON,§4.5 A):
```json
{"class":"A3-deny-license|A1-fmt|A2-lint|A4-doc-sync|ESCALATE-test|ESCALATE-compile|ESCALATE-logic|ESCALATE-security|ESCALATE-ambiguous",
 "confidence":0.0-1.0, "evidence":"<log excerpt>", "proposed_fix":"<for A* only>", "reason":"<for A3 the documented allowlist reason>"}
```
`confidence < 阈值` 或 class 非 A* → 强制 ESCALATE(fail-safe)。3-retry 验证循环(§4.5 B);弱模型
degrade → 倾向 ESCALATE(永不 over-act)。
**关键:`proposed_fix` 字符串不是安全边界 —— 它只是给 LLM 落地的草稿;真正的不可绕过检查是 fix 跑完后
`diff-guard.sh` 对 *实际产出 staged diff* 的审查(B1)。LLM 报什么不重要,diff 是什么才重要。**

## 6. 扩展点 / 插件接口

- **新 CI provider(GitLab/Jenkins,v.next)**: `ci-status.sh` 内 `query_<provider>()` 函数,verdict
  归一化到同 5 态;命令行 `--provider gitlab`。verdict 枚举 + exit code 契约不变(下游 gate 无感)。
- **扩 auto-fix allowlist**: 新增一个 class 行 → 必须同时(a)证明可逆 +(b)工具保证语义 +(c)
  **声明 EXPECTED FILE FOOTPRINT 并加进 diff-guard 的 footprint 表** +(d)§9 覆盖(含 footprint
  越界 reject 测)+(e)写进 §2 allowlist 表。**默认拒绝扩**(allowlist 越小越安全)。
- **新 gate 消费点**: 任意 agent/command 调 `ci-status.sh` 读 exit code/verdict 即获本能力(单一
  SSOT,不重复实现)。**写操作类的消费点必须在 commit 前调 `diff-guard.sh`**(同一 SSOT,不重复实现 guard)。
- **per-repo CI 严格度**: `.sdlc/ci-strict`(存在即 UNKNOWN→BLOCK,覆盖可逆门)/ `.sdlc/ci-lax`
  (存在即放宽不可逆门 UNKNOWN→WARN,opt-out)/ `.sdlc/ci-approved`(E3 逃生门,v.next),mirror
  `ga-tag-guard.sh:48` 的 `.sdlc/ga-approved`。**注意 default 已是不对称(可逆 WARN / 不可逆 BLOCK),
  这两个文件只是 per-repo override。**
- **E3 guard 接入点(v.next)**: PreToolUse:Bash hook entry 进 `hooks/hooks.json` + `hooks/ci-push-guard.sh`,
  形态 mirror `ga-tag-guard.sh`。

## 7. 错误 + 边界 case

| Edge | Behavior |
|------|----------|
| **gh unavailable / GitHub-API EOF**(本环境间歇)| verdict=UNKNOWN, exit 4;**可逆路径(pr-reviewer/dev)默认 WARN 不 block**;**不可逆路径(releaser RC gate / promote / tag)`--require-known` 是 default → BLOCK**(B3,reversibility-justified)。绝不 crash 整个 gate(graceful degrade,§7.2)。 |
| **UNKNOWN at the irreversible tag/release/promote gate**(B3)| verdict=UNKNOWN → **BLOCK**(`--require-known` default);理由:tag/main-push 不可逆(§7.1.2),一次 EOF→ship-red 远比多 retry 一次贵;放宽需显式 `--allow-unknown`/`SDLC_CI_LAX=1`(默认关)。 |
| **auto-fix diff touches a test / adds #[ignore] / removes assert / edits CI yaml**(B1)| auto-fix `git add` 后 `diff-guard.sh` 审实际 staged diff → 命中 rule(1)-(5)任一 → **exit 1 → 调用方 `git reset --hard`(revert)+ 强制 ESCALATE**;**zero-LLM,LLM 误分类穿不透**(§5 契约 + §9 真-diff 测)。 |
| **gh present but not authed** | UNKNOWN(同上);提示 `gh auth login`;不 log token。 |
| **CI in-progress(不能永等)** | verdict=IN_PROGRESS, exit 3;gate 端 poll `--poll`(默认 20s)直到 `--max-wait`(默认 300s);超时 → WARN(不无限等,不误判红)。 |
| **no CI configured(NONE)** | exit 5;gate **SKIP**(无 workflow ≠ 红;不 fail —— 否则任意无 CI 的空仓全链断,违北极星)。 |
| **red that auto-fix can't resolve** | 补救 attempt 达 MAX_REMEDIATION(=2)仍 FAIL → **ESCALATE**(有界,绝不无限 loop;R6)。 |
| **mid-refactor test-red** | class=ESCALATE-compile/test → **永不碰**(碰 = blind-edit mid-refactor,损坏别人重构);带诊断升级人工。**若 LLM 误标成 A* 并真去编辑 test → diff-guard rule(1)/(3) 在 commit 前拒绝 + revert + ESCALATE**(机器兜底,非靠 LLM 自觉)。 |
| **security advisory(RUSTSEC,`deny.toml:45-56` pattern)** | **B2 确定性 pre-gate**:`gh run view` log 含 `advisories`/`RUSTSEC-` → 在 LLM 被询问之前强制 ESCALATE-security;**永不机器自动 ignore**;A3 只能追加 `[licenses].allow`,diff-guard footprint rule(5) 再挡一层。 |
| **failing test(任何)** | class=ESCALATE-test → **NEVER auto-weaken/disable/skip/`#[ignore]`**;升级。**机制保障**:即便 LLM 误分类,diff-guard rule(1)碰 test 文件〔path+content marker,跨生态〕/ rule(2)加 skip-ignore / rule(3)A1 非 whitespace-only(改/删 token)任一命中 → REJECT + revert + ESCALATE。 |
| **flaky CI(间歇红)** | 不把单次红当定论:gate 端 `--rerun N`(默认对 IN_PROGRESS→FAIL 边界)= **re-QUERY 同一 run 的 conclusion(`gh run view <same-id>`),不 re-trigger CI**(N3 —— re-trigger 是无界成本 + 越界 pipeline territory);真红 N≥3 才 BLOCK(§2.3/§6.1 multi-seed);**不修 flaky 内容**(out-of-scope)。 |
| **ambiguous classification** | confidence < 阈值 或非 A* → **默认 ESCALATE**(fail-safe;§4.5 弱模型 degrade 倾向不 act)。 |
| **auto-fix 改了反而更红 / 引入新失败** | 重验捕获 → 该 attempt 视为失败 → 下一 attempt 或 ESCALATE;auto-fix 全可逆(fmt/配置增行),人可见 commit 便于 revert(R1)。 |
| **detached HEAD / ref 无对应 remote run** | ref 解析失败 → 尽量用 commit SHA 查;查不到 → NONE(exit 5),不误报 FAIL。 |
| **PR vs branch 上下文** | `--pr` 时用 `gh pr checks`;否则 `gh run list --branch/--commit`;两者归一化到同 verdict。 |

错误码:0/1/3/4/5(verdict)+ 2(usage);kebab 文本 message(grep-stable)。内部失败(jq/gh 缺)→
UNKNOWN 降级,绝不 abort 上层 gate。

## 8. 成本契约

- **磁盘**: 0 new persistent artifacts;bats fixtures 在 temp dir(auto-clean)。auto-fix commit 是
  正常 git 对象(无额外盘)。
- **LLM token**:
  - **E1 `ci-status.sh` = 0 token**(纯确定性 gh+jq)。
  - **组件4 `diff-guard.sh` = 0 token**(纯确定性 git+case/awk;安全核心却零成本 —— 这正是把安全
    property 做成脚本不变量而非 LLM 调用的额外红利)。
  - **B2 advisory pre-gate = 0 token**(LLM 之前的确定性 case 匹配)。
  - **组件3 ci-remediator = LLM**,仅在 **CI 红 + 非 advisory** 时触发(advisory 被 B2 pre-gate
    零-token 拦掉):每次诊断 ≈ 1 个 `gh run view --log-failed` 日志(典型 2–20KB)送 sonnet +
    schema-guided 输出;有界 MAX_REMEDIATION=2 → 上限 ≈ 2 次 diagnosis/红事件。预估 **~4–12K token /
    红事件**(取决日志长度)。绿 CI = 0 token。
- **Wall-clock**: `ci-status.sh` = 1–2 次 `gh` API 往返(~1–3s,EOF 时更快返回 UNKNOWN);poll 态最多
  `--max-wait`(默认 300s)。remediation = 诊断 LLM(~数十秒)+ re-run CI(分钟级,取决 CI 本身)。
- **时间金钱归属**: status 检查 = 本地 CPU + 用户已 auth 的 gh quota(零额外钱);remediation = LLM
  token(归属调用方 model tier;弱模型 degrade 仍可用,§4.5)。
- **审计命令(user 可自跑)**:
  ```bash
  bash skills/ci-status/ci-status.sh --json                  # 当前 commit verdict (reversible default)
  bash skills/ci-status/ci-status.sh --require-known --json  # tag/promote gate semantics (UNKNOWN→BLOCK, B3)
  SDLC_GH_BIN=tests/fixtures/gh-stub.sh bash skills/ci-status/ci-status.sh   # mock 自检(零网络/零 token)
  git add -A && bash skills/ci-status/diff-guard.sh --class A1; echo "guard exit=$?"  # diff-guard 自检(零 token)
  ```

## 9. 测试矩阵

`tests/ci-status.bats`(+ `diff-guard` 真-diff 测 + ci-remediator taxonomy 测) —— gh **全程 mock**
(`SDLC_GH_BIN` → `tests/fixtures/gh-stub.sh`,据 `$1` 子命令 + 环境变量返回对应 fixture JSON;
**stub 必须服务 `run list` / `pr checks` / `run view --log-failed` 三个子命令**(N2 —— remediator 路径
靠 `run view --log-failed`,不 mock 它则 taxonomy/guard 测无法离线跑,违 Hard constraint #4);**永不打
真 GitHub**)。diff-guard 测用**真 git repo fixture(temp dir + 真 `git add` 真 staged diff)**,审
*实际产出 diff*,**不是** JSON 字符串。6 类全覆盖 + B1 真-diff guard + B2 advisory pre-gate +
taxonomy + real-project-shaped:

| Class | Case | Pass criterion |
|-------|------|----------------|
| happy | gh-stub returns conclusion=success | exit 0, "ci-status: PASS" |
| happy | gh-stub returns conclusion=failure + run id/url | exit 1, "FAIL", url present |
| edge | gh-stub returns status=in_progress | exit 3, "IN_PROGRESS" |
| edge | gh-stub returns empty run list (no runs) | exit 5, "NONE" — gate SKIPs, not fail |
| edge | **reversible path** + UNKNOWN (no flag) | WARN semantics (proceeds; UNKNOWN-as-warn) |
| edge | **irreversible path** + UNKNOWN (`--require-known` default at tag/promote, B3) | exit → BLOCK semantics (UNKNOWN-as-block) |
| edge | irreversible path + UNKNOWN + `--allow-unknown`/`SDLC_CI_LAX=1` (opt-out) | WARN semantics (relaxed only when explicitly opted out) |
| **error** | **gh-stub exits non-zero / prints partial then EOF** | exit 4, "UNKNOWN", **reversible default = WARN msg; irreversible default = BLOCK**, no crash |
| error | jq absent (simulated) | degrade → UNKNOWN, no crash |
| error (N2) | **gh-stub `run view --log-failed` serves a failing-log fixture** | remediator path runs fully offline; log text reaches classifier/pre-gate |
| adversarial | gh-stub returns malformed/truncated JSON | parse-fail → UNKNOWN (not a false PASS/FAIL) |
| adversarial | gh-stub returns conclusion=cancelled / timed_out | classified FAIL (not PASS) |
| concurrent | two parallel ci-status.sh on disjoint SDLC_PROJECT_ROOT | both deterministic, no shared state |
| resource | gh-stub returns a 5000-run list | parser picks latest, sub-second, no OOM |
| **taxonomy — A3 auto-fix** | **real-project-shaped**: `run view --log-failed` = `cargo deny` LICENSE rejection (SPDX missing from allow, **no advisory**) | B2 pre-gate=A3-eligible; classify=A3; fix appends SPDX to `[licenses].allow` **with reason** (mirrors `deny.toml:72-86` allow pattern); diff-guard PASS (footprint=deny.toml only) |
| **B2 pre-gate — advisory wins** | log = `cargo deny` with **both** a license gap AND a `RUSTSEC-`/`advisories` line | **deterministic pre-gate forces ESCALATE-security BEFORE the LLM is invoked** (does not auto-fix the license to mask the vuln) |
| **taxonomy — ESCALATE test** | **real-project-shaped**: log = `cargo test` failure tangled with B4 AppError refactor | classify=ESCALATE-test/compile; **NO auto-fix attempted** |
| taxonomy — A1 fmt | log = `cargo fmt --check` diff | classify=A1; fmt command from stack-config (not hardcoded) |
| taxonomy — ESCALATE security | log = RUSTSEC advisory only (`deny.toml [advisories]`) | pre-gate=ESCALATE-security; **never auto-adds ignore** |
| taxonomy — ambiguous | log = unrecognized failure | confidence<thresh → ESCALATE (fail-safe) |
| **GUARD (B1) — diff touches a test → REAL diff** | in a temp git repo, **stage a real diff that edits `src/foo_test.rs` / a `#[test]` block** then run `diff-guard.sh --class A1` | **guard exit 1; caller `git reset --hard` reverts; ESCALATE** — asserts on the *actual staged diff*, NOT a remediator string |
| **GUARD (B1) — diff adds #[ignore]/.skip → REAL diff** | stage a real diff whose +lines add `#[ignore]` (Rust) / `it.skip(` (JS) / `@pytest.mark.skip` (Py) | guard exit 1; revert + ESCALATE (net skip-marker add detected) |
| **GUARD (B1/C3) — A1 non-whitespace change → REAL diff** | stage a real A1 diff that deletes/neuters an assertion (`expect(auth(pw))`→`expect(true)`), adds comment-noise, inflates brackets, or guts a function body | guard exit 1; revert + ESCALATE — the whitespace-only invariant catches ANY token change (token-count rule REMOVED in G3) |
| **GUARD (B1/C4) — test markers in a non-`*_test.*` src path → REAL diff** | stage a diff that removes `require.Equal`/`t.Fatal` in `src/helpers.go`, or `def test_` in `src/util.py`, or `@Disabled` on a JUnit `@Test` | guard exit 1 — content-marker detection (`func Test`/`def test_`/`@Test`/`describe(`) catches the ecosystem the path regex misses |
| **GUARD (B1) — diff touches .github/workflows/* → REAL diff** | stage a real edit to `.github/workflows/ci.yml` | guard exit 1; revert + ESCALATE (R8 — never auto-edit CI yaml) |
| **GUARD (B1) — A3 footprint overrun → REAL diff** | A3 stages a diff that edits a file ≠ `deny.toml`, OR appends to `[advisories].ignore` instead of `[licenses].allow` | guard exit 1; revert + ESCALATE (footprint rule (5)) |
| **GUARD (B1) — clean A1 fmt reflow → REAL diff (positive)** | stage a real `cargo fmt` reflow in `src/` (line-split + spacing, no token change) | guard exit 0 (PASS) — the whitespace-only invariant compares stripped-token streams, so a legit line-splitting reflow proceeds to commit (not a false-positive blocker) |
| **GUARD (B1) — A4 doc-sync *.md → REAL diff (positive)** | stage an A4 `*.md` inventory-count edit | guard exit 0 (PASS) — A4 footprint is docs-only; no over-block |
| bounded-loop | inject persistent FAIL after auto-fix | attempt stops at MAX_REMEDIATION=2 → ESCALATE (no infinite loop) |
| coupling guard | assert releaser rule 12 (130-145) + pr-reviewer reference `ci-status.sh`; remediator references `diff-guard.sh` | grep agent md for `ci-status` / `diff-guard` (E2 + E2.5 wired, not decoupled) |
| **META (dogfood, N4 pinned)** | run feature's own checks consistent with this repo's CI | this spec's deliverables pass v0.24 doc-audit with **pinned** inventory targets: **agents 17→18** (new `ci-remediator.md`), **commands 26→27** (new `promote.md`), **skills 20→21** (new `ci-status/`); doc-audit-content-gate asserts these exact counts (no `?`) |

通过判据: `ci-status.sh` + `diff-guard.sh` deterministic PASS rate = 1.00(zero-LLM,§6.1)。
**diff-guard 全部 6 个 GUARD 行用真 git staged diff,不是 JSON 字符串 —— 这是 B1 兑现的核心断言。**
ci-remediator(LLM)按 §4.5 D 三 tier 跑 ≥10 case,classify F1 三 tier 差 ≤ 0.15;弱模型不达标 →
degrade 到"全 ESCALATE"(永不 over-act,安全侧)。**真-diff GUARD(B1)+ B2 advisory-pre-gate +
real-project-shaped 是最高价值的对抗 case;它们靠确定性脚本,不靠 LLM 自觉。**

## 10. 向后兼容

- **新增,非破坏**: `ci-status.sh` / `diff-guard.sh` / `ci-remediator` / `/sdlc:promote` 全是新增;
  现有 command/agent 行为不变(releaser/pr-reviewer 的 edit 是**增强**,旧 verdict-less 路径仍 fall
  through)。
- **handoff schema**: 复用 v2(`validate.sh:60-80`);本 feature handoff `producer:` + `model_tier:`
  + `self_score.rubric_ref` 齐(Hard constraint #6/#7)。无 schema 变更。
- **CI 契约(本插件自身)**: `ci.yml` 无需改(`ci-status.sh` + `diff-guard.sh` 进 shellcheck
  `ci.yml:15-21` + bats `ci.yml:55-57` 即覆盖);E1/E2.5 不依赖改 workflow。
- **非 GitHub / 无 CI repo 行为**: NONE → SKIP gate;UNKNOWN → **可逆门 WARN / 不可逆门 BLOCK**
  (B3 asymmetry)。**可逆路径(pr-reviewer/dev)净效果 = 与今天等价**(不引入新 block);**不可逆
  路径(tag/release/promote)是有意收紧** —— 那里 UNKNOWN→BLOCK 是 feature 的点(防 EOF→ship-red
  irreversible tag),不是 regression。无 CI 空仓不受影响(NONE → SKIP,不进 UNKNOWN 分支)。
- **Migration (worked old→new example)**:
  - **Before**: operator 在 `develop` 上 `git push`;CI 红(`cargo deny` license + `cargo
    test`)无人拦、无人修 → 红 12+ 天。RC/promote 阶段无机制断言绿;若 `gh` EOF,无机制区分"真绿"
    与"查不到",一律放行。
  - **After (本 feature)**:
    1. releaser rule 12 / `/sdlc:promote` 调 `ci-status.sh --require-known`(strict default)→
       verdict=FAIL(run url) → **BLOCK**;若 EOF→UNKNOWN,不可逆门同样 **BLOCK**(不 ship 不确定态,B3)。
    2. 进有界补救:B2 pre-gate 确认 `cargo deny` 失败是 **license-only**(无 advisory)→ class=A3 →
       自动加 SPDX 到 `[licenses].allow` + reason → `git add` → **`diff-guard.sh --class A3` 审实际
       diff(footprint=deny.toml only,未碰 test/CI/advisory)→ PASS → commit** → re-run → 绿 →
       人可见 commit。
    3. `cargo test` 撞 B4 重构 → class=ESCALATE-test → **不碰**;即便 LLM 误标 A1 去编辑 test,
       `diff-guard.sh` rule(1) 在 commit 前拒绝 + `git reset --hard` + ESCALATE(机制兜底)。
    4. 结果:license 缺口几分钟内自愈(且经 diff-guard 证明只动了 deny.toml);test/refactor 红显式
       升级到人,**不再静静红 12 天**,也**不会被自动"修绿"而掩盖真 bug**。
  - **无 data-format migration**(只读 CI 结果 + 现有配置/文档文件)。
- **SemVer**: ships as **additive minor**(新 skill `ci-status`(含 `diff-guard.sh`)/agent/command;
  无 breaking CLI 变更)。具体版本号由 plan/merge 时刻定(§7.1.7 不预绑)。

## 11. 风险登记

| # | 风险 | 概率 | 影响 | 缓解 |
|---|------|------|------|------|
| R1 | **auto-fix 让事情更糟**(改了反而红 / 引入新失败) | Med | High | (a) allowlist **极小且每类可逆**(THREE 类:fmt / deny-allow-增行 / doc-count;A2 lint 已 DROP);(b) 每次 auto-fix **必重验**,变红即回滚该 attempt;(c) 人可见 commit(清晰 message + run url)便于一键 revert;(d) **绝不**碰 test/logic/refactor(那才是高破坏面) |
| R2 | **gh-flakiness false-block**(本环境间歇 EOF → 误判红/误拦) | High | High | verdict **UNKNOWN ≠ FAIL**;**可逆路径(pr-reviewer/dev)UNKNOWN 默认 WARN 不 block**(这正是这里要保住的);**不可逆 tag/promote 门有意 UNKNOWN→BLOCK**(B3,代价是偶尔多 retry 一次,换不发红 tag);EOF/parse-fail → UNKNOWN(永不误判 PASS/FAIL);§9 双向 fixture(reversible-WARN + irreversible-BLOCK)钉死 |
| R3 | **infinite remediation loop**(一直修一直红) | Med | High | **MAX_REMEDIATION=2 硬上限**;达上限仍 FAIL → ESCALATE;每 attempt 必重验 + 计数(无界 loop 是设计禁区,§7) |
| R4 | **E3 harness guard 误拦合法 in-progress push**(若 ship) | High | High | **本版不 ship E3**(主要 defer 理由);push-main 是高频动作,push 当下 CI 常"还没 run/正在跑"→ guard 极易 false-block;v.next 设计时必须 UNKNOWN/IN_PROGRESS-不拦 + `SDLC_CI_APPROVED=1` 逃生(mirror `ga-tag-guard.sh:48`) |
| R5 | E3 检测 push target 成本/正确性(判"目标 main 且该 commit 红") | Med | Med | 同 defer;v.next spike 先验证从 `git push` 命令行 + ref 解析能否廉价准确判定,再决定上 harness 牙齿 |
| R6 | **误把 ESCALATE 类当 auto-fixable**(分类错 → 碰了 test/security) | Med | **Crit** | (a) **确定性 diff-guard(组件4,B1)= 真正的兜底**:LLM 误标后,fix 跑完 `git add`,`diff-guard.sh` 审**实际 staged diff** → 碰 test〔path+content marker,跨生态〕/ 加 ignore-skip / A1 非 whitespace-only(改/删 token)/ 碰 CI yaml / 超 footprint 任一 → REJECT + `git reset --hard` + ESCALATE;**zero-LLM,误分类穿不透**(§9 用真 git staged diff 测,非 JSON 字符串);(b) **B2 确定性 pre-gate**:advisory/RUSTSEC 在 LLM 被询问前就强制 ESCALATE-security;(c) fail-safe:非 A* / confidence<阈值 → ESCALATE;(d) security/test/compile 永久 out-of-scope(§2);(e) §4.5 弱模型 degrade 倾向不 act。**关键:(a)(b) 是机器不变量,不是 prompt 规则 —— 这是 G1-B1 要求的核心修复** |
| R7 | **flaky test 被误当真红**(浪费 escalation / 误 block) | Med | Med | 重跑 N≥3 才下"红"结论(§2.3/§6.1 multi-seed);**不修 flaky 内容**(out-of-scope,交 tester);单次红不 block release |
| R8 | **越界写 CI yaml**(auto-fix 误改 `.github/workflows/*` → 撞 pipeline-emit 边界) | Low | High | `diff-guard.sh` rule(4)**机器强制**拒绝任何碰 `.github/workflows/*` 的 staged diff(非仅白名单 prompt);§2 写死"❌ 写/改 CI yaml";§9 真-diff 断言(stage 一个改 ci.yml 的 diff → 必 REJECT) |
| R9 | **gh token 泄露**(log/commit 进 message) | Low | **Crit** | `ci-status.sh` **绝不** echo/log auth;verdict 只输出 run id/url(public);§1.4;§9 加"output 无 token"断言 |
| R10 | SE16 flake(early-pipe-close under pipefail in new bash) | Low | High | mandate `case`/`awk`(reads to EOF)no-pipe 控制流;NO `\| grep -q`/`\| head -n`;shellcheck-clean in CI(`ci.yml:15-21`);stress-run ≥20× 验 flaky claim |
| R11 | **NONE 误判为 FAIL**(无 CI 空仓被全链拦,违北极星) | Med | High | NONE = SKIP gate(无 workflow ≠ 红);§7 + §9 NONE fixture 钉死;UNKNOWN/NONE 设计是核心兼容保证(§10) |
| R12 | **诊断 agent 弱模型抽烂分类** | Med | Med | §4.5 全套:schema-guided JSON + 3-retry validate + few-shot(含 A3/escalate 两例)+ 三 tier 兼容矩阵;不达标 → degrade 到"全 ESCALATE"(安全侧) |
| R13 | **promote 流与 releaser 职责重叠**(双实现漂移) | Low | Med | 先**内联 releaser**(不新增 promoter agent),`/sdlc:promote` 复用 `ci-status.sh` 同一 SSOT;promoter 独立化留 v.next 仅当 scope 证明需要 |
| R14 | **diff-guard false-reject 合法 fix**(把正当 `cargo fmt` reflow / license-allow 增行误拦,降自愈率) | Low | Med | footprint 表按 class 精确(A1=whitespace-only 源 reflow、A3=deny.toml-only、A4=docs-only);**A1 whitespace-only 不变量用 stripped-blob token 比较**(G3),真 formatter 的 line-split reflow PASS,只有改 token 才拒;§9 **正向 GUARD 行**(clean fmt reflow → exit 0;A4 *.md → exit 0)防 guard 变 false-positive blocker;guard reject 永远 fail-safe 到 ESCALATE(误拦只是少自愈一次,不损坏正确性,可逆) |
| R15 | **B3 不对称让 operator 意外**(release 门突然 UNKNOWN→BLOCK,以为坏了) | Low | Med | `ci-status.sh` UNKNOWN-at-strict 输出明确 message("irreversible gate: UNKNOWN treated as BLOCK; CI conclusion unverifiable — retry, or `--allow-unknown` to override");DEVELOP/README 文档不对称 + reversibility 理由;opt-out 路径(`--allow-unknown`/`SDLC_CI_LAX`)明示 |
| R16 | **B2 pre-gate 漏判**(advisory 输出格式变 → 没被 `*advisories*`/`*RUSTSEC-*` 命中 → 落到 LLM) | Low | High | pre-gate 用宽匹配(`advisories` 段名 + `RUSTSEC-` id 前缀,两者覆盖 cargo-deny 全部 advisory 输出形态);**即便漏到 LLM**,LLM 仍只产分类,A3 落地还要过 diff-guard footprint rule(5)(只允许 `[licenses].allow`,碰 `[advisories]` 必 REJECT)—— 双层确定性兜底;§9 "advisory wins" + footprint-overrun 两行钉死 |

## Appendix A — 出处映射

**A.1 a real CI failure → taxonomy(worked dichotomy,grounded in `deny.toml`)**

| specific CI failures observed | taxonomy | 动作 | 确定性闸门(B1/B2,非 LLM) | 依据 |
|------------------------|----------|------|---------------------------|------|
| `cargo deny check` **LICENSE policy gap**(某依赖 SPDX 不在 `[licenses].allow`,**无 advisory**) | **A3 AUTO-FIXABLE** | 把 SPDX 加进 `deny.toml [licenses].allow` **并写 documented reason** → `git add` → diff-guard PASS → re-run → 绿 → 人可见 commit | **B2 pre-gate** 先确认是 license-only(无 `advisories`/`RUSTSEC-`);**B1 diff-guard** 确认 staged diff 只动 `deny.toml [licenses].allow`(footprint) | 正是 `deny.toml:72-86` 的 allow 数组 + `:64-71` 的 per-addition reason 注释形态(可逆,只增配置行) |
| `cargo deny` **security advisory**(RUSTSEC 命中 `[advisories]`) | **ESCALATE-security** | **永不**机器自动加 ignore | **B2 pre-gate**:log 含 `advisories`/`RUSTSEC-` → LLM 被询问前就强制 ESCALATE-security;**B1**:即便漏到 A3,footprint rule(5)禁碰 `[advisories]` | `deny.toml:45-56` 每条 ignore 都需人写 rationale(IterMut path / custom-logger 分析)—— 机器无法判定"我们没走那条路" |
| `cargo test --workspace` **fail,与进行中 B4 `AppError` 重构纠缠** | **ESCALATE-test/compile** | **永不碰**(碰 = blind-edit mid-refactor,损坏别人重构 + 掩盖真 bug) | **B1 diff-guard** rule(1)/(2)/(3):即便 LLM 误标 A1 去编辑 test,staged diff 碰 test 文件〔path+content marker〕/ 加 skip-ignore / A1 非 whitespace-only → REJECT + revert + ESCALATE | 失败 test ⇒ 必须人改;mid-refactor 编译错 ⇒ 不可机器盲编辑 |
| `cargo fmt --check` 红 | **A1 AUTO-FIXABLE** | `cargo fmt`(命令从 stack-config 取)→ `git add` → diff-guard PASS → commit | **B1 diff-guard** 确认 staged diff 是 **whitespace-only**(去空白后 token 与 HEAD 全等),未碰 test/CI/`*.md`/`deny.toml` | 纯格式 reflow,完全可逆 |
| `cargo clippy --fix` 类 lint `--check` 红 | **ESCALATE(A2 DROPPED,G3)** | **不自动修** —— lint 是语义改写,无法 whitespace-only 守门 → 升级人工 | **B1 diff-guard** `--class A2` = usage error;lint 改动若误标 A1 必因非-whitespace-only 被拒 | 语义改写不可逆/不可证安全 |

**核心 dichotomy(一句话)**:**配置-allowlist 加行(license-only,A3)+ formatter whitespace-only
reflow(A1)+ doc-count 同步(A4)** = 可逆低风险 → 自动修(**G3:lint-autofix〔A2〕已 DROP**);
**任何 test / lint / logic / security-advisory / mid-refactor 编译** = 不可逆/高破坏/需人判断 → 升级。
**关键:这个 dichotomy 不靠 LLM 自觉兑现 —— B2 确定性 pre-gate 把 advisory 在 LLM 之前拦掉,B1 确定性
diff-guard 审实际 staged diff 把任何越界(碰 test〔path+content marker,跨生态〕/ 加 ignore /
A1 非 whitespace-only / 碰 CI yaml / 超 footprint)在 commit 之前拦掉。LLM 只分类,脚本守门。allowlist
之外一律 ESCALATE(fail-safe)。**

**A.2 §4.2.4 #13/#14 → this feature**

| 全局规则 | 本 feature 落地 |
|----------|----------------|
| §4.2.4 **#13 CI 硬门**(promote/merge to main 前 `gh run list`/`gh pr checks` 确认绿;红→不推;**禁止忽略 github CI 结果继续开发**) | E1 `ci-status.sh`(`gh run list`/`gh pr checks` 的确定性封装)+ E2 接进 releaser **rule 12 / lines 130-145**(OBSERVED-GREEN)/ pr-reviewer / `/sdlc:promote`;红→BLOCK;**tag/promote 门 UNKNOWN→BLOCK(B3)** |
| §4.2.4 **#14 develop↔main 回合**(main 只收整理过的原子 commit + CI 绿 + tag;`--no-ff` merge 锚点) | 新 `/sdlc:promote`:promote 前 `ci-status.sh --require-known`(strict default)断言 verdict=PASS **且** 已 tag;UNKNOWN/红→拒绝 |
| 同病映射(prompt 规则 → enforced gate) | GA-tag:`ga-tag-guard`(v0.18,`ga-tag-guard.sh:48`);doc-sync:`doc-audit-content-gate`(v0.24);**CI-green:本 feature**(第三个)。**本 feature 自己也吃这一招**:auto-edit 红仓代码这个不可逆操作,由确定性 diff-guard(B1)守门,不靠 prompt 规则 |

**Bottom line(诚实声明)**: 本 feature **可靠自愈** 的只有极小 allowlist —— **THREE 类**:fmt(A1)/
deny-LICENSE-allow(A3)/ doc-sync(A4);**lint-autofix(A2)在 G3 remediation 中已 DROP,和真正的
代码问题**(test / lint / logic / security / mid-refactor)一样**显式升级到人**,绝不自动碰。**而且
"绝不自动碰"不是一句 prompt 承诺 —— 它由两个 zero-LLM 闸门机器强制:B2 advisory pre-gate(LLM 之前拦
security)+ B1 post-fix diff-guard(commit 之前审实际 staged diff:碰 test〔path+content marker,跨
生态〕/ 加 ignore-skip / A1 非 whitespace-only / 碰 CI yaml / 超 footprint 即 revert+ESCALATE)。
G3 把 A1 从可被注释/括号/不支持框架击穿的 token 计数,升级为 whitespace-only 不变量,从构造上
tamper-proof。** 这正是 the 12-day red CI case 该有的处置:license 缺口几分钟自愈(且经 diff-guard
证明只动了 deny.toml),test/lint/refactor 红立刻摆到人面前,而不是静静红着,也不会被"自动修绿"掩盖真 bug。

---

## Handoff (spec → plan)

```yaml
# docs/superpowers/handoffs/2026-06-05-ci-green-gate_spec_draft.yaml
schema_version: 2
producer: spec-analyst
model_tier: opus
sprint_id: "2026-06-05-ci-green-gate"
phase_from: spec
phase_to: plan
artifact_path: "docs/superpowers/specs/2026-06-05-ci-green-gate.md"
artifact_sha: "<git hash-object docs/superpowers/specs/2026-06-05-ci-green-gate.md>"  # fill at materialization; validate.sh:50-51 must match
timestamp_utc8: "2026-06-05T16:00:00+08:00"
deliverables_proposed:
  - "skills/ci-status/ci-status.sh — deterministic CI verdict (PASS/FAIL/IN_PROGRESS/UNKNOWN/NONE), SDLC_GH_BIN-injectable, zero-LLM, SE16-safe; path-asymmetric strict (B3: --require-known default on irreversible tag/promote gate)"
  - "skills/ci-status/diff-guard.sh — B1 zero-LLM post-fix diff-guard on `git diff --cached`: REJECT (exit1→caller reverts+ESCALATE) if touches test path / adds skip-ignore / nets assertions DOWN / touches .github/workflows/* / exceeds per-class EXPECTED FILE FOOTPRINT; the load-bearing safety mechanism"
  - "skills/ci-status/SKILL.md"
  - "tests/ci-status.bats — gh-stub fixtures (PASS/FAIL/in-progress/EOF + run-view --log-failed, N2) + B1 REAL-staged-diff GUARD rows (touch-test/add-ignore/remove-assert/edit-CI-yaml/A3-footprint-overrun/clean-fmt-positive) + B2 advisory-pre-gate (advisory-wins) + real-project-shaped deny-license vs test-escalate"
  - "agents/ci-remediator.md — LLM diagnosis+classify agent (sonnet, §4.5); ONLY proposes class+fix; auto-fix step MUST call diff-guard.sh before commit; B2 advisory pre-gate runs BEFORE the LLM; bounded loop; fail-safe ESCALATE"
  - "agents/releaser.md (edit) — rule 12 / lines 130-145 (OBSERVED-GREEN real CI) wires `ci-status.sh --require-known` (strict default at tag gate, B3) + verdict consume"
  - "agents/pr-reviewer.md (edit) — R2 (REVIEW_DONE @ line 188) asserts branch HEAD verdict != FAIL; UNKNOWN=WARN (reversible path, B3)"
  - "commands/promote.md — /sdlc:promote (#14): `ci-status.sh --require-known` (UNKNOWN→BLOCK) + tagged assertion before develop→main"
  - "README.md / DEVELOP.md / RELEASE.md (edit) — document 5 components + diff-guard + path-asymmetric UNKNOWN policy; update inventory counts (dogfood v0.24 doc-audit: agents 17→18, commands 26→27, skills 20→21)"
risks_to_flag_in_plan:
  - "B1/R6 — diff-guard.sh is the load-bearing safety mechanism; its REAL-staged-diff GUARD tests (not JSON-string) must be BLOCKING acceptance judges; a plan that ships ci-remediator without diff-guard wired-before-commit is a non-starter"
  - "B2/R16 — A3 license-vs-advisory split must be a deterministic pre-gate on cargo-deny output class, running BEFORE the LLM; advisory/RUSTSEC → forced ESCALATE-security; A3 footprint = [licenses].allow append only"
  - "B3/R2/R15 — pin --require-known DEFAULT at releaser RC gate + /sdlc:promote (UNKNOWN→BLOCK, reversibility-justified); keep WARN-default on pr-reviewer/dev; do NOT regress to global WARN"
  - "R4/R5 E3 harness guard DEFERRED — plan must NOT include E3 (component 5); diff-guard (component 4) IS in-scope and mandatory — do not conflate them"
  - "N2 gh-stub must serve `run view --log-failed`; N3 flaky rerun = re-QUERY same run id, not re-trigger CI; N4 META inventory counts pinned (no `?`)"
estimated_minor: "additive minor (number assigned at merge per §7.1.7)"
estimated_tokens: 16000
estimated_duration_hours: "honest wall-clock unknown at spec time; plan to estimate per task (§1.2 — no fabricated hours)"
disk_snapshot_before: "PENDING — releaser/impl runs `df -h / /tmp /data` first line at build time (§1.1.6)"
self_score:
  rubric_ref: "spec (Appendix E.1)"
  prior_self_score: 5.0          # G1-challenger independent: 4.4, REVISE-REQUIRED (B1 Critical + B2/B3 Important)
  criteria_scores:
    scope_clarity: 5      # 5 components pinned (incl. diff-guard MANDATORY, E3 DEFERRED); A3 footprint pinned (B2); UNKNOWN policy now path-asymmetric & PINNED not 建议 (B3); explicit out-of-scope >2
    risk_register: 5      # 16 risks (was 13; +R14 diff-guard false-reject, +R15 B3-asymmetry surprise, +R16 B2 pre-gate miss), all 4-field; R6/R8 mitigations now cite the REAL mechanism not aspirational guard
    test_matrix: 5        # all 6 categories + B1 6× REAL-staged-diff GUARD rows (mechanical, not string) + B2 advisory-wins + run-view mock (N2) + META counts pinned (N4) + positive clean-fmt guard row
    migration: 5          # §10 worked old→new now includes B2 pre-gate + B1 diff-guard step + B3 UNKNOWN-at-tag→BLOCK; back-compat asymmetry explained (reversible unchanged / irreversible intentionally tightened)
    cost_contract: 5      # §8 unchanged-valid: disk 0; token E1/diff-guard=0, remediator bounded ~4-12K/red; wall-clock; audit cmd — diff-guard is zero-LLM (no token delta)
  overall: 5.0            # self-assessed PASS after addressing all 3 blocking findings with deterministic mechanisms + 4 nits; the +1 drift the challenger flagged was on B1/B2/B3-touched criteria, now mechanized
  weak_points:
    - "estimated_duration_hours honest-unknown at spec time (§1.2) — architect/planner to fill per-task"
    - "promoter agent vs inline-releaser decision deferred to plan (R13) — spec recommends inline-first"
    - "E3 harness guard (component 5) ship-vs-defer remains a DEFER recommendation; diff-guard (component 4) is NOT deferred — it is mandatory this version"
    - "diff-guard's net-assertion-count heuristic (rule 3) is line-grep-based; a pathological reformat that moves asserts across lines could miscount — mitigated by R14 (fail-safe to ESCALATE on reject) + the positive clean-fmt test guarding against over-blocking"
```

Validation: `bash skills/handoff-schema/validate.sh docs/superpowers/handoffs/2026-06-05-ci-green-gate_spec_draft.yaml`
must exit 0 (after the handoff file is materialized + artifact_sha computed) before returning control to task-orchestrator.
