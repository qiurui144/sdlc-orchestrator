#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/../.."
FIX="$ROOT/eval/fixtures"

@test "all 14 target agents have a fixture pair" {
  for a in spec-analyst dependency-auditor tester docs-curator releaser \
           architect pr-reviewer performance-analyst tech-debt-tracker cicd-designer \
           architecture-reviewer incident-responder codebase-reviewer task-orchestrator; do
    [ -d "$FIX/$a" ] || { echo "missing fixture dir: $a" >&2; return 1; }
    ls "$FIX/$a"/*.input.md >/dev/null 2>&1 || { echo "no .input.md for $a" >&2; return 1; }
    ls "$FIX/$a"/*.expect.yaml >/dev/null 2>&1 || { echo "no .expect.yaml for $a" >&2; return 1; }
  done
}

# v0.27.0 A3: the task-orchestrator behavioral fixture is the /sdlc:eval gate the G2 review
# required. Lock its grader contract deterministically (the LIVE N=3 run is separate, paid).
@test "task-orchestrator a3-spotcheck: grade.sh PASSES the good output" {
  run bash "$ROOT/eval/grade.sh" "$FIX/task-orchestrator/a3-spotcheck.good.out" \
                                 "$FIX/task-orchestrator/a3-spotcheck.expect.yaml"
  [ "$status" -eq 0 ]
}
@test "task-orchestrator a3-spotcheck: grade.sh FAILS the bad output (serial + spot-check-everything)" {
  run bash "$ROOT/eval/grade.sh" "$FIX/task-orchestrator/a3-spotcheck.bad.out" \
                                 "$FIX/task-orchestrator/a3-spotcheck.expect.yaml"
  [ "$status" -eq 1 ]
}
@test "task-orchestrator b-routing: grade.sh PASSES the good output (v0.28.0 B gate)" {
  run bash "$ROOT/eval/grade.sh" "$FIX/task-orchestrator/b-routing.good.out" \
                                 "$FIX/task-orchestrator/b-routing.expect.yaml"
  [ "$status" -eq 0 ]
}
@test "task-orchestrator b-routing: grade.sh FAILS the bad output (skips net / fast-paths HIGH)" {
  run bash "$ROOT/eval/grade.sh" "$FIX/task-orchestrator/b-routing.bad.out" \
                                 "$FIX/task-orchestrator/b-routing.expect.yaml"
  [ "$status" -eq 1 ]
}

@test "every expect.yaml is yq-parseable with >=1 assertion of a known kind" {
  for f in "$FIX"/*/*.expect.yaml; do
    n=$(yq '.assertions | length' "$f" 2>/dev/null) || { echo "unparseable: $f" >&2; return 1; }
    [ "$n" -ge 1 ] || { echo "no assertions: $f" >&2; return 1; }
    j=0
    while [ "$j" -lt "$n" ]; do
      k=$(yq -r ".assertions[$j].kind" "$f")
      case "$k" in
        all_present|any_present|count_at_least|llm_judge) : ;;
        *) echo "$f assertion[$j] unknown kind: $k" >&2; return 1 ;;
      esac
      j=$((j+1))
    done
  done
}
