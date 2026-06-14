#!/usr/bin/env bats
# C-2 Task 5: integration tests for the full draft-verify flow as the task-orchestrator would run it.
# Tests the ORCHESTRATOR RULE perspective (task-orchestrator.md rule 17):
#   - draftable judgment op + SDLC_DRAFT_VERIFY=1 + allowlisted → two-phase C-2 flow succeeds
#   - scope hard-stop: forbidden ops (ga/arch-decision/security-verdict/g1-judgment/…) structurally
#     refused even if forged into the allowlist (closed set, like M2's mechanical map)
#   - SDLC_DRAFT_VERIFY unset → route-claude-disabled (byte-identical to full-claude path)
#   - op not in allowlist (including "no-downstream-signal" task_types not yet human-evaluated)
#     → route-claude-not-allowlisted (full claude; fail-closed)
#   - repeated verify-recall misses → circuit-breaker opens (breaker-open)
# All stubbed — claude adversarial review is the harness (main ctx), supplied via --review.

setup() {
  R="${BATS_TEST_DIRNAME}/../.."
  DV="$R/skills/model-router/draft-verify.sh"
  JE="$R/skills/model-eval/judgment-eval.sh"
  LIB="$R/skills/model-eval/injected-defect-lib.sh"
  TD="$(mktemp -d)"
  export SDLC_INJECTED_DEFECTS_DIR="$TD/defects"
  export SDLC_CIRCUIT_DIR="$TD/circuit"
  mkdir -p "$TD/defects"

  # Valid injected-defect lib (passes circular-blind-spot guard)
  cat > "$TD/defects/spec-scope.yaml" <<'EOF'
task_type: spec-scope
defects:
  - {id: scope-overclaim, task_type: spec-scope, defect_type: overclaim,
     planted_patch: "p", detect_marker: "flags-distributed-should-be-deferred",
     source: prod-MISSED}
EOF

  # Build a valid allowlist via judgment-eval (4-gate simplified; no --recall)
  bash "$JE" --op spec-scope --task spec-scope \
    --judge-confidence 0.85 --human-checked \
    --net-savings 100 --tco-ok \
    --allowlist "$TD/allow.yaml" >/dev/null
  # Legacy prepare path requires lib_hash in allowlist (stale-hash check).
  # Add it manually since judgment-eval no longer writes lib_hash.
  live_hash="$(bash "$LIB" hash spec-scope)"
  OP=spec-scope HASH="$live_hash" \
    yq -i '.ops[env(OP)].lib_hash = env(HASH)' "$TD/allow.yaml"

  printf 'The feature to draft scope for.\n' > "$TD/in"
  printf 'In scope: per-key rate limiting.\nOut of scope: distributed rate limiting.\n' > "$TD/draft"
  WORK="$TD/work"
}
teardown() { rm -rf "$TD"; }

# Convenience: run prepare phase with standard env
prep() {
  env SDLC_DRAFT_VERIFY=1 bash "$DV" prepare \
    --op spec-scope --input "$TD/in" --work "$WORK" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/draft" "$@"
}

# ────────────────────────────────────────────────────────────────────────────────
# Full C-2 two-phase flow (happy path): prepare → claude-review → finalize
# (rule 17: SDLC_DRAFT_VERIFY=1 + allowlisted draftable op)
# ────────────────────────────────────────────────────────────────────────────────
@test "full C-2 flow (no probe): prepare → stub-review → finalize → route-deepseek-ok" {
  # Phase 1: prepare
  prep >/dev/null
  # Phase 2: simulate harness claude adversarial review
  printf '{"final":"In scope: per-key rate limiting.\\nOut of scope: distributed.","caught":[]}' \
    > "$TD/rev.json"
  # Phase 3: finalize
  run bash "$DV" finalize --op spec-scope --work "$WORK" --review "$TD/rev.json" --out "$TD/final"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "route-deepseek-ok"
  [ -s "$TD/final" ]
  ! grep -q 'INJECTED-DEFECT' "$TD/final"
}

@test "full C-2 flow (with probe, recall PASS): prepare → caught-review → finalize → route-deepseek-ok" {
  # Phase 1: prepare with force-probe (orchestrator periodic probe sampling)
  prep --force-probe >/dev/null
  # Phase 2: claude review catches the injected defect marker
  printf '{"final":"corrected","caught":["flags-distributed-should-be-deferred"]}' > "$TD/rev.json"
  # Phase 3: finalize
  run bash "$DV" finalize --op spec-scope --work "$WORK" --review "$TD/rev.json"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "route-deepseek-ok"
}

@test "full C-2 flow (probe, recall FAIL): finalize → verify-recall-degraded (rubber-stamp caught)" {
  prep --force-probe >/dev/null
  # claude review MISSES the injected defect
  printf '{"final":"unchanged draft","caught":["something-unrelated"]}' > "$TD/rev.json"
  run bash "$DV" finalize --op spec-scope --work "$WORK" --review "$TD/rev.json"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "verify-recall-degraded"
}

