#!/usr/bin/env bats
# doc-audit.sh content checks [6][7][8] (v0.24.0): zero-false-positive mechanical content gate.
# Root overridable via SDLC_DOC_ROOT; fixtures are bats temp dirs (mirrors test_doc_audit.bats).
A="$BATS_TEST_DIRNAME/../../scripts/doc-audit.sh"

# Build a minimal plugin-shaped fixture with N agents / M skills / K commands / J hooks and a
# README prose count line + plugin.json .description carrying the declared tuple.
# Args: declared_agents declared_skills declared_commands declared_hooks  (declared values in docs)
#       real_agents real_skills real_commands  (FS counts to create)
make_plugin() {
  da=$1; ds=$2; dc=$3; dh=$4; ra=$5; rs=$6; rc=$7
  mkdir -p "$R/.claude-plugin" "$R/agents" "$R/skills" "$R/commands" "$R/hooks"
  i=0; while [ "$i" -lt "$ra" ]; do : > "$R/agents/a$i.md"; i=$((i+1)); done
  i=0; while [ "$i" -lt "$rs" ]; do mkdir -p "$R/skills/s$i"; : > "$R/skills/s$i/SKILL.md"; i=$((i+1)); done
  i=0; while [ "$i" -lt "$rc" ]; do : > "$R/commands/c$i.md"; i=$((i+1)); done
  # 3 real hook entries (top-level keys)
  printf '{"hooks":{"PostToolUse":[],"Stop":[],"PreToolUse":[]}}\n' > "$R/hooks/hooks.json"
  printf '{"version":"1.0.0","description":"x: %s agents, %s skills, %s slash commands, %s hooks. y."}\n' \
    "$da" "$ds" "$dc" "$dh" > "$R/.claude-plugin/plugin.json"
  # README prose count line (kept on ONE line here unless a test overrides)
  printf '# x\n\nFoo **%s agents, %s skills, %s slash commands, %s hooks**. Bar.\n' \
    "$da" "$ds" "$dc" "$dh" > "$R/README.md"
  : > "$R/CLAUDE.md"
}

setup() { R=$(mktemp -d); }
teardown() { rm -rf "$R"; }
audit() { SDLC_DOC_ROOT="$R" run bash "$A" "$@"; }

@test "[6] happy: declared tuple matches FS → no inventory finding" {
  make_plugin 2 3 4 3 2 3 4
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "inventory drift" || { echo "$output"; false; }
}

@test "[6] drift counts (plugin.json): fs has 5 commands, json says 4 → strict fail" {
  make_plugin 2 3 4 3 2 3 5   # real commands = 5, declared = 4
  audit --strict
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "inventory drift (plugin.json): commands says 4, fs has 5"
}

@test "[6] drift counts (README): fs has 3 agents, README says 2 → strict fail" {
  make_plugin 2 3 4 3 3 3 4   # real agents = 3, declared = 2
  audit --strict
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "inventory drift (README): agents says 2, fs has 3"
}

@test "[6] count line vs Status table: parser reads prose line, ignores OLD table" {
  make_plugin 2 3 4 3 2 3 4
  # Append a Status table with WRONG old counts; must NOT be parsed.
  cat >> "$R/README.md" <<'EOF'

## Status

| Version | Agents | Skills | Commands | Hooks |
|---------|--------|--------|----------|-------|
| v0.1.0  | 99     | 99     | 99       | 99    |
EOF
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "inventory drift" || { echo "$output"; false; }
}

@test "[6] adversarial extra number: stray '5 adapters' ignored, tuple parsed" {
  make_plugin 2 3 4 3 2 3 4
  printf '# x\n\nAcross 5 adapters, **2 agents, 3 skills, 4 slash commands, 3 hooks**.\n' > "$R/README.md"
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "inventory drift" || { echo "$output"; false; }
}

@test "[6] non-plugin repo: no plugin.json → [6] skipped, no inventory finding" {
  mkdir -p "$R/docs"; : > "$R/README.md"; : > "$R/CLAUDE.md"
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "inventory drift" || { echo "$output"; false; }
}

