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

## Model-routing eval (M2): `/sdlc:eval --model-task <task_type>`

The second eval mode proves a weak provider on a mechanical, live-gradable task and
produces the routing allowlist consumed by `skills/model-router/executor.sh`:

1. Pre-flight (free): `bats tests/grader/` must be green — the grader is the gate's
   judge and must be proven first (spec EVAL C-1). A red grader suite ABORTS the eval.
2. Print the cost estimate (providers × seeds × cases real-LLM calls) and **wait for
   explicit user approval** — this is the only paid path (§1.3/§8). Keys come from
   env / `/tmp/secrets-*`, never from files in the repo.
3. Dispatch `skills/model-eval/eval.sh --task <task_type> --providers
   deepseek,claude,qwen --seeds 3 --out config/model-allowlist.yaml` (worst-case
   gate: every seed ≥ floor, std ≤ 0.05, |provider−claude| ≤ 0.10, claude ≥ floor).
4. Record the F1 matrix (mean±std per provider) to `reports/<date>_m2-eval.md`.
   The allowlist carries `sources_hash`; any later fixture/grader/prompt change
   invalidates it (the executor degrades to claude until re-eval).

`--stub <dir>` runs the same pipeline on canned outputs (free, CI-safe; never
produces a production allowlist).

## Refuses / limits

- Agent without a fixture → `eval-no-fixture`, skipped + noted in report.
- Free-form-output agents (architecture-reviewer ADR, incident-responder postmortem)
  have no deterministic grader yet — deferred to v0.3.1 (LLM-judge). Not in `all` count.
- Fidelity boundary (DP4): dispatch is prompt-injection via `claude -p`, not a native
  Claude Code plugin load. The contract assertions are load-path-independent.

## Linked
- [[releaser]] (its rule 11 "observed-green CI" is the release analogue of behavioral eval)
- spec §3.4 (expect.yaml format), `eval/grade.sh`, `eval/run-eval.sh`, `tests/PORTABILITY.md`
