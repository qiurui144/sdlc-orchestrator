#!/usr/bin/env bats
# web-ui-quality (UI-2): deterministic quality-gate orchestrator. Zero-network — gates read facts from
# env/--stub (mirrors UI-1's SDLC_WEBUI_* seam). Real chrome-devtools-mcp reads are §7.3 PENDING-VERIFY.
setup() {
  Q="$BATS_TEST_DIRNAME/../../skills/web-ui-quality/quality.sh"
  R=$(mktemp -d); printf '{"dependencies":{"react":"18.0.0"}}\n' > "$R/package.json"
  cat > "$R/web-ui-verify.yaml" <<'YML'
base_url: "http://localhost:8080"
build_id: "git:abc1234"
routes:
  - path: "/"
    positive: { selector: "#root [data-app-ready]", text: "Dashboard" }
    negative: [ "id=\"root\"></div>" ]
quality:
  a11y: { standard: "WCAG21AA", max_violations: 0 }
YML
}
teardown() { rm -rf "$R"; }
rq() { run bash "$Q" --repo "$R" "$@"; }

@test "skeleton: no args usage exit 2" { run bash "$Q"; [ "$status" -eq 2 ]; }
@test "skeleton: unknown --gate exit 2" { rq --gate bogus --dry-run; [ "$status" -eq 2 ]; }
@test "skeleton: non-Chrome browser exit 6" { SDLC_WEB_BROWSER=firefox rq --dry-run; [ "$status" -eq 6 ]; }
@test "skeleton: UI-1 not PASS => quality SKIP exit 0" {
  SDLC_WUQ_UI1_VERDICT=FAIL rq --url http://x; [ "$status" -eq 0 ]; echo "$output" | grep -q "quality-skipped"
}
@test "skeleton: dry-run lists enabled gates exit 0" {
  SDLC_WUQ_UI1_VERDICT=PASS rq --dry-run; [ "$status" -eq 0 ]; echo "$output" | grep -q "enabled-gates:.*a11y"
}

# --- T2: contract threshold parse + trivial fail-closed ---
@test "contract: trivial a11y max_violations ⇒ exit 7" {
  cat > "$R/web-ui-verify.yaml" <<'YML'
build_id: b
routes: [ { path: "/", positive: { selector: "#root[ready]", text: "X" }, negative: ["e"] } ]
quality: { a11y: { standard: WCAG21AA, max_violations: 9999999 } }
YML
  SDLC_WUQ_UI1_VERDICT=PASS rq --gate a11y --url http://x; [ "$status" -eq 7 ]
}
@test "contract: trivial visual diff_ratio_max>=1 ⇒ exit 7" {
  cat > "$R/web-ui-verify.yaml" <<'YML'
build_id: b
routes: [ { path: "/", positive: { selector: "#root[ready]", text: "X" }, negative: ["e"] } ]
quality: { visual: { baseline_dir: tests/screenshots, diff_ratio_max: 1, max_region_px: 10 } }
YML
  SDLC_WUQ_UI1_VERDICT=PASS rq --gate visual --url http://x; [ "$status" -eq 7 ]
}

# --- T7: orchestrator dispatch + aggregate ---
@test "aggregate: all gates PASS ⇒ exit 0 PASS" {
  SDLC_WUQ_UI1_VERDICT=PASS SDLC_A11Y_VIOLATIONS_JSON='[]' rq --gate a11y --url http://x
  [ "$status" -eq 0 ]; echo "$output" | grep -q "verdict:      PASS"
}
@test "aggregate: a11y FAIL ⇒ exit 8 with per-gate line" {
  SDLC_WUQ_UI1_VERDICT=PASS SDLC_A11Y_VIOLATIONS_JSON='[{"id":"color-contrast","impact":"moderate"}]' rq --gate a11y --url http://x
  [ "$status" -eq 8 ]; echo "$output" | grep -q "gate: a11y  verdict: FAIL"; echo "$output" | grep -q "verdict:      FAIL"
}
@test "aggregate: a UI-UNVERIFIED gate + no FAIL ⇒ exit 0 PASS-with-WARN" {
  SDLC_WUQ_UI1_VERDICT=PASS rq --gate a11y --url http://x   # no SDLC_A11Y_VIOLATIONS_JSON ⇒ gate UI-UNVERIFIED
  [ "$status" -eq 0 ]; echo "$output" | grep -q "WARN"
}
@test "I-1: --write-baseline plumbs to the visual gate (establishment ⇒ UI-UNVERIFIED, NOT exit 7)" {
  cat > "$R/web-ui-verify.yaml" <<'YML'
build_id: b
routes: [ { path: "/", positive: { selector: "#root[ready]", text: "X" }, negative: ["e"] } ]
quality: { visual: { baseline_dir: tests/screenshots, diff_ratio_max: 0.02, max_region_px: 2500 } }
YML
  SDLC_WUQ_UI1_VERDICT=PASS SDLC_VISUAL_BASELINE_MISSING=1 rq --gate visual --url http://x --write-baseline
  [ "$status" -eq 0 ]; echo "$output" | grep -q "UI-UNVERIFIED"
}
@test "I-1: visual baseline missing WITHOUT --write-baseline ⇒ exit 7 (orchestrator)" {
  cat > "$R/web-ui-verify.yaml" <<'YML'
build_id: b
routes: [ { path: "/", positive: { selector: "#root[ready]", text: "X" }, negative: ["e"] } ]
quality: { visual: { baseline_dir: tests/screenshots, diff_ratio_max: 0.02, max_region_px: 2500 } }
YML
  SDLC_WUQ_UI1_VERDICT=PASS SDLC_VISUAL_BASELINE_MISSING=1 rq --gate visual --url http://x
  [ "$status" -eq 7 ]
}
