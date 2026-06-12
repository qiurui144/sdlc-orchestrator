#!/usr/bin/env bash
# scan.sh — deterministic secret + file-permission scanner (v0.21, SE13 owner).
#
# Direct response to the 2026-06-04 §9.1 incident (a `gho_` token sat plaintext in .git/config and
# the plugin couldn't detect it). First-line REGEX secret detection + sensitive-file PERMISSION check.
# Zero-LLM. **NEVER prints the matched secret value** — only `file:line: kind` (§1.4). SE16-safe
# (grep -c / cut, no early-closing pipe). Honors SDLC_PROJECT_ROOT (v0.20). Reused by
# hooks/secret-guard.sh + dependency-auditor + /sdlc:intake. NOT a trufflehog replacement — for depth
# recommend trufflehog/gitleaks in CI (§1.4); this is fast defense-in-depth, not a guarantee.
#
# Usage: scan.sh [--secrets] [--perms] [--staged] [--fix] [--include-ssh] [--root <dir>] [<path>...]
#   exit 0 = CLEAN · 2 = findings (or usage error)
set -uo pipefail

do_secrets=0 do_perms=0 staged=0 fix=0 include_ssh=0 root=""; paths=()
while [ "$#" -gt 0 ]; do case "$1" in
  --secrets) do_secrets=1; shift;;
  --perms) do_perms=1; shift;;
  --staged) staged=1; shift;;
  --fix) fix=1; shift;;
  --include-ssh) include_ssh=1; shift;;
  --root) root="$2"; shift 2;;
  --*) echo "scan-bad-arg: $1" >&2; exit 2;;
  *) paths+=("$1"); shift;;
esac; done
[ "$do_secrets" -eq 0 ] && [ "$do_perms" -eq 0 ] && { do_secrets=1; do_perms=1; }  # default both
root="${root:-${SDLC_PROJECT_ROOT:-$(pwd -P)}}"
root="$(cd "$root" 2>/dev/null && pwd -P)" || { echo "scan-no-root: $root" >&2; exit 2; }
is_git=0; git -C "$root" rev-parse --git-dir >/dev/null 2>&1 && is_git=1

# Allowlist = §1.4 placeholders (so fixtures/examples never self-trip) + per-repo .sdlc/secret-allow.
# Built-in placeholders — matched against the MATCHED TOKEN only (never the whole line: a real token
# sharing a line with ${VAR}/<x> must still be flagged — the dual-acceptance BLOCK-1). Broad words
# like "example" are deliberately EXCLUDED (they'd suppress real secrets).
ALLOW='your-key-here|test-pass-not-real|fake_key_for_test|changeme|redacted|xxxxxxxx|\$\{|\$[A-Z_]+|<[A-Za-z0-9_]+>|pk_test_'
# Per-repo allowlist — an EXPLICIT vetted override; matched against the token OR the file path (so a
# user can allow a known-fake token value or a whole fixtures/ path). Not line-content (that re-opens BLOCK-1).
REPO_ALLOW=""
if [ -f "$root/.sdlc/secret-allow" ]; then
  REPO_ALLOW=$(awk 'NF && $0 !~ /^#/' "$root/.sdlc/secret-allow" 2>/dev/null | paste -sd'|' -)
fi
allowed() {  # $1 = string to test; allowed if it matches a built-in placeholder or a per-repo entry
  printf '%s' "$1" | grep -qiE -- "$ALLOW" && return 0
  [ -n "$REPO_ALLOW" ] && printf '%s' "$1" | grep -qiE -- "$REPO_ALLOW" && return 0
  return 1
}

findings=0
report() { echo "  $1" >&2; findings=$((findings+1)); }

# file list: explicit paths > --staged (git diff --cached) > all tracked (git ls-files)
files=()
if [ "${#paths[@]}" -gt 0 ]; then
  files=("${paths[@]}")
elif [ "$staged" -eq 1 ] && [ "$is_git" -eq 1 ]; then
  while IFS= read -r f; do [ -n "$f" ] && files+=("$root/$f"); done \
    < <(git -C "$root" diff --cached --name-only --diff-filter=ACM 2>/dev/null)
