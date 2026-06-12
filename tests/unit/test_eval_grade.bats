#!/usr/bin/env bats

GRADE="$BATS_TEST_DIRNAME/../../eval/grade.sh"
FIX="$BATS_TEST_DIRNAME/../fixtures/eval"

@test "good output passes all assertions (exit 0)" {
  run "$GRADE" "$FIX/good-output.txt" "$FIX/expect-sample.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GRADE PASS"* ]]
}

@test "bad output fails (exit 1) and names the failed assertions" {
  run "$GRADE" "$FIX/bad-output.txt" "$FIX/expect-sample.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "missing output file is malformed (exit 2)" {
  run "$GRADE" "$FIX/does-not-exist.txt" "$FIX/expect-sample.yaml"
  [ "$status" -eq 2 ]
}

@test "unknown assertion kind is malformed (exit 2)" {
  tmp=$(mktemp); printf 'assertions:\n  - kind: bogus_kind\n    of: ["x"]\n' > "$tmp"
  run "$GRADE" "$FIX/good-output.txt" "$tmp"
  [ "$status" -eq 2 ]
  [[ "$output" == *"eval-grader-malformed"* ]]
  rm -f "$tmp"
}

@test "empty assertion list is a vacuous pass (exit 0) with warning" {
  tmp=$(mktemp); printf 'assertions: []\n' > "$tmp"
  run "$GRADE" "$FIX/good-output.txt" "$tmp"
  [ "$status" -eq 0 ]
  rm -f "$tmp"
}

@test "count_at_least dedups matches (R1 twice counts once)" {
  tmp_out=$(mktemp); printf 'R1 here\nR1 again\nR2 once\n' > "$tmp_out"
  tmp_exp=$(mktemp); printf 'assertions:\n  - kind: count_at_least\n    pattern: %s\n    min: 3\n' "'R[0-9]+'" > "$tmp_exp"
  run "$GRADE" "$tmp_out" "$tmp_exp"
  [ "$status" -eq 1 ]   # only 2 unique (R1,R2) < 3
  rm -f "$tmp_out" "$tmp_exp"
}

@test "all_present / any_present match case-insensitively (Outdated == outdated)" {
  # An agent that writes '## 4. Outdated Dependencies' must satisfy an assertion
  # written as lowercase 'outdated' — the first real eval run (2026-05-29) failed
  # 2/3 dependency-auditor seeds purely on this case mismatch (the section existed).
  tmp_out=$(mktemp); printf '## 4. Outdated Dependencies\nVulnerabilities here\n' > "$tmp_out"
  tmp_exp=$(mktemp); printf 'assertions:\n  - kind: all_present\n    of: [outdated, vuln]\n' > "$tmp_exp"
  run "$GRADE" "$tmp_out" "$tmp_exp"
  [ "$status" -eq 0 ]
  rm -f "$tmp_out" "$tmp_exp"
}
