# Spec: cost-measurement (C-1) — make routing savings measurable

> Status: DRAFT **rev.2** (G1 panel CONCERNS×3 addressed) · Date: 2026-06-13 · Producer: spec-analyst-contract · model_tier: opus
> Stack: bash/bats/yq/jq. Builds on M2 (executor.sh routing + routing.jsonl telemetry, shipped v1.1.0).
> Part of the cost-deepening roadmap: **v1.2.0 (this spec) → v1.3.0 (C-2 judgment-tier downgrade)**.

## 0. rev.1 → rev.2 changelog (G1 panel fixes)

| Finding | Fix |
|---|---|
| MEAS-F1 + HON-3 net 公式重复扣减(degrade 把 claude-重做当额外损失,baseline 本就含;call-failed 没烧 token 却计 ds 损失) | §3 net 重定义为 `baseline(全 claude 反事实) − actual(实付)`;degrade 的额外损失**仅** ds_wasted(白烧的 deepseek token,call-failed=0);claude 重做不重复扣。 |
| MEAS-F2 claude_equiv 是估算非实测(tokenizer/输出长度差 ±15%) | §1/§8 措辞降级:deepseek 侧**实测**(真付),claude 侧**反事实估算**(estimate);net 标 estimated,不称"实测省钱"。 |
| MEAS-F5 task_claude_tier 默认 sonnet 高估 saved | §4 默认 **haiku**(机械 op 的真实反事实最便宜 tier);per-op 可覆盖。保守不高估。 |
| HON-1 null→0 偷漏(`// 0`/`// 6000` 把缺失当默认) | §5/§7 **禁 `// 0`**;net 项 two-term-both-present 才计入,缺任一→unmeasured(一票否决测试)。 |
| HON-2 measured vs estimated 混一个 net | §5 输出分列 `ds_spent_measured` / `claude_saved_estimated` / `net_estimated`。 |
| HON-3b degrade 按 `degraded` 布尔误扫 route-claude-*(零浪费) | §3 按**具体 decision** 串扣:仅 `degrade-*` 计 ds_wasted;`route-claude-*` 零浪费。 |
| HON-4 高 unmeasured 当全量结论(§6.3) | §5 输出 `coverage=measured/(measured+unmeasured)`;coverage < 0.5 打 `non-representative` 标。 |
| ISO-1 redact 不覆盖 usage sink(proxy 回显 key 绕脱敏) | §5/§7 sink = **闭合 4 字段 schema**(in/out 整数 + provider/model 字面量),不裸传 response;脱敏防御测试。 |
| ISO-2 黄金测试漏 `--usage-out` ON 时 stdout=content-only | §9 补 ON 黄金 case(ON 时 stdout 仍字节=content)。 |
| ISO-3 sink I/O 失败/缺 pricing 须对路由主路非致命 | §7 sink 写失败/缺 pricing → 不改 exit/不翻 decision,该项标 unmeasured。 |

---

## 1. 目标定位 (Goal)

M2 的诚实缺口:净省**未量化**(`call.sh` 不暴露 provider `usage`,claude 侧不走 `call.sh`,
`pricing.yaml` 无 deepseek/qwen 价)。本 feature 让每次路由的成本**有据**——其中 **deepseek 侧是实测**
(真付的 token),**claude 侧是反事实估算**(同 token 按 claude tier 计价,非真跑 claude)。诚实成本契约
(§8 / §1.2)从"完全未测量"升级为"deepseek 实测 + claude 反事实估算,net 标 estimated"。这是任何深入
降本(尤其 C-2 判断任务降级)的数据前提。

**不解决**(C-2,下个 minor):把判断任务降 tier。本 feature 只测量,不改路由决策。

## 2. 范围边界 (Scope)

**做**:
- `pricing.yaml` 补 deepseek / qwen 单价(input/output per 1M),与 claude tier 并列。
- `call.sh` 解析 response 的 `usage`(prompt_tokens / completion_tokens),可选写入一个 usage sink。
- `executor.sh` 路由 telemetry(`routing.jsonl`)记录每次路由的真实 token + 估算的 claude-等价成本。
- `cost.sh` 新增 `--compare`:读 telemetry,输出 **claude-only baseline vs with-routing actual** 的
  net token / USD 对比(含 degrade 双花扣除)。

**不做(写死)**:改任何路由/降级决策(C-2);prompt-cache 计量(插件控制不了 cache,见
the harness owns prompt-cache, not the plugin);claude 主链 agent 的精确 token(harness 不暴露给插件,
只能用 `cost.sh` 估算模型);多 provider 生产路由(qwen 仍仅 eval 对照)。

## 3. 架构数据流 (Architecture)

