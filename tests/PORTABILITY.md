# Portability rules (POSIX / bash 3.2 / BSD + GNU)

> Why this file exists: v0.2.0 shipped a "CI matrix" deliverable that went red on
> the first real push (postmortem: `docs/postmortems/2026-05-29-ci-red-dev-box-coupling.md`).
> The dev box ran GNU coreutils + bash 5 + PyYAML + had a `/data` mount, so
> GNU-only / bash-4-only / dev-box-specific constructs passed locally yet crashed
> on the macOS CI runner. This file lists the banned constructs and their portable
> replacements. **`tests/unit/test_portability.bats` enforces it mechanically** —
> reintroducing any of these fails the suite.

## Target environments

- **bash 3.2** (macOS system bash — last GPLv2 release; still the default `/bin/bash`)
- **bash 5.x** (Linux)
- **BSD userland** (macOS: `df`, `date`, `realpath`, `sed` differ from GNU)
- **GNU userland** (Linux)
- **No assumed Python / PyYAML**, **no assumed `/data` mount**

## Banned constructs → portable replacement

| Banned | Why it breaks | Use instead |
|--------|---------------|-------------|
| `declare -A` (associative array) | bash 4+ only; macOS bash 3.2 syntax-errors | Parallel `"key:value"` list + `${pair%%:*}` / `${pair#*:}` |
| `mapfile` / `readarray` | bash 4+ only | `while IFS= read -r line; do …; done` |
| `${var,,}` / `${var^^}` (case conversion) | bash 4+ only | `tr '[:upper:]' '[:lower:]'` |
| `df -BG` / `df -B<size>` | GNU-only block-size flag; BSD `df` rejects it | `df -P -k` (POSIX, 1024-byte blocks) then divide |
| `date -d` / `date -u -d '+N hours'` | GNU-only relative date; BSD `date` rejects `-d` | `TZ='Asia/Shanghai' date '+%Y-%m-%dT%H:%M:%S+08:00'` |
| `realpath --relative-to=` | GNU-only flag; BSD `realpath` lacks it | `cd "$dir" && pwd -P`, then strip prefix |
| bare `realpath "$0"` | not on all BSD installs | `cd "$(dirname "$0")/.." && pwd` |
| logical `pwd` for path matching | keeps symlinks; macOS `/var`→`/private/var` diverges from `git rev-parse` (physical) | `pwd -P` (physical) on **both** sides being compared |
| `python3 -c "import yaml"` | PyYAML not installed on macOS CI runner | `awk` to extract frontmatter block + `grep -E` to assert keys |
| `readlink -f` | GNU-only | `cd … && pwd -P` |
| `grep -P` (PCRE) | not in BSD grep | `grep -E` (ERE) |
| `sed -i` (no suffix) | GNU vs BSD differ (BSD needs `-i ''`) | write to temp + `mv`, or accept both forms explicitly |
| `base64 -w0` (unwrapped flag) | GNU-only flag; BSD `base64` rejects `-w` (and both wrap at 76 cols by default) | `base64 < f \| tr -d '\n'` — unwrap on BOTH platforms (a wrapped data-URI silently corrupts the image body; `ui-vision-judge/judge.sh` `encode_data_uri`) |

## Test-determinism rules (also dev-box couplings)

- **`CLAUDE_PLUGIN_ROOT`**: hook tests must `export CLAUDE_PLUGIN_ROOT="$BATS_TEST_DIRNAME/../.."` in `setup()`. Hooks fall back to it for `PLUGIN_ROOT`; if a test inherits an ambient value the result is non-deterministic (v0.2.0 "72 PASS" was env-luck).
- **`/data` mount**: never assume it exists. `disk-self-audit/audit.sh` treats an absent mount as *skipped*, not 0 GB. Tests that exercise disk logic must pin `SDLC_DISK_FAKE_ROOT_GB` / `_DATA_GB` / `_TMP_GB` rather than depend on the real machine.
- **Verify by hunting failure**: `bats … | grep -E "^not ok|instead of" || echo PASS`. Never judge by `tail -1` (hides mid-suite failures). Run the suite under both unset and hostile `CLAUDE_PLUGIN_ROOT`.

## Reproducing foreign environments locally

Portability bugs are mostly *behavioral* (path resolution, missing mounts), not statically greppable. Reproduce the foreign environment rather than theorize:

- **macOS `/var` symlink**: `real=$(mktemp -d); ln -s "$real" /tmp/sym; (cd /tmp/sym && git init)` then run the script via the symlinked path — exposes logical-vs-physical `pwd` divergence on Linux.
- **Missing `/data`**: `SDLC_DISK_FAKE_DATA_GB=0` (or test on a machine without `/data`).
- **Real CI**: the only true proof for a cross-platform claim is an observed-green run on `ubuntu-latest` + `macos-latest` (enforced by the releaser gate).

## Flaky pipes: `set -o pipefail` + an early-closing consumer = SIGPIPE race (SE16, v0.17)

The v0.17 flake: `test_pipeline_emit.bats` failed intermittently (~1/5; worse under load). Root cause
was NOT environment — it was a `pipefail` + early-pipe-close race in two scripts:

- `emit.sh` self-check `printf '%s\n' "$yaml" | grep -q "$stage"` — `grep -q` exits the instant it
  matches, closing the pipe; if `printf` hasn't finished, it gets SIGPIPE; under `set -o pipefail`
  the pipeline returns 141 → false "pipeline-missing-stage" → no yaml emitted → the test's downstream
  `grep` finds nothing → fail. It's a RACE (sometimes printf finishes first), so it's intermittent.
- `fanout.sh` slice `… | tr ',' '\n' | head -n "$n"` — `head` exits after N lines, closing the pipe
  → `tr` SIGPIPEs → same 141 under pipefail.

**Portable replacements (no early close):**
- instead of `printf "$x" | grep -q P` for control flow → `case "$x" in *P*) ;; *) … ;; esac` (no pipe).
- instead of `… | head -n N` → `… | awk -v n="$N" 'NR<=n'` (awk reads to EOF, never closes early).
- `… | head -1` (literal 1, single-match producer) is **low-risk**: the producer reaches EOF before
  head closes; leave those (audit.sh / jobs.sh / panel.sh `field`-style reads are fine).

**Verification discipline:** a flaky-test claim must be confirmed by stress-running **≥20×**, not once
(§2.3 multi-seed); a fix is only "done" when it passes ≥20/20 + the full suite is stable across several
recursive runs. (v0.17 fix: emit.sh + fanout.sh → 20/20 each, suite 3/3 clean.)
