#!/usr/bin/env bats
# lang.sh — i18n resolve + message catalog lookup (v0.13).
L="$BATS_TEST_DIRNAME/../../skills/i18n/lang.sh"
CATALOG_REAL="$BATS_TEST_DIRNAME/../../skills/i18n/messages.tsv"
setup() {
  export SDLC_I18N_CATALOG=$(mktemp)
  printf 'gate.advance\tAdvancing\t推进\n'      >> "$SDLC_I18N_CATALOG"
  printf '# a comment line\tx\ty\n'             >> "$SDLC_I18N_CATALOG"
  printf 'status.next\tRecommended next\t建议下一步\n' >> "$SDLC_I18N_CATALOG"
  printf 'empty.zh\tOnlyEnglish\t\n'            >> "$SDLC_I18N_CATALOG"
}
teardown() { rm -f "$SDLC_I18N_CATALOG"; }

@test "lang resolves zh / en / bilingual verbatim" {
  [ "$(SDLC_LANG=zh bash "$L" lang)" = "zh" ]
  [ "$(SDLC_LANG=en bash "$L" lang)" = "en" ]
  [ "$(SDLC_LANG=bilingual bash "$L" lang)" = "bilingual" ]
}
@test "lang defaults to en when unset" {
  run env -u SDLC_LANG bash "$L" lang
  [ "$output" = "en" ]
}
@test "lang falls back to en on invalid value" {
  [ "$(SDLC_LANG=fr bash "$L" lang)" = "en" ]
}
@test "msg returns en column under en" {
  [ "$(SDLC_LANG=en bash "$L" msg gate.advance)" = "Advancing" ]
}
@test "msg returns zh column under zh" {
  [ "$(SDLC_LANG=zh bash "$L" msg gate.advance)" = "推进" ]
}
@test "msg returns 'en / zh' under bilingual" {
  [ "$(SDLC_LANG=bilingual bash "$L" msg gate.advance)" = "Advancing / 推进" ]
}
@test "msg unknown key echoes the key (graceful, exit 0)" {
  run bash "$L" msg no.such.key
  [ "$status" -eq 0 ]
  [ "$output" = "no.such.key" ]
}
@test "msg missing key arg → exit 2" {
  run bash "$L" msg
  [ "$status" -eq 2 ]
}
@test "msg under zh with empty zh column falls back to en" {
  [ "$(SDLC_LANG=zh bash "$L" msg empty.zh)" = "OnlyEnglish" ]
}
@test "msg bilingual with empty zh shows en only (no trailing ' / ') [G2 fold-in]" {
  [ "$(SDLC_LANG=bilingual bash "$L" msg empty.zh)" = "OnlyEnglish" ]
}
@test "comment lines are not matched as keys" {
  run bash "$L" msg "# a comment line"
  [ "$output" = "# a comment line" ]
}
@test "missing catalog → msg echoes key (degrade, no crash)" {
  run env SDLC_I18N_CATALOG=/nonexistent/xx bash "$L" msg gate.advance
  [ "$status" -eq 0 ]
  [ "$output" = "gate.advance" ]
}
@test "adversarial: key with shell metachars is treated as a literal, not executed" {
  run bash "$L" msg 'a;touch PWNED $(id)'
  [ "$status" -eq 0 ]
  [ ! -e PWNED ]
  echo "$output" | grep -q 'a;touch PWNED'
}
@test "bad subcommand → exit 2" {
  run bash "$L" frobnicate
  [ "$status" -eq 2 ]
}
@test "key that is a substring of another is not mismatched (exact match)" {
  printf 'status\tBARE\t裸\n' >> "$SDLC_I18N_CATALOG"
  [ "$(SDLC_LANG=en bash "$L" msg status)" = "BARE" ]
  [ "$(SDLC_LANG=en bash "$L" msg status.next)" = "Recommended next" ]
}
@test "shipped messages.tsv is well-formed (3 tab fields per non-comment line) [G2 fold-in]" {
  # every non-comment, non-blank line must have exactly 2 tabs (key<TAB>en<TAB>zh-or-empty)
  bad=$(awk -F'\t' '!/^#/ && NF>0 && NF!=3 {print NR": "NF" fields"}' "$CATALOG_REAL")
  [ -z "$bad" ]
  # a real shipped key resolves via the DEFAULT catalog (not the test fixture)
  run env -u SDLC_I18N_CATALOG SDLC_LANG=zh bash "$L" msg gate.advance
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" != "gate.advance" ]   # resolved to a real translation, not the key fallback
}

@test "SKILL.md documents SDLC_LANG + human-facing-only boundary + default en" {
  S="$BATS_TEST_DIRNAME/../../skills/i18n/SKILL.md"
  grep -qE "SDLC_LANG" "$S"
  grep -qiE "human-facing|technical token|identifier" "$S"
  grep -qiE "default.*en|en.*default|opt-in" "$S"
}
@test "task-orchestrator documents output language via SDLC_LANG / lang.sh" {
  T="$BATS_TEST_DIRNAME/../../agents/task-orchestrator.md"
  grep -qE "SDLC_LANG" "$T"
  grep -qiE "lang.sh|i18n" "$T"
}
