#!/usr/bin/env bats
# Self-validation of grader.sh — the M2 gate's judge MUST be proven before any
# real-LLM eval. An over-normalizing grader inflates F1 (bad model passes); an
# under-normalizing one deflates it (good model blocked). Both are caught here.

setup() {
  GR="${BATS_TEST_DIRNAME}/../../skills/model-eval/grader.sh"
  TD="$(mktemp -d)"
}
teardown() { rm -rf "$TD"; }

score() { sed 's/score=//'; }

@test "exact: identical -> 1.000" {
  printf 'hello world\n' > "$TD/o"; printf 'hello world\n' > "$TD/g"
  run "$GR" --task exact-demo --output "$TD/o" --golden "$TD/g"
  [ "$status" -eq 0 ]; [ "$(echo "$output" | score)" = "1.000" ]
}

@test "exact: differ -> 0.000" {
  printf 'hello\n' > "$TD/o"; printf 'world\n' > "$TD/g"
  run "$GR" --task exact-demo --output "$TD/o" --golden "$TD/g"
  [ "$(echo "$output" | score)" = "0.000" ]
}

@test "normalized: reformatted-but-right -> 1.000 (not deflated)" {
  printf '   Foo   BAR  \n' > "$TD/o"; printf 'foo bar\n' > "$TD/g"
  run "$GR" --task normalized-demo --output "$TD/o" --golden "$TD/g"
  [ "$(echo "$output" | score)" = "1.000" ]
}

@test "normalized: wrong-but-close -> 0.000 (not inflated)" {
  # 'foo-bar' must NOT equal 'foo bar' (collapse-ws does not merge a hyphen).
  printf 'foo-bar\n' > "$TD/o"; printf 'foo bar\n' > "$TD/g"
  run "$GR" --task normalized-demo --output "$TD/o" --golden "$TD/g"
  [ "$(echo "$output" | score)" = "0.000" ]
}

@test "set-f1: {a,b,c} vs {a,b,d} -> 0.667" {
  printf 'a\nb\nc\n' > "$TD/o"; printf 'a\nb\nd\n' > "$TD/g"
  run "$GR" --task setf1-demo --output "$TD/o" --golden "$TD/g"
  [ "$(echo "$output" | score)" = "0.667" ]
}

@test "set-f1: identical set (reordered+dup) -> 1.000" {
  printf 'b\na\nb\nc\n' > "$TD/o"; printf 'c\nb\na\n' > "$TD/g"
  run "$GR" --task setf1-demo --output "$TD/o" --golden "$TD/g"
  [ "$(echo "$output" | score)" = "1.000" ]
}

@test "set-f1: disjoint -> 0.000" {
  printf 'x\ny\n' > "$TD/o"; printf 'a\nb\n' > "$TD/g"
  run "$GR" --task setf1-demo --output "$TD/o" --golden "$TD/g"
  [ "$(echo "$output" | score)" = "0.000" ]
}

@test "missing output file -> 0.000 (no crash)" {
  printf 'a\n' > "$TD/g"
  run "$GR" --task exact-demo --output "$TD/nope" --golden "$TD/g"
  [ "$status" -eq 0 ]; [ "$(echo "$output" | score)" = "0.000" ]
}

@test "unknown task -> exit 2" {
  printf 'a\n' > "$TD/o"; printf 'a\n' > "$TD/g"
  run "$GR" --task no-such-task --output "$TD/o" --golden "$TD/g"
  [ "$status" -eq 2 ]
}

@test "hash: stable for same content, changes on edit" {
  printf 'one\n' > "$TD/f"
  run "$GR" hash "$TD/f"; [ "$status" -eq 0 ]; h1="$output"
  run "$GR" hash "$TD/f"; h2="$output"
  [ "$h1" = "$h2" ]
  printf 'two\n' >> "$TD/f"
  run "$GR" hash "$TD/f"; h3="$output"
  [ "$h1" != "$h3" ]
}

@test "derive: re-derives expected from input (no stored golden)" {
  # a temporary modes file with a derive_cmd that echoes the line count of the input
  modes="$TD/modes.yaml"
  printf 'count-demo:\n  mode: exact\n  live_gradable: true\n  prompt_file: agents/docs-curator.md\n  derive_cmd: "wc -l < \\"$1\\" | tr -d \\" \\""\n' > "$modes"
  printf 'l1\nl2\nl3\n' > "$TD/in"
  printf '3\n' > "$TD/o_right"
  printf '5\n' > "$TD/o_wrong"
  SDLC_GRADER_MODES="$modes" run "$GR" --task count-demo --output "$TD/o_right" --derive "$TD/in"
  [ "$(echo "$output" | score)" = "1.000" ]
  SDLC_GRADER_MODES="$modes" run "$GR" --task count-demo --output "$TD/o_wrong" --derive "$TD/in"
  [ "$(echo "$output" | score)" = "0.000" ]
}

# --- build-messages: shared eval/executor task-prompt constructor (Task 4 real path) ---

@test "build-messages: emits system + 1 few-shot turn + user(input), valid JSON" {
  printf 'cmd a\ncmd b\nlens x\n' > "$TD/in"
  run "$GR" build-messages --task inventory-count-diff --input "$TD/in"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type=="array" and length==4' >/dev/null
  [ "$(echo "$output" | jq -r '.[0].role')" = "system" ]
  [ "$(echo "$output" | jq -r '.[1].role')" = "user" ]
  [ "$(echo "$output" | jq -r '.[2].role')" = "assistant" ]
  [ "$(echo "$output" | jq -r '.[3].role')" = "user" ]
  # system carries the task instruction; final user carries the actual input
  echo "$output" | jq -e '.[0].content | test("per-prefix counts")' >/dev/null
  echo "$output" | jq -e '.[3].content | test("cmd a")' >/dev/null
  # few-shot teaches the exact format (assistant = eval_fewshot.output)
  echo "$output" | jq -e '.[2].content | test("agent=1")' >/dev/null
}

@test "build-messages: missing eval_system/eval_fewshot -> die (never silent)" {
  modes="$TD/m.yaml"; printf 'bare:\n  mode: exact\n  live_gradable: true\n  prompt_file: agents/docs-curator.md\n' > "$modes"
  printf 'x y\n' > "$TD/in"
  SDLC_GRADER_MODES="$modes" run "$GR" build-messages --task bare --input "$TD/in"
  [ "$status" -ne 0 ]
}

@test "build-messages: identical bytes at eval-time and executor-time (prompt parity)" {
  printf 'agent q\nskill r\n' > "$TD/in"
  a="$("$GR" build-messages --task inventory-count-diff --input "$TD/in")"
  b="$("$GR" build-messages --task inventory-count-diff --input "$TD/in")"
  [ "$a" = "$b" ]
}
