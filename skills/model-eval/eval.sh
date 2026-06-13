#!/usr/bin/env bash
# eval.sh — offline behavioral eval for the M2 gate. Runs fixtures x providers x
# seeds, scores each output with grader.sh, applies the WORST-CASE compound gate,
# and emits config/model-allowlist.yaml (with sources_hash). The allowlist is the
# executor's gate: a task routes to deepseek only if it PASSED here.
#
# Usage:
#   eval.sh --task <t> --providers deepseek,claude,qwen --seeds 3 [--floor 0.85]
#           [--out config/model-allowlist.yaml] [--stub <dir>]
#   --stub <dir>: read each output from <dir>/<provider>/seed-<s>/case-<n>.out
#                 (no real LLM — for deterministic tests). Without --stub, call.sh.
#
# Gate (per spec §5): route deepseek IFF
#   every-seed mean >= floor  AND  std <= 0.05  AND  |ds_mean - claude_mean| <= 0.10
#   AND claude_mean >= floor (else task_reliability=low, never route).
# bash-3.2-safe; shellcheck -x clean; SE16-safe.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$HERE/../.." && pwd -P)"
GRADER="$HERE/grader.sh"
MODES="${SDLC_GRADER_MODES:-$HERE/grader-modes.yaml}"
CALL="$ROOT/skills/model-provider/call.sh"

die() { echo "eval: $*" >&2; exit 2; }

task="" providers="" seeds=3 floor="0.85" out="$ROOT/config/model-allowlist.yaml" stub="" claude_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) task="$2"; shift 2;;
    --providers) providers="$2"; shift 2;;
    --seeds) seeds="$2"; shift 2;;
    --floor) floor="$2"; shift 2;;
    --out) out="$2"; shift 2;;
    --stub) stub="$2"; shift 2;;
    --claude-dir) claude_dir="$2"; shift 2;;  # harness-produced claude baseline (rule H: claude has no call.sh backend)
    *) die "unknown arg: $1";;
  esac
done
if [ -z "$task" ] || [ -z "$providers" ]; then die "usage: --task <t> --providers <list> [--seeds N] [--floor F] [--stub dir] [--claude-dir dir]"; fi

fixdir="$HERE/fixtures/$task"
[ -d "$fixdir" ] || die "no fixtures for task '$task' at $fixdir"
prompt_file="$(yq -r ".\"$task\".prompt_file // \"\"" "$MODES")"
live_gradable="$(yq -r ".\"$task\".live_gradable // false" "$MODES")"

