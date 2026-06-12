#!/usr/bin/env bash
# Hook: PostToolUse Write. Defers to pre-create-gate skill for doc discipline.
# Exit codes: 0=allow, 1=warn(non-blocking), 2=block
set -euo pipefail

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // ""')

if [ "$tool" != "Write" ]; then
  exit 0
fi

path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
if [ -z "$path" ]; then
  exit 0
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
"$PLUGIN_ROOT/skills/pre-create-gate/check.sh" "$path"
exit $?