@test "[7] dangling command ref: README mentions /sdlc:ghost, no commands/ghost.md → strict fail" {
  make_plugin 2 3 4 3 2 3 4
  printf '# x\n\nRun /sdlc:c0 then /sdlc:ghost.\n' >> "$R/README.md"
  audit --strict
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "dangling command ref: /sdlc:ghost"
}

@test "[7] all refs resolve: /sdlc:c0 has commands/c0.md → no dangling finding" {
  make_plugin 2 3 4 3 2 3 4
  printf '# x\n\nRun /sdlc:c0 to start.\n' >> "$R/README.md"
  audit
  echo "$output" | grep -qv "dangling command ref" || { echo "$output"; false; }
}

@test "[7] placeholder /sdlc:<cmd> with angle brackets is not flagged" {
  make_plugin 2 3 4 3 2 3 4
  printf '# x\n\nUsage: /sdlc:<cmd> <args>.\n' >> "$R/README.md"
  audit
  echo "$output" | grep -qv "dangling command ref" || { echo "$output"; false; }
}

@test "[8] plugin anchor match: CLAUDE.md Shipped through **v1.0.0** == plugin.json 1.0.0" {
  make_plugin 2 3 4 3 2 3 4   # plugin.json .version = 1.0.0 (make_plugin pins it)
  printf '> Shipped through **v1.0.0** (date): notes;\n' > "$R/CLAUDE.md"
  audit
  echo "$output" | grep -qv "stale version anchor" || { echo "$output"; false; }
}

@test "[8] plugin anchor stale: CLAUDE.md v0.9.0 vs plugin.json 1.0.0 → strict fail" {
  make_plugin 2 3 4 3 2 3 4
  printf '> Shipped through **v0.9.0** (date): notes;\n' > "$R/CLAUDE.md"
  audit --strict
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "stale version anchor: CLAUDE.md says 0.9.0, source .claude-plugin/plugin.json = 1.0.0"
}

@test "[8] plugin anchor absent: no Shipped-through line → advisory skip, no hard fail from [8]" {
  make_plugin 2 3 4 3 2 3 4
  printf '# CLAUDE\nNo anchor here.\n' > "$R/CLAUDE.md"
  audit --strict
  # [8] itself must not hard-fail; the only possible finding here is the advisory note (non-counting).
  echo "$output" | grep -q "canonical anchor line absent"
  echo "$output" | grep -qv "stale version anchor" || { echo "$output"; false; }
}

@test "[8] generic marker stale: non-plugin repo, marker line 1.2.0 vs Cargo.toml 1.3.0 → strict fail" {
  mkdir -p "$R/docs"; : > "$R/README.md"; : > "$R/CLAUDE.md"
  printf 'version = "1.3.0"\n' > "$R/Cargo.toml"
  printf 'pin: 1.2.0 <!-- sdlc:version -->\n' > "$R/docs/INSTALL.md"
  audit --strict
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "stale version anchor"
  echo "$output" | grep -q "source Cargo.toml = 1.3.0"
}

@test "[8] generic no marker: non-plugin repo, no marker anywhere → silent skip, exit 0" {
  mkdir -p "$R/docs"; : > "$R/README.md"; : > "$R/CLAUDE.md"
  printf 'version = "1.3.0"\n' > "$R/Cargo.toml"
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "stale version anchor" || { echo "$output"; false; }
}

@test "[9] all commands referenced: every commands/cN.md in README → no finding" {
  make_plugin 2 3 4 3 2 3 4
  printf '# x\n\nRun /sdlc:c0 /sdlc:c1 /sdlc:c2 /sdlc:c3 to start.\n' > "$R/README.md"
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "command not in README" || { echo "$output"; false; }
}

@test "[9] command missing from README → strict fail with exact finding" {
  make_plugin 2 3 4 3 2 3 4
  # README references only c0..c2; commands/c3.md exists but is uncatalogued.
  printf '# x\n\nRun /sdlc:c0 /sdlc:c1 /sdlc:c2.\n' > "$R/README.md"
  audit --strict
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "command not in README: /sdlc:c3"
}

