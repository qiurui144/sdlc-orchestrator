#!/usr/bin/env bats
# C-1 cost-measurement: pricing rows + price lookup + --compare net (null≠0, coverage).

setup() {
  R="${BATS_TEST_DIRNAME}/../.."
  COST="$R/skills/cost-estimation/cost.sh"
  PRICING="$R/config/pricing.yaml"
  TD="$(mktemp -d)"
}
teardown() { rm -rf "$TD"; }

# --- Task 1: pricing + price lookup ---

@test "pricing.yaml has deepseek + qwen rows" {
  yq -e '.tiers.deepseek.input and .tiers.deepseek.output' "$PRICING" >/dev/null
  yq -e '.tiers.qwen.input and .tiers.qwen.output' "$PRICING" >/dev/null
}

@test "cost.sh price <provider> <in> <out> -> usd (deepseek 1M+1M)" {
  # deepseek 0.435 in / 0.87 out per 1M -> 1M in + 1M out = 1.305 (verified 2026-06-13)
  run bash "$COST" price deepseek 1000000 1000000
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'usd=1\.30'
}

@test "cost.sh price unknown provider -> usd=null (NOT 0, HON-1)" {
  run bash "$COST" price nonesuch 1000 1000
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'usd=null'
}

@test "cost.sh price zero tokens -> usd=0.000000 (real zero, distinct from null)" {
  run bash "$COST" price deepseek 0 0
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'usd=0\.0'
}

# --- Task 4: --compare net algebra (null≠0, coverage) ---

@test "--compare: net = saved − spent − ds_wasted; null route unmeasured (not 0)" {
  cat > "$TD/tel.jsonl" <<'EOF'
{"op":"inventory-count","decision":"route-deepseek-ok","in":100,"out":50,"ds_usd":0.0001645,"claude_equiv_usd":0.000280}
{"op":"inventory-count","decision":"degrade-claude-online-grade-fail","in":80,"out":40,"ds_usd":0.0001316,"claude_equiv_usd":0.000224}
{"op":"inventory-count","decision":"route-claude-not-allowlisted","in":null,"out":null,"ds_usd":null,"claude_equiv_usd":null}
{"op":"inventory-count","decision":"route-deepseek-ok","in":null,"out":null,"ds_usd":null,"claude_equiv_usd":null}
EOF
  run bash "$COST" --compare "$TD/tel.jsonl"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'claude_saved_estimated=0.000280'   # only the measured route-ok, NOT the null one
  echo "$output" | grep -q 'ds_spent_measured=0.0001645'
  echo "$output" | grep -qE 'net_estimated=-'                  # negative = honest (mechanical op + degrade waste)
  echo "$output" | grep -q 'coverage=0.6'                      # 2 measured (1 route + 1 degrade) / 3 attempts
  echo "$output" | grep -q 'routes=2'; echo "$output" | grep -q 'degrades=1'; echo "$output" | grep -q 'unmeasured=1'
}

@test "--compare: degrade with null ds_usd is UNMEASURED, NOT 0 waste (G3 B-1, no false savings)" {
  # 1 measured route + 4 degrades that burned token but returned no usage -> the waste is UNMEASURED,
  # must NOT read as 0 (which would let net look like a clean saving). -> low coverage + flag.
  { printf '{"op":"x","decision":"route-deepseek-ok","in":10,"out":10,"ds_usd":0.0000274,"claude_equiv_usd":0.000048}\n'
    for _ in 1 2 3 4; do printf '{"op":"x","decision":"degrade-claude-online-grade-fail","in":null,"out":null,"ds_usd":null,"claude_equiv_usd":null}\n'; done
  } > "$TD/tel.jsonl"
  run bash "$COST" --compare "$TD/tel.jsonl"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'degrades=4'
  echo "$output" | grep -q 'unmeasured=4'        # the 4 burned-but-unmeasured degrades
  echo "$output" | grep -q 'coverage=0.2'        # 1 measured / 5 attempts
  echo "$output" | grep -q 'non-representative'  # flagged, NOT silently reported as a clean net
}

@test "--compare: a null-operand route is UNMEASURED, never a fabricated 0 saving (HON-1)" {
  printf '{"op":"x","decision":"route-deepseek-ok","in":null,"out":null,"ds_usd":null,"claude_equiv_usd":null}\n' > "$TD/tel.jsonl"
  run bash "$COST" --compare "$TD/tel.jsonl"
  echo "$output" | grep -q 'routes=1'; echo "$output" | grep -q 'unmeasured=1'
  echo "$output" | grep -q 'coverage=0'
  echo "$output" | grep -q 'claude_saved_estimated=0'    # no measured saving (not fabricated)
  echo "$output" | grep -q 'non-representative'
}

@test "--compare: degrade-call-failed contributes 0 waste (burned nothing)" {
  cat > "$TD/tel.jsonl" <<'EOF'
{"op":"x","decision":"route-deepseek-ok","in":10,"out":10,"ds_usd":0.0000274,"claude_equiv_usd":0.000048}
{"op":"x","decision":"degrade-claude-call-failed","in":null,"out":null,"ds_usd":0,"claude_equiv_usd":null}
EOF
  run bash "$COST" --compare "$TD/tel.jsonl"
  # net = saved(0.000048) - spent(0.0000274) - wasted(0) = positive
  echo "$output" | grep -qE 'net_estimated=[0-9]'    # positive
  echo "$output" | grep -q 'degrades=1'
}

@test "--compare: no telemetry -> UNMEASURED, exit 0 (not a crash)" {
  run bash "$COST" --compare "$TD/nope.jsonl"
  [ "$status" -eq 0 ]; echo "$output" | grep -q UNMEASURED
}
