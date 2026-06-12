#!/usr/bin/env bash
# queue.sh — serial cross-feature merge-queue.
# Merges each feature branch (completion order) via worktree-merge/merge.sh, then
# assigns the next RELEASE version at merge time and tags it (§7.1.7). Third lift of
# the shard-then-merge pattern (feature-branch = shard). NEVER force-tags / pushes.
# bash-3.2-safe per tests/PORTABILITY.md.
#
# G1 BLOCKING1: --base MUST be a local branch NAME (merge.sh checks it out + advances
#   its ref → automatic new baseline). A SHA/HEAD would detach HEAD and orphan tags.
# G1 BLOCKING2: next version is computed from RELEASE tags only; pre-release tags
#   (-rc/-alpha/-beta) are filtered so they cannot poison the version sort.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MERGE_SH="$HERE/../worktree-merge/merge.sh"

base="" features="" repo="" bump="patch" prefix="v" dryrun=0
while [ "$#" -gt 0 ]; do case "$1" in
  --base) base="$2"; shift 2;;
  --features) features="$2"; shift 2;;
  --repo) repo="$2"; shift 2;;
  --bump) bump="$2"; shift 2;;
  --tag-prefix) prefix="$2"; shift 2;;
  --dry-run) dryrun=1; shift;;
  *) shift;;
esac; done

if [ -z "$base" ] || [ -z "$features" ]; then
  echo "usage: queue.sh --base <mainline-branch> --features <f1,f2,...> [--repo <p>] [--bump patch|minor] [--tag-prefix v] [--dry-run]" >&2
  exit 2
fi

# --repo threading: merge.sh uses the cwd git-dir, so cd into the target repo first.
if [ -n "$repo" ]; then
  cd "$repo" 2>/dev/null || { echo "queue-bad-repo: $repo" >&2; exit 2; }
fi
git rev-parse --git-dir >/dev/null 2>&1 || { echo "queue-not-a-git-repo" >&2; exit 2; }

# detached-HEAD guard (G1 BLOCKING1): refuse anything that is not a real local branch.
if ! git show-ref --verify --quiet "refs/heads/$base"; then
  echo "queue-base-not-a-branch: $base" >&2
  exit 2
fi

latest_release() {  # highest release version WITHOUT prefix, or empty
  git tag --list "${prefix}*" \
    | grep -vE -- '-(rc|alpha|beta)([.-][0-9]+)?$' \
    | sed "s/^${prefix}//" \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -1
}
bump_ver() {  # $1 = X.Y.Z (no prefix) → bumped X.Y.Z (no prefix); rc 3 on bad semver
  local v="$1" major minor patch rest
  major=${v%%.*}; rest=${v#*.}; minor=${rest%%.*}; patch=${rest#*.}
  case "$major.$minor.$patch" in *[!0-9.]*) return 3;; esac
  # normalize each segment base-10 (strips leading zeros; avoids octal interpretation of
  # e.g. "08" in $((...)) which would crash — review fix; spec §5.2 "防 leading-zero")
  major=$((10#$major)); minor=$((10#$minor)); patch=$((10#$patch))
  if [ "$bump" = "minor" ]; then minor=$((minor + 1)); patch=0; else patch=$((patch + 1)); fi
  echo "${major}.${minor}.${patch}"
}
next_version() {  # next full tag WITH prefix (reads live tags)
  local cur nb
  cur=$(latest_release)
  if [ -z "$cur" ]; then echo "${prefix}0.1.0"; return 0; fi
  nb=$(bump_ver "$cur") || { echo "queue-bad-semver: $cur" >&2; return 3; }
  echo "${prefix}${nb}"
}

# split comma list into positional args (injection-safe — parameterized, never eval'd)
oldifs=$IFS; IFS=','
# shellcheck disable=SC2086  # intentional word-split on comma into separate feature args
set -- $features
IFS=$oldifs

# fail-fast input validation (review CRITICAL): validate the ENTIRE feature list BEFORE any
# merge, so a typo (empty element from f1,,f2 / missing branch) never leaves a partial,
# half-tagged queue. A mid-queue partial state is only legitimate for a real merge CONFLICT
# (§7.1.7 keeps earlier tags), never for an input error. Single check (refs/heads) also
# removes the dual missing-branch inconsistency with merge.sh.
for f in "$@"; do
  if [ -z "$f" ] || ! git show-ref --verify --quiet "refs/heads/$f"; then
    echo "missing-feature=$f"; exit 2
  fi
done

# dry-run: report the version sequence; mutate nothing.
if [ "$dryrun" -eq 1 ]; then
  last=$(latest_release)
  for f in "$@"; do
    if [ -z "$last" ]; then nv="0.1.0"; else nv=$(bump_ver "$last") || { echo "queue-bad-semver: $last" >&2; exit 2; }; fi
    echo "would-merge=$f would-tag=${prefix}${nv}"
    last="$nv"
  done
  exit 0
fi

# real run: serial merge + tag.
for f in "$@"; do
  before=$(git rev-parse "refs/heads/$base")
  out=$(bash "$MERGE_SH" --base "$base" --branches "$f" 2>&1); mrc=$?
  if [ "$mrc" -eq 1 ]; then echo "$out"; exit 1; fi                 # conflict (merge.sh already aborted)
  if [ "$mrc" -ne 0 ]; then echo "merge-error=$f: $out"; exit 2; fi # surface merge.sh's reason
  after=$(git rev-parse "refs/heads/$base")
  if [ "$before" = "$after" ]; then echo "skipped-empty=$f"; continue; fi  # nothing merged → no tag
  v=$(next_version) || exit 2
  # git tag WITHOUT -f is the §7.2 guarantee: atomic, refuses an existing tag (never
  # force-overwrites). next_version returns max+1 so this is unreachable in single-driver
  # use; it is the TOCTOU/manual-tag backstop (spec §7 TOCTOU row).
  if ! git tag "$v" 2>/dev/null; then echo "tag-collision=$v"; exit 2; fi
  echo "merged=$f tag=$v"
done
exit 0
