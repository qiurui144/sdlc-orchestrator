#!/usr/bin/env bash
# Pre-Create Gate check. Returns:
#   0 = allow
#   1 = warn (non-blocking)
#   2 = block (hard violation)
set -euo pipefail

path="${1:?usage: check.sh <proposed-file-path>}"
filename=$(basename "$path")
dir=$(dirname "$path")

# Only audit .md / scripts/ / config/
case "$filename" in
  *.md)        ;;
  *.sh)        [[ "$dir" == */scripts ]] || exit 0 ;;
  *.yaml|*.yml) [[ "$dir" == */config ]] || exit 0 ;;
  *)            exit 0 ;;
esac

repo_root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || pwd)
# Both repo_root and abs_dir MUST resolve symlinks the same way, or the prefix
# strip fails and rel_path keeps leading slashes → wrong branch. git rev-parse
# returns the PHYSICAL path, but bash `pwd` (logical) keeps symlinks. On macOS,
# mktemp dirs live under /var → /private/var, so the two diverge. Use `pwd -P`
# (physical, POSIX on GNU+BSD) on both. Reproduced on Linux via a symlinked repo.
repo_root=$(cd "$repo_root" 2>/dev/null && pwd -P || echo "$repo_root")
# Portable repo-relative path (`realpath --relative-to` is GNU-only — absent on
# BSD/macOS, where it crashed these tests). Resolve parent via cd+pwd -P, strip prefix.
if abs_dir=$(cd "$dir" 2>/dev/null && pwd -P); then
  abs_path="$abs_dir/$(basename "$path")"
  rel_path="${abs_path#"$repo_root"/}"
else
  rel_path="$path"
fi

# Whitelist for .md
if [[ "$filename" == *.md ]]; then
  if [[ "$rel_path" != */* ]]; then
    case "$filename" in
      README.md|README.zh.md|DEVELOP.md|RELEASE.md|CLAUDE.md|LICENSE.md|ACKNOWLEDGMENTS.md|CONTRIBUTING.md|SECURITY.md)
        exit 0 ;;
      *)
        echo "pre-create-gate-fail: root .md whitelist violation: $filename (per CLAUDE.md §1.1.2). Allowed: README/DEVELOP/RELEASE/CLAUDE/LICENSE etc." >&2
        exit 2 ;;
    esac
  fi

  if [[ "$filename" =~ ^v[0-9]+\.[0-9]+(-|.)release-notes.*\.md$ ]]; then
    echo "pre-create-gate-fail: version-bound release notes file: $filename (per §3.2 禁止形态). Write to RELEASE.md instead." >&2
    exit 2
  fi

  if [[ "$filename" =~ -(tasks|report|todo|analysis|readiness)\.md$ ]]; then
    echo "pre-create-gate-fail: one-shot artifact filename: $filename (per §3.2). Write to PR description / RELEASE.md / reports/ instead." >&2
    exit 2
  fi

  if [[ "$filename" == *.zh.md && "$filename" != "README.zh.md" ]]; then
    echo "pre-create-gate-fail: .zh.md outside README: $rel_path (per §1.1.3). Use single ZH section in main file instead." >&2
    exit 2
  fi

  if [[ "$rel_path" == docs/* && "$rel_path" != docs/*/*/* ]]; then
    parent=$(dirname "$rel_path")
    if [[ "$parent" == "docs" ]]; then
      case "$filename" in
        INSTALL.md|TESTING.md|VERSIONING.md|DEPLOY.md)
          : ;;
        *)
          echo "pre-create-gate-warn: docs/ top-level file: $rel_path. Confirm single-topic feature doc (§1.1.2)." >&2
          exit 1
          ;;
      esac
    fi
  fi

  if [[ "$rel_path" =~ docs/(superpowers/)?(specs|plans|handoffs)/ ]]; then
    if [[ ! "$filename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}- ]]; then
      echo "pre-create-gate-fail: spec/plan/handoff requires <YYYY-MM-DD>- prefix: $filename" >&2
      exit 2
    fi
  fi

  topic_word=$(echo "$filename" | sed 's/\..*//' | tr -d '0-9-')
  if [ -n "$topic_word" ] && [ ${#topic_word} -ge 4 ]; then
    matches=$(grep -rli "$topic_word" "$repo_root/docs/" "$repo_root"/*.md 2>/dev/null | grep -v "$rel_path" | head -3 || true)
    if [ -n "$matches" ]; then
      echo "pre-create-gate-warn: similar-topic files exist:" >&2
      echo "$matches" >&2
      echo "Consider extending existing instead of creating new." >&2
      exit 1
    fi
  fi
fi

exit 0
