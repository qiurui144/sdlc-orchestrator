#!/usr/bin/env bats

CONS="$BATS_TEST_DIRNAME/../../skills/intake-consolidation/consolidate.sh"
FIX="$BATS_TEST_DIRNAME/../fixtures/intake"

@test "mixed (BLOCK present) → overall AT-RISK + P0 line" {
  src="$FIX/reports-mixed"; work=$(mktemp -d); trap "rm -rf $work" EXIT
  cp "$src"/*.md "$work"/
  run "$CONS" "$work" "$work/project-health.md"
  [ "$status" -eq 0 ]
  grep -q '## Overall verdict: AT-RISK' "$work/project-health.md"
  grep -q '\*\*P0\*\* \[deps\]' "$work/project-health.md"
  grep -q '| deps | BLOCK | 0.40 |' "$work/project-health.md"
  grep -q '\*\*P2\*\* \[debt\]' "$work/project-health.md"
}

@test "no BLOCK but a FAIL → NEEDS-ATTENTION" {
  work=$(mktemp -d); trap "rm -rf $work" EXIT
  printf '<!-- sdlc-intake: dim=review verdict=FAIL score=0.5 top="null deref" -->\n' > "$work/2026-06-01_review.md"
  printf '<!-- sdlc-intake: dim=docs verdict=PASS score=1.0 top="ok" -->\n'        > "$work/2026-06-01_docs.md"
  run "$CONS" "$work" "$work/h.md"
  [ "$status" -eq 0 ]
  grep -q '## Overall verdict: NEEDS-ATTENTION' "$work/h.md"
}

@test "all PASS → HEALTHY" {
  work=$(mktemp -d); trap "rm -rf $work" EXIT
  printf '<!-- sdlc-intake: dim=docs verdict=PASS score=1.0 top="ok" -->\n' > "$work/2026-06-01_docs.md"
  run "$CONS" "$work" "$work/h.md"
  grep -q '## Overall verdict: HEALTHY' "$work/h.md"
  ! grep -q 'low-signal' "$work/h.md"
}

@test "empty dir → HEALTHY (low-signal)" {
  work=$(mktemp -d); trap "rm -rf $work" EXIT
  run "$CONS" "$work" "$work/h.md"
  [ "$status" -eq 0 ]
  grep -q 'HEALTHY (low-signal)' "$work/h.md"
}

@test "a pipe char in top does not corrupt the scorecard row" {
  work=$(mktemp -d); trap "rm -rf $work" EXIT
  printf '<!-- sdlc-intake: dim=deps verdict=PASS score=1.0 top="a|b|c summary" -->\n' > "$work/2026-06-01_deps.md"
  run "$CONS" "$work" "$work/h.md"
  [ "$status" -eq 0 ]
  # the deps row must still parse cleanly: dim=deps verdict=PASS score=1.0, and the link present
  grep -q '| deps | PASS | 1.0 |' "$work/h.md"
  grep -q '\[deps\](./2026-06-01_deps.md)' "$work/h.md"
}

@test "renders metadata from intake-meta.env when present" {
  work=$(mktemp -d); trap "rm -rf $work" EXIT
  printf '<!-- sdlc-intake: dim=docs verdict=PASS score=1.0 top="ok" -->\n' > "$work/2026-06-01_docs.md"
  printf 'depth=standard\ntokens=12345\n' > "$work/intake-meta.env"
  run "$CONS" "$work" "$work/h.md"
  grep -q -- '- depth: standard' "$work/h.md"
  grep -q -- '- tokens: 12345' "$work/h.md"
}
