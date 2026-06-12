#!/usr/bin/env bats
# doc-audit.sh (v0.19.1): deterministic §3.2 doc-structure auditor. Root overridable via SDLC_DOC_ROOT.
A="$BATS_TEST_DIRNAME/../../scripts/doc-audit.sh"

setup() { R=$(mktemp -d); : > "$R/README.md"; : > "$R/CLAUDE.md"; mkdir -p "$R/docs"; }
teardown() { rm -rf "$R"; }
audit() { SDLC_DOC_ROOT="$R" run bash "$A" "$@"; }

@test "clean repo → CLEAN, exit 0" {
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CLEAN"
}

@test "off-whitelist root .md → finding" {
  : > "$R/RANDOM-NOTES.md"
  audit
  echo "$output" | grep -q "off-whitelist root doc: RANDOM-NOTES.md"
}

@test "whitelisted root docs do not trip" {
  : > "$R/DEVELOP.md"; : > "$R/RELEASE.md"; : > "$R/README.zh.md"
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CLEAN"
}

@test "stray .zh.md outside root README → finding" {
  : > "$R/docs/GUIDE.zh.md"
  audit
  echo "$output" | grep -q "stray bilingual file"
}

@test "root README.zh.md does NOT trip the .zh.md check" {
  : > "$R/README.zh.md"
  audit
  [ "$status" -eq 0 ]
}

@test "one-shot residue under docs/ → finding" {
  : > "$R/docs/v0.9-sprint-report.md"
  audit
  echo "$output" | grep -q "one-shot residue"
}

@test "lingering plan → finding" {
  mkdir -p "$R/docs/superpowers/plans"; : > "$R/docs/superpowers/plans/2026-01-01-x.md"
  audit
  echo "$output" | grep -q "plan file(s) present"
}

@test "--strict exits 1 on findings" {
  : > "$R/STRAY.md"
  audit --strict
  [ "$status" -eq 1 ]
}

@test "default (non-strict) exits 0 even with findings (advisory)" {
  : > "$R/STRAY.md"
  audit
  [ "$status" -eq 0 ]
}
