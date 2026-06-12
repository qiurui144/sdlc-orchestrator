#!/usr/bin/env bash
# verify.sh — deterministic edge hardware-deploy verifier (v0.19, Edge·HW-Verify).
#
# Extends §7.3 本机部署验证 to a remote SSH device. Transport + verdict are ZERO-LLM here; the
# hardware-deploy-verifier agent (sonnet) only interprets an ambiguous log + writes the evidence card.
#
# SSH SOP (§4.4): scp artifact+deploy → `ssh nohup deploy >log 2>&1 &` → poll `ssh cat log`
#   (NEVER run_in_background+ssh — pipe buffering returns empty). ServerAliveInterval keeps it alive.
# Secrets (§1.4): device IP/user/pass come from env ONLY (<DEV>_IP / <DEV>_USER / <DEV>_PASS); the
#   command REFUSES to run if they are placeholders, and never echoes the password.
# SE16-safe: verdict parsing uses `case`-glob (no `… | grep -q` / `| head -n` → no SIGPIPE).
# Testable without hardware: ssh/scp binaries are overridable (SDLC_SSH_BIN / SDLC_SCP_BIN) so a
#   stub on PATH exercises the real transport+poll+verdict logic; `--dry-run` runs nothing remote.
#
# Exit: 0 PASS · 2 usage/config · 3 FAIL(criteria not met) · 4 unreachable/auth/transport · 5 timeout
set -uo pipefail

usage() { echo "usage: verify.sh <device> [--artifact <path>] [--criteria <verify.yaml>] [--dry-run] [--timeout <s>]" >&2; exit 2; }

device="${1:-}"; [ -n "$device" ] || usage; shift || true
artifact="" criteria="" dry=0 timeout_override=""
while [ "$#" -gt 0 ]; do case "$1" in
  --artifact)  artifact="$2"; shift 2;;
  --criteria)  criteria="$2"; shift 2;;
  --timeout)   timeout_override="$2"; shift 2;;
  --dry-run)   dry=1; shift;;
  *) echo "verify-unknown-arg: $1" >&2; usage;;
esac; done

# device → ENV prefix (uppercase, non-alnum → _): rk3588 → RK3588 ; my-box → MY_BOX
DEV=$(printf '%s' "$device" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_'); DEV="${DEV%_}"

# criteria file: explicit, else devices/<device>/verify.yaml under the target repo (SDLC_DEVICES_DIR override)
[ -n "$criteria" ] || criteria="${SDLC_DEVICES_DIR:-$PWD/devices}/$device/verify.yaml"
if [ ! -f "$criteria" ]; then
  echo "verify-no-criteria: $criteria" >&2
  echo "  create devices/$device/verify.yaml — see skills/hardware-verify/SKILL.md (Convention)" >&2
  exit 2
fi

field() { yq -r ".$1 // \"\"" "$criteria" 2>/dev/null; }
deploy=$(field deploy)
ready=$(field 'health.ready_string')
want_rc=$(field 'health.exit_code')
timeout_s=$(field 'timeout_s'); [ -n "$timeout_override" ] && timeout_s="$timeout_override"
case "$timeout_s" in ''|*[!0-9]*) timeout_s=120;; esac

[ -n "$deploy" ] || { echo "verify-criteria-incomplete: $criteria (need .deploy)" >&2; exit 2; }
if [ -z "$ready" ] && [ -z "$want_rc" ]; then
  echo "verify-criteria-incomplete: $criteria (need health.ready_string and/or health.exit_code)" >&2
  exit 2
fi

# creds via env (§1.4) — indirect expansion (bash 3.2 ok)
ipv="${DEV}_IP"; userv="${DEV}_USER"; passv="${DEV}_PASS"
ip="${!ipv:-}"; user="${!userv:-}"; pass="${!passv:-}"
is_placeholder() { case "$1" in ''|your-*|*placeholder*|'<'*'>'|changeme|test-*-not-real) return 0;; *) return 1;; esac; }

