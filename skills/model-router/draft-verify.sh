#!/usr/bin/env bash
# draft-verify.sh — C-2 judgment draft-verify orchestrator (Task 3 + simplified route).
#
# Three subcommands:
#
#   route    --op <op> --input <f> [--out <f>] [--allowlist <f>] [--stub-draft <f>] [--min-chars N]
#            PREFERRED. Single-phase: opt-in → scope-hardstop → allowlist → circuit →
#            v4-pro draft (or stub) → inline oracle → emit. No --work needed.
#            Exit 0 = route-deepseek-ok; exit 10 = route-claude-* (fallback to full claude).
#            Oracle: output non-empty + >= min_chars (default 50) + first line has no failure marker.
#
#   prepare  --op <op> --input <f> --work <dir> [--stub-draft <f>] [--force-probe]  (LEGACY)
#            Two-phase: deepseek draft + optional injected-defect probe for recall testing.
#
#   finalize --op <op> --work <dir> --review <f> [--out <f>] [--telemetry <f>]      (LEGACY)
#            Two-phase: probe recall check → circuit → emit final.
#
# Decisions:
#   route-claude-disabled | route-claude-scope-hardstop | route-claude-not-draftable
#   route-claude-not-allowlisted | route-claude-stale-hash | route-claude-breaker-open
#   degrade-claude-provider-fail | route-claude-oracle-fail
#   prepared | route-deepseek-ok | degrade-claude-draft-failed | verify-recall-degraded
# bash-3.2-safe; shellcheck -x clean; SE16-safe.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$HERE/../.." && pwd -P)"
CALL="$ROOT/skills/model-provider/call.sh"
LIB="$ROOT/skills/model-eval/injected-defect-lib.sh"
GRADER="$ROOT/skills/model-eval/grader.sh"

# scope hard-stop: security-sensitive / final-decision judgment NEVER downgrades (closed set, §2).
FORBIDDEN_OPS="ga arch-decision security-verdict risk-final release-decision g1-judgment g2-judgment g3-judgment g4-judgment panel-verdict"

die() { echo "draft-verify: $*" >&2; exit 2; }
phase="${1:-}"; shift || true

op="" input="" work="" allowlist="$ROOT/config/draft-verify-allowlist.yaml" stub_draft="" force_probe=""
review="" out="" telemetry="" min_chars=50
while [ "$#" -gt 0 ]; do case "$1" in
  --op) op="$2"; shift 2;; --input) input="$2"; shift 2;; --work) work="$2"; shift 2;;
  --allowlist) allowlist="$2"; shift 2;; --stub-draft) stub_draft="$2"; shift 2;;
  --force-probe) force_probe=1; shift;; --review) review="$2"; shift 2;;
  --out) out="$2"; shift 2;; --telemetry) telemetry="$2"; shift 2;;
  --min-chars) min_chars="$2"; shift 2;;
  *) die "unknown arg: $1";; esac; done
[ -z "$op" ] && die "need --op"

emit() {
  if [ -n "$telemetry" ]; then mkdir -p "$(dirname "$telemetry")"
    printf '{"op":"%s","decision":"%s","probed":%s}\n' "$op" "$1" "${PROBED:-false}" >> "$telemetry"; fi
  echo "decision=$1"; exit "$2"; }

circuit_dir="${SDLC_CIRCUIT_DIR:-runs/.circuit-state}"
circuit_state="$circuit_dir/dv-$op.json"

record() {
  mkdir -p "$circuit_dir"
  local w="[]"; [ -f "$circuit_state" ] && w="$(jq -c '.window//[]' "$circuit_state" 2>/dev/null)"
  printf '%s' "$w" | jq -c --argjson o "$1" '{window: ((. + [$o]) | .[-20:])}' > "$circuit_state" 2>/dev/null || true
}

