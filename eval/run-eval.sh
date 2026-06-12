#!/usr/bin/env bash
# run-eval.sh — behavioral eval runner. Dispatches an agent's real prompt on each
# of its fixtures via headless `claude -p`, captures output, grades it with
# grade.sh, repeats N seeds, aggregates a pass-rate report.
#
# Usage:
#   run-eval.sh <agent> [--seeds N] [--case <case>] [--dry-run]
#   run-eval.sh --grade-only <output-file> <expect.yaml>
#
# DISPATCH (real LLM, human-triggered — NOT for CI):
#   claude -p "<fixture input>" --append-system-prompt "$(cat agents/<agent>.md)" \
#          --model <tier> --dangerously-skip-permissions
#
# bash-3.2-safe per tests/PORTABILITY.md.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
GRADE="$HERE/grade.sh"

# --- grade-only short-circuit (pure, no LLM) ---
if [ "${1:-}" = "--grade-only" ]; then
  "$GRADE" "${2:?need output}" "${3:?need expect}"
  exit $?
fi

agent="${1:?usage: run-eval.sh <agent> [--seeds N] [--case C] [--dry-run]}"
shift
seeds=3
only_case=""
dry_run=false
tiers_csv=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --seeds) seeds="${2:?}"; shift 2 ;;
    --case)  only_case="${2:?}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --tiers) tiers_csv="${2:?}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

agent_md="$ROOT/agents/$agent.md"
[ -f "$agent_md" ] || { echo "eval: unknown agent (no $agent_md)" >&2; exit 1; }

fix_dir="$ROOT/eval/fixtures/$agent"
[ -d "$fix_dir" ] || { echo "eval-no-fixture: no fixtures for $agent" >&2; exit 1; }

# model tier from frontmatter (awk extracts the --- … --- block; grep the field)
tier=$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' "$agent_md" \
        | grep -E '^model_tier:' | head -1 | awk '{print $2}')
[ -n "$tier" ] || { echo "eval: $agent has no model_tier" >&2; exit 1; }

ts=$(TZ='Asia/Shanghai' date '+%Y%m%d-%H%M%S')
runs="$ROOT/eval/runs/$ts-$agent"

# tiers to run: explicit --tiers list, else the agent's declared tier
if [ -n "$tiers_csv" ]; then
  run_tiers="$(printf '%s' "$tiers_csv" | tr ',' ' ')"
else
  run_tiers="$tier"
fi

pass=0; total=0
for inp in "$fix_dir"/*.input.md; do
  [ -f "$inp" ] || continue
  case="$(basename "$inp" .input.md)"
  [ -n "$only_case" ] && [ "$case" != "$only_case" ] && continue
  exp="$fix_dir/$case.expect.yaml"
  [ -f "$exp" ] || { echo "eval: $case has no expect.yaml" >&2; continue; }
  for rt in $run_tiers; do
    s=1; tpass=0
    while [ "$s" -le "$seeds" ]; do
      out="$runs/$case-$rt-seed$s.out"
      if $dry_run; then
        echo "DRY-RUN: claude -p \"<$case input>\" --append-system-prompt \"\$(cat agents/$agent.md)\" --model $rt --dangerously-skip-permissions > $out"
      else
        mkdir -p "$runs"
        claude -p "$(cat "$inp")" --append-system-prompt "$(cat "$agent_md")" \
          --model "$rt" --dangerously-skip-permissions > "$out" 2>"$out.err" \
          || echo "eval-dispatch-failed: $agent/$case/$rt/seed$s" >&2
        total=$((total+1))
        if "$GRADE" "$out" "$exp" >>"$runs/grade.log" 2>&1; then
          pass=$((pass+1)); tpass=$((tpass+1)); echo "PASS $agent/$case/$rt/seed$s"
        else
          echo "FAIL $agent/$case/$rt/seed$s (see $runs/grade.log)"
        fi
      fi
      s=$((s+1))
    done
    $dry_run || echo "TIER $agent/$case @ $rt: $tpass/$seeds"
  done
done

$dry_run && exit 0

rate="n/a"
[ "$total" -gt 0 ] && rate=$(awk "BEGIN{printf \"%.2f\", $pass/$total}")
echo "tier-matrix run complete for $agent. raw: $runs"
echo "EVAL $agent: $pass/$total seeds passed (rate $rate). raw: $runs"
# rate < 1.0 => flaky, not a robust PASS (per §2.3)
[ "$total" -gt 0 ] && [ "$pass" -eq "$total" ]
