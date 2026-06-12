#!/usr/bin/env bash
set -euo pipefail

MAX="${SDLC_MAX_PARALLEL:-2}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=skills/multi-agent-dispatch/counter.sh
. "$HERE/counter.sh"

audit_output=$("$HERE/../disk-self-audit/audit.sh" --strict 2>&1) && audit_rc=0 || audit_rc=$?

# v0.9: in-flight aware gate. avail = cap - in_flight.
INFLIGHT=$(counter_inflight 2>/dev/null || echo 0)
AVAIL=$(( MAX - INFLIGHT ))
if [ "$AVAIL" -lt 0 ]; then AVAIL=0; fi

echo "max_parallel=$MAX"
echo "in_flight=$INFLIGHT"
echo "avail=$AVAIL"
echo "$audit_output"

# disk redline takes precedence (hard abort, never relaxed per §1.1.6)
if [ "$audit_rc" -eq 2 ]; then
  echo ""
  echo "abort: cannot dispatch multi-agent (disk-redline hit)" >&2
  exit 2
fi

# no free slot → caller should wait (set -e safe: use if, not `cond && exit`)
if [ "$AVAIL" -le 0 ]; then
  echo "wait: no free slot (in_flight=$INFLIGHT, cap=$MAX)" >&2
  exit 1
fi

exit 0
