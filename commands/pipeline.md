---
description: Emit a deterministic, stack-accurate CI pipeline yaml (commands verbatim from config/stack-*.yaml; 5 mandatory stages; secret placeholders). Complements /sdlc:cicd (CD strategy + rollback).
argument-hint: "[--platform github|generic] [--out <file>]"
allowed-tools: [Read, Bash, Glob, Skill]
---

# /sdlc:pipeline

Generates a reproducible CI yaml via the [[pipeline-emit]] skill — build/lint/test commands taken
verbatim from `config/stack-*.yaml`, plus security_scan + publish, with secret placeholders only.

## Behavior

1. Detect the stack: `bash config/detect-stack.sh` (rust | ts | python | go | generic).
2. `bash skills/pipeline-emit/emit.sh --stack <detected> --platform github --out .github/workflows/sdlc-ci.yml`
   (use `--platform generic` for non-GitHub CI; omit `--out` to preview on stdout).
3. Report the emitted path + the 5 stages.
4. For CD strategy (canary/blue-green) + `docs/rollback-runbook.md`, run `/sdlc:cicd` (cicd-designer) —
   it layers the deploy/rollback design on top of this CI core.

## Constraints

- **Never inline plaintext secrets** — only `${{ secrets.NAME }}` / `$ENV` placeholders (§1.4).
- Commands come from the stack-config SSOT (not hand-written), so they stay accurate as the config evolves.
- Production deploy must use canary/blue-green (not rolling) — that gate lives in `/sdlc:cicd`.
