#!/usr/bin/env bash
# tests/fixtures/gh-stub.sh — offline `gh` mock for ci-status / remediator tests.
# Dispatches on the gh SUBCOMMAND ($1 $2) + env vars; NEVER hits real GitHub (Hard constraint #4).
# Env knobs: STUB_CONCLUSION (success|failure|cancelled|timed_out), STUB_STATUS (completed|in_progress),
#            STUB_EMPTY=1 (no runs), STUB_EOF=1 (partial+exit 1), STUB_MALFORMED=1,
#            STUB_LOG (deny-license|deny-advisory|deny-both|test-b4|fmt|unknown).
# C1 ref-binding knobs:
#            STUB_COMMIT (the SHA the run(s) belong to) — when `run list -c <SHA>` is queried,
#            the stub returns the run set ONLY if <SHA> matches STUB_COMMIT, else `[]` (empty),
#            faithfully modelling `gh run list -c <SHA>` filtering runs to that commit. When the
#            caller passes NO -c filter, the stub returns the set regardless (repo-wide, legacy).
#            STUB_BRANCH (the branch the run(s) belong to) — same filtering for `--branch <name>`.
# C2 reduce-over-all knob:
#            STUB_CHECKS — a ';'-separated list of "conclusion[:status]" entries, e.g.
#            "success;failure" or "success:completed;:in_progress". When set it OVERRIDES the
#            single-element default and emits a multi-element array so reduce-over-all is exercised.
set -u
sub="${1:-}"; subsub="${2:-}"

if [ "${STUB_EOF:-0}" = "1" ]; then printf '{"conclusion":'; exit 1; fi
if [ "${STUB_MALFORMED:-0}" = "1" ]; then printf '{"conclusion":"succ'; exit 0; fi

# Parse a -c/--commit/--branch filter out of the remaining args (C1).
want_commit=""; want_branch=""; have_commit_filter=0; have_branch_filter=0
shift 2 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--commit) want_commit="${2:-}"; have_commit_filter=1; shift 2 ;;
    -b|--branch) want_branch="${2:-}"; have_branch_filter=1; shift 2 ;;
    *) shift ;;
  esac
done

emit_array() { # emit the run/check array honoring STUB_CHECKS (multi) or the single default
  if [ -n "${STUB_CHECKS:-}" ]; then
    printf '['
    first=1
    OLDIFS="$IFS"; IFS=';'
    for entry in $STUB_CHECKS; do
      IFS="$OLDIFS"
      cc="${entry%%:*}"; st="${entry#*:}"
      [ "$st" = "$entry" ] && st="completed"   # no ':' → default completed
      [ -z "$st" ] && st="completed"
      [ "$first" = 1 ] || printf ','
      printf '{"conclusion":"%s","status":"%s","databaseId":12345678,"url":"https://github.com/o/r/actions/runs/12345678"}' "$cc" "$st"
      first=0
      IFS=';'
    done
    IFS="$OLDIFS"
    printf ']\n'
    return
  fi
  st="${STUB_STATUS:-completed}"; cc="${STUB_CONCLUSION:-success}"
  printf '[{"conclusion":"%s","status":"%s","databaseId":12345678,"url":"https://github.com/o/r/actions/runs/12345678"}]\n' "$cc" "$st"
}

case "$sub $subsub" in
  "run list"|"pr checks")
    if [ "${STUB_EMPTY:-0}" = "1" ]; then printf '[]\n'; exit 0; fi
    # C1: if a commit/branch filter is requested AND the stub is told which commit/branch the
    # runs belong to, return EMPTY when they don't match (this is what real `gh run list -c` does).
    if [ "$have_commit_filter" = 1 ] && [ -n "${STUB_COMMIT:-}" ] && [ "$want_commit" != "${STUB_COMMIT}" ]; then
      printf '[]\n'; exit 0
    fi
    if [ "$have_branch_filter" = 1 ] && [ -n "${STUB_BRANCH:-}" ] && [ "$want_branch" != "${STUB_BRANCH}" ]; then
      printf '[]\n'; exit 0
    fi
    emit_array
    ;;
  "run view")
    case "${STUB_LOG:-fmt}" in
      deny-license) printf 'error[licenses]: MIT OR Apache-2.0 not in allow list\n' ;;
      deny-advisory) printf 'error[advisories]: RUSTSEC-2024-0001 vulnerable\n' ;;
      deny-both) printf 'error[licenses]: not in allow\nerror[advisories]: RUSTSEC-2024-0001\n' ;;
      test-b4) printf 'error[E0599]: AppError refactor; test tangled\ntest result: FAILED\n' ;;
      fmt) printf 'Diff in src/foo.rs at line 3:\n cargo fmt --check failed\n' ;;
      *) printf 'some unrecognized failure output\n' ;;
    esac
    ;;
  *) printf 'gh-stub: unhandled subcommand: %s %s\n' "$sub" "$subsub" >&2; exit 2 ;;
esac
