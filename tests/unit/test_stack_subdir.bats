#!/usr/bin/env bats
# bug1 (dogfood 2026-06-05): detect-stack must DESCEND one level when the build
# module lives in a subdir (e.g. KVM's Go module in go/) instead of silently
# returning "generic" — which made /sdlc:test run bats, not go test (silent pass).
# It must also expose the module subdir (--module-dir) so onboard can emit
# `cd <dir> && ...` commands.

ROOT="$BATS_TEST_DIRNAME/../.."
DETECT="$ROOT/config/detect-stack.sh"

@test "subdir: detect go when go.mod is in a go/ subdir (root bare)" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  mkdir -p "$tmp/go"; touch "$tmp/go/go.mod"
  run "$DETECT" "$tmp"
  [ "$status" -eq 0 ]
  [ "$output" = "go" ]
}

@test "subdir: --module-dir echoes the subdir for a subdir module" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  mkdir -p "$tmp/go"; touch "$tmp/go/go.mod"
  run "$DETECT" --module-dir "$tmp"
  [ "$status" -eq 0 ]
  [ "$output" = "go" ]
}

@test "root marker: --module-dir echoes . (do not descend when root has a marker)" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  touch "$tmp/go.mod"
  run "$DETECT" --module-dir "$tmp"
  [ "$output" = "." ]
}

@test "subdir polyglot: prefers go/ over web(ts)/privacy(rust) by name preference" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  mkdir -p "$tmp/go" "$tmp/web" "$tmp/privacy"
  touch "$tmp/go/go.mod"; echo '{}' > "$tmp/web/package.json"; touch "$tmp/privacy/Cargo.toml"
  run "$DETECT" "$tmp"
  [ "$output" = "go" ]
  run "$DETECT" --module-dir "$tmp"
  [ "$output" = "go" ]
}

@test "subdir: name preference (backend/) beats an alphabetically-earlier subdir (aaa/)" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  mkdir -p "$tmp/aaa" "$tmp/backend"
  echo '{}' > "$tmp/aaa/package.json"; touch "$tmp/backend/go.mod"
  run "$DETECT" "$tmp"
  [ "$output" = "go" ]   # backend/ preferred over alphabetically-first aaa/
}

@test "still generic when no marker at root or in any subdir" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  mkdir -p "$tmp/docs" "$tmp/sub"; touch "$tmp/sub/README.md"
  run "$DETECT" "$tmp"
  [ "$output" = "generic" ]
  run "$DETECT" --module-dir "$tmp"
  [ "$output" = "." ]
}

@test "root marker still wins over a subdir module (back-compat, no descent)" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  touch "$tmp/Cargo.toml"; mkdir -p "$tmp/go"; touch "$tmp/go/go.mod"
  run "$DETECT" "$tmp"
  [ "$output" = "rust" ]
}

@test "subdir: src/ as the only module is still found via the alphabetical fallback (N1: src dropped from preference)" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  mkdir -p "$tmp/src"; touch "$tmp/src/pyproject.toml"
  run "$DETECT" "$tmp"
  [ "$output" = "python" ]
  run "$DETECT" --module-dir "$tmp"
  [ "$output" = "src" ]
}
