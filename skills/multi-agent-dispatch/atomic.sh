#!/usr/bin/env bash
# atomic.sh — portable (mkdir-lock) atomic write + read-modify-write.
# NO flock (absent on macOS); mkdir is POSIX-atomic. Stale lock = dead PID → reclaim.
# bash-3.2-safe per tests/PORTABILITY.md. source-able: defines functions, runs nothing.
# Explicit _lock/_unlock (not "_with_lock cmd...") so all work stays directly visible
# to shellcheck (the cmd-as-args pattern trips SC2317 on every function it dispatches).
set -uo pipefail
_LOCK_TIMEOUT="${SDLC_LOCK_TIMEOUT:-5}"

_lock() {  # $1=lockdir; spin + stale-reclaim; 0 ok / 1 timeout. Caller must _unlock.
  local lock="$1" waited=0 opid
  while ! mkdir "$lock" 2>/dev/null; do
    opid=$(cat "$lock/pid" 2>/dev/null || echo "")
    if [ -n "$opid" ] && ! kill -0 "$opid" 2>/dev/null; then
      # Stale holder (dead PID). Serialize the reclaim through a meta-lock so two racers
      # cannot both rm-rf + recreate the dir and both believe they won (TOCTOU double-
      # acquire). Re-verify the holder is still a *non-empty dead* PID under the meta-lock
      # — never delete a live holder, nor one that just mkdir'd but hasn't written its pid.
      if mkdir "$lock.reclaim" 2>/dev/null; then
        opid=$(cat "$lock/pid" 2>/dev/null || echo "")
        if [ -n "$opid" ] && ! kill -0 "$opid" 2>/dev/null; then rm -rf "$lock"; fi
        rmdir "$lock.reclaim" 2>/dev/null
      fi
      continue
    fi
    waited=$((waited+1)); [ "$waited" -gt $((_LOCK_TIMEOUT*10)) ] && return 1
    sleep 0.1
  done
  # Guard the residual mkdir→echo window: if a concurrent reclaimer destroyed our dir
  # before we wrote our pid, detect the failed write and bail so the caller retries.
  echo $$ > "$lock/pid" 2>/dev/null || { rm -rf "$lock" 2>/dev/null; return 1; }
}
_unlock() { rm -rf "$1"; }

atomic_write() {  # $1=target [$2=content | stdin]
  local target="$1" tmp dir rc
  dir=$(dirname "$target")
  tmp=$(mktemp "$dir/.tmp.XXXXXX") || return 1
  if [ "$#" -ge 2 ]; then printf '%s' "$2" > "$tmp"; else cat > "$tmp"; fi
  _lock "$target.lock" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$target"; rc=$?
  _unlock "$target.lock"
  return "$rc"
}

atomic_rmw() {  # $1=target  $2=transform_cmd (reads stdin, writes stdout)
  local target="$1" xf="$2" dir old new tmp rc=0
  dir=$(dirname "$target")
  _lock "$target.lock" || return 1
  old=""; [ -f "$target" ] && old=$(cat "$target")
  if new=$(printf '%s' "$old" | eval "$xf"); then
    if tmp=$(mktemp "$dir/.tmp.XXXXXX"); then
      printf '%s' "$new" > "$tmp"; mv -f "$tmp" "$target"; rc=$?
    else rc=1; fi
  else rc=2; fi
  _unlock "$target.lock"
  return "$rc"
}
