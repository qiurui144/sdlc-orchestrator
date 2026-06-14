#!/usr/bin/env bats

ARCHIVE="$BATS_TEST_DIRNAME/../../skills/sprint-archival/archive.sh"

setup() {
  TMP=$(mktemp -d)
  cd "$TMP" && git init -q
  git config user.name test && git config user.email test@test
  mkdir -p docs/superpowers/{specs,plans,handoffs}
  echo "spec" > docs/superpowers/specs/2026-05-28-foo.md
  echo "plan" > docs/superpowers/plans/2026-05-28-foo.md
  echo "handoff" > docs/superpowers/handoffs/2026-05-28-foo-spec-plan.yaml
  echo "release" > RELEASE.md
  git add -A && git commit -qm init
}

teardown() {
  rm -rf "$TMP"
}

@test "dry-run lists archival actions" {
  run "$ARCHIVE" --sprint 2026-05-28-foo --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan"* ]]
  [[ "$output" == *"would"* ]]
}

@test "apply mode removes plan but keeps spec" {
  run "$ARCHIVE" --sprint 2026-05-28-foo --apply
  [ "$status" -eq 0 ]
  [ ! -f docs/superpowers/plans/2026-05-28-foo.md ]
  [ -f docs/superpowers/specs/2026-05-28-foo.md ]
}

@test "handoffs archived to RELEASE.md" {
  run "$ARCHIVE" --sprint 2026-05-28-foo --apply
  grep -q "2026-05-28-foo" RELEASE.md
}

@test "adopted plan is preserved (plan_self_built=false)" {
  mkdir -p .sdlc
  printf '{"phase":"PLAN_APPROVED","plan_self_built":false}' > .sdlc/state.json
  run "$ARCHIVE" --sprint 2026-05-28-foo --apply
  [ "$status" -eq 0 ]
  [ -f docs/superpowers/plans/2026-05-28-foo.md ]
  grep -q "adopted" RELEASE.md
}

@test "self-built plan is deleted (plan_self_built=true)" {
  mkdir -p .sdlc
  printf '{"phase":"PLAN_APPROVED","plan_self_built":true}' > .sdlc/state.json
  run "$ARCHIVE" --sprint 2026-05-28-foo --apply
  [ "$status" -eq 0 ]
  [ ! -f docs/superpowers/plans/2026-05-28-foo.md ]
}

@test "no state.json defaults to delete plan (backward compat)" {
  run "$ARCHIVE" --sprint 2026-05-28-foo --apply
  [ "$status" -eq 0 ]
  [ ! -f docs/superpowers/plans/2026-05-28-foo.md ]
}
