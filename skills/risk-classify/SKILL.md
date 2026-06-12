---
name: risk-classify
description: Deterministic zero-LLM change-risk classifier. Given a staged change (git diff name-status), emits exactly one RISK TIER (LOW/NORMAL/HIGH) that selects path depth (fast vs full spec to test), Challenger panel size, and model tier. Default-deny — LOW is non-executable content ONLY (.md prose / .txt / LICENSE); any source/test/config/auth/migration/CI path becomes NORMAL/HIGH. The B-keystone of accurate-fast orchestration (v0.28.0). Triggers on /sdlc run path-depth selection.
---

# risk-classify

Deterministic, zero-LLM tier classifier — the trust core of risk-gated adaptive rigor (v0.28.0).
**NEVER an LLM judgment call.** Full rigor is the default; the LOW fast-path is the earned exception,
granted ONLY on a provably-safe non-executable change. A misclassification costs *time*, never *safety*.

## Tiers
- **LOW** → fast-path (impl+review only; the deterministic net still runs in full) + panel 3 + mechanical model tier. Non-executable content ONLY.
- **NORMAL** → full spec→plan→impl→review→test + panel 3 + per-agent tier. Any source/test/command-bearing config.
- **HIGH** → full path + panel 5 + judgment (human-signed) tier. auth/secret/migration/CI/irreversible + self-referential.

## Usage
```bash
risk-classify.sh [--staged | --diff <file> | --names <file>] [--rules <yaml>] [--verbose]
# stdout: risk_tier=… reason=… path_depth=… panel_size=… model_class=…
# exit 0 = classified (any tier) · 2 = bad-arg/unusable input → caller treats as HIGH
```

## Safety architecture (the 5 G1 fixes)
1. LOW = positive basename allowlist only (no dir-prefix, no exclusion clause).
2. STEP-0 self-guard: any edit to risk-classify/dispatch-prompt, `config/risk-rules.yaml`, `config/context-map.yaml`, or this feature's spec → HIGH (cannot rewrite its own policy on the fast-path).
3. STEP-3a .md fence guard is an allowlist: ANY fenced code block in a .md diff → NORMAL.
4. Path detection scans the RAW `git diff --name-status` — NOT panel.sh's comment-stripped view.
5. Command/behavior-bearing config (`config/*.yaml`, `.yml/.toml/.json/.sh/Makefile`) → NORMAL min, value-only counts.

## Consumers
- **task-orchestrator** — consults the tier for path depth + panel size + model class (`/sdlc:run`).
- **commands/run.md** — `--full` forces full rigor (always wins); `--fast` is advisory (can never demote NORMAL/HIGH).

## Boundaries (honest)
- The evasion suite is a denylist — it blocks the enumerated vectors + structurally bars executable
  files from LOW, but cannot PROVE no un-enumerated evasion exists (spec RES1). Standing adversarial-review item.
- Deterministic by mandate: same diff ⇒ same tier (N=20 byte-identical, LC_ALL=C). An LLM classifier is forbidden.
