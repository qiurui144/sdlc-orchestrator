#!/usr/bin/env bats
# ui-vision-judge (v0.30): deterministic driver for a provider-agnostic vision judge.
# ZERO network: HTTP is behind --stub <fixture>; the real curl POST + §4.5-D multi-tier
# compat matrix are §7.3 PENDING-VERIFY. The judge NEVER emits a verdict — only a SOFT,
# schema-bounded annotation (deterministic-verdict-supremacy).
setup() {
  J="$BATS_TEST_DIRNAME/../../skills/ui-vision-judge/judge.sh"
  TMP="$(mktemp -d)"; mkdir -p "$TMP/docs/screenshots/t"
  printf 'PNGDATA' > "$TMP/docs/screenshots/t/a.png"
  # keep every run-dir inside the per-test tmp (teardown cleans it) — no repo reports/runs litter (§1.1.6)
  export SDLC_RUN_ROOT="$TMP/runs"
}
teardown() { rm -rf "$TMP"; }

@test "skeleton: no args is usage exit 2" {
  run bash "$J"; [ "$status" -eq 2 ]
}
@test "skeleton: unknown --kind exit 2" {
  run bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --kind bogus --dry-run
  [ "$status" -eq 2 ]
}
@test "skeleton: image not under a §6.4 dir exit 2" {
  printf x > "$TMP/loose.png"
  run bash "$J" --image "$TMP/loose.png" --question q --dry-run
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "must be under docs/screenshots"
}
@test "skeleton: image not found exit 3" {
  run bash "$J" --image "$TMP/docs/screenshots/t/missing.png" --question q --dry-run
  [ "$status" -eq 3 ]
}
@test "skeleton: dry-run unconfigured exits 0" {
  run env -u SDLC_VISION_BASE_URL -u SDLC_VISION_MODEL -u SDLC_VISION_API_KEY \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --dry-run
  [ "$status" -eq 0 ]
}

# --- T2: env-config gate (non-dry) ---
@test "config: unconfigured (no env) degrades unavailable exit 0" {
  run env -u SDLC_VISION_BASE_URL -u SDLC_VISION_MODEL -u SDLC_VISION_API_KEY \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --stub /dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"vision_status":"unavailable"'
  echo "$output" | grep -q '"reason":"unconfigured"'
}
@test "config: only 2 of 3 set still degrades unconfigured" {
  # env options (-u) MUST precede assignments — GNU/BSD env rejects -u after NAME=VALUE (exit 127).
  run env -u SDLC_VISION_API_KEY SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=m \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --stub /dev/null
  [ "$status" -eq 0 ]; echo "$output" | grep -q '"reason":"unconfigured"'
}

# --- T3: portable base64 data-URI (R15) ---
@test "base64: data-URI is unwrapped and round-trips byte-identical" {
  printf '\211PNG\r\n\032\nrandombytes-0123456789-abcdefghijklmnop' > "$TMP/docs/screenshots/t/b.png"
  run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=m SDLC_VISION_API_KEY=sk-LIVE \
    bash "$J" --image "$TMP/docs/screenshots/t/b.png" --question q --emit-data-uri
  [ "$status" -eq 0 ]
  case "$output" in data:image/png\;base64,*) ;; *) false;; esac
  # exactly one line (no 76-col wrap)
  [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" -eq 0 ]
  # decode the payload after the comma and compare to source
  printf '%s' "${output#data:image/png;base64,}" | base64 -d > "$TMP/decoded.bin" 2>/dev/null || \
    printf '%s' "${output#data:image/png;base64,}" | base64 --decode > "$TMP/decoded.bin"
  cmp "$TMP/docs/screenshots/t/b.png" "$TMP/decoded.bin"
}

# --- T4: OpenAI-compat request build (§4.5-A/C) ---
@test "request: build emits valid OpenAI-compat JSON with response_format + >=2 few-shot" {
  run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=qwen-vl-max SDLC_VISION_API_KEY=sk-LIVE \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question "looks broken?" --emit-request
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null            # valid JSON
  [ "$(echo "$output" | jq -r '.model')" = "qwen-vl-max" ]
  t="$(echo "$output" | jq -r '.response_format.type')"; case "$t" in json_object|json_schema) ;; *) false;; esac
  # >=2 few-shot user messages precede the image-bearing message (3 user msgs total)
  [ "$(echo "$output" | jq '[.messages[] | select(.role=="user")] | length')" -ge 3 ]
  echo "$output" | jq -e '.messages[-1].content[] | select(.type=="image_url")' >/dev/null
}
@test "request: schema-bounded — no verdict/pass/fail field requested anywhere" {
  run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=m SDLC_VISION_API_KEY=sk-LIVE \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --emit-request
  ! echo "$output" | grep -qi '"verdict"'      # no verdict key designed into the request (non-vacuous)
}

# --- T5: stubbed call + deterministic grounding validate + retry-degrade (§4.5-A/B) ---
@test "validate: good-JSON stub parses to schema-bounded looks_ok judgment" {
  printf '{"choices":[{"message":{"content":"{\\"looks_ok\\":true,\\"confidence\\":0.9,\\"reason\\":\\"ok\\"}"}}]}' > "$TMP/good.json"
  run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=m SDLC_VISION_API_KEY=sk-LIVE \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --kind looks_ok --stub "$TMP/good.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.looks_ok')" = "true" ]
  [ "$(echo "$output" | jq -r '.vision_status')" = "ok" ]
}
@test "validate: grounding fail (looks_ok kind but score field) ⇒ degrade after retries" {
  printf '{"choices":[{"message":{"content":"{\\"score\\":77}"}}]}' > "$TMP/wrongkind.json"
  run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=m SDLC_VISION_API_KEY=sk-LIVE \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --kind looks_ok --max-retries 2 --stub "$TMP/wrongkind.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.vision_status')" = "unavailable" ]
  [ "$(echo "$output" | jq -r '.reason')" = "retries-exhausted" ]
}

