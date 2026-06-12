#!/usr/bin/env bash
# fanout.sh — enumerate the parallel units of a known fan-out group (conservative, v0.17).
# Single SSOT for "what to fire in one dispatch-batch turn". REUSES panel.sh for the panel
# group (no re-impl of size/high-risk/lens); intake dims are the SSOT here; waves stay in the
# v0.10 implementer. The orchestrator gates EVERY fan-out via budget.sh BEFORE batching.
# Zero LLM. bash-3.2-safe.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

group="${1:-}"; [ -n "$group" ] && shift
artifact="" handoff="" size="" free=0
while [ "$#" -gt 0 ]; do case "$1" in
  --artifact) artifact="$2"; shift 2;;
  --handoff) handoff="$2"; shift 2;;
  --size) size="$2"; shift 2;;
  --free-only) free=1; shift;;
  *) shift;;
esac; done

case "$group" in
  groups)
    printf '%s\n' panel intake
    ;;
  intake)
    if [ "$free" -eq 1 ]; then
      printf '%s\n' deps debt docs disk secrets
    else
      printf '%s\n' deps debt docs disk secrets review threat perf
    fi
    ;;
  panel)
    n="$size"; lenses="correctness,security,scope,rubric,performance"
    if [ -z "$n" ]; then
      if [ -z "$artifact" ] || [ -z "$handoff" ]; then
        echo "fanout-panel-needs: --artifact + --handoff (or --size N)" >&2; exit 2
      fi
      out=$(bash "$HERE/../challenger-panel/panel.sh" --dispatch --artifact "$artifact" --handoff "$handoff" 2>/dev/null) || {
        echo "fanout-panel-dispatch-failed" >&2; exit 2; }
      n=$(printf '%s\n' "$out" | sed -n 's/.*size=\([0-9]*\).*/\1/p')
      lz=$(printf '%s\n' "$out" | sed -n 's/.*lenses=\([a-z,]*\).*/\1/p')
      [ -n "$lz" ] && lenses="$lz"
    fi
    case "$n" in ''|*[!0-9]*) echo "fanout-panel-bad-size: $n" >&2; exit 2;; esac
    # awk reads to EOF then prints first n — NOT `head -n`, which closes the pipe early →
    # tr SIGPIPEs → under `set -o pipefail` the pipeline exits 141 (same flake class as emit.sh).
    printf '%s\n' "$lenses" | tr ',' '\n' | awk -v n="$n" 'NR<=n'
    ;;
  *)
    echo "usage: fanout.sh groups | intake [--free-only] | panel [--artifact A --handoff H | --size N]" >&2
    exit 2
    ;;
esac
