#!/usr/bin/env bats
# atomic.sh — portable lock + atomic write. Concurrency-correctness is THE point (spec §9).
AT="$BATS_TEST_DIRNAME/../../skills/multi-agent-dispatch/atomic.sh"
setup() { TMP=$(mktemp -d); }
teardown() { rm -rf "$TMP"; }

@test "atomic_write writes content from arg" {
  ( . "$AT"; atomic_write "$TMP/f" "hello" )
  [ "$(cat "$TMP/f")" = "hello" ]
}
@test "atomic_write writes content from stdin" {
  ( . "$AT"; printf 'piped' | atomic_write "$TMP/f" )
  [ "$(cat "$TMP/f")" = "piped" ]
}
@test "atomic_rmw transforms existing content" {
  printf '3' > "$TMP/c"
  ( . "$AT"; atomic_rmw "$TMP/c" 'awk "{print \$1+1}"' )
  [ "$(cat "$TMP/c")" = "4" ]
}
@test "atomic_rmw treats missing file as empty (transform sees empty stdin)" {
  ( . "$AT"; atomic_rmw "$TMP/new" 'awk "BEGIN{v=0}{v=\$1}END{print v}"' )
  [ "$(cat "$TMP/new")" = "0" ]
}
@test "CONCURRENCY: 20 parallel rmw increments lose nothing" {
  printf '0' > "$TMP/c"
  for i in $(seq 1 20); do
    ( . "$AT"; atomic_rmw "$TMP/c" 'awk "{print \$1+1}"' ) &
  done
  wait
  [ "$(cat "$TMP/c")" = "20" ]   # no lost updates → lock works
}
@test "stale lock (dead PID) is reclaimed" {
  mkdir -p "$TMP/f.lock"; echo 999999 > "$TMP/f.lock/pid"   # non-existent PID
  ( . "$AT"; atomic_write "$TMP/f" "ok" )
  [ "$(cat "$TMP/f")" = "ok" ]
}
@test "lock timeout returns 1 when held by live process" {
  mkdir -p "$TMP/f.lock"; echo $$ > "$TMP/f.lock/pid"        # current shell = alive
  run env SDLC_LOCK_TIMEOUT=1 bash -c ". '$AT'; atomic_write '$TMP/f' x"
  [ "$status" -eq 1 ]
}
@test "CONCURRENCY: concurrent reclaimers of a stale lock never double-acquire (Issue 1)" {
  printf '0' > "$TMP/c"
  mkdir -p "$TMP/c.lock"; echo 999999 > "$TMP/c.lock/pid"    # stale lock present at start
  for i in 1 2 3 4 5; do
    ( . "$AT"; atomic_rmw "$TMP/c" 'awk "{print \$1+1}"' ) &
  done
  wait
  [ "$(cat "$TMP/c")" = "5" ]   # a double-acquire would lose an update → value < 5
}
