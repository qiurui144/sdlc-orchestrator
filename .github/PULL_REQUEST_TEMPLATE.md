## Summary

<!-- 1-3 bullet points describing what this PR does -->

## Motivation / linked issue

<!-- Why is this change needed? Link any related issues: Fixes #NNN -->

## Changes

<!-- List the key files changed and what was done -->

## Testing

<!-- How was this tested? -->

- [ ] `./tests/run-all.sh` passes (no new failures)
- [ ] `shellcheck` passes on all modified `.sh` files
- [ ] New behaviour covered by a `.bats` test in `tests/unit/` or `tests/integration/`
- [ ] `scripts/doc-audit.sh --strict` passes

## SDLC evidence (for non-trivial changes)

<!-- If this change went through the full SDLC cycle, link the handoff artifacts -->

- Spec: `docs/superpowers/specs/<date>-<slug>.md` (if applicable)
- G1 gate: PASS / N/A
- G2 gate: PASS / N/A

## Checklist

- [ ] No internal project names or private paths introduced
- [ ] New agent `.md` files have `model_tier` frontmatter and ≥ 250 lines
- [ ] RELEASE.md updated with a brief entry
- [ ] No secrets or credentials in any file
- [ ] PR description is sufficient to understand the change without reading the code diff
