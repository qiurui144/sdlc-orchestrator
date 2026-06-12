#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/../.."
DETECT="$ROOT/config/detect-stack.sh"

@test "detect rust when Cargo.toml present" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  touch "$tmp/Cargo.toml"
  run "$DETECT" "$tmp"
  [ "$status" -eq 0 ]
  [ "$output" = "rust" ]
}

@test "detect ts when package.json present" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  echo '{}' > "$tmp/package.json"
  run "$DETECT" "$tmp"
  [ "$status" -eq 0 ]
  [ "$output" = "ts" ]
}

@test "detect python when pyproject.toml present" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  touch "$tmp/pyproject.toml"
  run "$DETECT" "$tmp"
  [ "$output" = "python" ]
}

@test "detect go when go.mod present" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  touch "$tmp/go.mod"
  run "$DETECT" "$tmp"
  [ "$output" = "go" ]
}

@test "fallback to generic when no marker" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  run "$DETECT" "$tmp"
  [ "$output" = "generic" ]
}

@test "each adapter YAML has required fields" {
  for stack in rust ts python go generic; do
    file="$ROOT/config/stack-$stack.yaml"
    [ -f "$file" ] || { echo "missing: $file" >&2; return 1; }
    for field in language build test_unit test_all lint clean; do
      val=$(yq -r ".$field" "$file" 2>/dev/null)
      [ "$val" != "null" ] && [ -n "$val" ] || { echo "$file missing $field" >&2; return 1; }
    done
  done
}

@test "detect python via requirements.txt (real-world marker, found in real-project validation)" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  printf 'requests==2.0\n' > "$tmp/requirements.txt"
  run "$DETECT" "$tmp"
  [ "$status" -eq 0 ]
  [ "$output" = "python" ]
}

@test "detect python via Pipfile" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  touch "$tmp/Pipfile"
  run "$DETECT" "$tmp"
  [ "$output" = "python" ]
}

@test "stack-web.yaml: has build/serve/e2e/lint_a11y keys, no hardcoded versions" {
  W="$ROOT/config/stack-web.yaml"
  [ -f "$W" ]
  for k in build serve e2e lint_a11y; do
    v=$(yq -r ".$k // \"\"" "$W"); [ -n "$v" ] || { echo "missing $k"; false; }
  done
  # no pinned tool version (e.g. "18.2.0") — adapters reference commands, not versions
  run awk '/[0-9]+\.[0-9]+\.[0-9]+/{f=1} END{exit f?1:0}' "$W"
  [ "$status" -eq 0 ] || { echo "hardcoded version in stack-web.yaml"; false; }
}
