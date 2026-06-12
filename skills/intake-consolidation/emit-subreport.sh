#!/usr/bin/env bash
# emit-subreport.sh — write a normalized intake sub-report with a machine-readable header.
# Usage: emit-subreport.sh <out-file> <dim> <verdict> <score> <top> [<native-body-file>]
#   verdict ∈ PASS|WARN|FAIL|BLOCK|INCONCLUSIVE ; score = 0.0-1.0 or N/A
set -euo pipefail

[ $# -ge 5 ] || { echo "usage: emit-subreport.sh <out> <dim> <verdict> <score> <top> [body]" >&2; exit 1; }

out="$1"; dim="$2"; verdict="$3"; score="$4"; top="$5"; body="${6:-}"

case "$verdict" in
  PASS|WARN|FAIL|BLOCK|INCONCLUSIVE) : ;;
  *) echo "emit-subreport: bad verdict '$verdict' (PASS|WARN|FAIL|BLOCK|INCONCLUSIVE)" >&2; exit 2 ;;
esac

top="${top//\"/\'}"   # replace any double-quote with single-quote to preserve header parseability

{
  printf '<!-- sdlc-intake: dim=%s verdict=%s score=%s top="%s" -->\n' "$dim" "$verdict" "$score" "$top"
  printf '# intake/%s — %s\n\n' "$dim" "$verdict"
  if [ -n "$body" ] && [ -f "$body" ]; then
    cat "$body"
  else
    printf '_top issue:_ %s\n' "$top"
  fi
} > "$out"
