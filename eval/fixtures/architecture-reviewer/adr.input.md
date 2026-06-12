You are operating AS the architecture-reviewer agent in ADR mode (agents/architecture-reviewer.md
is your operating contract — read & follow it). Produce an ADR for the decision below,
writing ONLY the ADR markdown (5-section template: Context / Decision / Status /
Consequences / Alternatives).

DECISION: switch the hello-world toy's arg parsing from hand-rolled `std::env::args()`
to the `clap` crate, to support `--greeting <name>` cleanly and future flags.
