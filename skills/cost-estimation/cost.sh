#!/usr/bin/env bash
# cost.sh — estimate the token + USD cost of a phase or full sprint at current model
# tiers. Pure deterministic, zero-LLM. ESTIMATE only (prices/token-counts approximate).
# Usage: cost.sh [--phase <name> | --sprint] [<repo-root>]
#   exit 0 = estimate printed (exit 2 only if over budget AND budget_strict)
# Env (for tests / overrides):
#   SDLC_PRICING_FILE, SDLC_COST_MODEL_FILE, SDLC_TOKEN_BUDGET, SDLC_BUDGET_STRICT
# POSIX / bash-3.2-safe per tests/PORTABILITY.md (no realpath, no date -d).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
PLUGIN_ROOT="$(cd "$HERE/../.." && pwd -P)"

mode="sprint"; phase=""
for a in "$@"; do
  case "$a" in
    --phase) mode="phase" ;;
    --sprint) mode="sprint" ;;
    --phase=*) mode="phase"; phase="${a#--phase=}" ;;
    *) if [ "$mode" = "phase" ] && [ -z "$phase" ]; then phase="$a"; fi ;;
  esac
done
# support "--phase spec" (space form)
if [ "$mode" = "phase" ] && [ -z "$phase" ]; then
  prev=""
  for a in "$@"; do [ "$prev" = "--phase" ] && phase="$a"; prev="$a"; done
fi

pricing="${SDLC_PRICING_FILE:-$PLUGIN_ROOT/config/pricing.yaml}"
model="${SDLC_COST_MODEL_FILE:-$PLUGIN_ROOT/config/cost-model.yaml}"

# pricing (fallback if missing)
pfallback=""
if [ -f "$pricing" ]; then
  as_of="$(yq -r '.as_of' "$pricing" 2>/dev/null || echo unknown)"
  price_in()  { yq -r ".tiers.$1.input"  "$pricing"; }
  price_out() { yq -r ".tiers.$1.output" "$pricing"; }
else
  echo "cost-no-pricing: $pricing missing — using fallback prices"
  as_of="fallback"
  price_in()  { case "$1" in opus) echo 15;; sonnet) echo 3;; haiku) echo 0.8;; *) echo 5;; esac; }
  price_out() { case "$1" in opus) echo 75;; sonnet) echo 15;; haiku) echo 4;; *) echo 25;; esac; }
  pfallback="(fallback prices)"
fi

# phase → agent(s)
agents_for() {
  case "$1" in
    spec)    echo spec-analyst ;;
    plan)    echo architect ;;
    impl)    echo implementer ;;
    review)  echo pr-reviewer ;;
    test)    echo tester ;;
    release) echo releaser ;;
    *)       echo "" ;;
  esac
}

if [ "$mode" = "phase" ]; then
  agent_list="$(agents_for "$phase")"
  [ -n "$agent_list" ] || { echo "cost: unknown phase '$phase' (spec|plan|impl|review|test|release)" >&2; exit 1; }
else
  agent_list="spec-analyst architect implementer pr-reviewer tester releaser"
fi

tier_of() {  # read model_tier from agent frontmatter
  awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' "$PLUGIN_ROOT/agents/$1.md" 2>/dev/null \
    | grep -E '^model_tier:' | head -1 | awk '{print $2}'
}

echo "Cost estimate ($mode${phase:+ $phase}) — ESTIMATE, prices as_of $as_of $pfallback"
total_tok=0
total_usd="0"
for ag in $agent_list; do
  tier="$(tier_of "$ag")"; [ -n "$tier" ] || tier=sonnet
  ti="$(yq -r ".\"$ag\".input // 6000"  "$model" 2>/dev/null)"; case "$ti" in ''|null) ti=6000 ;; esac
  to="$(yq -r ".\"$ag\".output // 4000" "$model" 2>/dev/null)"; case "$to" in ''|null) to=4000 ;; esac
  pi="$(price_in "$tier")"; po="$(price_out "$tier")"
  usd="$(awk "BEGIN{printf \"%.2f\", ($ti*$pi + $to*$po)/1000000}")"
  tok=$((ti + to))
  total_tok=$((total_tok + tok))
  total_usd="$(awk "BEGIN{printf \"%.2f\", $total_usd + $usd}")"
  printf "  %-22s %-7s %6sK in + %5sK out  = \$%s\n" "$ag" "$tier" "$((ti/1000))" "$((to/1000))" "$usd"
done

printf "  TOTAL: ~%sK tokens = \$%s\n" "$((total_tok/1000))" "$total_usd"

# budget
budget="${SDLC_TOKEN_BUDGET:-}"
strict="${SDLC_BUDGET_STRICT:-}"
if [ -n "$budget" ]; then
  if [ "$total_tok" -gt "$budget" ]; then
    echo "  Budget: $budget tokens — OVER by $((total_tok - budget)) (over budget)"
    [ -n "$strict" ] && { echo "cost-over-budget: budget_strict set — blocking" >&2; exit 2; }
  else
    echo "  Budget: $budget tokens — within."
  fi
fi
exit 0
