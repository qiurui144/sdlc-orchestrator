#!/usr/bin/env bash
# risk-classify.sh — deterministic, zero-LLM change-risk classifier (v0.28.0, B keystone).
# Given a staged change, emits exactly one RISK TIER ∈ {LOW, NORMAL, HIGH}. Pure git/grep/awk —
# NEVER an LLM call. Default-deny: a change reaches LOW only by passing every guard; any
# unmatched / ambiguous / error / executable-file condition falls through to NORMAL or HIGH.
# bash 3.2-safe (no `declare -A`). SE16-safe (case / awk EOF / grep -c; no early-pipe-close on
# a pipefail pipe). LC_ALL=C pinned for determinism. Honors SDLC_PROJECT_ROOT (v0.20).
#
# rev2 fixes baked in: #1 LOW = non-executable content only; #2 self-guard incl. risk-rules.yaml +
# context-map.yaml; #3 .md fence scan is an allowlist (ANY fence → NORMAL); #4 path scan is RAW
# --name-status (NOT comment-stripped — do NOT reuse panel.sh `neg`); #6 LOW = positive basename allowlist.
#
# Usage: risk-classify.sh [--staged | --diff <file> | --names <file>] [--rules <yaml>] [--verbose]
#   stdout (single kv line):
#     risk_tier=LOW|NORMAL|HIGH reason=<kebab> path_depth=fast|full panel_size=3|5 model_class=mechanical|per-agent|judgment
#   exit: 0 = classified ok (any tier) · 2 = error/unparseable → caller MUST treat as HIGH (fail-safe)
set -uo pipefail
export LC_ALL=C

mode="staged" diff_file="" names_file="" rules=""
while [ "$#" -gt 0 ]; do case "$1" in
  --staged) mode="staged"; shift;;
  --diff) mode="diff"; diff_file="$2"; shift 2;;
  --names) mode="names"; names_file="$2"; shift 2;;
  --rules) rules="$2"; shift 2;;
  --verbose) shift;;   # accepted (forward-compat); classification is deterministic regardless
  *) echo "risk-bad-arg: $1" >&2; exit 2;;
esac; done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="${SDLC_PROJECT_ROOT:-$(pwd -P)}"
rules="${rules:-$HERE/../../config/risk-rules.yaml}"

emit() {  # $1=tier $2=reason  → kv line + exit 0
  local tier="$1" reason="$2" depth panel mclass
  case "$tier" in
    LOW)    depth=fast; panel=3; mclass=mechanical;;
    NORMAL) depth=full; panel=3; mclass=per-agent;;
    HIGH)   depth=full; panel=5; mclass=judgment;;
  esac
  echo "risk_tier=$tier reason=$reason path_depth=$depth panel_size=$panel model_class=$mclass"
  exit 0
}
fail_high() { echo "risk_tier=HIGH reason=$1 path_depth=full panel_size=5 model_class=judgment"; exit 0; }
# note: exit 2 reserved for truly-unusable input; a classified HIGH still exits 0 (it IS a classification).

# --- read rules; missing/unreadable rules → cannot prove LOW → HIGH (fail-safe) ---
[ -f "$rules" ] || fail_high risk-rules-missing
yaml_list() {  # $1=top-level key → patterns under it (lines starting with '  - '), pipe-joined
  awk -v k="$1:" '
    $0==k {ing=1; next}
    /^[a-zA-Z_]/ {ing=0}
    ing && /^[[:space:]]*-[[:space:]]/ {
      line=$0; sub(/^[[:space:]]*-[[:space:]]*/,"",line);
      sub(/[[:space:]]+#.*$/,"",line);       # strip inline " # comment" (patterns contain no #)
      gsub(/^['"'"'"]|['"'"'"]$/,"",line);   # strip surrounding quotes
      print line
    }' "$rules"
}
SELF=$(yaml_list self_guard | paste -sd'|' -)
HIGH=$(yaml_list high | paste -sd'|' -)
NORMAL=$(yaml_list normal | paste -sd'|' -)
LOWA=$(yaml_list low_allow | paste -sd'|' -)
[ -n "$LOWA" ] || fail_high risk-rules-empty

# --- get RAW --name-status (fix #4: raw, NOT comment-stripped) ---
ns=""
case "$mode" in
  names) [ -f "$names_file" ] || fail_high risk-names-missing; ns=$(cat "$names_file");;
  staged) ns=$(git -C "$root" diff --cached --name-status -M 2>/dev/null) || fail_high risk-git-error;;
  diff)  [ -f "$diff_file" ] || fail_high risk-diff-missing
         ns=$(git -C "$root" apply --numstat "$diff_file" 2>/dev/null | awk '{print "M\t"$3}') \
            || fail_high risk-unparseable-diff;;
