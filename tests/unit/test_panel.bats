#!/usr/bin/env bats
# panel.sh --consensus — Challenger Panel vote merge. Reuses judge.sh parse_verdict.
PANEL="$BATS_TEST_DIRNAME/../../skills/challenger-panel/panel.sh"
setup() { D=$(mktemp -d); }
teardown() { rm -rf "$D"; }
mkvote() { printf 'VERDICT: %s\nSCORE: %s\nLENS: %s\nREASON: t\n' "$1" "$2" "$3" > "$D/$3.json"; }

@test "3 PASS high scores → AUTO_ADVANCE" {
  mkvote PASS 4 correctness; mkvote PASS 5 security; mkvote PASS 4 rubric
  run bash "$PANEL" --consensus --votes-dir "$D"
  [ "$status" -eq 0 ]; echo "$output" | grep -q "decision=AUTO_ADVANCE"
}
@test "split vote → ESCALATE" {
  mkvote PASS 4 correctness; mkvote FAIL 2 security; mkvote FAIL 3 rubric
  run bash "$PANEL" --consensus --votes-dir "$D"; [ "$status" -eq 1 ]
  echo "$output" | grep -q "decision=ESCALATE"
}
@test "majority PASS but mean below threshold → ESCALATE" {
  mkvote PASS 3 correctness; mkvote PASS 3 security; mkvote FAIL 2 rubric
  run bash "$PANEL" --consensus --votes-dir "$D"; [ "$status" -eq 1 ]
}
@test "high_risk forces ESCALATE even if all PASS" {
  mkvote PASS 5 correctness; mkvote PASS 5 security; mkvote PASS 5 rubric
  run bash "$PANEL" --consensus --votes-dir "$D" --high-risk yes
  [ "$status" -eq 1 ]; echo "$output" | grep -q "reason=high-risk"
}
@test "all malformed → exit 2 (forced ESCALATE)" {
  printf 'garbage\n' > "$D/a.json"; printf 'noise\n' > "$D/b.json"
  run bash "$PANEL" --consensus --votes-dir "$D"; [ "$status" -eq 2 ]
}

@test "dispatch picks size 3 for low-risk artifact" {
  echo "add a helper function" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=no"; echo "$output" | grep -q "size=3"
}
@test "dispatch escalates size to 5 on high-risk keyword" {
  echo "rotate the auth token and run db migration" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=yes"; echo "$output" | grep -q "size=5"
}

# --- high-risk calibration (v0.18): real classes still escalate; documented wrong-sense does not ---

# TRUE POSITIVES — must still escalate (false-negative on these is a security regression).
@test "calib: genuine hardcoded secret still escalates" {
  echo "this hardcodes a secret api_key in the source file" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=yes"
}
@test "calib: authentication change still escalates" {
  echo "this rewrites the authentication and authorization flow" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=yes"
}
@test "calib: data migration still escalates" {
  echo "the change requires a data migration on the users table" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=yes"
}
@test "calib: irreversible prod deploy still escalates" {
  echo "the production deploy is irreversible without a backup" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=yes"
}
@test "calib: STRIDE spoofing still escalates" {
  echo "STRIDE: a spoofing and tampering risk on the boundary" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=yes"
}
@test "calib: access token in plaintext still escalates" {
  echo "stores the access token in plaintext on disk" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=yes"
}
@test "calib: breaking API change still escalates" {
  echo "this is a breaking api change for old clients" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=yes"
}

# TRUE NEGATIVES — documented wrong-sense must NOT escalate (the recurring false-positive class).
@test "calib: 'author' word does not escalate (was matched by bare auth)" {
  echo "author: jane doe reviewed the change log" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=no"
}
@test "calib: LLM token budget does not escalate" {
  echo "the token budget is 500k and token cost stays low" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=no"
}
@test "calib: CI secrets ref placeholder does not escalate" {
  printf 'use ${{ secrets.PUBLISH_TOKEN }} in the workflow; key is your-key-here\n' > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=no"
}
@test "calib: handoff schema mention does not escalate" {
  echo "validates the handoff schema version field" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=no"
}
@test "calib: 'no migration needed' does not escalate" {
  echo "no migration needed; this is a non-breaking change" > "$D/art.md"
  run bash "$PANEL" --dispatch --artifact "$D/art.md" --handoff /dev/null
  echo "$output" | grep -q "high_risk=no"
}
