#!/usr/bin/env bats

DOCTOR="$BATS_TEST_DIRNAME/../../skills/project-onboarding/doctor.sh"
ONBOARD="$BATS_TEST_DIRNAME/../../skills/project-onboarding/onboard.sh"

mk_repo() {
  local d; d=$(mktemp -d)
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
    && echo '[package]' > Cargo.toml && git add -A && git commit -qm init )
  echo "$d"
}

@test "doctor on an onboarded repo reports READY (exit 0)" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  run "$DOCTOR" "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"READY"* ]]
}

@test "doctor on an un-onboarded repo FAILs scaffold + state (exit 1)" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  run "$DOCTOR" "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[scaffold] FAIL"* ]]
  [[ "$output" == *"[state] FAIL"* ]]
}

@test "doctor FAILs on malformed state.json" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  printf 'not json{{{' > "$repo/.sdlc/state.json"
  run "$DOCTOR" "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[state] FAIL"* ]]
}

@test "doctor FAILs on unknown phase in state.json" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  printf '{"schema_version":1,"phase":"BOGUS","stack":"rust"}' > "$repo/.sdlc/state.json"
  run "$DOCTOR" "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown phase"* ]]
}

@test "doctor accepts the 'RC' phase alias (not just RC_CANDIDATE) — real project reached RC" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  printf '{"schema_version":1,"phase":"RC","stack":"rust"}' > "$repo/.sdlc/state.json"
  run "$DOCTOR" "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"state valid"* ]]
}

@test "doctor detects the stack" {
  repo=$(mk_repo); trap "rm -rf $repo" EXIT
  "$ONBOARD" "$repo" >/dev/null
  run "$DOCTOR" "$repo"
  [[ "$output" == *"detected rust"* ]]
}

@test "doctor on a non-git dir FAILs git check" {
  d=$(mktemp -d); trap "rm -rf $d" EXIT
  run "$DOCTOR" "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[git] FAIL"* ]]
}

@test "doctor.sh has the [mcp] advisory (WARN/advisory, never a blocker)" {
  run awk '/\[mcp\].*(WARN|advisory)/{f=1} END{exit f?0:1}' "$DOCTOR"
  [ "$status" -eq 0 ]
}
