#!/usr/bin/env bats
# SE risk register catalog consistency: SE1..SE22 contiguous, well-formed (v0.22: +SE21 error-code
# taxonomy, +SE22 structured logging — project-quality requirements the plugin enforces).
SPEC="$BATS_TEST_DIRNAME/../../docs/superpowers/specs/2026-05-28-sdlc-orchestrator.md"

@test "SE catalog is SE1..SE23 contiguous, no duplicates" {
  nums=$(grep -oE '^\| SE[0-9]+ ' "$SPEC" | grep -oE '[0-9]+' | sort -n | tr '\n' ' ')
  exp=$(seq 1 23 | tr '\n' ' ')
  [ "$nums" = "$exp" ]
}
@test "SE21 error-code + SE22 structured-logging + SE23 commit-discipline defined as project requirements" {
  grep -qE '^\| SE21 \|.*error-code' "$SPEC"
  grep -qE '^\| SE22 \|.*(结构化|分级|structured).*日志|^\| SE22 \|.*log' "$SPEC"
  grep -qE '^\| SE23 \|.*commit' "$SPEC"
}
@test "every SE row has 4 content columns + non-empty owner" {
  while IFS= read -r line; do
    cols=$(printf '%s' "$line" | awk -F'|' '{print NF}')
    [ "$cols" -eq 6 ]                                  # leading + 4 content + trailing empty
    owner=$(printf '%s' "$line" | awk -F'|' '{print $4}' | sed 's/^ *//;s/ *$//')
    [ -n "$owner" ]
  done < <(grep -E '^\| SE[0-9]+ ' "$SPEC")
}
@test "SE1..SE12 unchanged (owners intact — regression)" {
  grep -qE '^\| SE1 \|.*architecture-reviewer' "$SPEC"
  grep -qE '^\| SE12 \|.*architecture-reviewer' "$SPEC"
}
@test "CLAUDE.md references SE1-SE23 (no stale SE1-SE12/SE1-SE20)" {
  C="$BATS_TEST_DIRNAME/../../CLAUDE.md"
  grep -qE 'SE1.?SE23|SE1–SE23|SE1-SE23' "$C"
  ! grep -qE 'SE1.?SE12|SE1–SE12|SE1-SE12' "$C"
}
