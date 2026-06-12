---
description: Release minor version with RC 4 gates + 本机部署 verify (§7.2/§7.3). Dispatches releaser (opus).
argument-hint: <semver-minor e.g. v0.1.0>
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent, Skill]
---

# /sdlc:release <minor>

Invokes the **releaser** agent (opus). Runs RC 4 gates in strict order: G1 docs → G2 code → G3 functionality → G4 known limitations. Builds packaged artifact and runs 本机部署 smoke. Refuses tag if any gate fails.

## Behavior

1. Verify state == TEST_PASS.
2. Pre-Create Gate on RELEASE.md update.
3. Disk audit (strict).
4. Compute semver from `<minor>` arg.
5. Run G1 → G2 → G3 → G4 sequentially. Any fail → return to upstream phase.
6. Build packaged artifact (per stack adapter).
7. 本机部署 verify: install + smoke run.
8. Update RELEASE.md (4 sections). Bump plugin.json version.
9. Commit + tag + (await user) push.
10. Trigger `sprint-archival` skill (plan deleted, handoffs inlined).
11. State: TEST_PASS → RC_CANDIDATE → GA_TAG.

## Refuses

- Adding new features in RC (per §7.1.3)
- Push to upstream-contribution repos (must use §7.4 three-stage flow)
