#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/../.."
RUN="$ROOT/eval/run-eval.sh"

@test "dry-run prints dispatch plan without calling claude" {
  run "$RUN" spec-analyst --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude -p"* ]]        # shows the command it WOULD run
  [[ "$output" == *"spec-analyst"* ]]
  [[ "$output" == *"--model"* ]]
}

@test "dry-run reads model_tier from the agent frontmatter" {
  run "$RUN" spec-analyst --dry-run
  [[ "$output" == *"opus"* ]]             # spec-analyst is opus-tier
}

@test "unknown agent errors clearly" {
  run "$RUN" no-such-agent --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"no-such-agent"* ]]
}

@test "grade-existing mode grades a pre-captured output (no LLM)" {
  # simulate a captured output, grade it against the fixture expect
  tmpout=$(mktemp)
  cp "$ROOT/tests/fixtures/eval/good-output.txt" "$tmpout"
  run "$RUN" --grade-only "$tmpout" "$ROOT/tests/fixtures/eval/expect-sample.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GRADE PASS"* ]]
  rm -f "$tmpout"
}

@test "--tiers dry-run shows a dispatch line per requested tier" {
  run "$RUN" spec-analyst --tiers opus,sonnet --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--model opus"* ]]
  [[ "$output" == *"--model sonnet"* ]]
}
