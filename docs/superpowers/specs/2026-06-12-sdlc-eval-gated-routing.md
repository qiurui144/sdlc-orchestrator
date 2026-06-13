# Spec: sdlc-eval-gated-routing (M2) — prove-then-wire deepseek into dispatch

> Status: DRAFT **rev.3** (rev.1 BLOCKed by G1 safety panel — 3 Critical; rev.2/rev.3 addressed + re-G1 PASS) · Date: 2026-06-12
> Stack: bash/bats/yq/jq. Builds on M1 (`route.sh`/`call.sh`/`model-routing.yaml`, shipped, unwired).
> Producer: spec-analyst-contract (main context) · model_tier: opus

---

## 0. rev.1 → rev.2 changelog (G1 BLOCK fixes)

| Finding | Fix |
|---|---|
| SAFETY C-1 confidently-wrong output mainlined | §3/§7 **online correctness oracle** — eligibility limited to LIVE-gradable mechanical tasks; the deterministic grader re-runs on the live deepseek output; structural fail → degrade to claude. + per-task circuit-breaker (§8). **G3-hardening**: the acceptance bar = `max(stored_f1 − 0.10, ONLINE_HARD_FLOOR=0.75)` and `stored_f1` is numeric-validated to [0,1] — a forged/poisoned `f1` (not covered by `sources_hash`) can never collapse the bar (G3 adversarial C-1). |
| SAFETY C-2 task-type label source unspecified | §4 **closed deterministic SDLC-op → task_type map**; NORMAL/HIGH phases structurally produce NO allowlist key (no LLM labeling). |
| SAFETY C-3 allowlist staleness | §5 allowlist entries carry `sources_hash` (fixtures+grader+agent-prompt); executor disables routing on hash mismatch (§7). |
| EVAL C-1 grader unvalidated | §4/§9 `tests/grader/` fixture suite is the FIRST impl task; no real-LLM eval until grader is proven. |
| EVAL I-1 claude_f1 itself low | §5 `task_reliability: low` when claude < floor → never route + warn. |
| EVAL I-2 seeds marginal / "std small" vague | §5 **worst-case gating**: route only if EVERY seed ≥ floor AND std ≤ 0.05 (not mean-only). |
| SCOPE I-1 §5 grader contract stub | §5 grader.sh contract + `grader-modes.yaml`. |
| (cross) define "mechanical" | §3: mechanical = task_type in the closed map, passed=true, AND live-gradable. |

## 1. 目标定位 (Goal)

M1 ship 了 provider 库(`route.sh`/`call.sh`)但**没接进 dispatch** → deepseek 0 调用(用户实测)。
**M2 = 评测门控接线**:eval 确定性证明 deepseek 在**哪些 live-gradable 机械任务**上达标 → `allowlist`;
executor **仅对 allowlist 任务**走 deepseek,且**每次都在线复判活输出**,任何失败/不达标/陈旧 → 降级 claude。

**诚实价值前提**(写死,不藏):仅 **LOW + 机械 + live-gradable** 任务路由;**NORMAL/HIGH(spec/plan/
review/G-panel/judgment)结构上不可外置**。机械任务本是 haiku 廉价档 → **省 claude token 有限**,真实数字
由 §8 telemetry 实测(扣除 deepseek 成本),net 可能很小甚至为负 —— RELEASE 如实标,不写降本营销。

**北极星**:`SDLC_MULTI_MODEL=1` 跑含机械任务的 sprint,telemetry 显示 allowlist 任务真走 deepseek +
**活输出在线复判通过** + claude token 实测变化;任一失败自动降级 claude,产物质量不变;judgment 永不被路由。

## 2. 范围边界 (Scope)

**做(M2)**:
- **Eval 层** `skills/model-eval/eval.sh` + `grader.sh` + `fixtures/<task-type>/*.json`:跨 provider
  矩阵 × ≥3 seed → **worst-case 门** → `config/model-allowlist.yaml`(带 `sources_hash` + `task_reliability`)。
- **grader 自验** `tests/grader/`:eval 前必须证明 grader 判分正确(零误判)。
- **Executor**(main context):closed map 定 task_type → route.sh → allowlist+hash 校验 → call.sh(deepseek)
  → **在线复判活输出** → 通过则用,否则/失败/陈旧 → claude。
