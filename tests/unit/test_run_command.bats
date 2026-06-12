#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/../.."

@test "run.md exists with required frontmatter" {
  run="$ROOT/commands/run.md"
  [ -f "$run" ]
  grep -q '^description:' "$run"
  grep -q '^argument-hint:' "$run"
  grep -q '^allowed-tools:' "$run"
}

@test "run.md documents drive mode + the three flags + GA hard-stop + cost gate" {
  run="$ROOT/commands/run.md"
  grep -q 'drive mode' "$run"
  grep -q -- '--auto' "$run"
  grep -q -- '--intake' "$run"
  grep -q -- '--from' "$run"
  grep -q 'GA tag' "$run"
  grep -q 'hard-stop' "$run"
  grep -q '/sdlc:cost' "$run"
}

@test "task-orchestrator declares BOTH read-only and drive modes + GA hard-stop" {
  to="$ROOT/agents/task-orchestrator.md"
  grep -q 'read-only mode' "$to"
  grep -q 'drive mode' "$to"
  grep -q 'continue/stop/redo' "$to"
  grep -q 'GA-tag hard-stop' "$to"
}

@test "GA hard-stop explicitly notes --auto cannot bypass it" {
  to="$ROOT/agents/task-orchestrator.md"
  grep -A3 'GA-tag hard-stop' "$to" | grep -q -- '--auto'
}

@test "status.md remains read-only (non-regression) and is NOT drive" {
  st="$ROOT/commands/status.md"
  grep -q 'read-only' "$st"
  ! grep -q 'drive mode' "$st"
}

@test "task-orchestrator gate uses challenger panel + consensus-auto (v0.9)" {
  to="$ROOT/agents/task-orchestrator.md"
  grep -qi 'panel' "$to"
  grep -qi 'consensus-auto' "$to"
  grep -q 'AUTO_ADVANCE' "$to"
}

@test "task-orchestrator escalates the four high-risk classes (v0.9)" {
  to="$ROOT/agents/task-orchestrator.md"
  grep -qi 'secret' "$to"
  grep -qi 'migration' "$to"
  grep -qi 'irreversible' "$to"
  grep -q 'STRIDE' "$to"
}

@test "run.md supports --interactive escape hatch (v0.9)" {
  grep -q -- '--interactive' "$ROOT/commands/run.md"
}

@test "run.md documents --full forces full rigor (override classifier) (v0.28 B)" {
  grep -qiE -- '--full' "$ROOT/commands/run.md"
}
@test "run.md documents --fast is advisory (never demotes HIGH/NORMAL) (v0.28 B)" {
  grep -qiE -- '--fast.*advisor|advisor.*--fast' "$ROOT/commands/run.md"
}
@test "run.md documents default = classifier-driven path depth (v0.28 B)" {
  grep -qiE 'classifier-driven|risk-classify' "$ROOT/commands/run.md"
}
