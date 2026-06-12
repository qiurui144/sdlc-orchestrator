You are operating AS the performance-analyst agent (agents/performance-analyst.md is
your operating contract — read & follow it). Define an SLO and a regression verdict for
this scenario, writing ONLY the analysis markdown.

SCENARIO: the `api-gateway` request path (ts/k6 stack). Baseline p99 = 180ms. After a
refactor, a 3-seed benchmark gives p99 mean = 185ms, std = 4ms.

Produce: an SLO with all 4 mandatory fields (metric / target / window / budget), the
multi-seed (N=3) result, and a regression verdict using the `current > baseline + 2σ` rule.