@test "[9] mention inside a fenced code block counts as referenced (edge E1)" {
  make_plugin 2 3 4 3 2 3 4
  # c0..c2 in prose; c3 ONLY inside a fenced code block → still 'listed'.
  { printf '# x\n\nRun /sdlc:c0 /sdlc:c1 /sdlc:c2.\n\n'; printf '```\n/sdlc:c3 --flag\n```\n'; } > "$R/README.md"
  audit
  echo "$output" | grep -qv "command not in README: /sdlc:c3" || { echo "$output"; false; }
}

@test "[9] exemption: uncatalogued command on .sdlc/doc-audit-allow → no finding" {
  make_plugin 2 3 4 3 2 3 4
  printf '# x\n\nRun /sdlc:c0 /sdlc:c1 /sdlc:c2.\n' > "$R/README.md"
  mkdir -p "$R/.sdlc"
  printf '# internal-only\n/sdlc:c3\n' > "$R/.sdlc/doc-audit-allow"
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "command not in README: /sdlc:c3" || { echo "$output"; false; }
}

@test "[9] exemption honors a bare <cmd> token (no /sdlc: prefix)" {
  make_plugin 2 3 4 3 2 3 4
  printf '# x\n\nRun /sdlc:c0 /sdlc:c1 /sdlc:c2.\n' > "$R/README.md"
  mkdir -p "$R/.sdlc"
  printf 'c3\n' > "$R/.sdlc/doc-audit-allow"
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "command not in README: /sdlc:c3" || { echo "$output"; false; }
}

@test "[9] non-plugin repo: no plugin.json → [9] skipped, no finding" {
  mkdir -p "$R/docs"; : > "$R/README.md"; : > "$R/CLAUDE.md"
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "command not in README" || { echo "$output"; false; }
}

@test "[10] zh tuple matches en tuple → no finding" {
  make_plugin 2 3 4 3 2 3 4
  printf '# x\n\n面向 Claude Code:**2 个 agent、3 个 skill、4 个斜杠命令、3 个 hook**。\n' > "$R/README.zh.md"
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "bilingual count drift" || { echo "$output"; false; }
}

@test "[10] zh commands count drifts (zh says 26, en says 27-style: 4 vs 5) → strict fail" {
  make_plugin 2 3 5 3 2 3 5   # en/FS commands = 5
  # zh README declares only 4 斜杠命令 → drift.
  printf '# x\n\n**2 个 agent、3 个 skill、4 个斜杠命令、3 个 hook**。\n' > "$R/README.zh.md"
  audit --strict
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "bilingual count drift (README.zh): commands says 4, README.md says 5"
}

@test "[10] no README.zh.md → [10] silently skipped (E2)" {
  make_plugin 2 3 4 3 2 3 4
  printf '# x\n\nRun /sdlc:c0 /sdlc:c1 /sdlc:c2 /sdlc:c3.\n' > "$R/README.md"
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "bilingual count drift" || { echo "$output"; false; }
}

# NB: the @test NAME must stay ASCII — bats on macOS mangles CJK in a test NAME into a bad
# function name ("unknown test name" → the test aborts: "Executed N-1 instead of N"). The Chinese
# stays in the test BODY (fixtures) where bats handles bytes fine. This was the v0.26.2 macOS fix.
@test "[10] adversarial: stray later CJK commands-word prose does not corrupt the bound count (E5/T5)" {
  make_plugin 2 3 4 3 2 3 4
  { printf '# x\n\n**2 个 agent、3 个 skill、4 个斜杠命令、3 个 hook**。\n\n'; \
    printf '后文又提到 斜杠命令 的用法,但不带数字。\n'; } > "$R/README.zh.md"
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "bilingual count drift" || { echo "$output"; false; }
}

@test "[10] zh kind word missing entirely → that kind skipped, not flagged (E5)" {
  make_plugin 2 3 4 3 2 3 4
  # zh omits hooks entirely; the other three match. Empty parsed value → skip (no false-positive).
  printf '# x\n\n**2 个 agent、3 个 skill、4 个斜杠命令**。\n' > "$R/README.zh.md"
  audit
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "bilingual count drift" || { echo "$output"; false; }
}