# ── route: single-phase, preferred architecture (no --work) ──────────────────
if [ "$phase" = "route" ]; then
  [ -n "$input" ] || die "route needs --input"
  # 0. opt-in gate
  [ "${SDLC_DRAFT_VERIFY:-0}" = "1" ] || emit route-claude-disabled 10
  # 1. scope hard-stop (closed set — even a forged allowlist cannot downgrade these)
  case "$op" in ''|*[!a-z0-9-]*) emit route-claude-not-draftable 10;; esac
  for f in $FORBIDDEN_OPS; do [ "$op" = "$f" ] && emit route-claude-scope-hardstop 10; done
  # 2. allowlist: op must exist with passed=true
  [ -f "$allowlist" ] || emit route-claude-not-draftable 10
  passed="$(yq -r ".ops.\"$op\".passed // false" "$allowlist" 2>/dev/null)"
  [ "$passed" = "true" ] || emit route-claude-not-allowlisted 10
  # 3. circuit breaker (>6 failures in last 20 → fallback to claude)
  if [ -f "$circuit_state" ]; then
    fails="$(jq '[.window[-20:][]|select(.==1)]|length' "$circuit_state" 2>/dev/null)" || fails=0
    [ "${fails:-0}" -gt 6 ] && emit route-claude-breaker-open 10
  fi
  # 4. provider-aware DRAFT (or stub for testing)
  td="$(mktemp -d)"
  if [ -n "$stub_draft" ]; then cp "$stub_draft" "$td/draft"
  else
    tt="$(yq -r ".ops.\"$op\".task_type // \"\"" "$allowlist" 2>/dev/null)"
    if ! "$GRADER" build-messages --task "$tt" --input "$input" > "$td/msgs.json" 2>/dev/null; then
      rm -rf "$td"; emit degrade-claude-provider-fail 10
    fi
    _prov="$(yq -r ".ops.\"$op\".preferred_provider // \"deepseek\"" "$allowlist" 2>/dev/null)"
    "$CALL" --provider "$_prov" --messages "$td/msgs.json" --format text > "$td/draft" 2>/dev/null
    _rc="$?"
    if [ "$_rc" = "6" ] && [ "$_prov" != "deepseek" ]; then
      # preferred provider unconfigured → fallback to deepseek
      "$CALL" --provider deepseek --messages "$td/msgs.json" --format text > "$td/draft" 2>/dev/null || { rm -rf "$td"; emit degrade-claude-provider-fail 10; }
    elif [ "$_rc" != "0" ]; then
      rm -rf "$td"; emit degrade-claude-provider-fail 10
    fi
  fi
  # 5. inline oracle: non-empty + min_chars + no failure marker on first line
  if ! [ -s "$td/draft" ]; then record 1; rm -rf "$td"; emit route-claude-oracle-fail 10; fi
  dlen="$(wc -c < "$td/draft" | tr -d ' ')"
  if [ "${dlen:-0}" -lt "$min_chars" ]; then record 1; rm -rf "$td"; emit route-claude-oracle-fail 10; fi
  first_line="$(head -1 "$td/draft")"   # SE16-safe: case not grep-pipe for control flow
  case "$first_line" in
    "I cannot"*|"I'm unable"*|"Error:"*)
      record 1; rm -rf "$td"; emit route-claude-oracle-fail 10;;
  esac
  # oracle pass
  record 0
  [ -n "$out" ] && cp "$td/draft" "$out"
  rm -rf "$td"
  emit route-deepseek-ok 0
fi

# ── prepare + finalize (legacy two-phase path): require --work ────────────────
[ -z "$work" ] && die "prepare/finalize need --work"
mkdir -p "$work"

