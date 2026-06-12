#!/usr/bin/env bats

JUDGE="$BATS_TEST_DIRNAME/../../eval/judge.sh"

@test "parse PASS verdict → exit 0" {
  tmp=$(mktemp); printf 'VERDICT: PASS\nREASON: descends to a process root\n' > "$tmp"
  run "$JUDGE" --parse "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  rm -f "$tmp"
}

@test "parse FAIL verdict → exit 1" {
  tmp=$(mktemp); printf 'VERDICT: FAIL\nREASON: just restates the bug\n' > "$tmp"
  run "$JUDGE" --parse "$tmp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
  rm -f "$tmp"
}

@test "parse is case/space tolerant (verdict:  pass)" {
  tmp=$(mktemp); printf 'some preamble\nverdict:  pass  \n' > "$tmp"
  run "$JUDGE" --parse "$tmp"
  [ "$status" -eq 0 ]
  rm -f "$tmp"
}

@test "no VERDICT line → MALFORMED exit 2" {
  tmp=$(mktemp); printf 'I think this is fine, looks good to me.\n' > "$tmp"
  run "$JUDGE" --parse "$tmp"
  [ "$status" -eq 2 ]
  [[ "$output" == *"judge-malformed-verdict"* ]]
  rm -f "$tmp"
}

@test "missing file → exit 2" {
  run "$JUDGE" --parse /tmp/nope-$$-missing.txt
  [ "$status" -eq 2 ]
}

@test "usage without mode → exit 2" {
  run "$JUDGE"
  [ "$status" -eq 2 ]
}

@test "judge.sh is sourceable without running CLI dispatch (panel reuse)" {
  run bash -c '. "'"$JUDGE"'"; type parse_verdict >/dev/null && echo OK'
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}
