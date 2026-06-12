#!/usr/bin/env bats
# emit.sh — deterministic stack-config-driven CI yaml emitter (v0.16).
E="$BATS_TEST_DIRNAME/../../skills/pipeline-emit/emit.sh"

@test "rust: 5 stages + config commands + cargo audit" {
  run bash "$E" --stack rust
  [ "$status" -eq 0 ]
  for s in build lint test security_scan publish; do echo "$output" | grep -q "$s"; done
  echo "$output" | grep -q "cargo build --release"
  echo "$output" | grep -q "cargo clippy"
  echo "$output" | grep -q "cargo test --workspace"
  echo "$output" | grep -q "cargo audit"
}
@test "scanner map ts/python/go" {
  bash "$E" --stack ts | grep -q "npm audit"
  bash "$E" --stack python | grep -q "pip-audit"
  bash "$E" --stack go | grep -q "govulncheck"
}
@test "emitted yaml is VALID (parses) for rust and generic (G2 fold-in)" {
  bash "$E" --stack rust | yq . >/dev/null
  bash "$E" --stack generic | yq . >/dev/null            # generic config has embedded quotes
  bash "$E" --stack rust --platform generic | yq . >/dev/null
}
@test "unknown stack → generic, no crash" {
  run bash "$E" --stack nosuchstack
  [ "$status" -eq 0 ]; echo "$output" | grep -q "publish"
}
@test "no plaintext secret — only placeholders" {
  out=$(bash "$E" --stack rust)
  echo "$out" | grep -q 'secrets\.'
  ! echo "$out" | grep -qiE '(secret|token|password|api_key)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9]{8,}'
}
@test "platform generic → no GH syntax" {
  run bash "$E" --stack rust --platform generic
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "runs-on: ubuntu"
  echo "$output" | grep -q "stages:"
}
@test "--out writes file + mkdir parent" {
  d=$(mktemp -d); run bash "$E" --stack rust --out "$d/wf/ci.yml"
  [ "$status" -eq 0 ]; [ -f "$d/wf/ci.yml" ]; grep -q "security_scan" "$d/wf/ci.yml"; rm -rf "$d"
}
@test "missing --stack → exit 2" { run bash "$E"; [ "$status" -eq 2 ]; }
@test "bad platform → exit 2" { run bash "$E" --stack rust --platform jenkins; [ "$status" -eq 2 ]; }
@test "stack injection rejected → exit 2" {
  run bash "$E" --stack "../etc"; [ "$status" -eq 2 ]
  run bash "$E" --stack "a;rm -rf /"; [ "$status" -eq 2 ]
}
@test "incomplete config → exit 2" {
  d=$(mktemp -d); echo "language: x" > "$d/stack-x.yaml"
  run env SDLC_CONFIG_DIR="$d" bash "$E" --stack x
  [ "$status" -eq 2 ]; echo "$output" | grep -q "emit-incomplete-config"; rm -rf "$d"
}
@test "SKILL documents deterministic-vs-cicd-designer split + no-plaintext-secret" {
  S="$BATS_TEST_DIRNAME/../../skills/pipeline-emit/SKILL.md"
  grep -qiE "deterministic|config" "$S"; grep -qiE "cicd-designer" "$S"; grep -qiE "secret" "$S"
}
@test "/sdlc:pipeline command exists + calls emit.sh + detect-stack" {
  C="$BATS_TEST_DIRNAME/../../commands/pipeline.md"
  head -1 "$C" | grep -q -- "---"; grep -q "emit.sh" "$C"; grep -qiE "detect-stack" "$C"
}
