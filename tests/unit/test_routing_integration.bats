#!/usr/bin/env bats
# M2 Task 7 — executor.sh wired into task-orchestrator. Safety assertions are
# one-vote-veto: judgment ops bypass the executor entirely (structural, closed map),
# the executor runs in MAIN context only, and off => byte-identical pre-M2 behavior.

ORCH="$BATS_TEST_DIRNAME/../../agents/task-orchestrator.md"
EVALCMD="$BATS_TEST_DIRNAME/../../commands/eval.md"
MAP="$BATS_TEST_DIRNAME/../../skills/model-router/task-type-map.yaml"
EXEC="$BATS_TEST_DIRNAME/../../skills/model-router/executor.sh"

@test "orchestrator wires executor.sh for mechanical ops" {
  run grep -E 'model-router/executor\.sh' "$ORCH"
  [ "$status" -eq 0 ]
}

@test "orchestrator: executor runs in MAIN context, never a dispatched subagent" {
  run grep -iE 'executor.*main context|main context.*executor' "$ORCH"
  [ "$status" -eq 0 ]
  run grep -iE 'never.*(inside|in) a dispatched subagent|dispatched (sub)?agents lack Bash' "$ORCH"
  [ "$status" -eq 0 ]
}

@test "orchestrator: judgment ops bypass the executor entirely" {
  run grep -iE 'judgment ops.*(never|bypass)|(never|bypass).*judgment' "$ORCH"
  [ "$status" -eq 0 ]
}

@test "orchestrator: exit 10 -> normal claude dispatch; exit 0 -> verified output used" {
  run grep -E 'exit 10' "$ORCH"
  [ "$status" -eq 0 ]
}

@test "orchestrator: SDLC_MULTI_MODEL unset -> executor never invoked (byte-identical pre-M2)" {
  run grep -iE 'SDLC_MULTI_MODEL.*(unset|off|default)' "$ORCH"
  [ "$status" -eq 0 ]
  run grep -iE 'byte-identical' "$ORCH"
  [ "$status" -eq 0 ]
}

@test "closed map structurally excludes every judgment op (one-vote-veto)" {
  for op in spec plan impl review threat release panel intake; do
    v="$(yq -r ".ops.\"$op\" // \"\"" "$MAP")"
    [ -z "$v" ] || { echo "judgment op '$op' found in closed map"; return 1; }
  done
}

@test "/sdlc:eval dispatches skills/model-eval/eval.sh for model-routing eval (cost-gated)" {
  run grep -E 'model-eval/eval\.sh' "$EVALCMD"
  [ "$status" -eq 0 ]
  run grep -iE 'cost|confirm|approval' "$EVALCMD"
  [ "$status" -eq 0 ]
}

# end-to-end golden: off => the executor declines instantly and leaves ZERO footprint
# (no --out, no circuit state) — the orchestrator's claude dispatch is untouched.
@test "e2e golden: off -> exit 10, route-claude-disabled, zero filesystem footprint" {
  TD="$(mktemp -d)"
  printf 'x\n' > "$TD/in"
  run env -u SDLC_MULTI_MODEL SDLC_CIRCUIT_DIR="$TD/circuit" "$EXEC" \
    --task-op inventory-count --input "$TD/in" --out "$TD/result"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q '^decision=route-claude-disabled$'
  [ ! -f "$TD/result" ]
  [ ! -d "$TD/circuit" ]
  rm -rf "$TD"
}
