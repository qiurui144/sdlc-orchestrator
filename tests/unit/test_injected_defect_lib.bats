#!/usr/bin/env bats
# C-2 Task 1: injected-defect library + circular-blind-spot guard (§6a).
# The guard is FAIL-CLOSED: a lib built only from claude-caught defects is tautological
# (can't surface claude's own blind spots) -> rejected until a real prod-MISSED/cross-provider
# entry exists. This correctly blocks C-2 from activating a draftable op without real calibration data.

setup() {
  R="${BATS_TEST_DIRNAME}/../.."
  LIB="$R/skills/model-eval/injected-defect-lib.sh"
  TD="$(mktemp -d)"; export SDLC_INJECTED_DEFECTS_DIR="$TD"
}
teardown() { rm -rf "$TD"; }

@test "validate REJECTS a lib with only prod-caught (circular blind spot, fail-closed)" {
  cat > "$TD/demo.yaml" <<'EOF'
task_type: demo
defects:
  - {id: d1, task_type: demo, defect_type: omission, planted_patch: "p", detect_marker: "m", source: prod-caught}
EOF
  run bash "$LIB" validate demo
  [ "$status" -eq 1 ]; [[ "$output" == *"circular-blind-spot"* ]]
}

@test "validate PASSES with >=1 prod-MISSED or cross-provider entry" {
  cat > "$TD/demo.yaml" <<'EOF'
task_type: demo
defects:
  - {id: d1, task_type: demo, defect_type: omission, planted_patch: "p", detect_marker: "m", source: prod-caught}
  - {id: d2, task_type: demo, defect_type: overclaim, planted_patch: "p2", detect_marker: "m2", source: prod-MISSED}
EOF
  run bash "$LIB" validate demo
  [ "$status" -eq 0 ]; [[ "$output" == *"lib-valid"* ]]
}

@test "validate REJECTS an incomplete entry (missing field)" {
  cat > "$TD/demo.yaml" <<'EOF'
task_type: demo
defects:
  - {id: d1, task_type: demo, defect_type: omission, source: cross-provider}
EOF
  run bash "$LIB" validate demo
  [ "$status" -eq 1 ]
}

@test "no lib for task_type -> exit 2" {
  run bash "$LIB" validate nonesuch
  [ "$status" -eq 2 ]
}

@test "hash stable + changes on content change" {
  cat > "$TD/demo.yaml" <<'EOF'
task_type: demo
defects:
  - {id: d1, task_type: demo, defect_type: omission, planted_patch: "p", detect_marker: "m", source: prod-MISSED}
EOF
  h1="$(bash "$LIB" hash demo)"; h2="$(bash "$LIB" hash demo)"
  [ "$h1" = "$h2" ]; [ -n "$h1" ]
  printf '  - {id: d2, task_type: demo, defect_type: x, planted_patch: y, detect_marker: z, source: prod-MISSED}\n' >> "$TD/demo.yaml"
  h3="$(bash "$LIB" hash demo)"
  [ "$h1" != "$h3" ]
}

@test "spec-scope shipped lib has cross-provider entry (2026-06-13 real eval) — guard passes" {
  # Real eval (C-2 Task 6) added a qwen cross-provider entry to spec-scope.yaml.
  # circular-blind-spot guard now passes (>= 1 real-source entry).
  # Use the REAL config dir (not the per-test temp override).
  run env -u SDLC_INJECTED_DEFECTS_DIR bash "$LIB" validate spec-scope
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "lib-valid"
}

@test "plan-decomp shipped lib has cross-provider entry (2026-06-13 gpt-5.5 eval) — guard passes" {
  run env -u SDLC_INJECTED_DEFECTS_DIR bash "$LIB" validate plan-decomp
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "lib-valid"
}

@test "review-body shipped lib has cross-provider entry (2026-06-13 gpt-5.5 eval) — guard passes" {
  run env -u SDLC_INJECTED_DEFECTS_DIR bash "$LIB" validate review-body
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "lib-valid"
}

@test "threat-draft shipped lib has cross-provider entry (2026-06-13 gpt-5.5 eval) — guard passes" {
  run env -u SDLC_INJECTED_DEFECTS_DIR bash "$LIB" validate threat-draft
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "lib-valid"
}

@test "adr-draft shipped lib has cross-provider entry (2026-06-13 gpt-5.5 eval) — guard passes" {
  run env -u SDLC_INJECTED_DEFECTS_DIR bash "$LIB" validate adr-draft
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "lib-valid"
}

@test "code-hotspot-summary shipped lib has cross-provider entry (2026-06-13 planted-defect eval) — guard passes" {
  run env -u SDLC_INJECTED_DEFECTS_DIR bash "$LIB" validate code-hotspot-summary
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "lib-valid"
}

@test "commit-msg-draft shipped lib has cross-provider entry (2026-06-13 gpt-5.5 eval) — guard passes" {
  run env -u SDLC_INJECTED_DEFECTS_DIR bash "$LIB" validate commit-msg-draft
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "lib-valid"
}
