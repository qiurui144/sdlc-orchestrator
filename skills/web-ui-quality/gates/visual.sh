#!/usr/bin/env bash
# visual.sh — visual-regression gate. Facts = SDLC_VISUAL_DIFF_RATIO (global) + SDLC_VISUAL_MAX_REGION_PX
# (largest contiguous changed block). FAIL if EITHER exceeds its threshold (WUQ_VIS_DR / WUQ_VIS_MR).
# ui-vision-judge classification (SDLC_WUQ_VISION_CLASS) is ADVISORY ONLY — printed alongside, NEVER read
# into the verdict (deterministic-verdict-supremacy, both directions). Real screenshot/diff = §7.3 PENDING.
set -uo pipefail
# baseline guard (I5): missing baseline is a hard error on a normal run; only --write-baseline may write.
if [ "${SDLC_VISUAL_BASELINE_MISSING:-0}" = 1 ]; then
  if [ "${WUQ_VIS_WRITE_BASELINE:-0}" = 1 ]; then
    echo "gate: visual  verdict: UI-UNVERIFIED  detail: baseline established (--write-baseline)"; exit 0
  else
    echo "web-ui-quality-visual-no-baseline: missing baseline on a normal run (use --write-baseline once)" >&2; exit 7
  fi
fi
dr="${SDLC_VISUAL_DIFF_RATIO:-}"; mr="${SDLC_VISUAL_MAX_REGION_PX:-}"
{ [ -n "$dr" ] && [ -n "$mr" ]; } || { echo "gate: visual  verdict: UI-UNVERIFIED  detail: diff facts unavailable"; exit 0; }
# G3: fail-closed on non-numeric facts (awk would coerce garbage to 0 ⇒ a false PASS). dr=float, mr=int.
if ! awk -v d="$dr" -v r="$mr" 'BEGIN{exit (d ~ /^-?[0-9]+(\.[0-9]+)?$/ && r ~ /^[0-9]+$/)?0:1}'; then
  echo "gate: visual  verdict: UI-UNVERIFIED  detail: non-numeric diff facts (dr=$dr mr=$mr)"; exit 0
fi
ann=""; [ -n "${SDLC_WUQ_VISION_CLASS:-}" ] && ann="  vision_annotation: {\"classification\":\"${SDLC_WUQ_VISION_CLASS}\"}(advisory)"
# DETERMINISTIC verdict — vision class is NOT consulted here (supremacy).
over="$(awk -v d="$dr" -v t="$WUQ_VIS_DR" -v r="$mr" -v c="$WUQ_VIS_MR" 'BEGIN{print ((d+0>t+0)||(r+0>c+0))?1:0}')"
if [ "$over" = 1 ]; then
  echo "gate: visual  verdict: FAIL  detail: diff $dr (max $WUQ_VIS_DR) / region ${mr}px (max ${WUQ_VIS_MR}px)$ann"; exit 9
else
  echo "gate: visual  verdict: PASS  detail: diff $dr<=$WUQ_VIS_DR, region ${mr}<=${WUQ_VIS_MR}px$ann"; exit 0
fi
