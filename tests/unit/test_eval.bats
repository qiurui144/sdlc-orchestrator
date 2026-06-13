#!/usr/bin/env bats
# eval.sh — worst-case compound gate + sources_hash allowlist, driven by stubbed
# provider outputs (no real LLM). Proves a high-variance or claude-low task is NOT
# marked passed.

setup() {
  EVAL="${BATS_TEST_DIRNAME}/../../skills/model-eval/eval.sh"
  FIX="${BATS_TEST_DIRNAME}/../../skills/model-eval/fixtures/inventory-count-diff"
  TD="$(mktemp -d)"
  STUB="$TD/stub"
}
teardown() { rm -rf "$TD"; }

# fill <provider> <seeds> <mode>   mode: good | bad | dip2 (seed 2 wrong)
fill() {
  local prov="$1" seeds="$2" mode="$3" s f cid
  for s in $(seq 1 "$seeds"); do
    mkdir -p "$STUB/$prov/seed-$s"
    for f in "$FIX"/*.json; do
      cid="$(basename "$f" .json)"
      if [ "$mode" = "bad" ] || { [ "$mode" = "dip2" ] && [ "$s" = "2" ]; }; then
        printf 'WRONG\n' > "$STUB/$prov/seed-$s/$cid.out"
      else
        jq -r '.golden' "$f" > "$STUB/$prov/seed-$s/$cid.out"
      fi
    done
  done
}

field() { yq -r ".tasks.\"inventory-count-diff\".$1" "$TD/allow.yaml"; }

@test "all-correct: deepseek passes, allowlist provider=deepseek + sources_hash set" {
  fill deepseek 3 good; fill claude 3 good
  run "$EVAL" --task inventory-count-diff --providers deepseek,claude --seeds 3 --stub "$STUB" --out "$TD/allow.yaml"
  [ "$status" -eq 0 ]
  [ "$(field passed)" = "true" ]
  [ "$(field provider)" = "deepseek" ]
  [ -n "$(field sources_hash)" ] && [ "$(field sources_hash)" != "null" ]
  [ "$(field live_gradable)" = "true" ]
}

@test "deepseek dips on one seed: worst-case gate fails (passed=false)" {
  fill deepseek 3 dip2; fill claude 3 good
  run "$EVAL" --task inventory-count-diff --providers deepseek,claude --seeds 3 --stub "$STUB" --out "$TD/allow.yaml"
  [ "$(field passed)" = "false" ]
  [ "$(field provider)" = "claude" ]
}

@test "claude itself below floor: task_reliability=low, never route" {
  fill deepseek 3 good; fill claude 3 bad
  run "$EVAL" --task inventory-count-diff --providers deepseek,claude --seeds 3 --stub "$STUB" --out "$TD/allow.yaml"
  [ "$(field task_reliability)" = "low" ]
  [ "$(field passed)" = "false" ]
}

@test "sources_hash is stable across runs (same inputs)" {
  fill deepseek 3 good; fill claude 3 good
  "$EVAL" --task inventory-count-diff --providers deepseek,claude --seeds 3 --stub "$STUB" --out "$TD/a1.yaml" >/dev/null
  "$EVAL" --task inventory-count-diff --providers deepseek,claude --seeds 3 --stub "$STUB" --out "$TD/a2.yaml" >/dev/null
  h1="$(yq -r '.tasks."inventory-count-diff".sources_hash' "$TD/a1.yaml")"
  h2="$(yq -r '.tasks."inventory-count-diff".sources_hash' "$TD/a2.yaml")"
  [ "$h1" = "$h2" ]
}
