#!/usr/bin/env bats
F="$BATS_TEST_DIRNAME/../../skills/auto-fanout/fanout.sh"
ROOT="$BATS_TEST_DIRNAME/../.."
@test "groups lists panel + intake" {
  run bash "$F" groups
  [ "$status" -eq 0 ]; echo "$output" | grep -q "^panel$"; echo "$output" | grep -q "^intake$"
}
@test "intake → 8 dims (incl secrets/SE13)" {
  run bash "$F" intake
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c .)" -eq 8 ]
  for d in deps debt docs disk secrets review threat perf; do echo "$output" | grep -q "^$d$"; done
}
@test "intake --free-only → 5 dims (deps debt docs disk secrets)" {
  run bash "$F" intake --free-only
  [ "$(echo "$output" | grep -c .)" -eq 5 ]
  echo "$output" | grep -q "^secrets$"; ! echo "$output" | grep -q "^threat$"
}
@test "panel --size 3 → 3 lenses" {
  run bash "$F" panel --size 3
  [ "$status" -eq 0 ]; [ "$(echo "$output" | grep -c .)" -eq 3 ]
  echo "$output" | grep -q "^correctness$"
}
@test "panel --size 5 → 5 lenses (high-risk)" {
  run bash "$F" panel --size 5
  [ "$(echo "$output" | grep -c .)" -eq 5 ]
  echo "$output" | grep -q "^performance$"
}
@test "panel --size 0 → empty, exit 0 (G2 SIGPIPE fold-in)" {
  run bash "$F" panel --size 0
  [ "$status" -eq 0 ]; [ "$(echo "$output" | grep -c .)" -eq 0 ]
}
@test "panel delegates to panel.sh via --artifact/--handoff" {
  art="$ROOT/README.md"
  h=$(mktemp); printf 'phase: SPEC_DRAFT\n' > "$h"
  run bash "$F" panel --artifact "$art" --handoff "$h"
  [ "$status" -eq 0 ]; [ "$(echo "$output" | grep -c .)" -ge 3 ]
  echo "$output" | grep -q "^correctness$"; rm -f "$h"
}
@test "panel without --artifact/--handoff and no --size → exit 2" {
  run bash "$F" panel
  [ "$status" -eq 2 ]
}
@test "bad group → exit 2" { run bash "$F" badgroup; [ "$status" -eq 2 ]; }
@test "no group → exit 2" { run bash "$F"; [ "$status" -eq 2 ]; }
@test "adversarial: group injection → exit 2 (whitelist, no exec)" {
  run bash "$F" 'intake;touch FOPWNED'
  [ "$status" -eq 2 ]; [ ! -e FOPWNED ]
}
@test "panel --size non-numeric → exit 2" { run bash "$F" panel --size abc; [ "$status" -eq 2 ]; }
@test "SKILL/orchestrator codify budget-gated one-turn batch" {
  S="$BATS_TEST_DIRNAME/../../skills/auto-fanout/SKILL.md"
  grep -qiE "budget" "$S"; grep -qiE "one.turn|single turn|dispatch-batch|批发" "$S"
  T="$BATS_TEST_DIRNAME/../../agents/task-orchestrator.md"
  grep -qiE "fanout" "$T"
}
