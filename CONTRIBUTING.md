# Contributing to sdlc-orchestrator

Thank you for your interest in contributing. This plugin uses its own SDLC commands — we eat our own dogfood.

## Before you start

- Read [DEVELOP.md](./DEVELOP.md) for architecture, component map, and coding conventions.
- Check existing [issues](../../issues) and [pull requests](../../pulls) to avoid duplicates.
- For significant changes, open an issue first to discuss the approach.

## Development setup

```bash
git clone <repo> ~/.claude/plugins/sdlc-orchestrator
cd ~/.claude/plugins/sdlc-orchestrator
# Install bats (https://github.com/bats-core/bats-core) and jq/yq
./tests/run-all.sh   # expect all PASS
```

## Workflow (dogfood — we use our own plugin)

This repo is managed with its own SDLC commands. For any non-trivial contribution:

1. **Spec first** (for new features or architecture changes):
   ```
   /sdlc:spec <feature-slug>
   ```
   The spec-analyst agent drafts an 11-section spec. Review it before proceeding.

2. **Implementation plan**:
   ```
   /sdlc:plan docs/superpowers/specs/<date>-<slug>.md
   ```

3. **Implement with TDD**:
   ```
   /sdlc:impl docs/superpowers/plans/<date>-<slug>.md
   ```
   Each task follows: write failing test → implement → commit.

4. **Review and test**:
   ```
   /sdlc:review
   /sdlc:test
   ```

For small fixes (typos, single-file bug fixes), you may skip to a direct PR.

## Code conventions

- **POSIX bash only** — no bashisms beyond arrays; every `.sh` passes `shellcheck`.
- **No business coupling** — agents and skills use generic terms. Do not reference specific downstream project names.
- **Every agent needs `model_tier`** in frontmatter. See `DEVELOP.md` Appendix D.
- **Test every new behaviour** — add a `.bats` test in `tests/unit/` or `tests/integration/`.
- **Commit messages**: `<type>(<scope>): <summary>` (feat/fix/docs/chore/test/refactor).

## Pull request checklist

- [ ] `./tests/run-all.sh` passes with no new failures
- [ ] `shellcheck` clean on any new/modified `.sh` files
- [ ] New agent `.md` files have `model_tier` frontmatter and ≥ 250 lines
- [ ] `scripts/doc-audit.sh --strict` passes
- [ ] RELEASE.md updated with a brief entry under the appropriate version section
- [ ] No internal project names or private paths in any file

## Reporting issues

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) or the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md).

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](./LICENSE).
