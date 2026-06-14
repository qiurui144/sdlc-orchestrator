# Release Notes

## v1.8.0 — C-2 per-op provider routing: qwen-plus for 4 ops, N=3 multi-seed eval (2026-06-14)

### Highlights

- **Per-op `preferred_provider` routing in `draft-verify-allowlist.yaml`**: 4 ops now route to
  qwen-plus (DashScope), 3 stay on deepseek-v4-pro, based on N=3 multi-seed gpt-5.5 cross-judge evaluation.
- **qwen-plus is 18.7× cheaper and 57× faster** than deepseek-v4-pro for simple/structured tasks.
  deepseek retains advantage for complex reasoning (plan-decomp, review-body, adr-draft).
- **Multi-seed evidence (N=3)**: single-seed scores from v1.6.0/v1.7.0 were biased (judge prompt
  truncated at 2000 chars) for long-output ops. Fixed to 8000 chars; N=3 gives mean±std.
- **Surprise finding**: `threat-draft` routes to qwen (0.87±0.03 vs deepseek 0.82±0.10).
- **Automatic fallback**: if `QWEN_API_KEY` unset (exit 6), `draft-verify.sh` falls back to
  deepseek transparently — zero-downgrade deployment.
- **6 new bats tests** covering: qwen routing, deepseek explicit, absent-defaults-to-deepseek,
  allowlist yq readability for all 7 ops, 4+3 provider count invariant.

### Routing table (N=3, gpt-5.5 judge):

| op | provider | score (mean±std) | rationale |
|----|---------|-----------------|-----------|
| `spec-scope` | **qwen** | 0.79±0.02 | tie quality, 57× faster |
| `plan-decomp` | deepseek | 0.81±0.02 | reasoning advantage vs qwen 0.76±0.02 |
| `review-body` | deepseek | 0.80±0.07 | qwen s0=0.63, borderline |
| `threat-draft` | **qwen** | 0.87±0.03 | qwen better quality + lower variance |
| `adr-draft` | deepseek | 0.81±0.05 | qwen s1=0.68 below gate |
| `code-hotspot-summary` | **qwen** | 0.85±0.07 | cheaper, comparable quality |
| `commit-msg-draft` | **qwen** | 0.87±0.02 | much cheaper, comparable quality |

### Breaking changes

None. `preferred_provider` absent defaults to `deepseek` (backward compatible).

### Migration

Optionally set `QWEN_API_KEY` (DashScope) to enable qwen routing for 4 ops.
If unset, all 7 ops continue routing to deepseek automatically.

### Known Limitations

- `postmortem-draft` remains NOT routable (score 0.66 < 0.70 floor).
- qwen variance on `adr-draft` is 0.07 — occasionally drops to 0.68; deepseek more consistent.

---

## v1.7.0 — C-2 allowlist expansion: adr-draft + code-hotspot-summary + commit-msg-draft (2026-06-13)

### Highlights

- **3 more ops added to C-2 draft-verify allowlist** (gpt-5.5 judge via cc-proxy):
  - `adr-draft` (architect/opus tier) — judge_confidence=0.85, net_savings=35,275 µUSD/call
  - `code-hotspot-summary` (codebase-reviewer/sonnet tier) — judge_confidence=0.95, net_savings=12,369 µUSD/call
  - `commit-msg-draft` (implementer/sonnet tier) — judge_confidence=0.90, net_savings=2,961 µUSD/call
- **postmortem-draft explicitly REJECTED** (Gate 1 fail: 0.66 < 0.70 floor).
- **Total: 7 routable op types** across haiku/sonnet/opus tiers.

### Aggregate cost model (7 ops, per sprint):

| Op | Freq/sprint | Claude cost | DeepSeek cost | Net savings |
|----|------------|------------|--------------|-------------|
| spec-scope | ~1 | $0.0047 | $0.0011 | ~$0.004 |
| adr-draft | ~1 | $0.036 | $0.0004 | ~$0.035 |
| plan-decomp | ~1 | $0.252 | $0.003 | ~$0.249 |
| review-body | ~3 | $0.078 | $0.005 | ~$0.073 |
| threat-draft | ~1 | $0.025 | $0.002 | ~$0.023 |
| code-hotspot-summary | ~2 | $0.026 | $0.002 | ~$0.025 |
| commit-msg-draft | ~5 | $0.016 | $0.001 | ~$0.015 |
| **Total** | | **~$0.44** | **~$0.014** | **~$0.424/sprint** |

### Breaking changes / Migration / Known Limitations

None. Set `SDLC_DRAFT_VERIFY=1` to enable all 7 allowlisted ops.

---

## v1.6.0 — C-2 allowlist expansion: plan-decomp + review-body + threat-draft (2026-06-13)

### Highlights

- **3 new ops added to C-2 draft-verify allowlist** (gpt-5.5 judge, deepseek-v4-pro drafts):
  - `plan-decomp` (architect/opus tier) — judge_confidence=0.78, net_savings=248,167 µUSD/call
  - `review-body` (pr-reviewer/sonnet tier) — judge_confidence=0.78, net_savings=24,037 µUSD/call
  - `threat-draft` (architecture-reviewer/sonnet tier) — judge_confidence=0.78, net_savings=23,488 µUSD/call
- **Injected-defect libraries** added for all 3 ops; circular-blind-spot guard passes.
- **Total routable coverage**: 4 op types covering haiku→opus and sonnet tiers.

### Breaking changes / Migration / Known Limitations

None. `SDLC_DRAFT_VERIFY=0` (default) leaves behavior byte-identical.

---

## v1.5.0 — superpowers interop: plan adoption + self-built archival + DEVELOP mapping (2026-06-13)

### Highlights

- **Plan adoption (`/sdlc:plan`)**: before regenerating, checks for an existing plan matching the
  spec slug — adopts it (marks `plan_self_built: false`) without re-invoking the writing-plans skill.
- **Archive only self-built (`sprint-archival/archive.sh`)**: adopted plans are preserved; self-built
  plans are deleted on archival.
- **DEVELOP.md §13**: documents superpowers ↔ /sdlc command mapping and `plan_self_built` field.

### Breaking changes / Migration / Known Limitations

None. `plan_self_built` absent defaults to `true` (backward compat).

---

## v1.4.0 — C-2 single-phase route: direct v4-pro + inline oracle (2026-06-13)

### Highlights

- **Single-phase route** (`draft-verify.sh route`): scope-hardstop → allowlist → circuit → v4-pro
  → inline oracle → emit. No `--work` dir, no phases. Preferred over legacy prepare/finalize.
- **Inline oracle**: non-empty + ≥ min-chars (default 50) + no failure marker on first line.
- **judgment-eval simplified to 4 gates**: judge-confidence, human-checked, net-savings, tco-ok.

### Breaking changes

- `judgment-eval.sh`: `--recall` and `--recall-floor` args removed.

### Migration

Remove `--recall`/`--recall-floor` from any `judgment-eval.sh` invocations.

---

## v1.3.0 — C-2 judgment-draft-verify: deepseek draft + adversarial verify (2026-06-13)

### Highlights

- **C-2 wires the 87%-of-cost lever**: deepseek drafts draftable judgment ops; claude adversarially
  verifies in main context. Claude owns the final output — judgment is never fully externalized.
- **Scope hard-stops (closed set)**: `ga`, `arch-decision`, `security-verdict`, `risk-final`,
  `release-decision`, `g1–g4-judgment`, `panel-verdict` structurally refused (exit 10), even with
  a forged allowlist entry.
- **Injected-defect recall gate**: a known defect is planted; claude's review must surface it.
  Seven misses in the rolling window trips the circuit breaker.
- **Circular-blind-spot guard**: `injected-defect-lib.sh validate` requires ≥1 `source: prod-MISSED`
  or `cross-provider` entry before the library is usable.
- **spec-scope is now LIVE** (judge_confidence 1.0, net +348 µUSD/route).
- Skills: `injected-defect-lib`, `probe-power`, `judgment-eval`; enhanced: `draft-verify`.

### Breaking changes / Migration / Known Limitations

None. `SDLC_DRAFT_VERIFY` defaults off — byte-identical to full-claude.

---

## v1.2.0 — cost-measurement (C-1) (2026-06-13)

> Closes M2's "savings unmeasured" gap: routing savings are now a real, honest number. Telemetry-only —
> no routing-decision change.

### Highlights
- **`pricing.yaml`** + deepseek/qwen rows; `cost.sh price <provider> <in> <out>` (null when unpriced,
  never 0).
