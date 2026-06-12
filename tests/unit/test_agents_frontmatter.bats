#!/usr/bin/env bats

AGENTS_DIR="$BATS_TEST_DIRNAME/../../agents"

# Validate an agent's YAML frontmatter using pure POSIX tools (awk + grep).
# Previously this used `python3 -c "import yaml"`, which failed on the macOS CI
# runner (no PyYAML installed) — a dev-box dependency coupling (R7). awk extracts
# the first --- … --- block; grep asserts the required keys. No python, no PyYAML,
# no extra dependency beyond what every POSIX shell already has.
fm_check() {
  local file="$1" expected_name="$2" fm
  [ -f "$file" ] || { echo "missing: $file" >&2; return 1; }
  fm=$(awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$file")
  echo "$fm" | grep -qE "^name: ${expected_name}[[:space:]]*$" || { echo "name mismatch in $file" >&2; return 1; }
  echo "$fm" | grep -qE "^description: .+"                     || { echo "no description in $file" >&2; return 1; }
  echo "$fm" | grep -qE "^tools:"                              || { echo "no tools field in $file" >&2; return 1; }
  echo "$fm" | grep -qE "^model_tier: (opus|sonnet|haiku)[[:space:]]*$" || { echo "model_tier invalid/missing in $file" >&2; return 1; }
}

@test "task-orchestrator agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/task-orchestrator.md" "task-orchestrator"
}

@test "spec-analyst agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/spec-analyst.md" "spec-analyst"
}

@test "architect agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/architect.md" "architect"
}

@test "implementer agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/implementer.md" "implementer"
}

@test "pr-reviewer agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/pr-reviewer.md" "pr-reviewer"
}

@test "tester agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/tester.md" "tester"
}

@test "releaser agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/releaser.md" "releaser"
}

@test "docs-curator agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/docs-curator.md" "docs-curator"
}

@test "disk-monitor agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/disk-monitor.md" "disk-monitor"
}

@test "architecture-reviewer agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/architecture-reviewer.md" "architecture-reviewer"
}

@test "performance-analyst agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/performance-analyst.md" "performance-analyst"
}

@test "dependency-auditor agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/dependency-auditor.md" "dependency-auditor"
}

@test "tech-debt-tracker agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/tech-debt-tracker.md" "tech-debt-tracker"
}

@test "incident-responder agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/incident-responder.md" "incident-responder"
}

@test "cicd-designer agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/cicd-designer.md" "cicd-designer"
}

@test "ci-remediator agent present with valid frontmatter" {
  fm_check "$AGENTS_DIR/ci-remediator.md" "ci-remediator"
}
