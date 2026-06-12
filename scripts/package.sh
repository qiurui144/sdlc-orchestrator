#!/usr/bin/env bash
# package.sh — build the distributable plugin tarball: dist/sdlc-orchestrator-<version>.tar.gz.
# Ships ONLY the runtime plugin surface (manifest + agents + commands + skills + hooks + config
# + user-facing docs); excludes tests/docs/reports/dev artifacts. Verifies the version arg
# matches the manifest so a tag/package can never split-brain (releaser AC6). bash-3.2-safe.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$HERE/.." && pwd -P)"

ver="${1:-}"
[ -n "$ver" ] || { echo "usage: package.sh <version>   (e.g. v0.16.0)" >&2; exit 2; }
v="${ver#v}"   # accept with or without leading 'v'

# version must match the manifest — no split-brain between tag, manifest, and tarball.
manifest="$ROOT/.claude-plugin/plugin.json"
mver=$(yq -r '.version' "$manifest" 2>/dev/null || jq -r '.version' "$manifest")
if [ "$v" != "$mver" ]; then
  echo "package-version-mismatch: arg=$v manifest=$mver (bump the manifest first)" >&2; exit 2
fi

out_dir="${DIST_DIR:-$ROOT/dist}"
mkdir -p "$out_dir"
tarball="$out_dir/sdlc-orchestrator-v$v.tar.gz"

# Runtime surface only. `eval/` is REQUIRED: challenger-panel/panel.sh sources eval/judge.sh
# and /sdlc:eval uses eval/{grade,run-eval}.sh + fixtures (caught by packaged-artifact smoke —
# omitting it shipped a broken Challenger Panel). Optional docs via if-guards (set -e && trap).
inc=(.claude-plugin agents commands skills hooks config eval README.md README.zh.md)
if [ -f "$ROOT/LICENSE" ]; then inc+=(LICENSE); fi
if [ -f "$ROOT/DEVELOP.md" ]; then inc+=(DEVELOP.md); fi
if [ -f "$ROOT/RELEASE.md" ]; then inc+=(RELEASE.md); fi

# Exclude transient run outputs (eval/runs, reports/runs) — never part of the distributable.
tar -czf "$tarball" --exclude='eval/runs' --exclude='*/runs/*' -C "$ROOT" "${inc[@]}"
echo "packaged=$tarball"
echo "size=$(du -h "$tarball" | awk '{print $1}')"
echo "contents=$(tar tzf "$tarball" | wc -l | tr -d ' ') entries"
