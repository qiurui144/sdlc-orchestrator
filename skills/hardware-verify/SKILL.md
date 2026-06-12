---
name: hardware-verify
description: Use when verifying that a software deployment actually runs on a remote edge device (RK3588 / RISC-V / any SSH-reachable box) — extends §7.3 本机部署验证 to remote hardware. verify.sh scp's the artifact + deploy script, starts it via nohup, polls the log over SSH (§4.4 SOP), and computes a PASS/FAIL/TIMEOUT verdict against devices/<dev>/verify.yaml. Zero-LLM; secrets via env only (§1.4). Triggers on /sdlc:hw-verify. Real-device verification needs real hardware (mock ≠ real, §7.3).
---

# hardware-verify

Remote counterpart to `scripts/verify-deploy.sh` (which verifies a packaged artifact on the **local**
machine). This verifies it on a **remote edge device** over SSH and renders a §7.3-style verdict.

## What it does

```
artifact + devices/<dev>/verify.yaml ──► verify.sh <dev> [--artifact P] [--dry-run]
  1. scp artifact + deploy script → device:/tmp/         (transport)
  2. ssh nohup '<deploy>; echo HWVERIFY_EXIT=$?' >log &   (§4.4 — NOT run_in_background+ssh)
  3. poll: ssh cat log, every Ns up to timeout_s          (ServerAliveInterval=30)
  4. verdict vs verify.yaml criteria                       → PASS(0)/FAIL(3)/TIMEOUT(5)
```

Errors: usage/config `2` · criteria-not-met `3` · unreachable/auth/transport `4` · timeout `5`.

## Convention — `devices/<dev>/` (lives in the TARGET repo, not this plugin)

Per §8.2, device specifics live under the consuming repo's `devices/<dev>/`:

```
devices/rk3588/
  verify.yaml      # deploy + health criteria (below)
  DEPLOY.md        # human notes: how to deploy on this device
  backup/          # optional
```

`verify.yaml`:

```yaml
deploy: deploy.sh            # script scp'd + run on the device
health:
  ready_string: SERVICE_READY  # log must contain this  (and/or)
  exit_code: 0                 # deploy must end with HWVERIFY_EXIT=0
timeout_s: 120
```

At least one of `ready_string` / `exit_code` is required (else config error). When both are set, **both**
must hold.

## Secrets (§1.4) — env only, never hardcoded

Credentials come from env, keyed by the uppercased device name (`-`/non-alnum → `_`):

```
RK3588_IP=10.0.0.9  RK3588_USER=root  RK3588_PASS=…   # or an SSH key / agent
```

`--dry-run` redacts the password and runs nothing remotely. A real run **refuses placeholders**
(`your-host`, `<...>`, `changeme`, `test-*-not-real`).

## Usage

```bash
# preview the exact scp/ssh commands (no device contact):
verify.sh rk3588 --dry-run
# real verify (needs the device reachable + env creds set):
verify.sh rk3588 --artifact dist/app.tar.gz
```

Overrides for testing without hardware: `SDLC_SSH_BIN` / `SDLC_SCP_BIN` (stub binaries),
`SDLC_DEVICES_DIR`, `SDLC_HW_POLL_SLEEP=0` (single-shot poll). See `tests/unit/test_hardware_verify.bats`.

## Boundaries (honest)

- The **deterministic** transport + verdict layer is unit-tested with stub ssh/scp. A **real-device**
  PASS is §7.3 PENDING-VERIFY until run on actual hardware (mock ≠ real).
- `health.port` (a live port probe) and a log-interpreting agent (`hardware-deploy-verifier`) are
  **v.next** — added with the real-hardware impl, where there is a real log to interpret.
- Covers tag-time **deploy** verification; provisioning/flashing the device is out of scope.