- **`call.sh --usage-out`**: records real `usage` tokens to a closed `{in,out,provider,model}` schema —
  built from parsed integers + literals, never the raw response (a key reflected in `.usage` can't leak);
  missing usage → null (UNMEASURED, never 0); stdout byte-identical with/without the flag.
- **Enriched `routing.jsonl`**: each route gains measured token + `ds_usd` (deepseek) + `claude_equiv_usd`
  (ESTIMATE at the counterfactual claude tier, default haiku). Routing decision byte-unchanged.
- **`cost.sh --compare`**: `net = claude_saved_estimated − ds_spent_measured − ds_wasted`. A null operand
  on a route/degrade is UNMEASURED, never a fabricated 0 saving; coverage spans routes+degrades;
  coverage<0.5 → `non-representative`.
- **Real measured net (2026-06-13)**: one real route → in 119 / out 241 → deepseek $0.000593 vs
  claude(haiku) $0.001059 → **net +$0.000466/route** (coverage 1.0).

### Breaking
- None. `--usage-out` is opt-in; with it absent, `call.sh`/executor behave exactly as v1.1.0.

### Migration
- None. `/plugin` update picks up v1.2.0; cost telemetry is recorded only when routing is on
  (`SDLC_MULTI_MODEL=1`).

### Known Limitations
- The net is **tiny** (cheap mechanical op); the claude side is an **estimate** (haiku, same token count);
  a degrade burst flips net negative; high `unmeasured` → `non-representative`. The value is that savings
  are now *measurable*, not the magnitude. The 87%-of-cost lever (judgment-task tier downgrade) is the
  next step (C-2), which moves the safety boundary and needs its own adversarial gate.

## v1.1.0 — multi-model routing M2 (eval-gated) (2026-06-13)

> Activates DeepSeek routing for one mechanically-verifiable task type, behind an eval gate. Opt-in
> (`SDLC_MULTI_MODEL=1`); default behavior is unchanged (all-Claude).

### Highlights
- **`model-eval` skill** (28 skills total): a deterministic grader (exact / normalized / set-F1) +
  `eval.sh` worst-case gate (every seed ≥ floor · std ≤ 0.05 · |provider−claude| ≤ 0.10 · claude ≥ floor)
  → an allowlist bound by `sources_hash` (fixtures + grader + prompt).
- **Eval-gated routing**: a *closed* task-type map (judgment ops — spec/plan/review/… — are
  structurally absent, never externalizable) → allowlist → **online correctness oracle** (re-grades the
  live output, hard floor `max(stored_f1−0.10, 0.75)`) → **circuit breaker** (rolling-20 fail-rate).
  Any failure degrades to Claude; a weak-model output never reaches the main line unverified.
- **Real eval done**: on the shipped task type (`inventory-count-diff`) deepseek-v4-pro / qwen-plus /
  claude all scored F1 1.00 (60 real calls, 3 seeds) → `passed: true`; the executor routes end-to-end to
  real DeepSeek with the oracle gating.

### Breaking
- None. Opt-in; with `SDLC_MULTI_MODEL` unset the drive is byte-identical to v1.0.0.

### Migration
- None required. `/plugin` update picks up v1.1.0; routing stays off until you set `SDLC_MULTI_MODEL=1`
  and an eval produces a `passed: true` allowlist.

### Known Limitations
- Single allowlisted task type; F1 1.00 reflects task triviality, not model parity on hard tasks.
- Net token savings are small and not precisely quantified (the provider caller does not surface
  `usage`, and the Claude baseline is the harness, not an API call). The value is the mechanism +
  safety gates, not a large cost reduction. Broader/discriminating task types are future work.

## v1.0.0 — GA: Personal edition (2026-06-12)

> **General Availability.** Rolls up the full feature set behind the RC 4 gates (§7.2) + real deployment
> & real-environment E2E verification (§7.3). The plugin drives its own SDLC end-to-end (self-hosting)
> and ships as a public OSS repo.

### Highlights
- Full SDLC chain `spec → plan → impl → review → test → release` with a Challenger Panel (consensus-auto).
- 18 agents · 27 skills · 30 commands · 3 hooks (5 scripts). Stack-agnostic; opt-in i18n (`SDLC_LANG`).
- Web-UI capability: `web-ui-verify` (real-browser render verdict), `web-ui-quality` (a11y/visual/
  responsive/perf gates), `ui-vision-judge` (provider-agnostic vision) — real-browser E2E verified
  (Chrome MCP + real Lighthouse + real qwen vision).
- `multi-model-routing` **M1** (provider layer): risk-driven router + OpenAI-compat caller
  (deepseek-verified), opt-in, zero default-behavior change.
- SE1–SE23 risk register; CI-green gate; doc-audit content gate; secret-scan + secret-guard.

### Breaking
- None. v1.0.0 is the first tagged GA; prior 0.x were unreleased/internal.

### Migration
- None for new users. `/sdlc:onboard` is idempotent; no config migration required.

### Known Limitations
- `multi-model-routing` is **experimental, provider-layer only** (M1): router + caller skills are opt-in
  (`SDLC_MULTI_MODEL=1`); the **M2 eval layer + phase-dispatch integration are post-GA**. GPT routing
  needs an OpenAI API key (or a local codex-proxy); default stays claude.
- `web-ui-quality` real-MCP reads are verified for the **a11y** gate (real Lighthouse); **visual /
  responsive / perf** are stub-suite covered and run via the same MCP fact-injection pattern.
- The LLM-driven north-star full chain is the user's §7.2 acceptance run; the deterministic
  install/onboard/doctor/component surface is verified.
- `public-readiness` and `interference-isolation` capabilities are on the post-GA roadmap.

---

## v0.31.0 — web-ui quality gates (UI-2): a11y / visual / responsive / perf (2026-06-10)

> Third minor of the **web-ui-capability** sprint. Drove the plugin's own SDLC: **G1** consensus panel BLOCKed rev.1 (6 design false-PASSes) → rev.2 → re-G1 PASS; **G2** adversarial CONCERNS (C-1 perf NOISE-masks-FAIL, I-1 `--write-baseline` wiring dropped, I-2 a11y ordinal floor, I-3 per-commit-green) → fixed. Layers deterministic quality gates on a UI-1-PASS page; vision is advisory-only (supremacy); the UI-1 verdict engine is byte-frozen.

### Highlights
- **`web-ui-quality` skill** (`/sdlc:web-ui-quality`): orchestrator `quality.sh` + four deterministic gates —
  **a11y** (lighthouse accessibility WCAG 2.1 AA count; ordinal `min_severity` floor), **visual regression**
  (global diff-ratio AND max contiguous changed-region px; deterministic `ignore_regions` mask + tolerance;
  baseline missing on a normal run ⇒ exit 7, `--write-baseline` to establish — never auto-launder),
  **responsive** (real layout: `scrollWidth`-overflow + key `getBoundingClientRect` in viewport, NOT DOM
  presence), **perf** (`performance_*_trace` {LCP,CLS,TBT} N≥3 **mean** vs SLO; high σ ⇒ UI-UNVERIFIED; a
  clear FAIL **dominates** a noisy metric).
- **Deterministic-verdict-supremacy (bidirectional)**: the visual gate consumes `ui-vision-judge` ONLY as an
  advisory annotation — never read into the verdict (the judge schema has no verdict field). BLOCKING test:
  vision says `intentional` on an over-tolerance diff ⇒ **still FAIL**.
- **Exit codes** 8 a11y / 9 visual / 10 responsive / 11 perf; aggregate = lowest failing code; tool-absent ⇒
  UI-UNVERIFIED (WARN), never a false PASS. Every G1/G2 finding is a BLOCKING adversarial test row.
- Inventory: skills 24→**25**, commands 29→**30**.

### Breaking
- None. Opt-in (`quality:` block in `web-ui-verify.yaml` + `/sdlc:web-ui-quality`). UI-1 `web-ui-verify` is
  byte-unchanged (the v0.29.0 R11 golden still passes).

### Migration
- None. Web-UI repos add a `quality:` block to `web-ui-verify.yaml`; establish visual baselines once with
  `--write-baseline` (commit via `git add -f` past the `*.png` gitignore).

### Known Limitations
- **Real chrome-devtools-mcp reads = §7.3 PENDING-VERIFY** — the live lighthouse-accessibility audit,
  performance trace, resize+evaluate, and screenshot-diff are NOT exercised by the zero-network bats suite
  (which fully covers the deterministic gate logic behind the `SDLC_*`/`--stub` seam). Lighthouse a11y is not
  a complete AA audit (some criteria are manual — documented in SKILL.md).
- A perpetually-high-σ perf gate sits at UI-UNVERIFIED (loud WARN); K consecutive ⇒ surface to the release gate.

## v0.30.0 — ui-vision-judge: provider-agnostic vision backend + UI-1 retrofit (2026-06-10)

> Second minor of the **web-ui-capability** sprint (G1 passed after a 3-lens panel caught a secret-in-retry-feedback leak + base64 GNU/BSD portability; G2 caught a missing hardcoded-count dogfood test). Adds an optional LLM **vision-understanding** backend that looks at a rendered screenshot via the user's own OpenAI-compatible provider (Qwen-VL, GPT-4o, …) — entirely additive, with the v0.29.0 deterministic verdict left byte-frozen. UI-2 (quality gates) + UI-3 (frontend-design) follow as v0.31/v0.32, consuming this judge.

### Highlights
- **`ui-vision-judge` skill** (`/sdlc:ui-vision-judge`) — a deterministic, zero-LLM-testable bash driver that takes a screenshot + question and returns a SOFT, schema-bounded judgment (`{vision_status, looks_ok|classification|score, confidence, reason}`) from a user-configured OpenAI-compatible vision endpoint (`SDLC_VISION_BASE_URL` / `_MODEL` / `_API_KEY`). All transport is behind a `--stub` seam ⇒ the bats suite runs with **zero network**.
- **Deterministic-verdict-supremacy** — the judgment schema has **no `verdict`/`pass`/`fail` field**; the v0.29.0 `web-ui-verify` 7-part engine (lines 140–175) is **byte-frozen vs the v0.29.0 tag** (golden `cmp` + exit-gate assertion + no-vision PASS/FAIL regression). A vision model can never flip a deterministic FAIL to PASS — it only annotates *alongside* the verdict.
- **§4.5 weak-model resilience** — schema-guided `response_format`, retry-validate (max 3) with a **redacted** fed-back error, ≥2 few-shot (incl. an EDGE blank-`#root` example), graceful degrade (`unconfigured`/`retries-exhausted`/`timeout`/`http-error` ⇒ `vision_status: unavailable`, never a hard error, never a fake judgment), and redacted telemetry.
- **Secret hygiene (§1.4)** — the API key is env-only and redacted (`sk-***`) everywhere, **including a provider error body that hostilely echoes the `Authorization` header** (BLOCKING R2 test, proven non-vacuous via a leaky-then-fixed RED).
- **Adversarial guards** — hostile extra `verdict` field DROPPED by a kind-keys projection; prompt-injection page handled (model judges pixels); 20× SIGPIPE-stress stable (SE16); portable `base64 | tr -d` data-URI (GNU/BSD).
- Inventory: skills 23→**24**, commands 28→**29**.

### Breaking
- None. The judge is opt-in (`/sdlc:ui-vision-judge` + `SDLC_VISION_*` env). Unconfigured ⇒ `vision_status: unavailable` (advisory). `web-ui-verify` behaves identically when `SDLC_WEBUI_VISION_ANNOTATION` is unset — the verdict engine is byte-unchanged.

### Migration
- None. To enable vision understanding, set `SDLC_VISION_BASE_URL` / `SDLC_VISION_MODEL` / `SDLC_VISION_API_KEY` to any OpenAI-compatible vision endpoint. No plugin install, no bundled provider (Hard constraint #4).

### Known Limitations
- **Real provider call = VERIFIED (§7.3)** — end-to-end `judge.sh` was run against the real DashScope OpenAI-compatible API (`qwen3.7-plus` + `qwen3.6-flash`; qwen-vl is retired). It returns a grounded judgment on a real screenshot (`looks_ok:true` on a rendered dashboard with the exact title/text/button read back; **`looks_ok:false` on a blank page** — it discriminates, not rubber-stamps), a nonexistent model degrades to `vision_status:unavailable, reason:http-error`, and the API key never appears in stdout or the run-dir. The **formal §4.5-D multi-tier F1 matrix** (N≥10 cases × weak/mid/strong, spread ≤ 0.15) remains as added rigor; the zero-network bats suite covers the full deterministic driver.
- **web-ui-verify real-browser E2E = VERIFIED (§7.3)** — driven via real Chrome (chrome-devtools-mcp) against `examples/web-hello` served locally: a real `/assets/app.js` **404** made the deterministic engine return **verdict FAIL** (real console-error + failed-network reads), and ui-vision-judge **independently** flagged the screenshot `looks_ok:false` ("content failed to render"). The §2.2 "curl-200-but-broken" anti-pattern was caught by BOTH the deterministic signal and vision; deterministic-supremacy held (the vision annotation rode alongside; the FAIL verdict stood). Closes the v0.29.0 UI-1 real-browser PENDING-VERIFY.
- The vision judgment is advisory only — by design it never gates. Quality gates that *act* on visual signals arrive in UI-2 (v0.31.0).

## v0.29.0 — web-ui-capability UI-1: real-browser render verification (2026-06-08)

> First minor of the **web-ui-capability** sprint (G1 passed after a 5-then-1-lens panel caught the undefined-render-signature false-green keystone + trivial-contract/build_id/exit-code seams; G2 caught the plan's own settle false-green-label). UI-1 lands the global CLAUDE.md UI rules (§2.2 user-first · §6.4 Playwright-Chrome E2E · §7.3 real-deploy render verify) for web-UI projects. UI-2 (a11y/visual/responsive/Lighthouse quality gates) + UI-3 (frontend-design in impl) follow.

### Highlights
- **`web-ui-verify` skill** (`/sdlc:web-ui-verify`) — verifies a web UI actually *renders* in a real browser, not just `curl 200` (the §2.2 anti-pattern killer). Detect frontend stack (`detect-web-stack.sh`: react/vue/svelte/next/angular/vanilla) → probe the **optional** Playwright/chrome-devtools MCP (`claude mcp list`, bounded timeout) → §6.4 lint (Chrome-only / no-Bash-interleave / screenshot-dir) → parse a per-target `web-ui-verify.yaml` success contract → emit a tri-state verdict.
- **Keystone verdict** — PASS requires positive-assertion present AND negative/placeholder absent AND zero console-errors AND zero failed-network (4xx/5xx) AND build-fresh; a blank `#root` / go:embed placeholder / stale build ⇒ **FAIL, never PASS-on-200**. `--emit-boot-check` generates a Go `init()` panic-on-placeholder guard.
- **MCP optional + graceful degrade** — MCP absent / probe timeout / `claude` CLI absent ⇒ **`UI-UNVERIFIED`** (server-side only, WARN), **never a false PASS**. Zero hard external dependency (MCP detected, never installed; Hard constraint #4). `/sdlc:doctor` reports MCP as a web-gated advisory.
- **Fail-closed contract** — no contract / no routes / trivial positive (generic selector + empty text) / zero negative markers ⇒ **exit 7**; `build_id` absent ⇒ UI-UNVERIFIED (freshness unprovable). Verdict travels to the releaser as the mechanical `ui_verified: true|false|unverified` handoff field.
- **Wiring** — tester (G4) runs the Chrome user-flow E2E for web-UI projects; releaser (§7.3) does post-deploy curl-200 **AND** browser render, mapping `ui_verified=false ⇒ BLOCK GA`, `unverified ⇒ Gate-4 Known Limitation`; pr-reviewer rejects backend-first UI reproduce (§2.2).
- **BLOCKING 15-fixture evasion suite** + an `engineering-skills:adversarial-reviewer` G3 pass on the real `verify.sh` (§5.2.0b dual-acceptance).
- Inventory: skills 22→**23**, commands 27→**28**.

### Breaking
- None. Non-web projects are unaffected (`detect-web-stack` ⇒ not-a-web-app, exit 2, no-op). `ui_verified` is an optional handoff field (old handoffs validate unchanged).

### Migration
- None. Web-UI projects add a `web-ui-verify.yaml` contract at their repo root (see `skills/web-ui-verify/SKILL.md`); absent ⇒ the verifier fails closed (exit 7), never a false PASS.

### Known Limitations
- **Real-browser E2E is PENDING-VERIFY** (§7.3, mock ≠ real): the deterministic layer (detect/probe/§6.4-lint/contract/verdict over stubbed browser facts) is bats-tested + shipped, but actually driving Chrome through a user flow + judging a real render is unverified until run on a real app + a connected Playwright MCP. Dogfood fixture: `examples/web-hello/` (the plugin itself has no web UI).
- Part-6 hydration-settle (real `browser_wait_for` timing) is PENDING-VERIFY; the deterministic engine checks the other 6 verdict parts.
- The evasion suite is a denylist — it blocks the enumerated + structurally-barred false-greens, not a proof of no un-enumerated evasion (standing adversarial-review item).
- **RES-UI1** (accepted residual, like risk-classify RES1): a contract's `positive.text` should be **route-distinctive (≥ a word)** — a single common char (`.`, `>`) passes the empty-text guard yet matches almost any HTML. Not mechanically closable without false-rejecting legit short labels; mitigated by the required ≥1 negative marker + §7.2 review (which caught the round-1 blank-`#root` false-green).

## v0.28.0 — B accurate-fast: deterministic risk classifier (2026-06-06)

> Second minor of the **accurate-fast-orchestration** sprint — the substantial, risk-gated half. This is the **real speed lever**: a provably-safe low-risk change skips the slow LLM ceremony (spec/plan/panels) while every change still passes the always-on deterministic net. The design passed G1 only after a 5-then-3-lens Challenger Panel caught 3 real findings (A1/A2 not plugin-controllable, a config-yaml command-execution bypass, a `docs/** non-.sh` denylist that let `docs/tools/gen.py` reach LOW); all closed before any code.

### Highlights
- **`skills/risk-classify/risk-classify.sh`** — deterministic, zero-LLM tier classifier (LOW/NORMAL/HIGH) selecting path depth (fast vs full) + Challenger panel size + model tier. **Default-deny**: LOW is a positive basename allowlist of non-executable content ONLY (`.md` prose / `.txt` / `LICENSE`); any source/test/command-bearing-config/auth/migration/CI path → NORMAL/HIGH. A misclassification costs *time*, never *safety*. bash-3.2 / SE16-safe / LC_ALL=C deterministic (N=20 byte-identical).
- **`/sdlc:run` is classifier-driven by default** — `--full` forces full rigor (always wins), `--fast` is advisory (can never demote NORMAL/HIGH). `SDLC_RISK_GATE=off` restores pre-v0.28 behavior.
- **BLOCKING 11-fixture classifier-evasion suite** (`tests/risk-classify-evasion.bats`) — crafted bypasses (auth-in-docs, fence-logic, rename-dodge, command-config, self-ref, `docs/*.py`, `# non-breaking`) all route NORMAL/HIGH; **a single LOW blocks the ship**. Dogfooded rigor on the speed feature itself.
- The deterministic safety net (doc-audit --strict + ci-status + diff-guard + shellcheck + full bats) runs on **EVERY** path including the LOW fast-path — never skipped. Optional `risk_tier` handoff field.

### Breaking
- None. `SDLC_RISK_GATE=off` restores exact pre-v0.28 full-rigor-always behavior; `risk_tier` is an optional handoff field (old handoffs validate unchanged).

### Migration
- None. First `/sdlc:run` after upgrade defaults `SDLC_RISK_GATE=on`; any classifier error / unparseable diff → HIGH (full rigor, safe).

### Known Limitations
- The evasion suite is a denylist (RES1): it blocks the enumerated vectors + structurally bars executable files from LOW, but cannot *prove* no un-enumerated evasion exists — a standing adversarial-review item.
- Speed savings are estimates (SE11) until benched on a real `/sdlc:run`.

## v0.27.0 — A3 accurate-fast: parallel-by-default + spot-check (2026-06-06)

> First minor of the **accurate-fast-orchestration** sprint (G1 passed after a 5-then-3-lens Challenger Panel caught 3 real findings; G2 caught a DAG write-conflict). This minor is the **zero-accuracy-risk** half: same agents, same checks, same rigor — only faster. The sibling minor v0.28.0 adds the risk classifier (B).

### Highlights
- **`SDLC_PARALLEL_DEFAULT=on`** (`config/defaults.yaml`) — independent impl-DAG tasks (shipped v0.10) now fan out **by default**, capped at `SDLC_MAX_PARALLEL` (default 2). No new concurrency infra; reuses the v0.9–v0.12 primitives (atomic.sh/counter.sh/dispatch-batch), so the v0.9 20-process race test still gates.
- **Spot-check-don't-full-re-run protocol** — a consumer agent spot-checks a producer-`self_score`d artifact (1 sample / hash-compare) instead of full-re-running it, **EXCEPT** when the change is `risk_tier == HIGH` or the producer handoff is missing its `self_score` (→ full-re-run). The deterministic safety net (doc-audit/ci-status/diff-guard/shellcheck/full bats) is **never** spot-checked.
- **Behaviorally verified, not just grep-asserted** — a new `eval/fixtures/task-orchestrator/a3-spotcheck` fixture + a live `/sdlc:eval task-orchestrator` run scores **3/3 seeds PASS (opus, rate 1.00)**: the real orchestrator, given the A3 scenario, actually parallel-dispatches the independent tasks, spot-checks the self_scored artifact, full-re-runs HIGH/missing-self_score, and never spot-checks the net. (Authoring this fixture was the G2-review-required gate; the eval roster goes 13→14 agents.)

### Breaking
- None. `SDLC_MAX_PARALLEL=1` restores the exact pre-v0.27 serial + full-re-run behavior. A3 degrades to today's behavior on any failure — it can only make a run equal-or-faster, never worse.

### Migration
- None. New default knobs land in `config/defaults.yaml`; override via an exported env var of the same name to opt out.

### Known Limitations
- Wall-clock / dispatch-count savings are estimates (SE11) until benched on a real `/sdlc:run` — the *behavior* is verified (the orchestrator follows the protocol, 3/3 seeds), the *magnitude* of the speedup is not yet benched.

## v0.26.2 — 2026-06-05 (patch)

> **The actual macOS CI fix: a CJK character in a bats test NAME** (honest correction of v0.26.1). The v0.26.0 `[10]` adversarial test was named ``[10] adversarial: stray later '斜杠命令' prose …`` — `bats` on the `macos-latest` runner mangles CJK bytes in a test NAME into an invalid generated function name (`bats: unknown test name` → the test aborts: "Executed 420 instead of 421"; `lint` + `ubuntu` were green). **v0.26.1 MISDIAGNOSED this** as a BSD-`sed` multibyte-program issue and refactored the `[10]` parser (`extract_count_tuple`, pure-ASCII — a reasonable hardening, but NOT the cause); macOS stayed red. The real fix here: rename the test to an ASCII name (the Chinese stays in the test BODY/fixtures, where bats handles raw bytes fine). No production-code change in this patch. Lesson re-applied: read the actual failing-job log before fixing (the `bats: unknown test name` line was the smoking gun); `LC_ALL=C` on GNU tooling did not reproduce the macOS-bats name-encoding behavior.

## v0.26.1 — 2026-06-05 (patch)

> **macOS cross-platform fix for the v0.26 [10] bilingual check.** v0.26.0's `[10]` parser used a `sed` PROGRAM containing the multibyte literal `斜杠命令`/`个`/`、`; BSD `sed` on the `macos-latest` CI runner (C locale) raises *illegal byte sequence* when the SCRIPT itself contains multibyte bytes — so the `[10]` test aborted (macOS job: "Executed 420 instead of 421"; ubuntu + lint were green). v0.26.0 shipped with a red macOS CI as a result. Fix: replace `parse_counts_zh` with `extract_count_tuple` — pull the count integers from the first `**bold**` run mentioning "agent" via ASCII-only `awk` + `grep -oE '[0-9]+'`, then compare en↔zh **positionally** (1=agents 2=skills 3=commands 4=hooks). Zero multibyte in any sed/awk program → BSD-safe. `[10]` semantics unchanged (match / drift / skip / missing-kind), verified under `LC_ALL=C`. (Header comments keep `§`/`·`/Chinese — harmless in shell comments, green on macOS through v0.25.1.) CLAUDE.md hard-constraint #5 — test on macOS bash 3.2 — is exactly the regression this guards.

## v0.26.0 — 2026-06-05

> **doc-audit reverse checks — close the two blind spots that let docs drift stay green.** This session's README drift (the command table listed 23 of 27; README.zh count drifted to 17/20/26) passed the v0.24 content gate because [7] only checked referenced→exists (not the reverse) and [6] read only README.md (not README.zh). These two additions make that drift class mechanically catchable — the recurring "prompt-rule → enforced-gate" lineage applied to the gate's own gaps.

### Highlights
- **[9] command-list completeness** (plugin-self) — every `commands/<cmd>.md` must be referenced as `/sdlc:<cmd>` in `README.md` (the exact reverse of [7]); a command file absent from the README catalogue → `command not in README: /sdlc:<cmd>`. A per-repo `.sdlc/doc-audit-allow` line exempts an intentionally-unlisted command (mirrors `.sdlc/secret-allow`). Substring-safe (`/sdlc:barbaz` does not satisfy `/sdlc:bar`).
- **[10] bilingual count parity** (plugin-self, when `README.zh.md` exists) — the inventory count tuple in `README.zh.md` (Chinese unit words `个`/`、`/`斜杠命令` parsed) must equal `README.md`'s (transitively == filesystem, since [6] binds README.md↔FS); a drift → `bilingual count drift (README.zh): <kind> says <zh>, README.md says <en>`. Enforces §1.1.3 (README + README.zh no-drift).
- Both reuse the existing `--strict` / CI hard-gate machinery; non-plugin repos and repos without `README.zh.md` skip cleanly. zh command-LIST parity is deferred (zh prose may group commands differently → false-positive risk).

### Breaking changes
- None (additive checks, no new components — counts unchanged 18/21/27/3).

### Migration
- None. Test suite 506 → **521** (+15: [9] completeness / exemption / substring-safety / non-plugin-skip; [10] parity / drift / zh-absent-skip; META). Dogfooded: `doc-audit.sh --strict` is CLEAN on this repo with [9]/[10] active (all 27 commands catalogued in both READMEs; README.zh tuple == README.md).

### Known Limitations
- [10] checks the count tuple, not the full command catalogue, in README.zh. The `[8]` canonical-version-anchor note counts toward `--strict` findings, so a plugin repo lacking a `> Shipped through **vX.Y.Z**` line fails the gate (intended — a plugin should declare its shipped version).

## v0.25.1 — 2026-06-05 (patch)

> **Wire `ci-remediator` into the `/sdlc:run` drive.** An audit ("can all functionality auto-trigger via run?") found the v0.25 auto-remediation was an orphan — the CI-green gate auto-blocked on a red CI at REVIEW/RC, but nothing in the drive dispatched the bounded auto-fix loop (it was only reachable manually). Now `task-orchestrator` rule 15 dispatches `ci-remediator` on a `ci-status` FAIL **before** hard-blocking (diff-guard-gated; security-advisory / test / logic failures escalate; `--interactive` pauses). `run.md` now documents the gates the drive auto-triggers (doc-audit + CI-green + bounded remediation; `/sdlc:promote` is a separate post-release command). +2 coupling guards so the wiring can't silently regress (suite 506 → 508). No code-logic change — the ci-status/diff-guard/ci-remediator logic is unchanged from v0.25.0.

## v0.25.0 — 2026-06-05

> **CI-green gate + bounded auto-remediation** (#13/#14) — the SDLC now mechanically enforces "GitHub CI is green before an irreversible tag/promote", and can auto-fix a small set of reversible CI failures behind a zero-LLM safety guard. Built after CI stayed red+unfixed for 12 days on a real downstream project. The G3 dual-acceptance adversarial reviewer **BLOCKED** the first cut — the gate wasn't binding the verdict to the commit (a red HEAD read green from an unrelated branch's run), and the diff-guard was defeatable by assertion-neutering — both were redesigned and re-verified (re-G3). Same "prompt-rule → enforced-mechanism" lineage as `ga-tag-guard` (v0.18) and `doc-audit-content-gate` (v0.24).

### Highlights
- **`skills/ci-status/ci-status.sh`** — deterministic CI verdict (PASS/FAIL/IN_PROGRESS/UNKNOWN/NONE) bound to the **resolved commit SHA** (`gh run list -c <SHA>`, fail-empty → NONE: an unrelated branch's green run can never read PASS), reducing over **all** checks (one green never masks a red). `SDLC_GH_BIN` injection for offline tests; graceful gh-EOF → UNKNOWN.
- **Gate wiring (#13/#14)** — `releaser` RC gate + the new **`/sdlc:promote`** (develop→main) default `--require-known` (UNKNOWN→BLOCK at the irreversible tag); `pr-reviewer` warns on UNKNOWN (reversible). Asymmetry justified by reversibility.
- **`skills/ci-status/diff-guard.sh` (the safety core)** — a zero-LLM guard that audits the actual `git diff --cached` before any auto-remediation commit. Auto-fix allowlist = **3 reversible classes** (A1 fmt = whitespace-only invariant / A3 deny-LICENSE append / A4 doc-sync); A2 lint-autofix dropped (semantic changes can't be safely guarded). Rejects (→ revert + ESCALATE) any test-file touch (path + content markers across Rust/Go/Python/Java/JS/C#), added skip/ignore marker, CI-yaml edit, or footprint overrun. **Never weakens a test — by mechanism, not instruction** (the token-counting heuristic that the adversarial review defeated was removed entirely).
- **`agents/ci-remediator.md`** — on red CI, classifies the failure (deterministic advisory-vs-license pre-gate: a security advisory escalates before any LLM) and either auto-fixes one of the 3 classes (gated by diff-guard) or escalates; bounded retries.

### Breaking changes
- None (additive). New skill `ci-status/`, new agent `ci-remediator`, new command `/sdlc:promote` → counts **18 agents / 21 skills / 27 commands / 3 hooks**.

### Migration
- None. Test suite 419 → **506** (+87: ci-status verdicts incl. the commit-binding + reduce-all regressions, the B1 diff-guard real-staged-diff matrix incl. the full adversarial-bypass regression set, B2 pre-gate, gate-wiring guards). `gh` CLI required for the live CI check (mocked in tests via `SDLC_GH_BIN`).

### Known Limitations
- G3 residual non-exploitable nit: the A1 whitespace-only check strips whitespace inside string literals (a string-literal whitespace edit passes A1) — blast radius nil for the threat model (cannot weaken a test or alter control flow). The E3 PreToolUse harness guard (hard block on red at `git push`/`tag`) is deferred. Non-GitHub CI (GitLab/Jenkins) is v.next.

## v0.24.0 — 2026-06-05

> **Self-enforcing doc-sync** — a content-aware doc-audit gate, built (dogfood) right after v0.23.0 shipped stale README/DEVELOP docs because doc-sync was a prompt rule, not an enforced gate. Same "prompt-rule → enforced-gate" conversion as `ga-tag-guard` (v0.18) and the doc whitelist (v0.19.1).

### Highlights
- **`scripts/doc-audit.sh` now does content-drift detection** — 3 zero-false-positive checks under `--strict`, on top of the 5 structural checks: `[6]` inventory-count consistency (the "N agents / M skills / K commands / J hooks" string in `plugin.json .description` + the README prose line must equal the real filesystem counts), `[7]` `/sdlc:` command-reference integrity (every command referenced in README has a `commands/<cmd>.md`), `[8]` canonical-version anchor (the CLAUDE.md `> Shipped through **vX.Y.Z**` line must equal `plugin.json .version`; non-plugin repos opt in via a `<!-- sdlc:version -->` marker on a single line).
- **CI hard-gate, zero yaml change** — `.github/workflows/ci.yml` already runs `doc-audit.sh --strict`, so content drift now fails CI.
- **Release flow wired (E2)** — `releaser` RC Gate 1 + `docs-curator` invoke the content-aware audit, closing the bypass that shipped the v0.23 drift.
- **Honest scope** — the originating `(v0.20)` *prose capability-claim* drift is NOT mechanically catchable (a regex cannot distinguish a stale claim from a valid historical attribution like `(v0.9) Challenger Panel`); it stays a `/sdlc:release` §7.2 review + `docs-curator` (LLM) responsibility. The broad version-string scan was explicitly rejected during G1 (false-positives on legitimate roadmap refs in DEVELOP.md).
- Trimmed the stale README `## Status` table (duplicated RELEASE.md, §3.2 SSOT) to a pointer.

### Breaking changes
- None. `doc-audit.sh` exit contract unchanged (advisory exit 0 / `--strict` exit 1); content checks are additive; plugin-self checks `[6]`/`[7]` are gated on `.claude-plugin/plugin.json` + `commands/` so non-plugin repos get only the opt-in generic anchor.

### Migration
- None required. Counts unchanged (17 agents / 20 skills / 26 commands / 3 hooks). Test suite **402 → 419** (+17: the new content checks' bats matrix incl. a META dogfood that runs the gate on this repo). Going forward, a version bump must also update the CLAUDE.md `Shipped through` anchor + any changed counts, or the gate fails CI — which is the point.

### Known Limitations
- Prose capability-drift (a sentence describing an outdated capability) is not mechanically detected — by design (see Highlights). The complementary CI-green gate + bounded auto-remediation is a separate planned feature (v0.25.0).

## v0.23.0 — 2026-06-05

> **Cross-project dogfood hardening** — found by driving the full SDLC chain (`/sdlc:spec`→`test`) on a real project (KVM) from this plugin's parent directory. Two real gaps surfaced; both fixed with TDD. (The roadmap's previously-planned v0.23.0 "superpowers 互通" shifts to v0.24.0 — version numbers are assigned at merge time, §7.1.7.)

### Highlights
- **Subdir build-module detection (bug1)** — `config/detect-stack.sh` now **descends one level** when the repo root has no marker, picking the primary module by a directory-name preference (`backend`/`server`/`go`/`api`/…, then the first marker-bearing subdir). Adds a `--module-dir` mode. `onboard` records `state.module_dir` and, for a subdir module, materializes `.sdlc/stack.yaml` with `cd <dir> && ` prefixed commands. Before this, a polyglot repo whose module lives in a subdir (e.g. KVM's Go module in `go/`) silently detected as `generic` → `/sdlc:test` ran the generic (bats) adapter and "passed" with zero tests. Root-module repos are unaffected (root markers still win, no descent).
- **`--project` on the granular commands (bug2)** — `spec`/`plan`/`impl`/`review`/`test` now document and accept `--project <dir>` (and honor a pre-set `SDLC_PROJECT_ROOT`), matching `/sdlc:run` and `/sdlc:status`. Each roots ALL paths at the target (specs/plans under `<dir>/docs/superpowers/`, impl commits into the `<dir>` repo, test runs `<dir>/.sdlc/stack.yaml`, review diffs with `git -C <dir>`). Closes the gap where a cross-project granular run silently used the cwd.
- **Restored a silently-skipped e2e** — `test_intake_spine_e2e.bats` asserted 7 intake dims but `plan.sh` has emitted 8 since v0.21 added `secrets`; the count assertion failed and bats reported the non-fatal "Executed 0 instead of expected 1" warning (not a failure), so it hid for several versions. Fixed to 8 + `secrets` in the scorecard check.

### Breaking changes
- None. `detect-stack.sh` output is unchanged for root-module repos; the new `--module-dir` mode is additive; `state.json` gains an additive `module_dir` field.

### Migration
- None required. Re-run `/sdlc:onboard` on an already-onboarded subdir-module repo to regenerate a correct `.sdlc/stack.yaml` (onboard never overwrites an existing one, so delete the stale `generic` `.sdlc/stack.yaml` first if you were affected). Counts unchanged (17 agents / 20 skills / 26 commands / 3 hook entries). Test suite 389 → **402** (+12 new: 7 detect-subdir + 1 onboard-subdir + 1 granular `--project` + 3 review-hardening [W1 subshell-wrap / W2 space-quote / src fallback]; +1 restored intake e2e).

### Known Limitations
- Subdir detection descends **one** level and picks **one** primary module; a deeply-nested or multi-primary monorepo still needs a hand-edited `.sdlc/stack.yaml` (onboard prints a `note:` naming the chosen dir so the choice is visible, not silent).
- The granular-command `--project` is a documented protocol the driving agent follows (the commands are markdown dispatchers); it is enforced by convention + the new bats contract test, not by a shared resolver script.

## v0.22.1 — 2026-06-04 (patch)

> Found by dogfooding `/sdlc:onboard`+`/sdlc:doctor` on a real project (KVM, which had legitimately reached the RC phase): `doctor.sh` only accepted `RC_CANDIDATE`, so a state with the diagram-shorthand phase `RC` false-FAILed. Fix: accept `RC` as an alias of `RC_CANDIDATE`. +1 regression test (389).

### Highlights
- **`doctor.sh` accepts the `RC` phase alias** (not only `RC_CANDIDATE`) — any project that reaches the RC phase no longer gets a spurious `[state] FAIL: unknown phase 'RC'`. The state-machine diagram uses the shorthand `RC`; the persisted canonical is `RC_CANDIDATE`; doctor now honors both.

### Breaking changes / Migration
- None.

### Known Limitations
- Carried forward from v0.22.0.

## v0.22.0 — 2026-06-04

> **三项软件项目质量要求,作为受检项目要求落地**(用户澄清:error 编号体系 / 结构化日志 / commit 纪律 指的是 sdlc 对**被管理项目**的要求,像 nginx/bluez/kernel/gcc,不是给插件自己脚本编号)。纯定义 + 强制接线,无新组件;suite 387 → 388。

### Highlights
- **SE21 — error-code 编号 taxonomy**:项目须有文档化、稳定、编号的 error/return-code 体系(nginx return codes / bluez error enums / `errno`),不是散落的 error 字面量;日志 + API 错误引用 code 而非仅 message。
- **SE22 — 结构化分级日志**:level + 时间戳 + 关联 error-code + grep-able;**扩到库/daemon/CLI,不止 request-service**(bluez/nginx 是 daemon/库却有典范分级日志)。
- **SE23 — commit 纪律**:原子 + 有意义的 commit(kernel/gcc patch-series),既反 `wip/fix` churn 直推、也反过度 squash 成 milestone blob;推公开 main 前 `rebase -i` 收拾(配套 global CLAUDE.md §4.2.4 新增)。
- **强制接线**:三项写进 SE 风险登记(SE1–SE23);`observability-baseline` skill 加 "Error-code taxonomy" + "日志覆盖所有 deployable" 两节(SE21/SE22 owner);`codebase-reviewer` 深审加 Item 6b(`/sdlc:intake` 审项目时检查三项);`test_se_catalog` 扩到 SE1..23。
- **配套全局规则**(`~/.claude/CLAUDE.md`):§5.2.0 最严审查 + §5.2.0b 双岗位双验收 + §4.2.4 干净公开主线/commit 纪律(学 kernel/gcc)+ §1.1.5/§4.2.1 GitHub SSH push —— 本轮新立。

### Breaking changes
- 无。纯增 SE 定义 + reviewer 检查项;不改任何命令/接口。

### Migration
- 无。counts 不变(17 agents / 20 skills / 26 commands / 3 hook entries)。被 sdlc 管理的项目从此在 `/sdlc:intake` review + spec §7 被检查 SE21/22/23;不达标 → finding(非硬 BLOCK,除非项目自定)。

### Known Limitations
- SE21/22/23 的检查是 **review-agent 判断**(LLM)+ spec 要求,非确定性 lint(跨栈难机械化);深度检测可接 trufflehog 类工具或语言原生 linter。
- pr-reviewer + spec-analyst 的 §7 接线为后续完善(本版以 SE 登记 + observability-baseline + codebase-reviewer 为强制核心)。
- 沿用:真 zh/background/multi-worktree E2E、真 macOS、SE17 a11y、panel N=3 校准、Edge·HW-Verify 真硬件。

## v0.21.0 — 2026-06-04

> **Secret + file-permission hygiene (SE13 owner)** — direct response to a §9.1 incident (a `gho_` token sat plaintext in 14 `.git/config` files and the plugin couldn't detect it). TDD: 18 cases (`test_secret_scan.bats` 11 + `test_secret_guard.bats` 7). Suite 365 → 383.

### Highlights
- **`secret-scan` skill** (`skills/secret-scan/scan.sh`): deterministic, zero-LLM scanner — plaintext secrets (`gh[opsu]_…` / `github_pat_…` / `-----BEGIN … PRIVATE KEY` / `AKIA…` / embedded-cred URLs, **incl. `.git/config`**) + loose perms on sensitive files (`*.pem/.key/.env`, `secrets/`, `id_*`; `--fix` → chmod 600). **Never prints the secret value** (`file:line: kind` only, §1.4); SE16-safe.
- **`secret-guard` hook** (`PreToolUse:Bash`): **blocks `git commit`/`git push` (exit 2)** when staged/tracked content contains a secret or a sensitive file is loose-perm — the active protection that would have stopped the incident. Escape: `SDLC_SECRET_OVERRIDE=1` or `.sdlc/secret-allow`.
- **Folded into existing features** (ADR 0001, no sprawl): `/sdlc:deps` (dependency-auditor) folds the scan into its PASS/BLOCK verdict; `/sdlc:intake` gains a `secrets` dimension (SE13). SE13 goes from definition-only to a real owner.
- **Dual-acceptance reviewed** before ship (CLAUDE.md §5.2.0/§5.2.0b): round 1 (two independent reviewers, different logic) **BLOCKED** it — caught a line-level-allowlist bypass (real token + `${VAR}` slipped through) and a `git -c …commit` hook evasion; both fixed + regression-tested; round-2 adversarial re-verify **PASS** (15 evasion variants blocked, no value leak). The gate did its job.

### Breaking changes
- None for normal use. **Behavioral**: in a git repo, committing/pushing a detected plaintext secret or loose-perm sensitive file is now blocked (intended, §1.4/§9.1); override per above.

### Migration
- None. Counts: skills 19 → 20, hook scripts 4 → 5 (entries stay 3 — guard joins the existing `PreToolUse:Bash` entry). Honors `SDLC_PROJECT_ROOT` (v0.20).

### Known Limitations
- **Regex first-line only** — misses obfuscated/split secrets (false-negative). Recommend trufflehog/gitleaks in CI for depth (§1.4); this is defense-in-depth, not a guarantee.
- Line-level allowlist: a real secret sharing a line with an allowlisted placeholder can be missed (rare; the v0.21 TDD removed the over-broad `EXAMPLE`/`example.com` entries that caused exactly this).
- `secret-guard` scans staged (commit) / tracked (push) — it does not deep-scan historical commits being pushed; a secret is caught at commit-time (staged), so this gaps only secrets committed before the hook existed; rotate any already-pushed secret (§9.1).
- `.sdlc/secret-allow` entries are unanchored case-insensitive regex matched against token+path — keep them SPECIFIC (an entry like `.*` or `AKIA` would over-suppress). It's an explicit maintainer-committed override (a trust boundary); anchoring/`grep -F` for token-mode is a tracked future hardening.
- `SDLC_SECRET_OVERRIDE=1` and a mis-pointed `SDLC_PROJECT_ROOT` are intentional fail-open env levers controlled by the operator (not third-party reachable).
- Carried forward: real zh / background / multi-worktree E2E, real macOS bash 3.2, SE17 a11y depth, panel multi-seed N=3 tuning, Edge·HW-Verify real-hardware E2E.

## v0.20.0 — 2026-06-04

> **Run on a specified project directory.** For when Claude is launched from a parent directory holding several projects. TDD: `tests/unit/test_project_root.bats` (6 cases). Suite 359 → 365.

### Highlights
- **`SDLC_PROJECT_ROOT` convention + `/sdlc:run --project <dir>`**: the orchestrator resolves a target project root once, exports `SDLC_PROJECT_ROOT` for every dispatch, and puts ALL project paths (specs / plans / `docs/superpowers/handoffs/<sprint>_state.yaml` / reports) under it. Default (no flag) = cwd, fully backward-compatible.
- **Deterministic scripts honor it**: `onboard.sh`, `doctor.sh`, `hooks/ga-tag-guard.sh`, `sprint-archival/archive.sh` all resolve the project root as **positional-arg > `SDLC_PROJECT_ROOT` > cwd**. So the GA-tag guard protects the *target* repo, archival cleans the *target* repo, etc., even when cwd is the parent. Proven from a parent cwd in the new tests.
- **`--project` exposed on `/sdlc:run` and `/sdlc:status`**; `/sdlc:onboard` & `/sdlc:doctor` already take the dir positionally. README documents "Running from a parent directory".

### Breaking changes
- None. Absent `--project`/`SDLC_PROJECT_ROOT`, everything behaves exactly as before (cwd).

### Migration
- None. Counts unchanged (17 agents / 19 skills / 26 commands / 3 hook entries); `--project` is a new flag on existing commands, not a new component.

### Known Limitations
- **The `Stop` archival hook runs in the session cwd, not `--project <dir>`** (a hook is a separate process; a per-command env export doesn't reach it). To archive the right repo at session end, launch Claude inside `<dir>` or export `SDLC_PROJECT_ROOT` in the shell env. Documented in `/sdlc:run` + README.
- LLM agents honoring `$root` for every Read/Write is prompt-driven (the deterministic scripts enforce it; the orchestrator is instructed to prefix all project paths). Multi-project *concurrent* sprints in one session are not yet a first-class feature.
- Carried forward: real zh / background / multi-worktree-feature-queue E2E, real macOS bash 3.2, SE17 a11y depth, v0.9 panel multi-seed N=3 tuning, Edge·HW-Verify real-hardware E2E.

## v0.19.1 — 2026-06-04 (patch)

> Maintenance/hygiene patch (no new feature → patch). Closes 3 self-audit gaps surfaced by a 4-way independent review: shellcheck wasn't in CI, the §3.2 deterministic `doc-audit.sh` was missing, and the repo (a doc-discipline plugin!) was itself violating §3.2. Suite 350 → 359.

### Highlights
- **shellcheck + doc-audit now gate CI** (`.github/workflows/ci.yml` new `lint` job): `shellcheck -x` on every `.sh` + `doc-audit.sh --strict`. A zero-cost regression lock — the next SC2034/dead-var or doc-structure violation fails CI instead of accreting silently (the SE16 flake class would be caught at the source).
- **`scripts/doc-audit.sh`** — the deterministic §3.2 doc-structure auditor that §3.2 calls for but was missing (the repo had only the haiku-LLM `docs-curator`). 5 checks: root .md whitelist · stray `.zh.md` · one-shot residue (`*-report/-tasks/-analysis/-readiness`) · lingering plans · tracked `reports/*.md`. `--strict` for the gate. +9 bats cases.
- **Dogfooding cleanup** (the plugin fixing its own §3.2 violations): deleted undead plans in `docs/superpowers/plans/` (archived sprints — plans are deleted on archival per §3.2) and **untracked 17 `reports/*.md`** (now gitignored; raw evidence stays in `reports/runs/`, conclusions in this file). Files remain on disk + in git history — nothing lost (reconciles §6.2 R18 "don't lose evidence" with §3.2 "keep the tracked tree clean").
- **Dead/duplicate-code audit result**: the repo is genuinely clean — 34 scripts shellcheck-clean, no dead code, no dead components, duplication is ≤3-line boilerplate; a shared lib is not warranted (each skill must stay standalone). No cleanup needed beyond the CI gate above.

### Breaking changes
- None.

### Migration
- `reports/*.md` is now gitignored. Existing copies stay on disk; the conclusions for every shipped version are already in this file. Per-sprint raw evidence belongs in `reports/runs/` (already gitignored).

### Known Limitations
- `doc-audit.sh` flags **all** plans in `docs/superpowers/plans/` for review (it can't tell "active" from "undead" deterministically) — verify each plan is an in-progress sprint before deleting.
- Carried forward: real zh / background / multi-worktree-feature-queue E2E, real macOS bash 3.2, SE17 a11y depth, v0.9 panel multi-seed N=3 tuning, Edge·HW-Verify real-hardware E2E.

## v0.19.0 — 2026-06-03

> **Edge·HW-Verify scaffold** (roadmap item ②). Ships the deterministic, stub-ssh-testable layer of remote edge-device deploy verification; the **real-hardware E2E is PENDING-VERIFY** (mock ≠ real, §7.3 — needs an actual device). TDD: `tests/unit/test_hardware_verify.bats` (12 cases). Suite 338 → 350.

### Highlights
- **`hardware-verify` skill + `/sdlc:hw-verify <device>`**: extends §7.3 本机部署验证 to a **remote** edge box (RK3588 / RISC-V / any SSH host). `verify.sh` scp's the artifact + deploy script, starts it via `nohup` (§4.4 SSH SOP — never `run_in_background`+ssh), polls the log over SSH, and renders a **PASS(0) / FAIL(3) / TIMEOUT(5)** verdict against `devices/<dev>/verify.yaml` (`ready_string` and/or `exit_code`).
- **Secrets via env only** (§1.4): creds come from `<DEV>_IP/_USER/_PASS` (uppercased device name); `--dry-run` redacts the password and contacts nothing; a real run **refuses placeholders**.
- **Testable without hardware**: `ssh`/`scp` are overridable (`SDLC_SSH_BIN`/`SDLC_SCP_BIN`), so 12 bats cases stub the transport and exercise the real dry-run / verdict / transport-fail / auth-fail / timeout / device-name-normalization paths. SE16-safe verdict parsing (`case`-glob, no `grep -q | …`).
- **`devices/<dev>/` convention** documented (lives in the target repo, never the plugin — read-only, per the stack-adapter rule).

### Breaking changes
- None. Purely additive: 1 new skill + 1 new command.

### Migration
- None. `devices/` is opt-in. Counts: skills 18 → 19, commands 25 → 26 (manifest synced; the dogfood "manifest not stale" test enforces this).

### Known Limitations
- **Real-device verification is PENDING-VERIFY**: only the deterministic transport+verdict layer is proven (stub ssh/scp). A real PASS requires running against actual hardware you provide (§7.3). The command states plainly whether it ran `--dry-run` or a real deploy.
- **v.next**: a live `health.port` probe and the `hardware-deploy-verifier` agent (interprets ambiguous real logs + writes the §7.3 evidence card) ship with the real-hardware impl, where there is a real log to interpret.
- Carried forward: real zh / background / multi-worktree-feature-queue E2E, real macOS bash 3.2, SE17 a11y depth, v0.9 panel multi-seed N=3 tuning.

## v0.18.0 — 2026-06-03

> Closes the #1 weakness from the v0.17 competitive review: gates were **prompt-codified, not harness-enforced** — an LLM could skip the "GA tag is a human hard-stop" rule. v0.18 makes the single most irreversible action a real harness invariant. TDD: `tests/unit/test_ga_tag_guard.bats` (15 cases) + 2 wiring-regression tests in `test_hooks.bats`. Suite 321 → 338.

### Highlights
- **Harness-enforced GA hard-stop** (`hooks/ga-tag-guard.sh`, `PreToolUse:Bash`): creating a **major GA tag** (`vN.0.0`, no pre-release suffix) is now **blocked at the tool layer (exit 2)** in an sdlc-gated repo unless a human approval marker is present (`SDLC_GA_APPROVED=1` or `touch .sdlc/ga-approved`). §7.2's "GA tag = human hard-stop, not skippable by `--auto`" is no longer just an agent-prompt instruction — the harness refuses the call.
- **Deliberately narrow + non-invasive** (so a normal repo with the plugin installed is never blocked from tagging): pre-1.0 minors (`v0.18.0`), patches (`v0.17.1`), and pre-release tags (`v1.0.0-rc.1`) all pass freely; `git tag -d` / `-l` pass; and if the repo has **no sdlc sprint state**, the hook no-ops entirely.
- **Regression-protected wiring**: new tests assert every `hooks.json` command resolves to an existing script (the "broken hook reference silently no-ops" anti-pattern) and that `ga-tag-guard` stays wired into `PreToolUse:Bash`.
- **Recorded the scope decision** as `docs/adr/0001` (orchestration-core vs. re-implemented SE audits): keep the SE-audit agents (self-containment forbids a hard dependency on `engineering-advanced-skills`; each earns its keep via a gate-consumable enforcement specific), with a new "earns-its-keep" guardrail for future agents. Dogfoods SE1.

### Breaking changes
- None for normal use. **Behavioral note**: in a repo using sdlc's gated flow, `git tag vN.0.0` (a major GA) now requires `SDLC_GA_APPROVED=1` or `.sdlc/ga-approved`. This is intended (§7.2) and affects only major GA tags; all other tags are unaffected.

### Migration
- None. No config or schema change. The "3 hook entries" count is unchanged (`ga-tag-guard` is a second command under the existing `PreToolUse:Bash` entry); there are now 4 hook scripts.

### Known Limitations
- The guard covers tag **creation**, not `git push <tag>` — pushing an already-created GA tag is not separately gated (creation is the commitment point; if approved, both proceed). A push-time guard is a possible future extension.
- "sdlc-gated repo" is detected by the presence of `.sdlc/state.json` or `docs/superpowers/handoffs/*_state.yaml`; a repo mid-migration without either is treated as non-gated (no-op).
- Carried forward: real zh / background / multi-worktree-feature-queue E2E (need real model), real macOS (non-docker) bash 3.2, SE17 a11y depth, v0.9 panel multi-seed N=3 tuning.

## v0.17.1 — 2026-06-03 (patch)

> Detector bug-fix on the Challenger Panel high-risk classifier (no new feature → patch, §7.1.2). TDD: `tests/unit/test_panel.bats` +12 calibration cases (7 true-positive must-escalate, 5 documented wrong-sense must-not). Suite 309 → 321, stress 10/10 (SE16-safe).

### Highlights
- **Panel high-risk grep calibrated** (`skills/challenger-panel/panel.sh dispatch`): the size-3→5 escalation classifier now drops provably wrong-sense lines before matching — the benign secret-handling form `${{ secrets.X }}` / `your-key-here`, LLM "token budget/cost", "handoff schema", "no migration / non-breaking" no longer false-escalate. `auth` was narrowed to `authentication|authorization|oauth` so the word "author" stops matching.
- **Fixed a latent false-NEGATIVE**: the old `api.*break` pattern missed "**breaking** API change" (word order); added `breaking` so real breaking changes now escalate (caught by the new TDD true-positive case).
- **SE16-safe by construction**: the two-stage filter uses `grep -c` (reads to EOF) instead of `grep -q | …` (early close), so it cannot SIGPIPE under `set -o pipefail` — dogfoods the v0.17 flake rule (`tests/PORTABILITY.md`).

### Breaking changes
- None. `dispatch` output contract (`high_risk=… size=… lenses=…`) unchanged; only classification accuracy improved.

### Migration
- None. No config or interface change.

### Known Limitations
- The wrong-sense filter strips by line; a single line mixing a benign secrets-ref with a real hardcoded secret could under-escalate. **Bounded, not unsafe**: `high_risk=no` still runs a normal size-3 panel that includes a security lens — escalation only raises the panel to 5. The orchestrator also still applies wrong-sense judgment per its prompt.
- Carried forward from v0.17.0 (unchanged): real zh / background / multi-worktree-feature-queue E2E (need real model), real macOS (non-docker) bash 3.2, SE17 a11y depth, v0.9 panel multi-seed N=3 tuning.

## v0.17.0 — 2026-06-03

> G1 3/3 mean 4.52;G2 2/2 4.50 —— reviewer 实测 fanout.sh 10/10 + 委托 panel.sh 路径。

### Highlights
- **多组件并行自动触发增强(conservative)**: 新 skill `auto-fanout/fanout.sh` —— 统一枚举"该并行触发哪些单元"(`groups`/`intake [--free-only]`/`panel`),orchestrator 据此在**一个 turn 批发**,不再人手逐个写 `Agent` 调用。
- **复用不重造**: `panel` 组**委托** `challenger-panel/panel.sh --dispatch`(size+high-risk+lens),`waves` 仍由 v0.10 implementer 拓扑,`intake` 7 维成为 SSOT。
- **固化 budget-gated 一次性批发**: task-orchestrator + intake-orchestrator 指令明确 —— fanout 清单 → **先过 `budget.sh`**(disk redline 硬停 + counter cap)→ 单 turn 全批发;清单 > avail → 分波。
- 保守边界:只枚举**已知**独立单元;**不**做依赖推断 / 跨 feature 自动调度(留激进版)。

### Breaking changes
- 无。panel.sh / budget / counter / waves 一字不改;fanout 是 opt-in 自动化(不调 = 旧手动行为)。

### Migration
- 无。

### Known Limitations
- **conservative**:无自动依赖分析 / 跨 feature·跨 phase 自动调度(deferred 激进版)。
- `panel` 组是 panel.sh 之上的**薄切片**(value 在统一接口 + 固化批发);`waves` 仍在 implementer(未纳入 fanout.sh)。
- "自动批发"是 orchestrator **prompt 行为的固化**(非代码强制);budget.sh 闸门前置不变。
- v0.17 是 GA 前 minor(用户 2026-06-03);后续 v0.18 ② Edge·HW-Verify(需真硬件)→ v1.0 GA。

## v0.16.0 — 2026-06-02

> G1 3/3 mean 4.33;G2 2/2 4.50 —— reviewer 实装 10/10 + 注入假 secret 验回归 + 注入拒绝。

### Highlights
- **`/sdlc:pipeline` + `pipeline-emit/emit.sh`**: **确定性** stack-config 驱动的 CI yaml emitter —— build/lint/test 命令**逐字来自** `config/stack-<name>.yaml`(非 LLM 自由生成,可复现可测)。
- **5 强制 stage** build/lint/test/security_scan/publish(emit 前 self-check,缺即拒);scanner map(rust→cargo audit / ts→npm audit / python→pip-audit / go→govulncheck / generic→占位)。
- **secret 只占位**(`${{ secrets.X }}` / `$ENV`,**绝不**明文,§1.4);命令走 **YAML block scalar**(`run: |`)—— config 命令含引号也不破 yaml(G2 fold-in,输出恒可解析)。
- **与 cicd-designer 互补不重复**:emit = 确定性 CI 核心;cicd-designer = LLM 设计层(CD 策略 canary/blue-green + rollback runbook + 平台判断)。

### Breaking changes
- 无。cicd-designer / config/stack-* 不改;`/sdlc:pipeline` 是新命令。

### Migration
- 无。

### Known Limitations
- 平台仅 **github + generic**;gitlab/jenkins 标 planned。
- emit 只出 **CI 核心**(build→publish);**CD 策略 + rollback runbook 仍在 cicd-designer**(`/sdlc:cicd`,刻意分工)。
- 拆分:roadmap v0.14 "功能补齐" → v0.14(handoff v2)/ v0.15(SE13-20)/ **v0.16(本版 /sdlc:pipeline)**;之后 **v1.0.0 GA(人工硬停 §7.2 + 本机部署验证 §7.3)**。

## v0.15.0 — 2026-06-02

> G1 3/3 mean 4.87;G2 3/3 5.00 —— reviewer 实测 catalog 一致性测试 + 变异验证。

### Highlights
- **SE 风险登记 12 → 20**: Appendix G.7 定义 **SE13–SE20**(secrets 硬编码/backup-restore 演练/config 漂移/flaky test/可访问性·i18n/load·capacity/doc 漂移/供应链 SBOM)。清掉 roadmap §5 登记的 "15/20 声明 vs 实际 SE1-12" **诚信缺口** → 现 **SE1–SE20 = 20/20 诚实**。
- **映射诚信**: 每条映射到**现有** owner(dependency-auditor / incident-responder / project-onboarding / cicd-designer / tester / performance-analyst / docs-curator / i18n);SE17 a11y 子项**明确标 planned深化**(不假装已覆盖,§6.3)。
- **catalog 一致性测试** `test_se_catalog.bats`: 钉死 SE1..SE20 连续无缺口 + 无重复 + 每行 4 列 + owner 非空 + SE1-12 逐字回归 + CLAUDE 引用无 stale。

### Breaking changes
- 无。SE1–SE12 逐字不变(append-only)。

### Migration
- 无。

### Known Limitations
- **定义型 minor**:SE13–20 的 owner 覆盖深度因条目而异;`planned深化` 项(SE17 a11y 子项)本版**只定义不实现**(留 edge/web 版),诚实标注而非虚报覆盖。
- 拆分:roadmap v0.14 "功能补齐" 按 §7.1 拆为 v0.14(handoff v2,已 ship)/ **v0.15(本版 SE13-20)**/ v0.16(/sdlc:pipeline);之后 v1.0 GA(人工硬停)。

## v0.14.0 — 2026-06-02

> G1 4-lens panel mean 4.89 —— "schema" 触发 high-risk,经 backward-compat 专项 lens **一致裁定 additive/非 breaking** → 非 class#2 → AUTO_ADVANCE,未升级人工;G2 3/3 mean 5.00,reviewer 在 /tmp 实装跑 15/15 全绿 + v1 逐字对比一致。

### Highlights
- **handoff schema v2**: `validate.sh` 接受 `schema_version ∈ {1,2}`;v2 在边界**强制** `producer` + `model_tier`(`haiku|sonnet|opus`,Appendix D.3)+ `self_score`(`rubric_ref` + `overall ∈ [0,5]`,Hard constraint #7)。把两条原本只是约定的硬规则升为**机器校验**。
- **4 个 kebab 错误码**:`handoff-v2-missing-producer` / `-bad-model-tier` / `-missing-self-score` / `-bad-self-score`(`overall` 先正则验数字再 awk 验区间,拒 `7`/`-1`/`abc`)。
- **v1 逐字不变**:v2 块全在 `if [ "$sv" = "2" ]` 内,v1 路径完全绕过(G1+G2 双重验证 byte-for-byte);v0.9 panel forgery guard 在 v1/v2 都生效。

### Breaking changes
- 无。v1 handoff 校验**逐字不变**;v2 是 additive opt-in(G1 panel 一致裁定非 breaking)。

### Migration
- 无。新 producer 设 `schema_version: 2` 即进 v2 校验。

### Known Limitations
- `self_score` 只校验 `overall` + `rubric_ref`,per-criterion 分数未校验(留 v.next);model_tier 枚举硬编码(集中一处,引 Appendix D);不自动升级存量 v1 handoff(刻意)。
- 拆分说明:roadmap v0.14 "功能补齐" 按 §7.1 拆为 focused minors —— **本版 = handoff v2**;v0.15 = SE13–SE20;v0.16 = /sdlc:pipeline;之后 v1.0 GA(人工硬停)。

## v0.13.0 — 2026-06-02

> G1 panel AUTO_ADVANCE 3/3 mean 4.62;G2 3/3 mean 4.87,在 docker GNU bash 3.2.57 实测全绿。

### Highlights
- **i18n 交互语言层**: `SDLC_LANG=zh|en|bilingual` 环境约定 + `skills/i18n/lang.sh`(`lang` 解析 + `msg <key>` 查表)+ 核心消息 catalog `messages.tsv`(en/zh,TSV `key<TAB>en<TAB>zh`)。中文用户用母语读 status/gate 决策/scorecard。
- **task-orchestrator 输出语言约定**: human-facing 摘要按 `SDLC_LANG` 产出;**technical token 恒英文**(identifier / phase 名 / error-code / JSON key / commit / path —— 机器契约不翻译)。
- **机制优先,不漂移**: 单 catalog SSOT + 按需扩行;**不**翻译全量 17 agent / 24 command prompt(避 §3.2 漂移)。
- **优雅降级**: `SDLC_LANG` unset/非法 → en;未知 key → 回显 key;zh 列空 → 回退 en(bilingual 无尾随 ` / `);catalog 缺失 → 全回显 key 不崩。

### Breaking changes
- 无。默认 `en`(unset)→ 既有英文输出**逐字不变**。

### Migration
- 无。

### Known Limitations
- **lean 范围**:机制 + 核心 catalog(~12 key)only,**不**做 per-agent/command 全量翻译(按需扩 catalog,避 §3.2 漂移)。
- 自由 prose 摘要的语言靠 agent 遵循约定(catalog 只覆盖结构化串);只 zh/en(无其他 locale / RTL);bash 脚本尚未 retrofit 到 lang.sh(opt-in 渐进)。
- **PENDING-VERIFY**:真 zh 全链交互 sprint 未跑(lang.sh 18 unit 测试覆盖,**已在 docker GNU bash 3.2.57 实测全绿** —— 即 macOS 的 bash 版本,但非真 macOS,故只**部分**清掉 macOS bash 3.2 顾虑);端到端 zh-interaction E2E 未跑。

## v0.12.0 — 2026-06-02

> G1 panel AUTO_ADVANCE 2/3 mean 4.29;G2 3/3 mean 4.67。

### Highlights
- **后台 job 注册表 `async-dispatch/jobs.sh`**: `register`/`complete`/`list`/`inflight`/`reap` —— 文件级 `.sdlc/jobs/<id>.job`(status/ts/label),复用 v0.9 `atomic.sh`(atomic rename → 无锁读安全)。让 orchestrator 用 `run_in_background` 派长审计后**不阻塞**,异步收集。
- **派发/收集异步模式**: task-orchestrator + intake-orchestrator 加 `run_in_background` 派发 + register → 继续别的 phase → 回头 `complete` 收。merge-queue(v0.11)**仍串行**(打 tag 不可并发),只有派发/收集侧 async。
- **`/sdlc:status` 在途可见性**: 显示 in-flight(running)+ orphaned(崩溃)job,长审计不再"消失"。
- **crash 兜底 + slot 不泄漏**: `reap --max-age` 把超时 running 标 orphaned 并打印 `reaped=<id>`,orchestrator 据此 `counter_release`(与 complete 对称 —— G1 panel correctness 抓的崩溃-slot-泄漏已堵)。
- 技术并行维 ④(最后一条轴):v0.9 并发原语 → v0.10 task 并行 → v0.11 feature 并行 → **v0.12 派发/收集 async**。

### Breaking changes
- 无。async opt-in;`atomic.sh` / `counter.sh` 一字不改(jobs.sh 与 counter 正交);默认同步行为不变。

### Migration
- 无。

### Known Limitations
- **后台执行本身 = harness `run_in_background`**(Agent/Bash tool),本版只做**状态追踪 + 派发指引**,不自己实现后台执行。
- 无 harness async → 退化同步(register → run → 立即 complete),注册表仍工作。
- **slot 释放是 orchestrator 职责**:jobs.sh 保持与 counter 正交,只打印离开 running 的 id(`completed=`/`reaped=`),orchestrator 据此 `counter_release`(不自动)。
- 不做跨 session agent 重连、实时进度流、async merge-queue。
- **PENDING-VERIFY**:真 `run_in_background` 派发 + 异步收集的端到端 sprint 未实跑(jobs.sh 已 21 unit 测试,registry 状态机 + reap + 注入 + label 净化全覆盖,但真后台 agent 全链未跑);macOS bash 3.2 真机未验。

## v0.11.0 — 2026-06-02

> G1-reviewed。

### Highlights
- **跨 feature 串行 tag merge-queue**: 新 skill `merge-queue/queue.sh` 把完成的多个独立 feature branch 按完成顺序逐个 merge 回主线,**在每次 clean merge 的时刻**从现有 release tag 算出下一个版本号并打 tag(§7.1.7「版本号 merge-时刻分配」)。复用 v0.10 `worktree-merge/merge.sh` 做实际 merge + 冲突检测(DRY)。
- **shard-then-merge 第三次抬升**: v0.9 文件层 → v0.10 task-branch 层 → v0.11 **feature-branch 层**(feature = shard,git merge + 版本 + tag = merge)。
- **worktree-per-feature 派发**: task-orchestrator 加 cross-feature 模式 —— N 个独立 feature 各在隔离 worktree 跑完整子 SDLC,收 branch 喂 queue,复用 v0.9 budget/counter 闸门。
- **multi-repo 雏形**: `queue.sh --repo <path>` 让 merge-queue 作用于任意 repo,证明原语 repo-参数化(为 ent-v1.0 多 repo 编排打底)。
- **`/sdlc:merge-queue` 命令** + 版本号预发布过滤(`-rc`/`-alpha`/`-beta` 不污染版本排序)+ `--dry-run` 预演版本序列。

### Breaking changes
- 无。`worktree-merge/merge.sh` 一字不改;单 sprint 流程不动;merge-queue 经 `/sdlc:merge-queue` opt-in。

### Migration
- 无。queue 是加法;releaser 仍管单 sprint 发版,queue 管多 feature 合流的版本分配(互补)。

### Known Limitations
- **multi-repo 仅 `--repo` 雏形**(一次一个 repo);跨 repo 依赖排序 / 原子多 repo 同步 tag → ent-v1.0。
- **冲突需手工 rebase-on-new-baseline**:queue 冲突即停 + 报告,被挡 feature 必须 rebase 新基线后重入;**永不自动 rebase / 自动解决**(§5.1)。
- **tag 仅本地**:queue 只 `git tag` 不 push(§7.2 push = 用户动作)。
- **tag-collision 是 TOCTOU backstop**:`next_version` 取 max+1,单 driver 下不自撞;`git tag` 无 `-f`(永不 force-overwrite)是真保证(TDD 实测确认)。
- **PENDING-VERIFY**:派多 worktree feature sub-agent 真跑完整子 SDLC → 喂 queue 的端到端 multi-feature sprint 未实跑(queue.sh 已 18 测试覆盖,但 E2E 全链未跑);macOS bash 3.2 真机本 sprint 未验(脚本按 PORTABILITY.md 写,POSIX numeric sort 替代 `sort -V`)。

## v0.10.0 — 2026-06-02

> 并行 impl DAG。

### Highlights
- **worktree-per-task 并行实现**: implementer 把 plan 的无依赖 task 组(`parallelizable_with`)拓扑分层成 wave,每个 task 用 `Agent isolation:'worktree'` 在独立工作树跑 TDD,互不踩文件。
- **串行 merge + 冲突检测**: 新 skill `worktree-merge/merge.sh` 按拓扑序 merge 各 branch,**冲突 abort + 报告 + escalate 回 architect 重排 DAG,永不自动解决**。branch = v0.9 的 shard,git merge = serial merge(同构)。
- **解除 max-2**: 隔离做对后,并行组大小由 `SDLC_MAX_PARALLEL` 决定(不再硬限 2)。
- 复用 v0.9 dispatch-batch(counter cap + `budget.sh` disk 闸门)。

### Breaking changes
- 无。`parallelizable_with` plan schema 不变;无标注 → 退串行。

### Migration
- 无。老 plan 直接可用。`SDLC_MAX_PARALLEL=1` 退化纯串行。

### Known Limitations
- **worktree 隔离依赖 harness 的 `Agent isolation:'worktree'`**;无此能力时退串行(merge.sh 仍可用于任何 branch 列表)。
- **全链并行 impl 未跑真 multi-task sprint**: merge.sh 有 bats 覆盖(干净/冲突/abort/单 branch),但"派 N 个 worktree sub-agent 真并发跑 TDD 再 merge"是 real-LLM,**PENDING-VERIFY**(本会话未跑)。
- worktree 占盘受 `budget.sh` disk redline 约束;大 repo 调低 `SDLC_MAX_PARALLEL`。

## v0.9.0 — 2026-06-02

> 并发地基 + Challenger Panel。

### Highlights
- **并发安全地基**: `atomic.sh` (mkdir 可移植锁 + temp+rename 原子写,**不依赖 flock**) + 跨 turn in-flight `counter.sh` + `budget.sh` 真闸门 (in_flight/avail) + dispatch-batch 协议 + shard-then-merge。并发正确性由 20-进程 race 测试守 (无丢失更新)。
- **真并行 intake fan-out**: deps/debt/docs/disk 经 dispatch-batch 单 turn 并发派发。
- **Challenger Panel**: 单 Challenger → N expert 多 lens 投票 (默认 3 / 高危 5,复用 `eval/judge.sh` 投票核心); consensus-auto 高置信自动推进,降低人机交互; 四类高危 (secret/auth · schema/migration · 不可逆/prod · STRIDE 高残留) 永远 escalate; GA 永远硬停。
- **DRIVE consensus-auto 默认**: `--interactive` 完全回退旧逐-gate 停人行为; `--auto` 最激进但四类高危 + GA 仍停。

### Breaking changes
- DRIVE 默认行为从「每 Challenger gate 停人」改为 consensus-auto。`--interactive` 恢复旧行为。

### Migration
- handoff `panel_score` 为新增可选 block, 老 handoff 向后兼容 (schema 仍 v1, 无需迁移)。首次 `/sdlc:run` 自动 `counter_reset`。`SDLC_MAX_PARALLEL=1` 退化为纯串行逃生门。

### Known Limitations
- **Panel N-expert 真投票 = 真 LLM 验证通过** (2026-06-02, N=1 calibration, sonnet experts; 报告 `reports/2026-06-02_v0.9-panel-real-llm-verify.md`): 机制 + 判别力 (correctness 抓真 bug、security 抓 hardcoded credential FAIL/1) + consensus 算术均经真 expert 验证,panel 正确拒绝 auto-advance 有缺陷产物。**两条校准限制**: (a) panel 偏严 → escalate 率高,consensus-auto 的实际降频效果取决于 threshold(4.0) + lens prompt 的 "blocking vs nit" 校准 (full multi-seed N=3 tuning 待做); (b) high-risk 检测是朴素 grep,否定语境 ("no secrets") 会 false-positive (偏安全侧, v0.x patch 优化)。
- 并发原语在 **Linux 验证** (mkdir 锁 + 20-进程 race);**macOS bash 3.2 真机未验证** (§5 要求,留 follow-up)。
- `SDLC_MAX_PARALLEL` 默认保守 **2**;提到 4 需 disk/token 实测支撑 (§6.3),未做。
- 跨 turn 并发依赖 harness「单 turn 多 Agent 调用」语义;`counter` 是软上限,会话崩溃后可能失准 (靠 `counter_reset` 自愈)。

## v0.8.0 — 2026-06-01

### Highlights
- **`/sdlc:run` — half-managed full-chain driver.**
  Activates the previously-orphaned `task-orchestrator` in a new DRIVE mode (it was only
  reachable read-only via `/sdlc:status`). Drives `spec → plan → impl → review → test →
  release` in a single command, pausing after each Challenger gate (G1–G4) for a
  continue / stop / redo decision before proceeding. A GA hard-stop prevents the tag from
  being pushed without explicit human confirmation — `--auto` can reach RC but cannot
  bypass the final gate. Start/resume is idempotent: re-running `/sdlc:run <slug>` on an
  already-started sprint resumes from the last completed phase. Optional `--intake`
  pre-flight runs `/sdlc:intake` before the chain begins, reusing the v0.7.0 inspection
  infrastructure.

### Breaking changes
- None.

### Migration
- None — purely additive command. `/sdlc:status` read-only behavior is unchanged. The
  `task-orchestrator` agent and `.sdlc/state.json` format are backward-compatible; DRIVE
  mode is a new branch in the agent's prompt, not a schema change.

### Known Limitations
- Full-chain DRIVE is real-LLM and is not exercised in CI; smoke + E2E are human-triggered
  (§7.2 Gate 3). **Verified 2026-06-01**: a real bounded drive E2E (real `spec-analyst` →
  real `architect` G1 PASS → `spec:plan` transition handoff passing `handoff-schema/validate.sh`
  → `cargo build` OK) confirmed the chain crosses the G1 gate and the build path works. This
  surfaced + fixed a pre-existing blocker (transition-handoff phase-vocab mismatch — see the
  `fix(run)` commit) that had made the orphaned orchestrator's drive path non-functional. The
  full impl→review→test→RC→GA tail is exercised at release time via `/sdlc:release`.
- `--auto` reaches RC but stops at the GA hard-stop: tagging always requires a human.
- Single-sprint only — parallel sprint execution is not supported in this release.

---

## v0.7.0 — 2026-06-01

### Highlights
- **`/sdlc:intake` — one-command full project inspection.**
  Runs a tiered sweep (`light` / `standard` / `deep`) across all audit dimensions (docs,
  architecture, threat, performance, dependencies, tech debt, CI/CD, code quality), writes
  per-dimension sub-reports to `reports/<date>/`, and consolidates them into a single
  `reports/<date>-project-health.md` scorecard with an overall verdict (HEALTHY / NEEDS-ATTENTION / AT-RISK).
- **New `codebase-reviewer` agent** — two-pass whole-repo review: pass 1 ranks hotspots
  (complexity / churn / coverage gap / security surface) via static signals; pass 2 deep-dives
  the top-N files with a structured finding per location. Closes the gap where no agent
  previously swept the full codebase in a single invocation.
- **New `intake-consolidation` skill** — deterministic plan/emit/consolidate spine used by
  `intake-orchestrator`. Provides the `plan.sh` dimension planner, `emit-subreport.sh`
  sub-report writer, and `consolidate.sh` scorecard merger; all three are fully bats-tested.
- **Three gaps closed by this release:**
  1. No whole-codebase review agent — now `codebase-reviewer`.
  2. No aggregator that combines all audit dimensions — now `intake-consolidation`.
  3. Threat/perf audit not reachable in a single command — now `/sdlc:intake --deep`.

### Breaking changes
- None — purely additive.

### Migration
- No migration required. `/sdlc:intake` reads but never mutates `.sdlc/state.json`; all
  existing onboarded repos work without re-running onboard.
- Intake writes per-dimension sub-reports to `reports/<date>/` and the consolidated scorecard
  to `reports/<date>-project-health.md`, alongside other audit-command reports under `reports/`.
  These paths are not auto-ignored by the onboard template; commit or clean them at your discretion.
- All reused audit agents (docs-curator, performance-analyst, dependency-auditor, etc.) are
  unchanged — their prompts and APIs are unmodified.

### Known Limitations
- **Cost on large repos**: the `standard` and `deep` tiers invoke multiple opus/sonnet agents.
  Mitigated by a top-N hotspot cap in `codebase-reviewer` and a cost-gate that prints a USD
  estimate and requires confirmation before proceeding.
- **Threat / perf full-sweep only in `deep`**: `light` omits threat and performance; `standard`
  includes a lightweight pass. Use `--deep` for full STRIDE + SLI/SLO coverage.
- **`codebase-reviewer` hotspot-ranking quality**: real-LLM multi-seed eval **PASS — 3/3 seeds
  (rate 1.00, sonnet)** on the shipped fixture (`eval/fixtures/codebase-reviewer/`): top hotspot
  correctly ranked `big_handler.py` across all seeds and the deep review found both the planted
  null-deref and an additional real inventory-leak path. Re-run `/sdlc:eval codebase-reviewer` to
  benchmark on your repo. Behavioral eval coverage 14/17.

---

## v0.6.6 — 2026-05-31

### Highlights
- **Generalized the F1 fix into a principle, surfaced by the second full-chain dogfood.**
  The same root cause as F1 (agents cannot read the plugin's own files — `CLAUDE_PLUGIN_ROOT`
  is unset for agents) was found in two more places; both now fixed the same way: onboard
  **materializes the asset into the repo's `.sdlc/`** and agents read it repo-relative.
  - **Stack adapter**: tester/implementer referenced `config/stack-<lang>.yaml` repo-relative
    (unreachable). onboard now copies the detected adapter to `.sdlc/stack.yaml`; tester,
    implementer, and `/sdlc:test` read it there; doctor verifies it's materialized. (The
    tester had silently fallen back to bare `pytest` — fine for Python, wrong for non-obvious
    stacks.)
  - **Disk config reconciled**: `.claude/sdlc-orchestrator.local.md` carried `disk_redline_*`
    keys that **nothing read** (the hook reads `.sdlc/disk.conf`). Removed the dead keys;
    onboard now seeds a commented `.sdlc/disk.conf` as the single disk-redline surface.

### Second dogfood result (wc-cli)
- A full `/sdlc:spec → release` chain on the loaded **v0.6.5** agents produced `wc-cli` and
  tagged it v0.2.0. Confirmed F1 closed-loop (spec-analyst read `.sdlc/templates/spec-template.md`
  on its own), the G3 gate caught a real spec-doc defect (`echo … | wc` expected `0 2 9`, correct
  `1 2 9`), and the tester added 8 boundary tests (49→57). Agents showed strong discipline:
  refused to fabricate a git SHA, self-corrected a char miscount before tagging, distinguished a
  wrong-test-expectation from a prod bug.

### Breaking changes
- None.

### Migration
- Existing onboarded repos: re-run `/sdlc:onboard` (idempotent) to materialize `.sdlc/stack.yaml`
  + `.sdlc/disk.conf`. The removed `disk_redline_*` keys in `.local.md` were already no-ops.

### Known Limitations
- The "materialize plugin assets in-repo" pattern means an onboarded repo carries copies under
  `.sdlc/` (gitignored); plugin upgrades don't auto-refresh them — re-run onboard (it never
  overwrites edited files, so delete a stale copy first if you want the new version).
- Behavioral eval coverage 12/15 (unchanged).

### Evidence
- 138 bats PASS both envs (onboard 10 → 13: stack materialized + disk.conf seeded + dead-keys-gone).
- E2E: fresh repo onboard → `.sdlc/stack.yaml` (9-line python adapter) + `.sdlc/disk.conf`; doctor READY.
- `claude plugin validate` PASS. Real CI green ubuntu+macOS before tag (rule 11).

---

## v0.6.5 — 2026-05-31

### Highlights
- **F1, actually fixed this time — closed-loop verification caught that v0.6.4's F1 was inert.**
  v0.6.4 pointed the agents at `${CLAUDE_PLUGIN_ROOT}/templates/…`, but probing a real
  dispatched agent proved `CLAUDE_PLUGIN_ROOT` is **UNSET** in the agent environment (CC only
  substitutes it inside `hooks.json`). So that path never resolved — agents always fell back.
- **Real fix**: `onboard.sh` (which knows its own location via `$0`) now **materializes the
  plugin's `templates/*.md` into the repo's `.sdlc/templates/`** — idempotent, never
  overwrites an edited template, and `.sdlc/` is gitignored so the git tree stays clean.
  spec-analyst / architect / architecture-reviewer now reference `.sdlc/templates/<x>.md`
  (which exists after onboard); the §3.1 inline structure remains the always-works fallback.
- Verified end-to-end: re-onboarding a real repo materialized `.sdlc/templates/spec-template.md`
  at exactly the path the corrected agent prompt reads.

### Breaking changes
- None.

### Migration
- Existing onboarded repos: re-run `/sdlc:onboard` (idempotent) to materialize the templates.

### Known Limitations
- `CLAUDE_PLUGIN_ROOT` is unavailable to agents by design — any agent needing a plugin asset
  must get it materialized in-repo (onboard) or fall back to an inline contract.
- The `.claude/sdlc-orchestrator.local.md` config stub carries `disk_redline_*` keys that the
  disk audit does NOT read (it reads `.sdlc/disk.conf`); reconciling the two config surfaces is
  deferred (tracked for a later release).
- Behavioral eval coverage 12/15 (unchanged).

### Evidence
- 135 bats PASS both envs (onboard 8 → 10: template materialized + never-overwrite).
- Probe agent: `CLAUDE_PLUGIN_ROOT=UNSET` in dispatched agent env (the v0.6.4 defect).
- `claude plugin validate` PASS. Real CI green ubuntu+macOS before tag (rule 11).

---

## v0.6.4 — 2026-05-31

### Highlights
- **Fixes for the 3 friction points the full-chain dogfood surfaced** (all real, none cosmetic):
  - **F1 — template path**: spec-analyst / architect / architecture-reviewer referenced
    `templates/spec-template.md` **repo-relative**, so in an onboarded repo (which has no
    `templates/`) the plugin-shipped template wasn't found. Now they reference
    `${CLAUDE_PLUGIN_ROOT}/templates/…`. And the spec-analyst instruction is corrected to
    **bless the §3.1 fallback** instead of "escalate/block" — exactly what the dogfood agent
    wisely did on its own. The 11 sections are the contract, not the template file.
  - **F2 — handoff ownership**: pr-reviewer + tester are read-only by design (no Write tool).
    review.md / test.md now state explicitly that the **orchestrator persists** the handoff
    YAML the agent returns, to `docs/superpowers/handoffs/`. No more "reviewer can't write
    its handoff" ambiguity.
  - **F3 — local-install update**: documented (DEVELOP §6.6) that a local-path marketplace
    needs `claude plugin marketplace update <mp>` + the fully-qualified
    `claude plugin update <name>@<marketplace>` (the bare form fails "not found"), then a
    restart. Not a code bug — a CLI incantation now written down.

### Breaking changes
- None.

### Migration
- None. Agent-prompt + command-doc corrections; no schema/behavior change for existing repos.

### Known Limitations
- `${CLAUDE_PLUGIN_ROOT}` resolution inside an agent's environment is best-effort; if unset,
  agents fall back to the canonical §3.1 / inline structures (no hard failure).
- Behavioral eval coverage 12/15 (unchanged).

### Evidence
- 133 bats PASS both envs; `claude plugin validate` PASS; structure/frontmatter guards green.
- Real CI green ubuntu+macOS before tag (rule 11).

---

## v0.6.3 — 2026-05-30

### Highlights
- **First full-chain dogfood (`/sdlc:spec → release` on a real Python project) — and it
  worked, finding real bugs along the way.** Drove a tiny `wc-core` library through all 6
  phases with live agent dispatches: spec-analyst (11-section spec) → architect (G1 +
  TDD plan) → implementer (3 TDD commits) → **pr-reviewer FAILed G3** → refix → **G3 PASS**
  → tester (G4) → releaser (4 gates + 本机部署). ~30 min wall-clock, 7 dispatches.
- **The disk-guard fix that made it possible**: the hook runs as a separate CC-spawned
  process, so a redline exported in a shell never reaches it, and the flat 50G-on-`/`
  redline hard-blocked builds on a box with a small `/` + a dedicated `/data`. `audit.sh`
  now reads `redline_{root,data,tmp}_gb` from a **config file** (`~/.config/sdlc-orchestrator/disk.conf`
  or project `.sdlc/disk.conf`) — visible to the hook subprocess, no restart needed.
  Precedence: env > project > machine > built-in default. +2 tests.

### What the dogfood proved (and the bugs the gates caught)
- **The G3 review gate earned its keep**: the generative chain (spec→plan→impl) propagated
  a subtle defect — an "adversarial NBSP" test that actually used an ASCII space (`0x20`,
  not U+00A0) — and only the independent pr-reviewer caught it by dumping codepoints. The
  gate FAILed, the implementer refixed, the re-gate independently re-verified. This is the
  central value of an adversarial gate: it catches blind spots the generators share.
- The tester independently found uncovered whitespace-class boundaries (`\v`/`\f`/`\t`,
  `\r`-only, `\r\n` line-count) and added 7 passing regression tests (29 → 36).
- Agents honored the discipline: real RED/GREEN observed, per-task commits, honest deviation
  reporting (the implementer self-caught an R18 reports-not-committed gap), read-only reviewer
  correctly could not write code.

### Breaking changes
- None.

### Migration
- None. Additive. The built-in 50/50/5 redline still applies when no config file/env is set.

### Known Limitations
- Disk redline config is read from `~/.config/sdlc-orchestrator/disk.conf` and project
  `.sdlc/disk.conf`; there is no global `claude` settings integration (use the file).
- Friction noted but not yet fixed: onboard does not scaffold a `templates/spec-template.md`
  (spec-analyst falls back to §3.1 cleanly); read-only agents (reviewer) cannot persist their
  own handoff YAML — the orchestrator must write it.
- Behavioral eval coverage 12/15 (unchanged).

### Evidence
- 133 bats PASS both envs (disk audit 4 → 6: project & machine config-file precedence).
- Dogfood artifacts: a real `wc` repo tagged v0.1.0 via the chain (spec/plan/reports/RELEASE
  all produced by the agents); full transcript in this session.
- Real CI green ubuntu+macOS before tag (rule 11).

---

## v0.6.2 — 2026-05-30

### Highlights
- **The plugin now actually passes `claude plugin validate`** — the real loader's validator,
  run for the first time during deployment, found 2 bugs that 129 bats tests + the
  official-layout comparison missed across 10 tagged releases:
  - `author` was a string; CC schema requires an object `{name, email}` — a string fails
    validation (the plugin would not load cleanly).
  - `commands/test.md` had `argument-hint: <scope: unit|...>` — the colon-space broke the
    YAML, so the loader **silently dropped all of test.md's frontmatter** (`/sdlc:test`
    loaded with no description/allowed-tools).
- **Mechanical guard added** so this class can't recur: `test_plugin_structure` now asserts
  the manifest author is an object AND every command/agent/skill frontmatter yq-parses —
  deterministic, runs in CI, no claude CLI needed.

### Breaking changes
- None (the fixes make the plugin load *correctly*; nothing that worked breaks).

### Migration
- None.

### Known Limitations
- `claude plugin validate` still emits a benign warning that the plugin-root `CLAUDE.md`
  isn't loaded as context — intentional; it's plugin-dev notes, not shipped context.
- Behavioral eval coverage 12/15 (unchanged).

### Evidence
- `claude plugin validate` → "Validation passed with warnings" (only the CLAUDE.md note).
- 131 bats PASS both envs (added author-is-object + frontmatter-parse guards).
- Real CI green ubuntu+macOS before tag (rule 11).

---

## v0.6.1 — 2026-05-30

### Highlights
- **First real-project deployment validation — and it found a real gap.** Deployed the
  deterministic layer (`onboard.sh` / `doctor.sh` / `cost.sh`) against an actual multi-file
  repo (Python processors + YAML, not the toy): onboard scaffolded correctly, doctor
  reported READY (0 issues), cost estimated a sprint — all worked end-to-end on real code.
- **The validation surfaced a stack-detection gap** a toy/synthetic test never would:
  `detect-stack` only checked `pyproject.toml`/`setup.py`, so a real Python project using
  `requirements.txt` was detected as `generic`. Fixed: added `requirements.txt` + `Pipfile`
  markers (2 new tests).
- Honest scope of validation: the **deterministic layer is validated on real code**; the
  **agent layer is eval-validated (12/15)**; the **interactive slash-command layer** requires
  a real Claude Code session with the plugin loaded (`claude --plugin-dir <path>` or install)
  — headless `-p` mode does not surface slash commands, so it can't be fully exercised here.

### Breaking changes
- None.

### Migration
- None. Pure detect-stack improvement. Existing repos re-detect correctly (idempotent onboard).

### Known Limitations
- `detect-stack` is still root-marker-based: a project whose code is nested with no root
  manifest is (correctly) `generic`. Recursive/heuristic detection is out of scope.
- Interactive plugin loading (live `/sdlc:*` commands) is validated by the user's real
  session, not headless — see Highlights.
- Behavioral eval coverage 12/15 (unchanged from v0.6.0).

### Evidence
- detect-stack 8 tests (added requirements.txt + Pipfile); full suite 129 PASS both envs.
- Real-project deployment: onboard/doctor/cost run on an actual repo (scratch copy, zero risk).
- Real CI green ubuntu+macOS before tag (rule 11).

---

## v0.6.0 — 2026-05-30

### Highlights
- **LLM-judge grader — behavioral eval coverage 10 → 12.** A new `kind: llm_judge`
  assertion judges narrative quality grep can't reach (e.g. "does the 5-Why descend to a
  process root?", "are the ADR Consequences real trade-offs?"), for the 2 free-form agents
  architecture-reviewer + incident-responder. Both 3/3 robust on structure (grade.sh) AND
  quality (judge.sh).
- `eval/judge.sh`: `--parse` (pure verdict extraction, CI-tested) / `--run` (real LLM judge,
  N=3 majority, structured VERDICT) / `--calibrate`.
- **Calibration is the trust gate, and it worked**: both judges PASS a known-good output and
  FAIL a deliberately planted-bad one (a postmortem whose root cause doesn't descend; an ADR
  whose consequences restate the decision). This is the honest answer to "who judges the
  judge" — demonstrated discrimination, not assumed perfection.
- grade.sh stays pure (skips llm_judge); the judge is eval-time only — **zero impact on user
  per-invocation cost**, never in CI.

### Breaking changes
- None.

### Migration
- None. Additive (judge.sh + 2 fixtures + llm_judge kind). grade.sh deterministic behavior
  unchanged; existing 10 fixtures unaffected.

### Known Limitations
- The LLM-judge is **non-deterministic and fallible** — a SIGNAL, not a proof. Mitigated by
  calibration (proven to discriminate good/bad on known cases) + N=3 majority + sharp rubrics
  demanding a quoted line. Never in CI (CI runs only judge.sh --parse + grade.sh, both pure).
- Coverage 12/15. The last 3 (implementer / task-orchestrator / disk-monitor) need a
  different harness (live repo / meta / already bats-tested), not an LLM-judge.
- Single judge model (opus); multi-model cross-voting deferred to v0.6.1.

### Evidence
- judge.sh --parse CI-tested (6 tests); grade.sh unchanged (7); full suite 127 PASS both envs.
- Calibration + eval: reports/2026-05-30-llm-judge.md (both judges discriminate planted-bad;
  real eval 2 agents @ opus N=3, structure 3/3 + quality 3/3).
- Real CI green ubuntu+macOS before tag (rule 11).

---

## v0.5.1 — 2026-05-30

### Highlights
- **Behavioral + cost eval coverage 5 → 10 of 15 agents.** Added fixtures + contracts for
  architect / pr-reviewer / performance-analyst / tech-debt-tracker / cicd-designer; each
  graded independently by `grade.sh` at N=3 — **all 3/3 robust**.
- **2 more eval-verified tier downgrades** (per-invocation cost savings): performance-analyst
  and cicd-designer both 3/3 robust at haiku → auto-downgraded sonnet→haiku (semi-mechanical).
  Tier distribution now opus×6 / sonnet×2 / haiku×7 (was opus×6 / sonnet×5 / haiku×4 at v0.2).
- architect / pr-reviewer cheaper-tier remain recommend-only (judgment agents, C1).
- Found & fixed a grader brittleness: architect first scored 0/3 because the assertion
  pinned an exact template phrase; corrected to match the TDD contract → 3/3 (agent was sound).
- See `reports/2026-05-30-eval-coverage.md`.

### Breaking changes
- None.

### Migration
- None. Additive (fixtures + reports) + 2 verified tier downgrades. No new commands/skills.

### Known Limitations
- Behavioral coverage 10/15. Remaining: architecture-reviewer + incident-responder
  (free-form ADR/postmortem → need an LLM-judge grader, deferred); implementer (needs a live
  repo to exercise); task-orchestrator (meta); disk-monitor (already bats-tested).
- Judgment-agent tier downgrades (architect, pr-reviewer, releaser) remain recommend-only
  pending human sign-off — contract-pass ≠ quality.

### Evidence
- test_eval_fixtures covers all 10 fixtures; full suite 121 PASS both env states.
- reports/2026-05-30-eval-coverage.md (real pass-rates, N=3, tier distribution verified).
- Real CI green ubuntu+macOS before tag (rule 11).

---

## v0.5.0 — 2026-05-30

### Highlights
- **Runtime cost optimization — minimize per-invocation user cost** (the cost that matters).
- `/sdlc:cost [phase|sprint]` — zero-LLM estimate of token + USD cost at current tiers,
  per-agent breakdown, against an optional per-project `token_budget`. 21 commands now.
- `config/pricing.yaml` (dated ESTIMATE) + `config/cost-model.yaml` (per-agent tokens);
  `cost.sh` numerically tested (exact hand-verified dollar values).
- `run-eval.sh --tiers` — multi-tier compatibility matrix. Ran spec-analyst/tester/
  releaser at cheaper tiers (`reports/2026-05-30-tier-matrix.md`): **tester auto-downgraded
  sonnet→haiku** (3/3 robust, real saving); releaser sonnet 3/3 **recommend-only** (judgment,
  needs sign-off); spec-analyst sonnet **2/3 flaky → stays opus** (multi-seed caught it).
- `token_budget` / `budget_strict` config + cost-aware dispatch rule in task-orchestrator.
- **zero-LLM-first** codified as a design principle (DEVELOP) — deterministic bash costs the
  user 0 tokens (onboarding/grading/cost/audit are all zero-LLM); the strongest cost lever.

### Breaking changes
- None.

### Migration
- None. Additive. `/sdlc:onboard` re-run backfills the new `token_budget` config field
  (idempotent). Handoff schema unchanged (v1).

### Known Limitations
- Cost figures are ESTIMATES — prices drift (see `as_of`), token counts are typical-case;
  not a metered bill (CC has no per-call token hook — real metering deferred to v0.6).
- **Runtime cost posture change**: tester downgraded sonnet→haiku (eval-verified 3/3,
  mechanical agent — contract IS the quality, low risk). releaser sonnet downgrade is
  recommended but NOT applied (judgment agent — contract-pass ≠ quality, awaits sign-off).
- Tier-downgrade coverage limited to the 5 agents with fixtures; judgment agents
  (spec-analyst stays opus, releaser recommend-only) not auto-changed.
- Behavioral eval coverage remains 5/15 agents.

### Evidence
- cost.sh numerically tested (exact \$110.00/\$2.00); full suite 121 PASS both env states.
- Tier matrix: reports/2026-05-30-tier-matrix.md (real pass-rates, N=3).
- Real CI green ubuntu+macOS before tag (rule 11).

---

## v0.4.0 — 2026-05-29

### Highlights
- **Project onboarding — the North Star capability.** `/sdlc:onboard` bootstraps any
  repo in one command (detect stack, scaffold `docs/superpowers/{specs,plans,handoffs}/`
  + `reports/`, seed `.sdlc/state.json`, gitignore, config stub). Idempotent — never
  overwrites your config/state, never touches `CLAUDE.md`.
- `/sdlc:doctor` health-checks a repo's wiring (manifest / tools / git / stack /
  scaffold / state / gitignore) → READY or lists issues with fixes.
- Both are **pure deterministic bash, zero-LLM** — CI-tested like `grade.sh`, run in
  seconds, cost the adopting user **0 tokens**. 9 skills / 20 slash commands now.
- E2E acceptance: a fresh repo adopted the plugin via its own entry path, doctor
  confirmed READY (0 issues), re-onboard non-destructive (`reports/2026-05-29-onboard.md`).

### Breaking changes
- None.

### Migration
- None. Additive (2 commands + 1 skill). Existing repos can run `/sdlc:onboard` to
  backfill scaffold safely (idempotent). Handoff schema unchanged (v1).

### Known Limitations
- onboard does NOT auto-`git init` (by design — surfaces `onboard-not-git` so the
  user decides).
- LLM "guided first spec" walkthrough is deferred to v0.4.1 — v0.4.0 ships the
  deterministic scaffold only.
- Behavioral eval coverage remains 5/15 agents (v0.3.0), unchanged here.
- Runtime per-invocation cost optimization (multi-tier matrix to push agent tiers
  down + per-sprint cost estimate) is the planned v0.5 focus.

### Evidence
- onboard.sh + doctor.sh CI-tested (test_onboard.bats 7, test_doctor.bats 6); full
  suite 112 PASS both env states. Real CI green ubuntu+macOS required before tag (rule 11).
- E2E: reports/2026-05-29-onboard.md (real fresh-repo adoption, idempotency verified).

---

## v0.3.0 — 2026-05-29

### Highlights
- **Behavioral conformance eval harness** — the first time agents are validated by
  *behavior*, not just structure. `eval/run-eval.sh` dispatches each agent's real
  prompt (at its declared model_tier) on fixture inputs; `eval/grade.sh` (pure,
  CI-tested) grades the output against its contract. The grader **never reads the
  agent's self-report** — codifies the AC1/R14 lesson.
- 5 agents covered with fixtures + mechanical contracts (spec-analyst /
  dependency-auditor / tester / docs-curator / releaser), multi-seed N=3.
- `/sdlc:eval [agent|all]` — 18th command. Human-triggered (real LLM); CI runs only
  the deterministic `grade.sh` unit tests.
- **First behavioral acceptance: all 5 agents 3/3 robust** (`reports/2026-05-29-eval.md`).
  The first run found 2 *grader* bugs (case-sensitivity + an over-specified assertion),
  not agent flaws — multi-seed N=3 is what exposed them; fixed graders, re-graded → 5/5.
- Portability lint scope extended to `eval/`; structural guard now also covers the
  manifest command count.

### Breaking changes
- None.

### Migration
- None. Pure additive (new `eval/` dir + 1 command). Handoff schema unchanged (v1).

### Known Limitations
- **Coverage is 5 of 15 agents.** The other 10 are structurally validated only
  (frontmatter + rubric), NOT behaviorally verified. Free-form-output agents
  (architecture-reviewer ADRs, incident-responder postmortems) need an LLM-judge
  grader — deferred to v0.3.1.
- Grep-based assertions can false-positive/negative on keywords in unrelated context
  (E1); assertions are anchored + now case-insensitive; LLM-judge will harden further.
- Eval dispatch fidelity: in-session subagent / `claude -p` prompt-injection, not a
  native Claude Code plugin load (DP4) — contract assertions are load-path-independent.
- Multi-tier compatibility matrix (opus/sonnet/haiku per §4.5) deferred to v0.3.2.

### Evidence
- grade.sh deterministic unit tests in CI; full suite 99 PASS both env states.
- Behavioral acceptance: `reports/2026-05-29-eval.md` (real pass-rates, 5 agents, N=3).
- Real CI green on ubuntu+macOS required before tag per releaser rule 11 (this release dogfoods it).

---

## v0.2.2 — 2026-05-29

### Highlights
- **Critical structural fix: the plugin now actually loads.** A structural audit found `plugin.json` sat at the repo root, but Claude Code loads the manifest from `.claude-plugin/plugin.json` (258 of 263 installed official plugins use that path). As structured, the plugin would **never load** — all 15 agents were dead weight, and every prior "self-hosting validation" was grep-only, never an actual plugin load. `git mv` to `.claude-plugin/plugin.json`; stale description refreshed (was "9 agents, 5 skills"; now 15/8/17).
- **Postmortem debt closed** (pulled forward from v0.3.0): the v0.2.1 CI-red incident's 2 open action items are now done —
  - `agents/releaser.md` rule 11: any release touching tests/CI/scripts requires an **observed-green real CI run** (cite run id + conclusion), not a local bats count.
  - `tests/PORTABILITY.md`: banned-GNU-ism → POSIX-replacement table + test-determinism rules + foreign-env reproduction recipes.
- **Mechanical guards added** (the enforcement teeth):
  - `tests/unit/test_plugin_structure.bats`: manifest location, no stray root manifest, description-not-stale, orphan `[[refs]]`, SKILL.md presence, hook script exec.
  - `tests/unit/test_portability.bats`: GNU-ism lint (declare -A / mapfile / `${v,,}` / df -BG / date -d / realpath / import yaml), proven to catch an injected violation.

### Breaking changes
- None for users. (Manifest moved to `.claude-plugin/plugin.json` — this is the *correct* CC location; the prior root location never loaded, so no working install is affected.)

### Migration
- None. If you somehow had this installed, reinstall — the manifest is now at the location Claude Code expects.

### Known Limitations
- **Behavioral conformance of agents is still unverified** — agents are markdown prompts validated only *structurally* (frontmatter, ≥9 sections, rubric). No agent has been invoked-and-asserted against its contract (e.g. "spec-analyst actually emits 11 sections", "dependency-auditor actually blocks on a High CVE"). A behavioral eval harness is the v0.3.0 deliverable.
- Windows/WSL CI still deferred to v0.3.x.
- SE breadth agents (data-engineering / DR / api-versioning / onboarding) deferred to v0.3.x.

### Evidence
- Structure guard + lint: 86 bats PASS (was 72; +7 structure +7 portability), green under both unset and hostile `CLAUDE_PLUGIN_ROOT`.
- Real CI green required before tag per the new releaser rule 11 (this release dogfoods it).
- Postmortem updated: `docs/postmortems/2026-05-29-ci-red-dev-box-coupling.md` (all 4 action items closed).

---

## v0.2.1 — 2026-05-29

### Highlights
- **Hotfix: CI is now genuinely green on real ubuntu + macOS runners.** v0.2.0 claimed a CI matrix as a deliverable, but the first real push turned it red — exposing that the test suite was silently coupled to this dev box. Five portability bugs fixed (the local "72 PASS" had been environment-luck):
  - `test_agents_frontmatter`: `python3 import yaml` → pure `awk`+`grep` (macOS runner has no PyYAML).
  - `audit.sh`: GNU `df -BG` → POSIX `df -P -k` (BSD/macOS df rejects `-BG`).
  - `audit.sh`: a **missing `/data` mount was treated as 0 GB free** → permanent false redline that would have **blocked every build and aborted every multi-agent dispatch on any machine without `/data`** (CI, macOS, normal users). Now an absent mount is skipped.
  - `audit.sh` + `archive.sh`: GNU `date -d '+8 hours'` → portable `TZ=Asia/Shanghai`.
  - `check.sh` + 3 hooks: GNU `realpath --relative-to` / bare `realpath` → POSIX `cd && pwd -P` (BSD/macOS realpath lacks `--relative-to`; logical `pwd` kept symlinks so `/var`→`/private/var` diverged from git's physical path → wrong code branch).

### Breaking changes
- None.

### Migration
- None. Pure portability hotfix over v0.2.0.

### Known Limitations
- Windows/WSL CI still deferred to v0.3.
- SE breadth (data-engineering / DR / api-versioning / onboarding agents) still v0.3.0.

### Evidence
- Real CI green (ubuntu-latest + macos-latest): run 26621232540 @ commit 4fbd09e.
- Postmortem: `docs/postmortems/2026-05-29-ci-red-dev-box-coupling.md`
- 72 bats PASS local (both unset and hostile CLAUDE_PLUGIN_ROOT) + both CI platforms.

---

## v0.2.0 — 2026-05-29

### Highlights

- **Hardening release — no new capability** (per §7.1.2 hardening minor).
- D1: handoff-valid fixture repointed at immutable `tests/fixtures/stable-artifact.md` — README edits no longer break the validator test (fixes KL#11; root cause of two v0.1 GA hotfixes 4435c5c / 870f10c).
- D2: GitHub Actions CI matrix (ubuntu-latest + macOS-latest) running bats. Removed the only bash-4 construct (`declare -A` in test_commands.bats) → repo is now bash-3.2-safe (delivers spec §11 R7, previously claimed-but-untested).
- D2c (found during review): hook bats tests now pin `CLAUDE_PLUGIN_ROOT` → suite is deterministic (72 PASS under both unset and hostile env). v0.1's "72 PASS" was environment-luck; now robust.
- D3: self-hosting re-validated at the 15-agent scope (prior report covered only 9 agents).

### Breaking changes

- None.

### Migration

- None. v0.1.0 → v0.2.0 is a pure-improvement upgrade; handoff schema unchanged (still v1).

### Known Limitations

- Real macOS bash-3.2 run is proven only once the repo is pushed and CI fires; local floor was static bash-4 scan (clean) + ubuntu bash-5 real run (no local macOS available).
- CI does not yet cover Windows/WSL (deferred to v0.3).
- SE breadth (data-engineering / DR / api-versioning / onboarding agents, docs-curator --quality-rubric auto-lint) deferred to v0.2.1+.

### Evidence

- design reviewed @ sha 23e56d5
- self-hosting: reports/2026-05-29-self-hosting.md (15-agent scope)
- bats: 72 PASS (unit + integration), deterministic across CLAUDE_PLUGIN_ROOT, bash-3.2-safe

---

## v0.1.0 — 2026-05-29

### Highlights

**SDLC orchestration core (9 agents / 5 skills / 9 commands)**:
- 9 SDLC agents at rubric E.2 ≥ 4/5 (per spec Appendix E):
  - `spec-analyst` (opus) — 11-section spec gate
  - `architect` (opus) — G1 Challenger + plan↔spec alignment
  - `implementer` (sonnet) — TDD Red→Green→Refactor + batch task execution
  - `pr-reviewer` (sonnet) — 2-round review (§5.2) + silent-failure hunter
  - `tester` (sonnet) — 6-category test matrix + multi-seed N≥3 for LLM paths
  - `releaser` (opus) — RC 4 gates + 本机部署 verify
  - `docs-curator` (haiku) — §3.2 whitelist enforcement
  - `disk-monitor` (haiku) — §1.1.6 three-disk audit
  - `task-orchestrator` (opus) — meta-dispatcher / phase state machine / §6.2 Agent 落档强制
- `model_tier` per Appendix D.3 (opus×4 / sonnet×3 / haiku×2)
- 5 SDLC skills — `pre-create-gate` / `sprint-archival` / `disk-self-audit` / `handoff-schema` / `multi-agent-dispatch`
- 9 SDLC slash commands — `/sdlc:{spec,plan,impl,review,test,release,audit-docs,disk,status}`

**Common SE practice coverage (NEW, per spec Appendix G — 6 agents / 3 skills / 8 commands)**:
- `architecture-reviewer` (opus) — ADR + STRIDE threat model + migration strategy
- `performance-analyst` (sonnet) — SLI/SLO + multi-seed bench + 2σ regression
- `dependency-auditor` (haiku) — SBOM + CVE block + license whitelist
- `tech-debt-tracker` (haiku) — TODO/FIXME registry + sprint budget
- `incident-responder` (opus) — runbook + postmortem (CLAUDE.md §9)
- `cicd-designer` (sonnet) — CI/CD pipeline + canary/blue-green + rollback
- 3 SE skills — `threat-model-stride` / `observability-baseline` / `migration-strategy`
- 8 SE commands — `/sdlc:{adr,threat,migrate,perf,deps,debt,incident,cicd}`

**Infrastructure**:
- 3 hooks — `PostToolUse:Write` → `pre-create-gate`; `Stop` → `sprint-archival`; `PreToolUse:Bash` → `disk-self-audit`
- 5 stack adapters — rust / ts / python / go / generic with auto-detect via `config/detect-stack.sh`
- 5 templates — `spec` / `plan` / `release` / `dispatch` / `handoff`
- Hello-world Rust E2E demo + `SDLC_DEMO.md` walkthrough (386 lines)
- Self-hosting validated (plugin used to spec/plan/impl/review/test/release itself)

**Design philosophy embedded**:
- spec Appendix C (5 design layers: collaboration / process / detail / model / standards)
- spec Appendix D (model tiering matrix, decision rules, downgrade policy)
- spec Appendix E (rubrics + golden examples + `self_score` blocks)
- spec Appendix F (12 anti-pattern AC1-AC12 quick reference)
- spec Appendix G (SE practice 20-area coverage matrix; 15 built-in for v0.1)

### Breaking changes

None (initial release).

### Migration

Not applicable (initial release).

### Known Limitations

Core SDLC limits:
1. Stack auto-detect supports Rust / TS / Python / Go / generic; Flutter / Swift / Kotlin require manual `stack:` override in `.claude/sdlc-orchestrator.local.md`.
2. `multi-agent-dispatch` parallelism caps at `max_parallel=2` by default; raising via env var is unvalidated for disk pressure beyond 4 workers.
3. `sprint-archival` deletes plan files unconditionally on Stop; if a session is interrupted mid-sprint without commit, the plan is still removed (recover via `git reflog`).
4. `pre-create-gate` whitelist is hardcoded in `skills/pre-create-gate/check.sh`; per-project override deferred to v0.2.
5. `handoff-schema` v1 has no migration path declared; bump to v2 in v0.2 will require dual-support window.
6. Plugin marketplace install (`/plugin install`) is not live; v0.1 requires git clone + manual symlink.
7. CI pipeline (GitHub Actions) for plugin self-tests is planned for v0.2.
8. Bats integration tests require `bats ≥ 1.7` with `bats-support` / `bats-assert` vendored; not auto-installed.
9. `task-orchestrator` phase state machine is single-session only; no persistence across Claude Code restarts.
10. `disk-self-audit` reads `df -h` for `/`, `/data`, `/tmp` only; custom mount points not auto-detected.
11. `valid-handoff` fixture pins README.md blob sha; every README edit requires a fixture sha refresh (will be addressed in v0.2 by switching to a stable fixture artifact).

SE-practice limits (v0.1 expansion):

12. **SE coverage** — 5 of 20 SE areas NOT in v0.1 (data engineering / DR / i18n / compliance / a11y) — deferred to v0.2 (a11y, data-eng, i18n) and v0.3 (DR, compliance) per Appendix G.1.
13. `architecture-reviewer` exposes 3 modes (ADR / threat / migrate) via separate commands; no fused workflow yet.
14. `dependency-auditor` stack tool detection covers 4 stack natives (cargo / npm / pip / go); other stacks fall back to manual SBOM input.
15. `performance-analyst` bench tool installation is NOT auto (criterion / locust / k6 / wrk must be pre-installed on the host).
16. `incident-responder` 24h SLA tracking is advisory only (no actual paging integration; PagerDuty / Opsgenie webhooks deferred).
17. `cicd-designer` template emission per platform (GHA / GitLab / Jenkins) — Jenkins template is basic / declarative-only.
18. `observability-baseline` alert routing (PagerDuty / Slack) referenced but template-only; actual integration is manual.
19. `threat-model-stride` DFD diagramming is ASCII only; image-based DFD support is planned for v0.2.

### Evidence

- design spec @ sha 4059470 (1342 lines, archived after implementation)
- self-hosting: `reports/2026-05-29-self-hosting.md` @ sha 6577b5f
- bats tests: 72 PASS (61 unit + 11 integration)
- Total commits at GA: 51
- Total agent lines: 6234 (15 agents)
- Total skill lines: 466 (8 skill SKILL.md entrypoints)
- Total tracked files: 96

### Verification commands

```bash
git clone https://github.com/your-org/sdlc-orchestrator ~/.claude/plugins/sdlc-orchestrator
cd ~/.claude/plugins/sdlc-orchestrator
./tests/run-all.sh        # expect 72 PASS / 0 FAIL
# Restart Claude Code, then:
/sdlc:status              # plugin loaded + stack detected
/sdlc:spec hello-world    # start an SDLC cycle
```

## Sprint 2026-05-28-sdlc-orchestrator — archived 2026-05-29

## Sprint 2026-05-29-hardening — archived 2026-05-29
