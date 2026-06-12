#!/usr/bin/env bats
# counter.sh — cross-turn in-flight slot counter. Cap-enforcement under races is the point.
CT="$BATS_TEST_DIRNAME/../../skills/multi-agent-dispatch/counter.sh"
setup() { TMP=$(mktemp -d); export SDLC_COUNTER_FILE="$TMP/counter"; }
teardown() { rm -rf "$TMP"; }

@test "fresh counter inflight is 0" {
  run bash -c ". '$CT'; counter_reset; counter_inflight"
  [ "$output" = "0" ]
}
@test "acquire then release returns to 0" {
  bash -c ". '$CT'; counter_reset; counter_acquire 3 >/dev/null; counter_release 3"
  run bash -c ". '$CT'; counter_inflight"; [ "$output" = "0" ]
}
@test "acquire 3 emits 3 slot ids" {
  run bash -c ". '$CT'; counter_reset; SDLC_MAX_PARALLEL=5 counter_acquire 3"
  [ "$(echo "$output" | wc -w)" -eq 3 ]
}
@test "acquire beyond cap exits 3" {
  run bash -c ". '$CT'; counter_reset; SDLC_MAX_PARALLEL=2 counter_acquire 3"
  [ "$status" -eq 3 ]
}
@test "CONCURRENCY: parallel acquires never oversell cap" {
  bash -c ". '$CT'; counter_reset"
  for i in $(seq 1 10); do
    ( . "$CT"; SDLC_MAX_PARALLEL=4 counter_acquire 1 >/dev/null 2>&1 ) &
  done
  wait
  run bash -c ". '$CT'; counter_inflight"
  [ "$output" -le 4 ]    # never exceeds cap despite 10 racing acquirers
}
@test "release floors at 0" {
  run bash -c ". '$CT'; counter_reset; counter_release 5; counter_inflight"
  [ "$output" = "0" ]
}
@test "counter_acquire on missing file initialises to n (no prior reset) (Issue 2)" {
  run bash -c ". '$CT'; SDLC_MAX_PARALLEL=4 counter_acquire 1 >/dev/null; counter_inflight"
  [ "$output" = "1" ]
}
