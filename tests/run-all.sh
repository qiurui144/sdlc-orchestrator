#!/usr/bin/env bash
# CI + local test entrypoint. Runs the ENTIRE bats suite recursively so root-level files
# (ci-status.bats, *-evasion.bats) and tests/unit + tests/integration are all covered — a
# non-recursive `bats tests/unit/` silently skipped the root-level security/evasion suites.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
echo "=== Full test suite (recursive) ==="
bats -r tests/