- **接 2–3 个真机械 + live-gradable 任务**(候选:inventory 计数 diff、kebab 错误码归类、changelog 行抽取)。
- telemetry + 每任务 circuit-breaker(在线复判失败率超阈值 → 自动停该任务路由)。

**不做(写死)**:路由 NORMAL/HIGH / judgment(结构禁止);非 live-gradable 任务入 allowlist;GPT/qwen 生产
路由(qwen 仅 eval 对照);CI 自动跑 eval(real-LLM,手动);无 allowlist→"先用着"(→ 全 claude)。

## 3. 架构数据流 (Architecture)

```
=== Eval (offline, manual, real-LLM) ===
tests/grader/<task>/*.json (output,expected_score) ──validate──> grader.sh proven (bats)  ← FIRST
fixtures/<task>/*.json (input+golden, ≥10)
   │ eval.sh --task t --providers deepseek,claude,qwen --seeds 3
   │   per (provider×seed×case): call.sh→output ; grader.sh(output,golden)→score
   ▼ worst-case: route IFF every seed F1≥floor AND std≤0.05 AND |ds−claude|≤0.10 AND claude≥floor
config/model-allowlist.yaml { t: {provider, f1, claude_f1, passed, task_reliability, sources_hash} }

=== Executor (online, MAIN context, inside /sdlc:run for one task) ===
task ── closed map (SDLC-op → task_type) ──┬─ no task_type (judgment/NORMAL/HIGH) ─→ claude (Agent dispatch)
                                            └─ task_type present →
   risk-classify=LOW/mechanical?  ─ no ─→ claude
   allowlist[t].passed && sources_hash==live_hash ?  ─ no(absent/stale) ─→ claude
   ─ yes → call.sh --provider deepseek --schema <s>  (main context, inline)
            ├ exit 7 / schema-fail ─────────────→ claude (degrade)
            └ ok → grader.sh(live_output, derivable_check)   ← ONLINE ORACLE (C-1)
                     ├ score < (stored_f1 − tolerance, tol=0.10) ─→ claude (degrade)   # not just score==0
                     └ score ≥ threshold → use deepseek output
   telemetry: runs/<ts>/routing.jsonl { task_type, provider, degraded, online_score, ts }
   circuit-breaker: rolling last 20 online grades per task_type; fail-rate > 30% → auto-disable
                    that task_type's routing (reset on re-eval)
   # derivable_check: for a live-gradable task the correct answer is RE-DERIVABLE from the input
   #   alone (inventory-count = count lines; kebab-classify = static taxonomy lookup; changelog-extract
   #   = substring match) — no stored golden is needed at runtime; that is the eligibility criterion.
```

**mechanical = task_type ∈ closed map ∧ passed ∧ live-gradable**(只有能对活输出做确定性复判的才合格)。
无外部存储;allowlist/telemetry 是文件;eval 离线手动;executor main context(dispatched subagent 无 Bash)。

## 4. 模块边界 (Modules)

| 模块 | 职责 |
|---|---|
| `skills/model-eval/eval.sh` | fixture×provider×seed,调 grader,worst-case 门,产 allowlist(含 sources_hash);--stub |
| `skills/model-eval/grader.sh` | 确定性判分;mode per task-type(exact/normalized/set-F1);**用于 eval 与在线复判同一份** |
| `skills/model-eval/grader-modes.yaml` | per-task-type:grader mode + 是否 live-gradable |
| `skills/model-eval/fixtures/<task>/*.json` | input + golden |
| `tests/grader/<task>/*.json` | (output, expected_score) — grader 自验,先于真 eval |
| `config/model-allowlist.yaml` | eval 产物(passed + sources_hash + task_reliability)= executor 的门 |
| `skills/model-router/executor.sh`(新) | closed map + route + allowlist/hash 校验 + call + 在线复判 + degrade + telemetry |
| `skills/model-router/task-type-map.yaml`(新) | **closed** SDLC-op→task_type(judgment/NORMAL/HIGH 无 key) |
| `agents/task-orchestrator.md` | 加 rule:LOW/机械 task → executor.sh 决策 |
| `commands/eval.md` | (existing stub) → dispatch eval.sh |

