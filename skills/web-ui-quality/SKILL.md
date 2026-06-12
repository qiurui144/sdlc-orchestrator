---
name: web-ui-quality
description: Deterministic web-UI quality gates (a11y WCAG 2.1 AA, visual regression, responsive, Lighthouse Core Web Vitals) layered on a page that already passes web-ui-verify (UI-1). Use after a render passes to grade quality. Each gate is a deterministic verdict; the visual gate consumes ui-vision-judge as an advisory annotation only — vision never decides. Triggers on /sdlc:web-ui-quality.
---

# web-ui-quality

UI-1 (`web-ui-verify`) answers *did the page render?*. `web-ui-quality` answers *is the rendered page
good?* — four deterministic gates on top of a UI-1-PASS page:

| Gate | Measures | Source (real Chrome via chrome-devtools-mcp) | FAIL exit |
|------|----------|----------------------------------------------|-----------|
| a11y | WCAG 2.1 AA violation count (all severities) | `lighthouse_audit` accessibility category (contrast/name/role from rendered styles) | 8 |
| visual | global diff-ratio AND max contiguous changed-region px vs baseline | screenshot vs `tests/screenshots/<route>/baselines/` | 9 |
| responsive | no horizontal overflow + key element bbox in viewport, per width | `resize_page` + `evaluate_script` (scrollWidth, getBoundingClientRect) | 10 |
| perf | {LCP,CLS,TBT} N≥3 **mean** vs SLO budget | `performance_start_trace`/`stop_trace` | 11 |

## Deterministic-verdict-supremacy (load-bearing, both directions)

Every gate's PASS/FAIL is a deterministic threshold/count/range check (float math via `awk`). The visual
gate consumes **ui-vision-judge** ONLY as an ADVISORY annotation (it classifies a changed region's reason
`intentional`/`regression` for the human-facing message, identical to v0.29's `vision_annotation` channel)
— it is **NEVER read into the verdict in either direction** (cannot flip FAIL→PASS, and is not needed to
FAIL). The judge schema has no verdict/pass field, so the gate structurally cannot read a decision from it.
All visual noise-suppression is DETERMINISTIC (a per-baseline `ignore_regions` mask + a `diff_ratio_max`
tolerance), never vision.

## Contract — `quality:` block in `<repo>/web-ui-verify.yaml`

```yaml
quality:
  a11y:       { standard: "WCAG21AA", max_violations: 0 }       # all severities; min_severity optional
  visual:     { baseline_dir: "tests/screenshots", diff_ratio_max: 0.02, max_region_px: 2500, ignore_regions: [] }
  responsive: { viewports: [375, 768, 1280] }
  perf:       { slo: { lcp_ms: 2500, cls: 0.1, tbt_ms: 200 }, seeds: 3, max_rel_sigma: 0.25 }
```
A gate absent from `quality:` is disabled. A trivial config (vacuous threshold) ⇒ exit 7 (fail-closed).

## Degrade & precondition

- UI-1 verdict ≠ PASS for the route ⇒ quality SKIP (don't grade a non-rendered page).
- A gate's tool absent (lighthouse/trace/MCP) ⇒ that gate `UI-UNVERIFIED` (WARN, exit 0), never a false PASS.
- **Visual baseline:** established only with `--write-baseline`; a normal run with a missing baseline ⇒
  exit 7 (never auto-write — which would launder a first-run regression — and never a silent WARN).
- **Perf noise:** the gate FAILs on the N≥3 **mean** vs SLO (NOT a σ-widened band). If `σ/mean >
  max_rel_sigma` the runs are too noisy ⇒ `UI-UNVERIFIED` (re-run). K consecutive UI-UNVERIFIED perf runs
  should be surfaced to the release gate — a perpetually-noisy gate is loudly degraded, not silently off.

## a11y coverage honesty

The a11y gate sources violations from Lighthouse's accessibility category (axe-core under the hood), which
computes contrast and name/role/structure from rendered styles. Lighthouse a11y is NOT a complete AA audit
— some criteria (keyboard traps, certain 1.4.x, focus order) are manual; treat a PASS as "no automated AA
violation", not "fully AA-conformant".

## Honesty (§7.3)

The real chrome-devtools-mcp reads (lighthouse audit, performance trace, resize + evaluate_script,
screenshot) are **PENDING-VERIFY** — the deterministic gate logic (count/ratio/region/mean/σ thresholds,
fail-closed, supremacy) is fully bats-covered behind the `SDLC_*`/`--stub` seam (zero network). The visual
gate's provider key (for the advisory vision annotation) is env-only and redacted (§1.4).
