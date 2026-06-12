#!/usr/bin/env bash
# a11y.sh — WCAG 2.1 AA gate. Facts = Lighthouse accessibility audit violations (SDLC_A11Y_VIOLATIONS_JSON,
# a JSON array of {id,impact}). Deterministic count vs WUQ_A11Y_MAX (ALL severities unless WUQ_A11Y_MINSEV
# floor set). Tool/facts absent ⇒ UI-UNVERIFIED (never a false PASS). Real lighthouse read = §7.3 PENDING.
set -uo pipefail
j="${SDLC_A11Y_VIOLATIONS_JSON:-}"
[ -n "$j" ] || { echo "gate: a11y  verdict: UI-UNVERIFIED  detail: lighthouse accessibility audit unavailable"; exit 0; }
maxv="${WUQ_A11Y_MAX:-0}"; minsev="${WUQ_A11Y_MINSEV:-}"
if [ -n "$minsev" ]; then
  # I-2: a real ordinal floor — count violations whose severity rank >= the configured floor's rank.
  # G3: rank is NULL-SAFE so a single entry with a missing impact can't abort the whole jq pipeline
  # (which would empty n ⇒ UI-UNVERIFIED ⇒ a REAL serious violation alongside it rides through as WARN).
  n="$(echo "$j" | jq --arg s "$minsev" '
    def rank: (. // "") as $i | {"minor":1,"moderate":2,"serious":3,"critical":4}[$i] // 0;
    [.[] | select((.impact|rank) >= ($s|rank))] | length' 2>/dev/null)"
else
  n="$(echo "$j" | jq 'length' 2>/dev/null)"
fi
case "$n" in ''|*[!0-9]*) echo "gate: a11y  verdict: UI-UNVERIFIED  detail: malformed accessibility audit JSON"; exit 0;; esac
if [ "$n" -le "$maxv" ]; then echo "gate: a11y  verdict: PASS  detail: $n <= $maxv WCAG 2.1 AA violations"; exit 0
else echo "gate: a11y  verdict: FAIL  detail: $n > $maxv WCAG 2.1 AA violations"; exit 8; fi
