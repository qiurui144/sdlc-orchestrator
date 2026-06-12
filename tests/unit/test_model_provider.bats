#!/usr/bin/env bats
# model-provider (M1): OpenAI-compat text caller. stub seam (zero-network), schema/retry/degrade,
# exit codes, redact-ALL-keys (metachar-safe).
CALL="$BATS_TEST_DIRNAME/../../skills/model-provider/call.sh"
setup() { MSGS="$(mktemp)"; printf '[{"role":"user","content":"hi"}]' > "$MSGS"; }
teardown() { rm -f "$MSGS"; }

@test "no provider arg -> usage exit 2" {
  run "$CALL" --messages "$MSGS"; [ "$status" -eq 2 ]
}

@test "provider configured-absent (no env) -> exit 6 provider-unconfigured" {
  run env DEEPSEEK_BASE_URL= DEEPSEEK_MODEL= DEEPSEEK_API_KEY= "$CALL" --provider deepseek --messages "$MSGS"
  [ "$status" -eq 6 ]; [[ "$output" == *"provider-unconfigured"* ]]
}

@test "stub success -> emits model content, exit 0" {
  S="$(mktemp)"; printf '{"choices":[{"message":{"content":"{\\"answer\\":\\"42\\"}"}}]}' > "$S"
  run env DEEPSEEK_BASE_URL=http://x DEEPSEEK_MODEL=deepseek-v4-flash DEEPSEEK_API_KEY=sk-test \
    "$CALL" --provider deepseek --messages "$MSGS" --stub "$S"
  [ "$status" -eq 0 ]; [[ "$output" == *'"answer":"42"'* ]]; rm -f "$S"
}

@test "stub empty content -> degrade exit 7" {
  S="$(mktemp)"; printf '{"choices":[{"message":{"content":""}}]}' > "$S"
  run env DEEPSEEK_BASE_URL=http://x DEEPSEEK_MODEL=deepseek-v4-flash DEEPSEEK_API_KEY=sk-test \
    "$CALL" --provider deepseek --messages "$MSGS" --stub "$S" --max-retries 1
  [ "$status" -eq 7 ]; [[ "$output" == *"fallback"* ]]; rm -f "$S"
}

@test "A4-I1: malformed --messages JSON -> exit 2 (no false stub success)" {
  BAD="$(mktemp)"; printf 'not json{' > "$BAD"
  S="$(mktemp)"; printf '{"choices":[{"message":{"content":"x"}}]}' > "$S"
  run env DEEPSEEK_BASE_URL=http://x DEEPSEEK_MODEL=deepseek-v4-flash DEEPSEEK_API_KEY=sk-test \
    "$CALL" --provider deepseek --messages "$BAD" --stub "$S"
  [ "$status" -eq 2 ]; [[ "$output" == *"bad-messages"* ]]
  rm -f "$BAD" "$S"
}

@test "metachar key never leaks in degrade feedback (per-provider redaction)" {
  K='sk-a.b/c^d$e*f[g+h=i'
  S="$(mktemp)"; printf '{"error":{"message":"bad key %s echoed"}}' "$K" > "$S"
  run env DEEPSEEK_BASE_URL=http://x DEEPSEEK_MODEL=deepseek-v4-flash DEEPSEEK_API_KEY="$K" \
    SDLC_RUN_ROOT="$BATS_TEST_TMPDIR/runs" \
    "$CALL" --provider deepseek --messages "$MSGS" --stub "$S" --max-retries 1
  [ "$status" -eq 7 ]
  ! ( printf '%s' "$output"; cat "$BATS_TEST_TMPDIR/runs"/*/feedback.log 2>/dev/null ) | grep -qF "$K"
  rm -f "$S"
}