# --- T6: http/timeout error → degrade (never crash, never PASS) (§4.5-E, §7) ---
@test "httperr: 4xx body with no choices ⇒ degrade http-error exit 0" {
  printf '{"error":{"message":"bad key","code":401}}' > "$TMP/e401.json"
  run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=m SDLC_VISION_API_KEY=sk-LIVE \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --max-retries 2 --stub "$TMP/e401.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.vision_status')" = "unavailable" ]
  case "$(echo "$output" | jq -r '.reason')" in http-error|retries-exhausted) ;; *) false;; esac
}
@test "httperr: empty stub (timeout-class) ⇒ degrade reason=timeout exit 0, never crash" {
  : > "$TMP/empty.json"
  run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=m SDLC_VISION_API_KEY=sk-LIVE \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --max-retries 2 --stub "$TMP/empty.json"
  [ "$status" -eq 0 ]; [ "$(echo "$output" | jq -r '.vision_status')" = "unavailable" ]
  # reason=timeout must be REACHABLE as a terminal output (spec §5/§7; was unreachable pre-fix)
  [ "$(echo "$output" | jq -r '.reason')" = "timeout" ]
}

# --- T7: secret redaction everywhere INCL. fed-back error body (R2 / case 5b — BLOCKING) ---
@test "redact: leaked key in a fed-back error body appears NOWHERE (R2 / case 5b — BLOCKING)" {
  LK="sk-LEAKED-LIVE-KEY-abc123"
  # stub error body that hostilely echoes the Authorization header back
  printf '{"error":{"message":"unauthorized: Authorization: Bearer %s"}}' "$LK" > "$TMP/leak.json"
  RUNROOT="$TMP/runs"
  run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=m SDLC_VISION_API_KEY="$LK" \
    SDLC_RUN_ROOT="$RUNROOT" \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --max-retries 2 --stub "$TMP/leak.json"
  [ "$status" -eq 0 ]
  # the live key must NOT be in stdout
  echo "$output" | grep -qF "$LK" && { echo "LEAK in stdout"; false; }
  # nor anywhere in the run dir
  if [ -d "$RUNROOT" ]; then ! grep -rqF "$LK" "$RUNROOT"; fi
}
@test "redact: key with sed/BRE metachars (. / ^ \$ * [) is fully scrubbed (R2 hardening — adversarial)" {
  # the prior sed-escaper leaked ANY key containing a BRE metachar — i.e. almost every real key.
  LK='sk-live.key/0^1$2*3[4'
  printf '{"error":{"message":"the api_key %s is invalid"}}' "$LK" > "$TMP/leak2.json"
  RUNROOT="$TMP/runs2"
  run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=m SDLC_VISION_API_KEY="$LK" \
    SDLC_RUN_ROOT="$RUNROOT" \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --max-retries 2 --stub "$TMP/leak2.json"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "$LK" && { echo "LEAK in stdout"; false; }
  if [ -d "$RUNROOT" ]; then ! grep -rqF "$LK" "$RUNROOT"; fi
}
@test "redact: dry-run shows sk-*** not the key" {
  run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=m SDLC_VISION_API_KEY=sk-REALKEY-xyz \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --dry-run
  echo "$output" | grep -q 'sk-\*\*\*'
  echo "$output" | grep -qF 'sk-REALKEY-xyz' && false || true
}

# --- T8: telemetry (key redacted) + remaining adversarial set (§4.5-F, §9) ---
@test "telemetry: record has fields + key REDACTED" {
  printf '{"error":{"message":"x"}}' > "$TMP/e.json"; RUNROOT="$TMP/tel"
  run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=qwen-vl-max SDLC_VISION_API_KEY=sk-LIVE-tel \
    SDLC_RUN_ROOT="$RUNROOT" bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --max-retries 1 --stub "$TMP/e.json"
  f="$(find "$RUNROOT" -name telemetry.jsonl | head -1)"; [ -n "$f" ]
  grep -q '"agent_id":"ui-vision-judge"' "$f"; grep -q '"error_kind"' "$f"
  grep -qF 'sk-LIVE-tel' "$f" && false || true
}
@test "adversarial(7): hostile extra verdict field is DROPPED from output" {
  printf '{"choices":[{"message":{"content":"{\\"looks_ok\\":true,\\"confidence\\":0.5,\\"reason\\":\\"x\\",\\"verdict\\":\\"PASS\\"}"}}]}' > "$TMP/h.json"
  run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=m SDLC_VISION_API_KEY=sk-LIVE \
    bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --kind looks_ok --stub "$TMP/h.json"
  [ "$(echo "$output" | jq -r '.looks_ok')" = "true" ]
  echo "$output" | jq -e 'has("verdict")' >/dev/null && false || true
}
@test "sigpipe: 20x parse stress is stable (SE16)" {
  printf '{"choices":[{"message":{"content":"{\\"looks_ok\\":true,\\"confidence\\":0.9,\\"reason\\":\\"ok\\"}"}}]}' > "$TMP/g.json"
  n=0; while [ "$n" -lt 20 ]; do
    run env SDLC_VISION_BASE_URL=http://x/v1 SDLC_VISION_MODEL=m SDLC_VISION_API_KEY=sk-LIVE \
      bash "$J" --image "$TMP/docs/screenshots/t/a.png" --question q --stub "$TMP/g.json"
    [ "$status" -eq 0 ]; n=$((n+1))
  done
}