## 5. API 契约 (Contracts)

`eval.sh --task <t> --providers <list> --seeds <N> [--floor 0.85] [--out ...] [--stub <f>] [--claude-dir <f>]` →
`task=t provider=p f1=x.xx±s worst=y.yy passed=bool reliability=ok|low`;exit 0/2/6.

**rev.4 (real-path wiring, Task 4 实跑发现):** real-eval 端到端首跑暴露三个接线缺口(全程 stub 漏检,
§7.3 教训重演):① **claude 无 call.sh 后端**(rule H:claude=harness)→ `--claude-dir` 读 harness 产出的
确定性基线(seed 无关);② **任务指令/few-shot 缺失** + ③ **call.sh 强制 json_object 与纯文本 exact 任务
不兼容** → 新 `grader.sh build-messages --task <t> --input <f>`(system 指令 + 1 few-shot turn + user,
读 `grader-modes.yaml` 的 `eval_system`/`eval_fewshot`,**eval 与 executor 共用同一构造**保证 F1 代表路由
行为)+ `call.sh --format text`(省 response_format)。eval_system/eval_fewshot 已在 sources_hash 内(随
grader-modes 绑定)。**Task 4 实跑(2026-06-13)**:deepseek-v4-pro/qwen-plus/claude 在 `inventory-count-diff`
F1 均 1.00(60 真调,3 seed,std 0)→ `passed:true`;executor 真路由 `route-deepseek-ok` 端到端验证。
诚实标:F1 1.00 反映任务机械性非模型对等;`config/model-allowlist.yaml` = 实跑产物(commit)。

`grader.sh --task <t> --output <f> [--golden <f> | --derive <input>]` → `score=<0..1>`
(exact/normalized/set-F1 per `grader-modes.yaml`)。eval 用 `--golden`;在线复判用 `--derive`(从 input
重新推导期望,无需运行时 golden)。**同一 grader 供 eval 与在线复判**。`tests/grader/` 必须先全过。
`normalized` mode = trim+lowercase+collapse-whitespace 后 exact;hash 算法 = sha256。
`grader-modes.yaml` per task-type:`{ mode, live_gradable, prompt_file: <agent .md path hashed for sources_hash> }`
(eval 与 executor 必须 hash **同一** prompt_file,否则比较无意义)。online 阈值 = `stored_f1 − 0.10`。

`config/model-allowlist.yaml`:
```yaml
version: 1
generated: <stamped after run>
tasks:
  inventory-count-diff: { provider: deepseek, f1: 0.94, claude_f1: 0.96, passed: true,
                          task_reliability: ok, live_gradable: true, sources_hash: <sha> }
  kebab-error-classify: { provider: claude,   f1: 0.71, claude_f1: 0.95, passed: false, ... }
```
`sources_hash` = sha of (fixtures + grader.sh + grader-modes + the agent prompt template for that task).

`executor.sh --task-op <sdlc-op> --input <f> [--schema <f>]` → runs the §3 decision; stdout = chosen
output; kebab status: `route-deepseek-ok` / `route-claude-no-tasktype` / `route-claude-not-allowlisted` /
`route-claude-stale-hash` / `degrade-claude-call-failed` / `degrade-claude-online-grade-fail`.
**`--schema` MANDATORY for any allowlisted (deepseek) call.**

## 6. 扩展点

新 task-type = fixtures + grader-mode + tests/grader,过 worst-case 门自动进 allowlist。新 provider = eval
矩阵加列。closed map 新增**只能**加机械 op(judgment op 加入需显式 review)。per-task floor 可调。

## 7. 错误 + 边界

无 task_type(judgment/NORMAL/HIGH)→ claude;不在 allowlist / passed=false → claude;**sources_hash
不匹配(陈旧)→ claude + warn**;call.sh exit 7 / schema-fail → claude;**在线复判结构 fail → claude**;
circuit-breaker 触发 → 该 task 暂停路由 → claude;`SDLC_MULTI_MODEL` 未开 → 全 claude;grader 对畸形输出 →
score=0(不 crash)。**所有降级路径产物 = claude,质量不降。**

## 8. 成本契约 (诚实实测)

