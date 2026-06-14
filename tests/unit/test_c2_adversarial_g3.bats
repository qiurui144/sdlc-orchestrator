#!/usr/bin/env bats
# C-2 Task 7: G3 adversarial review — one-vote-veto scenarios.
#
# G3 adversarial attacks (each is a hard requirement, any failure blocks ship):
#   A1: rubber-stamp — route oracle rejects degenerate deepseek output; 7 failures trip breaker
#   A2: circular-blind-spot — lib without prod-MISSED/cross-provider rejected by validate gate
#   A3: scope bypass — forged allowlist on security-sensitive/final-decision op refused
#   A4: detection-delay honesty — 6 oracle-fails do NOT trip breaker (threshold is >6)
#   A5: did-vs-said gone — no did-vs-said / edit-magnitude logic in implementation files
#   A6: spec-scope is LIVE — real eval 2026-06-13 added cross-provider entry, guard passes

setup() {
  R="${BATS_TEST_DIRNAME}/../.."
  DV="$R/skills/model-router/draft-verify.sh"
  LIB="$R/skills/model-eval/injected-defect-lib.sh"
  JE="$R/skills/model-eval/judgment-eval.sh"
  TD="$(mktemp -d)"
  export SDLC_INJECTED_DEFECTS_DIR="$TD/defects"
  export SDLC_CIRCUIT_DIR="$TD/circuit"
  mkdir -p "$TD/defects"
  cat > "$TD/defects/spec-scope.yaml" <<'EOF'
task_type: spec-scope
defects:
  - {id: scope-overclaim, task_type: spec-scope, defect_type: overclaim,
     planted_patch: "p", detect_marker: "flags-distributed-should-be-deferred",
     source: prod-MISSED}
EOF
  # 4-gate judgment-eval (simplified; no --recall arg)
  bash "$JE" --op spec-scope --task spec-scope \
    --judge-confidence 0.85 --human-checked \
    --net-savings 100 --tco-ok \
    --allowlist "$TD/allow.yaml" >/dev/null
  printf 'input\n' > "$TD/in"
  # good stub: passes oracle (>= 50 chars, no failure markers)
  printf 'Rate limiter scope: per-key counters in Redis, 1000 req/min default.\n' > "$TD/good"
  # oracle-fail stub: failure marker first line
  printf 'I cannot process this request due to policy.\n' > "$TD/bad"
}
teardown() { rm -rf "$TD"; }

# ────────────────────────────────────────────────────────────────────────────────
# A1: rubber-stamp — oracle rejects degenerate output; repeated failure trips breaker
# In the single-phase route architecture, "rubber-stamp" = deepseek producing
# degenerate output (empty/short/failure marker). The oracle catches it, records
# circuit failures, and trips the breaker after >6 failures.
# ────────────────────────────────────────────────────────────────────────────────
@test "A1: oracle-fail stub → route-claude-oracle-fail (single degenerate output caught)" {
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" route \
    --op spec-scope --input "$TD/in" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/bad"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-oracle-fail"
}

@test "A1: 7 oracle-fails → breaker open (rubber-stamp pattern detected; route-claude-breaker-open)" {
  i=0
  while [ "$i" -lt 7 ]; do
    env SDLC_DRAFT_VERIFY=1 bash "$DV" route \
      --op spec-scope --input "$TD/in" \
      --allowlist "$TD/allow.yaml" --stub-draft "$TD/bad" >/dev/null 2>&1 || true
    i=$((i+1))
  done
  # 8th call: circuit sees 7 failures → blocked
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" route \
    --op spec-scope --input "$TD/in" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/bad"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-breaker-open"
}

# ────────────────────────────────────────────────────────────────────────────────
# A2: circular-blind-spot — lib must NOT be built only from claude-caught defects.
# Protection is offline (injected-defect-lib validate) before allowlist entry is
# written. The single-phase route architecture has no runtime recall; this gate
# remains at the lib-build phase.
# ────────────────────────────────────────────────────────────────────────────────
@test "A2: lib with only prod-caught entries → circular-blind-spot guard rejects (fail-closed)" {
  cat > "$TD/defects/claude-only.yaml" <<'EOF'
task_type: claude-only
defects:
  - {id: d1, task_type: claude-only, defect_type: omission, planted_patch: "p",
     detect_marker: "m", source: prod-caught}
EOF
  run bash "$LIB" validate claude-only
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "circular-blind-spot"
}

@test "A2: lib with cross-provider entry → guard passes (real calibration data present)" {
  cat > "$TD/defects/good.yaml" <<'EOF'
task_type: good
defects:
  - {id: d1, task_type: good, defect_type: omission, planted_patch: "p",
     detect_marker: "m", source: prod-caught}
  - {id: d2, task_type: good, defect_type: overclaim, planted_patch: "p2",
     detect_marker: "m2", source: cross-provider}
EOF
  run bash "$LIB" validate good
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "lib-valid"
}