@test "META [9]+[10]: THIS repo tracked tree emits neither new finding kind (commands all listed; zh==en)" {
  REPO="$BATS_TEST_DIRNAME/../.."
  EXPORT=$(mktemp -d)
  ( cd "$REPO" && git ls-files -z | tar --null -T - -cf - ) | tar -x -C "$EXPORT"
  SDLC_DOC_ROOT="$EXPORT" run bash "$EXPORT/scripts/doc-audit.sh" --strict
  rm -rf "$EXPORT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "command not in README" || { echo "$output"; false; }
  echo "$output" | grep -qv "bilingual count drift" || { echo "$output"; false; }
}

@test "header comment documents checks (9) and (10)" {
  # Both checks must be documented within the header 'Checks' comment paragraph (lines 8-14),
  # not in the inline block comments much further down. NR<=14 = the header comment region.
  A="$BATS_TEST_DIRNAME/../../scripts/doc-audit.sh"
  run awk 'NR<=14 && /\(9\)/{a=1} NR<=14 && /\(10\)/{b=1} END{exit (a&&b)?0:1}' "$A"
  [ "$status" -eq 0 ]
}

@test "E1 guard: ci.yml still invokes doc-audit.sh --strict (E1 cannot silently regress)" {
  CI="$BATS_TEST_DIRNAME/../../.github/workflows/ci.yml"
  run awk '/doc-audit\.sh --strict/{f=1} END{exit f?0:1}' "$CI"
  [ "$status" -eq 0 ]
}

@test "E2 wiring: releaser.md and docs-curator.md reference doc-audit.sh --strict" {
  RL="$BATS_TEST_DIRNAME/../../agents/releaser.md"
  DC="$BATS_TEST_DIRNAME/../../agents/docs-curator.md"
  run awk '/doc-audit\.sh --strict/{f=1} END{exit f?0:1}' "$RL"
  [ "$status" -eq 0 ]
  run awk '/doc-audit\.sh --strict/{f=1} END{exit f?0:1}' "$DC"
  [ "$status" -eq 0 ]
}

@test "META dogfood: doc-audit.sh --strict on THIS repo (tracked tree) → exit 0 (CLEAN)" {
  # Dogfood the gate against the TRACKED working tree (the files CI sees on a fresh checkout),
  # mirroring my current edits. We materialize tracked files into a temp export so transient
  # UNTRACKED sprint scaffolding (e.g. the in-flight docs/superpowers/plans/<sprint>.md, which
  # [4] correctly flags and which is deleted at sprint archival per §3.2) does not mask the
  # committed-state proof. This is what /sdlc:release Gate 1 and ci.yml enforce.
  REPO="$BATS_TEST_DIRNAME/../.."
  EXPORT=$(mktemp -d)
  ( cd "$REPO" && git ls-files -z | tar --null -T - -cf - ) | tar -x -C "$EXPORT"
  SDLC_DOC_ROOT="$EXPORT" run bash "$EXPORT/scripts/doc-audit.sh" --strict
  rm -rf "$EXPORT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CLEAN"
}

@test "[11] dangling-spec gate: a ## Linked ref to a non-existent dated spec → flagged" {
  T=$(mktemp -d); trap "rm -rf $T" EXIT
  mkdir -p "$T/skills/x"
  printf '## Linked\n- spec docs/superpowers/specs/2026-01-01-ghost.md\n' > "$T/skills/x/SKILL.md"
  SDLC_DOC_ROOT="$T" run bash "$BATS_TEST_DIRNAME/../../scripts/doc-audit.sh"
  echo "$output" | grep -q "dangling doc ref: docs/superpowers/specs/2026-01-01-ghost.md"
}

@test "[11] no false positive: existing dated spec + generic output-doc ref → NOT flagged" {
  T=$(mktemp -d); trap "rm -rf $T" EXIT
  mkdir -p "$T/skills/x" "$T/docs/superpowers/specs"
  : > "$T/docs/superpowers/specs/2026-01-01-real.md"
  printf '## Linked\n- spec docs/superpowers/specs/2026-01-01-real.md\n- produces docs/cicd-strategy.md\n' > "$T/skills/x/SKILL.md"
  SDLC_DOC_ROOT="$T" run bash "$BATS_TEST_DIRNAME/../../scripts/doc-audit.sh"
  ! echo "$output" | grep -q "dangling doc ref"
}
