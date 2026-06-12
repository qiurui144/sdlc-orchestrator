#!/usr/bin/env bats

CMD_DIR="$BATS_TEST_DIRNAME/../../commands"

@test "all 21 commands present" {
  for n in spec plan impl review test release audit-docs disk status \
            adr threat migrate perf deps debt incident cicd eval \
            onboard doctor cost; do
    [ -f "$CMD_DIR/$n.md" ] || { echo "missing: $n" >&2; return 1; }
  done
}

@test "each command has frontmatter with description + allowed-tools" {
  for f in "$CMD_DIR"/*.md; do
    head -20 "$f" | grep -q "^description:" || { echo "$f: no description" >&2; return 1; }
    head -20 "$f" | grep -q "^allowed-tools:" || { echo "$f: no allowed-tools" >&2; return 1; }
  done
}

@test "phase commands dispatch correct agent" {
  for pair in \
    "spec:spec-analyst" "plan:architect" "impl:implementer" \
    "review:pr-reviewer" "test:tester" "release:releaser" \
    "audit-docs:docs-curator" "disk:disk-monitor" "status:task-orchestrator"; do
    n="${pair%%:*}"
    agent="${pair#*:}"
    grep -q "$agent" "$CMD_DIR/$n.md" || { echo "$n missing agent $agent" >&2; return 1; }
  done
}

@test "SE commands dispatch correct agent" {
  for pair in \
    "adr:architecture-reviewer" "threat:architecture-reviewer" "migrate:architecture-reviewer" \
    "perf:performance-analyst" "deps:dependency-auditor" "debt:tech-debt-tracker" \
    "incident:incident-responder" "cicd:cicd-designer"; do
    n="${pair%%:*}"
    agent="${pair#*:}"
    grep -q "$agent" "$CMD_DIR/$n.md" || { echo "$n missing agent $agent" >&2; return 1; }
  done
}

@test "web-ui-verify.md exists, has description frontmatter, invokes verify.sh, documents PENDING-VERIFY" {
  C="$CMD_DIR/web-ui-verify.md"; [ -f "$C" ]
  fm=$(awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$C")
  echo "$fm" | grep -qE "^description: .+"
  run awk '/web-ui-verify\/verify\.sh/{f=1} END{exit f?0:1}' "$C"; [ "$status" -eq 0 ]
  run awk '/PENDING-VERIFY/{f=1} END{exit f?0:1}' "$C"; [ "$status" -eq 0 ]
}

@test "ui-vision-judge.md exists, has description frontmatter, dispatches judge.sh, documents PENDING-VERIFY" {
  C="$CMD_DIR/ui-vision-judge.md"; [ -f "$C" ]
  fm=$(awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$C")
  echo "$fm" | grep -qE "^description: .+"
  grep -q "skills/ui-vision-judge/judge.sh" "$C"
  run awk '/PENDING-VERIFY/{f=1} END{exit f?0:1}' "$C"; [ "$status" -eq 0 ]
}

@test "web-ui-quality.md exists, frontmatter (description+allowed-tools), dispatches quality.sh, PENDING-VERIFY" {
  C="$CMD_DIR/web-ui-quality.md"; [ -f "$C" ]
  fm=$(awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$C")
  echo "$fm" | grep -qE "^description: .+"; echo "$fm" | grep -qE "^allowed-tools:"
  grep -q "skills/web-ui-quality/quality.sh" "$C"
  run awk '/PENDING-VERIFY/{f=1} END{exit f?0:1}' "$C"; [ "$status" -eq 0 ]
}
