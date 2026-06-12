#!/usr/bin/env bats
# web-ui-quality responsive gate (T5). Facts (per-viewport "W:flag" CSV): SDLC_RESP_OVERFLOW (1=scrollWidth>width)
# + SDLC_RESP_BBOX_IN (1=key bbox within viewport). FAIL if ANY overflow OR key not in-viewport — real layout,
# NOT DOM presence (C2). Real resize_page+evaluate_script = §7.3 PENDING-VERIFY.
RG="$BATS_TEST_DIRNAME/../../skills/web-ui-quality/gates/responsive.sh"

@test "responsive: no overflow + bbox-in at all widths ⇒ PASS" {
  run env SDLC_RESP_OVERFLOW="375:0,768:0,1280:0" SDLC_RESP_BBOX_IN="375:1,768:1,1280:1" bash "$RG"
  [ "$status" -eq 0 ]; echo "$output"|grep -q "verdict: PASS"
}
@test "responsive(C2): horizontal overflow at 375 (fixed-1280 page) ⇒ FAIL(10)" {
  run env SDLC_RESP_OVERFLOW="375:1,768:0,1280:0" SDLC_RESP_BBOX_IN="375:1,768:1,1280:1" bash "$RG"
  [ "$status" -eq 10 ]; echo "$output"|grep -q "verdict: FAIL"
}
@test "responsive: overflow at the LAST viewport ⇒ FAIL(10) (glob catches trailing element)" {
  run env SDLC_RESP_OVERFLOW="375:0,768:0,1280:1" SDLC_RESP_BBOX_IN="375:1,768:1,1280:1" bash "$RG"; [ "$status" -eq 10 ]
}
@test "responsive: key bbox off-screen ⇒ FAIL(10)" {
  run env SDLC_RESP_OVERFLOW="375:0,768:0,1280:0" SDLC_RESP_BBOX_IN="375:0,768:1,1280:1" bash "$RG"; [ "$status" -eq 10 ]
}
@test "responsive: facts absent ⇒ UI-UNVERIFIED" { run env -u SDLC_RESP_OVERFLOW bash "$RG"; [ "$status" -eq 0 ]; echo "$output"|grep -q "UI-UNVERIFIED"; }
@test "responsive(G3): malformed CSV (no flag) ⇒ UI-UNVERIFIED, never PASS" {
  run env SDLC_RESP_OVERFLOW="1280" SDLC_RESP_BBOX_IN="1280:1" bash "$RG"
  [ "$status" -eq 0 ]; echo "$output"|grep -q "UI-UNVERIFIED"
  echo "$output"|grep -q "verdict: PASS" && { echo "garbage must not PASS"; false; } || true
}
@test "responsive(G3): overflow/bbox cardinality mismatch ⇒ UI-UNVERIFIED" {
  run env SDLC_RESP_OVERFLOW="375:0,768:0,1280:0" SDLC_RESP_BBOX_IN="375:1" bash "$RG"
  [ "$status" -eq 0 ]; echo "$output"|grep -q "UI-UNVERIFIED"
}
