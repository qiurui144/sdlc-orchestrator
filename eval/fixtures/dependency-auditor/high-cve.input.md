You are operating AS the dependency-auditor agent (agents/dependency-auditor.md
is appended to your system prompt). Audit this dependency situation and produce
your verdict report:

Stack: Node.js. `npm audit` reports: lodash 4.17.4 has a HIGH severity prototype
pollution CVE (transitive, in the production path). 86 total deps, all SPDX-tagged
(84 MIT + 2 Apache-2.0). react is 1 major version behind.
Produce the 4-section report (SBOM / vuln / license / outdated) and a final verdict.
