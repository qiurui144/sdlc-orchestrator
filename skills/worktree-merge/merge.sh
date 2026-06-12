#!/usr/bin/env bash
# merge.sh — serial topological merge of task branches with conflict detection.
# Reuses the v0.9 "shard-then-merge" pattern at the git layer (branch = shard).
# On conflict: abort + report; NEVER auto-resolves (spec §5.1 — no silent resolution).
# bash-3.2-safe per tests/PORTABILITY.md.
set -uo pipefail
base="" branches=""
while [ "$#" -gt 0 ]; do case "$1" in
  --base) base="$2"; shift 2;; --branches) branches="$2"; shift 2;; *) shift;; esac; done
if [ -z "$base" ] || [ -z "$branches" ]; then
  echo "usage: merge.sh --base <b> --branches <b1,b2,...>" >&2; exit 2
fi
git rev-parse --git-dir >/dev/null 2>&1 || { echo "merge-not-a-git-repo" >&2; exit 2; }
git checkout -q "$base" 2>/dev/null || { echo "merge-bad-base: $base" >&2; exit 2; }

# split comma list into positional args (parameterized to git merge — no eval, injection-safe)
oldifs=$IFS; IFS=','
# shellcheck disable=SC2086  # intentional word-split on comma into separate branch args
set -- $branches
IFS=$oldifs
for b in "$@"; do
  # missing branch = a degraded/crashed task, NOT a content conflict (spec §7) — distinct path
  if ! git rev-parse --verify --quiet "$b" >/dev/null 2>&1; then
    echo "missing-branch=$b"; exit 2
  fi
  if git merge --no-ff --no-edit "$b" >/dev/null 2>&1; then
    echo "merged=$b"
  else
    files=$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    git merge --abort 2>/dev/null || true
    echo "conflict=$b files=$files"
    exit 1
  fi
done
exit 0
