#!/usr/bin/env bats
# web-ui-quality visual gate (T4). Facts = SDLC_VISUAL_DIFF_RATIO (global) + SDLC_VISUAL_MAX_REGION_PX
# (largest contiguous changed block). DETERMINISTIC verdict; ui-vision-judge class (SDLC_WUQ_VISION_CLASS)
# is ADVISORY only — never read into the verdict (supremacy). Real screenshot/diff = §7.3 PENDING-VERIFY.
V="$BATS_TEST_DIRNAME/../../skills/web-ui-quality/gates/visual.sh"
base(){ env SDLC_VISUAL_DIFF_RATIO="$1" SDLC_VISUAL_MAX_REGION_PX="$2" WUQ_VIS_DR=0.02 WUQ_VIS_MR=2500 "${@:3}"; }

@test "visual: within tol+cap ⇒ PASS exit 0" { run base 0.005 100 bash "$V"; [ "$status" -eq 0 ]; echo "$output"|grep -q "verdict: PASS"; }
@test "visual(C1): diff over tol ⇒ FAIL(9) even if vision says intentional (SUPREMACY)" {
  run base 0.05 100 SDLC_WUQ_VISION_CLASS=intentional bash "$V"
  [ "$status" -eq 9 ]; echo "$output"|grep -q "verdict: FAIL"
}
@test "visual(I6): localized — ratio<tol but region>cap ⇒ FAIL(9)" { run base 0.005 9000 bash "$V"; [ "$status" -eq 9 ]; }
@test "visual(I5): baseline missing, normal run ⇒ exit 7" {
  run env SDLC_VISUAL_BASELINE_MISSING=1 WUQ_VIS_DR=0.02 WUQ_VIS_MR=2500 bash "$V"; [ "$status" -eq 7 ]
}
@test "visual(I5): baseline missing + --write-baseline ⇒ UI-UNVERIFIED exit 0" {
  run env SDLC_VISUAL_BASELINE_MISSING=1 WUQ_VIS_WRITE_BASELINE=1 WUQ_VIS_DR=0.02 WUQ_VIS_MR=2500 bash "$V"
  [ "$status" -eq 0 ]; echo "$output"|grep -q "UI-UNVERIFIED"
}
@test "visual: facts absent ⇒ UI-UNVERIFIED exit 0" {
  run env -u SDLC_VISUAL_DIFF_RATIO WUQ_VIS_DR=0.02 WUQ_VIS_MR=2500 bash "$V"; [ "$status" -eq 0 ]; echo "$output"|grep -q "UI-UNVERIFIED"
}
@test "visual(G3): garbage diff fact ⇒ UI-UNVERIFIED, never PASS" {
  run env SDLC_VISUAL_DIFF_RATIO="huge" SDLC_VISUAL_MAX_REGION_PX=5 WUQ_VIS_DR=0.02 WUQ_VIS_MR=2500 bash "$V"
  [ "$status" -eq 0 ]; echo "$output"|grep -q "UI-UNVERIFIED"
  echo "$output"|grep -q "verdict: PASS" && { echo "garbage must not PASS"; false; } || true
}
