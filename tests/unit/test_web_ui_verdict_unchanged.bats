#!/usr/bin/env bats
# R11 regression guard: the v0.29.0 web-ui verdict engine must stay byte-identical so the v0.30 vision
# retrofit cannot introduce a false-green. (1) the decision logic+output (verify.sh lines 140-175) is
# cmp'd to a pinned v0.29.0 golden; (2) the exit gate is the exact v0.29.0 decision; (3) with NO vision
# configured a deterministic PASS stays PASS and a FAIL stays FAIL (and emits no annotation).
V="$BATS_TEST_DIRNAME/../../skills/web-ui-verify/verify.sh"
G="$BATS_TEST_DIRNAME/../golden/web-ui-verdict-engine-v0.29.0.txt"

setup() {
  R=$(mktemp -d); BIN=$(mktemp -d)
  printf '{"dependencies":{"react":"18.0.0"}}\n' > "$R/package.json"
  cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
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
  # ensure no ambient vision annotation leaks into the no-vision regression cases
  unset SDLC_WEBUI_VISION_ANNOTATION || true
}
teardown() { rm -rf "$R" "$BIN"; }
rv() { PATH="$BIN:$PATH" SDLC_MCP_PROBE_TIMEOUT="${SDLC_MCP_PROBE_TIMEOUT:-2}" run bash "$V" --repo "$R" "$@"; }

@test "regression: verdict logic lines 140-175 byte-identical to v0.29.0 golden (R11)" {
  sed -n '140,175p' "$V" > "$BATS_TMPDIR/engine.txt"
  cmp "$G" "$BATS_TMPDIR/engine.txt"
}
@test "regression: exit gate is still exactly the v0.29.0 verdict decision" {
  grep -qF '[ "$verdict" = PASS ] && exit 0 || exit 3' "$V"
}
@test "regression: NO vision configured ⇒ deterministic PASS stays PASS (and no annotation)" {
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<div id="root"><main data-app-ready>Dashboard</main></div>' \
    SDLC_WEBUI_CONSOLE='' SDLC_WEBUI_NETWORK='' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' \
    rv --url http://x
  [ "$status" -eq 0 ]; echo "$output" | grep -q "verdict:      PASS"
  echo "$output" | grep -q "vision_annotation" && { echo "unexpected annotation"; false; } || true
}
@test "regression: NO vision configured ⇒ deterministic FAIL stays FAIL (no false-green)" {
  STUB_MCP=connected SDLC_WEBUI_SNAPSHOT='<div id="root"></div>' SDLC_WEBUI_DOM_BUILD_ID='git:abc1234' \
    rv --url http://x
  [ "$status" -eq 3 ]; echo "$output" | grep -q "verdict:      FAIL"
}
