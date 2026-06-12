#!/usr/bin/env bash
# skills/ci-status/diff-guard.sh — component 4, B1 zero-LLM post-fix safety guard.
# Audits the ACTUAL `git diff --cached`. REJECT (exit 1) if the diff weakens tests or
# escapes the fix-class footprint. Caller MUST `git reset --hard` + ESCALATE on exit 1.
# SE16-safe: name-only + case/awk, no `| grep -q` control flow. Contract: spec §5.
#
# C3/C4 REDESIGN (G3 remediation): the assert-COUNT heuristic was removed entirely — it was
# defeated by neutering / comment-noise / bracket-inflation and was Rust-only. The guard's
# safety is now an INVARIANT, not a count:
#   A1 (fmt) = WHITESPACE-ONLY invariant: REJECT unless `git diff --cached --ignore-all-space`
#              shows NO change (the staged diff is purely whitespace/formatting). A neutered
#              assert is a non-whitespace change → REJECTed. Tamper-proof by construction.
#   A2 (lint-autofix) is DROPPED from the auto-fix allowlist — its semantic changes cannot be
#              safely guarded without full tool-reproducibility; lint failures escalate to human.
#   A3 (deny-license) / A4 (doc-sync) keep their footprint restrictions.
# Test-file detection (path + content markers) and skip/ignore markers are broadened across
# ecosystems (Go / Python / Java / JS / C# / Rust) and apply to EVERY class.
set -u
CLASS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --class) CLASS="${2:-}"; shift 2 ;;
    --staged) shift ;;
    *) echo "diff-guard: usage: bad arg $1" >&2; exit 2 ;;
  esac
done
# A2 is intentionally NOT accepted — lint-autofix is no longer an auto-fix class (C3).
case "$CLASS" in A1|A3|A4) ;; *) echo "diff-guard: usage: --class must be A1|A3|A4 (A2 dropped — lint escalates to human)" >&2; exit 2 ;; esac

FILES="$(git diff --cached --name-only)"
ADDED="$(git diff --cached -U0 | awk '/^\+[^+]/')"
reject() { echo "diff-guard: REJECT ($1) — caller must git reset --hard + ESCALATE" >&2; exit 1; }

