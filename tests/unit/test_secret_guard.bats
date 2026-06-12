#!/usr/bin/env bats
# secret-guard (v0.21, SE13): PreToolUse hook blocking commit/push of secrets/loose-perm files.
# Fixtures built at runtime (no contiguous token literal in this file → no self-trip).
HOOK="$BATS_TEST_DIRNAME/../../hooks/secret-guard.sh"

setup() { R=$(mktemp -d); git -C "$R" init -q; }
teardown() { rm -rf "$R"; }
ghtoken() { printf 'gho_%s' "$(printf 'A%.0s' $(seq 40))"; }
payload() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" > "$R/in.json"; }

@test "non-Bash tool → allow" {
  printf '{"tool_name":"Write","tool_input":{}}' > "$R/in.json"
  cd "$R"; SDLC_PROJECT_ROOT="$R" run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "non-history git command (status) → allow" {
  payload "git status"; cd "$R"; SDLC_PROJECT_ROOT="$R" run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "git commit with a STAGED secret → BLOCK (exit 2)" {
  printf 'token=%s\n' "$(ghtoken)" > "$R/leak.env.txt"; git -C "$R" add leak.env.txt
  payload "git commit -m wip"; cd "$R"; SDLC_PROJECT_ROOT="$R" run bash "$HOOK" < in.json
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "secret-guard"
  ! echo "$output" | grep -q "$(ghtoken)"   # §1.4 — value not echoed
}

@test "git commit clean → allow" {
  echo "just code" > "$R/ok.txt"; git -C "$R" add ok.txt
  payload "git commit -m ok"; cd "$R"; SDLC_PROJECT_ROOT="$R" run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "SDLC_SECRET_OVERRIDE=1 → allow even with a staged secret" {
  printf 'token=%s\n' "$(ghtoken)" > "$R/leak.txt"; git -C "$R" add leak.txt
  payload "git commit -m wip"; cd "$R"
  SDLC_PROJECT_ROOT="$R" SDLC_SECRET_OVERRIDE=1 run bash "$HOOK" < in.json
  [ "$status" -eq 0 ]
}

@test "git push with a TRACKED secret → BLOCK" {
  printf 'k=%s\n' "$(ghtoken)" > "$R/c.txt"; git -C "$R" add c.txt
  git -C "$R" -c user.email=t@t -c user.name=t commit -q -m c
  payload "git push origin main"; cd "$R"; SDLC_PROJECT_ROOT="$R" run bash "$HOOK" < in.json
  [ "$status" -eq 2 ]
}

@test "non-git directory → no-op allow" {
  P=$(mktemp -d); payload "git commit -m x"
  cd "$P"; SDLC_PROJECT_ROOT="$P" run bash "$HOOK" < "$R/in.json"
  [ "$status" -eq 0 ]; rm -rf "$P"
}

@test "regression(BLOCK-2): 'git -c x=y commit' with a staged secret is BLOCKED (option-insertion bypass closed)" {
  printf 'k=%s\n' "$(ghtoken)" > "$R/leak.txt"; git -C "$R" add leak.txt
  payload "git -c user.name=x commit -m wip"; cd "$R"; SDLC_PROJECT_ROOT="$R" run bash "$HOOK" < in.json
  [ "$status" -eq 2 ]
}
@test "regression(BLOCK-2): 'git -C dir commit' variant also blocked" {
  printf 'k=%s\n' "$(ghtoken)" > "$R/leak.txt"; git -C "$R" add leak.txt
  payload "git -C . commit -m wip"; cd "$R"; SDLC_PROJECT_ROOT="$R" run bash "$HOOK" < in.json
  [ "$status" -eq 2 ]
}
