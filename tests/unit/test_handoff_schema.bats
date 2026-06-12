#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/../.."
VALIDATE="$ROOT/skills/handoff-schema/validate.sh"
FIXT="$BATS_TEST_DIRNAME/../fixtures"

@test "valid handoff passes" {
  run "$VALIDATE" "$FIXT/handoff-valid.yaml"
  [ "$status" -eq 0 ]
}

@test "missing required field is rejected" {
  run "$VALIDATE" "$FIXT/handoff-missing-field.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing"* ]]
}

@test "future schema_version is rejected with friendly error" {
  run "$VALIDATE" "$FIXT/handoff-bad-schema-version.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"handoff-schema-future-version"* ]]
}

@test "phase transition matrix enforced" {
  cat > /tmp/bad-transition.yaml <<EOF
schema_version: 1
sprint_id: test
phase_from: spec
phase_to: impl
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-05-28T12:00:00+08:00
EOF
  run "$VALIDATE" /tmp/bad-transition.yaml
  [ "$status" -eq 2 ]
  [[ "$output" == *"phase-skip-not-allowed"* ]]
  rm /tmp/bad-transition.yaml
}

@test "artifact-sha-mismatch is rejected" {
  cat > /tmp/sha-mismatch.yaml <<EOF
schema_version: 1
sprint_id: 2026-05-28-test
phase_from: spec
phase_to: plan
artifact_path: README.md
artifact_sha: 0000000000000000000000000000000000000000
timestamp_utc8: 2026-05-28T14:30:00+08:00
EOF
  run "$VALIDATE" /tmp/sha-mismatch.yaml
  [ "$status" -eq 2 ]
  [[ "$output" == *"artifact-sha-mismatch"* ]]
  rm /tmp/sha-mismatch.yaml
}

@test "valid panel_score AUTO_ADVANCE passes (v0.9)" {
  cat > /tmp/panel-ok.yaml <<EOF
schema_version: 1
sprint_id: 2026-06-02-test
phase_from: spec
phase_to: plan
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-02T12:00:00+08:00
panel_score:
  decision: AUTO_ADVANCE
  high_risk: false
  size: 3
  mean: 4.2
EOF
  run "$VALIDATE" /tmp/panel-ok.yaml
  [ "$status" -eq 0 ]
  rm /tmp/panel-ok.yaml
}

@test "forged high_risk + AUTO_ADVANCE is rejected (v0.9)" {
  cat > /tmp/panel-forged.yaml <<EOF
schema_version: 1
sprint_id: 2026-06-02-test
phase_from: spec
phase_to: plan
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-02T12:00:00+08:00
panel_score:
  decision: AUTO_ADVANCE
  high_risk: true
  size: 5
EOF
  run "$VALIDATE" /tmp/panel-forged.yaml
  [ "$status" -eq 2 ]
  [[ "$output" == *"panel-high-risk-must-escalate"* ]]
  rm /tmp/panel-forged.yaml
}

@test "handoff without panel_score still valid (back-compat)" {
  run "$VALIDATE" "$FIXT/handoff-valid.yaml"
  [ "$status" -eq 0 ]
}

# --- schema v2 (v0.14): producer + model_tier + self_score enforced at boundary ---

