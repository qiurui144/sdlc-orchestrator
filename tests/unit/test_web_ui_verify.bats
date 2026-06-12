#!/usr/bin/env bats
# web-ui-verify (UI-1): deterministic detect/probe/lint/verdict. Tested WITHOUT a real browser
# or live MCP by stubbing `claude`/`curl` on PATH and SDLC_PLAYWRIGHT_MCP. Real browser reads are
# §7.3 PENDING-VERIFY (examples/web-hello + connected MCP).
V="$BATS_TEST_DIRNAME/../../skills/web-ui-verify/verify.sh"

setup() {
  R=$(mktemp -d); BIN=$(mktemp -d)
  mkdir -p "$R/web"
  printf '{"dependencies":{"react":"18.0.0"}}\n' > "$R/package.json"
  # stub `claude`: `mcp list` prints connected/absent per STUB_MCP; sleeps per STUB_MCP_SLEEP.
  cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
[ -n "${STUB_MCP_SLEEP:-}" ] && sleep "$STUB_MCP_SLEEP"
case "$* " in
  *"mcp list"*) case "${STUB_MCP:-none}" in
      connected) echo "playwright: ✓ Connected";;
      failed)    echo "playwright: ✗ Failed";;
      *)         echo "no servers";; esac;;
esac
exit 0
EOF
  chmod +x "$BIN/claude"
}
teardown() { rm -rf "$R" "$BIN"; }
goodcrit() { cat > "$R/web-ui-verify.yaml" <<'YML'
base_url: "http://localhost:8080"
build_id: "git:abc1234"
build_id_selector: "meta[name=build-id]"
settle_timeout_s: 10
routes:
  - path: "/"
    positive: { selector: "#root [data-app-ready]", text: "Dashboard" }
    negative: [ "id=\"root\"></div>", "Application error" ]
YML
}
runv() { PATH="$BIN:$PATH" SDLC_MCP_PROBE_TIMEOUT="${SDLC_MCP_PROBE_TIMEOUT:-2}" run bash "$V" --repo "$R" "$@"; }

@test "dry-run prints stack + parsed routes + mcp result, runs no browser, exit 0" {
  goodcrit; STUB_MCP=connected runv --dry-run
  [ "$status" -eq 0 ]; echo "$output" | grep -q "web-ui-stack: react"; echo "$output" | grep -q "mcp-present:"
}
@test "not a web app → exit 2, not-a-web-app" {
  rm "$R/package.json"; runv --dry-run; [ "$status" -eq 2 ]; echo "$output" | grep -q "not-a-web-app"
}
@test "MCP stub connected (SDLC_PLAYWRIGHT_MCP=1) → mcp-present: yes" {
  goodcrit; SDLC_PLAYWRIGHT_MCP=1 runv --dry-run; echo "$output" | grep -q "mcp-present:  *yes"
}
@test "MCP stub absent (SDLC_PLAYWRIGHT_MCP=0) → mcp-present: no" {
  goodcrit; SDLC_PLAYWRIGHT_MCP=0 runv --dry-run; echo "$output" | grep -q "mcp-present:  *no"
}
@test "claude CLI absent on PATH → UI-UNVERIFIED, exit 0 (never hang/PASS)" {
  # minimal PATH with the essential tools symlinked but NO claude — so `command -v claude` fails
  # without breaking bash/cat/timeout (PATH=/nonexistent would break everything, not just claude).
  goodcrit; M=$(mktemp -d)
  # contract-parse (runs before the MCP probe) needs yq + tr; include everything verify.sh uses EXCEPT claude
  for t in bash timeout dirname cat yq tr; do ln -s "$(command -v "$t")" "$M/$t"; done
  PATH="$M" run bash "$V" --repo "$R" --url http://x
  rm -rf "$M"
  [ "$status" -eq 0 ]; echo "$output" | grep -q "UI-UNVERIFIED"
}
@test "MCP probe timeout (claude mcp list slow) → UI-UNVERIFIED, exit 0" {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || skip "no timeout/gtimeout (macOS w/o coreutils) — bounded probe N/A; the unbounded fallback can't enforce a timeout"
  goodcrit; STUB_MCP=connected STUB_MCP_SLEEP=5 SDLC_MCP_PROBE_TIMEOUT=1 runv --url http://x
  [ "$status" -eq 0 ]; echo "$output" | grep -q "UI-UNVERIFIED"
}
@test "lint-only: non-Chrome request → exit 6" {
  goodcrit; SDLC_WEB_BROWSER=firefox runv --lint-only; [ "$status" -eq 6 ]
}
@test "lint-only: screenshot dir = repo root → exit 6" {
  goodcrit; runv --lint-only --screenshot-dir "$R"; [ "$status" -eq 6 ]
}
@test "lint-only: legal screenshot dir (docs/screenshots) → exit 0" {
  goodcrit; runv --lint-only --screenshot-dir "docs/screenshots/web"; [ "$status" -eq 0 ]
}

