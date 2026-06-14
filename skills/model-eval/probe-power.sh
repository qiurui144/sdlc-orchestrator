#!/usr/bin/env bash
# probe-power.sh — EXACT-binomial power for the C-2 injected-defect SPC gate (Task 2).
#
# Model: M probes per window, claude-verify recall prob = p. The gate TRIPS when the observed recall
# X/M < floor. power(M,p1) = P[X < M*floor | X~Binomial(M,p1)] — the chance we detect a degraded recall
# p1. We find the min M with power >= target. NO continuous two-sample approximation: rev.3-review
# showed that formula was wrong AND power is NON-MONOTONIC in M (the trip threshold M*floor jumps with
# integer rounding), so we scan M with the exact binomial CDF and report whether power STAYS >= target.
#
# Usage: probe-power.sh [--p0 .95] [--p1 .7] [--floor .8] [--target-power .9] [--max-m N] [--power-at M]
# bash-3.2-safe; shellcheck -x clean.
set -uo pipefail

p0=0.95 p1=0.7 floor=0.8 target=0.9 maxm=200 atm=""
while [ "$#" -gt 0 ]; do case "$1" in
  --p0) p0="$2"; shift 2;; --p1) p1="$2"; shift 2;; --floor) floor="$2"; shift 2;;
  --target-power) target="$2"; shift 2;; --max-m) maxm="$2"; shift 2;; --power-at) atm="$2"; shift 2;;
  *) echo "probe-power: unknown arg $1" >&2; exit 2;; esac; done

# power(M,p) = P[X < M*floor | Bin(M,p)], computed by an iterative (overflow-safe) pmf.
powerf() {
  awk -v M="$1" -v p="$2" -v floor="$floor" 'BEGIN{
    thr = M*floor; pmf = (1-p)^M; cdf = 0;
    for (x=0; x<=M; x++) {
      if (x>0) pmf = pmf * (M-x+1)/x * p/(1-p);
      if (x < thr) cdf += pmf;
    }
    printf "%.6f", cdf }'
}

if [ -n "$atm" ]; then
  echo "power_at_M=$atm p1=$p1: $(powerf "$atm" "$p1")  false_alarm_at_p0: $(powerf "$atm" "$p0")"
  exit 0
fi

m=1
while [ "$m" -le "$maxm" ]; do
  pw="$(powerf "$m" "$p1")"
  if awk -v a="$pw" -v t="$target" 'BEGIN{exit !(a>=t)}'; then
    # non-monotonic guard: does it STAY >= target over the next 5 M?
    stays=1; j="$m"; end=$((m+5))
    while [ "$j" -le "$end" ] && [ "$j" -le "$maxm" ]; do
      awk -v a="$(powerf "$j" "$p1")" -v t="$target" 'BEGIN{exit !(a>=t)}' || stays=0
      j=$((j+1))
    done
    echo "min_M=$m power=$pw target=$target p0=$p0 p1=$p1 floor=$floor stays_next5=$([ "$stays" -eq 1 ] && echo yes || echo NO-nonmonotonic)"
    exit 0
  fi
  m=$((m+1))
done
echo "min_M=NONE (no M<=$maxm reaches power $target)"; exit 1
