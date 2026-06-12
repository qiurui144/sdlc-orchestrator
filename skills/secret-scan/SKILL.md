---
name: secret-scan
description: Use to detect plaintext secrets (tokens / keys / passwords / embedded-cred URLs) and loose permissions on sensitive files (keys / .env / secrets / cred-bearing .git/config). The deterministic engine behind the secret-guard pre-commit/push hook and the dependency-auditor (/sdlc:deps) + /sdlc:intake SE13 dimension. Zero-LLM, never prints the secret value (§1.4); first-line defense — pair with trufflehog/gitleaks in CI for depth. Triggers on git commit/push guarding and security audits.
---

# secret-scan

Deterministic first-line **secret + file-permission** scanner. Owns SE13 (secrets), created after the
2026-06-04 §9.1 incident (a `gho_` token sat plaintext in `.git/config` and the plugin couldn't see it).

## What it checks
- **Secrets** (regex, full-length so truncated doc mentions don't match): `gh[opsu]_…` / `github_pat_…`
  / `-----BEGIN … PRIVATE KEY-----` / `AKIA…` / `https://<user>:<pass>@` embedded creds. Always also scans
  `.git/config` (the incident class).
- **Permissions**: sensitive files (`*.pem/*.key/*.env`, `secrets/`, `id_rsa/id_ed25519`, `.netrc`)
  must be `0600`; group/other-readable flagged. `--fix` → `chmod 600`.

## Usage
```bash
scan.sh [--secrets] [--perms] [--staged] [--fix] [--include-ssh] [--root <dir>] [<path>...]
# exit 0 = CLEAN · 2 = findings (prints file:line: kind — NEVER the value, §1.4)
```
Default: both checks, all tracked files (`--staged` = `git diff --cached`, used by the hook),
root = `$SDLC_PROJECT_ROOT` or cwd (v0.20).

## Consumers
- **`hooks/secret-guard.sh`** (PreToolUse:Bash) — blocks `git commit`/`git push` on a finding (exit 2).
  Escape: `SDLC_SECRET_OVERRIDE=1` or `.sdlc/secret-allow`.
- **`dependency-auditor`** (`/sdlc:deps`) — folds the result into its PASS/BLOCK verdict.
- **`/sdlc:intake`** — the `secrets` audit dimension (SE13) in the project scorecard.

## Allowlist (avoid false positives)
§1.4 placeholders (`your-key-here`, `test-pass-not-real`, `${VAR}`, `<PLACEHOLDER>`, `pk_test_`, …)
are allowlisted by default. Per-repo: one regex/path per line in `.sdlc/secret-allow`.

## Boundaries (honest)
- Regex first-line only — **misses obfuscated/split secrets** (false-neg). Recommend trufflehog/
  gitleaks in CI for depth (§1.4). The hook is defense-in-depth, not a guarantee.
- Line-level allowlist: a real secret sharing a line with an allowlisted token can be missed (rare).
- `--fix` only chmods on the explicit flag; never touches `~/.ssh` without `--include-ssh`.
