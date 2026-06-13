#!/usr/bin/env bash
# grader.sh — deterministic scorer for the eval-gated-routing (M2) gate. The SAME
# scorer runs offline (eval: output vs a stored --golden) and online (executor
# oracle: output vs an expected RE-DERIVED from the input via --derive). A wrong
# scorer would let a bad model pass, so this is validated FIRST (tests/grader/).
#
# Usage:
#   grader.sh --task <t> --output <f> --golden <f>     # eval mode
#   grader.sh --task <t> --output <f> --derive <input> # online mode (re-derive expected)
#   grader.sh hash <file>...                           # sha256 of concatenated files (sources_hash)
#   -> prints "score=<0..1>" (exit 0). Malformed input -> score=0.000 (never crash).
#
# bash-3.2-safe; shellcheck -x clean; SE16-safe (no early-pipe-close control flow).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
MODES="${SDLC_GRADER_MODES:-$HERE/grader-modes.yaml}"

die() { echo "grader: $*" >&2; exit 2; }

# ---- sources_hash subcommand (used by eval.sh + executor.sh) ----
if [ "${1:-}" = "hash" ]; then
  shift
  [ "$#" -gt 0 ] || die "hash needs >=1 file"
  # concatenate file contents in argument order, sha256 — stable across runs.
  for f in "$@"; do [ -f "$f" ] || die "hash: missing $f"; done
  cat -- "$@" | sha256sum | awk '{print $1}'
  exit 0
fi

# ---- build-messages subcommand: the SHARED task prompt used at BOTH eval time
#      (eval.sh) and routing time (executor.sh). Reading it from grader-modes.yaml
#      (already a sources_hash input) guarantees the eval F1 represents the routed
#      behavior AND that a prompt change invalidates a stale allowlist. Emits an
#      OpenAI messages array: [system, few-shot user, few-shot assistant, user(input)].
if [ "${1:-}" = "build-messages" ]; then
  shift
  bm_task="" bm_input=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --task)  bm_task="$2"; shift 2 ;;
      --input) bm_input="$2"; shift 2 ;;
      *) die "build-messages: unknown arg: $1" ;;
    esac
  done
  if [ -z "$bm_task" ] || [ -z "$bm_input" ]; then die "build-messages: --task <t> --input <f>"; fi
  [ -f "$bm_input" ] || die "build-messages: missing input file $bm_input"
  bm_sys="$(yq -r ".\"$bm_task\".eval_system // \"\"" "$MODES" 2>/dev/null)"
  bm_fin="$(yq -r ".\"$bm_task\".eval_fewshot.input // \"\"" "$MODES" 2>/dev/null)"
  bm_fout="$(yq -r ".\"$bm_task\".eval_fewshot.output // \"\"" "$MODES" 2>/dev/null)"
  if [ -z "$bm_sys" ] || [ -z "$bm_fin" ] || [ -z "$bm_fout" ]; then
    die "build-messages: task '$bm_task' missing eval_system/eval_fewshot in $MODES"
  fi
  jq -n --arg s "$bm_sys" --arg fin "$bm_fin" --arg fout "$bm_fout" --rawfile u "$bm_input" \
    '[{role:"system",content:$s},
      {role:"user",content:("Input:\n"+$fin)},
      {role:"assistant",content:$fout},
      {role:"user",content:("Input:\n"+$u)}]'
  exit 0
fi

task="" output="" golden="" derive=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --task)   task="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --golden) golden="$2"; shift 2 ;;
    --derive) derive="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done
if [ -z "$task" ] || [ -z "$output" ]; then die "usage: --task <t> --output <f> (--golden <f> | --derive <input>)"; fi
[ -f "$output" ] || { echo "score=0.000"; exit 0; }  # missing output = fail, not crash

mode="$(yq -r ".\"$task\".mode // \"\"" "$MODES" 2>/dev/null)"
[ -n "$mode" ] || die "task '$task' not in $MODES"

# Resolve the EXPECTED text: stored golden, or re-derived from input.
expected_file=""
if [ -n "$golden" ]; then
  [ -f "$golden" ] || { echo "score=0.000"; exit 0; }
  expected_file="$golden"
elif [ -n "$derive" ]; then
  derive_cmd="$(yq -r ".\"$task\".derive_cmd // \"\"" "$MODES" 2>/dev/null)"
  [ -n "$derive_cmd" ] || die "task '$task' has no derive_cmd for --derive"
  [ -f "$derive" ] || { echo "score=0.000"; exit 0; }
  tmp_exp="$(mktemp)"; trap 'rm -f "$tmp_exp"' EXIT
  # derive_cmd receives the input path as $1; its stdout is the expected output.
  if ! sh -c "$derive_cmd" _ "$derive" > "$tmp_exp" 2>/dev/null; then echo "score=0.000"; exit 0; fi
  expected_file="$tmp_exp"
else
  die "need --golden or --derive"
fi

norm() { tr '[:upper:]' '[:lower:]' < "$1" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; }

case "$mode" in
  exact)
    if cmp -s -- "$output" "$expected_file"; then echo "score=1.000"; else echo "score=0.000"; fi
    ;;
  normalized)
    if [ "$(norm "$output")" = "$(norm "$expected_file")" ]; then echo "score=1.000"; else echo "score=0.000"; fi
    ;;
  set-f1)
    # sets = unique non-empty trimmed lines. F1 = 2PR/(P+R).
    awk '
      function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
      NR==FNR { a=trim($0); if(a!="") A[a]=1; next }
      { b=trim($0); if(b!="") B[b]=1 }
      END {
        for(k in A) na++; for(k in B) nb++;
        for(k in A) if(k in B) inter++;
        if(na==0 && nb==0){ printf "score=1.000\n"; exit }
        if(na==0 || nb==0){ printf "score=0.000\n"; exit }
        p=inter/na; r=inter/nb;
        if(p+r==0){ printf "score=0.000\n"; exit }
        printf "score=%.3f\n", 2*p*r/(p+r);
      }' "$output" "$expected_file"
    ;;
  *) die "unknown mode '$mode' for task '$task'" ;;
esac
exit 0