@test "v2 handoff with producer + model_tier + self_score passes" {
  cat > /tmp/v2-ok.yaml <<EOF
schema_version: 2
sprint_id: 2026-06-02-test
phase_from: spec
phase_to: plan
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-02T12:00:00+08:00
producer: spec-analyst
model_tier: opus
self_score:
  rubric_ref: "docs/x.md#appendix-e"
  overall: 4.6
EOF
  run "$VALIDATE" /tmp/v2-ok.yaml
  [ "$status" -eq 0 ]; rm /tmp/v2-ok.yaml
}
@test "v2 boundary overall=0 and overall=5 pass (closed interval)" {
  for v in 0 5; do
    cat > /tmp/v2-b.yaml <<EOF
schema_version: 2
sprint_id: t
phase_from: spec
phase_to: plan
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-02T12:00:00+08:00
producer: spec-analyst
model_tier: sonnet
self_score: {rubric_ref: "x#e", overall: $v}
EOF
    run "$VALIDATE" /tmp/v2-b.yaml; [ "$status" -eq 0 ]; rm /tmp/v2-b.yaml
  done
}
@test "v2 missing producer rejected" {
  cat > /tmp/v2-np.yaml <<EOF
schema_version: 2
sprint_id: t
phase_from: spec
phase_to: plan
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-02T12:00:00+08:00
model_tier: opus
self_score: {rubric_ref: "x#e", overall: 4}
EOF
  run "$VALIDATE" /tmp/v2-np.yaml
  [ "$status" -eq 2 ]; [[ "$output" == *"handoff-v2-missing-producer"* ]]; rm /tmp/v2-np.yaml
}
@test "v2 bad model_tier rejected (no eval)" {
  cat > /tmp/v2-bt.yaml <<EOF
schema_version: 2
sprint_id: t
phase_from: spec
phase_to: plan
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-02T12:00:00+08:00
producer: x
model_tier: "opus; rm -rf /"
self_score: {rubric_ref: "x#e", overall: 4}
EOF
  run "$VALIDATE" /tmp/v2-bt.yaml
  [ "$status" -eq 2 ]; [[ "$output" == *"handoff-v2-bad-model-tier"* ]]; rm /tmp/v2-bt.yaml
}
@test "v2 missing self_score rejected" {
  cat > /tmp/v2-ns.yaml <<EOF
schema_version: 2
sprint_id: t
phase_from: spec
phase_to: plan
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-02T12:00:00+08:00
producer: x
model_tier: opus
EOF
  run "$VALIDATE" /tmp/v2-ns.yaml
  [ "$status" -eq 2 ]; [[ "$output" == *"handoff-v2-missing-self-score"* ]]; rm /tmp/v2-ns.yaml
}
@test "v2 overall out of range / non-numeric rejected" {
  for v in 7 -1 abc; do
    cat > /tmp/v2-bo.yaml <<EOF
schema_version: 2
sprint_id: t
phase_from: spec
phase_to: plan
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-02T12:00:00+08:00
producer: x
model_tier: opus
self_score: {rubric_ref: "x#e", overall: "$v"}
EOF
    run "$VALIDATE" /tmp/v2-bo.yaml
    [ "$status" -eq 2 ]; [[ "$output" == *"handoff-v2-bad-self-score"* ]]; rm /tmp/v2-bo.yaml
  done
}
@test "v2 still enforces panel high-risk forgery guard" {
  cat > /tmp/v2-forge.yaml <<EOF
schema_version: 2
sprint_id: t
phase_from: spec
phase_to: plan
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-02T12:00:00+08:00
producer: x
model_tier: opus
self_score: {rubric_ref: "x#e", overall: 4}
panel_score: {decision: AUTO_ADVANCE, high_risk: true, size: 5}
EOF
  run "$VALIDATE" /tmp/v2-forge.yaml
  [ "$status" -eq 2 ]; [[ "$output" == *"panel-high-risk-must-escalate"* ]]; rm /tmp/v2-forge.yaml
}

# --- v0.28.0 B: optional risk_tier field ---

@test "risk_tier absent → handoff still valid (back-compat)" {
  run "$VALIDATE" "$FIXT/handoff-valid.yaml"
  [ "$status" -eq 0 ]
}
@test "risk_tier present and valid (NORMAL) → valid" {
  cat > /tmp/rt-ok.yaml <<EOF
schema_version: 2
sprint_id: t
phase_from: spec
phase_to: plan
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-06T12:00:00+08:00
producer: x
model_tier: opus
self_score: {rubric_ref: "x#e", overall: 4}
risk_tier: NORMAL
EOF
  run "$VALIDATE" /tmp/rt-ok.yaml
  [ "$status" -eq 0 ]; rm /tmp/rt-ok.yaml
}
@test "risk_tier present but invalid (MEDIUM) → reject" {
  cat > /tmp/rt-bad.yaml <<EOF
schema_version: 2
sprint_id: t
phase_from: spec
phase_to: plan
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-06T12:00:00+08:00
producer: x
model_tier: opus
self_score: {rubric_ref: "x#e", overall: 4}
risk_tier: MEDIUM
EOF
  run "$VALIDATE" /tmp/rt-bad.yaml
  [ "$status" -ne 0 ]; [[ "$output" == *"handoff-bad-risk-tier"* ]]; rm /tmp/rt-bad.yaml
}

# --- web-ui capability: optional ui_verified field ---

@test "ui_verified absent → still valid (back-compat)" {
  run "$VALIDATE" "$FIXT/handoff-valid.yaml"
  [ "$status" -eq 0 ]
}
@test "ui_verified: unverified is accepted (additive)" {
  cat > /tmp/uv-ok.yaml <<EOF
schema_version: 2
sprint_id: t
phase_from: test
phase_to: release
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-07T12:00:00+08:00
producer: x
model_tier: opus
self_score: {rubric_ref: "x#e", overall: 4}
ui_verified: unverified
EOF
  run "$VALIDATE" /tmp/uv-ok.yaml
  [ "$status" -eq 0 ]; rm /tmp/uv-ok.yaml
}
@test "ui_verified: bogus (maybe) → exit 2" {
  cat > /tmp/uv-bad.yaml <<EOF
schema_version: 2
sprint_id: t
phase_from: test
phase_to: release
artifact_path: README.md
artifact_sha: $(git -C "$ROOT" hash-object README.md)
timestamp_utc8: 2026-06-07T12:00:00+08:00
producer: x
model_tier: opus
self_score: {rubric_ref: "x#e", overall: 4}
ui_verified: maybe
EOF
  run "$VALIDATE" /tmp/uv-bad.yaml
  [ "$status" -eq 2 ]; [[ "$output" == *"ui_verified"* ]]; rm /tmp/uv-bad.yaml
}
