#!/usr/bin/env bats
# test_intake_spine_e2e.bats — deterministic plan→emit→consolidate spine e2e
#
# Exercises intake-consolidation/{plan.sh,emit-subreport.sh,consolidate.sh}
# together as the orchestrator would, WITHOUT any LLM, by simulating sub-agent
# verdicts. Guards the contract between the 3 scripts.

SK="$BATS_TEST_DIRNAME/../../skills/intake-consolidation"

@test "spine: plan(standard) → emit each dim → consolidate → scorecard has all planned dims" {
  work=$(mktemp -d); trap "rm -rf $work" EXIT
  # 1. plan
  "$SK/plan.sh" --depth standard > "$work/plan.txt"
  [ "$(wc -l < "$work/plan.txt" | tr -d ' ')" -eq 8 ]   # deps/debt/docs/disk/secrets/review/threat/perf (secrets added v0.21)
  # 2. emit a normalized sub-report per planned dim (simulate sub-agent verdicts)
  while IFS=$'\t' read -r dim tier paid scope; do
    v=PASS; [ "$dim" = deps ] && v=BLOCK
    "$SK/emit-subreport.sh" "$work/2026-06-01_${dim}.md" "$dim" "$v" 0.8 "synthetic ${dim}"
  done < "$work/plan.txt"
  # 3. consolidate
  run "$SK/consolidate.sh" "$work" "$work/health.md"
  [ "$status" -eq 0 ]
  grep -q '## Overall verdict: AT-RISK' "$work/health.md"   # deps=BLOCK dominates
  for d in deps debt docs disk secrets review threat perf; do
    grep -q "| $d |" "$work/health.md"
  done
}
