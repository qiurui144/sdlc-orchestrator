---
name: Bug report
about: Report a bug or unexpected behaviour in sdlc-orchestrator
title: '[BUG] '
labels: bug
assignees: ''
---

## Describe the bug

A clear and concise description of what the bug is.

## Steps to reproduce

1. Plugin version: (run `/sdlc:status` and paste the version line)
2. Target project stack: (rust / typescript / python / go / generic)
3. Command run: `/sdlc:...`
4. What happened:

## Expected behavior

What you expected to happen.

## Actual behavior

What actually happened. Include any error messages or exit codes.

## Logs / evidence

```
paste relevant output here
```

If the bug involves a specific agent or skill, please include:
- The handoff YAML at `docs/superpowers/handoffs/` (redact any secrets)
- The relevant lines from `reports/runs/`

## Environment

- OS: (e.g. Ubuntu 22.04, macOS 14)
- Bash version: (`bash --version`)
- Claude Code version: (`claude --version`)
- bats version: (`bats --version`)
- jq / yq versions

## Additional context

Any other context about the problem.
