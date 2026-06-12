#!/usr/bin/env bats

PLAN="$BATS_TEST_DIRNAME/../../skills/intake-consolidation/plan.sh"

@test "light = 5 free dims, scope full (incl secrets/SE13)" {
  run "$PLAN" --depth light
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 5 ]
  echo "$output" | grep -qE '^deps	haiku	free	full$'
  echo "$output" | grep -qE '^disk	haiku	free	full$'
  echo "$output" | grep -qE '^secrets	haiku	free	full$'
  ! echo "$output" | grep -q 'review'
}

@test "standard = 8 dims, paid ones sampled" {
  run "$PLAN" --depth standard
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 8 ]
  echo "$output" | grep -qE '^review	sonnet	paid	sampled$'
  echo "$output" | grep -qE '^threat	opus	paid	sampled$'
}

@test "deep = paid ones full scope" {
  run "$PLAN" --depth deep
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^threat	opus	paid	full$'
}

@test "--only filters within depth" {
  run "$PLAN" --depth standard --only deps,debt
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "--only naming a paid dim under light is rejected" {
  run "$PLAN" --depth light --only review
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'requires --depth'
}

@test "--only with unknown dim exits 2 unknown-dimension" {
  run "$PLAN" --depth standard --only bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'unknown-dimension'
}

@test "bad --depth exits 2" {
  run "$PLAN" --depth wat
  [ "$status" -eq 2 ]
}

@test "--only tolerates spaces after commas" {
  run "$PLAN" --depth standard --only "deps, debt"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 2 ]
}
