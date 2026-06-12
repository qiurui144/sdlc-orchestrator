---
name: challenger-panel
description: Use AT a Challenger gate (G1–G4) instead of a single Challenger. Dispatches N expert agents (different lenses) to vote on one artifact, merges via consensus, and AUTO-ADVANCES on high-confidence agreement — escalating to a human only on disagreement, the four high-risk classes, or non-convergence. Lowers human-interaction frequency while raising reliability (strengthens §5.2 adversarial review + §2.3 multi-view).
---

# challenger-panel

Replaces "one Challenger + always pause for human" with "N experts vote +
consensus-auto + human as backstop". Built on [[multi-agent-dispatch]] (parallel
fan-out) and reuses `eval/judge.sh` `parse_verdict` (one judge primitive, two uses).

## When to use

- A producer artifact (spec/plan/code/RC) is ready at a Challenger gate G1–G4.
- You want high-confidence agreement to advance WITHOUT pausing the human.
- NOT for the GA tag (always a hard human stop, §7.2 — irreversible).

## Two-step protocol

1. **Dispatch** — `panel.sh --dispatch --artifact <p> --handoff <y>` returns
   `high_risk=<yes|no> size=<n> lenses=...`. high_risk (four classes below) →
   `size = SDLC_PANEL_HIGH_RISK_SIZE` (default 5); else `SDLC_PANEL_SIZE` (3).
   The orchestrator then issues `size` Agent calls **in one turn** (per the
   dispatch-batch protocol in [[multi-agent-dispatch]]), each running one lens
   prompt from `lenses/<lens>.md`, each writing a vote shard to
   `reports/runs/<ts>/panel/<gate>/<lens>.json`.
2. **Consensus** — `panel.sh --consensus --votes-dir <d> [--high-risk yes|no]`
   reads the vote shards and prints `decision=AUTO_ADVANCE|ESCALATE ...`.

## Vote shard format (each expert writes)

```
VERDICT: PASS|FAIL
SCORE: <0-5>
LENS: <name>
REASON: <one sentence, quote the line judged>
```

## Consensus rule

| Condition | Decision | exit |
|-----------|----------|------|
| all votes malformed (no parseable VERDICT) | ESCALATE | 2 |
| high_risk = yes | ESCALATE (even if all PASS) | 1 |
| majority PASS (pass·2 ≥ total) AND mean(SCORE) ≥ threshold (4.0) | AUTO_ADVANCE | 0 |
| otherwise (split / low mean) | ESCALATE | 1 |

## The four high-risk classes (always escalate to a human)

1. **secret / auth / credential** (§1.4, §5.2)
2. **data-model / API breaking change** (§3.1 §10, §5.1)
3. **irreversible / production deploy** (§7.2, §8.1)
4. **STRIDE high residual risk** (from architecture-reviewer)

GA tag is an additional permanent hard stop, independent of the panel.

## Principle boundary (does NOT relax the rules)

- Challenger still exists (1 → N, stricter).
- Gate still exists (default auto-pass on consensus).
- Every AUTO_ADVANCE is recorded in handoff `panel_score` (auditable after the fact).
- The four high-risk classes + GA always escalate.
- Calibration gate: each lens rubric must PASS a known-good and FAIL a planted-bad
  before deployment (reuse `judge.sh --calibrate`). A panel that can't discriminate
  is not trusted.

## Config

| Env | Default | Meaning |
|-----|---------|---------|
| `SDLC_PANEL_SIZE` | 3 | experts for normal gates |
| `SDLC_PANEL_HIGH_RISK_SIZE` | 5 | experts when a high-risk class is hit |

## Linked

- skill [[multi-agent-dispatch]] (dispatch-batch + budget gate)
- skill [[handoff-schema]] (`panel_score` block)
- `eval/judge.sh` (`parse_verdict` reuse)
