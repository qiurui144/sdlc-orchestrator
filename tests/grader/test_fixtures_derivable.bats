#!/usr/bin/env bats
# Every inventory-count-diff fixture's golden must be RE-DERIVABLE from its input
# (live-gradable, spec §3). A hand-edited wrong golden in any case fails here —
# before eval.sh (Task 3) or executor.sh (Task 5) trust these fixtures.

setup() {
  GR="${BATS_TEST_DIRNAME}/../../skills/model-eval/grader.sh"
  FIX="${BATS_TEST_DIRNAME}/../../skills/model-eval/fixtures/inventory-count-diff"
  TD="$(mktemp -d)"
}
teardown() { rm -rf "$TD"; }

@test "all inventory-count-diff fixtures are derivable (golden == derive(input))" {
  local n=0
  for f in "$FIX"/*.json; do
    n=$((n+1))
    jq -r '.input'  "$f" > "$TD/in"
    jq -r '.golden' "$f" > "$TD/gold"
    run "$GR" --task inventory-count-diff --output "$TD/gold" --derive "$TD/in"
    [ "$status" -eq 0 ]
    if [ "$(echo "$output" | sed 's/score=//')" != "1.000" ]; then
      echo "NON-DERIVABLE fixture: $f (got $output)" >&2
      return 1
    fi
  done
  [ "$n" -ge 10 ]
}

@test "a deliberately-wrong golden is caught (derive guard bites)" {
  jq -r '.input' "$FIX/case-1.json" > "$TD/in"
  printf 'agent=999\n' > "$TD/wrong"   # wrong count
  run "$GR" --task inventory-count-diff --output "$TD/wrong" --derive "$TD/in"
  [ "$(echo "$output" | sed 's/score=//')" = "0.000" ]
}
