#!/usr/bin/env bats

HOOKS="$BATS_TEST_DIRNAME/../../hooks"

# Pin CLAUDE_PLUGIN_ROOT to the plugin root so hook PLUGIN_ROOT resolution is
# deterministic regardless of ambient env. In production Claude Code sets this
# to the plugin's own root; without pinning, these tests pass/fail by luck of
# whatever CLAUDE_PLUGIN_ROOT happened to be in the surrounding shell.
setup() {
  export CLAUDE_PLUGIN_ROOT="$BATS_TEST_DIRNAME/../.."
}

@test "hooks.json has 3 hook entries" {
  [ -f "$HOOKS/hooks.json" ]
  count=$(jq '[.hooks.PostToolUse, .hooks.Stop, .hooks.PreToolUse] | flatten | length' "$HOOKS/hooks.json")
  [ "$count" -ge 3 ]
}

@test "every referenced hook command resolves to an existing script" {
  while read -r h; do
    f="$HOOKS/$(printf '%s' "$h" | sed 's|.*/||')"
    [ -f "$f" ] || { echo "missing hook script: $f"; return 1; }
  done < <(jq -r '.hooks[][].hooks[].command' "$HOOKS/hooks.json")
}

@test "ga-tag-guard is wired into PreToolUse Bash (v0.18 §7.2 harness gate)" {
  n=$(jq -r '[.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[].command | select(test("ga-tag-guard"))] | length' "$HOOKS/hooks.json")
  [ "$n" -ge 1 ]
}

@test "post-write.sh defers to pre-create-gate" {
  grep -q "pre-create-gate" "$HOOKS/post-write.sh"
}

@test "post-write hook handles non-Write tool gracefully" {
  out=$(echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' | "$HOOKS/post-write.sh"; echo "rc=$?")
  [[ "$out" == *"rc=0"* ]]
}

@test "post-write hook blocks one-shot artifact filename" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  cd "$tmp" && git init -q
  out=$(echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$tmp/foo-tasks.md\"}}" | "$HOOKS/post-write.sh"; echo "rc=$?")
  [[ "$out" == *"rc=2"* ]]
}

@test "stop hook triggers audit + archival check" {
  grep -q "sprint-archival" "$HOOKS/stop.sh"
  grep -q "disk-self-audit" "$HOOKS/stop.sh"
}

@test "pre-bash-build matches cargo/npm/go/pytest" {
  for cmd in "cargo build" "npm run build" "go build ." "pytest tests/"; do
    out=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}" | env SDLC_DISK_FAKE_TMP_GB=2 SDLC_DISK_FAKE_ROOT_GB=200 SDLC_DISK_FAKE_DATA_GB=200 "$HOOKS/pre-bash-build.sh"; echo "rc=$?")
    [[ "$out" == *"rc=2"* ]] || { echo "cmd=$cmd output=$out" >&2; return 1; }
  done
}
