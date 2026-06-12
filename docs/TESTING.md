# Testing

This document describes how to run, extend, and understand the sdlc-orchestrator test suite.
See [`tests/TEST_PLAN.md`](../tests/TEST_PLAN.md) for the SSOT test matrix (25+ rows, per §6.1).

---

## Run all tests

```bash
./tests/run-all.sh
```

Runs unit tests first, then integration tests, and prints a final PASS/FAIL summary.
Requires bats-core ≥ 1.9 (see [docs/INSTALL.md](INSTALL.md#prerequisites)).

---

## Run unit tests only

```bash
bats tests/unit/
```

Unit tests cover individual shell scripts and YAML schema validators.
All unit tests are deterministic and complete in < 5 s on a modern machine.

---

## Run integration tests

```bash
bats tests/integration/
```

Integration tests spin up a temporary git repo (via `mktemp -d`) and exercise the full
skill + hook + stack-adapter wiring across the 7 SDLC phases. They may take 10–20 s.

---

## Test categories (per §6.1 6-category matrix)

| Category | What it covers | Example test IDs |
|----------|----------------|-----------------|
| **Happy path** | Normal inputs → expected outputs | U1, U5, U9, I1, I3, I6 |
| **Edge case** | Empty inputs, boundary values, missing files | U3, U6, U10, U15, I4 |
| **Error case** | Bad schema, illegal transitions, missing fields | U7, U8, U11, I2, I5 |
| **Adversarial** | Version-bound filenames, forbidden `.zh.md`, tasks/report filenames | U12, U13, U14 |
| **Concurrent / resource** | Disk redline triggers abort; multi-agent budget check | U18, U19, I3, I7 |
| **Regression** | Behaviour unchanged after refactors (re-run on every commit) | All `bats tests/` |

---

## Multi-seed (per §2.3)

Currently **not applicable**: v0.1 tests are deterministic shell + YAML — no LLM-driven paths
are exercised at the test layer.

When LLM-in-the-loop agent tests are added (planned v0.3), each scenario must pass with
N ≥ 3 independent seeds (`SDLC_LLM_SEED=1/2/3`) and report mean ± std. A scenario is only
considered passing if improvement exceeds 2σ over the control baseline (§2.3 multi-seed rule).

---

## CI matrix (planned v0.2)

| OS | bash version | bats version | Status |
|----|-------------|-------------|--------|
| Ubuntu 22.04 | 5.1 | 1.10 | planned |
| Ubuntu 20.04 | 5.0 | 1.9 | planned |
| macOS 14 (Homebrew bash) | 5.2 | 1.10 | planned |
| macOS 12 (system bash) | 3.2 | 1.9 | planned |

---

## Coverage targets (v0.1)

| Component | Target | Metric |
|-----------|--------|--------|
| Skills (bash scripts) | ≥ 80% | bats @test branches |
| Agents | 100% | frontmatter field conformance |
| Commands | 100% | frontmatter field conformance |
| Hooks | 100% | match / skip path coverage |
| Handoff schema | 100% | all valid + invalid YAML variants |
| Stack adapters | 100% | all 5 stacks detect + YAML fields present |

---

## Test naming conventions

- Files: `test_<component>.bats` (snake_case, no hyphens)
- Test descriptions (`@test`): `"<Component> — <scenario> <expected>"` in title case
  - Example: `@test "Disk audit — redline hit on /tmp returns exit 1"`
- Fixture files: `tests/fixtures/<descriptive-slug>.yaml` or `.json`

---

## Adding a new test

Follow the red-green cycle:

1. **Write a failing test** in the appropriate `tests/unit/` or `tests/integration/` bats file.
   ```bash
   @test "My component — new scenario returns exit 0" {
     run my_script.sh --new-flag
     [ "$status" -eq 0 ]
   }
   ```

2. **Run it and confirm FAIL**:
   ```bash
   bats tests/unit/test_my_component.bats
   # ✗ My component — new scenario returns exit 0 (expected 0, got 1)
   ```

3. **Implement the feature** until the test passes.

4. **Run the full suite** to confirm no regression:
   ```bash
   ./tests/run-all.sh
   ```

5. **Commit test and implementation together** (per §5.3):
   ```bash
   git add tests/unit/test_my_component.bats <impl-files>
   git commit -m "feat: <description>"
   ```

> Rule: every new feature or bug fix ships with at least one new `@test`. No exceptions.
