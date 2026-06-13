#!/usr/bin/env bash
# executor.sh — the M2 online routing decision engine (runs in MAIN context;
# dispatched subagents have no Bash). For ONE SDLC op it decides: route to deepseek
# (only if the closed map + allowlist + sources_hash + online correctness oracle all
# pass) or fall back to claude. Any failure degrades to claude — a weak-model output
# never reaches the main line unverified.
#
# Usage:
#   executor.sh --task-op <op> --input <f> [--out <f>]
#               [--allowlist <f>] [--stub-output <f>] [--telemetry <f>]
# Decision (stdout last line): decision=<kebab>. Exit 0 = deepseek output written to
# --out (use it); exit 10 = caller must do the normal claude dispatch.
#
# kebab decisions: route-deepseek-ok | route-claude-disabled | route-claude-no-tasktype
#   | route-claude-not-allowlisted | route-claude-stale-hash | route-claude-breaker-open
#   | degrade-claude-call-failed | degrade-claude-online-grade-fail
# bash-3.2-safe; shellcheck -x clean; SE16-safe.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$HERE/../.." && pwd -P)"
GRADER="$ROOT/skills/model-eval/grader.sh"
MODES="${SDLC_GRADER_MODES:-$ROOT/skills/model-eval/grader-modes.yaml}"
MAP="${SDLC_TASKTYPE_MAP:-$HERE/task-type-map.yaml}"
CALL="$ROOT/skills/model-provider/call.sh"

die() { echo "executor: $*" >&2; exit 2; }

op="" input="" out="" allowlist="$ROOT/config/model-allowlist.yaml" stub_output="" telemetry=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --task-op) op="$2"; shift 2;;
    --input) input="$2"; shift 2;;
    --out) out="$2"; shift 2;;
    --allowlist) allowlist="$2"; shift 2;;
    --stub-output) stub_output="$2"; shift 2;;
    --telemetry) telemetry="$2"; shift 2;;
    *) die "unknown arg: $1";;
  esac
done
if [ -z "$op" ] || [ -z "$input" ]; then die "usage: --task-op <op> --input <f> [--out <f>]"; fi

# Hard absolute online-oracle floor: the acceptance bar is never lowered below this,
# regardless of the allowlist's stored f1 (a forged/poisoned f1 cannot collapse the
# oracle — G3 C-1). 0.75 = default eval floor 0.85 − the 0.10 online tolerance.
ONLINE_HARD_FLOOR="${SDLC_ONLINE_HARD_FLOOR:-0.75}"

emit() {  # emit <decision> <exit>
  local decision="$1" code="$2"
  if [ -n "$telemetry" ]; then
    mkdir -p "$(dirname "$telemetry")"
    printf '{"op":"%s","decision":"%s","degraded":%s}\n' \
      "$op" "$decision" "$([ "$code" -eq 0 ] && echo false || echo true)" >> "$telemetry"
  fi
  echo "decision=$decision"
  exit "$code"
}

# 0. global opt-in gate (default off -> always claude, zero behavior change). Exits
#    BEFORE any side effect, incl. telemetry — disabled = byte-identical, zero footprint.
if [ "${SDLC_MULTI_MODEL:-0}" != "1" ]; then echo "decision=route-claude-disabled"; exit 10; fi

# 1. CLOSED map: judgment/unknown ops have NO task_type -> claude (structural, C-2).
#    Reject any op that isn't a plain kebab token first, so it can never be spliced
#    into the yq query as an expression (I-1 yq-injection).
case "$op" in
  ''|*[!a-z0-9-]*) emit route-claude-no-tasktype 10;;
esac
task_type="$(yq -r ".ops.\"$op\" // \"\"" "$MAP" 2>/dev/null)"
[ -n "$task_type" ] || emit route-claude-no-tasktype 10

# 2. allowlist: must be passed AND carry a numerically-sane f1 in [0,1]. A
#    non-numeric / out-of-range f1 is a corrupt or forged entry -> not allowlisted.
[ -f "$allowlist" ] || emit route-claude-not-allowlisted 10
passed="$(yq -r ".tasks.\"$task_type\".passed // false" "$allowlist" 2>/dev/null)"
[ "$passed" = "true" ] || emit route-claude-not-allowlisted 10
stored_f1="$(yq -r ".tasks.\"$task_type\".f1 // \"\"" "$allowlist" 2>/dev/null)"
case "$stored_f1" in
  ''|*[!0-9.]*|*.*.*) emit route-claude-not-allowlisted 10;;  # empty / non-numeric / multi-dot
