---
description: Audit repo doc structure per §1.1.2/§3.2 whitelist. Dispatches docs-curator (haiku). Dry-run default; --apply to execute.
argument-hint: [--apply | --dry-run]
allowed-tools: [Read, Glob, Grep, Bash, Edit, Agent]
---

# /sdlc:audit-docs [--apply]

Invokes the **docs-curator** agent (haiku). Globs root + docs/. Categorizes each `.md`: KEEP / MOVE / INLINE / DELETE. Outputs `reports/<date>-doc-audit.md`. With `--apply` + clean git tree: executes git mv / rm with descriptive commit.

## Behavior

1. Dry-run mode (default): list violations + suggested commands; no fs changes.
2. `--apply`: REQUIRES git status clean (R15 safety). Executes suggested commands.
3. Detects: `*-tasks.md`, `*-report.md`, `v*-release-notes.md`, `.zh.md` outside README, missing date prefix in specs/plans, root non-whitelisted `.md`.
4. Output: `reports/<date>-doc-audit.md` + commit if `--apply`.

## Refuses

- `--apply` on dirty git tree
