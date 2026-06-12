#!/usr/bin/env bats
# jobs.sh — file-based background job registry (v0.12).
J="$BATS_TEST_DIRNAME/../../skills/async-dispatch/jobs.sh"
setup() { export SDLC_JOBS_DIR=$(mktemp -d); }
teardown() { rm -rf "$SDLC_JOBS_DIR"; }

@test "register then list: two running jobs" {
  bash "$J" register --id a --label "audit a"
  bash "$J" register --id b --label "audit b"
  run bash "$J" list --status running
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "id=a status=running"
  echo "$output" | grep -q "id=b status=running"
}
@test "complete transitions running→done; inflight count drops" {
  bash "$J" register --id a --label x
  bash "$J" register --id b --label y
  [ "$(bash "$J" inflight)" -eq 2 ]
  bash "$J" complete --id a
  [ "$(bash "$J" inflight)" -eq 1 ]
  run bash "$J" list --status done
  echo "$output" | grep -q "id=a status=done"
}
@test "complete --status failed records failed" {
  bash "$J" register --id a --label x
  bash "$J" complete --id a --status failed
  run bash "$J" list --status failed
  echo "$output" | grep -q "id=a status=failed"
}
@test "inflight on empty dir is 0; list on empty prints none" {
  run bash "$J" inflight
  [ "$output" = "0" ]
  run bash "$J" list
  echo "$output" | grep -q "none"
}
@test "register auto-creates jobs dir" {
  rm -rf "$SDLC_JOBS_DIR"
  run bash "$J" register --id a --label x
  [ "$status" -eq 0 ]
  [ -f "$SDLC_JOBS_DIR/a.job" ]
}
@test "reap orphans a stale running job and prints reaped=<id> (G1 slot-release hook)" {
  SDLC_NOW_OVERRIDE=1000 bash "$J" register --id a --label x
  run env SDLC_NOW_OVERRIDE=5000 bash "$J" reap --max-age 1000
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "reaped=a"
  run bash "$J" list --status orphaned
  echo "$output" | grep -q "id=a status=orphaned"
}
@test "reap leaves a fresh running job alone, prints nothing" {
  SDLC_NOW_OVERRIDE=5000 bash "$J" register --id a --label x
  run env SDLC_NOW_OVERRIDE=5100 bash "$J" reap --max-age 1000
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "reaped="
  [ "$(bash "$J" inflight)" -eq 1 ]
}
@test "reap preserves the job's result-pointer fields (ts/label kept)" {
  SDLC_NOW_OVERRIDE=1000 bash "$J" register --id a --label "keep-me"
  env SDLC_NOW_OVERRIDE=9000 bash "$J" reap --max-age 1
  run bash "$J" list --status orphaned
  echo "$output" | grep -q "label=keep-me"
}
@test "complete a non-existent id → exit 2 missing-job" {
  run bash "$J" complete --id ghost
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "missing-job=ghost"
}
@test "missing --id on register → exit 2" {
  run bash "$J" register --label x
  [ "$status" -eq 2 ]
}
@test "reap without --max-age → exit 2" {
  run bash "$J" reap
  [ "$status" -eq 2 ]
}
@test "adversarial: id with path traversal / separator / injection → exit 2, no file escapes" {
  run bash "$J" register --id "../escape" --label x
  [ "$status" -eq 2 ]
  run bash "$J" register --id "a/b" --label x
  [ "$status" -eq 2 ]
  run bash "$J" register --id "a;rm -rf /" --label x
  [ "$status" -eq 2 ]
  [ ! -e "$SDLC_JOBS_DIR/../escape.job" ]
}
@test "G2 hygiene: dot and dotdot ids rejected → exit 2" {
  run bash "$J" register --id "." --label x
  [ "$status" -eq 2 ]
  run bash "$J" register --id ".." --label x
  [ "$status" -eq 2 ]
}
@test "G3 hardening: newline in label cannot inject an extra record line" {
  bash "$J" register --id a --label "$(printf 'l1\nstatus=HACKED')"
  [ "$(wc -l < "$SDLC_JOBS_DIR/a.job")" -eq 3 ]
  run bash "$J" list --status running
  echo "$output" | grep -q "id=a status=running"
}
@test "concurrent-style: three distinct ids → three independent files, no clobber" {
  bash "$J" register --id j1 --label a
  bash "$J" register --id j2 --label b
  bash "$J" register --id j3 --label c
  [ "$(bash "$J" inflight)" -eq 3 ]
  ls "$SDLC_JOBS_DIR"/*.job | wc -l | grep -q 3
}
@test "synchronous-degrade equivalence: register then immediate complete = done, inflight 0" {
  bash "$J" register --id a --label x
  bash "$J" complete --id a
  [ "$(bash "$J" inflight)" -eq 0 ]
  run bash "$J" list --status done
  echo "$output" | grep -q "id=a status=done"
}

@test "SKILL.md documents run_in_background + register→collect + degrade-to-sync" {
  S="$BATS_TEST_DIRNAME/../../skills/async-dispatch/SKILL.md"
  grep -qiE "run_in_background" "$S"
  grep -qiE "degrade|synchronous|退化|sync" "$S"
}
@test "SKILL.md documents slot-release on complete AND reap (no leak) + results to reports" {
  S="$BATS_TEST_DIRNAME/../../skills/async-dispatch/SKILL.md"
  grep -qiE "counter_release|slot" "$S"
  grep -qiE "reports/runs|R18|result" "$S"
}

@test "task-orchestrator documents async background dispatch via jobs.sh" {
  T="$BATS_TEST_DIRNAME/../../agents/task-orchestrator.md"
  grep -qiE "run_in_background" "$T"
  grep -qiE "jobs.sh|async-dispatch" "$T"
}
@test "intake-orchestrator notes independent audits may run in background" {
  I="$BATS_TEST_DIRNAME/../../agents/intake-orchestrator.md"
  grep -qiE "run_in_background|async-dispatch|background" "$I"
}
@test "/sdlc:status shows in-flight background jobs" {
  C="$BATS_TEST_DIRNAME/../../commands/status.md"
  grep -qiE "in-flight|jobs.sh|background" "$C"
}
