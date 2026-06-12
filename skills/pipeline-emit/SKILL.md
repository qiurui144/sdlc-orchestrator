---
name: pipeline-emit
description: Use to generate a concrete, stack-accurate CI pipeline yaml whose build/lint/test commands come VERBATIM from config/stack-*.yaml (deterministic, zero-LLM). Emits the 5 mandatory stages (build/lint/test/security_scan/publish) with secret placeholders only (never plaintext). Complements cicd-designer, which adds the LLM design layer (CD strategy by tier, rollback runbook, platform reasoning).
---

# pipeline-emit

Deterministic CI-yaml core. cicd-designer (LLM) DESIGNS pipelines but its commands can drift
from `config/stack-*.yaml`; this skill emits the yaml with commands taken **verbatim** from the
stack config — reproducible and testable.

## Contract

```
emit.sh --stack <name> [--platform github|generic] [--out <file>]
```

- Reads `config/stack-<name>.yaml` (`SDLC_CONFIG_DIR` override); unknown stack → `stack-generic.yaml`.
- 5 mandatory stages build/lint/test/security_scan/publish (self-check refuses if any missing).
- scanner map: rust→cargo audit, ts→npm audit, python→pip-audit, go→govulncheck, *→placeholder.
- Commands emitted in YAML **block scalars** (`run: |`) so embedded quotes in a config command
  cannot malform the yaml (the output always parses).
- Secrets: `${{ secrets.NAME }}` (github) / `$ENV` (generic) placeholders — **never plaintext (§1.4)**.
- `--out` writes the file (mkdir -p parent); else stdout. `^[a-z0-9-]+$` stack validation (anti-traversal).

## vs cicd-designer — when to use which

- **pipeline-emit** (this) → the deterministic CI core (build→publish, stack-accurate). Use for a
  reproducible CI yaml fast; commands stay correct as `config/stack-*.yaml` evolves.
- **cicd-designer** (`/sdlc:cicd`) → the LLM design layer: CD strategy (canary/blue-green by tier),
  `docs/rollback-runbook.md`, platform selection. It can build ON this CI core.

## Linked

- command `/sdlc:pipeline`; agent [[cicd-designer]]
- `config/stack-*.yaml` + `config/detect-stack.sh` (read-only reuse)
