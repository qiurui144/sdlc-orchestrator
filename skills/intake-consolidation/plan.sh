#!/usr/bin/env bash
# plan.sh — deterministic intake dimension planner.
# Usage: plan.sh --depth <light|standard|deep> [--only <csv>]
# stdout (tab-separated), registry order, one per line: dim<TAB>tier<TAB>paid<TAB>scope
# exit 0 ok; 2 bad input (bad-depth / unknown-dimension / dim-needs-deeper-depth / bad-arg).
set -uo pipefail

# registry: dim|tier|paid|min_depth_rank   (light=1 standard=2 deep=3)
REGISTRY="deps|haiku|free|1
debt|haiku|free|1
docs|haiku|free|1
disk|haiku|free|1
secrets|haiku|free|1
review|sonnet|paid|2
threat|opus|paid|2
perf|sonnet|paid|2"

depth=""; only=""
while [ $# -gt 0 ]; do
  case "$1" in
    --depth) depth="${2:-}"; shift 2 ;;
    --only)  only="${2:-}";  shift 2 ;;
    *) echo "plan: unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$depth" in
  light) rank=1 ;; standard) rank=2 ;; deep) rank=3 ;;
  *) echo "plan: --depth must be light|standard|deep (got '${depth}')" >&2; exit 2 ;;
esac

# Normalize --only: strip all whitespace so "deps, debt" == "deps,debt"
only="$(printf '%s' "$only" | tr -d '[:space:]')"

if [ -n "$only" ]; then
  IFS=',' read -ra want <<< "$only"
  for w in "${want[@]}"; do
    line=$(printf '%s\n' "$REGISTRY" | awk -F'|' -v d="$w" '$1==d{print}')
    if [ -z "$line" ]; then
      valid=$(printf '%s\n' "$REGISTRY" | awk -F'|' 'NF{printf "%s ",$1}')
      echo "plan: unknown-dimension: $w (valid: $valid)" >&2; exit 2
    fi
    minr=$(printf '%s\n' "$line" | awk -F'|' '{print $4}')
    if [ "$minr" -gt "$rank" ]; then
      need=$([ "$minr" -ge 3 ] && echo deep || echo standard)
      echo "plan: dimension '$w' requires --depth >= $need" >&2; exit 2
    fi
  done
fi

printf '%s\n' "$REGISTRY" | while IFS='|' read -r dim tier paid minr; do
  [ -n "$dim" ] || continue
  [ "$minr" -le "$rank" ] || continue
  if [ -n "$only" ]; then
    case ",$only," in *",$dim,"*) : ;; *) continue ;; esac
  fi
  if [ "$paid" = "paid" ]; then
    scope=$([ "$rank" -ge 3 ] && echo full || echo sampled)
  else
    scope=full
  fi
  printf '%s\t%s\t%s\t%s\n' "$dim" "$tier" "$paid" "$scope"
done
