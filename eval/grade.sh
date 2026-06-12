#!/usr/bin/env bash
# grade.sh — pure mechanical grader. Asserts an agent's captured output against an
# expect.yaml contract. NEVER reads any self-score the agent emitted (codifies the
# AC1/R14 anti-pattern: agents self-report PASS; the grader is independent).
#
# Usage: grade.sh <output-file> <expect.yaml>
#   exit 0 = all assertions pass (or vacuous: no assertions)
#   exit 1 = one or more assertions failed
#   exit 2 = malformed input (missing file / unparseable yaml / unknown kind)
#
# bash-3.2-safe / POSIX userland per tests/PORTABILITY.md (no declare -A, no
# mapfile, no GNU-only flags).
set -euo pipefail

out="${1:?usage: grade.sh <output-file> <expect.yaml>}"
exp="${2:?usage: grade.sh <output-file> <expect.yaml>}"

[ -f "$out" ] || { echo "eval-grader-malformed: output file missing: $out" >&2; exit 2; }
[ -f "$exp" ] || { echo "eval-grader-malformed: expect file missing: $exp" >&2; exit 2; }

n=$(yq '.assertions | length' "$exp" 2>/dev/null) || {
  echo "eval-grader-malformed: cannot parse assertions in $exp" >&2; exit 2; }
case "$n" in ''|*[!0-9]*) echo "eval-grader-malformed: bad assertion count in $exp" >&2; exit 2 ;; esac

if [ "$n" -eq 0 ]; then
  echo "GRADE PASS (0 assertions — vacuous; add assertions to $exp)" >&2
  exit 0
fi

fails=0
i=0
while [ "$i" -lt "$n" ]; do
  kind=$(yq -r ".assertions[$i].kind" "$exp")
  case "$kind" in
    all_present)
      missing=""
      while IFS= read -r s; do
        [ -z "$s" ] && continue
        grep -qiF -- "$s" "$out" || missing="$missing [$s]"
      done <<EOF
$(yq -r ".assertions[$i].of[]" "$exp")
EOF
      if [ -n "$missing" ]; then
        echo "FAIL[$i] all_present missing:$missing" >&2; fails=$((fails+1))
      else echo "ok[$i] all_present"; fi
      ;;
    any_present)
      hit=0
      while IFS= read -r s; do
        [ -z "$s" ] && continue
        if grep -qiF -- "$s" "$out"; then hit=1; break; fi
      done <<EOF
$(yq -r ".assertions[$i].of[]" "$exp")
EOF
      if [ "$hit" -eq 0 ]; then
        echo "FAIL[$i] any_present: none of the options matched" >&2; fails=$((fails+1))
      else echo "ok[$i] any_present"; fi
      ;;
    count_at_least)
      pat=$(yq -r ".assertions[$i].pattern" "$exp")
      min=$(yq -r ".assertions[$i].min" "$exp")
      c=$(grep -oE "$pat" "$out" 2>/dev/null | sort -u | wc -l | tr -d ' ')
      if [ "$c" -lt "$min" ]; then
        echo "FAIL[$i] count_at_least /$pat/: $c < $min" >&2; fails=$((fails+1))
      else echo "ok[$i] count_at_least /$pat/ ($c >= $min)"; fi
      ;;
    llm_judge)
      echo "ok[$i] llm_judge SKIPPED (run eval/judge.sh --run for narrative quality)"
      ;;
    *)
      echo "eval-grader-malformed: unknown assertion kind '$kind' at [$i]" >&2; exit 2
      ;;
  esac
  i=$((i+1))
done

if [ "$fails" -eq 0 ]; then
  echo "GRADE PASS ($n assertions)"; exit 0
else
  echo "GRADE FAIL ($fails of $n assertions failed)" >&2; exit 1
fi
