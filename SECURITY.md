# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| v0.31.x (latest) | Yes |
| < v0.31.0 | No — please upgrade |

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Please report security issues by emailing the maintainer directly (see the GitHub profile for contact details) or by opening a [GitHub Security Advisory](../../security/advisories/new).

Include:
- A description of the vulnerability and its potential impact
- Steps to reproduce
- Affected versions
- Any suggested mitigations

You will receive an acknowledgement within 48 hours. We aim to release a fix within 14 days for critical issues.

## Security mechanisms in this plugin

This plugin ships two built-in defences that it also applies to managed repos:

### secret-scan (`skills/secret-scan/`)

`/sdlc:deps` runs `secret-scan/scan.sh` against the target repo. It detects:
- High-entropy strings in tracked files
- Common secret patterns (API keys, tokens, private keys)
- Secrets accidentally staged in `.git/config` or dotfiles

### secret-guard (`hooks/secret-guard.sh`)

A `PreToolUse` hook that intercepts `git commit` and `git push` calls. It runs `scan.sh` on the staged diff and **hard-blocks** the commit if a secret pattern is found, preventing accidental secret commits.

Both mechanisms are deterministic (zero-LLM) — they do not rely on an LLM to judge whether something is a secret.

### Scope

This plugin is a set of markdown + bash files. It has no runtime server, no database, and makes no outbound network calls itself. All `gh` CLI calls are made by the user's existing authenticated session. Secrets used by managed repos are the responsibility of those repos' owners.
