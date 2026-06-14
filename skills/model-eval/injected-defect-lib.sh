#!/usr/bin/env bash
# injected-defect-lib.sh — C-2 injected-defect library loader + circular-blind-spot guard (§6a).
#
# A library built ONLY from claude-caught defects is tautological: it can never surface the defect
# types claude SYSTEMATICALLY MISSES (those were, by definition, never caught). So `validate` is
# FAIL-CLOSED — it requires ≥1 entry sourced `prod-MISSED` (a deepseek error claude's verify let
# through, found later by human/downstream) or `cross-provider` (labelled by qwen/human, not claude).
# Until such real calibration data exists for a task_type, C-2 cannot activate draft-verify for it.
#
# Subcommands: validate|list|pick|hash <task_type>. bash-3.2-safe; shellcheck -x clean.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$HERE/../.." && pwd -P)"
LIBDIR="${SDLC_INJECTED_DEFECTS_DIR:-$ROOT/config/injected-defects}"

cmd="${1:-}"; tt="${2:-}"
{ [ -n "$cmd" ] && [ -n "$tt" ]; } || { echo "usage: injected-defect-lib.sh validate|list|pick|hash <task_type>" >&2; exit 2; }
libf="$LIBDIR/$tt.yaml"
[ -f "$libf" ] || { echo "no-lib: $tt"; exit 2; }

case "$cmd" in
  validate)
    # circular-blind-spot guard: must have ≥1 prod-MISSED or cross-provider entry (not just claude-caught)
    real="$(yq '[.defects[] | select(.source=="prod-MISSED" or .source=="cross-provider")] | length' "$libf" 2>/dev/null)"
    case "$real" in
      ''|0) echo "circular-blind-spot: lib for '$tt' has no prod-MISSED/cross-provider entry (only claude-caught = tautological; fail-closed until real calibration data)"; exit 1 ;;
    esac
    # every entry must carry all required fields
    incomplete="$(yq '[.defects[] | select((.id==null) or (.defect_type==null) or (.planted_patch==null) or (.detect_marker==null) or (.source==null))] | length' "$libf" 2>/dev/null)"
    case "$incomplete" in
      ''|0) ;;
      *) echo "incomplete-entry: '$tt' has $incomplete entries missing a required field"; exit 1 ;;
    esac
    echo "lib-valid: $tt ($(yq '.defects | length' "$libf") defects, $real real-source)"
    ;;
  list) yq -r '.defects[].id' "$libf" ;;
  pick) yq -o=json -I=0 '.defects[0]' "$libf" ;;   # plan: seeded rotation; index-0 for now
  hash) yq -o=json '.' "$libf" | sha256sum | awk '{print $1}' ;;
  *) echo "usage: injected-defect-lib.sh validate|list|pick|hash <task_type>" >&2; exit 2 ;;
esac
