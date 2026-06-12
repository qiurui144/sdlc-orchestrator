#!/usr/bin/env bats
# web-ui-quality a11y gate (T3). Facts = lighthouse accessibility violations (SDLC_A11Y_VIOLATIONS_JSON).
# Deterministic count vs WUQ_A11Y_MAX. Real lighthouse_audit read is §7.3 PENDING-VERIFY (stub seam here).
A="$BATS_TEST_DIRNAME/../../skills/web-ui-quality/gates/a11y.sh"

@test "a11y: facts absent ⇒ UI-UNVERIFIED exit 0" {
  run env -u SDLC_A11Y_VIOLATIONS_JSON WUQ_A11Y_MAX=0 bash "$A"
  [ "$status" -eq 0 ]; echo "$output" | grep -q "UI-UNVERIFIED"
}
@test "a11y: zero violations ⇒ PASS exit 0" {
  run env SDLC_A11Y_VIOLATIONS_JSON='[]' WUQ_A11Y_MAX=0 bash "$A"
  [ "$status" -eq 0 ]; echo "$output" | grep -q "verdict: PASS"
}
@test "a11y(I4): a contrast violation ⇒ FAIL exit 8 (all severities counted)" {
  run env SDLC_A11Y_VIOLATIONS_JSON='[{"id":"color-contrast","impact":"moderate"}]' WUQ_A11Y_MAX=0 bash "$A"
  [ "$status" -eq 8 ]; echo "$output" | grep -q "verdict: FAIL"
}
@test "a11y: malformed JSON ⇒ UI-UNVERIFIED (never false PASS)" {
  run env SDLC_A11Y_VIOLATIONS_JSON='not json' WUQ_A11Y_MAX=0 bash "$A"
  [ "$status" -eq 0 ]; echo "$output" | grep -q "UI-UNVERIFIED"
}
@test "a11y(I-2): min_severity=critical excludes a lone serious ⇒ PASS (ordinal floor)" {
  run env SDLC_A11Y_VIOLATIONS_JSON='[{"id":"x","impact":"serious"}]' WUQ_A11Y_MAX=0 WUQ_A11Y_MINSEV=critical bash "$A"
  [ "$status" -eq 0 ]; echo "$output" | grep -q "verdict: PASS"
}
@test "a11y(I-2): min_severity=serious counts a critical ⇒ FAIL(8)" {
  run env SDLC_A11Y_VIOLATIONS_JSON='[{"id":"x","impact":"critical"}]' WUQ_A11Y_MAX=0 WUQ_A11Y_MINSEV=serious bash "$A"
  [ "$status" -eq 8 ]
}
@test "a11y(G3): a malformed entry (no impact) alongside a real serious ⇒ FAIL(8), not masked" {
  run env SDLC_A11Y_VIOLATIONS_JSON='[{"id":"real","impact":"serious"},{"id":"broken"}]' WUQ_A11Y_MAX=0 WUQ_A11Y_MINSEV=serious bash "$A"
  [ "$status" -eq 8 ]
}
