#!/usr/bin/env bash
# call.sh — provider-agnostic OpenAI-compat TEXT caller (M1). Ports the ui-vision-judge/judge.sh
# kernel for text: env-config, schema-guided request, response validate, retry (<=3), degrade,
# redact-ALL-keys, telemetry, --stub seam. ZERO product logic; the provider is the user's config.
# DETERMINISTIC-VERDICT-SUPREMACY: output is raw model content; a gate verdict is NEVER derived here.
# Exit: 0 ok . 2 usage . 6 provider-unconfigured . 7 degraded (provider failed -> caller falls back to claude).
# bash 3.2-safe. SE16-safe (case, no | grep -q control flow).
set -uo pipefail
usage() { echo "usage: call.sh --provider <deepseek|openai|qwen> --messages <file.json> [--model <id>] [--schema <f>] [--max-retries N] [--timeout S] [--stub <f>]" >&2; exit 2; }

provider="" msgs="" model="" schema="" max_retries=3 timeout_s=60 stub=""
[ "$#" -gt 0 ] || usage
while [ "$#" -gt 0 ]; do case "$1" in
  --provider) provider="$2"; shift 2;;
  --messages) msgs="$2"; shift 2;;
  --model) model="$2"; shift 2;;
  --schema) schema="$2"; shift 2;;
  --max-retries) max_retries="$2"; shift 2;;
  --timeout) timeout_s="$2"; shift 2;;
  --stub) stub="$2"; shift 2;;
  *) echo "model-provider-unknown-arg: $1" >&2; usage;;
esac; done
case "$max_retries" in ''|*[!0-9]*) max_retries=3;; esac
case "$timeout_s" in ''|*[!0-9]*) timeout_s=60;; esac
[ -n "$provider" ] || usage
{ [ -n "$msgs" ] && [ -f "$msgs" ]; } || usage
# A4-I1 (adversarial): a malformed --messages must NOT silently produce an empty request that the
# stub path then reports as a false success. Validate it parses as a JSON array up front (exit 2).
jq -e 'type=="array"' "$msgs" >/dev/null 2>&1 || { echo "model-provider-bad-messages: $msgs is not a JSON array" >&2; exit 2; }

# resolve provider env prefix -> BASE/MODEL/KEY (qwen reads DASHSCOPE_* as alias)
prefix=""
case "$provider" in
  deepseek) prefix=DEEPSEEK;; openai) prefix=OPENAI;; qwen) prefix=QWEN;;
  *) echo "model-provider-bad-provider: $provider" >&2; exit 2;;
esac
eval "BASE=\"\${${prefix}_BASE_URL:-}\"; MODEL=\"\${${prefix}_MODEL:-}\"; KEY=\"\${${prefix}_API_KEY:-}\""
[ -n "$model" ] && MODEL="$model"
if [ "$provider" = qwen ]; then
  [ -z "$BASE" ] && BASE="${DASHSCOPE_BASE_URL:-}"
  [ -z "$KEY" ] && KEY="${DASHSCOPE_API_KEY:-}"
fi

# config gate: any of base/model/key absent => exit 6 (caller routes to claude). Not a crash.
if [ -z "$BASE" ] || [ -z "$MODEL" ] || [ -z "$KEY" ]; then
  echo "model-provider-unconfigured: $provider (need ${prefix}_BASE_URL/_MODEL/_API_KEY)" >&2; exit 6
fi

# redact(): LITERAL substitution of EVERY loaded provider key (not just the active one) — bash literal
# (quoted => no glob/regex), immune to any metachar in the key (judge.sh R2). Broadened Bearer fallback
# includes + / = (base64-ish tokens). Redacts cross-provider echoes too (R10).
redact() {
  local s="$1" k
  for k in "${DEEPSEEK_API_KEY:-}" "${OPENAI_API_KEY:-}" "${QWEN_API_KEY:-}" "${DASHSCOPE_API_KEY:-}"; do
    [ -n "$k" ] && s="${s//"$k"/sk-***}"
  done
  printf '%s' "$s" | sed -E 's#Bearer [A-Za-z0-9._/+=-]{6,}#Bearer sk-***#g'
}
run_dir="${SDLC_RUN_ROOT:-reports/runs}/$(date +%Y%m%dT%H%M%S)_$$_model-provider"

# build OpenAI-compat request from the messages file (+ optional json_schema response_format)
build_request() {
  local rf
  if [ -n "$schema" ] && [ -f "$schema" ]; then rf="$(jq -nc --slurpfile s "$schema" '{type:"json_schema", json_schema:$s[0]}')"
  else rf='{"type":"json_object"}'; fi
  jq -n --arg model "$MODEL" --argjson rf "$rf" --slurpfile m "$msgs" '{model:$model, response_format:$rf, messages:$m[0]}'
}
do_call() {  # $1=request file -> raw response; --stub bypasses network (real curl is §7.3 PENDING-VERIFY)
  if [ -n "$stub" ]; then cat "$stub"; return 0; fi
  local pre=""; command -v timeout >/dev/null 2>&1 && pre=timeout
  { [ -z "$pre" ] && command -v gtimeout >/dev/null 2>&1; } && pre=gtimeout
  if [ -n "$pre" ]; then "$pre" "$timeout_s" curl -sS --max-time "$timeout_s" -X POST "$BASE/chat/completions" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' --data-binary @"$1"
  else curl -sS --max-time "$timeout_s" -X POST "$BASE/chat/completions" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' --data-binary @"$1"; fi
}
grounding_ok() {  # non-empty; if --schema given, must parse as object
  [ -n "$1" ] || return 1
  if [ -n "$schema" ]; then echo "$1" | jq -e 'type=="object"' >/dev/null 2>&1; else return 0; fi
}

req="$(mktemp)"
# A4-I1 (adversarial): guard build_request — a jq failure must not leave an empty req that fakes success.
build_request > "$req" 2>/dev/null || { rm -f "$req"; echo "model-provider-build-failed" >&2; exit 2; }
[ -s "$req" ] || { rm -f "$req"; echo "model-provider-build-empty" >&2; exit 2; }
attempt=0; http_seen=0
while [ "$attempt" -lt "$max_retries" ]; do
  attempt=$((attempt+1))
  raw="$(do_call "$req" 2>/dev/null)" || raw=""
  content="$(echo "$raw" | jq -r '.choices[0].message.content // empty' 2>/dev/null)"
  if grounding_ok "$content"; then printf '%s\n' "$content"; rm -f "$req"; exit 0; fi
  echo "$raw" | jq -e '.error' >/dev/null 2>&1 && http_seen=1
  # feed back a REDACTED note for the next attempt; the key can never re-enter prompt/disk (R2/R10)
  fb="$(redact "previous response invalid: $raw")"
  mkdir -p "$run_dir" 2>/dev/null || true
  printf '%s\n' "$fb" >> "$run_dir/feedback.log" 2>/dev/null || true
  if [ "$attempt" -lt "$max_retries" ]; then
    req2="$(mktemp)"; jq --arg fb "$fb" '.messages += [{role:"user", content:$fb}]' "$req" > "$req2" && mv "$req2" "$req"
  fi
done
rm -f "$req"
# degrade (§4.5-E): provider unusable after retries -> emit fallback marker, exit 7 (caller -> claude).
printf '{"model_status":"degraded","fallback":"claude","reason":"%s"}\n' "$( [ "$http_seen" -eq 1 ] && echo http-error || echo retries-exhausted )"
exit 7
