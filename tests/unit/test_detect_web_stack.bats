#!/usr/bin/env bats
# detect-web-stack: frontend framework detection, ORTHOGONAL to detect-stack (build lang).
# Stubbed by building marker package.json fixtures — no network, no install.
D="$BATS_TEST_DIRNAME/../../config/detect-web-stack.sh"

setup() { R=$(mktemp -d); }
teardown() { rm -rf "$R"; }
pkg() { printf '%s\n' "$1" > "$R/package.json"; }

@test "react: react dep → react" {
  pkg '{"dependencies":{"react":"18.0.0","react-dom":"18.0.0"}}'
  run bash "$D" "$R"; [ "$status" -eq 0 ]; [ "$output" = react ]
}
@test "next: next dep wins over react (more specific)" {
  pkg '{"dependencies":{"next":"14.0.0","react":"18.0.0"}}'
  run bash "$D" "$R"; [ "$output" = next ]
}
@test "vue: vue dep → vue" {
  pkg '{"dependencies":{"vue":"3.4.0"}}'
  run bash "$D" "$R"; [ "$output" = vue ]
}
@test "svelte: svelte devDep → svelte" {
  pkg '{"devDependencies":{"svelte":"4.0.0"}}'
  run bash "$D" "$R"; [ "$output" = svelte ]
}
@test "angular: @angular/core → angular" {
  pkg '{"dependencies":{"@angular/core":"17.0.0"}}'
  run bash "$D" "$R"; [ "$output" = angular ]
}
@test "vanilla: index.html present, no framework dep → vanilla" {
  printf '<!doctype html><div id=root></div>\n' > "$R/index.html"
  run bash "$D" "$R"; [ "$output" = vanilla ]
}
@test "not-a-web-app: Cargo.toml only → not-a-web-app, exit 2" {
  printf '[package]\nname="x"\n' > "$R/Cargo.toml"
  run bash "$D" "$R"; [ "$status" -eq 2 ]; [ "$output" = not-a-web-app ]
}
@test "monorepo subdir: web/ has package.json with react → react (descend one level)" {
  mkdir -p "$R/web"; printf '{"dependencies":{"react":"18.0.0"}}\n' > "$R/web/package.json"
  run bash "$D" "$R"; [ "$output" = react ]
}
@test "empty repo → not-a-web-app, exit 2" {
  run bash "$D" "$R"; [ "$status" -eq 2 ]; [ "$output" = not-a-web-app ]
}
