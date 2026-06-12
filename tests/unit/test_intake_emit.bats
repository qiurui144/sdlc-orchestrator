#!/usr/bin/env bats

EMIT="$BATS_TEST_DIRNAME/../../skills/intake-consolidation/emit-subreport.sh"

@test "writes a parseable header line" {
  out=$(mktemp); trap "rm -f $out" EXIT
  run "$EMIT" "$out" deps PASS 0.92 "0 CVE, 1 license flag"
  [ "$status" -eq 0 ]
  grep -qE '<!-- sdlc-intake: dim=deps verdict=PASS score=0.92 top="0 CVE, 1 license flag" -->' "$out"
}

@test "rejects an unknown verdict" {
  out=$(mktemp); trap "rm -f $out" EXIT
  run "$EMIT" "$out" deps NOPE 0.5 "x"
  [ "$status" -eq 2 ]
}

@test "embeds a native body file when given" {
  out=$(mktemp); body=$(mktemp); trap "rm -f $out $body" EXIT
  printf 'NATIVE-BODY-MARKER\n' > "$body"
  run "$EMIT" "$out" disk WARN N/A "/ at 12G" "$body"
  [ "$status" -eq 0 ]
  grep -q 'NATIVE-BODY-MARKER' "$out"
}

@test "double-quotes in top are sanitized to keep header parseable" {
  out=$(mktemp); trap "rm -f $out" EXIT
  run "$EMIT" "$out" perf PASS 0.9 'he said "hi"'
  [ "$status" -eq 0 ]
  # header still has exactly the dim=...top="..." shape with no stray inner double-quotes
  head -1 "$out" | grep -qE '<!-- sdlc-intake: dim=perf verdict=PASS score=0.9 top="[^"]*" -->'
}

@test "header is the first line of the file" {
  out=$(mktemp); trap "rm -f $out" EXIT
  "$EMIT" "$out" deps PASS 1.0 ok
  [ "$(head -1 "$out" | cut -c1-20)" = '<!-- sdlc-intake: di' ]
}
