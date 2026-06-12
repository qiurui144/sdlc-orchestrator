#!/usr/bin/env bats
# Portability lint. Converts the v0.2.1 CI-red postmortem lesson into a mechanical
# guard: the dev box ran GNU coreutils + bash 5 + PyYAML, so GNU-only / bash-4-only
# constructs passed locally yet crashed on the macOS CI runner. This test greps all
# shell + bats sources for banned constructs and fails if any reappear.
#
# Comment lines (^[[:space:]]*#) are excluded so the codebase can *document* why a
# construct was removed without tripping its own lint.

ROOT="$BATS_TEST_DIRNAME/../.."

# Scan executable (non-comment) lines of every .sh and .bats under the source dirs.
# Usage: scan_for <ERE-pattern>  → prints offending "file:line: text", empty if clean.
scan_for() {
  local pat="$1" f
  # Exclude this lint file itself — it necessarily contains every banned pattern
  # as the search strings, which would otherwise self-trip (a linter shouldn't
  # lint its own rule definitions).
  for f in $(find "$ROOT/skills" "$ROOT/hooks" "$ROOT/config" "$ROOT/tests" "$ROOT/eval" \
               -type f \( -name '*.sh' -o -name '*.bats' \) \
               -not -name 'test_portability.bats' 2>/dev/null); do
    # strip comment-only lines, then grep with line numbers against the original
    grep -nE "$pat" "$f" 2>/dev/null | grep -vE ':[[:space:]]*#' || true
  done
}

@test "no bash-4 associative arrays (declare -A) — breaks macOS bash 3.2" {
  hits=$(scan_for 'declare -A')
  [ -z "$hits" ] || { echo "$hits" >&2; return 1; }
}

@test "no bash-4 mapfile/readarray — breaks macOS bash 3.2" {
  hits=$(scan_for '\b(mapfile|readarray)\b')
  [ -z "$hits" ] || { echo "$hits" >&2; return 1; }
}

@test "no bash-4 case-conversion expansion (\${v,,} / \${v^^})" {
  hits=$(scan_for '\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)')
  [ -z "$hits" ] || { echo "$hits" >&2; return 1; }
}

@test "no GNU df block-size flag (df -BG / -B) — BSD/macOS df rejects it" {
  hits=$(scan_for 'df .*-B')
  [ -z "$hits" ] || { echo "$hits" >&2; return 1; }
}

@test "no GNU date -d / date -u -d — BSD/macOS date rejects it" {
  hits=$(scan_for 'date .*-d ')
  [ -z "$hits" ] || { echo "$hits" >&2; return 1; }
}

@test "no realpath — BSD/macOS lacks --relative-to; use cd && pwd -P" {
  hits=$(scan_for '\brealpath\b')
  [ -z "$hits" ] || { echo "$hits" >&2; return 1; }
}

@test "no python yaml dependency in tests — macOS runner has no PyYAML" {
  hits=$(scan_for 'import yaml')
  [ -z "$hits" ] || { echo "$hits" >&2; return 1; }
}
