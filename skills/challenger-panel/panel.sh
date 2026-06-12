#!/usr/bin/env bash
# panel.sh — Challenger Panel: N experts × lenses vote on one artifact → consensus.
# Reuses eval/judge.sh parse_verdict (source-guarded). bash-3.2-safe per PORTABILITY.md.
# Replaces "single Challenger + always pause" with multi-lens vote + consensus-auto.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=eval/judge.sh
. "$HERE/../../eval/judge.sh"   # parse_verdict (no CLI runs when sourced)

consensus() {  # --votes-dir D [--high-risk yes|no] [--threshold T]
  local dir="" high="no" thr="4.0"
  while [ "$#" -gt 0 ]; do case "$1" in
    --votes-dir) dir="$2"; shift 2;; --high-risk) high="$2"; shift 2;;
    --threshold) thr="$2"; shift 2;; *) shift;; esac; done
  local pass=0 fail=0 total=0 sum=0 f rc sc
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    parse_verdict "$f" >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 2 ] && continue                     # malformed vote: skip
    sc=$(grep -iE '^[[:space:]]*SCORE:' "$f" | head -1 | sed 's/[^0-9.]//g'); [ -z "$sc" ] && sc=0
    total=$((total+1)); sum=$(awk -v s="$sum" -v x="$sc" 'BEGIN{print s+x}')
    if [ "$rc" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
  done
  if [ "$total" -eq 0 ]; then
    echo "decision=ESCALATE pass_votes=0 total=0 mean=0 reason=all-malformed"; return 2; fi
  local mean; mean=$(awk -v s="$sum" -v t="$total" 'BEGIN{printf "%.2f", s/t}')
  if [ "$high" = "yes" ]; then
    echo "decision=ESCALATE pass_votes=$pass total=$total mean=$mean reason=high-risk-always-escalate"; return 1; fi
  local maj=0 mok=0
  [ $((pass*2)) -ge "$total" ] && maj=1
  awk -v m="$mean" -v t="$thr" 'BEGIN{exit !(m>=t)}' && mok=1
  if [ "$maj" -eq 1 ] && [ "$mok" -eq 1 ]; then
    echo "decision=AUTO_ADVANCE pass_votes=$pass total=$total mean=$mean reason=consensus"; return 0
  else
    echo "decision=ESCALATE pass_votes=$pass total=$total mean=$mean reason=no-consensus"; return 1
  fi
}

dispatch() {  # --artifact P --handoff Y → prints high_risk/size/lenses for the orchestrator
  local art="" ho=""
  while [ "$#" -gt 0 ]; do case "$1" in
    --artifact) art="$2"; shift 2;; --handoff) ho="$2"; shift 2;; *) shift;; esac; done
  local risk=no size="${SDLC_PANEL_SIZE:-3}"
  # Four high-risk classes (spec §3.3) → escalate to size 5. Bias toward over-escalation stays:
  # the broad `pos` patterns all trigger. high_risk=no does NOT mean "skip review" — it means a
  # normal size-3 panel (still incl. a security lens), so a calibration miss is bounded, not unsafe.
  # We first drop lines that are PROVABLY wrong-sense — the recurring false positives: the benign
  # secret-handling form `${{ secrets.X }}` / `your-key-here`, LLM "token budget/cost", "handoff
  # schema", "no migration / non-breaking". (bare `auth` was dropped from `pos` so "author" no
  # longer matches — no line-strip needed for it.) `grep -c` reads to EOF so it never closes the
  # pipe early → no SIGPIPE under `pipefail` (SE16; see tests/PORTABILITY.md).
  local neg='secrets\.[a-z_]|\$\{\{[[:space:]]*secrets|your-key-here|test-pass-not-real|fake_key_for_test|placeholder|<api_key>|<secret>|(llm|technical|prompt|completion|input|output|context)[ _-]*token|token[ _-]*(cost|budget|count|usage|limit|window|estimate)|handoff[ _-]*schema|json[ _-]*schema|schema[ _-]*(version|valid)|no[ _-]+migration|migration[ _:-]*(none|n/a|not[ ]needed)|non-breaking'
  local pos='secret|password|credential|api[_-]?key|authentication|authorization|oauth|token|schema|migration|breaking|irreversible|prod.*deploy|force.*push|drop[ ]+table|stride|spoofing|tampering|repudiation|elevation'
  local a="${art:-/dev/null}" h="${ho:-/dev/null}" hits=0
  hits=$(grep -ihvE "$neg" "$a" "$h" 2>/dev/null | grep -icE "$pos") || hits=0
  if [ "${hits:-0}" -gt 0 ]; then
    risk=yes; size="${SDLC_PANEL_HIGH_RISK_SIZE:-5}"
  fi
  echo "high_risk=$risk size=$size lenses=correctness,security,scope,rubric,performance"
}

case "${1:-}" in
  --consensus) shift; consensus "$@";;
  --dispatch)  shift; dispatch "$@";;
  *) echo "usage: panel.sh --dispatch --artifact <p> --handoff <y> | --consensus --votes-dir <d> [--high-risk yes|no] [--threshold T]" >&2; exit 2;;
esac
