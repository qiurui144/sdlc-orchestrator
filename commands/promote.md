---
description: Promote develop to main (#14) — assert the main-bound commit's CI is green (require-known, UNKNOWN blocks) and already tagged, then --no-ff merge. Reuses ci-status.sh as the single SSOT (inline-releaser scope, no separate promoter agent).
argument-hint: [--allow-unknown]
allowed-tools: [Read, Glob, Grep, Bash]
---

# /sdlc:promote — develop to main with a CI-green hard gate (#14, B3)

Before any develop to main promotion, assert the main-bound commit is **CI green** and
**already tagged**. Reuses `skills/ci-status/ci-status.sh` (no separate promoter agent this
version — R13 inline-releaser SSOT: the same verdict primitive the releaser RC gate uses).

This is the **irreversible path** (main is the published line), so the CI gate runs
`ci-status.sh --require-known` by default: an UNKNOWN verdict (gh-EOF / API unreachable)
BLOCKs rather than promoting an unverifiable commit. This mirrors the releaser tag gate and is the
opposite of the pr-reviewer's reversible WARN-default.

## Steps

1. Resolve the main-bound commit (develop HEAD):
   ```bash
   REF=$(git rev-parse develop)
   ```

2. **CI-green hard gate (irreversible — `--require-known` default, B3):**
   ```bash
   bash skills/ci-status/ci-status.sh --ref "$REF" --require-known --json
   ```
   - PASS (exit 0) → continue.
   - FAIL (exit 1) → ABORT promote; print the failing run url;
     "fix it, or run /sdlc:impl auto-remediation (ci-remediator), then re-promote".
   - UNKNOWN (exit 4) → ABORT (do not promote an unverifiable commit to main); retry, or
     pass `--allow-unknown` (or `SDLC_CI_LAX=1`) only after a documented manual CI confirmation.
   - IN_PROGRESS (exit 3) → wait/poll; do not promote while CI is still running.
   - NONE (exit 5) → no CI configured for the ref → skip the gate (no CI is not red).

3. **Tagged assertion (#14 — main only takes tagged commits):**
   ```bash
   git describe --exact-match --tags "$REF" >/dev/null 2>&1 \
     || { echo "promote: commit not tagged — tag via /sdlc:release first"; exit 1; }
   ```

4. **`--no-ff` merge develop into main** (leaves a merge anchor per §4.2.4 #14), then push.
   ```bash
   git checkout main && git merge --no-ff "$REF" && git push origin main
   ```

## Out of scope

- Does NOT emit or edit CI yaml (that is the pipeline-emit / /sdlc:pipeline boundary).
- Does NOT run the GA tag itself (that is /sdlc:release + the ga-tag-guard hard stop).
- Does NOT auto-remediate a red CI (it ABORTs and points at /sdlc:impl → ci-remediator).
