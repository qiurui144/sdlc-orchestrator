#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/../.."
COST="$ROOT/skills/cost-estimation/cost.sh"
FIX="$BATS_TEST_DIRNAME/../fixtures/cost"

# point cost.sh at synthetic pricing + model via env (real agent tiers still used)
synth() { export SDLC_PRICING_FILE="$FIX/pricing.yaml" SDLC_COST_MODEL_FILE="$FIX/cost-model.yaml"; }

@test "phase estimate is numerically exact (spec-analyst opus = \$110.00)" {
  synth
  run "$COST" --phase spec
  [ "$status" -eq 0 ]
  [[ "$output" == *"110.00"* ]]
}

@test "tester haiku phase = \$2.00 exact (downgraded sonnet→haiku per tier-matrix 2026-05-30)" {
  # tester was downgraded sonnet→haiku (eval 3/3 robust at haiku, mechanical agent).
  # synthetic haiku input = \$1/M; cost-model tester = 2M in + 0 out → 2M×\$1 = \$2.00.
  synth
  run "$COST" --phase test
  [[ "$output" == *"2.00"* ]]
}

@test "output is labelled ESTIMATE with the pricing as_of date" {
  synth
  run "$COST" --phase spec
  [[ "$output" == *"ESTIMATE"* ]]
  [[ "$output" == *"2026-01-01"* ]]
}

@test "missing pricing file → fallback + warning, not crash" {
  export SDLC_PRICING_FILE="$FIX/does-not-exist.yaml" SDLC_COST_MODEL_FILE="$FIX/cost-model.yaml"
  run "$COST" --phase spec
  [ "$status" -eq 0 ]
  [[ "$output" == *"fallback"* ]] || [[ "$output" == *"cost-no-pricing"* ]]
}

@test "over budget warns (default, exit 0)" {
  synth
  run env SDLC_TOKEN_BUDGET=100 "$COST" --phase spec
  [ "$status" -eq 0 ]
  [[ "$output" == *"OVER"* ]] || [[ "$output" == *"over budget"* ]]
}

@test "over budget with strict → exit 2" {
  synth
  run env SDLC_TOKEN_BUDGET=100 SDLC_BUDGET_STRICT=1 "$COST" --phase spec
  [ "$status" -eq 2 ]
}

@test "sprint sums the core SDLC chain agents" {
  synth
  run "$COST" --sprint
  [ "$status" -eq 0 ]
  [[ "$output" == *"TOTAL"* ]]
  [[ "$output" == *"spec-analyst"* ]]
  [[ "$output" == *"releaser"* ]]
}
