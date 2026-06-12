---
description: Verify a deployment actually runs on a remote edge device over SSH (extends §7.3 本机部署验证 to hardware). scp + nohup-deploy + poll-log + PASS/FAIL verdict against devices/<dev>/verify.yaml. Zero-LLM; secrets via env only.
argument-hint: "<device> [--artifact <path>] [--dry-run] [--timeout <s>]"
allowed-tools: [Read, Bash, Skill]
---

# /sdlc:hw-verify

Run the **hardware-verify** skill against a target edge device and report a §7.3-style verdict.

## Steps

1. Resolve the device convention: confirm `devices/$1/verify.yaml` exists (or `--criteria <file>`).
   If absent, point the user to the `hardware-verify` SKILL.md "Convention" section — do not guess.
2. Confirm credentials are present in env (`<DEV>_IP`, `<DEV>_USER`, `<DEV>_PASS` or an SSH key),
   uppercased device name with non-alnum → `_`. **Never echo the password.** If the user has not
   provided creds, ask them to set the env vars (per §1.4 / §8.2) — do not hardcode anything.
3. Recommend `--dry-run` first to show the exact scp/ssh commands without contacting the device.
4. Invoke the skill:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/hardware-verify/verify.sh" <device> [--artifact <path>] [--dry-run] [--timeout <s>]
   ```

5. Interpret the exit code for the user:
   - `0` PASS — criteria met; cite the log evidence.
   - `3` FAIL — deploy ran but health criteria not met; show the last log lines.
   - `4` unreachable/auth/transport — check IP/user/pass + network; the secret is never printed.
   - `5` TIMEOUT — no ready signal within `timeout_s`; show the tail.
   - `2` usage/config — missing/incomplete `verify.yaml` or placeholder creds.

## Honesty (§7.3)

A real-device PASS is real verification only when run against **actual hardware** — `--dry-run` and the
stub-tested deterministic layer prove the wiring, not the deploy. State plainly which one you ran.

## Notes

- The log-interpreting `hardware-deploy-verifier` agent and a live `health.port` probe are **v.next**
  (added with the real-hardware impl). Today the command runs the deterministic skill directly.
- SSH SOP per §4.4 (nohup + `ssh cat log`, never `run_in_background`+ssh). SIGPIPE-safe per SE16.
