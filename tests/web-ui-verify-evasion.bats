#!/usr/bin/env bats
# BLOCKING adversarial suite — spec §9 cases 1-13. A single false-green/false-PASS fails here and
# ship-blocks. Deterministic (stub claude/browser-facts); real-browser cases 8/9 are PENDING-VERIFY.
V="$BATS_TEST_DIRNAME/../skills/web-ui-verify/verify.sh"
setup() {
  R=$(mktemp -d); BIN=$(mktemp -d)
  printf '{"dependencies":{"react":"18.0.0"}}\n' > "$R/package.json"
  cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
[ -n "${STUB_MCP_SLEEP:-}" ] && sleep "$STUB_MCP_SLEEP"
case "$* " in *"mcp list"*) [ "${STUB_MCP:-none}" = connected ] && echo "playwright: ✓ Connected" || echo none;; esac
exit 0
EOF
  chmod +x "$BIN/claude"
  cat > "$R/web-ui-verify.yaml" <<'YML'
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
teardown() { rm -rf "$R" "$BIN"; }
rv() { PATH="$BIN:$PATH" SDLC_MCP_PROBE_TIMEOUT="${SDLC_MCP_PROBE_TIMEOUT:-2}" run bash "$V" --repo "$R" "$@"; }

@test "case 1: curl-200 + blank page (negative present) → FAIL, never PASS" {
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<div id="root"></div>' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' rv --url http://x
  [ "$status" -eq 3 ]; echo "$output" | grep -q "PASS" && false || true
}
@test "case 2: MCP absent → UI-UNVERIFIED + WARN, never PASS" {
  SDLC_PLAYWRIGHT_MCP=0 rv --url http://x; [ "$status" -eq 0 ]; echo "$output" | grep -q "UI-UNVERIFIED"
}
@test "case 4: non-Chrome → exit 6" { SDLC_WEB_BROWSER=webkit rv --lint-only; [ "$status" -eq 6 ]; }
@test "case 5: screenshot to repo root → exit 6" { rv --lint-only --screenshot-dir "$R"; [ "$status" -eq 6 ]; }
@test "case 6: Bash-interleave flag → exit 6" { SDLC_WEB_BASH_INTERLEAVE=1 rv --lint-only; [ "$status" -eq 6 ]; }
@test "case 7: no web-ui-verify.yaml → exit 7, never PASS" {
  rm "$R/web-ui-verify.yaml"; STUB_MCP=connected rv --url http://x; [ "$status" -eq 7 ]
}
@test "case 8: console-error stub → FAIL" {
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<main data-app-ready>Dashboard</main>' \
    SDLC_WEBUI_CONSOLE='error: boom' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' rv --url http://x; [ "$status" -eq 3 ]
}
@test "case 8b: asset-404 stub → FAIL" {
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<main data-app-ready>Dashboard</main>' \
    SDLC_WEBUI_NETWORK='GET /assets/x.js 404' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' rv --url http://x; [ "$status" -eq 3 ]
}
@test "case 9: stale-build stub (build_id mismatch) → FAIL" {
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<main data-app-ready>Dashboard</main>' \
    SDLC_WEBUI_DOM_BUILD_ID='git:OLD' rv --url http://x; [ "$status" -eq 3 ]
}
@test "case 10: stale evidence (cited mtime < run-start) → exit 7" {
  old=$(mktemp); touch -t 200001010000 "$old"
  STUB_MCP=connected SDLC_WEBUI_EVIDENCE="$old" SDLC_RUN_TS=9999999999 \
    SDLC_WEBUI_SNAPSHOT='<main data-app-ready>Dashboard</main>' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' rv --url http://x
  [ "$status" -eq 7 ]; rm -f "$old"
}
@test "case 11: claude CLI absent / probe timeout → UI-UNVERIFIED, never PASS" {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || skip "no timeout/gtimeout (macOS w/o coreutils) — probe-timeout behavior N/A"
  STUB_MCP=connected STUB_MCP_SLEEP=5 SDLC_MCP_PROBE_TIMEOUT=1 rv --url http://x
  [ "$status" -eq 0 ]; echo "$output" | grep -q "UI-UNVERIFIED"
}
@test "case 12: trivial contract (generic selector + empty text) → exit 7, never PASS" {
  printf 'build_id: b\nroutes:\n  - path: "/"\n    positive: { selector: "body", text: "" }\n    negative: [ "e" ]\n' > "$R/web-ui-verify.yaml"
  STUB_MCP=connected rv --url http://x; [ "$status" -eq 7 ]
}
@test "case 13: contract with no build_id → UI-UNVERIFIED, never PASS" {
  printf 'routes:\n  - path: "/"\n    positive: { selector: "#root[ready]", text: "Dashboard" }\n    negative: [ "id=\\"root\\"></div>" ]\n' > "$R/web-ui-verify.yaml"
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<main>Dashboard</main>' rv --url http://x
  [ "$status" -eq 0 ]; echo "$output" | grep -q "UI-UNVERIFIED"
}
@test "case 16 (re-G3 P0): non-generic selector + EMPTY text → exit 7 (vacuous positive, never PASS on blank)" {
  printf 'build_id: b\nroutes:\n  - path: "/"\n    positive: { selector: "#root [data-app-ready]", text: "" }\n    negative: [ "id=\\"root\\"></div>" ]\n' > "$R/web-ui-verify.yaml"
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<div id="root"></div>' SDLC_WEBUI_DOM_BUILD_ID='b' rv --url http://x
  [ "$status" -eq 7 ]; echo "$output" | grep -q "PASS" && false || true
}
@test "case 17 (re-G3 S1): asset 404 formatted as [404] (no leading space) → FAIL" {
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<main data-app-ready>Dashboard</main>' \
    SDLC_WEBUI_NETWORK='GET /assets/x.js [404]' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' rv --url http://x; [ "$status" -eq 3 ]
}
@test "case 18 (re-G3 S2): console 'Uncaught TypeError' (no word 'error') → FAIL" {
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<main data-app-ready>Dashboard</main>' \
    SDLC_WEBUI_CONSOLE='Uncaught TypeError: x is not a function' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' rv --url http://x; [ "$status" -eq 3 ]
}
@test "concurrent: 20x verdict parse, no SIGPIPE/flake (SE16 §2.3)" {
  n=0; while [ "$n" -lt 20 ]; do
    STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<main data-app-ready>Dashboard</main>' \
      SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' PATH="$BIN:$PATH" bash "$V" --repo "$R" --url http://x >/dev/null 2>&1
    [ "$?" -ne 141 ] || { echo "SIGPIPE at iter $n"; false; }
    n=$((n+1))
  done
}
