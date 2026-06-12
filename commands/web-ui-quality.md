---
description: Run web-UI quality gates (a11y WCAG 2.1 AA / visual regression / responsive / Lighthouse CWV) on a UI-1-PASS page. Dispatches skills/web-ui-quality/quality.sh; deterministic verdicts, ui-vision-judge advisory-only. Real chrome-devtools-mcp reads PENDING-VERIFY.
argument-hint: "[--gate a11y|visual|responsive|perf] [--repo <dir>] [--url <u>] [--write-baseline]"
allowed-tools: [Read, Bash, Skill]
---

# /sdlc:web-ui-quality

Run the **web-ui-quality** gates over a page that already passes `/sdlc:web-ui-verify` (UI-1). Each gate
is a DETERMINISTIC verdict; ui-vision-judge is consumed by the visual gate as an ADVISORY annotation
only (it never decides). Facts come from real Chrome (chrome-devtools-mcp): the lighthouse accessibility
audit, a performance trace (LCP/CLS/TBT), viewport resize + layout reads, and a screenshot vs baseline.

Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/web-ui-quality/quality.sh" --repo <dir> [--gate <g>] [--url <u>] [--write-baseline]`

Exit: 0 all PASS / UI-UNVERIFIED-WARN · 2 usage/all-disabled · 6 §6.4 lint · 7 contract/baseline ·
8 a11y · 9 visual · 10 responsive · 11 perf. Establish visual baselines ONCE with `--write-baseline`
(commit them via `git add -f` past the `*.png` gitignore); a normal run with a missing baseline fails
closed (exit 7), never auto-writes.

**Deterministic-verdict-supremacy:** the visual gate's ui-vision-judge classification is an advisory
annotation only — the FAIL is decided by the deterministic diff-ratio + max-region thresholds; vision
never flips a verdict in either direction. The UI-1 `web-ui-verify` engine is byte-unchanged.

**Honesty (§7.3):** the real chrome-devtools-mcp lighthouse / trace / resize reads are PENDING-VERIFY —
the deterministic gate logic (count / ratio / region / mean / σ thresholds, fail-closed) is fully
bats-covered behind the `SDLC_*`/`--stub` seam. The visual gate's provider key (for the advisory vision
annotation) is env-only and redacted (§1.4).
