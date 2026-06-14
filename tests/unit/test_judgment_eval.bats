#!/usr/bin/env bats
# C-2 judgment-eval.sh — simplified 4-gate offline eligibility evaluator.
#
# The lib_valid (gate 1) and recall (gate 3) gates from the two-phase design are removed.
# Single-phase route architecture relies on offline judge_confidence + human sign-off.
#
# Four gates (all must pass):
#   1. judge_confidence — cross-provider (claude+qwen, NOT deepseek) panel >= floor
#   2. human_checked    — explicit --human-checked flag (manual gate; no auto-pass)
#   3. net_savings      — probe-inclusive token savings >= min_net_savings
#   4. tco_ok           — explicit --tco-ok flag (manual TCO gate)

setup() {
  R="${BATS_TEST_DIRNAME}/../.."
  JE="$R/skills/model-eval/judgment-eval.sh"
  TD="$(mktemp -d)"
}
teardown() { rm -rf "$TD"; }

# Convenience wrapper: 4-gate pass flags
PASS_FLAGS="--judge-confidence 0.85 --human-checked --net-savings 100 --tco-ok"
je() { bash "$JE" --op spec-scope --task spec-scope $PASS_FLAGS --allowlist "$TD/allow.yaml" "$@"; }

# ────────────────────────────────────────────────────────────────────────────────
# Gate 1: judge_confidence (cross-provider panel — claude+qwen, never deepseek)
# ────────────────────────────────────────────────────────────────────────────────
@test "judge_confidence below floor -> not eligible" {
  run bash "$JE" --op spec-scope --task spec-scope \
    --judge-confidence 0.65 --human-checked --net-savings 100 --tco-ok \
    --judge-floor 0.7 --allowlist "$TD/allow.yaml"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "judge-confidence-fail"
}

@test "judge_confidence at exactly the floor -> eligible (boundary: >=)" {
  run bash "$JE" --op spec-scope --task spec-scope \
    --judge-confidence 0.7 --human-checked --net-savings 100 --tco-ok \
    --judge-floor 0.7 --allowlist "$TD/allow.yaml"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "eligible=true"
}

# ────────────────────────────────────────────────────────────────────────────────
# Gate 2: human_checked (manual gate — no --human-checked flag = fail)
# ────────────────────────────────────────────────────────────────────────────────
@test "missing --human-checked -> not eligible" {
  run bash "$JE" --op spec-scope --task spec-scope \
    --judge-confidence 0.85 --net-savings 100 --tco-ok \
    --allowlist "$TD/allow.yaml"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "human-checked-fail"
}

# ────────────────────────────────────────────────────────────────────────────────
# Gate 3: net_savings (probe-inclusive, from C-1)
# ────────────────────────────────────────────────────────────────────────────────
@test "net_savings below min -> not eligible" {
  run bash "$JE" --op spec-scope --task spec-scope \
    --judge-confidence 0.85 --human-checked --net-savings 5 --tco-ok \
    --min-net-savings 10 --allowlist "$TD/allow.yaml"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "net-savings-fail"
}

@test "net_savings at exactly min -> eligible (boundary: >=)" {
  run bash "$JE" --op spec-scope --task spec-scope \
    --judge-confidence 0.85 --human-checked --net-savings 10 --tco-ok \
    --min-net-savings 10 --allowlist "$TD/allow.yaml"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "eligible=true"
}

# ────────────────────────────────────────────────────────────────────────────────
# Gate 4: tco_ok (manual TCO gate)
# ────────────────────────────────────────────────────────────────────────────────
@test "missing --tco-ok -> not eligible" {
  run bash "$JE" --op spec-scope --task spec-scope \
    --judge-confidence 0.85 --human-checked --net-savings 100 \
    --allowlist "$TD/allow.yaml"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "tco-fail"
}

# ────────────────────────────────────────────────────────────────────────────────
# Happy path: all gates pass -> eligible, allowlist written (no lib_hash/recall)
# ────────────────────────────────────────────────────────────────────────────────
@test "all gates pass -> eligible, allowlist written with required fields" {
  run je
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "eligible=true"
  [ -f "$TD/allow.yaml" ]
  yq -r '.ops."spec-scope".passed' "$TD/allow.yaml" | grep -qx "true"
  yq -r '.ops."spec-scope".task_type' "$TD/allow.yaml" | grep -qx "spec-scope"
  yq -r '.ops."spec-scope".judge_confidence' "$TD/allow.yaml" | grep -qx "0.85"
  yq -r '.ops."spec-scope".human_checked' "$TD/allow.yaml" | grep -qx "true"
  yq -r '.ops."spec-scope".tco_ok' "$TD/allow.yaml" | grep -qx "true"
}

@test "allowlist does NOT contain lib_hash or injected_defect_recall (simplified schema)" {
  run je
  [ "$status" -eq 0 ]
  lh="$(yq -r '.ops."spec-scope".lib_hash // "absent"' "$TD/allow.yaml")"
  [ "$lh" = "absent" ]
  ir="$(yq -r '.ops."spec-scope".injected_defect_recall // "absent"' "$TD/allow.yaml")"
  [ "$ir" = "absent" ]
}

@test "allowlist written with version field" {
  run je
  [ "$status" -eq 0 ]
  yq -r '.version' "$TD/allow.yaml" | grep -qx "1"
}

# ────────────────────────────────────────────────────────────────────────────────
# dry-run: eligible but allowlist NOT written
# ────────────────────────────────────────────────────────────────────────────────
@test "dry-run: eligible but allowlist NOT written" {
  run je --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "eligible=true"
  [ ! -f "$TD/allow.yaml" ]
}

@test "dry-run: not-eligible also does not write" {
  run bash "$JE" --op spec-scope --task spec-scope \
    --judge-confidence 0.5 --human-checked --net-savings 100 --tco-ok \
    --allowlist "$TD/allow.yaml" --dry-run
  [ "$status" -ne 0 ]
  [ ! -f "$TD/allow.yaml" ]
}

# ────────────────────────────────────────────────────────────────────────────────
# Existing allowlist: other ops preserved on update (no destructive write)
# ────────────────────────────────────────────────────────────────────────────────
@test "existing allowlist: other ops preserved on update" {
  cat > "$TD/allow.yaml" <<'EOF'
version: 1
ops:
  other-op: {passed: true, task_type: other, judge_confidence: 0.9,
              human_checked: true, net_savings: 200, tco_ok: true}
EOF
  run je
  [ "$status" -eq 0 ]
  yq -r '.ops."other-op".passed' "$TD/allow.yaml" | grep -qx "true"
  yq -r '.ops."spec-scope".passed' "$TD/allow.yaml" | grep -qx "true"
}

# ────────────────────────────────────────────────────────────────────────────────
# Integration: allowlist written by judgment-eval passes draft-verify route gates
# ────────────────────────────────────────────────────────────────────────────────
@test "allowlist written by judgment-eval passes draft-verify route gates" {
  DV="$R/skills/model-router/draft-verify.sh"
  printf 'Feature: rate limiter.\n' > "$TD/in"
  printf 'Valid stub response with enough characters to pass the oracle check here.\n' > "$TD/stub"
  je >/dev/null
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" route \
    --op spec-scope --input "$TD/in" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/stub"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "decision=route-deepseek-ok"
}
