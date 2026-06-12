#!/usr/bin/env bash
# consolidate.sh — merge intake sub-reports into one project-health scorecard.
# Usage: consolidate.sh <reports-dir> [<out-file>]
#   scans <reports-dir>/*.md for '<!-- sdlc-intake: ... -->'.
#   optional <reports-dir>/intake-meta.env (KEY=VALUE) → Run metadata section.
set -uo pipefail
dir="${1:?usage: consolidate.sh <reports-dir> [out-file]}"
out="${2:-$dir/project-health.md}"

rows=""
for f in "$dir"/*.md; do
  [ -e "$f" ] || continue
  hdr=$(grep -m1 -E '<!-- sdlc-intake: ' "$f" 2>/dev/null) || continue
  dim=$(printf '%s' "$hdr"     | sed -n 's/.*dim=\([^ ]*\).*/\1/p')
  verdict=$(printf '%s' "$hdr" | sed -n 's/.*verdict=\([^ ]*\).*/\1/p')
  score=$(printf '%s' "$hdr"   | sed -n 's/.*score=\([^ ]*\).*/\1/p')
  top=$(printf '%s' "$hdr"     | sed -n 's/.*top="\([^"]*\)".*/\1/p')
  top=$(printf '%s' "$top" | tr '|' '/')   # internal rows are |-delimited; keep top single-field
  rows="${rows}${dim}|${verdict}|${score}|${top}|$(basename "$f")
"
done

overall="HEALTHY"; suffix=""
if printf '%s' "$rows" | awk -F'|' '$2=="BLOCK"{f=1} END{exit !f}'; then
  overall="AT-RISK"
elif printf '%s' "$rows" | awk -F'|' '$2=="FAIL"{f=1} END{exit !f}'; then
  overall="NEEDS-ATTENTION"
elif printf '%s' "$rows" | awk -F'|' 'NF&&$2!="INCONCLUSIVE"{f=1} END{exit f}'; then
  suffix=" (low-signal)"
fi

{
  printf '# Project Health — intake\n\n## Scorecard\n\n'
  printf '| dimension | verdict | score | top issue |\n|---|---|---|---|\n'
  printf '%s' "$rows" | awk -F'|' 'NF{printf "| %s | %s | %s | %s |\n",$1,$2,$3,$4}'
  printf '\n## Overall verdict: %s%s\n\n## Prioritized fixes\n\n' "$overall" "$suffix"
  printf '%s' "$rows" | awk -F'|' '$2=="BLOCK"{printf "- **P0** [%s] %s\n",$1,$4}'
  printf '%s' "$rows" | awk -F'|' '$2=="FAIL"{printf  "- **P1** [%s] %s\n",$1,$4}'
  printf '%s' "$rows" | awk -F'|' '$2=="WARN"{printf  "- **P2** [%s] %s\n",$1,$4}'
  printf '\n## Per-dimension reports\n\n'
  printf '%s' "$rows" | awk -F'|' 'NF{printf "- [%s](./%s)\n",$1,$5}'
  printf '\n## Run metadata\n\n'
  if [ -f "$dir/intake-meta.env" ]; then
    while IFS='=' read -r k v; do [ -n "$k" ] && printf -- '- %s: %s\n' "$k" "$v"; done < "$dir/intake-meta.env"
  else
    printf -- '- (not recorded)\n'
  fi
} > "$out"
echo "$out"