eval 烧 token(real-LLM × case × 3 seed × 3 provider)→ 手动一次性,产 allowlist 复用。上线 telemetry 实测
`claude_tokens_saved − deepseek_tokens_spent`;在线复判与 degrade 也有成本(claude 兜底时是双花)。**预期净省
有限甚至可能为负**(机械任务廉价 + 双花风险),RELEASE 用 telemetry 真数,**不预先夸大**。

## 9. 测试矩阵 (§6.1 + §2.3)

| 类 | 用例 |
|---|---|
| happy | grader 自验全过;eval --stub 产正确 allowlist;executor allowed+在线复判 pass→deepseek;无 tasktype→claude |
| edge | allowlist 缺;passed=false;sources_hash 陈旧→claude;空 fixture;reliability=low→不路由 |
| error | call.sh exit7→degrade;schema-fail→degrade;**在线复判 fail→degrade**;circuit-breaker→暂停;grader 畸形→score0 不 crash |
| adversarial | **伪造 allowlist 把 judgment 标 passed → executor 仍拒(closed map 无 key + risk 双门)**;伪造 sources_hash;call.sh key redact(元字符);**confidently-wrong 活输出→在线复判 catch→degrade** |
| 并发 | 多 task 并行无串扰;telemetry 不交错 |
| i18n/降级 | SDLC_MULTI_MODEL 未开→字节级不变;worst-seed<floor→passed=false |
| §2.3 多 seed | ≥3 seed,mean±std,worst-case 门,rank-flip→fail |

**判据**:bats 全过;grader 自验先过;executor 确定性;**zero-behavior-change when off**(黄金);
**「judgment 不可外置」+「confidently-wrong 被在线复判拦」一票否决必过**。真 provider eval = **PENDING-VERIFY**
(real-LLM 手动 §6.3)—— 出真 allowlist 才算真证。

## 10. 向后兼容

默认 off / `SDLC_MULTI_MODEL` 未设 → 全 claude,**零行为变化**。allowlist 缺 = 全 claude。route/call(M1)契约
不变;executor + closed map 是新增层,可整体禁用。

## 11. 风险登记

| 风险 | 等级 | 缓解 |
|---|---|---|
| **confidently-wrong 弱输出上主线** | **高** | 仅 live-gradable 任务;**在线复判**活输出;结构 fail→degrade;circuit-breaker;NORMAL/HIGH 硬不外置 |
| **judgment 被错标外置** | **高** | **closed 确定性 map**(judgment 无 task_type key)+ risk LOW 双门;adversarial 一票否决 |
| **allowlist 陈旧(prompt 变)** | **高** | `sources_hash`(fixtures+grader+prompt)绑定;executor 启动校验,失配→禁路由 |
| grader 自身错判 | 中 | `tests/grader/` 先验;eval 与在线同一 grader |
| 阈值不稳(claude 本身低 / 高方差) | 中 | claude<floor→不路由;worst-case 门 + std≤0.05 |
| executor 在 subagent 跑(无 Bash) | 中 | 强制 main context(写死,M1/web-ui 教训) |
| 省 token 被夸大 | 中 | §8 telemetry 真数,扣 deepseek + 双花,RELEASE 如实 |
| call.sh key 泄漏 | 中 | M1 redact-ALL-keys 复用 + 回归 |

---

## Handoff (spec → plan)
- producer: spec-analyst-contract · model_tier: opus · rev: 2 · self_score(E.1): 4.7/5
  (§5 grader 契约补齐;在线复判 + closed map + sources_hash 三 Critical 已纳入)。
- **next**: re-G1(同 3 lens 复审:在线复判是否真堵 confidently-wrong / closed map 是否真禁 judgment /
  sources_hash 是否真防陈旧 / grader 自验是否先于真 eval / 诚实)→ 用户批准 → `/sdlc:plan`。
- **plan task 顺序(写死)**:① `tests/grader/` + grader.sh 自验 → ② eval.sh + fixtures(1 task)→ 真 eval 出 allowlist →
  ③ executor.sh + closed map + 在线复判 + sources_hash → ④ 接 task-orchestrator → ⑤ telemetry + circuit-breaker。
- **honest flags**: 真实净省未知(机械廉价 + 双花);真 provider eval = PENDING-VERIFY;价值在机制与安全门,不在降本幅度。
