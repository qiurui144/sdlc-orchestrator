#!/usr/bin/env bash
# onboard.sh — bootstrap a target repo to use sdlc-orchestrator. Deterministic,
# idempotent, zero-LLM. Creates missing scaffold ONLY; never overwrites an existing
# config/state and never touches the user's CLAUDE.md (per spec O1/O5, DP2).
# Usage: onboard.sh [<repo-root>]   (default: cwd)
#   exit 0 = onboarded (or already onboarded — idempotent)
#   exit 1 = precondition fail (dir missing / not a git repo)
# POSIX / bash-3.2-safe per tests/PORTABILITY.md (no realpath, no date -d).
set -euo pipefail

# Target project root: positional arg > SDLC_PROJECT_ROOT > cwd (so Claude launched from a parent
# directory can target a specific project subdir — v0.20).
repo_in="${1:-${SDLC_PROJECT_ROOT:-$(pwd)}}"
repo="$(cd "$repo_in" 2>/dev/null && pwd -P)" || { echo "onboard: no such dir: $repo_in" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd -P)"
PLUGIN_ROOT="$(cd "$HERE/../.." && pwd -P)"

# 1. precondition: must be a git repo (we do NOT auto-init — per spec DP3/O2)
if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  echo "onboard-not-git: $repo is not a git repository. Run 'git init' first, then re-onboard." >&2
  exit 1
fi

filled=0

# 2. detect stack (reuses the single source of stack truth). module_dir is "." for a
#    root module, or a subdir name when the build module lives below the root (bug1) —
#    used to cd the adapter commands into the module dir.
stack="$("$PLUGIN_ROOT/config/detect-stack.sh" "$repo" 2>/dev/null || echo generic)"
module_dir="$("$PLUGIN_ROOT/config/detect-stack.sh" --module-dir "$repo" 2>/dev/null || echo .)"

# 3. scaffold dirs (mkdir -p is idempotent; count only newly created)
for d in docs/superpowers/specs docs/superpowers/plans docs/superpowers/handoffs reports; do
  if [ ! -d "$repo/$d" ]; then mkdir -p "$repo/$d"; filled=$((filled+1)); fi
done

# 4. seed state ONLY if absent (preserve sprint progress on re-onboard)
state="$repo/.sdlc/state.json"
if [ ! -f "$state" ]; then
  mkdir -p "$repo/.sdlc"
  ver="$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)"
  ts="$(TZ='Asia/Shanghai' date '+%Y-%m-%dT%H:%M:%S+08:00')"
  cat > "$state" <<EOF
{
  "schema_version": 1,
  "phase": "INIT",
  "stack": "$stack",
  "module_dir": "$module_dir",
  "sprint_id": null,
  "onboarded_at": "$ts",
  "plugin_version": "$ver"
}
EOF
  filled=$((filled+1))
fi

# 5. gitignore: append each line only if missing (dedup)
gi="$repo/.gitignore"
touch "$gi"
for line in ".sdlc/" "reports/runs/"; do
  grep -qxF "$line" "$gi" 2>/dev/null || { printf '%s\n' "$line" >> "$gi"; filled=$((filled+1)); }
done

# 6. config stub ONLY if absent (preserve user edits — never overwrite)
cfg="$repo/.claude/sdlc-orchestrator.local.md"
if [ ! -f "$cfg" ]; then
  mkdir -p "$repo/.claude"
  cat > "$cfg" <<EOF
---
# sdlc-orchestrator per-project config (overrides plugin defaults)
# NOTE: disk redlines are NOT set here — they live in .sdlc/disk.conf (the only surface
# the disk-guard hook reads). Setting disk_redline_* in this file has no effect.
multi_agent_max_parallel: 2
pre_create_gate_strict: false
token_budget: 0          # 0 = no cap; set a per-sprint token ceiling to enable budget warnings
budget_strict: false     # true = block (exit 2) when a /sdlc:cost estimate exceeds token_budget
stack: $stack
---

