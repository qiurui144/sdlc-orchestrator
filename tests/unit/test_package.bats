#!/usr/bin/env bats
# package.sh — distributable plugin tarball builder (GA tooling, v1.0 prep).
P="$BATS_TEST_DIRNAME/../../scripts/package.sh"
ROOT="$BATS_TEST_DIRNAME/../.."
setup() { export DIST_DIR=$(mktemp -d); }
teardown() { rm -rf "$DIST_DIR"; }

@test "packages current manifest version → tarball with runtime surface, excludes dev" {
  v=$(yq -r '.version' "$ROOT/.claude-plugin/plugin.json")
  run bash "$P" "v$v"
  [ "$status" -eq 0 ]
  tb="$DIST_DIR/sdlc-orchestrator-v$v.tar.gz"
  [ -f "$tb" ]
  tar tzf "$tb" | grep -q ".claude-plugin/plugin.json"
  tar tzf "$tb" | grep -q "agents/"
  tar tzf "$tb" | grep -q "skills/"
  tar tzf "$tb" | grep -q "commands/"
  tar tzf "$tb" | grep -q "hooks/"
  tar tzf "$tb" | grep -q "config/"
  # dev artifacts excluded
  ! tar tzf "$tb" | grep -q "tests/"
  ! tar tzf "$tb" | grep -q "reports/"
  ! tar tzf "$tb" | grep -q "^docs/"
  ! tar tzf "$tb" | grep -qE "(^|/)\.git/"
}
@test "version mismatch vs manifest → exit 2" {
  run bash "$P" v99.99.99
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "package-version-mismatch"
}
@test "missing version arg → exit 2" {
  run bash "$P"
  [ "$status" -eq 2 ]
}
@test "accepts version with or without leading v" {
  v=$(yq -r '.version' "$ROOT/.claude-plugin/plugin.json")
  run bash "$P" "$v"
  [ "$status" -eq 0 ]
  [ -f "$DIST_DIR/sdlc-orchestrator-v$v.tar.gz" ]
}
@test "packaged challenger-panel RUNS from extracted artifact (eval/judge.sh shipped) [smoke regression]" {
  v=$(yq -r '.version' "$ROOT/.claude-plugin/plugin.json")
  bash "$P" "v$v"
  x=$(mktemp -d); tar -xzf "$DIST_DIR/sdlc-orchestrator-v$v.tar.gz" -C "$x"
  [ -f "$x/eval/judge.sh" ]                          # panel.sh runtime dep must ship
  mkdir -p "$x/v"; printf 'VERDICT: PASS\nSCORE: 5\nLENS: x\nREASON: y\n' > "$x/v/a.json"
  run bash "$x/skills/challenger-panel/panel.sh" --consensus --votes-dir "$x/v" --high-risk no
  [ "$status" -eq 0 ]; echo "$output" | grep -q "AUTO_ADVANCE"
  rm -rf "$x"
}
@test "transient eval/runs excluded from package" {
  v=$(yq -r '.version' "$ROOT/.claude-plugin/plugin.json")
  bash "$P" "v$v"
  ! tar tzf "$DIST_DIR/sdlc-orchestrator-v$v.tar.gz" | grep -q "eval/runs/"
}
