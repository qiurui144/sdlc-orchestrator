---
description: SBOM + vuln scan + license check + outdated detection. Dispatches dependency-auditor (haiku).
allowed-tools: [Read, Bash, Glob, Grep, Edit, Agent]
---

# /sdlc:deps

Invokes **dependency-auditor** (haiku). Stack-native tool (cargo audit / npm audit / pip-audit / govulncheck). Per spec G.2.3.

## Behavior

1. Stack detect (Cargo.toml / package.json / requirements.txt / go.mod)
2. Run native audit tool
3. Produce SBOM list
4. CVE severity >= High -> BLOCK verdict; must fix before `/sdlc:release`
5. License whitelist check (MIT / Apache-2.0 / BSD / ISC default; flag others)
6. Outdated: major-behind > 2 -> flag for upgrade
7. Report `reports/<date>_deps.md`

## Preconditions

- Lock file present (Cargo.lock / package-lock.json / requirements.txt / go.sum)
- Audit tool installed (dependency-auditor installs if missing)

## Next step

PASS -> unblock `/sdlc:release`.
BLOCK -> fix CVEs; re-run `/sdlc:deps`.
