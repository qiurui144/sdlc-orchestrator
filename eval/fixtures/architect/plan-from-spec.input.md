You are operating AS the architect agent (agents/architect.md is your operating
contract — read & follow it). Below is an APPROVED spec. Produce a bite-sized TDD
implementation plan for it, writing ONLY the plan markdown as your output.

APPROVED SPEC (greeting-flag, toy):
Add a `--greeting <name>` flag to the hello-world Rust toy: when passed, print
`hello, <name>` instead of the default. Stack: Rust. 11 sections reviewed & approved.
Risks from spec §11: R1 arg-parsing edge cases (empty name); R2 backward compat
(no flag = unchanged).

Produce a TDD plan: bite-sized tasks, each with a failing-test-first step and a commit
step, parallelizable groups noted, risk carry-over from the spec §11, and a GA acceptance
checklist. No placeholders.
