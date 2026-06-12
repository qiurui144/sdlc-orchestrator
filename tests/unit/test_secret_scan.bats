#!/usr/bin/env bats
# secret-scan (v0.21, SE13): deterministic secret + file-permission scanner. NEVER prints the secret
# value (§1.4). Fixtures are built at RUNTIME by concatenation so this test file's SOURCE contains no
# contiguous matchable token (a repo self-scan must not flag this file).
S="$BATS_TEST_DIRNAME/../../skills/secret-scan/scan.sh"

setup() { D=$(mktemp -d); }
teardown() { rm -rf "$D"; }

# runtime-built fixtures (no contiguous literal in source)
ghtoken() { printf 'gho_%s' "$(printf 'A%.0s' $(seq 40))"; }           # gho_ + 40 → matches
awskey()  { printf 'AKIA%s' "$(printf 'A%.0s' $(seq 16))"; }
pkey()    { printf -- '-----BEGIN RSA PRIVATE %s' 'KEY-----'; }
ecred()   { printf 'https://%s:%s@host.invalid' 'user' 'password'; }   # runtime forms a https://<user>:<pw>@ URL; source ':%s@' (<3 chars) does NOT match

@test "clean dir → CLEAN exit 0" {
  echo "just some code" > "$D/a.txt"
  run bash "$S" --secrets "$D/a.txt"
  [ "$status" -eq 0 ]; echo "$output" | grep -q "CLEAN"
}

@test "github token → exit 2, kind reported, VALUE NOT printed" {
  t=$(ghtoken); printf 'token = %s\n' "$t" > "$D/f"
  run bash "$S" --secrets "$D/f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "github-token"
  ! echo "$output" | grep -q "$t"     # §1.4 — the secret value must never appear in output
}

@test "private key → exit 2" {
  pkey > "$D/id"; run bash "$S" --secrets "$D/id"
  [ "$status" -eq 2 ]; echo "$output" | grep -q "private-key"
}

@test "aws access key → exit 2" {
  printf 'aws=%s\n' "$(awskey)" > "$D/f"; run bash "$S" --secrets "$D/f"
  [ "$status" -eq 2 ]; echo "$output" | grep -q "aws-access-key"
}

@test "embedded credential URL → exit 2" {
  ecred > "$D/f"; run bash "$S" --secrets "$D/f"
  [ "$status" -eq 2 ]; echo "$output" | grep -q "embedded-cred"
}

@test "§1.4 placeholder (your-key-here) is allowlisted → CLEAN" {
  echo "api_key = your-key-here" > "$D/f"; run bash "$S" --secrets "$D/f"
  [ "$status" -eq 0 ]
}

@test ".sdlc/secret-allow suppresses by file path (explicit per-repo override)" {
  t=$(ghtoken); printf 'token=%s\n' "$t" > "$D/vendor-sample.txt"
  mkdir -p "$D/.sdlc"; echo 'vendor-sample' > "$D/.sdlc/secret-allow"
  run bash "$S" --secrets --root "$D" "$D/vendor-sample.txt"
  [ "$status" -eq 0 ]
}

@test "loose perms on a secrets file → flagged; --fix → 0600 + CLEAN" {
  printf 'X=1\n' > "$D/prod.env"; chmod 644 "$D/prod.env"
  run bash "$S" --perms "$D/prod.env"
  [ "$status" -eq 2 ]; echo "$output" | grep -q "loose-perm"
  run bash "$S" --perms --fix "$D/prod.env"
  [ "$(stat -c '%a' "$D/prod.env" 2>/dev/null || stat -f '%Lp' "$D/prod.env")" = "600" ]
  run bash "$S" --perms "$D/prod.env"
  [ "$status" -eq 0 ]
}

@test "non-sensitive file perms are ignored" {
  echo x > "$D/readme.txt"; chmod 644 "$D/readme.txt"
  run bash "$S" --perms "$D/readme.txt"
  [ "$status" -eq 0 ]
}

@test "binary file is skipped (no false positive)" {
  printf '\x00\x01\x02gho_%s' "$(printf 'A%.0s' $(seq 40))" > "$D/bin"
  run bash "$S" --secrets "$D/bin"
  [ "$status" -eq 0 ]
}

@test "SDLC_PROJECT_ROOT honored (scan a target repo from elsewhere)" {
  mkdir -p "$D/proj"; git -C "$D/proj" init -q
  t=$(ghtoken); printf 'k=%s\n' "$t" > "$D/proj/leak.txt"; git -C "$D/proj" add leak.txt
  cd "$D"
  SDLC_PROJECT_ROOT="$D/proj" run bash "$S" --secrets --staged
  [ "$status" -eq 2 ]; echo "$output" | grep -q "github-token"
}

# --- dual-acceptance regression tests (encode the bypasses the review caught) ---
@test "regression(BLOCK-1): a real token on a line that ALSO has \${VAR} is still flagged (token-level allowlist)" {
  t=$(ghtoken); printf 'GH_TOKEN=%s  # default from ${HOME}/.config\n' "$t" > "$D/f"
  run bash "$S" --secrets "$D/f"
  [ "$status" -eq 2 ]; echo "$output" | grep -q "github-token"
}
@test "embedded-cred with a \${VAR} password IS allowlisted (the legit placeholder case)" {
  printf 'url=https://user:%s@host.internal\n' '${DB_PASS}' > "$D/f"
  run bash "$S" --secrets "$D/f"
  [ "$status" -eq 0 ]
}
@test "regression(perm): 4-digit setgid mode on a sensitive file is flagged (no false-neg)" {
  printf 'X=1\n' > "$D/s.env"; chmod 2644 "$D/s.env"
  run bash "$S" --perms "$D/s.env"
  [ "$status" -eq 2 ]; echo "$output" | grep -q "loose-perm"
}
