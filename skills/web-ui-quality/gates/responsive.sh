#!/usr/bin/env bash
# responsive.sh — real-layout gate. Facts (per-viewport "W:flag" CSV): SDLC_RESP_OVERFLOW (1 = scrollWidth>width)
# and SDLC_RESP_BBOX_IN (1 = key element's bounding box within the viewport). FAIL if ANY viewport overflows
# OR the key element is not in-viewport. Measures LAYOUT, not DOM presence (C2). Real reads = §7.3 PENDING.
# SE16-safe: `case` glob over the CSV (no |grep); `,$x,` wrapping makes the match work at every position.
set -uo pipefail
ov="${SDLC_RESP_OVERFLOW:-}"; bb="${SDLC_RESP_BBOX_IN:-}"
{ [ -n "$ov" ] && [ -n "$bb" ]; } || { echo "gate: responsive  verdict: UI-UNVERIFIED  detail: layout facts unavailable"; exit 0; }
# G3: fail-closed on malformed CSV — every field must be W:flag (0/1), and overflow/bbox cardinality must
# match. A shapeless field never matches the verdict globs below ⇒ silent PASS without this guard.
ovn="$(printf '%s' "$ov" | awk -F, '{for(i=1;i<=NF;i++) if($i!~/^[0-9]+:[01]$/){print -1;exit} print NF}')"
bbn="$(printf '%s' "$bb" | awk -F, '{for(i=1;i<=NF;i++) if($i!~/^[0-9]+:[01]$/){print -1;exit} print NF}')"
if [ "$ovn" -le 0 ] || [ "$bbn" -le 0 ] || [ "$ovn" -ne "$bbn" ]; then
  echo "gate: responsive  verdict: UI-UNVERIFIED  detail: malformed/mismatched layout facts (ov=$ov bb=$bb)"; exit 0
fi
fail=""
case ",$ov," in *:1,*) fail="horizontal overflow";; esac
case ",$bb," in *:0,*) fail="${fail:+$fail; }key element not in viewport";; esac
if [ -n "$fail" ]; then
  echo "gate: responsive  verdict: FAIL  detail: $fail (overflow: $ov / bbox: $bb)"; exit 10
else
  echo "gate: responsive  verdict: PASS  detail: no overflow, key element in viewport at all widths"; exit 0
fi