# sources_hash binds the allowlist entry to (fixtures + grader + modes + prompt_file).
hash_inputs() {
  local files=""
  for f in "$fixdir"/*.json; do files="$files $f"; done
  # shellcheck disable=SC2086
  "$GRADER" hash $files "$GRADER" "$MODES" "$ROOT/$prompt_file"
}
sources_hash="$(hash_inputs)"

# score one (provider, seed) over all fixtures -> mean score, via stub or call.sh.
seed_mean() {
  local provider="$1" seed="$2" sum=0 n=0 td out_f score
  td="$(mktemp -d)"
  for f in "$fixdir"/*.json; do
    n=$((n+1))
    jq -r '.input'  "$f" > "$td/in"
    jq -r '.golden' "$f" > "$td/gold"
    local case_id; case_id="$(basename "$f" .json)"
    out_f="$td/out"
    if [ "$provider" = claude ] && [ -n "$claude_dir" ]; then
      # claude baseline = harness-produced outputs (claude IS the SDLC harness; no call.sh
      # backend per global rule H). Deterministic -> seed-independent (one file per case).
      if [ -f "$claude_dir/$case_id.out" ]; then cp "$claude_dir/$case_id.out" "$out_f"; else : > "$out_f"; fi
    elif [ -n "$stub" ]; then
      local sf="$stub/$provider/seed-$seed/$case_id.out"
      if [ -f "$sf" ]; then cp "$sf" "$out_f"; else : > "$out_f"; fi
    elif [ "$provider" = claude ]; then
      die "claude has no call.sh backend (rule H); supply --claude-dir <dir> or --stub <dir>"
    else
      # real path (Task 4): the SHARED task prompt (grader build-messages) + plain-text mode,
      # so the eval F1 represents EXACTLY what executor.sh sends when it routes this task.
      "$GRADER" build-messages --task "$task" --input "$td/in" > "$td/msgs.json" 2>/dev/null || : > "$td/msgs.json"
      if ! "$CALL" --provider "$provider" --messages "$td/msgs.json" --format text > "$out_f" 2>/dev/null; then
        : > "$out_f"
      fi
    fi
    score="$("$GRADER" --task "$task" --output "$out_f" --golden "$td/gold" | sed 's/score=//')"
    sum="$(awk -v s="$sum" -v x="$score" 'BEGIN{printf "%.6f", s+x}')"
  done
  rm -rf "$td"
  awk -v s="$sum" -v n="$n" 'BEGIN{ if(n==0){print "0.0000"} else printf "%.4f", s/n }'
}

# aggregate seed means -> mean, std(population), worst(min)
agg() { awk '{x[NR]=$1; s+=$1} END{ n=NR; m=s/n;
  for(i=1;i<=n;i++){d=x[i]-m; ss+=d*d}; sd=sqrt(ss/n);
  w=x[1]; for(i=2;i<=n;i++) if(x[i]<w) w=x[i];
  printf "%.4f %.4f %.4f", m, sd, w }'; }

declare_stats() {  # provider -> "mean std worst" (also exposes worst seed for gate)
  local provider="$1" s means=""
  for s in $(seq 1 "$seeds"); do means="$means$(seed_mean "$provider" "$s")
"; done
  printf '%s' "$means" | grep -v '^$' | agg
}

claude_mean=""
ds_mean=""; ds_std=""; ds_worst=""
IFS=',' read -r -a plist <<EOF
$providers
EOF
echo "task=$task floor=$floor seeds=$seeds"
for p in "${plist[@]}"; do
  read -r m sd w <<EOF
$(declare_stats "$p")
EOF
  echo "provider=$p f1=$m std=$sd worst=$w"
  [ "$p" = "claude" ] && claude_mean="$m"
  if [ "$p" = "deepseek" ]; then ds_mean="$m"; ds_std="$sd"; ds_worst="$w"; fi
done

# --- compound worst-case gate ---
reliability="ok"
passed="false"
chosen="claude"
if [ -n "$claude_mean" ] && awk -v c="$claude_mean" -v f="$floor" 'BEGIN{exit !(c<f)}'; then
  reliability="low"   # claude itself below floor -> task unreliable, never route
fi
if [ "$reliability" = "ok" ] && [ -n "$ds_mean" ] && [ "$live_gradable" = "true" ]; then
  if awk -v dm="$ds_mean" -v dw="$ds_worst" -v ds="$ds_std" -v cm="$claude_mean" -v f="$floor" 'BEGIN{
        gap = dm-cm; if(gap<0) gap=-gap;
        exit !(dw>=f && ds<=0.05 && gap<=0.10 && cm>=f) }'; then
    passed="true"; chosen="deepseek"
  fi
fi

mkdir -p "$(dirname "$out")"
{
  echo "version: 1"
  echo "tasks:"
  echo "  $task:"
  echo "    provider: $chosen"
  echo "    f1: ${ds_mean:-null}"
  echo "    claude_f1: ${claude_mean:-null}"
  echo "    passed: $passed"
  echo "    task_reliability: $reliability"
  echo "    live_gradable: $live_gradable"
  echo "    sources_hash: $sources_hash"
} > "$out"
echo "allowlist=$out passed=$passed provider=$chosen reliability=$reliability"
exit 0
