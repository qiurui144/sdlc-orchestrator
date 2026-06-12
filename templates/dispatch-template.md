# Agent Dispatch Template

> INJECTED into any agent prompt by orchestrator. Per spec §11 R18 + §1.3 mapping.

## Pre-Create Gate (CLAUDE.md §1.1.7)

Before you Write any `.md` / `scripts/*` / new file, answer 3 questions:

1. **重复检查**: `grep -rli "<topic>" docs/ scripts/`. If found → extend it, don't create new.
2. **生命周期**: One-shot sprint artifact? → goes to PR description / RELEASE.md / `reports/`, NOT `docs/` top level.
3. **白名单** (per CLAUDE.md §1.1.2 / §3.2):
   - 仓根:README.md / README.zh.md / DEVELOP.md / RELEASE.md / CLAUDE.md / LICENSE only
   - docs/ 顶层:INSTALL.md / TESTING.md / VERSIONING.md / DEPLOY.md / `<feature>.md` (single topic)
   - docs/adr/<NNNN>-<title>.md / docs/specs/<date>-<feature>.md / docs/screenshots/

Any "No" → DO NOT CREATE. Stop and ask the user.

## File Output Discipline (per spec §11 R18)

- raw log: `reports/runs/<ts>_<topic>/`
- **MUST `Write` a `.md` summary** to `reports/<date>_<topic>.md` (chat-return text does NOT count as archival)
- Verify with `ls reports/<date>_*.md` before claiming "done"

## Disk Discipline (per CLAUDE.md §1.1.6)

- Before any build / cargo command, run `df -h / /tmp /data`
- Red line: any of root/data < 50G or /tmp < 5G → stop and request clean

## Evidence Discipline (per CLAUDE.md §6.3)

- No claim of "PASS" / "实证" / "已验证" without `reports/runs/<ts>/<file>:<line>` reference
- Multi-seed N=3 for any LLM-driven test (per §2.3)
