#!/usr/bin/env bash
# Hook: PreToolUse Bash. Disk audit before any build/test command (per §1.1.6).
# Exit codes: 0=allow, 2=block(disk redline)
set -euo pipefail

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // ""')

[ "$tool" = "Bash" ] || exit 0

cmd=$(echo "$input" | jq -r '.tool_input.command // ""')

# Match build-ish commands that consume significant disk
if echo "$cmd" | grep -qE '\b(cargo build|cargo test|npm run build|npm test|pnpm build|pnpm test|go build|go test|pytest|python -m build|tsc|webpack|vite build)\b'; then
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
  "$PLUGIN_ROOT/skills/disk-self-audit/audit.sh" --strict
  exit $?
fi

exit 0