```
deepseek/qwen call (executor.sh step 4)
  └─ call.sh --provider X --messages m [--usage-out <f>]
       └─ HTTP response → jq '.usage' → {prompt_tokens, completion_tokens}
            └─ write usage to --usage-out (json line); stdout still = content only (unchanged)
executor.sh (after a route decision)
  └─ routing.jsonl += {op, decision, degraded, provider, in_tok, out_tok,
                        ds_usd, claude_equiv_usd}   # claude_equiv = same tokens priced at the
                                                    # task's claude tier (the counterfactual baseline)
cost.sh --compare [<telemetry>]
  └─ Σ over routing.jsonl, BY SPECIFIC decision (not the `degraded` bool — that would
     wrongly sweep the zero-waste route-claude-* fallbacks):
       saved_est  = Σ(claude_equiv_usd where decision == route-deepseek-ok)   # ESTIMATE: what
                                                                              #   claude(haiku) would have cost
       ds_spent   = Σ(ds_usd          where decision == route-deepseek-ok)    # MEASURED: deepseek actually paid
       ds_wasted  = Σ(ds_usd          where decision == degrade-*)            # MEASURED: deepseek burned then
                                                                              #   thrown away (call-failed=0)
       # route-claude-* (not-allowlisted/stale-hash/breaker/disabled/no-tasktype) never called deepseek
       #   -> baseline == actual == claude -> ZERO net contribution (not saved, not wasted).
       # On degrade the op falls back to claude; that claude cost is the SAME as the baseline for that op,
       #   so it cancels -> the ONLY extra loss is the wasted deepseek tokens. NOT re-charged. (MEAS-F1)
       net_est    = saved_est − ds_spent − ds_wasted
       coverage   = measured_routes / (measured_routes + unmeasured_routes)
     → print: ds_spent_measured · claude_saved_estimated · net_estimated · coverage · routes · degrades ·
              unmeasured; coverage<0.5 -> tag `non-representative`; honest sign (net can be negative).
```

`pricing.yaml` tiers gain `deepseek`/`qwen` rows. `claude_equiv` uses the op's `task_claude_tier`
(`task-type-map.yaml`) — **default haiku** (a mechanical op's realistic counterfactual is the cheapest
claude tier; defaulting to sonnet would overstate saved, MEAS-F5). It is an ESTIMATE (same token count
priced at the claude tier; tokenizers differ ±15%), never a measured claude run.

## 4. 模块边界 (Modules)

| 文件 | 改动 |
|---|---|
| `config/pricing.yaml` | + deepseek / qwen rows (input/output per 1M, ESTIMATE + `as_of`) |
| `skills/model-provider/call.sh` | parse `.usage`; `--usage-out <f>` writes `{in,out}` (stdout unchanged) |
| `skills/model-router/task-type-map.yaml` | + `task_claude_tier` per op (the counterfactual baseline tier) |
| `skills/model-router/executor.sh` | enrich `routing.jsonl` with token + ds_usd + claude_equiv_usd |
| `skills/cost-estimation/cost.sh` | + `--compare` mode (baseline vs actual vs NET) |
| `tests/unit/test_cost_compare.bats`, `test_model_provider.bats` | new + extended |

## 5. API 契约 (Contracts)

- `call.sh ... [--usage-out <f>]` → on success ALSO appends a **closed 4-field schema** to `<f>`:
  `{"in":<int|null>,"out":<int|null>,"provider":"<literal>","model":"<literal>"}` — built field-by-field
  from parsed integers + the known provider/model literals, **never** by echoing the raw response (so a
  proxy that reflects a key in `.usage` can't leak it, ISO-1). stdout stays content-only (ON or OFF,
  byte-identical, ISO-2). Absent `--usage-out` → today's behavior byte-identical. Missing/duplicate
  `.usage` → `in/out=null` (never fabricate 0 — UNMEASURED is honest). Sink write failure → non-fatal:
  do NOT change exit code or stdout (ISO-3).
- `cost.sh --compare [<telemetry-file>]` → `ds_spent_measured=… claude_saved_estimated=… net_estimated=…
  coverage=… routes=<n> degrades=<n> unmeasured=<n>`; exit 0. A net term is included ONLY when BOTH its
  operands are non-null — **no `// 0` defaulting** (a null operand → that route counts as unmeasured, never
  as 0 savings, HON-1). No telemetry → `net=UNMEASURED`, exit 0. coverage<0.5 → append `non-representative`.
- `pricing.yaml`: `tiers.deepseek: {input, output}` / `tiers.qwen: {…}` (per-1M USD, `as_of` + ESTIMATE).
  `cost.sh` reads provider price by name; missing provider price → that route unmeasured (not 0).

## 6. 扩展点 (Extensibility)

新 provider 降本计量 = `pricing.yaml` 加一行 + (若路由)`task_claude_tier`。`--compare` 自动纳入。
未来 C-2 的 tier-downgrade 复用同一 telemetry schema(记 baseline tier vs actual tier 的 token 差)。

