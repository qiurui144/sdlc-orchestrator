#!/usr/bin/env bash
# Hook: PreToolUse Bash — block committing/pushing secrets or loose-perm sensitive files (v0.21, SE13).
#
# Direct response to the 2026-06-04 §9.1 incident. Before `git commit` (scan staged) or `git push`
# (scan tracked + .git/config), run secret-scan/scan.sh; on a finding, exit 2 (block) — like
# ga-tag-guard. Honors SDLC_PROJECT_ROOT (v0.20). Escape hatch for a vetted false-positive:
# SDLC_SECRET_OVERRIDE=1 (or a per-repo .sdlc/secret-allow entry). Never prints the secret (§1.4).
# Exit: 0 = allow · 2 = block.
set -uo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
[ "$tool" = "Bash" ] || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

# Guard history-writing / upload commands. Over-match deliberately: `git` + commit/push ANYWHERE,
# so option insertion (`git -c x=y commit`, `git -C d commit`, `git --no-pager push`) can't evade
# (the dual-acceptance review's CRITICAL bypass). Over-matching only runs a harmless scan (which has
# an override); under-matching would let a secret through, so we bias to scanning.
case "$cmd" in *git*) ;; *) exit 0 ;; esac
mode=""
case "$cmd" in
  *commit*) mode="staged" ;;
  *push*)   mode="tracked" ;;
  *) exit 0 ;;
esac

[ "${SDLC_SECRET_OVERRIDE:-}" = "1" ] && exit 0   # vetted false-positive escape hatch

repo="${SDLC_PROJECT_ROOT:-$(pwd -P)}"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || exit 0   # not a git repo → no-op

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCAN="${CLAUDE_PLUGIN_ROOT:-$(cd "$HERE/.." && pwd -P)}/skills/secret-scan/scan.sh"
[ -f "$SCAN" ] || exit 0   # scanner missing → don't block (fail-open; deps/CI is the backstop)

if [ "$mode" = "staged" ]; then
  out=$(SDLC_PROJECT_ROOT="$repo" bash "$SCAN" --secrets --perms --staged 2>&1)
else
  out=$(SDLC_PROJECT_ROOT="$repo" bash "$SCAN" --secrets --perms 2>&1)
fi
rc=$?

[ "$rc" -ne 2 ] && exit 0   # CLEAN (0) or scanner error (other) → allow

{
  echo "🛑 secret-guard: refusing the $mode git operation — secret-scan found findings (§1.4 / §9.1):"
  printf '%s\n' "$out" | sed 's/^/   /'
  echo "   Fix the file(s) above (rotate any real secret — §9.1). If a false positive: add to"
  echo "   .sdlc/secret-allow, or re-run this command with SDLC_SECRET_OVERRIDE=1."
} >&2
exit 2