# ────────────────────────────────────────────────────────────────────────────────
# A3: scope bypass — forbidden ops refused even with a forged allowlist entry.
# route subcommand checks scope hard-stop BEFORE allowlist lookup.
# ────────────────────────────────────────────────────────────────────────────────
@test "A3: ga with forged allowlist entry → scope-hardstop (GA stays full-claude)" {
  OP=ga yq -i '.ops[env(OP)] = {"passed": true, "task_type": "spec-scope"}' "$TD/allow.yaml"
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" route \
    --op ga --input "$TD/in" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/good"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-scope-hardstop"
}

@test "A3: panel-verdict with forged entry → scope-hardstop (panel judgment never downgraded)" {
  OP=panel-verdict yq -i '.ops[env(OP)] = {"passed": true, "task_type": "spec-scope"}' "$TD/allow.yaml"
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" route \
    --op panel-verdict --input "$TD/in" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/good"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-scope-hardstop"
}

@test "A3: risk-final with forged entry → scope-hardstop" {
  OP=risk-final yq -i '.ops[env(OP)] = {"passed": true, "task_type": "spec-scope"}' "$TD/allow.yaml"
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" route \
    --op risk-final --input "$TD/in" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/good"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-scope-hardstop"
}

# ────────────────────────────────────────────────────────────────────────────────
# A4: detection-delay honesty — 6 consecutive oracle-fails (just below threshold)
# do NOT trip the breaker. Threshold is >6 (i.e., >=7 failures). This is the honest
# acknowledgment: with oracle-only quality monitoring, errors can go undetected for
# up to 6 bad responses in a window of 20. The threshold is set at >6 to balance
# false-positive rate vs detection speed.
# ────────────────────────────────────────────────────────────────────────────────
@test "A4: 6 oracle-fails (below threshold) → breaker NOT open (detection-delay acknowledged)" {
  i=0
  while [ "$i" -lt 6 ]; do
    env SDLC_DRAFT_VERIFY=1 bash "$DV" route \
      --op spec-scope --input "$TD/in" \
      --allowlist "$TD/allow.yaml" --stub-draft "$TD/bad" >/dev/null 2>&1 || true
    i=$((i+1))
  done
  # 6 oracle-fails is NOT enough to trip (>6 = 7+ required); a good stub should still pass
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" route \
    --op spec-scope --input "$TD/in" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/good"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "decision=route-deepseek-ok"
}

@test "A4: interleaved oracle-pass+fail cycle — cumulative rate below threshold → breaker NOT open" {
  # 4 passes + 4 fails = 4/8 fail rate → below >6 threshold in a 20-window
  i=0
  while [ "$i" -lt 4 ]; do
    env SDLC_DRAFT_VERIFY=1 bash "$DV" route \
      --op spec-scope --input "$TD/in" \
      --allowlist "$TD/allow.yaml" --stub-draft "$TD/good" >/dev/null || true
    env SDLC_DRAFT_VERIFY=1 bash "$DV" route \
      --op spec-scope --input "$TD/in" \
      --allowlist "$TD/allow.yaml" --stub-draft "$TD/bad" >/dev/null 2>&1 || true
    i=$((i+1))
  done
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" route \
    --op spec-scope --input "$TD/in" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/good"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "decision=route-deepseek-ok"
}

# ────────────────────────────────────────────────────────────────────────────────
# A5: did-vs-said fully gone — no edit-magnitude / did-vs-said logic in implementation
# ────────────────────────────────────────────────────────────────────────────────
@test "A5: no did-vs-said logic in skills/model-router/ implementation files" {
  hits="$(grep -rl "did.vs.said\|edit.magnitude\|edit_magnitude" \
    "$R/skills/model-router/" "$R/skills/model-eval/" 2>/dev/null \
    | grep -v ".bats" | wc -l | tr -d ' ')"
  [ "$hits" -eq 0 ]
}

@test "A5: no did-vs-said in agent files" {
  hits="$(grep -rl "did.vs.said\|edit.magnitude\|edit_magnitude" \
    "$R/agents/" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$hits" -eq 0 ]
}

# ────────────────────────────────────────────────────────────────────────────────
# A6: real eval completed — spec-scope is now live (2026-06-13 Task 6)
# Guard passes because qwen independently found overclaim-log-schema in deepseek draft.
# ────────────────────────────────────────────────────────────────────────────────
@test "A6: spec-scope shipped lib passes guard after real eval (cross-provider qwen entry)" {
  # Task 6 real eval added qwen cross-provider defect → guard now passes.
  run env -u SDLC_INJECTED_DEFECTS_DIR bash "$LIB" validate spec-scope
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "lib-valid"
}

@test "A6: circular-blind-spot still blocks a pure prod-caught lib (guard logic unchanged)" {
  # The guard logic itself hasn't changed; only spec-scope's lib content changed.
  cat > "$TD/defects/guard-check.yaml" <<'EOF'
task_type: guard-check
defects:
  - {id: d1, task_type: guard-check, defect_type: omission, planted_patch: "p",
     detect_marker: "m", source: prod-caught}
EOF
  run bash "$LIB" validate guard-check
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "circular-blind-spot"
}
