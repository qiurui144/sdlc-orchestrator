#!/usr/bin/env bats

@test "plugin.json exists" {
  [ -f "$BATS_TEST_DIRNAME/../../.claude-plugin/plugin.json" ]
}

@test "plugin.json has required fields" {
  manifest="$BATS_TEST_DIRNAME/../../.claude-plugin/plugin.json"
  run jq -r '.name, .version, .description, .author, .license' "$manifest"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sdlc-orchestrator"* ]]
  # version must be present and semver — checked dynamically so version bumps don't break this test
  ver=$(jq -r '.version' "$manifest")
  [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?$ ]]
}

@test "plugin.json version is semver" {
  ver=$(jq -r '.version' "$BATS_TEST_DIRNAME/../../.claude-plugin/plugin.json")
  [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?$ ]]
}
