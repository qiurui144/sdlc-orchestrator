#!/usr/bin/env bats
# C-2 Task 2: exact-binomial probe power. Fixes rev.3-review's finding that the continuous
# two-sample formula was wrong AND power is non-monotonic in M.
setup() { POWER="${BATS_TEST_DIRNAME}/../../skills/model-eval/probe-power.sh"; }

@test "exact-binomial min M = 29 (NOT the wrong continuous M=24)" {
  run bash "$POWER" --p0 0.95 --p1 0.7 --floor 0.8 --target-power 0.9
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'min_M=29'
}

@test "power at M=24 is < 0.9 (continuous formula was optimistic, ~0.889)" {
  pw="$(bash "$POWER" --power-at 24 --p1 0.7 --floor 0.8 | awk '{print $3}')"
  awk -v a="$pw" 'BEGIN{exit !(a<0.9 && a>0.88)}'
}

@test "power is NON-monotonic in M (M=25 power < M=24 power, discrete jump)" {
  p24="$(bash "$POWER" --power-at 24 --p1 0.7 --floor 0.8 | awk '{print $3}')"
  p25="$(bash "$POWER" --power-at 25 --p1 0.7 --floor 0.8 | awk '{print $3}')"
  awk -v a="$p25" -v b="$p24" 'BEGIN{exit !(a<b)}'
}

@test "min_M output flags non-monotonic (stays_next5=NO) so plan doesn't trust a lone M" {
  run bash "$POWER" --p0 0.95 --p1 0.7 --floor 0.8 --target-power 0.9
  echo "$output" | grep -q 'stays_next5=NO'
}

@test "false alarm at healthy p0 is low (<0.05) at M=29" {
  fa="$(bash "$POWER" --power-at 29 --p1 0.7 --floor 0.8 | awk '{print $5}')"
  awk -v a="$fa" 'BEGIN{exit !(a<0.05)}'
}

@test "impossible target -> min_M=NONE exit 1 (not a crash)" {
  run bash "$POWER" --p1 0.79 --floor 0.8 --target-power 0.999 --max-m 10
  [ "$status" -eq 1 ]; echo "$output" | grep -q 'min_M=NONE'
}
