#!/usr/bin/env bats
# Integration test: hello-world end-to-end phase wiring
# Exercises skill+hook+adapter integration without invoking LLM agents.
# All tests run in an isolated temp git repo (setup/teardown).

ROOT="$BATS_TEST_DIRNAME/../.."
DEMO="$ROOT/examples/hello-world"

setup() {
  # Pin CLAUDE_PLUGIN_ROOT to the real plugin root (not the temp WORK dir) so
  # hook scripts resolve their sibling skills deterministically across envs.
  export CLAUDE_PLUGIN_ROOT="$ROOT"
  WORK=$(mktemp -d)
  cp -r "$DEMO"/. "$WORK"/
  cp -a "$DEMO"/.gitignore "$WORK"/ 2>/dev/null || true
  cd "$WORK"
  git init -q
  git config user.name test
  git config user.email test@test
  git add -A
  git commit -qm "init"
  mkdir -p docs/superpowers/specs docs/superpowers/plans docs/superpowers/handoffs reports/runs .sdlc
}

teardown() {
  rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# Phase 0 — bootstrap / disk audit
# ---------------------------------------------------------------------------

@test "Phase 0 — disk audit emits YAML snapshot with disk_snapshot key" {
  run env SDLC_DISK_FAKE_ROOT_GB=200 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=20 \
    "$ROOT/skills/disk-self-audit/audit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"disk_snapshot:"* ]]
}

# ---------------------------------------------------------------------------
# Phase 1 — spec creation (Pre-Create Gate)
# ---------------------------------------------------------------------------

@test "Phase 1 — Pre-Create Gate allows date-prefixed spec path (exit 0 or 1/warn)" {
  # Exit 0 = allow, exit 1 = warn (non-blocking similar-topic hint).
  # Both are permissive outcomes — only exit 2 (block) is a failure.
  run "$ROOT/skills/pre-create-gate/check.sh" \
    "$WORK/docs/superpowers/specs/2026-05-29-hello.md"
  [ "$status" -ne 2 ]
}

@test "Phase 1 — Pre-Create Gate rejects spec path missing YYYY-MM-DD prefix (exit 2)" {
  run "$ROOT/skills/pre-create-gate/check.sh" \
    "$WORK/docs/superpowers/specs/hello.md"
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Phase 2 — plan (handoff schema validation)
# ---------------------------------------------------------------------------

@test "Phase 2 — handoff schema validates spec→plan transition (exit 0)" {
  echo "spec content" > docs/superpowers/specs/2026-05-29-hello.md
  git add docs/ && git commit -qm "spec"
  sha=$(git hash-object docs/superpowers/specs/2026-05-29-hello.md)
  tmp_handoff=$(mktemp /tmp/handoff-i4-XXXXXX.yaml)
  cat > "$tmp_handoff" <<EOF
schema_version: 1
sprint_id: 2026-05-29-hello
phase_from: spec
phase_to: plan
artifact_path: docs/superpowers/specs/2026-05-29-hello.md
artifact_sha: $sha
timestamp_utc8: 2026-05-29T15:00:00+08:00
EOF
  run "$ROOT/skills/handoff-schema/validate.sh" "$tmp_handoff"
  rm -f "$tmp_handoff"
  [ "$status" -eq 0 ]
}

@test "Phase 2 — handoff rejects illegal phase transition spec→impl (exit 2)" {
  echo "spec content" > docs/superpowers/specs/2026-05-29-hello.md
  git add docs/ && git commit -qm "spec"
  sha=$(git hash-object docs/superpowers/specs/2026-05-29-hello.md)
  tmp_handoff=$(mktemp /tmp/handoff-i5-XXXXXX.yaml)
  cat > "$tmp_handoff" <<EOF
schema_version: 1
sprint_id: 2026-05-29-hello
phase_from: spec
phase_to: impl
artifact_path: docs/superpowers/specs/2026-05-29-hello.md
artifact_sha: $sha
timestamp_utc8: 2026-05-29T15:00:00+08:00
EOF
  run "$ROOT/skills/handoff-schema/validate.sh" "$tmp_handoff"
  rm -f "$tmp_handoff"
  [ "$status" -eq 2 ]
  [[ "$output" == *"phase-skip-not-allowed"* ]]
}

# ---------------------------------------------------------------------------
# Phase 3 — impl (multi-agent dispatch budget)
# ---------------------------------------------------------------------------

@test "Phase 3 — multi-agent dispatch exits 0 when disk is healthy" {
  run env SDLC_DISK_FAKE_ROOT_GB=200 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=20 \
    "$ROOT/skills/multi-agent-dispatch/budget.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"max_parallel="* ]]
}

# ---------------------------------------------------------------------------
# Phase 5 — test (stack adapter + hook)
# ---------------------------------------------------------------------------

@test "Phase 5 — stack detect identifies hello-world as rust" {
  stack=$("$ROOT/config/detect-stack.sh" "$WORK")
  [ "$stack" = "rust" ]
}

@test "Phase 5 — stack-rust.yaml test_unit field references cargo test" {
  cmd=$(yq -r '.test_unit' "$ROOT/config/stack-rust.yaml")
  [[ "$cmd" == *"cargo test"* ]]
}

@test "Phase 5 — pre-bash-build hook blocks cargo test when /tmp is at disk redline" {
  json='{"tool_name":"Bash","tool_input":{"command":"cargo test --lib"}}'
  out=$(echo "$json" | \
    env SDLC_DISK_FAKE_TMP_GB=2 SDLC_DISK_FAKE_ROOT_GB=200 SDLC_DISK_FAKE_DATA_GB=200 \
    "$ROOT/hooks/pre-bash-build.sh"; echo "rc=$?")
  [[ "$out" == *"rc=2"* ]]
}

# ---------------------------------------------------------------------------
# Phase 6 — release (sprint archival)
# ---------------------------------------------------------------------------

@test "Phase 6 — sprint archival dry-run lists plan deletion without removing file" {
  echo "plan content" > docs/superpowers/plans/2026-05-29-hello.md
  git add docs/ && git commit -qm "plan"
  run "$ROOT/skills/sprint-archival/archive.sh" --sprint 2026-05-29-hello --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would"* ]]
  [ -f docs/superpowers/plans/2026-05-29-hello.md ]
}

@test "Phase 6 — sprint archival apply removes plan and retains spec" {
  echo "spec content" > docs/superpowers/specs/2026-05-29-hello.md
  echo "plan content" > docs/superpowers/plans/2026-05-29-hello.md
  git add docs/ && git commit -qm "spec and plan"
  run "$ROOT/skills/sprint-archival/archive.sh" --sprint 2026-05-29-hello --apply
  [ "$status" -eq 0 ]
  [ ! -f docs/superpowers/plans/2026-05-29-hello.md ]
  [ -f docs/superpowers/specs/2026-05-29-hello.md ]
}
