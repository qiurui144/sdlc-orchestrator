---
name: ci-status
description: Use to get a deterministic GitHub CI verdict for a ref (PASS/FAIL/IN_PROGRESS/UNKNOWN/NONE) via gh+jq (zero-LLM, SDLC_GH_BIN-mockable), and to GATE auto-remediation commits with diff-guard.sh — a zero-LLM audit of `git diff --cached` that REJECTs any diff touching a test path, adding skip/ignore markers, net-removing assertions, editing .github/workflows/*, or exceeding a fix class's footprint. Consumed by releaser (RC gate), pr-reviewer, and /sdlc:promote with path-asymmetric strictness (--require-known default on irreversible tag/promote → UNKNOWN blocks).
---

# ci-status

Two zero-LLM scripts that make "CI is green" enforceable and make "never weaken a test" a mechanism.

## ci-status.sh — deterministic verdict
```
ci-status.sh [--ref <sha|branch>] [--pr <num>] [--require-known] [--allow-unknown] [--json]
```
Exit: 0 PASS · 1 FAIL · 3 IN_PROGRESS · 4 UNKNOWN · 5 NONE · 2 usage. `GH="${SDLC_GH_BIN:-gh}"` injection.
UNKNOWN policy is path-asymmetric (B3): reversible (pr-reviewer/dev) = WARN; irreversible (releaser RC gate / `/sdlc:promote` / tag) runs `--require-known` by default → UNKNOWN = BLOCK. NONE = skip (no CI ≠ red).

## diff-guard.sh — B1 safety core (zero-LLM)
```
diff-guard.sh --class <A1|A2|A3|A4>
```
Run AFTER an auto-fix stages changes, BEFORE the remediation commit. Exit 1 → caller `git reset --hard` + ESCALATE. Rejects: test-path touch · skip/ignore add · net-assert-down · `.github/workflows/*` · class-footprint overrun (A3 = deny.toml `[licenses].allow` only). Audits the actual staged diff, not the LLM's proposed_fix string.

## Mocking (tests, no real GitHub)
`SDLC_GH_BIN=tests/fixtures/gh-stub.sh` serves `run list` / `pr checks` / `run view --log-failed` fixtures offline (Hard constraint #4).