# ────────────────────────────────────────────────────────────────────────────────
# Scope hard-stop: forbidden ops refused even if forged into the allowlist
# (rule 17 closed-set; security-sensitive/final-decision NEVER downgrade)
# ────────────────────────────────────────────────────────────────────────────────
@test "scope hard-stop: ga → structurally refused (even if forged-allowlisted)" {
  OP=ga TASK=spec-scope HASH=x \
    yq -i '.ops[env(OP)] = {"passed": true, "task_type": env(TASK), "lib_hash": env(HASH)}' "$TD/allow.yaml"
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" prepare \
    --op ga --input "$TD/in" --work "$WORK" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/draft"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-scope-hardstop"
}

@test "scope hard-stop: g1-judgment → refused (G1-G4 gate judgments stay full-claude)" {
  OP=g1-judgment TASK=spec-scope HASH=x \
    yq -i '.ops[env(OP)] = {"passed": true, "task_type": env(TASK), "lib_hash": env(HASH)}' "$TD/allow.yaml"
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" prepare \
    --op g1-judgment --input "$TD/in" --work "$WORK" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/draft"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-scope-hardstop"
}

@test "scope hard-stop: security-verdict → refused (security never downgraded)" {
  OP=security-verdict TASK=spec-scope HASH=x \
    yq -i '.ops[env(OP)] = {"passed": true, "task_type": env(TASK), "lib_hash": env(HASH)}' "$TD/allow.yaml"
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" prepare \
    --op security-verdict --input "$TD/in" --work "$WORK" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/draft"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-scope-hardstop"
}

@test "scope hard-stop: arch-decision → refused (final arch decisions stay full-claude)" {
  OP=arch-decision TASK=spec-scope HASH=x \
    yq -i '.ops[env(OP)] = {"passed": true, "task_type": env(TASK), "lib_hash": env(HASH)}' "$TD/allow.yaml"
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" prepare \
    --op arch-decision --input "$TD/in" --work "$WORK" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/draft"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-scope-hardstop"
}

# ────────────────────────────────────────────────────────────────────────────────
# SDLC_DRAFT_VERIFY unset → route-claude-disabled (byte-identical to full-claude)
# (rule 17: off → orchestrator never diverges from pre-C2 behavior)
# ────────────────────────────────────────────────────────────────────────────────
@test "SDLC_DRAFT_VERIFY unset → route-claude-disabled (full-claude path, byte-identical)" {
  run env -u SDLC_DRAFT_VERIFY bash "$DV" prepare \
    --op spec-scope --input "$TD/in" --work "$WORK" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/draft"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-disabled"
}

@test "SDLC_DRAFT_VERIFY=0 → route-claude-disabled" {
  run env SDLC_DRAFT_VERIFY=0 bash "$DV" prepare \
    --op spec-scope --input "$TD/in" --work "$WORK" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/draft"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-disabled"
}

# ────────────────────────────────────────────────────────────────────────────────
# Op not in allowlist → route-claude-not-allowlisted (fail-closed)
# Covers: a draftable-type op that hasn't been human-evaluated yet (no allowlist entry),
# and "no-downstream-signal" task_types that failed human_checked gate in judgment-eval.
# ────────────────────────────────────────────────────────────────────────────────
@test "op not in allowlist → route-claude-not-allowlisted (fail-closed)" {
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" prepare \
    --op plan-decomp --input "$TD/in" --work "$WORK" \
    --allowlist "$TD/allow.yaml" --stub-draft "$TD/draft"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-not-allowlisted"
}

@test "allowlist file missing → route-claude-not-draftable" {
  run env SDLC_DRAFT_VERIFY=1 bash "$DV" prepare \
    --op spec-scope --input "$TD/in" --work "$WORK" \
    --allowlist "$TD/no-such.yaml" --stub-draft "$TD/draft"
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-not-draftable"
}

# ────────────────────────────────────────────────────────────────────────────────
# Circuit-breaker: repeated verify-recall misses → breaker-open
# ────────────────────────────────────────────────────────────────────────────────
@test "7 consecutive probe misses → breaker trips (route-claude-breaker-open)" {
  # drive 7 miss cycles to fill the window above threshold
  i=0
  while [ "$i" -lt 7 ]; do
    prep --force-probe >/dev/null 2>&1
    printf '{"final":"unchanged","caught":["wrong-marker"]}' > "$TD/rev-miss.json"
    bash "$DV" finalize --op spec-scope --work "$WORK" --review "$TD/rev-miss.json" >/dev/null 2>&1 || true
    i=$((i+1))
    rm -rf "$WORK"
  done
  # now breaker should be open
  run prep
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "route-claude-breaker-open"
}
