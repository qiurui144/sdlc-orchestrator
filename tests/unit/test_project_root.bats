#!/usr/bin/env bats
# SDLC_PROJECT_ROOT (v0.20): run sdlc against a SPECIFIED project dir while cwd is a parent.
# The project-root scripts default to cwd but honor $SDLC_PROJECT_ROOT (positional arg, where it
# exists, still wins). Proves the convention across onboard / doctor / ga-tag-guard / archive.
ONBOARD="$BATS_TEST_DIRNAME/../../skills/project-onboarding/onboard.sh"
DOCTOR="$BATS_TEST_DIRNAME/../../skills/project-onboarding/doctor.sh"
GUARD="$BATS_TEST_DIRNAME/../../hooks/ga-tag-guard.sh"
ARCHIVE="$BATS_TEST_DIRNAME/../../skills/sprint-archival/archive.sh"

setup() {
  PARENT=$(mktemp -d)            # cwd will be here (the "mother directory")
  PROJ="$PARENT/proj"            # the target project subdir
  mkdir -p "$PROJ"
  git -C "$PROJ" init -q
}
teardown() { rm -rf "$PARENT"; }

@test "onboard honors SDLC_PROJECT_ROOT (scaffolds the target, not cwd)" {
  cd "$PARENT"
  SDLC_PROJECT_ROOT="$PROJ" run bash "$ONBOARD"
  [ "$status" -eq 0 ]
  [ -d "$PROJ/docs/superpowers" ]          # scaffolded in the target
  [ ! -d "$PARENT/docs/superpowers" ]      # NOT in the parent/cwd
}

@test "positional arg still wins over SDLC_PROJECT_ROOT" {
  cd "$PARENT"
  other="$PARENT/other"; mkdir -p "$other"; git -C "$other" init -q
  SDLC_PROJECT_ROOT="$PROJ" run bash "$ONBOARD" "$other"
  [ "$status" -eq 0 ]
  [ -d "$other/docs/superpowers" ]
}

@test "doctor honors SDLC_PROJECT_ROOT" {
  bash "$ONBOARD" "$PROJ" >/dev/null
  cd "$PARENT"
  SDLC_PROJECT_ROOT="$PROJ" run bash "$DOCTOR"
  echo "$output" | grep -qiE "READY|PASS"     # it inspected the target, not the empty parent
}

@test "ga-tag-guard honors SDLC_PROJECT_ROOT (guards the target repo from a parent cwd)" {
  mkdir -p "$PROJ/.sdlc"; : > "$PROJ/.sdlc/state.json"
  printf '{"tool_name":"Bash","tool_input":{"command":"git tag v1.0.0"}}' > "$PARENT/in.json"
  cd "$PARENT"
  SDLC_PROJECT_ROOT="$PROJ" run bash "$GUARD" < in.json
  [ "$status" -eq 2 ]                          # blocked, even though cwd (parent) has no state
}

@test "ga-tag-guard: parent cwd alone (no SDLC_PROJECT_ROOT, no state) → no-op allow" {
  printf '{"tool_name":"Bash","tool_input":{"command":"git tag v1.0.0"}}' > "$PARENT/in.json"
  cd "$PARENT"
  run bash "$GUARD" < in.json
  [ "$status" -eq 0 ]
}

@test "archive honors SDLC_PROJECT_ROOT (archives the target's plan from a parent cwd)" {
  mkdir -p "$PROJ/docs/superpowers/plans"
  : > "$PROJ/docs/superpowers/plans/2026-01-01-x.md"
  cd "$PARENT"
  SDLC_PROJECT_ROOT="$PROJ" run bash "$ARCHIVE" --sprint 2026-01-01-x --apply
  [ "$status" -eq 0 ]
  [ ! -f "$PROJ/docs/superpowers/plans/2026-01-01-x.md" ]   # deleted in the target
}

# bug2 (dogfood 2026-06-05): the granular agent-dispatching commands must document
# --project / SDLC_PROJECT_ROOT, not just /sdlc:run + /sdlc:status. Without this, a
# cross-project granular run (parent cwd, target subdir project) silently used the cwd.
@test "granular commands document --project + SDLC_PROJECT_ROOT (bug2)" {
  CMDROOT="$BATS_TEST_DIRNAME/../../commands"
  for c in spec plan impl review test status; do
    f="$CMDROOT/$c.md"
    [ -f "$f" ] || { echo "missing $f" >&2; return 1; }
    grep -q -- "--project" "$f"        || { echo "$c.md: no --project in body" >&2; return 1; }
    grep -q "SDLC_PROJECT_ROOT" "$f"   || { echo "$c.md: no SDLC_PROJECT_ROOT" >&2; return 1; }
    head -5 "$f" | grep -q -- "--project" || { echo "$c.md: --project not in argument-hint" >&2; return 1; }
  done
}
