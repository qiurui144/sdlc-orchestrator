#!/usr/bin/env bats
# executor.sh — online routing decision engine. Safety adversarial tests are
# one-vote-veto: judgment can't be externalized, confidently-wrong is caught,
# stale hash degrades, off is claude.

setup() {
  R="${BATS_TEST_DIRNAME}/../.."
  EXEC="$R/skills/model-router/executor.sh"
  EVAL="$R/skills/model-eval/eval.sh"
  FIX="$R/skills/model-eval/fixtures/inventory-count-diff"
  TD="$(mktemp -d)"
  # build a PASSED allowlist whose sources_hash matches the live fixtures (stub all-correct).
  for s in 1 2 3; do for prov in deepseek claude; do
    mkdir -p "$TD/stub/$prov/seed-$s"
    for f in "$FIX"/*.json; do jq -r '.golden' "$f" > "$TD/stub/$prov/seed-$s/$(basename "$f" .json).out"; done
  done; done
  "$EVAL" --task inventory-count-diff --providers deepseek,claude --seeds 3 --stub "$TD/stub" --out "$TD/allow.yaml" >/dev/null
  # input + the correct (derived) answer + a confidently-wrong answer for case-1
  jq -r '.input'  "$FIX/case-1.json" > "$TD/in"
  jq -r '.golden' "$FIX/case-1.json" > "$TD/correct"
  printf 'agent=999\n' > "$TD/wrong"
  TEL="$TD/routing.jsonl"
  # circuit-breaker state isolated per test (pinned file: $CIRC/<task_type>.json)
  export SDLC_CIRCUIT_DIR="$TD/circuit"
  CIRC="$SDLC_CIRCUIT_DIR"
  LIVE_HASH="$(yq -r '.tasks."inventory-count-diff".sources_hash' "$TD/allow.yaml")"
}

# seed_window <hash> <n_fails> <n_passes> — write a breaker state file
seed_window() {
  mkdir -p "$CIRC"
  jq -nc --arg h "$1" --argjson f "$2" --argjson p "$3" \
    '{sources_hash:$h, window: ([range($f)|1] + [range($p)|0])}' > "$CIRC/inventory-count-diff.json"
}
teardown() { rm -rf "$TD"; }

dec() { echo "$output" | sed -n 's/^decision=//p'; }

@test "off (SDLC_MULTI_MODEL unset) -> route-claude-disabled, exit 10" {
  run env -u SDLC_MULTI_MODEL "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct"
  [ "$status" -eq 10 ]; [ "$(dec)" = "route-claude-disabled" ]
}

@test "FORGED allowlist cannot externalize a judgment op (closed map has no key)" {
  # craft an allowlist that marks a judgment op 'spec' passed -> still refused.
  cp "$TD/allow.yaml" "$TD/forged.yaml"
  yq -i '.tasks.spec.passed = true | .tasks.spec.sources_hash = "x" | .tasks.spec.f1 = 0.99' "$TD/forged.yaml"
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op spec --input "$TD/in" --allowlist "$TD/forged.yaml" --stub-output "$TD/correct"
  [ "$status" -eq 10 ]; [ "$(dec)" = "route-claude-no-tasktype" ]
}

@test "allowlist passed=false -> route-claude-not-allowlisted" {
  cp "$TD/allow.yaml" "$TD/np.yaml"; yq -i '.tasks."inventory-count-diff".passed = false' "$TD/np.yaml"
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/np.yaml" --stub-output "$TD/correct"
  [ "$status" -eq 10 ]; [ "$(dec)" = "route-claude-not-allowlisted" ]
}

@test "stale sources_hash -> route-claude-stale-hash" {
  cp "$TD/allow.yaml" "$TD/stale.yaml"; yq -i '.tasks."inventory-count-diff".sources_hash = "deadbeef"' "$TD/stale.yaml"
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/stale.yaml" --stub-output "$TD/correct"
  [ "$status" -eq 10 ]; [ "$(dec)" = "route-claude-stale-hash" ]
}

@test "correct deepseek output passes online oracle -> route-deepseek-ok, --out written" {
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct" --out "$TD/result" --telemetry "$TEL"
  [ "$status" -eq 0 ]; [ "$(dec)" = "route-deepseek-ok" ]
  diff -q "$TD/result" "$TD/correct"
  grep -q '"decision":"route-deepseek-ok"' "$TEL"
}

@test "confidently-wrong output caught by online oracle -> degrade (NOT used)" {
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/wrong" --out "$TD/result"
  [ "$status" -eq 10 ]; [ "$(dec)" = "degrade-claude-online-grade-fail" ]
  [ ! -f "$TD/result" ]  # wrong output must NOT be handed to the caller
}

# --- G3 adversarial C-1: forged f1 must NOT lower the online-oracle bar ---

@test "C-1: forged f1=0 (valid sources_hash) + wrong output -> STILL degrade (hard online floor)" {
  cp "$TD/allow.yaml" "$TD/forge.yaml"; yq -i '.tasks."inventory-count-diff".f1 = 0' "$TD/forge.yaml"
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/forge.yaml" --stub-output "$TD/wrong" --out "$TD/result"
  [ "$status" -eq 10 ]; [ "$(dec)" = "degrade-claude-online-grade-fail" ]
  [ ! -f "$TD/result" ]
}

@test "C-1: forged f1=0.10 (bar would be 0.0) + wrong output -> STILL degrade" {
  cp "$TD/allow.yaml" "$TD/forge.yaml"; yq -i '.tasks."inventory-count-diff".f1 = 0.10' "$TD/forge.yaml"
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/forge.yaml" --stub-output "$TD/wrong" --out "$TD/result"
  [ "$status" -eq 10 ]; [ "$(dec)" = "degrade-claude-online-grade-fail" ]
  [ ! -f "$TD/result" ]
}

@test "C-1: non-numeric stored_f1 -> degrade (corrupt threshold, never NaN-passes)" {
  cp "$TD/allow.yaml" "$TD/forge.yaml"; yq -i '.tasks."inventory-count-diff".f1 = "abc"' "$TD/forge.yaml"
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/forge.yaml" --stub-output "$TD/correct" --out "$TD/result"
  [ "$status" -eq 10 ]; [ "$(dec)" = "route-claude-not-allowlisted" ]
  [ ! -f "$TD/result" ]
}

@test "C-1: a genuinely-correct output STILL routes under a legit (high) f1" {
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct" --out "$TD/result"
  [ "$status" -eq 0 ]; [ "$(dec)" = "route-deepseek-ok" ]
  diff -q "$TD/result" "$TD/correct"
}

# --- I-1: op string can't yq-inject a task_type ---

@test "I-1: op with yq-injection metachars -> route-claude-no-tasktype (validated charset)" {
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op 'spec" // "inventory-count-diff' --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct" --out "$TD/result"
  [ "$status" -eq 10 ]; [ "$(dec)" = "route-claude-no-tasktype" ]
  [ ! -f "$TD/result" ]
}

# --- M-1: disabled path writes nothing, even with --telemetry ---

@test "M-1: off + --telemetry -> route-claude-disabled, NO telemetry written" {
  run env -u SDLC_MULTI_MODEL "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct" --telemetry "$TEL"
  [ "$status" -eq 10 ]; [ "$(dec)" = "route-claude-disabled" ]
  [ ! -f "$TEL" ]
}

# --- Task 6: per-task circuit-breaker (rolling-20 online-fail-rate) ---

@test "breaker: >30% fails in rolling-20 -> route-claude-breaker-open (even with a correct output)" {
  seed_window "$LIVE_HASH" 7 13   # 7/20 = 35% > 30%
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct" --out "$TD/result"
  [ "$status" -eq 10 ]; [ "$(dec)" = "route-claude-breaker-open" ]
  [ ! -f "$TD/result" ]
}

@test "breaker: exactly 30% (6/20) does NOT trip -> route-deepseek-ok" {
  seed_window "$LIVE_HASH" 6 14
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct"
  [ "$status" -eq 0 ]; [ "$(dec)" = "route-deepseek-ok" ]
}

@test "breaker: window is ROLLING last-20 (old fails age out)" {
  # 7 fails followed by 14 passes: last-20 holds only 6 of the fails -> not tripped
  seed_window "$LIVE_HASH" 7 14
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct"
  [ "$status" -eq 0 ]; [ "$(dec)" = "route-deepseek-ok" ]
}

@test "breaker: RESET on new sources_hash (re-eval) -> routing re-enabled + state rewritten" {
  seed_window "stale-old-hash" 20 0   # fully tripped under the OLD hash
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct"
  [ "$status" -eq 0 ]; [ "$(dec)" = "route-deepseek-ok" ]
  [ "$(jq -r '.sources_hash' "$CIRC/inventory-count-diff.json")" = "$LIVE_HASH" ]
  [ "$(jq -r '.window | length' "$CIRC/inventory-count-diff.json")" = "1" ]
}

@test "breaker: transient single fail does not trip (denominator bounded)" {
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/wrong"
  [ "$status" -eq 10 ]; [ "$(dec)" = "degrade-claude-online-grade-fail" ]
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct"
  [ "$status" -eq 0 ]; [ "$(dec)" = "route-deepseek-ok" ]
}

@test "breaker: executor records online outcomes (fail=1, pass=0) and trims to 20" {
  seed_window "$LIVE_HASH" 0 20
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/wrong"
  [ "$status" -eq 10 ]
  [ "$(jq -r '.window | length' "$CIRC/inventory-count-diff.json")" = "20" ]
  [ "$(jq -r '.window[-1]' "$CIRC/inventory-count-diff.json")" = "1" ]
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.window[-1]' "$CIRC/inventory-count-diff.json")" = "0" ]
}

# --- C-1 Task 3: telemetry enriched with measured token + usd ---

@test "telemetry: route-deepseek-ok enriched with token + ds_usd + claude_equiv_usd (haiku)" {
  printf '{"in":100,"out":50}' > "$TD/usage"
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct" --stub-usage "$TD/usage" --out "$TD/result" --telemetry "$TEL"
  [ "$status" -eq 0 ]; [ "$(dec)" = "route-deepseek-ok" ]
  grep -q '"in":100' "$TEL"; grep -q '"out":50' "$TEL"
  grep -qE '"ds_usd":[0-9]' "$TEL"; grep -qE '"claude_equiv_usd":[0-9]' "$TEL"
  # haiku in 0.8/out 4 per 1M: claude_equiv = (100*0.8+50*4)/1e6 = 0.00028; deepseek (100*.55+50*2.19)/1e6=0.0001645
  grep -q '"claude_equiv_usd":0.000280' "$TEL"
}

@test "telemetry: missing usage -> in/out null (NOT 0, HON-1)" {
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/allow.yaml" --stub-output "$TD/correct" --out "$TD/result" --telemetry "$TEL"
  [ "$status" -eq 0 ]
  grep -q '"in":null' "$TEL"; grep -q '"ds_usd":null' "$TEL"
}

@test "telemetry: route-claude-* (not-allowlisted) has null usd (no deepseek call)" {
  cp "$TD/allow.yaml" "$TD/np.yaml"; yq -i '.tasks."inventory-count-diff".passed = false' "$TD/np.yaml"
  run env SDLC_MULTI_MODEL=1 "$EXEC" --task-op inventory-count --input "$TD/in" --allowlist "$TD/np.yaml" --stub-output "$TD/correct" --telemetry "$TEL"
  [ "$(dec)" = "route-claude-not-allowlisted" ]
  grep -q '"ds_usd":null' "$TEL"; grep -q '"in":null' "$TEL"
}
