#!/usr/bin/env bash
# skills/ci-status/ci-status.sh — E1 deterministic CI verdict (zero-LLM, SE16-safe).
# Contract: spec §5. Exit 0=PASS 1=FAIL 3=IN_PROGRESS 4=UNKNOWN 5=NONE 2=usage.
set -u
GH="${SDLC_GH_BIN:-gh}"

# B2 deterministic license-vs-advisory pre-gate (runs BEFORE any LLM, spec §5).
# advisory/RUSTSEC always wins → ESCALATE-security (never auto-fixable); license-only is
# the sole A3-eligible class; everything else is deferred to the LLM classifier.
# W4 (G3): the match is CASE-INSENSITIVE (cargo-deny output is usually lowercase but an
# uppercase ADVISORIES log must not slip a security failure to the LLM), and an EMPTY/missing
# failing-log fails SAFE to ESCALATE — a missing log means we cannot prove it is benign.
if [ "${1:-}" = "deny-classify" ]; then
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    echo "ESCALATE-security"; echo "(empty/missing failing log — fail-safe ESCALATE, cannot classify)" >&2; exit 10
  fi
  log_text="$2"
  # lowercase for case-insensitive matching (tr is POSIX; SE16-safe — no early-close pipe)
  log_lc="$(printf '%s' "$log_text" | tr '[:upper:]' '[:lower:]')"
  case "$log_lc" in
    *advisories*|*rustsec-*) echo "ESCALATE-security"; exit 10 ;;
    *licenses*)              echo "A3-eligible";        exit 0  ;;
    *)                       echo "DEFER-LLM";          exit 0  ;;
  esac
fi

REF=""; PR=""; JSON=0; REQUIRE_KNOWN=0; ALLOW_UNKNOWN=0
[ "${SDLC_CI_STRICT:-0}" = "1" ] && REQUIRE_KNOWN=1
[ "${SDLC_CI_LAX:-0}" = "1" ] && ALLOW_UNKNOWN=1
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --repo) shift 2 ;;
    --json) JSON=1; shift ;;
    --require-known) REQUIRE_KNOWN=1; shift ;;
    --allow-unknown) ALLOW_UNKNOWN=1; shift ;;
    --poll|--max-wait|--gh-bin) shift 2 ;;
    *) echo "ci-status: usage: bad arg $1" >&2; exit 2 ;;
  esac
done
[ -z "$REF" ] && REF="$(git rev-parse HEAD 2>/dev/null || echo HEAD)"

# C1: resolve REF to a concrete SHA so the verdict is BOUND to the commit, never to a
# repo-wide latest run. `git rev-parse` resolves a SHA / branch / tag to its commit object;
# an unresolvable ref stays as-is (gh will return no matching run → verdict NONE, never PASS).
SHA="$(git rev-parse --verify "$REF^{commit}" 2>/dev/null || git rev-parse --verify "$REF" 2>/dev/null || printf '%s' "$REF")"

emit() { # $1 verdict $2 exit $3 extra
  if [ "$JSON" = "1" ]; then
    printf '{"verdict":"%s","ref":"%s","sha":"%s","run_id":"%s","url":"%s","conclusion":"%s"}\n' \
      "$1" "$REF" "$SHA" "${RUN_ID:-}" "${RUN_URL:-}" "${CONCL:-}"
  else
    printf 'ci-status: %s  ref=%s %s\n' "$1" "$REF" "$3"
  fi
}

# C1: bind the query to the commit. `gh pr checks` is already PR-scoped (checks of the PR
# head). `gh run list -c <SHA>` filters runs to that exact commit — so a green run on any
# OTHER branch/commit is NOT returned, and an unrelated-latest run can never mask the target.
if [ -n "$PR" ]; then RAW="$("$GH" pr checks --json conclusion,status,databaseId,url 2>/dev/null)"; GHX=$?
else RAW="$("$GH" run list -c "$SHA" --json conclusion,status,databaseId,url 2>/dev/null)"; GHX=$?; fi

# gh missing / non-zero / EOF / unparseable → UNKNOWN
if [ "$GHX" -ne 0 ] || [ -z "$RAW" ] || ! printf '%s' "$RAW" | jq -e . >/dev/null 2>&1; then
  if [ "$REQUIRE_KNOWN" = "1" ] && [ "$ALLOW_UNKNOWN" != "1" ]; then
    emit UNKNOWN 4 "(gh unavailable or API EOF) — irreversible gate: treated as BLOCK; retry or --allow-unknown"
  else
    emit UNKNOWN 4 "(gh unavailable or API EOF) — treated as WARN; use --require-known to block"
  fi
  exit 4
fi

LEN="$(printf '%s' "$RAW" | jq 'length')"
if [ "$LEN" = "0" ]; then
  # C1: no run is bound to THIS commit. Never fall through to a repo-wide latest run.
  # Under --require-known (irreversible gate) an unverifiable commit must BLOCK, not skip.
  if [ "$REQUIRE_KNOWN" = "1" ] && [ "$ALLOW_UNKNOWN" != "1" ]; then
    emit UNKNOWN 4 "(no CI run bound to this commit) — irreversible gate: treated as BLOCK; retry or --allow-unknown"
    exit 4
  fi
  emit NONE 5 "(no CI runs for this commit — skip, not a failure)"; exit 5
fi

# C2: reduce over ALL checks/runs, not just .[0]. A single green check ahead of a red one
# must NOT read green. Precedence: any failure-class → FAIL; else any not-completed/pending
# → IN_PROGRESS; else any unrecognized conclusion → UNKNOWN; else (all success/skipped/
# neutral) → PASS. The run id/url reported is the first failing (or first pending) element.
AGG="$(printf '%s' "$RAW" | jq -r '
  def cls(c;s):
    if (s != "completed" and s != "" and s != null) then "in_progress"
    elif (c == "failure" or c == "timed_out" or c == "cancelled"
          or c == "startup_failure" or c == "action_required") then "failure"
    elif (c == "success" or c == "skipped" or c == "neutral") then "success"
    else "unknown" end;
  [ .[] | . + {cls: cls(.conclusion; .status)} ] as $all
  | ([ $all[] | select(.cls=="failure") ]) as $f
  | ([ $all[] | select(.cls=="in_progress") ]) as $p
  | ([ $all[] | select(.cls=="unknown") ]) as $u
  | (if ($f|length)>0 then $f[0] | "failure\t\(.databaseId)\t\(.url)\t\(.conclusion)"
     elif ($p|length)>0 then $p[0] | "in_progress\t\(.databaseId)\t\(.url)\t\(.conclusion)"
     elif ($u|length)>0 then $u[0] | "unknown\t\(.databaseId)\t\(.url)\t\(.conclusion)"
     else .[0] | "success\t\(.databaseId)\t\(.url)\t\(.conclusion)" end)
' 2>/dev/null)"

VERDICT_CLS="${AGG%%	*}"; rest="${AGG#*	}"
RUN_ID="${rest%%	*}"; rest="${rest#*	}"
RUN_URL="${rest%%	*}"; CONCL="${rest##*	}"

case "$VERDICT_CLS" in
  failure)     emit FAIL 1 "run=$RUN_ID $RUN_URL"; exit 1 ;;
  in_progress) emit IN_PROGRESS 3 "run=$RUN_ID $RUN_URL"; exit 3 ;;
  success)     emit PASS 0 "run=$RUN_ID"; exit 0 ;;
  *)           emit UNKNOWN 4 "(unrecognized conclusion) — WARN"; exit 4 ;;
esac
