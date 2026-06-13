---
name: model-eval
description: Offline eval gate for SDLC multi-model routing (M2). Proves a weak provider (deepseek) on a mechanical, live-gradable task before any routing — fixture × provider × seed matrix, deterministic grader (exact/normalized/set-F1), worst-case gate (every seed ≥ floor, std ≤ 0.05, gap-to-claude ≤ 0.10), emitting config/model-allowlist.yaml with sources_hash. Real-LLM runs are manual + cost-gated; --stub is free and CI-safe.
---

# model-eval

The offline proof layer for M2 eval-gated routing: no task type is ever routed to a
weak provider until it has PASSED this eval, and the resulting allowlist entry is
hash-bound to the exact fixtures + grader + prompt that produced it.

## Contract

```
grader.sh --task <t> --output <f> (--golden <f> | --derive <input>)
  -> score=<0.000..1.000>            (deterministic; malformed output -> score=0, no crash)
grader.sh hash <files...>            -> sha256 over sorted file contents (sources_hash helper)

eval.sh --task <t> --providers <p1,p2,..> --seeds <N> [--floor 0.85] [--out <yaml>] [--stub <dir>]
  -> per-provider F1 mean±std + allowlist YAML:
     tasks.<t>: {passed, f1, std, claude_f1, task_reliability, sources_hash}
```

- **Grader modes** per task type in `grader-modes.yaml` (`exact` / `normalized` /
  `set-f1`), plus `live_gradable` + `prompt_file`. The SAME grader serves the offline
  eval (`--golden`) and the executor's online oracle (`--derive`) — one judge, proven
  once in `tests/grader/` BEFORE any real-LLM eval (spec EVAL C-1).
- **Worst-case gate** (not mean-only): passed=true IFF every seed ≥ floor AND
  std ≤ 0.05 AND |provider − claude| ≤ 0.10 AND claude ≥ floor. claude < floor →
  `task_reliability: low`, never routed.
- **sources_hash** = sha256(fixtures + grader.sh + grader-modes.yaml + prompt_file):
  the executor recomputes it live and degrades to claude on any mismatch (stale eval).
- **Fixtures** live in `fixtures/<task_type>/*.json` (input + golden); every golden
  must be RE-DERIVABLE from its input (`tests/grader/test_fixtures_derivable.bats`) —
  that is the live-gradable eligibility criterion.

## Cost / safety

`--stub <dir>` (canned provider outputs) is the only CI path — free, deterministic.
A real run (provider × seed × case real-LLM calls) is manual, cost-gated behind
explicit user approval via `/sdlc:eval --model-task <t>`; keys come from env /
`/tmp/secrets-*`, never the repo. Judgment tasks are NOT evaluable here by
construction: only ops in the closed `skills/model-router/task-type-map.yaml` ever
consult the allowlist this skill produces.

## Linked

- [[model-router]] (executor.sh consumes the allowlist + reuses grader.sh as the online oracle)
- [[model-provider]] (call.sh — schema-guided provider calls)
- spec `docs/superpowers/specs/2026-06-12-sdlc-eval-gated-routing.md` (§5 allowlist, §9 test matrix)
