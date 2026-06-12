---
name: pre-create-gate
description: Use BEFORE any Write of .md / scripts/* / config / new file. Enforces CLAUDE.md §1.1.7 three questions (duplicate / lifecycle / whitelist). Returns exit 2 to block, exit 1 to warn, exit 0 to allow.
---

# pre-create-gate

## When to use

Before EVERY Write tool call that creates a NEW file (modifying existing is fine).
Especially:
- New `.md` in repo (white-list enforce)
- New `scripts/<name>.sh` (consolidate vs proliferate)
- New `config/<name>.yaml` (likely user override path)

## What it does

Three checks (per CLAUDE.md §1.1.7):

1. **Duplicate check** — grep repo for the topic; if same-topic file exists, REJECT (extend existing).
2. **Lifecycle check** — file looks like one-shot artifact (`*-tasks.md`, `*-report.md`, `v*-release-notes.md`)? REJECT (write to PR / RELEASE / reports/).
3. **Whitelist check** — file location + name match §1.1.2 / §3.2 whitelist? If not, REJECT.

## Steps

1. Receive proposed file path
2. Run `${CLAUDE_PLUGIN_ROOT}/skills/pre-create-gate/check.sh <proposed-path>`
3. Interpret exit code: 0 = allow; 1 = warn (proceed but log); 2 = BLOCK (do not create)

## Strict vs warn mode (per spec §6.6 config override)

Default: warn (exit 1) for soft violations, block (exit 2) for hard violations.
Strict mode (config flag `pre_create_gate_strict: true`): all violations → block.

## Linked
- spec §1.1.7 / §3.2
- skill [[handoff-schema]]
- hook `PostToolUse:Write` invokes this
