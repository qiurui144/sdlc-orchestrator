#!/usr/bin/env bash
# counter.sh — cross-turn in-flight slot counter, atomic via atomic.sh.
# Soft concurrency cap shared across orchestrators (real value lands in v0.11/v0.12).
# bash-3.2-safe. source-able. The persisted file holds a single integer.
set -uo pipefail
_CDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=skills/multi-agent-dispatch/atomic.sh
. "$_CDIR/atomic.sh"
_CFILE="${SDLC_COUNTER_FILE:-.sdlc/counter}"
_cap() { echo "${SDLC_MAX_PARALLEL:-2}"; }
_read() {  # always echoes an integer; empty/absent file → 0 (guards budget.sh arithmetic)
  local v
  v=$([ -f "$_CFILE" ] && cat "$_CFILE" 2>/dev/null || echo "")
  [ -z "$v" ] && v=0
  echo "$v"
}

counter_reset()    { mkdir -p "$(dirname "$_CFILE")"; atomic_write "$_CFILE" "0"; }
counter_inflight() { _read; }

counter_acquire() {  # $1=n ; emits n slot ids; exit 3 = cap exceeded, 1 = infra error
  local n="$1" cur cap i rmw_rc=0
  cur=$(_read); cap=$(_cap)
  [ $((cur + n)) -gt "$cap" ] && return 3            # optimistic fast-path reject
  mkdir -p "$(dirname "$_CFILE")"
  # Authoritative re-check inside the lock: awk exits 3 (no print) if it would exceed cap.
  # BEGIN/END so it emits a value even on a fresh (empty) file → correct init to n.
  atomic_rmw "$_CFILE" "awk -v n=$n -v cap=$cap 'BEGIN{c=0}{c=\$1+0}END{if(c+n>cap) exit 3; print c+n}'" || rmw_rc=$?
  [ "$rmw_rc" -eq 2 ] && return 3                    # awk exit 3 → atomic_rmw rc 2 → cap exceeded
  [ "$rmw_rc" -ne 0 ] && return 1                    # lock timeout / I/O error: don't mislabel as cap
  i=1; while [ "$i" -le "$n" ]; do echo "slot-$$-$i"; i=$((i+1)); done
}

counter_release() {  # $1=n ; floors at 0
  local n="$1"; mkdir -p "$(dirname "$_CFILE")"
  atomic_rmw "$_CFILE" "awk -v n=$n 'BEGIN{c=0}{c=\$1+0}END{c=c-n; if(c<0)c=0; print c}'" \
    || echo "counter_release: atomic_rmw failed — slot may be leaked ($_CFILE)" >&2
}
