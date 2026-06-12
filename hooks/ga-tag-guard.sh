#!/usr/bin/env bash
# Hook: PreToolUse Bash — harness-enforced §7.2 GA hard-stop (v0.18).
#
# Why this exists: the Challenger-Panel "GA tag is a human hard-stop" rule lived only in agent
# prompts — an LLM could skip it (the v0.17 competitive review flagged this as the #1 weakness:
# gates were prompt-codified, not harness-enforced). This converts the single most irreversible
# action — creating a MAJOR GA tag (vN.0.0, no pre-release suffix) — into a harness invariant:
# exit 2 BLOCKS it unless a human approval marker is present. Deliberately narrow + non-invasive:
#   • only major GA tags (vN.0.0); pre-1.0 minors (v0.18.0), patches (v0.17.1), and pre-release
#     tags (v1.0.0-rc.1) pass freely — they are not the §7.2 hard-stop.
#   • only when the repo uses sdlc's gated flow (a sprint-state file exists); otherwise no-op, so a
#     normal repo that merely has the plugin installed is never blocked from tagging.
#   • the human escape is explicit + cheap: SDLC_GA_APPROVED=1, or `touch .sdlc/ga-approved`.
# Exit codes: 0 = allow, 2 = block.
set -uo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
[ "$tool" = "Bash" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

# Require both 'git' and 'tag' ANYWHERE (two globs) — option insertion (`git -C d tag`,
# `git --no-pager tag`, `git -c x=y tag`, newline-split `git\n tag`) can't evade the way the old
# literal "git tag" substring could (F1, the dual-acceptance bypass; mirrors secret-guard). Over-match
# is safe: the vN.0.0 regex below still gates creation, and a non-creation command at worst gets a
# fail-SAFE false block, never a bypass.
case "$cmd" in *git*) ;; *) exit 0 ;; esac
case "$cmd" in *tag*) ;; *) exit 0 ;; esac
# Tag deletes/lists are not a GA commitment → allow. (If option insertion defeats these the result is
# a false BLOCK on a delete — fail-safe, not a bypass.)
case "$cmd" in
  *"tag -d"*|*"tag --delete"*|*"tag -l"*|*"tag --list"*|*"tag -n"*) exit 0 ;;
esac

# Major GA = vN.0.0 with no pre-release suffix. The trailing class excludes '-' (suffix), extra
# digits and '.', so v1.0.0-rc.1 / v0.18.0 / v0.10.0 / v0.17.1 do NOT match. bash 3.2 =~ (no pipe).
if [[ "$cmd" =~ (^|[^.0-9])(v?[0-9]+\.0\.0)($|[^.0-9-]) ]]; then
  ver="${BASH_REMATCH[2]}"
else
  exit 0
fi

# Scope to sdlc-gated repos only — no sprint state ⇒ not using the gated flow ⇒ no-op.
# Honor SDLC_PROJECT_ROOT so the guard protects the TARGET project when Claude runs from a parent dir (v0.20).
repo="${SDLC_PROJECT_ROOT:-$(pwd -P)}"
gated=no
for marker in "$repo"/.sdlc/state.json "$repo"/docs/superpowers/handoffs/*_state.yaml; do
  if [ -e "$marker" ]; then gated=yes; break; fi
done
[ "$gated" = yes ] || exit 0

# Human approval markers (§7.2 hard-stop release).
if [ "${SDLC_GA_APPROVED:-}" = "1" ] || [ -f "$repo/.sdlc/ga-approved" ]; then
  exit 0
fi

{
  echo "🛑 ga-tag-guard: '$ver' is a MAJOR GA tag — a human hard-stop (CLAUDE.md §7.2, irreversible once pushed)."
  echo "   Confirm first: RC 4 gates passed + 本机部署验证 (§7.3) + north-star acceptance run."
  echo "   To proceed, re-run with SDLC_GA_APPROVED=1, or: touch .sdlc/ga-approved"
} >&2
exit 2
