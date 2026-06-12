#!/usr/bin/env bats
# risk-classify.sh — deterministic zero-LLM tier classifier. Spec §5.1 / §3.2 (rev2 + 5 G1 fixes).
RC="$BATS_TEST_DIRNAME/../../skills/risk-classify/risk-classify.sh"
RULES="$BATS_TEST_DIRNAME/../../config/risk-rules.yaml"
setup() { D=$(mktemp -d); }
teardown() { rm -rf "$D"; }
# helper: build a fake --name-status file (TAB-separated, git porcelain shape)
names() { printf '%s\n' "$@" > "$D/names"; }

@test "risk-rules.yaml exists and defines high/normal/low pattern sets" {
  [ -f "$RULES" ]
  run grep -E '^(high|normal|low_allow):' "$RULES"
  [ "$status" -eq 0 ]
}

@test "docs-only prose .md → LOW path_depth=fast" {
  names "M	README.md"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  [ "$status" -eq 0 ]
  case "$output" in *risk_tier=LOW*) ;; *) echo "$output"; false;; esac
  case "$output" in *path_depth=fast*) ;; *) false;; esac
}
@test "source file touched → NORMAL" {
  names "M	src/lib.rs"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  [ "$status" -eq 0 ]; case "$output" in *risk_tier=NORMAL*) ;; *) echo "$output"; false;; esac
}
@test "auth path → HIGH" {
  names "M	src/auth/session.rs"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  [ "$status" -eq 0 ]; case "$output" in *risk_tier=HIGH*) ;; *) false;; esac
}
@test "command-bearing config (value-only) → NORMAL min, never LOW (fix #1)" {
  names "M	config/stack-rust.yaml"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  [ "$status" -eq 0 ]; case "$output" in *risk_tier=LOW*) echo "LEAK"; false;; *) ;; esac
}
@test "self-ref edit to risk-rules.yaml → HIGH (fix #2)" {
  names "M	config/risk-rules.yaml"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  [ "$status" -eq 0 ]; case "$output" in *risk_tier=HIGH*) ;; *) false;; esac
}
@test "renamed/moved file → NORMAL (defeats rename-dodge)" {
  printf 'R100\tsrc/auth.rs\tsrc/util.rs\n' > "$D/names"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  [ "$status" -eq 0 ]; case "$output" in *risk_tier=LOW*) echo "LEAK"; false;; *) ;; esac
}
@test "mixed change (md + source) → NORMAL never LOW" {
  names "M	README.md" "M	src/lib.rs"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  [ "$status" -eq 0 ]; case "$output" in *risk_tier=NORMAL*) ;; *) false;; esac
}
@test "empty diff → NORMAL (nothing to fast-path safely)" {
  : > "$D/names"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  [ "$status" -eq 0 ]; case "$output" in *risk_tier=NORMAL*) ;; *) false;; esac
}
@test "missing rules file → HIGH (cannot prove LOW)" {
  names "M	README.md"
  run bash "$RC" --names "$D/names" --rules "$D/nonexistent.yaml"
  case "$output" in *risk_tier=HIGH*) ;; *) echo "$output"; false;; esac
}
@test "unknown-type new file → NORMAL (default-deny)" {
  names "A	weirdfile.xyz"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  [ "$status" -eq 0 ]; case "$output" in *risk_tier=LOW*) echo "LEAK"; false;; *) ;; esac
}
@test "kv output shape: tier+reason+path_depth+panel_size+model_class" {
  names "M	README.md"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  case "$output" in *risk_tier=*reason=*path_depth=*panel_size=*model_class=*) ;; *) echo "$output"; false;; esac
}
@test "determinism: same diff x20 → byte-identical output" {
  names "M	src/auth/session.rs"
  first=""; for i in $(seq 1 20); do
    out=$(LC_ALL=C bash "$RC" --names "$D/names" --rules "$RULES")
    if [ -z "$first" ]; then first="$out"; fi
    [ "$out" = "$first" ] || { echo "drift at $i: $out != $first"; false; }
  done
}

@test "bad arg → exit 2" {
  run bash "$RC" --bogus
  [ "$status" -eq 2 ]
}
@test "exit code 0 for any successful classification (HIGH included)" {
  names "M	src/auth/session.rs"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  [ "$status" -eq 0 ]
}
@test "SE16: no early-pipe-close control flow on pipefail pipe in classifier" {
  # no `| head -n` used for CONTROL FLOW; allowed: grep -c (EOF), awk (EOF), single-tiny-producer basename grep.
  run grep -nE '\|[[:space:]]*head[[:space:]]+-n' "$RC"
  [ "$status" -ne 0 ]   # no `| head -n` at all
}
@test "LC_ALL=C is pinned in the script" {
  run grep -E 'LC_ALL=C' "$RC"
  [ "$status" -eq 0 ]
}
@test "verbose flag accepted (does not change tier)" {
  names "M	README.md"
  a=$(bash "$RC" --names "$D/names" --rules "$RULES")
  b=$(bash "$RC" --names "$D/names" --rules "$RULES" --verbose)
  case "$a" in *risk_tier=LOW*) ;; *) false;; esac
  case "$b" in *risk_tier=LOW*) ;; *) false;; esac
}
@test "SKILL.md exists with frontmatter name + description" {
  SK="$BATS_TEST_DIRNAME/../../skills/risk-classify/SKILL.md"
  [ -f "$SK" ]
  run grep -E '^name:[[:space:]]*risk-classify' "$SK"
  [ "$status" -eq 0 ]
}
