#!/usr/bin/env bats
# queue.sh — serial cross-feature merge-queue: merge + version-at-merge-time + tag (v0.11).
Q="$BATS_TEST_DIRNAME/../../skills/merge-queue/queue.sh"
setup() {
  R=$(mktemp -d); cd "$R" || exit 1
  git init -q -b main; git config user.email t@t; git config user.name t
  echo base > base.txt; git add .; git commit -qm base
  git tag v0.11.0
  git checkout -q -b f1; echo a > a.txt; git add .; git commit -qm a
  git checkout -q -b f2 main; echo b > b.txt; git add .; git commit -qm b
  git checkout -q -b c1 main; echo x > shared.txt; git add .; git commit -qm c1
  git checkout -q -b c2 main; echo y > shared.txt; git add .; git commit -qm c2
  git checkout -q main
}
teardown() { cd /; rm -rf "$R"; }

@test "happy: two features merge in order, tagged v0.11.1 then v0.11.2" {
  run bash "$Q" --base main --features f1,f2
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "merged=f1 tag=v0.11.1"
  echo "$output" | grep -q "merged=f2 tag=v0.11.2"
  git -C "$R" rev-parse -q --verify refs/tags/v0.11.1
  git -C "$R" rev-parse -q --verify refs/tags/v0.11.2
}
@test "version: --bump minor → v0.12.0" {
  run bash "$Q" --base main --features f1 --bump minor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "merged=f1 tag=v0.12.0"
}
@test "version: fresh repo (no tags) seeds v0.1.0" {
  git -C "$R" tag -d v0.11.0
  run bash "$Q" --base main --features f1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "merged=f1 tag=v0.1.0"
}
@test "version: pre-release tag is ignored (G1 BLOCKING2)" {
  git -C "$R" tag v1.0.0-rc.1
  run bash "$Q" --base main --features f1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "merged=f1 tag=v0.11.1"
}
@test "error: conflicting feature → first tagged, second exit 1 + conflict report" {
  run bash "$Q" --base main --features c1,c2
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "merged=c1 tag=v0.11.1"
  echo "$output" | grep -q "conflict=c2"
  echo "$output" | grep -q "shared.txt"
}
@test "kept-tag reachable from mainline after later conflict (G1 BLOCKING3)" {
  bash "$Q" --base main --features c1,c2 || true
  run git -C "$R" merge-base --is-ancestor v0.11.1 main
  [ "$status" -eq 0 ]
}
@test "error: missing feature branch → missing-feature, exit 2 (no partial merge)" {
  run bash "$Q" --base main --features f1,nope
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "missing-feature=nope"
  ! echo "$output" | grep -q "merged=f1"
}
@test "review CRITICAL: empty element f1,,f2 → fail-fast, no partial merge/tag" {
  before=$(git -C "$R" rev-parse main)
  run bash "$Q" --base main --features 'f1,,f2'
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "missing-feature="
  ! echo "$output" | grep -q "merged=f1"
  ! git -C "$R" rev-parse -q --verify refs/tags/v0.11.1
  [ "$(git -C "$R" rev-parse main)" = "$before" ]
}
@test "review IMPORTANT: leading-zero version segment normalizes, never crashes" {
  git -C "$R" tag -d v0.11.0
  git -C "$R" tag v0.08.0
  run bash "$Q" --base main --features f1 --bump minor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "merged=f1 tag=v0.9.0"
}
# §7.2 "never force-overwrite": next_version returns max+1 so a collision is unreachable
# in single-driver flow (TDD finding) — collision is a TOCTOU backstop. We test the real,
# reachable guarantees: (a) the script never passes -f/--force to git tag; (b) re-running a
# merged feature is a no-op that never re-tags.
@test "§7.2: queue.sh never force-tags (no -f/--force on git tag, comments excluded)" {
  # strip comment lines first so an explanatory comment mentioning -f is not a false hit
  run bash -c "grep -vE '^[[:space:]]*#' '$Q' | grep -nE 'git[[:space:]]+tag([[:space:]].*)?(-f|--force)'"
  [ "$status" -ne 0 ]
}
@test "re-running a merged feature is a no-op (skipped-empty), never re-tags" {
  bash "$Q" --base main --features f1
  run bash "$Q" --base main --features f1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "skipped-empty=f1"
  ! git -C "$R" rev-parse -q --verify refs/tags/v0.11.2
}
@test "error: --base a SHA (not a branch) → refused, exit 2 (G1 BLOCKING1)" {
  sha=$(git -C "$R" rev-parse HEAD)
  run bash "$Q" --base "$sha" --features f1
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "queue-base-not-a-branch"
}
@test "missing args → exit 2" {
  run bash "$Q" --base main
  [ "$status" -eq 2 ]
}
@test "dry-run: reports version sequence, creates no tags, mutates no branch" {
  before=$(git -C "$R" rev-parse main)
  run bash "$Q" --base main --features f1,f2 --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would-merge=f1 would-tag=v0.11.1"
  echo "$output" | grep -q "would-merge=f2 would-tag=v0.11.2"
  ! git -C "$R" rev-parse -q --verify refs/tags/v0.11.1
  [ "$(git -C "$R" rev-parse main)" = "$before" ]
}
@test "adversarial: feature name injection is not executed" {
  run bash "$Q" --base main --features 'f1;touch HACKED'
  [ "$status" -eq 2 ]
  [ ! -f "$R/HACKED" ]
}
@test "repo: --repo runs the queue in the target repo" {
  cd /
  run bash "$Q" --base main --features f1 --repo "$R"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "merged=f1 tag=v0.11.1"
}

@test "SKILL.md documents conflict→rebase-on-new-baseline (never auto-resolve)" {
  S="$BATS_TEST_DIRNAME/../../skills/merge-queue/SKILL.md"
  grep -qiE "rebase" "$S"
  grep -qiE "never.*(resolve|auto)|escalate" "$S"
}
@test "SKILL.md documents version-at-merge-time + multi-repo prototype boundary" {
  S="$BATS_TEST_DIRNAME/../../skills/merge-queue/SKILL.md"
  grep -qiE "merge.time|merge-time|7\.1\.7" "$S"
  grep -qiE "prototype|ent-v1.0|multi-repo" "$S"
}

@test "task-orchestrator documents cross-feature worktree dispatch + merge-queue" {
  T="$BATS_TEST_DIRNAME/../../agents/task-orchestrator.md"
  grep -qiE "cross-feature|worktree-per-feature" "$T"
  grep -qiE "merge-queue|queue.sh" "$T"
}
@test "/sdlc:merge-queue command exists with frontmatter + calls queue.sh + no-push" {
  C="$BATS_TEST_DIRNAME/../../commands/merge-queue.md"
  head -1 "$C" | grep -q -- "---"
  grep -qi "queue.sh" "$C"
  grep -qiE "do not push|never push|push.*user|7\.2" "$C"
}
