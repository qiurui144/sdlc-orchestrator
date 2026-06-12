#!/usr/bin/env bats
A="$BATS_TEST_DIRNAME/../../agents"
@test "tester.md wires web-ui-verify + Chrome E2E + MCP-degrade" {
  run awk '/web-ui-verify/{a=1} /[Cc]hrome/{b=1} /UI-UNVERIFIED|degrade/{c=1} END{exit (a&&b&&c)?0:1}' "$A/tester.md"
  [ "$status" -eq 0 ]
}
@test "releaser.md maps ui_verified unverified→Known Limitation + blocks GA on false" {
  run awk '/ui_verified/{a=1} /[Kk]nown [Ll]imitation/{b=1} /BLOCK|block/{c=1} END{exit (a&&b&&c)?0:1}' "$A/releaser.md"
  [ "$status" -eq 0 ]
}
@test "pr-reviewer.md rejects backend-first UI reproduce (§2.2)" {
  run awk '/backend-first|user-first|browser_navigate/{a=1} /§?2\.2/{b=1} END{exit (a&&b)?0:1}' "$A/pr-reviewer.md"
  [ "$status" -eq 0 ]
}
@test "wired agents keep model_tier frontmatter + ≥250 lines" {
  for f in tester releaser pr-reviewer; do
    run awk '/^model_tier: (opus|sonnet|haiku)/{m=1} END{exit m?0:1}' "$A/$f.md"; [ "$status" -eq 0 ]
    run awk 'END{exit (NR>=250)?0:1}' "$A/$f.md"; [ "$status" -eq 0 ]
  done
}