# Project SDLC notes
(Optional: project-specific SDLC conventions the orchestrator should honor.)
EOF
  filled=$((filled+1))
fi

# 6.5 materialize plugin templates into the repo so agents can read a repo-relative
#     skeleton. CLAUDE_PLUGIN_ROOT is NOT exported to agents (verified v0.6.5), so an
#     agent cannot read the plugin's own templates/ dir — we copy them in. Idempotent:
#     never overwrite an existing template (preserve user edits).
if [ -d "$PLUGIN_ROOT/templates" ]; then
  for tpl in "$PLUGIN_ROOT"/templates/*.md; do
    [ -f "$tpl" ] || continue
    base="$(basename "$tpl")"
    if [ ! -f "$repo/.sdlc/templates/$base" ]; then
      mkdir -p "$repo/.sdlc/templates"
      cp "$tpl" "$repo/.sdlc/templates/$base"
      filled=$((filled+1))
    fi
  done
fi

# 6.6 materialize the detected stack adapter into the repo (same class as 6.5: agents
#     cannot reach the plugin's config/ dir — CLAUDE_PLUGIN_ROOT unset — so the tester/
#     implementer read build/test/lint commands from .sdlc/stack.yaml repo-relative).
adapter="$PLUGIN_ROOT/config/stack-$stack.yaml"
if [ -f "$adapter" ] && [ ! -f "$repo/.sdlc/stack.yaml" ]; then
  mkdir -p "$repo/.sdlc"
  if [ "$module_dir" != "." ]; then
    # Module lives in a subdir → wrap each command value in a subshell that cd's into
    # the module root: `<key>: (cd '<dir>' && <value>)` (bug1). The SUBSHELL + the
    # closing paren are load-bearing: a value containing `;` (e.g. the python `clean`
    # = `find ... +; rm -rf ...`) must run its post-`;` part INSIDE the cd, not at the
    # repo root (W1); the dir is single-quoted so a name with spaces/metachars is safe
    # (W2). Only single-line command keys are wrapped; `language:` + the multi-line
    # `target_size_estimator: |` block are left untouched.
    awk -v d="$module_dir" -v q="'" '
      /^(build|test_unit|test_integration|test_all|lint|clean): / {
        key=$1; sub(/^[^:]+: /, ""); print key " (cd " q d q " && " $0 ")"; next
      }
      { print }
    ' "$adapter" > "$repo/.sdlc/stack.yaml"
    echo "note: build module detected in '$module_dir/' — stack.yaml commands cd into it; edit .sdlc/stack.yaml if the primary module is elsewhere." >&2
  else
    cp "$adapter" "$repo/.sdlc/stack.yaml"
  fi
  filled=$((filled+1))
fi

# 6.7 seed .sdlc/disk.conf (the single disk-redline surface the hook reads) with commented
#     defaults — documents the knob without imposing a value. Idempotent.
dconf="$repo/.sdlc/disk.conf"
if [ ! -f "$dconf" ]; then
  mkdir -p "$repo/.sdlc"
  cat > "$dconf" <<'EOF'
# sdlc-orchestrator disk redline — read by the disk-guard hook (skills/disk-self-audit/audit.sh).
# Precedence: env var > this file > ~/.config/sdlc-orchestrator/disk.conf > built-in 50/50/5.
# Calibrate per machine: a box with a small / but a dedicated work disk should lower
# redline_root_gb. Uncomment + edit to override the built-in defaults:
# redline_root_gb=50
# redline_data_gb=50
# redline_tmp_gb=5
EOF
  filled=$((filled+1))
fi

# 7. report (note: we never create/touch CLAUDE.md — DP2)
if [ "$filled" -eq 0 ]; then
  echo "already onboarded (stack=$stack) — nothing to fill."
else
  echo "onboarded (stack=$stack) — filled $filled gap(s)."
fi
echo "Next: /sdlc:spec <feature-slug>   (then /sdlc:plan, /sdlc:impl, /sdlc:review, /sdlc:test, /sdlc:release)"
echo "Check wiring anytime: /sdlc:doctor"
exit 0
