#!/usr/bin/env bats
# A3 parallel-by-default + spot-check protocol. Config knobs + orchestrator protocol assertions.
DEFAULTS="$BATS_TEST_DIRNAME/../../config/defaults.yaml"
ORCH="$BATS_TEST_DIRNAME/../../agents/task-orchestrator.md"

@test "defaults.yaml exists and sets SDLC_PARALLEL_DEFAULT on" {
  [ -f "$DEFAULTS" ]
  run grep -E '^SDLC_PARALLEL_DEFAULT:[[:space:]]*on' "$DEFAULTS"
  [ "$status" -eq 0 ]
}
@test "defaults.yaml sets SDLC_RISK_GATE on" {
  run grep -E '^SDLC_RISK_GATE:[[:space:]]*on' "$DEFAULTS"
  [ "$status" -eq 0 ]
}

@test "orchestrator documents parallel-by-default reading SDLC_PARALLEL_DEFAULT" {
  run grep -iE 'SDLC_PARALLEL_DEFAULT' "$ORCH"
  [ "$status" -eq 0 ]
}
@test "orchestrator documents SDLC_MAX_PARALLEL=1 serial escape hatch" {
  run grep -iE 'SDLC_MAX_PARALLEL=1' "$ORCH"
  [ "$status" -eq 0 ]
}
@test "orchestrator documents spot-check-don't-full-re-run for producer-self_scored artifacts" {
  run grep -iE 'spot-check' "$ORCH"
  [ "$status" -eq 0 ]
}
@test "orchestrator documents deterministic net is NEVER spot-checked (always full)" {
  run grep -iE 'never spot-check' "$ORCH"
  [ "$status" -eq 0 ]
}
@test "orchestrator documents HIGH-tier change full-re-runs (no spot-check)" {
  run grep -iE 'HIGH.*full-re-run|full-re-run.*HIGH|high-risk.*full' "$ORCH"
  [ "$status" -eq 0 ]
}
@test "A3 degradation: orchestrator states A3 failure degrades to today's behavior" {
  run grep -iE "degrade.*today|today.*behavior|SDLC_MAX_PARALLEL=1 serial" "$ORCH"
  [ "$status" -eq 0 ]
}
@test "A3 reuses shipped concurrency primitives (no new infra)" {
  run grep -iE 'atomic\.sh|counter\.sh|dispatch-batch|v0\.9.*race' "$ORCH"
  [ "$status" -eq 0 ]
}

@test "orchestrator consults risk-classify.sh for path depth (B)" {
  run grep -iE 'risk-classify' "$ORCH"
  [ "$status" -eq 0 ]
}
@test "orchestrator: LOW → fast-path impl+review; deterministic net still runs (B)" {
  run grep -iE 'LOW.*fast-path|fast-path.*impl.*review' "$ORCH"
  [ "$status" -eq 0 ]
}
@test "orchestrator: tier drives panel size (LOW/NORMAL=3, HIGH=5) (B)" {
  run grep -iE 'HIGH.*size 5|panel.*size 5|SDLC_PANEL_HIGH_RISK_SIZE' "$ORCH"
  [ "$status" -eq 0 ]
}
@test "orchestrator: deterministic net runs on EVERY path incl LOW (B)" {
  run grep -iE 'every path|EVERY path.*LOW|net.*never skip' "$ORCH"
  [ "$status" -eq 0 ]
}
