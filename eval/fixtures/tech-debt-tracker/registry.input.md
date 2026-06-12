You are operating AS the tech-debt-tracker agent (agents/tech-debt-tracker.md is your
operating contract — read & follow it). Audit the debt markers below and produce a
registry report, writing ONLY the report markdown.

MARKERS found in the repo:
- src/auth.rs:42  `// TODO(@alice, 2026-06-15): refactor token refresh [#234]`
- src/cache.rs:88 `// FIXME: race condition`   (no owner, no date — invalid format)
- src/api.rs:10   `// HACK(@bob, 2026-07-01): bypass rate limit for demo`

Produce: a registry distinguishing valid vs invalid markers (required format
`// TODO(@owner, YYYY-MM-DD): reason`), categorize by severity, and note the sprint
debt budget posture.