elif [ "$is_git" -eq 1 ]; then
  while IFS= read -r f; do [ -n "$f" ] && files+=("$root/$f"); done < <(git -C "$root" ls-files 2>/dev/null)
fi

# ---- (A) secrets ----
if [ "$do_secrets" -eq 1 ]; then
  # kind|regex — high-confidence + full-length so truncated doc mentions ("gho_…") do NOT match.
  patterns='github-token|gh[opsu]_[A-Za-z0-9]{36,}
github-pat|github_pat_[A-Za-z0-9_]{40,}
private-key|-----BEGIN [A-Z ]*PRIVATE KEY-----
aws-access-key|AKIA[0-9A-Z]{16}
embedded-cred|https://[A-Za-z0-9._~%+-]+:[^@/]{3,}@'
  targets=(); [ "${#files[@]}" -gt 0 ] && targets=("${files[@]}")   # bash-3.2-safe (empty array + set -u)
  [ "$is_git" -eq 1 ] && [ -f "$root/.git/config" ] && targets+=("$root/.git/config")   # the incident class
  for f in ${targets[@]+"${targets[@]}"}; do
    [ -f "$f" ] || continue
    LC_ALL=C grep -qI . "$f" 2>/dev/null || continue   # skip binary/empty
    rel="${f#"$root"/}"; [ "$f" = "$root/.git/config" ] && rel=".git/config"
    [ -n "$REPO_ALLOW" ] && printf '%s' "$rel" | grep -qiE -- "$REPO_ALLOW" && continue   # per-repo path allow → skip file
    while IFS='|' read -r kind re; do
      [ -n "$re" ] || continue
      # TOKEN-level allowlist (NOT line-level): suppress only when the MATCHED secret is itself a
      # placeholder — else a real token on a line that merely mentions ${VAR}/<x> would be missed
      # (the dual-acceptance review's CRITICAL bypass). `grep -noE` → lineno:match; the value is used
      # only for the allow test and never printed (§1.4); printf is single-line so no SIGPIPE (SE16).
      while IFS=: read -r ln match; do
        [ -n "$ln" ] || continue
        allowed "$match" && continue
        report "$rel:$ln: $kind"
      done < <(grep -noE -- "$re" "$f" 2>/dev/null)
    done <<EOF
$patterns
EOF
  done
fi

# ---- (B) permissions ----
if [ "$do_perms" -eq 1 ]; then
  SENS='\.(pem|key|p12|pfx|keystore|env)$|(^|/)\.env|(^|/)secrets?/|(^|/)id_(rsa|ed25519|ecdsa|dsa)$|(^|/)\.netrc$'
  ptargets=(); [ "${#files[@]}" -gt 0 ] && ptargets=("${files[@]}")   # bash-3.2-safe (empty array + set -u)
  if [ "$include_ssh" -eq 1 ] && [ -d "$HOME/.ssh" ]; then
    while IFS= read -r f; do ptargets+=("$f"); done \
      < <(find "$HOME/.ssh" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' 2>/dev/null)
  fi
  for f in ${ptargets[@]+"${ptargets[@]}"}; do
    [ -f "$f" ] || continue
    case "$f" in *.pub) continue;; esac
    rel="${f#"$root"/}"
    printf '%s\n' "$rel" | grep -qE "$SENS" || continue
    mode=$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null)
    m=${mode#"${mode%???}"}; g=${m:1:1}; o=${m:2:1}   # last 3 octal digits (handles 4-digit setuid/sticky → no false-neg)
    if [ "${g:-0}" != 0 ] || [ "${o:-0}" != 0 ]; then
      if [ "$fix" -eq 1 ]; then chmod 600 "$f" && echo "  fixed 0600: $rel" >&2
      else report "$rel: loose-perm:$mode (want 600)"; fi
    fi
  done
fi

if [ "$findings" -eq 0 ]; then echo "secret-scan: CLEAN"; exit 0; fi
echo "secret-scan: $findings finding(s) — values withheld (§1.4)" >&2
exit 2
