#!/usr/bin/env bats
# Structural integrity guard. Mechanically prevents the class of defect found in
# v0.2.2 review: plugin.json was at the repo root, but Claude Code loads the
# manifest from .claude-plugin/plugin.json (258 of 263 official plugins use that
# path). With the manifest misplaced, the plugin never loads — so every agent
# would be dead weight. This test fails loudly if the structure regresses.

ROOT="$BATS_TEST_DIRNAME/../.."

@test "manifest lives at .claude-plugin/plugin.json (Claude Code load path)" {
  [ -f "$ROOT/.claude-plugin/plugin.json" ]
}

@test "no stray plugin.json at repo root (would shadow / confuse load)" {
  [ ! -f "$ROOT/plugin.json" ]
}

@test "manifest is valid JSON with required fields" {
  m="$ROOT/.claude-plugin/plugin.json"
  run jq -r '.name, .version, .description, .author, .license' "$m"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sdlc-orchestrator"* ]]
}

@test "manifest description is not stale (matches actual component counts)" {
  m="$ROOT/.claude-plugin/plugin.json"
  desc=$(jq -r '.description' "$m")
  agents=$(ls "$ROOT"/agents/*.md | wc -l | tr -d ' ')
  skills=$(ls -d "$ROOT"/skills/*/ | wc -l | tr -d ' ')
  commands=$(ls "$ROOT"/commands/*.md | wc -l | tr -d ' ')
  # description must cite the real counts (guards against the v0.2.0 "9 agents,
  # 5 skills" drift after the surface grew to 15/8/17).
  [[ "$desc" == *"$agents agent"* ]] || { echo "desc agents != $agents: $desc" >&2; return 1; }
  [[ "$desc" == *"$skills skill"* ]] || { echo "desc skills != $skills: $desc" >&2; return 1; }
  [[ "$desc" == *"$commands"*"command"* ]] || { echo "desc commands != $commands: $desc" >&2; return 1; }
}

@test "every [[cross-ref]] in agents/skills resolves to a real agent or skill" {
  # Collect known component basenames (agents + skill dirs).
  known=$(ls "$ROOT"/agents/*.md 2>/dev/null | xargs -n1 basename | sed 's/\.md$//'; \
          ls -d "$ROOT"/skills/*/ 2>/dev/null | xargs -n1 basename)
  missing=""
  for ref in $(grep -rhoE "\[\[[a-z][a-z0-9-]+\]\]" "$ROOT"/agents/ "$ROOT"/skills/ 2>/dev/null \
                | sed 's/\[\[//; s/\]\]//' | sort -u); do
    echo "$known" | grep -qxF "$ref" || missing="$missing $ref"
  done
  [ -z "$missing" ] || { echo "orphan [[refs]]:$missing" >&2; return 1; }
}

@test "every skill directory has a SKILL.md" {
  for d in "$ROOT"/skills/*/; do
    [ -f "$d/SKILL.md" ] || { echo "missing SKILL.md in $d" >&2; return 1; }
  done
}

@test "every hooks.json command script exists and is executable" {
  for rel in $(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/[^"]+' "$ROOT/hooks/hooks.json" \
                | sed 's|${CLAUDE_PLUGIN_ROOT}/||'); do
    [ -f "$ROOT/$rel" ] || { echo "hook script missing: $rel" >&2; return 1; }
    [ -x "$ROOT/$rel" ] || { echo "hook script not executable: $rel" >&2; return 1; }
  done
}

@test "manifest author is an object (CC schema — string form fails plugin validate)" {
  # claude plugin validate (the real loader) rejects a string author; jq sees the
  # field present but not its type. Found in v0.6.2 real deployment validation.
  m="$ROOT/.claude-plugin/plugin.json"
  run jq -e '.author | type == "object"' "$m"
  [ "$status" -eq 0 ]
}

@test "every command/agent/skill frontmatter parses as YAML" {
  # A colon-in-an-unquoted-value (e.g. argument-hint: <scope: a|b>) makes the loader
  # drop ALL frontmatter silently. Extract each --- … --- block and yq-parse it.
  fail=""
  for f in "$ROOT"/commands/*.md "$ROOT"/agents/*.md "$ROOT"/skills/*/SKILL.md; do
    fm=$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' "$f")
    printf '%s\n' "$fm" | yq -e '.' >/dev/null 2>&1 || fail="$fail $f"
  done
  [ -z "$fail" ] || { echo "frontmatter parse fail:$fail" >&2; return 1; }
}
