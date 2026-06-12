#!/usr/bin/env bats
# ga-tag-guard (v0.18): harness-enforced §7.2 GA hard-stop. A major GA tag (vN.0.0, no
# pre-release suffix) is BLOCKED (exit 2) in an sdlc-gated repo unless a human approval marker
# is present. Non-sdlc repos, pre-release tags, dev minors, patches, deletes/lists → allow.
HOOK="$BATS_TEST_DIRNAME/../../hooks/ga-tag-guard.sh"

setup() { R=$(mktemp -d); }
teardown() { rm -rf "$R"; }

# write a PreToolUse JSON payload for a Bash command into $R/in.json
payload() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" > "$R/in.json"; }
sdlc_repo() { mkdir -p "$R/.sdlc"; : > "$R/.sdlc/state.json"; }

@test "non-Bash tool → allow" {
  printf '{"tool_name":"Write","tool_input":{}}' > "$R/in.json"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "non-tag bash command in sdlc repo → allow" {
  sdlc_repo; payload "git status"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "major GA tag in sdlc repo, no approval → BLOCK (exit 2)" {
  sdlc_repo; payload "git tag v1.0.0"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 2 ]
}

@test "blocked message is actionable (mentions approval + §7.2)" {
  sdlc_repo; payload "git tag v1.0.0"
  cd "$R"; run bash "$HOOK" < in.json
  echo "$output" | grep -q "SDLC_GA_APPROVED"
  echo "$output" | grep -q "7.2"
}

@test "major GA tag with SDLC_GA_APPROVED=1 → allow" {
  sdlc_repo; payload "git tag v1.0.0"
  cd "$R"; SDLC_GA_APPROVED=1 run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "major GA tag with .sdlc/ga-approved file → allow" {
  sdlc_repo; : > "$R/.sdlc/ga-approved"; payload "git tag v1.0.0"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "major GA tag in NON-sdlc repo (no state) → allow (no-op, non-invasive)" {
  payload "git tag v1.0.0"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "pre-release rc tag → allow even in sdlc repo" {
  sdlc_repo; payload "git tag v1.0.0-rc.1"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "dev minor v0.18.0 → allow (not a major GA)" {
  sdlc_repo; payload "git tag v0.18.0"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "minor v0.10.0 (minor!=0) → allow" {
  sdlc_repo; payload "git tag v0.10.0"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "patch v0.17.1 → allow" {
  sdlc_repo; payload "git tag v0.17.1"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "git tag -d v1.0.0 (delete) → allow" {
  sdlc_repo; payload "git tag -d v1.0.0"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "git tag -l (list) → allow" {
  sdlc_repo; payload "git tag -l"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "v2.0.0 major also blocked" {
  sdlc_repo; payload "git tag v2.0.0"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 2 ]
}

# --- F1 (dual-acceptance adversarial): option insertion must NOT evade the GA hard-stop ---
@test "BYPASS F1: git --no-pager tag v1.0.0 → still BLOCK" {
  sdlc_repo; payload "git --no-pager tag v1.0.0"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 2 ]
}
@test "BYPASS F1: git -C /some/dir tag v1.0.0 → still BLOCK" {
  sdlc_repo; payload "git -C /some/dir tag v1.0.0"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 2 ]
}
@test "BYPASS F1: git -c user.name=x tag v1.0.0 → still BLOCK" {
  sdlc_repo; payload "git -c user.name=x tag v1.0.0"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 2 ]
}
@test "BYPASS F1: newline-separated git\\n tag v1.0.0 → still BLOCK" {
  sdlc_repo
  printf '{"tool_name":"Bash","tool_input":{"command":"git\\n tag v1.0.0"}}' > "$R/in.json"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 2 ]
}

@test "state via docs/superpowers/handoffs → also detected (block)" {
  mkdir -p "$R/docs/superpowers/handoffs"; : > "$R/docs/superpowers/handoffs/hello_state.yaml"
  payload "git tag v2.0.0"
  cd "$R"; run bash "$HOOK" < in.json
  [ "$status" -eq 2 ]
}
