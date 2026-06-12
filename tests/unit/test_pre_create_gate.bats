#!/usr/bin/env bats

CHECK="$BATS_TEST_DIRNAME/../../skills/pre-create-gate/check.sh"

@test "rejects creation of non-whitelisted root .md" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  cd "$tmp" && git init -q
  run "$CHECK" "$tmp/foo-tasks.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"whitelist"* ]] || [[ "$output" == *"白名单"* ]]
}

@test "rejects version-bound filename" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  cd "$tmp" && git init -q
  run "$CHECK" "$tmp/docs/v0.5-release-notes.md"
  [ "$status" -eq 2 ]
}

@test "rejects .zh.md docs other than README" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  cd "$tmp" && git init -q
  run "$CHECK" "$tmp/docs/INSTALL.zh.md"
  [ "$status" -eq 2 ]
}

@test "allows whitelisted root files" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  cd "$tmp" && git init -q
  run "$CHECK" "$tmp/README.md"
  [ "$status" -eq 0 ]
}

@test "allows docs/superpowers/specs/<date>-<slug>.md" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  cd "$tmp" && git init -q
  mkdir -p "$tmp/docs/superpowers/specs"
  run "$CHECK" "$tmp/docs/superpowers/specs/2026-05-28-foo.md"
  [ "$status" -eq 0 ]
}

@test "warns on duplicate topic" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  cd "$tmp" && git init -q
  mkdir -p "$tmp/docs"
  echo "# install" > "$tmp/docs/INSTALL.md"
  run "$CHECK" "$tmp/docs/install-guide.md"
  [ "$status" -eq 1 ]
}

@test "ignores non-.md, non-scripts files" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  cd "$tmp" && git init -q
  run "$CHECK" "$tmp/main.rs"
  [ "$status" -eq 0 ]
}