if [ "$phase" = "prepare" ]; then
  [ -n "$input" ] || die "prepare needs --input"
  # 0. opt-in gate
  [ "${SDLC_DRAFT_VERIFY:-0}" = "1" ] || { echo "decision=route-claude-disabled"; exit 10; }
  # 1. scope hard-stop
  case "$op" in ''|*[!a-z0-9-]*) emit route-claude-not-draftable 10;; esac
  for f in $FORBIDDEN_OPS; do [ "$op" = "$f" ] && emit route-claude-scope-hardstop 10; done
  # 2. draftable allowlist
  [ -f "$allowlist" ] || emit route-claude-not-draftable 10
  passed="$(yq -r ".ops.\"$op\".passed // false" "$allowlist" 2>/dev/null)"
  [ "$passed" = "true" ] || emit route-claude-not-allowlisted 10
  # 3. sources_hash must match live lib hash — stale → claude
  tt="$(yq -r ".ops.\"$op\".task_type // \"\"" "$allowlist" 2>/dev/null)"
  live_hash="$("$LIB" hash "$tt" 2>/dev/null)"
  stored="$(yq -r ".ops.\"$op\".lib_hash // \"\"" "$allowlist" 2>/dev/null)"
  { [ -n "$stored" ] && [ "$stored" = "$live_hash" ]; } || emit route-claude-stale-hash 10
  # 4. circuit breaker
  if [ -f "$circuit_state" ]; then
    fails="$(jq '[.window[-20:][]|select(.==1)]|length' "$circuit_state" 2>/dev/null)" || fails=0
    [ "${fails:-0}" -gt 6 ] && emit route-claude-breaker-open 10
  fi
  # 5. provider-aware DRAFT
  if [ -n "$stub_draft" ]; then cp "$stub_draft" "$work/draft"
  else
    "$GRADER" build-messages --task "$tt" --input "$input" > "$work/msgs.json" 2>/dev/null || emit degrade-claude-draft-failed 10
    _prov="$(yq -r ".ops.\"$op\".preferred_provider // \"deepseek\"" "$allowlist" 2>/dev/null)"
    "$CALL" --provider "$_prov" --messages "$work/msgs.json" --format text > "$work/draft" 2>/dev/null
    _rc="$?"
    if [ "$_rc" = "6" ] && [ "$_prov" != "deepseek" ]; then
      "$CALL" --provider deepseek --messages "$work/msgs.json" --format text > "$work/draft" 2>/dev/null || emit degrade-claude-draft-failed 10
    elif [ "$_rc" != "0" ]; then
      emit degrade-claude-draft-failed 10
    fi
  fi
  [ -s "$work/draft" ] || emit degrade-claude-draft-failed 10
  # 6. probe? inject a known defect for recall testing
  PROBED=false
  if [ -n "$force_probe" ]; then
    PROBED=true
    defect="$("$LIB" pick "$tt" 2>/dev/null)"
    marker="$(printf '%s' "$defect" | jq -r '.detect_marker' 2>/dev/null)"
    did="$(printf '%s' "$defect" | jq -r '.id' 2>/dev/null)"
    printf '%s\n[INJECTED-DEFECT:%s]\n' "$(cat "$work/draft")" "$did" > "$work/draft.probed" && mv "$work/draft.probed" "$work/draft"
    jq -nc --arg m "$marker" --arg id "$did" '{probed:true,detect_marker:$m,defect_id:$id}' > "$work/probe.json"
  else
    echo '{"probed":false}' > "$work/probe.json"
  fi
  emit prepared 0
fi

if [ "$phase" = "finalize" ]; then
  [ -n "$review" ] || die "finalize needs --review"
  [ -f "$work/probe.json" ] || die "no prepared draft in $work"
  probed="$(jq -r '.probed' "$work/probe.json" 2>/dev/null)"
  PROBED="$probed"
  if [ "$probed" = "true" ]; then
    marker="$(jq -r '.detect_marker' "$work/probe.json")"
    caught="$(jq -r --arg m "$marker" '[.caught[]?|select(.==$m)]|length' "$review" 2>/dev/null)"
    if [ "${caught:-0}" -lt 1 ]; then record 1; emit verify-recall-degraded 10; fi
    record 0
  fi
  # strip injected-defect marker line from the final output
  jq -r '.final' "$review" 2>/dev/null | grep -v '^\[INJECTED-DEFECT:' > "$work/final" || true
  [ -n "$out" ] && cp "$work/final" "$out"
  emit route-deepseek-ok 0
fi

die "phase must be route|prepare|finalize (got '$phase')"
