#!/usr/bin/env bash
# route.sh — deterministic risk->provider router (M1). ZERO-LLM. Reads risk-classify tier + a
# conservative config/model-routing.yaml; decides which provider/model a task routes to.
# DEFAULT: disabled => claude for everything (opt-in via config enabled:true or SDLC_MULTI_MODEL=1).
# Runs in MAIN context. bash 3.2-safe. SE16-safe (case/grep -c, no early-pipe-close control flow).
# Usage: route.sh (--tier T --model-class M | --staged | --names <f>) [--config <yaml>]
#   stdout (single kv line): tier=<T> model_class=<M> provider=<p> model=<id> reason=<kebab>
#   exit: 0 always (a decision is always made; uncertainty resolves to claude/HIGH).
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

tier="" mclass="" mode="explicit" names_file="" cfg="$HERE/../../config/model-routing.yaml"
while [ "$#" -gt 0 ]; do case "$1" in
  --tier) tier="$2"; shift 2;;
  --model-class) mclass="$2"; shift 2;;
  --staged) mode="staged"; shift;;
  --names) mode="names"; names_file="$2"; shift 2;;
  --config) cfg="$2"; shift 2;;
  *) echo "route-bad-arg: $1" >&2; exit 0;;   # never hard-fail a routing decision
esac; done

emit() { echo "tier=$1 model_class=$2 provider=$3 model=$4 reason=$5"; exit 0; }

# read one scalar key from the yaml (bash 3.2-safe; value-only, strips quotes/comment)
cfg_get() {  # $1=key -> value or empty
  [ -f "$cfg" ] || return 1
  awk -v k="^$1:" '$0 ~ k {sub(/^[^:]*:[[:space:]]*/,""); sub(/[[:space:]]*#.*$/,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}' "$cfg"
}

# opt-in gate: SDLC_MULTI_MODEL=1 (env wins) OR config enabled:true. Anything else => disabled.
enabled=0
case "${SDLC_MULTI_MODEL:-}" in 1) enabled=1;; esac
if [ "$enabled" -eq 0 ]; then case "$(cfg_get enabled)" in true) enabled=1;; esac; fi
[ "$enabled" -eq 1 ] || emit "${tier:-NORMAL}" "${mclass:-per-agent}" claude "" multi-model-disabled

# resolve tier when not given explicitly (run risk-classify; exit 2 => HIGH fail-safe)
if [ "$mode" != "explicit" ] || [ -z "$tier" ]; then
  rc_args=""; case "$mode" in staged) rc_args="--staged";; names) rc_args="--names $names_file";; esac
  # shellcheck disable=SC2086  # intentional split of the (controlled) risk-classify args
  rc_line="$("$HERE/../risk-classify/risk-classify.sh" $rc_args 2>/dev/null)"; rc_rc=$?
  if [ "$rc_rc" -ne 0 ] || [ -z "$rc_line" ]; then tier=HIGH; mclass=judgment
  else
    tier="$(printf '%s' "$rc_line" | sed -n 's/.*risk_tier=\([A-Z]*\).*/\1/p')"
    mclass="$(printf '%s' "$rc_line" | sed -n 's/.*model_class=\([a-z-]*\).*/\1/p')"
  fi
fi

case "$tier" in
  LOW)    lp="$(cfg_get low_provider)"
          [ -n "$lp" ] || emit LOW "${mclass:-mechanical}" claude "" low-provider-unset-fallback-claude
          emit LOW "${mclass:-mechanical}" "$lp" "$(cfg_get low_model)" low-mechanical-externalized;;
  NORMAL) emit NORMAL "${mclass:-per-agent}" claude "" normal-default-claude;;
  HIGH)   emit HIGH "${mclass:-judgment}" claude "" high-never-externalized;;
  *)      emit HIGH judgment claude "" uncertain-tier-to-claude;;
esac
