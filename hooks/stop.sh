#!/usr/bin/env bash
# Hook: Stop. Runs disk-self-audit + checks for sprint completion → archival suggestion.
# Never blocks the Stop event (always exit 0).
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# Always run disk audit on Stop (warn-level, never block Stop)
"$PLUGIN_ROOT/skills/disk-self-audit/audit.sh" || true

# Periodic value-based scratch reclaim (the 253G-incident prevention). VALUE-based (stale beyond
# retention, not an active worktree) — NOT fullness-gated. Opt-in auto-apply keeps the Stop fast by
# default; never blocks Stop.
if [ "${SDLC_SCRATCH_AUTORECLAIM:-0}" = "1" ]; then
  echo "[scratch] auto-reclaim (SDLC_SCRATCH_AUTORECLAIM=1):"
  "$PLUGIN_ROOT/skills/disk-self-audit/audit.sh" --reclaim --apply || true
else
  echo "[scratch] periodic reclaim: bash skills/disk-self-audit/audit.sh --reclaim [--apply] (value-based; SDLC_SCRATCH_AUTORECLAIM=1 to auto-apply on Stop)"
fi

# Check sprint state for sprint-archival suggestion
state_file=".sdlc/state.json"
if [ -f "$state_file" ]; then
  state=$(jq -r '.phase // ""' "$state_file" 2>/dev/null || echo "")
  if [ "$state" = "GA_TAG" ]; then
    sprint_id=$(jq -r '.sprint_id' "$state_file")
    echo "Sprint $sprint_id reached GA_TAG. Recommend: /sdlc:audit-docs --archive-sprint $sprint_id"
    # Note: sprint-archival is NOT auto-applied on Stop — user must confirm.
    # The sprint-archival skill is invoked explicitly by /sdlc:release after user confirmation.
    echo "To archive: invoke skills/sprint-archival/run.sh $sprint_id"
  fi
fi

exit 0
