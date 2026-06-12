# ADR 0001 — Orchestration core vs. re-implemented SE audits

- **Status**: Accepted
- **Date**: 2026-06-03
- **Deciders**: qiurui144 (with an independent competitive analysis, 2026-06-03)
- **Context tag**: SE1 (architectural decision recorded before it ossifies)

## Context

An independent competitive review (vs. the Claude-native plugin ecosystem) found that
sdlc-orchestrator's defensible edge is narrow but real — a **stateful, SHA-gated cross-phase
state machine + a risk-tiered Challenger consensus gate** — while a chunk of its surface
(17 agents / 25 commands) **re-implements capabilities that native plugins already ship**,
notably `engineering-advanced-skills` (`dependency-auditor`, `tech-debt-tracker`,
`ci-cd-pipeline-builder`, `performance-profiler` / `slo-architect`, `migration-architect`,
`runbook-generator`) and `engineering-skills` (`incident-response`, `senior-architect`).

The question this ADR settles: **should the overlapping SE-audit agents be deleted and the
`/sdlc:*` commands delegate to the native skills instead, to shrink surface and stop
"reinventing"?**

## Decision

**Keep the SE-audit agents. Do NOT hard-depend on native plugins. Require each SE-audit agent
to earn its keep via a concrete, gate-consumable enforcement specific** (else it is reinvention
and should be cut). Thin only the one genuine pure-overlap boundary (see below).

Two load-bearing reasons:

1. **Self-containment is a hard constraint of being a standalone plugin.** A Claude Code plugin
   cannot assume another *separate* plugin (`engineering-advanced-skills`) is installed. Deleting
   `/sdlc:deps` and delegating to native would make sdlc-orchestrator silently break — or silently
   no-op — on any machine without that plugin. Self-containment > surface-area minimalism.

2. **The value is the enforcement/integration layer, not the raw capability.** Each SE-audit
   agent emits a **PASS/BLOCK verdict the gate consumes** and is dispatchable inside `/sdlc:intake`
   and `/sdlc:run` with the handoff schema + `model_tier`. Native skills are standalone advisors;
   they do not feed a gated state machine. The overlap is in *capability*, not in *role*.

### Per-component verdict (the "earns its keep" audit)

| Component | Native overlap | Enforcement specific that justifies keeping | Verdict |
|-----------|----------------|---------------------------------------------|---------|
| `dependency-auditor` (`/sdlc:deps`) | dependency-auditor | `config/license-allow.yaml` whitelist + CVE≥High **BLOCK** + SBOM → intake scorecard | **Keep** |
| `tech-debt-tracker` (`/sdlc:debt`) | tech-debt-tracker | enforces marker **format** `TODO(@owner, date)` + blocks untagged + `docs/tech-debt.md` SSOT (SE4) | **Keep** |
| `performance-analyst` (`/sdlc:perf`) | performance-profiler / slo-architect | **2σ regression rule + multi-seed N=3** + SLI/SLO baseline (SE3/SE11, §2.3/§6.3) | **Keep** |
| `threat-model-stride` (`/sdlc:threat`) | (none precise) | **6-letter STRIDE completeness** gate (SE2) | **Keep** |
| `architecture-reviewer` ADR mode (`/sdlc:adr`) | senior-architect | enforces **ADR-before-component** (SE1) — this file is the proof | **Keep** |
| `architecture-reviewer` migration mode (`/sdlc:migrate`) | migration-architect | mandatory **reversibility analysis** + pattern selection (SE9) | **Keep** |
| `incident-responder` (`/sdlc:incident`) | incident-response, runbook-generator | **5-Why-past-code** + 7-section postmortem + action-item owner+deadline (SE8, §9.3) | **Keep** |
| `cicd-designer` (`/sdlc:cicd`) | ci-cd-pipeline-builder | canary/blue-green **CD strategy + rollback runbook** (SE7) | **Keep, thinned** |
| `pipeline-emit` (`/sdlc:pipeline`) | ci-cd-pipeline-builder | **zero-LLM deterministic** stack-config yaml (5 stages, secret placeholders) | **Keep** |

**The one real thinning**: `cicd-designer` and `pipeline-emit` both touched "emit CI yaml".
`/sdlc:pipeline` (deterministic, zero-LLM, commands verbatim from `config/stack-*.yaml`) owns yaml
emission; `cicd-designer` is scoped to what it *uniquely* adds — CD strategy (canary/blue-green) +
rollback runbook + the gate verdict. This boundary already shipped in v0.16; this ADR ratifies it
as the rule rather than an accident.

## Consequences

- **Positive**: the plugin stays installable and correct standalone; every SE-audit agent now has a
  documented reason to exist (a gate-consumable enforcement specific); "are we just reinventing?"
  has a written answer instead of recurring every review.
- **Negative (accepted)**: capability overlap with native plugins persists, and we carry the
  maintenance of 4 stack adapters + these agents. This is the *price of self-containment*, recorded
  here so it is a chosen cost, not drift.
- **Guardrail (new rule)**: any *future* SE-audit agent must cite a concrete enforcement specific in
  its frontmatter/Purpose. An agent that only restates a native skill's advice — with no PASS/BLOCK
  verdict and no gate role — is reinvention and must be cut, not merged.

## Alternatives considered

- **Delete + delegate to native** — *rejected*: breaks self-containment (can't assume
  `engineering-advanced-skills` is installed); would convert a hard guarantee into a soft,
  environment-dependent one.
- **Optional soft-delegation** (use native if present, fall back to own) — *deferred*: adds
  detection complexity + two code paths to test for marginal surface reduction; revisit only if a
  native dependency becomes a documented prerequisite.
- **Do nothing / leave undocumented** — *rejected*: the overlap kept resurfacing in reviews; SE1
  requires the decision be written down.
