#!/usr/bin/env bash
set -euo pipefail

sprint=""
mode="dry-run"
args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    --sprint) sprint="${args[$((i+1))]:-}" ;;
    --sprint=*) sprint="${args[$i]#--sprint=}" ;;
    --apply) mode=apply ;;
    --dry-run) mode=dry-run ;;
  esac
done

if [ -z "$sprint" ]; then
  echo "usage: archive.sh --sprint <sprint-id> [--apply|--dry-run]" >&2
  exit 1
fi

# Target project root: SDLC_PROJECT_ROOT (run from a parent dir, v0.20) > git toplevel of cwd.
repo_root="${SDLC_PROJECT_ROOT:-$(git rev-parse --show-toplevel)}"
cd "$repo_root"

plan_file="docs/superpowers/plans/${sprint}.md"
handoff_glob="docs/superpowers/handoffs/${sprint}-*.yaml"
test_report="reports/${sprint}-test.md"

actions=()
[ -f "$plan_file" ] && actions+=("delete:$plan_file")
for h in $handoff_glob; do
  [ -f "$h" ] && actions+=("inline-then-delete:$h")
done
[ -f "$test_report" ] && actions+=("reference-in-release:$test_report")

if [ "${#actions[@]}" -eq 0 ]; then
  echo "Sprint $sprint: nothing to archive."
  exit 0
fi

echo "Sprint $sprint archival plan:"
for a in "${actions[@]}"; do
  echo "  - would $a"
done

if [ "$mode" = "dry-run" ]; then
  echo ""
  echo "Dry-run complete. Pass --apply to execute."
  exit 0
fi

release="RELEASE.md"
[ -f "$release" ] || echo "# Release Notes" > "$release"

{
  echo ""
  echo "## Sprint $sprint — archived $(TZ='Asia/Shanghai' date +%Y-%m-%d)"
} >> "$release"
for h in $handoff_glob; do
  [ -f "$h" ] || continue
  {
    echo "### Handoff: $(basename "$h" .yaml)"
    echo '```yaml'
    cat "$h"
    echo '```'
  } >> "$release"
  rm "$h"
done

[ -f "$plan_file" ] && rm "$plan_file"
[ -f "$test_report" ] && echo "Test report: \`$test_report\`" >> "$release"

echo "Sprint $sprint archived. Review RELEASE.md and commit."
