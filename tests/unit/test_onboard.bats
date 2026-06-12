#!/usr/bin/env bats

ONBOARD="$BATS_TEST_DIRNAME/../../skills/project-onboarding/onboard.sh"

# fresh temp git repo with a rust marker
mk_repo() {
  local d; d=$(mktemp -d)
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
    && echo '[package]' > Cargo.toml && git add -A && git commit -qm init )
  echo "$d"
}

@test "onboard scaffolds all dirs + state + config + gitignore (exit 0)" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  run "$ONBOARD" "$repo"
  [ "$status" -eq 0 ]
  [ -d "$repo/docs/superpowers/specs" ]
  [ -d "$repo/docs/superpowers/plans" ]
  [ -d "$repo/docs/superpowers/handoffs" ]
  [ -d "$repo/reports" ]
  [ -f "$repo/.sdlc/state.json" ]
  [ -f "$repo/.claude/sdlc-orchestrator.local.md" ]
  grep -qxF ".sdlc/" "$repo/.gitignore"
  grep -qxF "reports/runs/" "$repo/.gitignore"
}

@test "state.json is valid JSON with phase INIT and detected stack" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  run jq -r '.schema_version, .phase, .stack' "$repo/.sdlc/state.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1"* ]]
  [[ "$output" == *"INIT"* ]]
  [[ "$output" == *"rust"* ]]   # Cargo.toml → rust
}

@test "onboard is idempotent — second run leaves git tree clean" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  ( cd "$repo" && git add -A && git commit -qm onboarded )
  run "$ONBOARD" "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already onboarded"* ]]
  # the crucial idempotency assertion: no new changes after re-onboard
  [ -z "$(git -C "$repo" status --porcelain)" ]
}

@test "onboard does not overwrite an existing config stub" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  mkdir -p "$repo/.claude"
  printf 'CUSTOM USER CONFIG\n' > "$repo/.claude/sdlc-orchestrator.local.md"
  "$ONBOARD" "$repo" >/dev/null
  grep -qxF "CUSTOM USER CONFIG" "$repo/.claude/sdlc-orchestrator.local.md"
}

@test "onboard never creates or touches CLAUDE.md" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  [ ! -f "$repo/CLAUDE.md" ]
}

@test "onboard on a non-git dir errors (exit 1)" {
  d=$(mktemp -d); trap "rm -rf $d" EXIT
  run "$ONBOARD" "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"onboard-not-git"* ]]
}

@test "gitignore append is dedup (no duplicate .sdlc/ line on re-run)" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  "$ONBOARD" "$repo" >/dev/null
  [ "$(grep -cxF '.sdlc/' "$repo/.gitignore")" -eq 1 ]
}

@test "config stub includes a token_budget field" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  grep -q "token_budget" "$repo/.claude/sdlc-orchestrator.local.md"
}

@test "onboard materializes plugin templates into repo .sdlc/templates (F1 fix — CLAUDE_PLUGIN_ROOT unset for agents)" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  run "$ONBOARD" "$repo"
  [ "$status" -eq 0 ]
  # the shipped spec-template must now be reachable repo-relative (the path agents reference)
  [ -f "$repo/.sdlc/templates/spec-template.md" ]
  # and it matches the plugin's shipped copy
  diff -q "$repo/.sdlc/templates/spec-template.md" "$BATS_TEST_DIRNAME/../../templates/spec-template.md"
}

@test "onboard never overwrites an edited template (idempotent)" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  printf 'USER EDIT\n' > "$repo/.sdlc/templates/spec-template.md"
  "$ONBOARD" "$repo" >/dev/null
  grep -qxF "USER EDIT" "$repo/.sdlc/templates/spec-template.md"
}

@test "onboard materializes the detected stack adapter to .sdlc/stack.yaml (v0.6.6 — agents read repo-relative)" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT   # mk_repo makes a rust marker (Cargo.toml)
  run "$ONBOARD" "$repo"
  [ "$status" -eq 0 ]
  [ -f "$repo/.sdlc/stack.yaml" ]
  # detected rust → materialized adapter matches the plugin's rust adapter
  diff -q "$repo/.sdlc/stack.yaml" "$BATS_TEST_DIRNAME/../../config/stack-rust.yaml"
}

@test "onboard a subdir-module repo: stack=go, module_dir=go, stack.yaml cmds cd into go/ (bug1)" {
  d=$(mktemp -d); trap "rm -rf $d" EXIT
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t )
  mkdir -p "$d/go"; printf 'module x\n' > "$d/go/go.mod"
  ( cd "$d" && git add -A && git commit -qm init )
  run "$ONBOARD" "$d"
  [ "$status" -eq 0 ]
  # detected go (not generic) + module_dir recorded in state
  run jq -r '.stack' "$d/.sdlc/state.json"; [ "$output" = "go" ]
  run jq -r '.module_dir' "$d/.sdlc/state.json"; [ "$output" = "go" ]
  # materialized stack.yaml runs go test FROM the module subdir (subshell-wrapped, quoted)
  grep -qF "test_all: (cd 'go' && go test ./...)" "$d/.sdlc/stack.yaml"
  grep -qF "build: (cd 'go' && go build ./...)" "$d/.sdlc/stack.yaml"
  # language line is NOT cd-prefixed
  grep -q "^language: go$" "$d/.sdlc/stack.yaml"
}

@test "onboard subdir python: a ';' command value is subshell-wrapped so the post-; part runs in the module dir (W1)" {
  d=$(mktemp -d); trap "rm -rf $d" EXIT
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t )
  mkdir -p "$d/backend"; touch "$d/backend/pyproject.toml"
  ( cd "$d" && git add -A && git commit -qm init )
  "$ONBOARD" "$d" >/dev/null
  # python clean uses ';' — the WHOLE value must be inside (cd 'backend' && ... ) so the
  # post-; `rm -rf` cannot escape to the repo root (W1 regression).
  line="$(grep '^clean:' "$d/.sdlc/stack.yaml")"
  [[ "$line" == "clean: (cd 'backend' && "*")" ]]
  [[ "$line" == *"; rm -rf"*")" ]]   # the ; stays inside the closing paren
}

@test "onboard subdir module with a space in its name: cd target is single-quoted (W2)" {
  d=$(mktemp -d); trap "rm -rf $d" EXIT
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t )
  mkdir -p "$d/My Service"; printf 'module x\n' > "$d/My Service/go.mod"
  ( cd "$d" && git add -A && git commit -qm init )
  "$ONBOARD" "$d" >/dev/null
  grep -qF "test_all: (cd 'My Service' && go test ./...)" "$d/.sdlc/stack.yaml"
}

@test "onboard seeds .sdlc/disk.conf (single disk-redline surface) with commented defaults" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  [ -f "$repo/.sdlc/disk.conf" ]
  # commented-only by default (no active override → built-in defaults apply)
  ! grep -qE '^[[:space:]]*redline_root_gb=' "$repo/.sdlc/disk.conf"
  grep -qE '# redline_root_gb=' "$repo/.sdlc/disk.conf"
}

@test "config stub no longer carries dead disk_redline_* keys (v0.6.6 reconcile)" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  ! grep -qE '^disk_redline_(root|data)_gb:' "$repo/.claude/sdlc-orchestrator.local.md"
}
