#!/usr/bin/env bash
# judge.sh — LLM-judge grader for narrative quality (what grep can't assert).
# Modes:
#   judge.sh --parse <verdict-file>            pure: extract VERDICT (PASS/FAIL). exit 0/1; 2=malformed
#   judge.sh --run <agent-output> <expect.yaml>  real LLM: judge each kind:llm_judge, N=3 majority
#   judge.sh --calibrate <expect.yaml> <good> <bad>  judge must PASS good + FAIL bad → exit 0
# --parse is pure (CI-tested). --run/--calibrate dispatch claude -p (human-triggered, NOT CI).
# Honest: the judge is a non-deterministic, fallible SIGNAL — calibration is the trust gate.
# POSIX/bash-3.2-safe per tests/PORTABILITY.md (no realpath, no date -d, no declare -A).
set -uo pipefail

JUDGE_TIER="${SDLC_JUDGE_TIER:-opus}"
VOTES="${SDLC_JUDGE_VOTES:-3}"

mode="${1:-}"

# ---- pure: extract verdict from one judge output ----
parse_verdict() {  # $1=file; echoes PASS|FAIL; returns 0/1; 2 if malformed
  local f="$1" line
  [ -f "$f" ] || { echo "judge-malformed-verdict: file missing: $f" >&2; return 2; }
  line=$(grep -iE '^[[:space:]]*VERDICT:[[:space:]]*(PASS|FAIL)' "$f" | head -1)
  [ -n "$line" ] || { echo "judge-malformed-verdict: no 'VERDICT: PASS|FAIL' line in $f" >&2; return 2; }
  case "$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')" in
    *pass*) echo PASS; return 0 ;;
    *fail*) echo FAIL; return 1 ;;
  esac
  echo "judge-malformed-verdict: unparseable verdict in $f" >&2; return 2
}

if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "$mode" = "--parse" ]; then
  v=$(parse_verdict "${2:?usage: judge.sh --parse <verdict-file>}"); rc=$?
  [ "$rc" -ne 2 ] && echo "$v"
  exit $rc
fi

# ---- real LLM: judge one rubric against an agent output, N votes, majority ----
# emits the majority verdict to stdout, returns 0 (PASS) / 1 (FAIL) / 2 (all votes malformed)
judge_one() {  # $1=agent-output-file  $2=rubric
  local out="$1" rubric="$2" pass=0 fail=0 mal=0 v rc n
  local tmpd; tmpd=$(mktemp -d)
  n=1
  while [ "$n" -le "$VOTES" ]; do
    local vf="$tmpd/vote$n.out"
    claude -p "You are an impartial eval JUDGE. Apply this rubric to the SUBMISSION below.
Answer in EXACTLY this format, first line a verdict:
VERDICT: PASS|FAIL
REASON: <one or two sentences, QUOTE the specific line you judged>

RUBRIC: $rubric

SUBMISSION:
$(cat "$out")" --model "$JUDGE_TIER" --dangerously-skip-permissions > "$vf" 2>"$vf.err" \
      || echo "judge-dispatch-failed: vote $n" >&2
    v=$(parse_verdict "$vf"); rc=$?
    case "$rc" in 0) pass=$((pass+1));; 1) fail=$((fail+1));; *) mal=$((mal+1));; esac
    n=$((n+1))
  done
  rm -rf "$tmpd"
  # majority of valid votes; all malformed → 2
  if [ "$pass" -eq 0 ] && [ "$fail" -eq 0 ]; then echo "MALFORMED"; return 2; fi
  if [ "$pass" -ge "$fail" ]; then echo "PASS ($pass/$((pass+fail)) votes)"; return 0
  else echo "FAIL ($fail/$((pass+fail)) votes)"; return 1; fi
}

# iterate the kind:llm_judge assertions in an expect.yaml against an agent output
run_judges() {  # $1=agent-output  $2=expect.yaml ; returns 0 all PASS / 1 any FAIL / 2 malformed
  local out="$1" exp="$2" nfail=0 i n kind rubric res rc
  n=$(yq '.assertions | length' "$exp" 2>/dev/null) || { echo "eval-grader-malformed: $exp" >&2; return 2; }
  i=0
  while [ "$i" -lt "$n" ]; do
    kind=$(yq -r ".assertions[$i].kind" "$exp")
    if [ "$kind" = "llm_judge" ]; then
      rubric=$(yq -r ".assertions[$i].rubric" "$exp")
      res=$(judge_one "$out" "$rubric"); rc=$?
      case "$rc" in
        0) echo "judge[$i] PASS — $res" ;;
        1) echo "judge[$i] FAIL — $res" >&2; nfail=$((nfail+1)) ;;
        *) echo "judge[$i] MALFORMED (all votes unparseable)" >&2; return 2 ;;
      esac
    fi
    i=$((i+1))
  done
  [ "$nfail" -eq 0 ] && return 0 || return 1
}

# source-guard: when sourced (panel reuses parse_verdict), do NOT run CLI dispatch.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
case "$mode" in
  --run)
    run_judges "${2:?need agent-output}" "${3:?need expect.yaml}"; exit $?
    ;;
  --calibrate)
    exp="${2:?}"; good="${3:?}"; bad="${4:?need <expect> <good> <bad>}"
    echo "calibration: judge must PASS good, FAIL bad"
    run_judges "$good" "$exp" >/dev/null 2>&1; gp=$?
    run_judges "$bad"  "$exp" >/dev/null 2>&1; bp=$?
    echo "  good.out → $([ "$gp" -eq 0 ] && echo PASS || echo FAIL)  (want PASS)"
    echo "  bad.out  → $([ "$bp" -eq 1 ] && echo FAIL || echo PASS)  (want FAIL)"
    if [ "$gp" -eq 0 ] && [ "$bp" -eq 1 ]; then echo "CALIBRATED ✓ (judge discriminates)"; exit 0
    else echo "judge-not-calibrated: rubric cannot distinguish good from bad — rewrite it" >&2; exit 1; fi
    ;;
  *)
    echo "usage: judge.sh --parse <file> | --run <output> <expect> | --calibrate <expect> <good> <bad>" >&2
    exit 2
    ;;
esac
fi
