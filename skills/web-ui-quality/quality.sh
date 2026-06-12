#!/usr/bin/env bash
# quality.sh — deterministic web-UI quality-gate orchestrator (UI-2, v0.31). Runs the enabled gates on a
# UI-1-PASS page and aggregates. Every gate's PASS/FAIL is DETERMINISTIC; ui-vision-judge is consumed by
# the visual gate as an ADVISORY annotation only (deterministic-verdict-supremacy, both directions).
#
# Exit: 0 PASS / UI-UNVERIFIED-WARN / quality-skipped · 2 usage/bad-gate/all-disabled · 6 §6.4 lint ·
#       7 contract trivial / visual baseline · 8 a11y · 9 visual · 10 responsive · 11 perf.
# SE16-safe: branching via `case`/`awk` (awk reads to EOF), never `cmd | grep -q`/`| head -n` control flow.
set -uo pipefail

usage() { echo "usage: quality.sh --repo <dir> [--url <u>] [--gate a11y|visual|responsive|perf] [--stub <dir>] [--write-baseline] [--dry-run]" >&2; exit 2; }

HERE="$(cd "$(dirname "$0")" && pwd -P)"
repo="" url="" gate="" stub="" write_baseline=0 dry=0
[ "$#" -gt 0 ] || usage
while [ "$#" -gt 0 ]; do case "$1" in
  --repo)           repo="$2"; shift 2;;
  --url)            url="$2"; shift 2;;
  --gate)           gate="$2"; shift 2;;
  --stub)           stub="$2"; shift 2;;
  --write-baseline) write_baseline=1; shift;;
  --dry-run)        dry=1; shift;;
  *) echo "web-ui-quality-unknown-arg: $1" >&2; usage;;
esac; done

[ -n "$repo" ] || usage
case "$gate" in ""|a11y|visual|responsive|perf) ;; *) echo "web-ui-quality-bad-gate: $gate" >&2; exit 2;; esac

# §6.4 lint (Chrome-only) — reuse the rule
case "${SDLC_WEB_BROWSER:-chrome}" in chrome) ;; *) echo "lint: non-Chrome browser forbidden (§6.4)" >&2; exit 6;; esac

crit="${SDLC_WUQ_CRITERIA:-$repo/web-ui-verify.yaml}"

# UI-1 precondition: never grade a page that does not render
if [ "${SDLC_WUQ_UI1_VERDICT:-PASS}" != PASS ]; then
  echo "verdict:      quality-skipped"
  echo "reason:       UI-1 verdict != PASS (won't grade a non-rendered page)"
  exit 0
fi

# enabled gates = keys present under quality: (filtered by --gate)
enabled=""
for g in a11y visual responsive perf; do
  [ -n "$gate" ] && [ "$gate" != "$g" ] && continue
  has="$(yq -r ".quality.$g // \"\"" "$crit" 2>/dev/null)"
  [ -n "$has" ] && [ "$has" != null ] && enabled="$enabled $g"
done
enabled="${enabled# }"
[ -n "$enabled" ] || { echo "web-ui-quality: no enabled gates in $crit" >&2; exit 2; }

if [ "$dry" -eq 1 ]; then
  echo "enabled-gates: $enabled"
  echo "# dry-run (no browser). repo=$repo url=${url:-<unset>} write_baseline=$write_baseline stub=${stub:-<none>}"
  exit 0
fi

# --- contract thresholds + trivial fail-closed (T2) — a vacuous gate must not silently PASS ---
read_thr() { yq -r ".quality.$1.$2 // \"\"" "$crit" 2>/dev/null; }
trivial()  { echo "web-ui-quality-trivial-contract: $1" >&2; exit 7; }
# (assign-then-export — `export VAR=$(cmd)` masks the cmd return value, SC2155)
for g in $enabled; do case "$g" in
  a11y)
    mv="$(read_thr a11y max_violations)"; case "$mv" in ''|*[!0-9]*) trivial "a11y.max_violations";; esac
    [ "$mv" -ge 1000000 ] && trivial "a11y.max_violations too high (vacuous)"
    WUQ_A11Y_MINSEV="$(read_thr a11y min_severity)"
    export WUQ_A11Y_MAX="$mv" WUQ_A11Y_MINSEV ;;
  visual)
    dr="$(read_thr visual diff_ratio_max)"; mr="$(read_thr visual max_region_px)"
    awk -v d="$dr" 'BEGIN{exit (d=="" || d+0>=1)?0:1}' && trivial "visual.diff_ratio_max>=1 (vacuous)"
    case "$mr" in ''|*[!0-9]*) trivial "visual.max_region_px";; esac
    [ "$mr" -ge 1000000000 ] && trivial "visual.max_region_px (vacuous)"
    WUQ_VIS_BASEDIR="$(read_thr visual baseline_dir)"
    export WUQ_VIS_DR="$dr" WUQ_VIS_MR="$mr" WUQ_VIS_BASEDIR ;;
  responsive)
    vp="$(yq -r '.quality.responsive.viewports | length' "$crit" 2>/dev/null || echo 0)"
    case "$vp" in ''|0|null) trivial "responsive.viewports empty";; esac
    WUQ_RESP_VPS="$(yq -r '.quality.responsive.viewports | join(",")' "$crit")"
    export WUQ_RESP_VPS ;;
  perf)
    sl="$(read_thr perf 'slo.lcp_ms')"; [ -z "$sl" ] && trivial "perf.slo missing"
    WUQ_PERF_CLS="$(read_thr perf 'slo.cls')"; WUQ_PERF_TBT="$(read_thr perf 'slo.tbt_ms')"
    WUQ_PERF_SEEDS="$(read_thr perf seeds)"; WUQ_PERF_MAXSIG="$(read_thr perf max_rel_sigma)"
    export WUQ_PERF_LCP="$sl" WUQ_PERF_CLS WUQ_PERF_TBT WUQ_PERF_SEEDS WUQ_PERF_MAXSIG ;;
esac; done

# I-1: plumb --write-baseline to the visual gate (without this the establishment run hard-errors exit 7).
[ "$write_baseline" -eq 1 ] && export WUQ_VIS_WRITE_BASELINE=1

# --- dispatch enabled gates + aggregate (T7). quality.sh NEVER reads a vision verdict — it only
#     propagates each gate's deterministic exit, so deterministic-supremacy holds at the aggregate too. ---
echo "enabled-gates: $enabled"
agg=PASS; agg_code=0; warn=0
for g in $enabled; do
  out="$(bash "$HERE/gates/$g.sh")"; rc=$?
  echo "$out"
  case "$out" in *"verdict: UI-UNVERIFIED"*) warn=1;; esac
  if [ "$rc" -ne 0 ]; then
    agg=FAIL
    if [ "$agg_code" -eq 0 ] || [ "$rc" -lt "$agg_code" ]; then agg_code="$rc"; fi
  fi
done
if [ "$agg" = FAIL ]; then echo "verdict:      FAIL"; exit "$agg_code"; fi
if [ "$warn" -eq 1 ]; then echo "verdict:      PASS (some gates UI-UNVERIFIED — WARN)"; else echo "verdict:      PASS"; fi
exit 0
