---
name: threat-model-stride
description: Use when architecture-reviewer is in threat-model mode OR user invokes /sdlc:threat <component>. Enumerates threats per STRIDE (Spoofing/Tampering/Repudiation/InfoDisclosure/DoS/EoP) for each DFD element. Scores residual risk; proposes mitigations.
---

# threat-model-stride

## When to use

- architecture-reviewer agent's threat mode
- `/sdlc:threat <component>` slash command
- Any time a new external interface / data flow / trust boundary is added
- Pre-G1 design review for security-sensitive changes

## When NOT to use

- Pure refactors (no new attack surface)
- Documentation-only changes
- Internal tool changes that don't cross trust boundaries

## STRIDE letter reference

| Letter | Threat | Example attack |
|--------|--------|----------------|
| **S**poofing | Identity impersonation | Forged JWT / weak session |
| **T**ampering | Data integrity attack | SQL inj / message replay |
| **R**epudiation | Denying actions | Missing audit log |
| **I**nformation disclosure | Sensitive data leak | Verbose error / unencrypted storage |
| **D**enial of service | Resource exhaustion | Algorithmic complexity / flood |
| **E**levation of privilege | Privilege escalation | Path traversal / IDOR |

## Steps

1. **Draw DFD** (Data Flow Diagram) — ASCII OK. Identify:
   - **Actors** (external users, services)
   - **Processes** (your code)
   - **Data stores** (DB, cache, file)
   - **Data flows** (arrows between elements)
   - **Trust boundaries** (dashed lines)

2. **For each DFD element**, enumerate threats for ALL 6 STRIDE letters. Skip with reason if N/A; never silently skip.

3. **Score each threat** with:
   - **Likelihood** (1=remote, 5=expected): based on attacker capability + opportunity
   - **Impact** (1=cosmetic, 5=catastrophic): based on data sensitivity + user reach
   - **Risk** = Likelihood × Impact (1-25)

4. **For each risk >= Medium (>= 8)**: propose mitigation (control, monitoring, or design change).

5. **For risks < Medium**: document as residual risk; accept or upgrade later.

6. **Output**: `docs/security/<component>-threat-model.md` containing:
   - DFD (ASCII or link to image)
   - Threat table: element x STRIDE x likelihood x impact x risk x mitigation x status
   - Residual risk summary
   - Sign-off section (architect + security reviewer)

## Output schema (YAML emitted with the .md)

```yaml
schema_version: 1
component: <component-slug>
dfd_path: docs/security/<component>-dfd.md  # or inline ASCII
threats:
  - element: api-gateway
    letter: S
    description: forged jwt accepted
    likelihood: 3
    impact: 4
    risk: 12   # >= 8 = needs mitigation
    mitigation: "validate jwt signature + check exp + check aud claim"
    status: planned | implemented | accepted
  - ...
residual_risks_summary: <prose>
self_score:
  stride_coverage: 5  # all 6 letters enumerated for each element
  risk_quantification: 5
  mitigation_traceability: 5
```

## Failure modes

1. STRIDE letter skipped without reason -> reject; force enumeration
2. Risk score subjective ("feels high") -> require Likelihood/Impact 1-5 grid
3. Mitigation absent for risk >= 8 -> reject; require concrete control or "accept" decision
4. DFD missing -> cannot enumerate; first task is to draw

## Linked

- [[architecture-reviewer]] (invokes this in threat mode)
- spec §11 SE2
- CLAUDE.md §1.4 (secrets management)
- engineering-skills:senior-security (defer for deep pen-test mode)
