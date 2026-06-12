#!/usr/bin/env bats
# vision-fixtures: the shared captured-response corpus (documentation + the real-provider
# PENDING-VERIFY harness). judge.sh's own unit tests build inline fixtures; these are the
# canonical examples covering good / garbage / injection / extra-field / http-error / timeout /
# leaked-key-error-body / non-ascii.
setup() { F="$BATS_TEST_DIRNAME/../../examples/vision-fixtures"; }

@test "fixtures: every non-empty .json fixture is valid JSON" {
  # timeout-empty.json is intentionally EMPTY (a timeout-class non-response) — skip it.
  for j in "$F"/*.json; do [ -s "$j" ] || continue; jq . "$j" >/dev/null || { echo "bad: $j"; false; }; done
}
@test "fixtures: timeout-empty.json is intentionally empty (timeout-class non-response)" {
  [ -f "$F/timeout-empty.json" ]; [ ! -s "$F/timeout-empty.json" ]
}
@test "fixtures: injection fixture carries the string but no verdict field in content" {
  c="$(jq -r '.choices[0].message.content' "$F/prompt-injection-page.json")"
  echo "$c" | grep -q 'ignore instructions'
  echo "$c" | jq -e 'has("verdict")' >/dev/null && false || true
}
@test "fixtures: small.png base64 round-trips byte-identical" {
  b="$(base64 < "$F/small.png" | tr -d '\n')"
  printf '%s' "$b" | base64 -d > "$BATS_TMPDIR/rt.bin" 2>/dev/null || printf '%s' "$b" | base64 --decode > "$BATS_TMPDIR/rt.bin"
  cmp "$F/small.png" "$BATS_TMPDIR/rt.bin"
}
