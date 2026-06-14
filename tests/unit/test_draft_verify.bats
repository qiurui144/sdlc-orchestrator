#!/usr/bin/env bats
# C-2 Task 3: draft-verify orchestration. claude review is the harness (main ctx) -> stubbed via --review.
# Safety: scope hard-stop (security/final-decision never downgrades), verify-recall-degraded (rubber-stamp
# caught by injected-defect recall, NOT did-vs-said), stale lib-hash, off byte-identical.
setup() {
  R="${BATS_TEST_DIRNAME}/../.."
  DV="$R/skills/model-router/draft-verify.sh"; LIB="$R/skills/model-eval/injected-defect-lib.sh"
  TD="$(mktemp -d)"
  export SDLC_INJECTED_DEFECTS_DIR="$TD/defects"; mkdir -p "$SDLC_INJECTED_DEFECTS_DIR"
  export SDLC_CIRCUIT_DIR="$TD/circuit"
  cat > "$SDLC_INJECTED_DEFECTS_DIR/spec-scope.yaml" <<'EOF'
task_type: spec-scope
defects:
  - {id: scope-overclaim, task_type: spec-scope, defect_type: overclaim, planted_patch: "p", detect_marker: "flags-distributed-should-be-deferred", source: prod-MISSED}
EOF
  LIBHASH="$(bash "$LIB" hash spec-scope)"
  cat > "$TD/allow.yaml" <<EOF
ops:
  spec-scope: {passed: true, task_type: spec-scope, lib_hash: $LIBHASH}
EOF
  printf 'Feature: rate limiter.\n' > "$TD/in"
  printf 'In scope: per-key.\nOut of scope: distributed.\n' > "$TD/draft"
  WORK="$TD/work"
}
teardown() { rm -rf "$TD"; }
P() { env SDLC_DRAFT_VERIFY=1 bash "$DV" prepare --op "$1" --input "$TD/in" --work "$WORK" --allowlist "$TD/allow.yaml" --stub-draft "$TD/draft" "${@:2}"; }

@test "off -> route-claude-disabled" {
  run env -u SDLC_DRAFT_VERIFY bash "$DV" prepare --op spec-scope --input "$TD/in" --work "$WORK" --allowlist "$TD/allow.yaml" --stub-draft "$TD/draft"
  [ "$status" -eq 10 ]; echo "$output" | grep -q route-claude-disabled
}
@test "scope hard-stop: ga refused even if forged-allowlisted" {
  yq -i '.ops.ga.passed=true | .ops.ga.task_type="spec-scope" | .ops.ga.lib_hash="x"' "$TD/allow.yaml"
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" prepare --op ga --input "$TD/in" --work "$WORK" --allowlist "$TD/allow.yaml" --stub-draft "$TD/draft"
  [ "$status" -eq 10 ]; echo "$output" | grep -q route-claude-scope-hardstop
}
@test "prepare happy (no probe) -> prepared + draft + probed:false" {
  run P spec-scope
  [ "$status" -eq 0 ]; echo "$output" | grep -q decision=prepared
  [ -s "$WORK/draft" ]; grep -q '"probed":false' "$WORK/probe.json"
}
@test "prepare --force-probe injects defect + probe.json" {
  run P spec-scope --force-probe
  [ "$status" -eq 0 ]; grep -q 'INJECTED-DEFECT' "$WORK/draft"; grep -q '"probed":true' "$WORK/probe.json"
}
@test "finalize no-probe -> route-deepseek-ok + final stripped" {
  P spec-scope >/dev/null
  printf '{"final":"In scope: per-key.\\nOut of scope: distributed.","caught":[]}' > "$TD/rev.json"
  run bash "$DV" finalize --op spec-scope --work "$WORK" --review "$TD/rev.json" --out "$TD/final"
  [ "$status" -eq 0 ]; echo "$output" | grep -q route-deepseek-ok; [ -s "$TD/final" ]
  ! grep -q 'INJECTED-DEFECT' "$TD/final"
}
@test "finalize probe + review CAUGHT marker -> route-deepseek-ok" {
  P spec-scope --force-probe >/dev/null
  printf '{"final":"corrected","caught":["flags-distributed-should-be-deferred"]}' > "$TD/rev.json"
  run bash "$DV" finalize --op spec-scope --work "$WORK" --review "$TD/rev.json"
  [ "$status" -eq 0 ]; echo "$output" | grep -q route-deepseek-ok
}
@test "finalize probe + review MISSED marker -> verify-recall-degraded (rubber-stamp caught)" {
  P spec-scope --force-probe >/dev/null
  printf '{"final":"corrected","caught":["something-else"]}' > "$TD/rev.json"
  run bash "$DV" finalize --op spec-scope --work "$WORK" --review "$TD/rev.json"
  [ "$status" -eq 10 ]; echo "$output" | grep -q verify-recall-degraded
}
@test "stale lib_hash -> route-claude-stale-hash" {
  yq -i '.ops."spec-scope".lib_hash="deadbeef"' "$TD/allow.yaml"
  run P spec-scope
  [ "$status" -eq 10 ]; echo "$output" | grep -q route-claude-stale-hash
}