SSH="${SDLC_SSH_BIN:-ssh}"; SCP="${SDLC_SCP_BIN:-scp}"
sshopts=(-o ServerAliveInterval=30 -o StrictHostKeyChecking=accept-new)
logpath="/tmp/${device}-deploy.log"
remote="$user@$ip"

redact() { printf '%s' "$1" | sed 's/./*/g'; }
if [ "$dry" -eq 1 ]; then
  echo "# hw-verify dry-run for device=$device (NOTHING is run remotely)"
  echo "device-env: ${ipv}=${ip:-<unset>} ${userv}=${user:-<unset>} ${passv}=$( [ -n "$pass" ] && redact "$pass" || echo '<unset>')"
  echo "criteria: deploy='$deploy' ready_string='$ready' exit_code='$want_rc' timeout_s=$timeout_s"
  echo "1) $SCP ${sshopts[*]} ${artifact:-<artifact>} $deploy $remote:/tmp/"
  echo "2) $SSH ${sshopts[*]} $remote \"nohup sh -c '/tmp/$(basename "${deploy:-deploy.sh}"); echo HWVERIFY_EXIT=\\\$?' >$logpath 2>&1 &\""
  echo "3) poll: $SSH ${sshopts[*]} $remote \"cat $logpath\"  (every ${SDLC_HW_POLL_SLEEP:-3}s up to ${timeout_s}s)"
  exit 0
fi

# real run — creds required + must not be placeholders (§1.4)
if is_placeholder "$ip" || is_placeholder "$user"; then
  echo "verify-bad-creds: set real ${ipv}/${userv} (and ${passv} or an SSH key) in env — no placeholders (§1.4)" >&2
  exit 2
fi

# 1. transport artifact + deploy script (scp). Failure ⇒ unreachable/auth/transport.
scpargs=("${sshopts[@]}"); [ -n "$artifact" ] && scpargs+=("$artifact")
scpargs+=("$deploy" "$remote:/tmp/")
if ! "$SCP" "${scpargs[@]}" >/dev/null 2>&1; then
  echo "verify-transport-failed: scp to $remote (check ${ipv}/${userv}/${passv} + network)" >&2
  exit 4
fi

# 2. start deploy in background, append an exit sentinel we can poll for (§4.4 nohup, not run_in_background)
dname="$(basename "$deploy")"
if ! "$SSH" "${sshopts[@]}" "$remote" "nohup sh -c '/tmp/$dname; echo HWVERIFY_EXIT=\$?' >$logpath 2>&1 &" >/dev/null 2>&1; then
  echo "verify-start-failed: ssh nohup on $remote" >&2
  exit 4
fi

# 3. poll the log until criteria met or timeout (SE16-safe verdict via case-glob)
verdict_met() {
  local log="$1" ok=1
  [ -n "$ready" ]   && case "$log" in *"$ready"*) ;; *) ok=0;; esac
  [ -n "$want_rc" ] && case "$log" in *"HWVERIFY_EXIT=$want_rc"*) ;; *) ok=0;; esac
  [ "$ok" -eq 1 ]
}
interval="${SDLC_HW_POLL_SLEEP:-3}"; elapsed=0; lastlog=""
while :; do
  lastlog=$("$SSH" "${sshopts[@]}" "$remote" "cat $logpath" 2>/dev/null || true)
  if verdict_met "$lastlog"; then
    echo "hw-verify PASS device=$device (criteria met)"
    exit 0
  fi
  [ "$elapsed" -ge "$timeout_s" ] && break
  if [ "$interval" -gt 0 ]; then sleep "$interval"; else break; fi
  elapsed=$((elapsed + interval))
done

# determine FAIL vs TIMEOUT: if the deploy finished (sentinel present) but criteria unmet ⇒ FAIL(3)
case "$lastlog" in
  *"HWVERIFY_EXIT="*) echo "hw-verify FAIL device=$device (deploy ran, criteria not met)" >&2; exit 3;;
  *) echo "hw-verify TIMEOUT device=$device (no ready signal in ${timeout_s}s)" >&2; exit 5;;
esac
