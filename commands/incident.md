---
description: Incident severity classify + runbook + postmortem per CLAUDE.md §9.3. Dispatches incident-responder (opus).
argument-hint: <SEV1|SEV2|SEV3|SEV4>
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent]
---

# /sdlc:incident <severity>

Invokes **incident-responder** (opus). Per spec G.2.5 + CLAUDE.md §9.3. 7-section postmortem mandatory.

## Behavior

1. Classify severity (or accept user-provided SEV1-SEV4)
2. Start runbook (during incident) at `docs/runbooks/<date>-<slug>-runbook.md`
3. After resolution: 24h cool-off (SEV1/2) or 7d (SEV3/4) before postmortem
4. Draft postmortem at `docs/postmortems/<YYYY-MM-DD>-<slug>.md`
5. 5-Why root cause must descend past code-level to process/SOP/culture level
6. Action items with explicit owner + deadline (no open-ended items)
7. Report `reports/<date>_incident.md`

## Preconditions

- Incident description provided (what failed, when, impact scope)

## Severity reference

| SEV | Meaning | Response SLA |
|-----|---------|--------------|
| SEV1 | Data loss / security breach / complete outage | Immediate; 24h postmortem cool-off |
| SEV2 | Major feature broken for all users | 2h response; 24h postmortem cool-off |
| SEV3 | Significant degradation / partial outage | 8h response; 7d postmortem cool-off |
| SEV4 | Minor issue / cosmetic | Next sprint; optional postmortem |

## Next step

Action items feed into task tracker. Regression tests added for each root cause.
Postmortem linked from RELEASE.md Known Limitations if unresolved.
