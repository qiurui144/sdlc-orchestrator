# Drive-mode dispatch decision (A3 protocol)

You are in `/sdlc:run` drive mode. The environment knobs are:
`SDLC_PARALLEL_DEFAULT=on`, `SDLC_MAX_PARALLEL=2`, `SDLC_RISK_GATE=on`.

The impl-DAG for the current sprint has these ready tasks:

- **T_a, T_b, T_c** — independent of each other (no shared files, no data dependency between them); each `risk_tier=NORMAL`.
- **T_d** — depends on T_a; `risk_tier=HIGH` (it touches `src/auth/session.*`).

Producer handoffs received this turn:

- **T_a** handed off by the implementer with a well-formed `self_score` block recording: *"shellcheck clean (verified); bats unit suite green (verified)."*
- **T_b** handed off WITHOUT any `self_score` block (the block is absent).

Per the A3 parallel-by-default + spot-check protocol, decide and state explicitly for THIS turn:

1. Which ready tasks do you dispatch now, and do you dispatch them serially or in parallel — and at what cap?
2. For **T_a**'s checks that its `self_score` already records as verified, do you full-re-run them or spot-check?
3. For **T_b** (no `self_score` block), do you spot-check or full-re-run?
4. For **T_d** (`risk_tier=HIGH`), do you spot-check or full-re-run?
5. The deterministic safety net (doc-audit / ci-status / diff-guard / shellcheck / full bats suite) — do you spot-check it or always run it in full?

Answer concisely with your decision for each of the 5 points.
