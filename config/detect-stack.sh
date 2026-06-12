#!/usr/bin/env bash
# Detect the build stack of a repo by its marker files.
#
#   detect-stack.sh [<repo-root>]                 -> echoes language: rust|ts|python|go|generic
#   detect-stack.sh --module-dir [<repo-root>]    -> echoes the module dir: "." or a subdir name
#
# Root markers win (back-compat). When the root has NO marker, descend ONE level
# and pick the primary module — the common polyglot layout where the build module
# lives in a subdir (e.g. a Go backend in go/, a Rust crate in privacy/). Without
# this, such a repo silently detected as "generic" and /sdlc:test ran the generic
# adapter (bats) instead of the real toolchain (bug1, dogfound 2026-06-05).
#
# Primary-module selection among subdirs: a directory-NAME preference list first
# (backend/server/go/... — the conventional "main code" dir), then the first
# marker-bearing subdir alphabetically. onboard records the chosen dir as
# state.module_dir and emits `cd <dir> && ...` adapter commands.
#
# Python markers include requirements.txt / Pipfile (v0.6.1 real-project finding).
set -euo pipefail

mode="lang"
if [ "${1:-}" = "--module-dir" ]; then mode="dir"; shift; fi
root="${1:-$(pwd)}"

# Echo the language implied by a single directory's marker files, or "" if none.
lang_of() {
  local d="$1"
  if   [ -f "$d/Cargo.toml" ];   then echo rust
  elif [ -f "$d/package.json" ]; then echo ts
  elif [ -f "$d/pyproject.toml" ] || [ -f "$d/setup.py" ] || [ -f "$d/requirements.txt" ] || [ -f "$d/Pipfile" ]; then echo python
  elif [ -f "$d/go.mod" ];       then echo go
  else echo ""; fi
}

# 1. Root marker wins (back-compat: module at repo root → dir ".").
root_lang="$(lang_of "$root")"
if [ -n "$root_lang" ]; then
  if [ "$mode" = dir ]; then echo "."; else echo "$root_lang"; fi
  exit 0
fi

# 2. Descend one level. Prefer conventional "main code" directory names, then any
#    marker-bearing subdir alphabetically.
prefer=(backend server go api core srv service cmd)   # NOT src/app — too ambiguous (often frontend); a sole src/ module is still found by the fallback below
chosen_dir=""
chosen_lang=""

for name in "${prefer[@]}"; do
  if [ -d "$root/$name" ]; then
    l="$(lang_of "$root/$name")"
    if [ -n "$l" ]; then chosen_dir="$name"; chosen_lang="$l"; break; fi
  fi
done

if [ -z "$chosen_dir" ]; then
  for d in "$root"/*/; do
    [ -d "$d" ] || continue          # no subdirs → literal glob, skipped
    l="$(lang_of "${d%/}")"
    if [ -n "$l" ]; then chosen_dir="$(basename "${d%/}")"; chosen_lang="$l"; break; fi
  done
fi

if [ -n "$chosen_dir" ]; then
  if [ "$mode" = dir ]; then echo "$chosen_dir"; else echo "$chosen_lang"; fi
  exit 0
fi

# 3. No marker anywhere.
if [ "$mode" = dir ]; then echo "."; else echo generic; fi
