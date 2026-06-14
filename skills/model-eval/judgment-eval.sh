#!/usr/bin/env bash
# judgment-eval.sh — C-2 offline eligibility evaluator (simplified single-phase architecture).
#
# Four gates, one-vote-veto, before an op enters the draft-verify-allowlist:
#   Gate 1 judge_confidence: cross-provider (claude+qwen, NOT deepseek) panel score >= floor.
#   Gate 2 human_checked:    explicit --human-checked flag (manual gate; no auto-pass).
#   Gate 3 net_savings:      probe-inclusive token savings >= min_net_savings.
#   Gate 4 tco_ok:           explicit --tco-ok flag (manual TCO gate).
#
# Note: lib_valid and recall gates from the two-phase draft-verify design are removed.
# The single-phase route architecture relies on offline judge_confidence + human sign-off
# instead of runtime injected-defect recall.
#
# Usage:
#   judgment-eval.sh --op <op> --task <task_type>
#     --judge-confidence <float>
#     --net-savings <int>
#     [--human-checked] [--tco-ok]
#     [--judge-floor <f>] [--min-net-savings <n>]
#     [--allowlist <f>] [--dry-run]
#
# Exit: 0 = eligible (all gates pass); 1 = not eligible; 2 = usage error.
# bash-3.2-safe; shellcheck -x clean.
set -uo pipefail

die() { echo "judgment-eval: $*" >&2; exit 2; }

op="" task="" judge_conf="" net_sav="" human_checked=0 tco_ok=0
judge_floor=0.7 min_net_sav=10 allowlist="" dry_run=0

while [ "$#" -gt 0 ]; do case "$1" in
  --op)              op="$2"; shift 2;;
  --task)            task="$2"; shift 2;;
  --judge-confidence) judge_conf="$2"; shift 2;;
  --net-savings)     net_sav="$2"; shift 2;;
  --human-checked)   human_checked=1; shift;;
  --tco-ok)          tco_ok=1; shift;;
  --judge-floor)     judge_floor="$2"; shift 2;;
  --min-net-savings) min_net_sav="$2"; shift 2;;
  --allowlist)       allowlist="$2"; shift 2;;
  --dry-run)         dry_run=1; shift;;
  *) die "unknown arg: $1";;
esac; done

{ [ -n "$op" ] && [ -n "$task" ] && [ -n "$judge_conf" ] && [ -n "$net_sav" ]; } \
  || die "required: --op --task --judge-confidence --net-savings"

# float >= comparison (SE16-safe: no pipe)
fge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0>=b+0)}'; }

eligible=1 reason=""

fail() { eligible=0; reason="${reason:-$1}"; echo "gate=$1 status=fail"; }
pass() { echo "gate=$1 status=pass"; }

# Gate 1: judge_confidence (cross-provider panel — claude+qwen, never deepseek)
if fge "$judge_conf" "$judge_floor"; then pass "judge-confidence"; else fail "judge-confidence-fail"; fi

# Gate 2: human_checked (manual, no auto-pass)
if [ "$human_checked" -eq 1 ]; then pass "human-checked"; else fail "human-checked-fail"; fi

# Gate 3: net_savings (probe-inclusive, integer comparison)
if [ "${net_sav:-0}" -ge "$min_net_sav" ]; then pass "net-savings"; else fail "net-savings-fail"; fi

# Gate 4: tco_ok (manual TCO gate)
if [ "$tco_ok" -eq 1 ]; then pass "tco-ok"; else fail "tco-fail"; fi

if [ "$eligible" -eq 1 ]; then
  echo "eligible=true"
else
  echo "eligible=false reason=$reason"
fi

# Write allowlist only when eligible and not dry-run
if [ "$eligible" -eq 0 ] || [ "$dry_run" -eq 1 ] || [ -z "$allowlist" ]; then
  exit "$((1 - eligible))"
fi

# Initialize allowlist if it doesn't exist
if [ ! -f "$allowlist" ]; then
  printf 'version: 1\nops: {}\n' > "$allowlist"
fi

# Write the op entry (env() pattern; tonumber for floats)
OP="$op" TASK="$task" CONF="$judge_conf" NET="$net_sav" \
  yq -i '.ops[env(OP)] = {
    "passed": true,
    "task_type": env(TASK),
    "judge_confidence": env(CONF)|tonumber,
    "human_checked": true,
    "net_savings": env(NET)|tonumber,
    "tco_ok": true
  }' "$allowlist"

exit 0
