#!/usr/bin/env bats
# merge.sh — serial topological merge of task branches + conflict detection (v0.10).
MERGE="$BATS_TEST_DIRNAME/../../skills/worktree-merge/merge.sh"
setup() {
  R=$(mktemp -d); cd "$R" || exit 1
  git init -q -b main; git config user.email t@t; git config user.name t
  echo base > base.txt; git add .; git commit -qm base
  git checkout -q -b b1; echo a > a.txt; git add .; git commit -qm a
  git checkout -q -b b2 main; echo b > b.txt; git add .; git commit -qm b
  git checkout -q -b c1 main; echo x > shared.txt; git add .; git commit -qm c1
  git checkout -q -b c2 main; echo y > shared.txt; git add .; git commit -qm c2
  git checkout -q main
}
teardown() { cd /; rm -rf "$R"; }

@test "clean merge of two non-conflicting branches → exit 0, both files present" {
  run bash "$MERGE" --base main --branches b1,b2
  [ "$status" -eq 0 ]
  [ -f "$R/a.txt" ] && [ -f "$R/b.txt" ]
}
@test "conflicting branches → exit 1 + reports conflict branch and file" {
  run bash "$MERGE" --base main --branches c1,c2
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "conflict=c2"
  echo "$output" | grep -q "shared.txt"
}
@test "after conflict abort, tree is clean (no merge markers left)" {
  bash "$MERGE" --base main --branches c1,c2 || true
  run git -C "$R" status --porcelain
  [ -z "$output" ]
}
@test "missing args → exit 2" {
  run bash "$MERGE" --base main
  [ "$status" -eq 2 ]
}
@test "single branch merges clean" {
  run bash "$MERGE" --base main --branches b1
  [ "$status" -eq 0 ]
}

@test "SKILL.md documents conflict-escalate (never auto-resolve)" {
  S="$BATS_TEST_DIRNAME/../../skills/worktree-merge/SKILL.md"
  grep -qi "conflict" "$S"
  grep -qiE "escalate|never.*resolve|no silent resolution" "$S"
}

@test "implementer dispatches parallel tasks in isolated worktrees with serial merge" {
  I="$BATS_TEST_DIRNAME/../../agents/implementer.md"
  grep -qi "worktree" "$I"
  grep -qi "isolation" "$I"
  grep -qiE "merge.sh|worktree-merge" "$I"
}

@test "architect group cap is SDLC_MAX_PARALLEL not hardcoded max-2" {
  A="$BATS_TEST_DIRNAME/../../agents/architect.md"
  grep -q "SDLC_MAX_PARALLEL" "$A"
}

@test "non-existent branch → missing-branch (not conflict), exit 2 (review Issue 1)" {
  run bash "$MERGE" --base main --branches b1,nonexistent
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "missing-branch=nonexistent"
  ! echo "$output" | grep -q "conflict="
}

@test "add/add conflict (same new file) detected + file reported (refutes review Issue 3)" {
  git -C "$R" checkout -q -b aa1 main; echo A > "$R/newf.txt"; git -C "$R" add .; git -C "$R" commit -qm aa1
  git -C "$R" checkout -q -b aa2 main; echo B > "$R/newf.txt"; git -C "$R" add .; git -C "$R" commit -qm aa2
  git -C "$R" checkout -q main
  run bash "$MERGE" --base main --branches aa1,aa2
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "conflict=aa2"
  echo "$output" | grep -q "newf.txt"
}