## 7. 错误 + 边界 (Errors)

- response 无/重复 `usage`(某些 provider/proxy 不返回)→ `in/out=null` → `--compare` 计为 `unmeasured`
  (单列计数),不混入 net。**绝不**把 null 当 0(否则虚报省钱);实现禁 `// 0`/`// <default>`。
- pricing 缺某 provider → 该路由标 `unmeasured`(不计 0)。
- telemetry 行畸形 → 跳过 + 计 1 个 skipped(不 crash)。
- **degrade-* 行** → 仅 `ds_wasted`(白烧的 deepseek;`degrade-call-failed` 没发出请求→ds_wasted=0)计入,
  net 减;claude 重做**不**重复扣(baseline 已含该 op 的 claude 成本)。`route-claude-*` → 零 net 贡献。
- **usage sink 写失败 / I/O 错** → 非致命:不改 call.sh exit code、不改 stdout、不翻路由 decision(ISO-3)。
- **usage sink 脱敏** → sink 只写解析出的整数 + provider/model 字面量,response 任何回显的 secret 不进 sink(ISO-1)。

## 8. 成本契约 (Cost)

测量本身**零额外 LLM 成本**(读已有 response 的 usage 字段;cost.sh 是确定性聚合)。`--usage-out` 写本地
文件。**诚实**:`claude_equiv` 是反事实估算(同 token 按 claude tier 计价),不是真跑 claude 的实测——
标注为 estimate。net 可为负(机械任务廉价 + degrade 双花),`--compare` 如实输出符号。

## 9. 测试矩阵 (Test)

| 类 | 用例 |
|---|---|
| happy | stub response 带 usage → call.sh --usage-out 写闭合 4 字段;executor telemetry 含 token+usd;--compare net 正确 |
| edge | usage 缺失/重复→null→unmeasured(不计 0);空 telemetry→UNMEASURED;degrade-* 扣 ds_wasted;call-failed→ds_wasted=0;route-claude-* 零贡献 |
| error | 畸形 telemetry 行→skip 计数;pricing 缺 provider→该路由 unmeasured;sink I/O 失败→不改 exit/stdout(ISO-3) |
| adversarial | **(HON-1 一票否决)** null 操作数→该路由 unmeasured,**绝不计 0 入 net**;**(ISO-1)** usage sink 喂含密钥的 .usage→断言 sink 不含 key(脱敏防御);**(HON-3b)** route-claude-* 不被误扫为 double;degrade 漏扣→断言 ds_wasted 计入;**对账不变量**:Σ(route+degrade+claude+unmeasured)==total |
| boundary | 大 token 数;net 为负;0 routes;coverage<0.5→non-representative 标 |
| 兼容 | 无 `--usage-out` → stdout 字节不变;**`--usage-out` ON → stdout 仍字节=content(ISO-2 黄金)**;M2 18+9 executor/provider 测试不退化 |

**判据**:`net = saved_est − ds_spent − ds_wasted`(claude 重做不重复扣);**null≠0 一票否决**;usage sink 脱敏;
ON/OFF stdout 字节不变;coverage 标注;bats 全过 + M2 路由回归绿。

## 10. 向后兼容 (Compat)

`routing.jsonl` schema 加字段(向后兼容,旧行缺字段→该项 unmeasured)。`call.sh` 默认行为不变
(`--usage-out` opt-in)。`cost.sh` 旧 `--sprint`/`--phase` 不变,`--compare` 新增。

## 11. 风险登记 (Risks)

| 风险 | 级别 | 缓解 |
|---|---|---|
| provider usage 字段差异(deepseek vs qwen vs proxy) | 中 | 解析 `.usage.prompt_tokens`+兼容别名;缺→null→unmeasured |
| claude_equiv 是估算非实测,被当真省 | 中 | §8 标 estimate;net 区分 measured(deepseek 实付)vs estimated(claude 反事实) |
| 把 null usage 当 0 → 虚报省钱(§1.2 诚信) | **高** | adversarial 测试一票否决:null 必入 unmeasured 列,绝不计 net |
| pricing 过时(deepseek 调价) | 低 | `as_of` 标注 + ESTIMATE,verify 提示 |
| 改 executor telemetry 影响 M2 路由安全 | 中 | telemetry 是旁路(不进路由决策);off→字节不变黄金测试 |

---

## Handoff (spec → plan)
- producer: spec-analyst-contract · model_tier: opus · self_score(E.1): 4.5/5(11 节实质;诚实 null≠0
  一票否决;复用 M2 telemetry;不碰路由决策风险隔离)。
- **G1 Challenger Panel next**(lens:测量正确性 / 诚信 null≠0 对抗 / M2 路由回归隔离)。
- 依赖:无硬 blocker,确定性可建;真实 usage 字段需一次真 call 验证(deepseek 已验证可调,M2)。
