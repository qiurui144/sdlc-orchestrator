#!/usr/bin/env bash
# jobs.sh — file-based background-job registry: register/complete/list/inflight/reap.
# Tracks STATUS only; results live in reports/runs/ (R18). Reuses atomic.sh write.
# Orthogonal to counter.sh: jobs records state; the orchestrator releases a counter slot
# on ANY exit from running — complete OR reap→orphaned (spec §3 slot-release invariant,
# G1 correctness fix: reap also frees the slot so a crashed job never leaks one).
# bash-3.2-safe per tests/PORTABILITY.md.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=skills/multi-agent-dispatch/atomic.sh
. "$HERE/../multi-agent-dispatch/atomic.sh"

now() { echo "${SDLC_NOW_OVERRIDE:-$(date +%s)}"; }
# valid id: no path separator / no shell metachar — blocks ../ traversal + injection.
# Also reject "." / ".." explicitly (G2 hygiene): they pass the charset but are not job ids.
valid_id() { case "$1" in ''|.|..|*[!A-Za-z0-9._-]*) return 1;; *) return 0;; esac; }
field() { grep "^$1=" "$2" 2>/dev/null | head -1 | sed "s/^$1=//"; }

sub="${1:-}"; [ "$#" -gt 0 ] && shift
id="" label="" status="" maxage=""
dir="${SDLC_JOBS_DIR:-.sdlc/jobs}"
while [ "$#" -gt 0 ]; do case "$1" in
  --id) id="$2"; shift 2;;
  --label) label="$2"; shift 2;;
  --status) status="$2"; shift 2;;
  --max-age) maxage="$2"; shift 2;;
  --dir) dir="$2"; shift 2;;
  *) shift;;
esac; done

write_job() {  # $1=id $2=status $3=ts $4=label  (atomic, single per-id file)
  atomic_write "$dir/$1.job" "status=$2
ts=$3
label=$4
"
}

case "$sub" in
  register)
    valid_id "$id" || { echo "bad-id=$id" >&2; exit 2; }
    mkdir -p "$dir"
    # strip CR/LF so a multi-line label can't inject an extra record line into the
    # line-based .job format (G3 review hardening; status is line 1 so head -1 already
    # prevents status-hijack, this keeps the format clean + label intact)
    label=$(printf '%s' "$label" | tr -d '\n\r')
    write_job "$id" running "$(now)" "$label" || { echo "write-failed=$id" >&2; exit 2; }
    echo "registered=$id"
    ;;
  complete)
    valid_id "$id" || { echo "bad-id=$id" >&2; exit 2; }
    [ -f "$dir/$id.job" ] || { echo "missing-job=$id" >&2; exit 2; }
    write_job "$id" "${status:-done}" "$(field ts "$dir/$id.job")" "$(field label "$dir/$id.job")"
    echo "completed=$id status=${status:-done}"
    ;;
  list)
    want="${status:-all}"
    found=0
    if [ -d "$dir" ]; then
      for f in "$dir"/*.job; do
        [ -f "$f" ] || continue
        jst=$(field status "$f")
        if [ "$want" = "all" ] || [ "$want" = "$jst" ]; then
          echo "id=$(basename "$f" .job) status=$jst label=$(field label "$f")"; found=1
        fi
      done
    fi
    [ "$found" -eq 0 ] && echo "none"
    exit 0
    ;;
  inflight)
    c=0
    if [ -d "$dir" ]; then
      for f in "$dir"/*.job; do
        [ -f "$f" ] || continue
        [ "$(field status "$f")" = "running" ] && c=$((c+1))
      done
    fi
    echo "$c"
    ;;
  reap)
    [ -n "$maxage" ] || { echo "usage: reap --max-age <s>" >&2; exit 2; }
    n=$(now)
    if [ -d "$dir" ]; then
      for f in "$dir"/*.job; do
        [ -f "$f" ] || continue
        [ "$(field status "$f")" = "running" ] || continue
        ts=$(field ts "$f"); [ -z "$ts" ] && continue
        if [ "$((n - ts))" -gt "$maxage" ]; then
          jid=$(basename "$f" .job)
          write_job "$jid" orphaned "$ts" "$(field label "$f")"
          echo "reaped=$jid"
        fi
      done
    fi
    exit 0
    ;;
  *)
    echo "usage: jobs.sh register|complete|list|inflight|reap [--id <id>] [--label <t>] [--status <s>] [--max-age <s>] [--dir <d>]" >&2
    exit 2
    ;;
esac
