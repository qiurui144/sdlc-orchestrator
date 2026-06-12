#!/usr/bin/env bats

BUDGET="$BATS_TEST_DIRNAME/../../skills/multi-agent-dispatch/budget.sh"

# Tests 1-2 assert the max_parallel VALUE, not disk state, so they pin a healthy
# fake disk. Without this they called budget.sh bare → depended on the real
# machine having /data with >50G free, which fails on CI / macOS / any box
# without a /data mount (the dev-box coupling that turned CI red).
@test "default max_parallel is 2" {
  run env SDLC_DISK_FAKE_ROOT_GB=200 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=20 "$BUDGET" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"max_parallel=2"* ]]
}

@test "override max_parallel via env" {
  run env SDLC_MAX_PARALLEL=4 SDLC_DISK_FAKE_ROOT_GB=200 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=20 "$BUDGET" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"max_parallel=4"* ]]
}

@test "budget blocks dispatch when tmp below threshold" {
  run env SDLC_DISK_FAKE_ROOT_GB=200 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=2 "$BUDGET" --check
  [ "$status" -eq 2 ]
  [[ "$output" == *"disk-redline-hit"* ]]
}

@test "budget allows dispatch when disk healthy" {
  run env SDLC_DISK_FAKE_ROOT_GB=200 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=20 "$BUDGET" --check
  [ "$status" -eq 0 ]
}

# v0.9 real-gate: budget reports in_flight/avail and blocks when no slot free.
@test "budget emits in_flight and avail" {
  D=$(mktemp -d); export SDLC_COUNTER_FILE="$D/counter"
  run env SDLC_MAX_PARALLEL=4 SDLC_DISK_FAKE_ROOT_GB=200 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=20 "$BUDGET" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"max_parallel=4"* ]]
  [[ "$output" == *"in_flight=0"* ]]
  [[ "$output" == *"avail=4"* ]]
}

@test "budget avail=0 exits 1 when full (disk healthy)" {
  D=$(mktemp -d); export SDLC_COUNTER_FILE="$D/counter"; echo 2 > "$D/counter"
  run env SDLC_MAX_PARALLEL=2 SDLC_DISK_FAKE_ROOT_GB=200 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=20 "$BUDGET" --check
  [ "$status" -eq 1 ]
}

@test "SKILL.md documents dispatch-batch protocol" {
  S="$BATS_TEST_DIRNAME/../../skills/multi-agent-dispatch/SKILL.md"
  grep -q "dispatch-batch" "$S"
  grep -q "counter_acquire" "$S"
  grep -q "shard" "$S"
}

@test "intake-orchestrator references dispatch-batch for fan-out" {
  grep -q "dispatch-batch" "$BATS_TEST_DIRNAME/../../agents/intake-orchestrator.md"
}

@test "budget does not crash when counter file is empty (Issue 2 regression)" {
  D=$(mktemp -d); : > "$D/counter"; export SDLC_COUNTER_FILE="$D/counter"
  run env SDLC_MAX_PARALLEL=2 SDLC_DISK_FAKE_ROOT_GB=200 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=20 "$BUDGET" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"in_flight=0"* ]]
}