# ---------------------------------------------------------------------------
# rule (1): touches a test FILE — path patterns OR content markers (C4: all ecosystems).
# Applies to ALL classes. Any staged file matching → REJECT.
# ---------------------------------------------------------------------------
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    # path patterns: Rust/generic, JS/TS, Go, Python, Java, C#, bats.
    # NB: `*_test.*` already covers Go's `*_test.go`; the extra patterns add what it misses.
    */tests/*|tests/*|*_test.*|test_*.*|*.test.*|*.spec.*|*.bats \
    |*.t.ts|*.t.tsx|*.t.js|conftest.py \
    |*Test.java|*Tests.java|*Test.cs|*Tests.cs|*Spec.scala)
      reject "touches test path: $f" ;;
  esac
  # content markers: any staged file whose CURRENT content carries a per-language test signature.
  # Rust #[test]/#[cfg(test)]; Go func Test/func Benchmark; Python def test_/class Test;
  # Java @Test/@ParameterizedTest; JS it(/describe(/test(.
  if git show ":$f" 2>/dev/null | awk '
      /#\[test\]|#\[cfg\(test\)\]/                                 {f=1}
      /func[ \t]+Test|func[ \t]+Benchmark/                         {f=1}
      /def[ \t]+test_|class[ \t]+Test/                             {f=1}
      /@Test|@ParameterizedTest/                                   {f=1}
      /(^|[^a-zA-Z])(it|describe|test)\(/                          {f=1}
      END{exit f?0:1}'; then
    reject "touches a file carrying test markers: $f"
  fi
done <<EOF
$FILES
EOF

# ---------------------------------------------------------------------------
# rule (2): added lines net-ADD a skip/ignore marker (W1: broadened). Applies to ALL classes.
# ---------------------------------------------------------------------------
if printf '%s\n' "$ADDED" | awk '
    /#\[ignore\]|#\[cfg\(ignore\)\]/                {f=1}
    /\.skip\(|\.only\(|it\.skip|describe\.skip/     {f=1}
    /xit\(|fit\(|fdescribe\(/                       {f=1}
    /xfail|\.xfail/                                 {f=1}
    /@pytest\.mark\.skip|pytest\.skip\(|@unittest\.skip/ {f=1}
    /t\.Skip\(|t\.Skipf\(/                          {f=1}
    /@Disabled|@Ignore/                             {f=1}
    /\/\/[ \t]*nolint/                              {f=1}
    END{exit f?0:1}'; then
  reject "adds skip/ignore marker"
fi

# ---------------------------------------------------------------------------
# rule (3): touches CI yaml (R8 — never auto-edit CI yaml). Applies to ALL classes.
# ---------------------------------------------------------------------------
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in .github/workflows/*) reject "touches CI yaml: $f (R8)" ;; esac
done <<EOF
$FILES
EOF

# ---------------------------------------------------------------------------
# rule (4): footprint per class.
#   A1 = WHITESPACE-ONLY invariant (C3): the staged diff must collapse to NO change once
#        whitespace is ignored. A formatter never alters non-whitespace tokens; any non-ws
#        change (neuter / comment-noise / bracket-inflate / logic-gut) → REJECT.
#        (A1 also keeps the doc/deny.toml exclusions — a formatter never touches those.)
#   A3 = deny.toml ONLY, [licenses].allow append only.
#   A4 = docs (*.md) only.
# ---------------------------------------------------------------------------
case "$CLASS" in
  A1)
    # doc / deny.toml exclusion (a formatter never edits these)
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      case "$f" in
        *.md)     reject "A1 footprint: doc edit not allowed: $f" ;;
        deny.toml) reject "A1 footprint: deny.toml not allowed: $f" ;;
      esac
    done <<EOF
$FILES
EOF
    # whitespace-only invariant (tamper-proof, reflow-aware): for every staged file, compare
    # the OLD (HEAD) and NEW (staged) content with ALL whitespace (incl. newlines) stripped.
    # If the non-whitespace token streams are identical, the change is pure formatting (a real
    # `cargo fmt`/`prettier` may split/join lines — `git diff --ignore-all-space` alone cannot
    # collapse a line-split, so we compare stripped blobs directly). ANY difference in the
    # stripped stream = a real token changed → neuter/comment-noise/bracket-inflate/logic-gut
    # all caught → REJECT. New/deleted files have no whitespace-only equivalent → REJECT.
    strip_ws() { awk '{ gsub(/[ \t\r\n]/, "") } { printf "%s", $0 }'; }
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      old_ws="$(git show "HEAD:$f" 2>/dev/null | strip_ws)"; ohx=$?
      new_ws="$(git show ":$f" 2>/dev/null | strip_ws)"; nhx=$?
      if [ "$ohx" -ne 0 ] || [ "$nhx" -ne 0 ]; then
        reject "A1 not whitespace-only: $f is added/removed (a formatter only reflows existing files)"
      fi
      if [ "$old_ws" != "$new_ws" ]; then
        reject "A1 not whitespace-only: $f alters non-whitespace tokens (formatter never deletes/changes code)"
      fi
    done <<EOF
$FILES
EOF
    ;;
  A3)
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      case "$f" in deny.toml) ;; *) reject "A3 footprint: only deny.toml allowed, got $f" ;; esac
    done <<EOF
$FILES
EOF
    # A3 must only append [licenses].allow, never [advisories]/[bans]
    if printf '%s\n' "$ADDED" | awk '/\[advisories\]|\[bans\]|advisories\.ignore/{f=1} END{exit f?0:1}'; then
      reject "A3 footprint: must append [licenses].allow only, not [advisories]/[bans]"
    fi
    ;;
  A4)
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      case "$f" in *.md) ;; *) reject "A4 footprint: only docs (*.md) allowed, got $f" ;; esac
    done <<EOF
$FILES
EOF
    ;;
esac

echo "diff-guard: PASS (class=$CLASS, within footprint, weakens nothing)"
exit 0
