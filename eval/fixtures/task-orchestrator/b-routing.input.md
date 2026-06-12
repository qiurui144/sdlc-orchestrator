# Drive-mode path-depth routing (B: risk-gated adaptive rigor)

You are in `/sdlc:run` drive mode with `SDLC_RISK_GATE=on`. The deterministic classifier
`risk-classify.sh --staged` has already produced a `risk_tier` for the staged change. For each
scenario below, state the path you run.

1. **Change A** — `risk_tier=LOW` (a one-line `README.md` typo fix, fence-free prose). Do you run the
   full spec→plan→impl→review→test ceremony, or the fast-path? And do the deterministic gates
   (doc-audit --strict / ci-status / diff-guard / shellcheck / full bats suite) still run on this change?
2. **Change B** — `risk_tier=HIGH` (edits `src/auth/session.rs`). What path depth, and what Challenger
   panel size?
3. The user adds `--full` to Change A. What happens to its path depth?
4. The user adds `--fast` to Change B. Can it be fast-pathed?

Answer concisely for each of the 4 points.
