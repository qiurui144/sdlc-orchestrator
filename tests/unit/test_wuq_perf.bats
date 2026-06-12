#!/usr/bin/env bats
# web-ui-quality perf gate (T6). Facts = SDLC_PERF_LCP/_CLS/_TBT, each a comma-list of N>=3 trace runs.
# FAIL when the MEAN breaches the SLO (NOT a σ-widened band, C3). High σ/mean ⇒ UI-UNVERIFIED (re-run),
# never a silent PASS. Real performance_*_trace = §7.3 PENDING-VERIFY.
P="$BATS_TEST_DIRNAME/../../skills/web-ui-quality/gates/perf.sh"
# helper: perf <lcp-csv> <cmd...>  — CLS/TBT fixed within-SLO; thresholds fixed. (cmd starts at $2.)
perf(){ env SDLC_PERF_LCP="$1" SDLC_PERF_CLS="0.0,0.0,0.0" SDLC_PERF_TBT="10,10,10" \
  WUQ_PERF_LCP=2500 WUQ_PERF_CLS=0.1 WUQ_PERF_TBT=200 WUQ_PERF_MAXSIG=0.25 "${@:2}"; }

@test "perf: mean within SLO ⇒ PASS" { run perf "2000,2100,2050" bash "$P"; [ "$status" -eq 0 ]; echo "$output"|grep -q "verdict: PASS"; }
@test "perf(C3): mean 44% over LCP (3000,3200,4600) ⇒ NEVER PASS" {
  run perf "3000,3200,4600" bash "$P"
  [ "$status" -ne 0 ]; echo "$output"|grep -q "verdict: PASS" && { echo "must not PASS"; false; } || true
}
@test "perf: low-noise clear breach ⇒ FAIL(11)" { run perf "4000,4050,3950" bash "$P"; [ "$status" -eq 11 ]; }
@test "perf: very noisy runs ⇒ UI-UNVERIFIED (never PASS, never silent)" {
  run perf "1000,1000,9000" bash "$P"; [ "$status" -eq 0 ]; echo "$output"|grep -q "UI-UNVERIFIED"
}
@test "perf(C-1): a clear FAIL metric dominates a NOISY metric ⇒ FAIL(11), never UI-UNVERIFIED" {
  run env SDLC_PERF_LCP="5000,5050,4950" SDLC_PERF_CLS="0.05,0.30,0.02" SDLC_PERF_TBT="10,10,10" \
    WUQ_PERF_LCP=2500 WUQ_PERF_CLS=0.1 WUQ_PERF_TBT=200 WUQ_PERF_MAXSIG=0.25 bash "$P"
  [ "$status" -eq 11 ]; echo "$output"|grep -q "verdict: FAIL"
}
@test "perf: facts absent ⇒ UI-UNVERIFIED" { run env -u SDLC_PERF_LCP bash "$P"; [ "$status" -eq 0 ]; echo "$output"|grep -q "UI-UNVERIFIED"; }
@test "perf(G3): non-numeric/unmeasured fact ⇒ UI-UNVERIFIED, never PASS" {
  run env SDLC_PERF_LCP="null,null,null" SDLC_PERF_CLS="0,0,0" SDLC_PERF_TBT="10,10,10" \
    WUQ_PERF_LCP=2500 WUQ_PERF_CLS=0.1 WUQ_PERF_TBT=200 WUQ_PERF_MAXSIG=0.25 bash "$P"
  [ "$status" -eq 0 ]; echo "$output"|grep -q "UI-UNVERIFIED"
  echo "$output"|grep -q "verdict: PASS" && { echo "garbage must not PASS"; false; } || true
}
