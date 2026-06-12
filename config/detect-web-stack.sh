#!/usr/bin/env bash
# detect-web-stack.sh — frontend framework detector, ORTHOGONAL to detect-stack.sh.
# A web framework is NOT a build language: a Next app is still `ts` for detect-stack,
# and `next` here. Root package.json wins; else descend one level (monorepo web/ subdir).
# Framework precedence: next > angular > react > vue > svelte;
# bare index.html (no framework dep) → vanilla; no web marker anywhere → not-a-web-app (exit 2).
# Output is the framework token on stdout. SE16-safe: case-glob, no `|grep -q`.
set -uo pipefail
root="${1:-$(pwd)}"

framework_of() {  # echoes token or "" for a single dir
  local d="$1" pj="$1/package.json"
  if [ -f "$pj" ]; then
    local deps; deps="$(cat "$pj")"
    case "$deps" in
      *'"next"'*|*'"@next/'*)        echo next;    return;;
      *'"@angular/core"'*)           echo angular; return;;
      *'"react"'*|*'"react-dom"'*)   echo react;   return;;
      *'"vue"'*|*'"nuxt"'*)          echo vue;     return;;
      *'"svelte"'*|*'"@sveltejs/'*)  echo svelte;  return;;
      *) echo "";  return;;            # package.json but no known framework → caller may fall back
    esac
  fi
  [ -f "$d/index.html" ] && { echo vanilla; return; }
  echo ""
}

f="$(framework_of "$root")"
if [ -z "$f" ] && [ -f "$root/package.json" ]; then f=vanilla; fi   # JS app, no framework dep
if [ -z "$f" ]; then
  for sub in "$root"/*/; do
    [ -d "$sub" ] || continue
    f="$(framework_of "${sub%/}")"
    [ -n "$f" ] && break
  done
fi
if [ -z "$f" ]; then echo not-a-web-app; exit 2; fi
echo "$f"; exit 0