@test "contract absent → exit 7 (web-ui-no-criteria)" {
  rm -f "$R/web-ui-verify.yaml"; STUB_MCP=connected runv --url http://x; [ "$status" -eq 7 ]
  echo "$output" | grep -q "web-ui-no-criteria"
}
@test "contract with empty routes → exit 7" {
  printf 'base_url: x\nbuild_id: b\nroutes: []\n' > "$R/web-ui-verify.yaml"
  STUB_MCP=connected runv --url http://x; [ "$status" -eq 7 ]
}
@test "route missing positive → exit 7" {
  printf 'build_id: b\nroutes:\n  - path: "/"\n    negative: [ "err" ]\n' > "$R/web-ui-verify.yaml"
  STUB_MCP=connected runv --url http://x; [ "$status" -eq 7 ]
}
@test "trivial positive (selector body, empty text) → exit 7" {
  printf 'build_id: b\nroutes:\n  - path: "/"\n    positive: { selector: "body", text: "" }\n    negative: [ "err" ]\n' > "$R/web-ui-verify.yaml"
  STUB_MCP=connected runv --url http://x; [ "$status" -eq 7 ]
}
@test "route with zero negative markers → exit 7" {
  printf 'build_id: b\nroutes:\n  - path: "/"\n    positive: { selector: "#root[ready]", text: "Dashboard" }\n    negative: []\n' > "$R/web-ui-verify.yaml"
  STUB_MCP=connected runv --url http://x; [ "$status" -eq 7 ]
}
@test "contract with NO build_id → UI-UNVERIFIED (freshness unprovable), exit 0, never PASS" {
  printf 'routes:\n  - path: "/"\n    positive: { selector: "#root[ready]", text: "Dashboard" }\n    negative: [ "id=\\"root\\"></div>" ]\n' > "$R/web-ui-verify.yaml"
  STUB_MCP=connected runv --url http://x
  [ "$status" -eq 0 ]; echo "$output" | grep -q "UI-UNVERIFIED"
  echo "$output" | grep -q "PASS" && { echo "build_id-absent must not PASS"; false; } || true
}
@test "dry-run prints parsed routes from a valid contract" {
  goodcrit; STUB_MCP=connected runv --dry-run; echo "$output" | grep -q "route: /"
}

@test "keystone PASS: positive present, negative absent, no console/net err, build fresh" {
  goodcrit
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<div id="root"><main data-app-ready>Dashboard</main></div>' \
    SDLC_WEBUI_CONSOLE='' SDLC_WEBUI_NETWORK='' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' \
    runv --url http://x
  [ "$status" -eq 0 ]; echo "$output" | grep -q "verdict:      PASS"
}
@test "false-green: curl 200 + blank #root (negative present) → FAIL exit 3, never PASS" {
  goodcrit
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<div id="root"></div>' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' \
    runv --url http://x
  [ "$status" -eq 3 ]; echo "$output" | grep -q "FAIL"
  echo "$output" | grep -q "PASS" && { echo "blank page must FAIL"; false; } || true
}
@test "console error present → FAIL exit 3" {
  goodcrit
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<main data-app-ready>Dashboard</main>' \
    SDLC_WEBUI_CONSOLE='error: ChunkLoadError' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' runv --url http://x
  [ "$status" -eq 3 ]
}
@test "failed asset (404) → FAIL exit 3" {
  goodcrit
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<main data-app-ready>Dashboard</main>' \
    SDLC_WEBUI_NETWORK='GET /assets/app.js 404' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' runv --url http://x
  [ "$status" -eq 3 ]
}
@test "stale build (DOM build_id != contract) → FAIL exit 3" {
  goodcrit
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<main data-app-ready>Dashboard</main>' \
    SDLC_WEBUI_DOM_BUILD_ID='git:OLD0000' runv --url http://x
  [ "$status" -eq 3 ]; echo "$output" | grep -q "stale"
}
@test "--emit-boot-check prints go:embed assertion (assets + id=root or panic)" {
  goodcrit; STUB_MCP=connected runv --emit-boot-check
  [ "$status" -eq 0 ]; echo "$output" | grep -q '/assets/'; echo "$output" | grep -q 'id="root"'; echo "$output" | grep -qi 'panic'
}
@test "examples/web-hello detects as vanilla" {
  D="$BATS_TEST_DIRNAME/../../config/detect-web-stack.sh"
  run bash "$D" "$BATS_TEST_DIRNAME/../../examples/web-hello"; [ "$output" = vanilla ]
}

# --- T11: ui-vision-judge retrofit (provider-agnostic prose + annotation alongside) ---
@test "retrofit: no hardcoded sonnet browser-judge prose remains" {
  V="$BATS_TEST_DIRNAME/../../skills/web-ui-verify/verify.sh"
  S="$BATS_TEST_DIRNAME/../../skills/web-ui-verify/SKILL.md"
  ! grep -qi "sonnet browser-judge" "$V"
  ! grep -qi "sonnet browser-judge" "$S"
}
@test "retrofit: vision annotation rides alongside, never flips the verdict (PASS stays PASS)" {
  goodcrit
  STUB_MCP=connected SDLC_WEBUI_VISION_ANNOTATION='{"looks_ok":false,"vision_status":"ok"}' \
    SDLC_WEBUI_SNAPSHOT='<div id="root"><main data-app-ready>Dashboard</main></div>' \
    SDLC_WEBUI_CONSOLE='' SDLC_WEBUI_NETWORK='' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' \
    runv --url http://x
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "verdict:      PASS"
  echo "$output" | grep -q "vision_annotation"
}
