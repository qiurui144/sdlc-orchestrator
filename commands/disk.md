---
description: 3-mount disk audit (/ /tmp /data) per §1.1.6. Dispatches disk-monitor (haiku) for action-oriented remediation.
allowed-tools: [Read, Bash, Agent, Skill]
---

# /sdlc:disk

Invokes the **disk-monitor** agent (haiku). Wraps `disk-self-audit` skill. Identifies bloat by mount and category (cargo target / node_modules / /tmp leftovers / docker images). Suggests targeted cleanup with explicit paths. Never auto-cleans without user confirmation.

## Behavior

1. Run `skills/disk-self-audit/audit.sh --strict`.
2. If exit 0 (healthy): log + return.
3. If exit 2 (redline): sub-checks per category; print prioritized cleanup commands; ask user "apply? (y/n/list-only)".
4. After cleanup: re-audit. If still red → escalate to human.
5. Append `.sdlc/disk-audit.log` rolling 7d.
