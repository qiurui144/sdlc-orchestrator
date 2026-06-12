#!/usr/bin/env bash
# Handoff YAML validator. Exit 0 = valid; exit 2 = invalid (blocking).
set -euo pipefail

handoff="${1:?usage: validate.sh <handoff.yaml>}"

if [ ! -f "$handoff" ]; then
  echo "handoff-schema-invalid: file not found: $handoff" >&2
  exit 2
fi

# Required fields
for field in schema_version sprint_id phase_from phase_to artifact_path artifact_sha timestamp_utc8; do
  val=$(yq -r ".$field // \"\"" "$handoff")
  if [ -z "$val" ] || [ "$val" = "null" ]; then
    echo "handoff-schema-invalid: missing required field: $field" >&2
    exit 2
  fi
done

# Schema version supported?
sv=$(yq -r '.schema_version' "$handoff")
case "$sv" in
  1|2) : ;;
  *) echo "handoff-schema-future-version: schema_version=$sv (plugin supports 1,2). Upgrade plugin or regenerate handoff." >&2; exit 2 ;;
esac

# Phase transition matrix
pf=$(yq -r '.phase_from' "$handoff")
pt=$(yq -r '.phase_to' "$handoff")
case "$pf:$pt" in
  spec:plan|plan:impl|impl:review|impl:plan|plan:spec|review:test|review:impl|test:release|test:impl)
    : # ok
    ;;
  *)
    echo "phase-skip-not-allowed: transition $pf -> $pt is not in the allowed matrix (see spec §3.3)" >&2
    exit 2
    ;;
esac

# artifact_path exists?
ap=$(yq -r '.artifact_path' "$handoff")
repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
if [ ! -f "$repo_root/$ap" ]; then
  echo "handoff-schema-invalid: artifact_path does not exist: $ap" >&2
  exit 2
fi

# artifact_sha matches?
declared_sha=$(yq -r '.artifact_sha' "$handoff")
actual_sha=$(git hash-object "$repo_root/$ap")
if [ "$declared_sha" != "$actual_sha" ]; then
  echo "artifact-sha-mismatch: declared=$declared_sha actual=$actual_sha (artifact changed since handoff written)" >&2
  exit 2
fi

# v2 (v0.14): enforce producer + model_tier + self_score at the boundary
# (Hard constraint #6 model_tier, #7 self_score). Only for schema_version 2;
# v1 bypasses this block entirely (byte-for-byte back-compat, verified G1).
if [ "$sv" = "2" ]; then
  producer=$(yq -r '.producer // ""' "$handoff")
  if [ -z "$producer" ] || [ "$producer" = "null" ]; then
    echo "handoff-v2-missing-producer: schema_version 2 requires a non-empty 'producer'" >&2; exit 2
  fi
  mt=$(yq -r '.model_tier // ""' "$handoff")
  case "$mt" in
    haiku|sonnet|opus) : ;;
    *) echo "handoff-v2-bad-model-tier: model_tier must be haiku|sonnet|opus (got '$mt')" >&2; exit 2 ;;
  esac
  rref=$(yq -r '.self_score.rubric_ref // ""' "$handoff")
  if [ -z "$rref" ] || [ "$rref" = "null" ]; then
    echo "handoff-v2-missing-self-score: schema_version 2 requires self_score.rubric_ref" >&2; exit 2
  fi
  ov=$(yq -r '.self_score.overall // ""' "$handoff")
  if [ -z "$ov" ] || [ "$ov" = "null" ]; then
    echo "handoff-v2-missing-self-score: schema_version 2 requires self_score.overall" >&2; exit 2
  fi
  # numeric (int or decimal) then range [0,5] closed
  if ! printf '%s' "$ov" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    echo "handoff-v2-bad-self-score: self_score.overall must be a number in [0,5] (got '$ov')" >&2; exit 2
  fi
  if ! awk -v x="$ov" 'BEGIN{exit !(x>=0 && x<=5)}'; then
    echo "handoff-v2-bad-self-score: self_score.overall out of [0,5] (got '$ov')" >&2; exit 2
  fi
fi

# Optional panel_score block (v0.9). Absent → ok (back-compat with schema v1).
if [ "$(yq -r '.panel_score != null' "$handoff")" = "true" ]; then
  dec=$(yq -r '.panel_score.decision // ""' "$handoff")
  case "$dec" in
    AUTO_ADVANCE|ESCALATE) : ;;
    *) echo "panel-score-invalid: decision must be AUTO_ADVANCE|ESCALATE (got '$dec')" >&2; exit 2 ;;
  esac
  hr=$(yq -r '.panel_score.high_risk // false' "$handoff")
  # forgery guard: a high-risk gate can never auto-advance (spec §3.3 / §5.5)
  if [ "$hr" = "true" ] && [ "$dec" != "ESCALATE" ]; then
    echo "panel-high-risk-must-escalate: high_risk=true requires decision=ESCALATE" >&2; exit 2
  fi
  if [ "$dec" = "ESCALATE" ] && [ "$hr" != "true" ]; then
    er=$(yq -r '.panel_score.escalate_reason // ""' "$handoff")
    if [ -z "$er" ] || [ "$er" = "null" ]; then
      echo "panel-score-invalid: ESCALATE needs escalate_reason" >&2; exit 2
    fi
  fi
fi

# Optional risk_tier (v0.28.0 B): if present, must be LOW|NORMAL|HIGH. Absent → ok (old handoffs valid).
rt=$(yq -r '.risk_tier // ""' "$handoff")
if [ -n "$rt" ] && [ "$rt" != "null" ]; then
  case "$rt" in
    LOW|NORMAL|HIGH) : ;;
    *) echo "handoff-bad-risk-tier: $rt (must be LOW|NORMAL|HIGH)" >&2; exit 2 ;;
  esac
fi

# Optional ui_verified (web-ui capability): true|false|unverified. Absent → ok (non-web handoff).
uv=$(yq -r '.ui_verified // ""' "$handoff")
if [ -n "$uv" ] && [ "$uv" != "null" ]; then
  case "$uv" in
    true|false|unverified) : ;;
    *) echo "handoff-bad-ui-verified: ui_verified='$uv' (must be true|false|unverified)" >&2; exit 2 ;;
  esac
fi

echo "handoff valid: $pf -> $pt for sprint $(yq -r '.sprint_id' "$handoff")"
exit 0
