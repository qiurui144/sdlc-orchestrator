#!/usr/bin/env bats
# hardware-verify (v0.19): deterministic edge-deploy verifier. Tested WITHOUT real hardware by
# stubbing ssh/scp on SDLC_SSH_BIN/SDLC_SCP_BIN. Real-device E2E is §7.3 PENDING-VERIFY (needs hw).
V="$BATS_TEST_DIRNAME/../../skills/hardware-verify/verify.sh"

setup() {
  R=$(mktemp -d)
  mkdir -p "$R/devices/rk3588"
  # stub scp: success unless STUB_SCP_FAIL=1
  cat > "$R/scp" <<'EOF'
#!/usr/bin/env bash
[ "${STUB_SCP_FAIL:-0}" = 1 ] && exit 1
exit 0
EOF
  # stub ssh: STUB_SSH_FAIL=1 → all fail (255). 'cat' → print $STUB_LOG; 'nohup' → ok.
  cat > "$R/ssh" <<'EOF'
#!/usr/bin/env bash
[ "${STUB_SSH_FAIL:-0}" = 1 ] && exit 255
cmd="${@: -1}"
case "$cmd" in
  *cat*) [ -n "${STUB_LOG:-}" ] && cat "$STUB_LOG"; exit 0;;
  *) exit 0;;
esac
EOF
  chmod +x "$R/scp" "$R/ssh"
  crit() { printf '%s\n' "$@" > "$R/devices/rk3588/verify.yaml"; }
}
teardown() { rm -rf "$R"; }

# shared env for a run against the stubs
runv() {
  SDLC_DEVICES_DIR="$R/devices" SDLC_SSH_BIN="$R/ssh" SDLC_SCP_BIN="$R/scp" \
  SDLC_HW_POLL_SLEEP=0 RK3588_IP=10.0.0.9 RK3588_USER=root RK3588_PASS="${RK3588_PASS:-}" \
  STUB_LOG="${STUB_LOG:-}" STUB_SCP_FAIL="${STUB_SCP_FAIL:-0}" STUB_SSH_FAIL="${STUB_SSH_FAIL:-0}" \
  run bash "$V" "$@"
}

@test "missing verify.yaml → exit 2" {
  runv nodevice
  [ "$status" -eq 2 ]
}

@test "criteria incomplete (no ready/exit_code) → exit 2" {
  printf 'deploy: deploy.sh\ntimeout_s: 2\n' > "$R/devices/rk3588/verify.yaml"
  runv rk3588
  [ "$status" -eq 2 ]
}

@test "dry-run runs nothing remote, exit 0, mentions dry-run" {
  crit 'deploy: deploy.sh' 'health:' '  ready_string: SERVICE_READY' 'timeout_s: 2'
  runv rk3588 --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "dry-run"
}

@test "dry-run redacts the password (no plaintext)" {
  crit 'deploy: deploy.sh' 'health:' '  ready_string: SERVICE_READY'
  RK3588_PASS=supersecret123 runv rk3588 --dry-run
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "supersecret123"
}

@test "placeholder creds on real run → exit 2 (no connection)" {
  crit 'deploy: deploy.sh' 'health:' '  ready_string: R'
  SDLC_DEVICES_DIR="$R/devices" SDLC_SSH_BIN="$R/ssh" SDLC_SCP_BIN="$R/scp" \
    SDLC_HW_POLL_SLEEP=0 RK3588_IP=your-host RK3588_USER=root run bash "$V" rk3588
  [ "$status" -eq 2 ]
}

@test "happy: log contains ready_string → PASS (exit 0)" {
  crit 'deploy: deploy.sh' 'health:' '  ready_string: SERVICE_READY' 'timeout_s: 2'
  printf 'booting...\nSERVICE_READY on :8080\n' > "$R/canned.log"
  STUB_LOG="$R/canned.log" runv rk3588
  [ "$status" -eq 0 ]
}

@test "happy via exit_code sentinel → PASS" {
  crit 'deploy: deploy.sh' 'health:' '  exit_code: 0' 'timeout_s: 2'
  printf 'did work\nHWVERIFY_EXIT=0\n' > "$R/canned.log"
  STUB_LOG="$R/canned.log" runv rk3588
  [ "$status" -eq 0 ]
}

@test "deploy ran but criteria unmet → FAIL (exit 3)" {
  crit 'deploy: deploy.sh' 'health:' '  ready_string: SERVICE_READY' 'timeout_s: 2'
  printf 'crashed\nHWVERIFY_EXIT=1\n' > "$R/canned.log"
  STUB_LOG="$R/canned.log" runv rk3588
  [ "$status" -eq 3 ]
}

@test "no ready signal, no sentinel → TIMEOUT (exit 5)" {
  crit 'deploy: deploy.sh' 'health:' '  ready_string: SERVICE_READY' 'timeout_s: 2'
  printf 'still booting...\n' > "$R/canned.log"
  STUB_LOG="$R/canned.log" runv rk3588
  [ "$status" -eq 5 ]
}

@test "scp transport failure → exit 4" {
  crit 'deploy: deploy.sh' 'health:' '  ready_string: R' 'timeout_s: 2'
  STUB_SCP_FAIL=1 runv rk3588
  [ "$status" -eq 4 ]
}

@test "ssh start failure → exit 4" {
  crit 'deploy: deploy.sh' 'health:' '  ready_string: R' 'timeout_s: 2'
  STUB_SSH_FAIL=1 runv rk3588
  [ "$status" -eq 4 ]
}

@test "device name normalization: my-box → MY_BOX_IP env" {
  mkdir -p "$R/devices/my-box"
  printf 'deploy: deploy.sh\nhealth:\n  ready_string: OK\ntimeout_s: 2\n' > "$R/devices/my-box/verify.yaml"
  printf 'OK\n' > "$R/canned.log"
  SDLC_DEVICES_DIR="$R/devices" SDLC_SSH_BIN="$R/ssh" SDLC_SCP_BIN="$R/scp" \
    SDLC_HW_POLL_SLEEP=0 MY_BOX_IP=10.0.0.5 MY_BOX_USER=root STUB_LOG="$R/canned.log" \
    run bash "$V" my-box
  [ "$status" -eq 0 ]
}
