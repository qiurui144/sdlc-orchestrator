---
description: Run behavioral conformance eval on agents — dispatch each agent's real prompt on fixture inputs and mechanically grade the output against its contract (multi-seed). Human-triggered (real LLM); not for CI.
argument-hint: "[agent-name | all]"
allowed-tools: [Read, Write, Bash, Agent, Skill]
---

# /sdlc:eval [agent-name | all]

Behavioral conformance eval. For each target agent it dispatches the agent's real
prompt (`agents/<agent>.md` as system prompt) on its fixture inputs, captures the
output, and grades it against `eval/fixtures/<agent>/<case>.expect.yaml` using the
pure mechanical grader `eval/grade.sh` (which NEVER reads the agent's self-report).

## Behavior

1. Resolve targets: a single agent, or `all` (every agent under `eval/fixtures/`).
2. For each target, run `eval/run-eval.sh <agent> --seeds 3`.
   - It reads `model_tier` from the agent frontmatter and dispatches via
     `claude -p --append-system-prompt --model <tier>` (real LLM).
   - Raw outputs land in `eval/runs/<ts>-<agent>/` (gitignored).
   - Each seed is graded; pass-rate < 1.0 is flagged flaky (not a robust PASS, §2.3).
3. Aggregate a report to `reports/<date>-eval.md`: agent × case × seed pass matrix,
   pass-rate, and the failed-assertion detail for any miss. Header states coverage
   (N of 15 agents have fixtures) so the report is never read as "all agents verified."

## Cost (per spec §8)

Real LLM calls: ~(agents × cases × 3 seeds). `all` ≈ 200K tokens. This is the only
paid path; `grade.sh` and `--dry-run` are free. Confirm with the user before `all`.

## Refuses / limits

- Agent without a fixture → `eval-no-fixture`, skipped + noted in report.
- Free-form-output agents (architecture-reviewer ADR, incident-responder postmortem)
  have no deterministic grader yet — deferred to v0.3.1 (LLM-judge). Not in `all` count.
- Fidelity boundary (DP4): dispatch is prompt-injection via `claude -p`, not a native
  Claude Code plugin load. The contract assertions are load-path-independent.

## Linked
- [[releaser]] (its rule 11 "observed-green CI" is the release analogue of behavioral eval)
- spec §3.4 (expect.yaml format), `eval/grade.sh`, `eval/run-eval.sh`, `tests/PORTABILITY.md`
