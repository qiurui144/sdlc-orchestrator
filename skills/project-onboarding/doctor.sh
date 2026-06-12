#!/usr/bin/env bash
# doctor.sh — health-check a repo's sdlc-orchestrator wiring. Deterministic, zero-LLM.
# Usage: doctor.sh [<repo-root>]   (default cwd)
#   exit 0 = READY (no FAIL; WARNs allowed)
#   exit 1 = >=1 FAIL
# NOTE: set -u/-o pipefail but NOT -e — checks must continue past individual failures.
# POSIX / bash-3.2-safe per tests/PORTABILITY.md.
set -uo pipefail

# Target project root: positional arg > SDLC_PROJECT_ROOT > cwd (run from a parent dir — v0.20).
repo_in="${1:-${SDLC_PROJECT_ROOT:-$(pwd)}}"
repo="$(cd "$repo_in" 2>/dev/null && pwd -P)" || { echo "doctor: no such dir: $repo_in" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd -P)"
PLUGIN_ROOT="$(cd "$HERE/../.." && pwd -P)"

fails=0
pass() { echo "[$1] PASS: $2"; }
warn() { echo "[$1] WARN: $2"; }
fail() { echo "[$1] FAIL: $2"; fails=$((fails+1)); }

# manifest loadable
if [ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ] && jq -e . "$PLUGIN_ROOT/.claude-plugin/plugin.json" >/dev/null 2>&1; then
  pass manifest "plugin manifest valid at .claude-plugin/plugin.json"
else
  fail manifest "plugin manifest missing/invalid — see docs/INSTALL.md"
fi

# tools: git required; yq/jq/bats recommended
if command -v git >/dev/null 2>&1; then pass tools "git present"; else fail tools "git missing (required)"; fi
for t in yq jq bats; do
  command -v "$t" >/dev/null 2>&1 || warn tools "$t missing (recommended — see docs/INSTALL.md)"
done

# target is a git repo
if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  pass git "target is a git repo"
else
  fail git "$repo is not a git repo — run 'git init'"
fi

# stack detected + adapter present (in plugin) + materialized in-repo (agents read repo-relative)
stack="$("$PLUGIN_ROOT/config/detect-stack.sh" "$repo" 2>/dev/null || echo generic)"
if [ -f "$PLUGIN_ROOT/config/stack-$stack.yaml" ]; then
  if [ -f "$repo/.sdlc/stack.yaml" ]; then
    pass stack "detected $stack (adapter materialized at .sdlc/stack.yaml)"
  else
    warn stack "detected $stack but .sdlc/stack.yaml not materialized — re-run /sdlc:onboard (agents read it repo-relative)"
  fi
else
  warn stack "detected $stack but no adapter yaml — falling back to generic"
fi

# scaffold dirs
miss=""
for d in docs/superpowers/specs docs/superpowers/plans docs/superpowers/handoffs reports; do
  [ -d "$repo/$d" ] || miss="$miss $d"
done
if [ -z "$miss" ]; then pass scaffold "all SDLC dirs present"; else fail scaffold "missing:$miss — run /sdlc:onboard"; fi

# state.json valid + known phase
state="$repo/.sdlc/state.json"
if [ ! -f "$state" ]; then
  fail state ".sdlc/state.json missing — run /sdlc:onboard"
elif ! jq -e . "$state" >/dev/null 2>&1; then
  fail state ".sdlc/state.json is not valid JSON — re-run /sdlc:onboard"
else
  phase="$(jq -r '.phase' "$state" 2>/dev/null)"
  case "$phase" in
    INIT|SPEC_DRAFT|SPEC_APPROVED|PLAN_DRAFT|PLAN_APPROVED|IMPL_IN_PROGRESS|IMPL_COMPLETE|REVIEW_R1|REVIEW_R2|TEST_RUN|TEST_PASS|RC|RC_CANDIDATE|GA_TAG)
      pass state "state valid (phase=$phase)" ;;
    *) fail state "unknown phase '$phase' in state.json" ;;
  esac
fi

# gitignore
gi="$repo/.gitignore"
gimiss=""
for line in ".sdlc/" "reports/runs/"; do
  grep -qxF "$line" "$gi" 2>/dev/null || gimiss="$gimiss $line"
done
if [ -z "$gimiss" ]; then pass gitignore "sdlc paths ignored"; else warn gitignore "not ignored:$gimiss — run /sdlc:onboard"; fi

# [mcp] advisory (web-ui-verify): only for web-UI repos; Playwright MCP presence is NEVER a blocker
# (absent ⇒ web-UI E2E degrades to UI-UNVERIFIED, never a false PASS). SE16-safe: case, no pipe-grep.
webstack="$(bash "$(dirname "$0")/../../config/detect-web-stack.sh" "$repo" 2>/dev/null || echo not-a-web-app)"
if [ "$webstack" != not-a-web-app ]; then
  mcpout=""; mcpto=""
  if command -v timeout >/dev/null 2>&1; then mcpto=timeout; elif command -v gtimeout >/dev/null 2>&1; then mcpto=gtimeout; fi
  if command -v claude >/dev/null 2>&1; then
    if [ -n "$mcpto" ]; then mcpout="$("$mcpto" "${SDLC_MCP_PROBE_TIMEOUT:-45}" claude mcp list 2>/dev/null || true)"
    else mcpout="$(claude mcp list 2>/dev/null || true)"; fi
  fi
  case "$mcpout" in
    *playwright*Connected*|*chrome-devtools*Connected*) echo "[mcp] PASS: Playwright/chrome-devtools MCP connected — real Chrome browser E2E available." ;;
    *) echo "[mcp] WARN: Playwright/chrome-devtools MCP not connected — web-UI E2E runs server-side only, reports UI-UNVERIFIED (advisory, not a blocker)." ;;
  esac
fi

echo "---"
if [ "$fails" -eq 0 ]; then
  echo "READY (0 issues)"; exit 0
else
  echo "$fails issue(s) — fix the FAIL lines above"; exit 1
fi
