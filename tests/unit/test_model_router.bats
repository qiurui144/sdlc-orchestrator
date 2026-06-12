#!/usr/bin/env bats
# model-router (M1): deterministic risk->provider routing. Default disabled => all claude (opt-in).
ROUTE="$BATS_TEST_DIRNAME/../../skills/model-router/route.sh"
CFG="$BATS_TEST_DIRNAME/../../config/model-routing.yaml"

@test "default config exists and is disabled (opt-in)" {
  [ -f "$CFG" ]
  grep -qE '^enabled:[[:space:]]*false' "$CFG"
  grep -qE '^high_provider:[[:space:]]*claude' "$CFG"
}

@test "disabled config + explicit tier -> claude for ALL tiers (zero behavior change)" {
  for t in LOW NORMAL HIGH; do
    run env SDLC_MULTI_MODEL= "$ROUTE" --tier "$t" --model-class per-agent --config "$CFG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"provider=claude"* ]] || { echo "tier $t got: $output"; false; }
    [[ "$output" == *"reason=multi-model-disabled"* ]]
  done
}

@test "missing config file -> claude (fail-safe), exit 0" {
  run "$ROUTE" --tier LOW --model-class mechanical --config /nonexistent/x.yaml
  [ "$status" -eq 0 ]; [[ "$output" == *"provider=claude"* ]]
}

@test "enabled: LOW/mechanical -> deepseek, NORMAL -> claude, HIGH -> claude" {
  run env SDLC_MULTI_MODEL=1 "$ROUTE" --tier LOW --model-class mechanical --config "$CFG"
  [[ "$output" == *"provider=deepseek"* ]] && [[ "$output" == *"model=deepseek-v4-flash"* ]]
  run env SDLC_MULTI_MODEL=1 "$ROUTE" --tier NORMAL --model-class per-agent --config "$CFG"
  [[ "$output" == *"provider=claude"* ]] && [[ "$output" == *"reason=normal-default-claude"* ]]
  run env SDLC_MULTI_MODEL=1 "$ROUTE" --tier HIGH --model-class judgment --config "$CFG"
  [[ "$output" == *"provider=claude"* ]] && [[ "$output" == *"reason=high-never-externalized"* ]]
}

@test "enabled but low_provider unset -> claude fallback (not empty provider)" {
  T="$(mktemp)"; printf 'enabled: true\nlow_provider: ""\nlow_model: ""\n' > "$T"
  run env SDLC_MULTI_MODEL=1 "$ROUTE" --tier LOW --model-class mechanical --config "$T"
  [ "$status" -eq 0 ]; [[ "$output" == *"provider=claude"* ]]; [[ "$output" == *"fallback-claude"* ]]
  rm -f "$T"
}

@test "enabled but unknown/empty tier -> claude (fail-safe HIGH)" {
  run env SDLC_MULTI_MODEL=1 "$ROUTE" --tier BOGUS --model-class judgment --config "$CFG"
  [ "$status" -eq 0 ]; [[ "$output" == *"provider=claude"* ]]; [[ "$output" == *"reason=uncertain-tier-to-claude"* ]]
}

@test "e2e: enabled LOW routes to deepseek, then call.sh stub returns content" {
  CALL="$BATS_TEST_DIRNAME/../../skills/model-provider/call.sh"
  dec="$(env SDLC_MULTI_MODEL=1 "$ROUTE" --tier LOW --model-class mechanical --config "$CFG")"
  prov="$(printf '%s' "$dec" | sed -n 's/.*provider=\([a-z]*\).*/\1/p')"
  [ "$prov" = deepseek ]
  M="$(mktemp)"; printf '[{"role":"user","content":"hi"}]' > "$M"
  S="$(mktemp)"; printf '{"choices":[{"message":{"content":"ok-routed"}}]}' > "$S"
  run env DEEPSEEK_BASE_URL=http://x DEEPSEEK_MODEL=deepseek-v4-flash DEEPSEEK_API_KEY=sk-test \
    "$CALL" --provider "$prov" --messages "$M" --stub "$S"
  [ "$status" -eq 0 ]; [[ "$output" == *"ok-routed"* ]]; rm -f "$M" "$S"
}