esac
awk -v v="$stored_f1" 'BEGIN{ exit !(v+0==v && v>=0 && v<=1) }' || emit route-claude-not-allowlisted 10

# 3. sources_hash must match the LIVE hash (stale eval after a prompt/fixture change -> claude, C-3).
prompt_file="$(yq -r ".\"$task_type\".prompt_file // \"\"" "$MODES")"
fixdir="$ROOT/skills/model-eval/fixtures/$task_type"
live_files=""
for f in "$fixdir"/*.json; do live_files="$live_files $f"; done
# shellcheck disable=SC2086
live_hash="$("$GRADER" hash $live_files "$GRADER" "$MODES" "$ROOT/$prompt_file" 2>/dev/null)"
stored_hash="$(yq -r ".tasks.\"$task_type\".sources_hash // \"\"" "$allowlist" 2>/dev/null)"
if [ -z "$stored_hash" ] || [ "$stored_hash" != "$live_hash" ]; then emit route-claude-stale-hash 10; fi

# 3b. circuit-breaker: rolling last-20 online grades; > 30% fails (i.e. > 6/20) ->
#     auto-disable this task_type until a re-eval rotates sources_hash (which resets
#     the window). Denominator is bounded at 20, so a transient single fail never trips.
circuit_dir="${SDLC_CIRCUIT_DIR:-runs/.circuit-state}"
circuit_state="$circuit_dir/$task_type.json"
window="[]"
if [ -f "$circuit_state" ]; then
  state_hash="$(jq -r '.sources_hash // ""' "$circuit_state" 2>/dev/null)"
  if [ "$state_hash" = "$live_hash" ]; then
    window="$(jq -c '.window // []' "$circuit_state" 2>/dev/null)" || window="[]"
  fi
fi
fails="$(printf '%s' "$window" | jq '[.[-20:][] | select(. == 1)] | length' 2>/dev/null)" || fails=0
if [ "${fails:-0}" -gt 6 ]; then emit route-claude-breaker-open 10; fi

record() {  # record <0|1> — append an online-grade outcome, keep the last 20
  mkdir -p "$circuit_dir"
  printf '%s' "$window" | jq -c --argjson o "$1" --arg h "$live_hash" \
    '{sources_hash: $h, window: ((. + [$o]) | .[-20:])}' > "$circuit_state" 2>/dev/null || true
}

# 4. call deepseek with the shared build-messages prompt (plain-text mode).
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
ds_out="$work/out"
if [ -n "$stub_output" ]; then
  cp "$stub_output" "$ds_out"
else
  # SAME prompt as eval (grader build-messages) + plain-text mode, so the routed deepseek
  # output is drawn from exactly the distribution the allowlist F1 was measured on.
  "$GRADER" build-messages --task "$task_type" --input "$input" > "$work/msgs.json" 2>/dev/null \
    || emit degrade-claude-call-failed 10
  if ! "$CALL" --provider deepseek --messages "$work/msgs.json" --format text > "$ds_out" 2>/dev/null; then
    emit degrade-claude-call-failed 10
  fi
fi

# 5. ONLINE correctness oracle: re-grade the LIVE output against the input-derived
#    expected. The acceptance bar = max(stored_f1 - 0.10, ONLINE_HARD_FLOOR) — the
#    hard floor means a forged/poisoned f1 can never collapse the bar (C-1).
score="$("$GRADER" --task "$task_type" --output "$ds_out" --derive "$input" 2>/dev/null | sed 's/score=//')"
case "$score" in ''|*[!0-9.]*|*.*.*) score="0.000";; esac
if ! awk -v s="$score" -v t="$stored_f1" -v hf="$ONLINE_HARD_FLOOR" \
     'BEGIN{ bar = t-0.10; if (bar < hf) bar = hf; exit !(s >= bar) }'; then
  record 1
  emit degrade-claude-online-grade-fail 10
fi

# 6. success: deepseek output is verified -> hand it to the caller.
record 0
[ -n "$out" ] && cp "$ds_out" "$out"
emit route-deepseek-ok 0