esac

# empty-but-invoked → nothing to fast-path safely → NORMAL (spec §9 edge)
[ -n "$ns" ] || emit NORMAL empty-diff

# --- extract changed paths from RAW name-status (handle R/C rename rows = 3 cols) ---
# Rename/copy rows (status R### / C###) → NORMAL immediately (defeats rename-dodge; spec STEP 2).
have_rename=0; paths=""
while IFS= read -r row; do
  [ -n "$row" ] || continue
  status=$(printf '%s' "$row" | awk '{print $1}')
  case "$status" in
    R*|C*) have_rename=1
           # both old+new paths count for scanning
           p=$(printf '%s' "$row" | awk '{print $2"\n"$3}');;
    *)     p=$(printf '%s' "$row" | awk '{print $2}');;
  esac
  paths="$paths
$p"
done <<EOF
$ns
EOF

scan() {  # $1=pattern-set ; returns 0 if ANY path matches (grep -c reads to EOF, SE16-safe)
  [ -n "$1" ] || return 1
  local n; n=$(printf '%s\n' "$paths" | grep -cE "$1" 2>/dev/null) || n=0
  [ "${n:-0}" -gt 0 ]
}

# STEP 0 — self-referential guard → HIGH (meta-constraint §2.4 / fix #2). Authoritative.
scan "$SELF" && emit HIGH self-referential

# STEP 1 — HIGH path triggers → HIGH. Authoritative (body scan is advisory; never demotes).
scan "$HIGH" && emit HIGH high-risk-path

# STEP 2 — rename/copy → NORMAL (defeats rename-dodge).
[ "$have_rename" -eq 1 ] && emit NORMAL rename-detected

# STEP 2 — NORMAL triggers (source/test/command-bearing config — fix #1 value-only counts) → NORMAL.
scan "$NORMAL" && emit NORMAL logic-or-config-touched

# STEP 3 — LOW positive basename allowlist (fix #1/#6). EVERY path's BASENAME must match low_allow,
# else fall through to NORMAL (a single non-allowlisted path makes the whole change NON-LOW).
non_low=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  base=$(basename -- "$p")
  case "$base" in
    *) printf '%s\n' "$base" | grep -qE "$LOWA" || non_low=1;;
  esac
done <<EOF
$(printf '%s\n' "$paths")
EOF
[ "$non_low" -eq 1 ] && emit NORMAL non-allowlisted-path

# STEP 3a — .md fence guard (ALLOWLIST, fix #3): ANY fenced code block in a .md diff → NORMAL.
# awk fence state machine reads to EOF (SE16). Only fence-free prose stays LOW.
if [ "$mode" = "staged" ] || [ "$mode" = "diff" ]; then
  body=""
  case "$mode" in
    staged) body=$(git -C "$root" diff -U0 --cached -- '*.md' 2>/dev/null);;
    diff)   body=$(grep -E '^\+' "$diff_file" 2>/dev/null || true);;
  esac
  if printf '%s\n' "$body" | awk '
      /^[+].*(```|~~~)/ {found=1}
      END{exit !found}'; then
    emit NORMAL md-code-fence
  fi
fi

# All guards passed → LOW (the only fast-path-eligible class).
emit LOW non-executable-content
