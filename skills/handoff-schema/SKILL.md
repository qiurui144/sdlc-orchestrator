---
name: handoff-schema
description: Use when one SDLC phase agent hands off to the next (spec → plan, plan → impl, impl → review, review → test, test → release). Validates the YAML handoff against schema v1/v2, enforces required fields (v2 also producer + model_tier + self_score), and rejects illegal phase transitions. Triggers on any /sdlc:* command boundary.
---

# handoff-schema

## When to use

Any time a phase agent produces a handoff YAML that the next phase will consume. The skill validates structure BEFORE the next phase agent runs — preventing silent contract violations.

## Two distinct YAML artifacts — only one is validated here

There are two different YAMLs in a sprint; do not confuse them:

- **Transition handoff** — what `validate.sh` checks. Each producer boundary emits one.
  It uses the **SHORT producer-name vocab** in `phase_from`/`phase_to`
  (`spec:plan | plan:impl | impl:review | review:test | test:release`, plus the
  backward re-routes `impl:plan | plan:spec | review:impl | test:impl`), carries all
  7 required fields below, and its `artifact_path` must be a real file whose
  `git hash-object` equals `artifact_sha`. This is the contract that gates a phase advance.
- **State snapshot** — `<sprint_id>_state.yaml`, the task-orchestrator's bookkeeping
  output. It uses the **fine-grained state-machine phases** (`phase: SPEC_APPROVED`,
  `previous_phase`, `iteration_counts`, …). It is NOT a transition handoff and is NOT
  validated by `validate.sh`. Do not write a transition handoff with these fine-grained
  labels — that fails `validate.sh` with `phase-skip-not-allowed`.

## What to enforce

1. **schema_version** present and equals current supported version (1)
2. **Required fields** all present: `schema_version`, `sprint_id`, `phase_from`, `phase_to`, `artifact_path`, `artifact_sha`, `timestamp_utc8`
3. **Phase transition matrix** (per spec §3.3):
   - spec → plan ✓
   - plan → impl ✓
   - impl → review ✓
   - impl → plan ✓ (deviation re-route)
   - plan → spec ✓ (insufficiency re-route)
   - review → test ✓
   - review → impl ✓ (round-2 finding)
   - test → release ✓
   - test → impl ✓ (regression found)
   - any other transition: REJECT with `phase-skip-not-allowed`
4. **artifact_path** must exist as file on disk
5. **artifact_sha** must match `git hash-object <artifact_path>` output
6. **panel_score** (optional, v0.9) — if present, `decision ∈ {AUTO_ADVANCE, ESCALATE}`;
   `high_risk: true` ⇒ `decision: ESCALATE` (forgery guard — a high-risk gate can never
   auto-advance); `ESCALATE` (non-high-risk) ⇒ non-empty `escalate_reason`. Absent ⇒ ok
   (back-compat). Written by the Challenger panel (skill [[challenger-panel]]).

## Steps

1. Read handoff YAML
2. Run `${CLAUDE_PLUGIN_ROOT}/skills/handoff-schema/validate.sh <path-to-handoff.yaml>`
3. exit 0 → proceed; exit 2 → block downstream phase and surface error to user

## Error codes (per spec §7.1)

- `handoff-schema-invalid`: required field missing or malformed
- `handoff-schema-future-version`: schema_version > 1 (plugin too old)
- `phase-skip-not-allowed`: illegal phase transition attempted
- `artifact-sha-mismatch`: file changed since handoff written
- `panel-score-invalid`: panel_score decision malformed or ESCALATE without reason
- `panel-high-risk-must-escalate`: high_risk=true but decision≠ESCALATE (forged auto-advance)

## Schema v2 (v0.14)

`schema_version: 2` additionally requires (validated at the boundary; v1 unaffected):

| Field | Rule | Error code |
|-------|------|------------|
| `producer` | non-empty agent name | `handoff-v2-missing-producer` |
| `model_tier` | `haiku` \| `sonnet` \| `opus` (Appendix D.3) | `handoff-v2-bad-model-tier` |
| `self_score.rubric_ref` | non-empty | `handoff-v2-missing-self-score` |
| `self_score.overall` | number in `[0,5]` (closed) | `handoff-v2-bad-self-score` |

v1 handoffs (no `schema_version: 2`) validate exactly as before — v2 is additive/opt-in. The
v0.9 `panel_score` forgery guard (high_risk + AUTO_ADVANCE → reject) applies under both v1 and v2.

## Linked

- spec §3.2 / §3.3 / §5.2
- skill [[pre-create-gate]] (orthogonal — both gate the handoff process)
- skill [[challenger-panel]] (writes the optional `panel_score` block)
