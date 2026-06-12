#!/usr/bin/env bash
# perf.sh — Core Web Vitals gate. Facts = SDLC_PERF_LCP/_CLS/_TBT, each a comma-list of N>=3 trace runs.
# FAIL when the MEAN breaches the SLO (NOT a σ-widened band, C3). If σ/mean > WUQ_PERF_MAXSIG for any metric,
# the runs are too noisy to trust ⇒ UI-UNVERIFIED (re-run), never a silent PASS. SE16-safe (awk reads to EOF).
# Real performance_start_trace/stop_trace reads = §7.3 PENDING-VERIFY.
set -uo pipefail
lcp="${SDLC_PERF_LCP:-}"; cls="${SDLC_PERF_CLS:-}"; tbt="${SDLC_PERF_TBT:-}"
{ [ -n "$lcp" ] && [ -n "$cls" ] && [ -n "$tbt" ]; } || { echo "gate: perf  verdict: UI-UNVERIFIED  detail: trace facts unavailable"; exit 0; }
# judge_metric <csv-of-runs> <slo> <max_rel_sigma> → "PASS m" | "FAIL m" | "NOISY m sd"
judge_metric() {
  echo "$1" | awk -v slo="$2" -v ms="$3" -F, '
    { for(i=1;i<=NF;i++) if ($i !~ /^-?[0-9]+(\.[0-9]+)?$/) { print "NONNUM"; exit }   # G3: fail-closed on garbage
      s=0; for(i=1;i<=NF;i++) s+=$i; m=s/NF; v=0; for(i=1;i<=NF;i++) v+=($i-m)^2; sd=sqrt(v/NF);
      if (m>0 && (sd/m) > ms+0) { print "NOISY " m " " sd; exit }
      print (m > slo+0 ? "FAIL " m : "PASS " m) }'
}
rl="$(judge_metric "$lcp" "$WUQ_PERF_LCP" "$WUQ_PERF_MAXSIG")"
rc="$(judge_metric "$cls" "$WUQ_PERF_CLS" "$WUQ_PERF_MAXSIG")"
rt="$(judge_metric "$tbt" "$WUQ_PERF_TBT" "$WUQ_PERF_MAXSIG")"
# C-1: a deterministic SLO breach DOMINATES noise — check *FAIL* before *NOISY*, else a real breach on
# one metric is silently downgraded to UI-UNVERIFIED when an unrelated metric happens to be jittery.
# FAIL (a real breach) dominates; then non-numeric/unmeasured ⇒ UI-UNVERIFIED (never a false PASS, G3);
# then noisy ⇒ UI-UNVERIFIED; else PASS.
case "$rl$rc$rt" in
  *FAIL*)   echo "gate: perf  verdict: FAIL  detail: mean breaches SLO [lcp:$rl cls:$rc tbt:$rt]"; exit 11;;
  *NONNUM*) echo "gate: perf  verdict: UI-UNVERIFIED  detail: non-numeric/unmeasured trace fact [lcp:$rl cls:$rc tbt:$rt]"; exit 0;;
  *NOISY*)  echo "gate: perf  verdict: UI-UNVERIFIED  detail: runs too noisy (σ/mean>$WUQ_PERF_MAXSIG) — re-run [lcp:$rl cls:$rc tbt:$rt]"; exit 0;;
  *)        echo "gate: perf  verdict: PASS  detail: means within SLO [lcp:$rl cls:$rc tbt:$rt]"; exit 0;;
esac
