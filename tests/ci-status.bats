#!/usr/bin/env bats
# tests/ci-status.bats — ci-green-gate matrix (gh-stub, ci-status verdicts, B1 diff-guard, B2 pre-gate).

STUB="$BATS_TEST_DIRNAME/fixtures/gh-stub.sh"

# ---------------------------------------------------------------------------
# Task 1: gh-stub mock fixture self-test
# ---------------------------------------------------------------------------

@test "gh-stub: run list returns success conclusion when STUB_CONCLUSION=success" {
  STUB_CONCLUSION=success run bash "$STUB" run list --json conclusion,status,databaseId,url
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"conclusion":"success"'
}

@test "gh-stub: run view --log-failed serves a failing-log fixture (N2)" {
  STUB_LOG=deny-license run bash "$STUB" run view 123 --log-failed
  [ "$status" -eq 0 ]
  case "$output" in *licenses*) ;; *) false ;; esac
}

@test "gh-stub: STUB_EOF=1 simulates partial-then-EOF (non-zero exit)" {
  STUB_EOF=1 run bash "$STUB" run list --json conclusion
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Task 2: ci-status.sh deterministic verdict (E1)
# ---------------------------------------------------------------------------

CS="$BATS_TEST_DIRNAME/../skills/ci-status/ci-status.sh"
cs() { SDLC_GH_BIN="$STUB" run bash "$CS" "$@"; }

@test "ci-status PASS: success conclusion → exit 0" {
  STUB_CONCLUSION=success cs --ref HEAD
  [ "$status" -eq 0 ]; echo "$output" | grep -q "ci-status: PASS"
}
@test "ci-status FAIL: failure conclusion → exit 1 + run url" {
  STUB_CONCLUSION=failure cs --ref HEAD
  [ "$status" -eq 1 ]; echo "$output" | grep -q "FAIL"; echo "$output" | grep -q "runs/12345678"
}
@test "ci-status IN_PROGRESS: status=in_progress → exit 3" {
  STUB_STATUS=in_progress STUB_CONCLUSION= cs --ref HEAD
  [ "$status" -eq 3 ]; echo "$output" | grep -q "IN_PROGRESS"
}
@test "ci-status NONE: empty run list → exit 5 (skip, not fail)" {
  STUB_EMPTY=1 cs --ref HEAD
  [ "$status" -eq 5 ]; echo "$output" | grep -q "NONE"
}
@test "ci-status UNKNOWN reversible default: gh EOF → exit 4 (WARN)" {
  STUB_EOF=1 cs --ref HEAD
  [ "$status" -eq 4 ]; echo "$output" | grep -q "UNKNOWN"; echo "$output" | grep -q "WARN"
}
@test "ci-status UNKNOWN irreversible: --require-known + gh EOF → BLOCK exit 4" {
  STUB_EOF=1 cs --ref HEAD --require-known
  [ "$status" -eq 4 ]; echo "$output" | grep -q "BLOCK"
}
@test "ci-status UNKNOWN opt-out: --require-known --allow-unknown → WARN" {
  STUB_EOF=1 cs --ref HEAD --require-known --allow-unknown
  [ "$status" -eq 4 ]; echo "$output" | grep -q "WARN"
}
@test "ci-status malformed JSON → UNKNOWN (not a false PASS/FAIL)" {
  STUB_MALFORMED=1 cs --ref HEAD
  [ "$status" -eq 4 ]
}
@test "ci-status cancelled → FAIL (not PASS)" {
  STUB_CONCLUSION=cancelled cs --ref HEAD
  [ "$status" -eq 1 ]
}
@test "ci-status --json emits verdict field" {
  STUB_CONCLUSION=failure cs --ref HEAD --json
  echo "$output" | grep -q '"verdict":"FAIL"'
}
@test "ci-status never leaks a token in output (R9)" {
  STUB_CONCLUSION=success cs --ref HEAD
  echo "$output" | grep -qiv "ghp_\|gho_\|token" || { echo "$output"; false; }
}
@test "ci-status bad arg → usage exit 2" {
  cs --bogus
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# C1: verdict MUST bind to the commit/ref — an unrelated green run never reads PASS
# ---------------------------------------------------------------------------

@test "C1: green run on ANOTHER branch + target ref has NO run → NONE, never PASS" {
  # The green run belongs to commit deadbeefcafe; we ask for a DIFFERENT ref.
  # ci-status.sh must resolve the ref to a SHA and pass `-c <SHA>` to gh, so the
  # stub returns [] for the mismatched commit → verdict NONE (skip), not PASS.
  STUB_CONCLUSION=success STUB_COMMIT=deadbeefcafe cs --ref feedface0000
  [ "$status" -ne 0 ]                       # MUST NOT be PASS
  echo "$output" | grep -q "PASS" && { echo "leaked PASS from unrelated run"; false; } || true
  [ "$status" -eq 5 ]                       # NONE — no run for THIS commit
}

@test "C1: nonexistent ref → NONE (reversible) — never a false PASS from latest repo-wide run" {
  STUB_CONCLUSION=success STUB_COMMIT=realcommit99 cs --ref ref-that-does-not-exist
  [ "$status" -ne 0 ]
  [ "$status" -eq 5 ]
}

@test "C1: nonexistent ref + --require-known → UNKNOWN BLOCK, never PASS" {
  STUB_CONCLUSION=success STUB_COMMIT=realcommit99 cs --ref ghost --require-known
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "PASS" && { echo "leaked PASS"; false; } || true
  case "$status" in 4|5) ;; *) echo "expected UNKNOWN/NONE, got $status"; false ;; esac
}

@test "C1: run DOES exist for the target commit → PASS binds correctly (no over-block)" {
  STUB_CONCLUSION=success STUB_COMMIT=mycommit42 cs --ref mycommit42
  [ "$status" -eq 0 ]; echo "$output" | grep -q "PASS"
}

@test "C1: red run bound to the target commit → FAIL (commit-bound, not masked)" {
  STUB_CONCLUSION=failure STUB_COMMIT=mycommit42 cs --ref mycommit42
  [ "$status" -eq 1 ]; echo "$output" | grep -q "FAIL"
}

# ---------------------------------------------------------------------------
# C2: reduce over ALL checks — one green among reds must NOT mask a red
# ---------------------------------------------------------------------------

@test "C2: [success, failure] → FAIL (a red check is not masked by a leading green)" {
  STUB_CHECKS="success;failure" cs --ref HEAD
  [ "$status" -eq 1 ]; echo "$output" | grep -q "FAIL"
}

@test "C2: [failure, success] → FAIL (order-independent reduce)" {
  STUB_CHECKS="failure;success" cs --ref HEAD
  [ "$status" -eq 1 ]
}

@test "C2: [success, success] → PASS (all green)" {
  STUB_CHECKS="success;success" cs --ref HEAD
  [ "$status" -eq 0 ]; echo "$output" | grep -q "PASS"
}

@test "C2: [success, :in_progress] → IN_PROGRESS (a pending check is not masked by a green)" {
  STUB_CHECKS="success:completed;:in_progress" cs --ref HEAD
  [ "$status" -eq 3 ]; echo "$output" | grep -q "IN_PROGRESS"
}

@test "C2: [success, cancelled] → FAIL (cancelled is a failure mode)" {
  STUB_CHECKS="success;cancelled" cs --ref HEAD
  [ "$status" -eq 1 ]
}

@test "C2: [success, skipped, neutral] → PASS (skipped/neutral are non-failing)" {
  STUB_CHECKS="success;skipped;neutral" cs --ref HEAD
  [ "$status" -eq 0 ]; echo "$output" | grep -q "PASS"
}

@test "C2 (--pr): [success, failure] on pr checks → FAIL (not .[0]-only)" {
  STUB_CHECKS="success;failure" cs --pr 7
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Task 3: diff-guard.sh — B1 safety core (REAL git staged diffs)
# ---------------------------------------------------------------------------

DG="$BATS_TEST_DIRNAME/../skills/ci-status/diff-guard.sh"
# helper: build a throwaway git repo, stage a real diff, run diff-guard.
# NOTE: diff-guard reads `git diff --cached` from $PWD, so each test must `cd "$TD"`
# in its OWN shell (not a subshell) before `run`, otherwise bats `$status` would not
# propagate out of a subshell. Cleanup `cd`s back to the repo before rm.
mkrepo() { TD=$(mktemp -d); ( cd "$TD" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir -p src tests .github/workflows && echo "fn a(){assert_eq!(1,1);}" > src/lib.rs \
  && printf 'workflow\n' > .github/workflows/ci.yml && git add -A && git commit -qm base ); echo "$TD"; }
dgteardown() { cd "$BATS_TEST_DIRNAME" || return; rm -rf "$TD"; }

@test "GUARD B1: diff edits a test file → REJECT exit 1" {
  TD=$(mkrepo); ( cd "$TD" && echo "fn t(){}" > src/foo_test.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}
@test "GUARD B1: diff adds #[ignore] → REJECT exit 1" {
  TD=$(mkrepo); ( cd "$TD" && printf '#[ignore]\nfn a(){assert_eq!(1,1);}\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}
@test "GUARD B1: diff nets assertions DOWN → REJECT exit 1" {
  TD=$(mkrepo); ( cd "$TD" && echo "fn a(){}" > src/lib.rs && git add -A )   # removed assert_eq!
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}
@test "GUARD B1: removes ONE assert from a 2-assert LINE → REJECT (occurrence count, not line count)" {
  # Adversarial (G3 probe): the line still contains an assert after the edit, so a
  # line-based count sees 1→1 (no drop) and would PASS. Occurrence count sees 2→1 → REJECT.
  TD=$(mkrepo)
  ( cd "$TD" && printf 'fn a(){ assert_eq!(1,1); assert_eq!(2,2); }\n' > src/lib.rs && git add -A && git commit -qm two \
    && printf 'fn a(){ assert_eq!(1,1); }\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}
@test "GUARD B1: diff touches .github/workflows/* → REJECT exit 1 (R8)" {
  TD=$(mkrepo); ( cd "$TD" && printf 'workflow edited\n' > .github/workflows/ci.yml && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}
@test "GUARD B1: A3 footprint overrun (edits non-deny.toml) → REJECT exit 1" {
  TD=$(mkrepo); ( cd "$TD" && echo "x" >> src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A3; [ "$status" -eq 1 ]
  dgteardown
}
@test "GUARD B1: A3 touching [advisories] in deny.toml → REJECT exit 1" {
  TD=$(mkrepo); ( cd "$TD" && printf '[advisories]\nignore=["RUSTSEC-2024-0001"]\n' > deny.toml && git add -A )
  cd "$TD"; run bash "$DG" --class A3; [ "$status" -eq 1 ]
  dgteardown
}
@test "GUARD B1 positive: clean A1 fmt whitespace diff in src/ → PASS exit 0" {
  TD=$(mkrepo); ( cd "$TD" && printf 'fn a(){ assert_eq!(1,1); }\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 0 ]
  dgteardown
}
@test "GUARD B1 positive: A3 appends [licenses].allow in deny.toml → PASS exit 0" {
  TD=$(mkrepo); ( cd "$TD" && printf '[licenses]\nallow=["MIT","Apache-2.0"]\n' > deny.toml && git add -A )
  cd "$TD"; run bash "$DG" --class A3; [ "$status" -eq 0 ]
  dgteardown
}
@test "GUARD B1 positive: A4 doc-sync edits *.md only → PASS exit 0 (no over-block)" {
  TD=$(mkrepo); ( cd "$TD" && printf '# Inventory\n18 agents\n' > README.md && git add -A )
  cd "$TD"; run bash "$DG" --class A4; [ "$status" -eq 0 ]
  dgteardown
}
@test "GUARD B1: bad/missing --class → usage exit 2" {
  TD=$(mkrepo); cd "$TD"; run bash "$DG" --class Z9; [ "$status" -eq 2 ]
  dgteardown
}

# ---------------------------------------------------------------------------
# C3: token-count REMOVED — A1 is a whitespace-only INVARIANT (tamper-proof)
# Every adversarial bypass that survived the assert-count must now REJECT.
# ---------------------------------------------------------------------------

@test "C3 bypass (neuter): expect(auth(pw)) → expect(true) (same count) → REJECT" {
  # Assertion-neutering keeps the `expect` count identical but guts the test.
  # A non-whitespace change → REJECTed by the whitespace-only A1 invariant.
  TD=$(mkrepo)
  ( cd "$TD" && printf 'fn v(){ expect(auth(pw)).toBe(true); }\n' > src/lib.rs && git add -A && git commit -qm seed \
    && printf 'fn v(){ expect(true).toBe(true); }\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "C3 bypass (comment-noise): delete 2 asserts, add /* assert assert */ comment → REJECT" {
  TD=$(mkrepo)
  ( cd "$TD" && printf 'fn a(){ assert_eq!(1,1); assert_eq!(2,2); }\n' > src/lib.rs && git add -A && git commit -qm two \
    && printf 'fn a(){ /* assert assert */ }\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "C3 bypass (bracket-inflate): remove asserts, add shell-test [ -z ] brackets → REJECT" {
  TD=$(mkrepo)
  ( cd "$TD" && printf 'fn a(){ assert_eq!(1,1); assert_eq!(2,2); }\n' > src/lib.rs && git add -A && git commit -qm two \
    && printf 'fn a(){ [ -z "$x" ] && [ -z "$y" ]; }\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "C3 bypass (W3 logic-gut): validate() body replaced with true → REJECT (formatter never deletes logic)" {
  TD=$(mkrepo)
  ( cd "$TD" && printf 'fn validate(p){ if p.len()<8 {return false} true }\n' > src/lib.rs && git add -A && git commit -qm seed \
    && printf 'fn validate(p){ true }\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "C3 positive: PURE-whitespace A1 reflow (no token change) → PASS exit 0" {
  # base src/lib.rs (from mkrepo) is the tight form `fn a(){assert_eq!(1,1);}`; a real
  # formatter reflows it across lines (adds spaces + splits) but changes NO token → PASS.
  TD=$(mkrepo)
  ( cd "$TD" && printf 'fn a() {\n    assert_eq!(1, 1);\n}\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 0 ]
  dgteardown
}

@test "C3: A2 is DROPPED from the auto-fix allowlist → usage exit 2 (lint escalates to human)" {
  TD=$(mkrepo); cd "$TD"; run bash "$DG" --class A2; [ "$status" -eq 2 ]
  dgteardown
}

# ---------------------------------------------------------------------------
# C4: broaden test-file detection across ecosystems (Go / Py / Java / JS / C#)
# ---------------------------------------------------------------------------

@test "C4 (Go path): edit src/foo_test.go → REJECT (path pattern *_test.go)" {
  TD=$(mkrepo); ( cd "$TD" && printf 'package x\nfunc TestA(t *testing.T){}\n' > src/foo_test.go && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "C4 (Go testify in src): remove require.Equal in src/helpers.go → REJECT (content marker func Test)" {
  TD=$(mkrepo)
  ( cd "$TD" && printf 'package x\nfunc TestAuth(t *testing.T){ require.Equal(t, a, b) }\n' > src/helpers.go && git add -A && git commit -qm seed \
    && printf 'package x\nfunc TestAuth(t *testing.T){ }\n' > src/helpers.go && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "C4 (Go t.Fatal in src): src/h.go with t.Fatal → REJECT (func Test content marker)" {
  TD=$(mkrepo); ( cd "$TD" && printf 'package x\nfunc TestX(t *testing.T){ if e!=nil { t.Fatal(e) } }\n' > src/h.go && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "C4 (Python conftest): edit conftest.py → REJECT (path pattern)" {
  TD=$(mkrepo); ( cd "$TD" && printf 'def fixture(): pass\n' > conftest.py && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "C4 (Python def test_ in src): src/util.py with def test_ → REJECT (content marker)" {
  TD=$(mkrepo); ( cd "$TD" && printf 'def test_login(): assert ok\n' > src/util.py && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "C4 (Java @Test + @Disabled in src): add @Disabled to a @Test → REJECT" {
  TD=$(mkrepo); ( cd "$TD" && printf 'class C { @Disabled @Test void a(){ assertThat(x).isTrue(); } }\n' > src/C.java && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "C4 (JS .t.ts path): edit auth.t.ts → REJECT (path pattern *.t.ts)" {
  TD=$(mkrepo); ( cd "$TD" && printf 'it("auth", () => {})\n' > src/auth.t.ts && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "C4 (JS describe in src): src/app.js with describe( → REJECT (content marker)" {
  TD=$(mkrepo); ( cd "$TD" && printf 'describe("auth", () => { it("ok", () => {}) })\n' > src/app.js && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "C4 (C# *Tests.cs path): edit AuthTests.cs → REJECT (path pattern *Tests.cs)" {
  TD=$(mkrepo); ( cd "$TD" && printf 'class AuthTests { [Fact] void A(){} }\n' > src/AuthTests.cs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

# ---------------------------------------------------------------------------
# W1 broadened skip/ignore markers
# ---------------------------------------------------------------------------

@test "W1 (@Disabled): adding @Disabled in a src file → REJECT" {
  TD=$(mkrepo); ( cd "$TD" && printf 'fn a(){assert_eq!(1,1);}\n@Disabled\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "W1 (t.Skipf): adding t.Skipf( → REJECT (only t.Skip was matched before)" {
  TD=$(mkrepo); ( cd "$TD" && printf 'fn a(){assert_eq!(1,1);}\nt.Skipf("x")\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "W1 (xit): adding xit( → REJECT" {
  TD=$(mkrepo); ( cd "$TD" && printf 'fn a(){assert_eq!(1,1);}\nxit("x")\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "W1 (pytest.skip): adding pytest.skip( → REJECT" {
  TD=$(mkrepo); ( cd "$TD" && printf 'fn a(){assert_eq!(1,1);}\npytest.skip("x")\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "W1 (@unittest.skip): adding @unittest.skip → REJECT" {
  TD=$(mkrepo); ( cd "$TD" && printf 'fn a(){assert_eq!(1,1);}\n@unittest.skip\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "W1 (@Ignore): adding @Ignore → REJECT" {
  TD=$(mkrepo); ( cd "$TD" && printf 'fn a(){assert_eq!(1,1);}\n@Ignore\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

@test "W1 (.xfail): adding .xfail → REJECT" {
  TD=$(mkrepo); ( cd "$TD" && printf 'fn a(){assert_eq!(1,1);}\nresult.xfail\n' > src/lib.rs && git add -A )
  cd "$TD"; run bash "$DG" --class A1; [ "$status" -eq 1 ]
  dgteardown
}

# ---------------------------------------------------------------------------
# Task 4: SKILL.md
# ---------------------------------------------------------------------------

@test "SKILL.md present with name + description frontmatter" {
  SK="$BATS_TEST_DIRNAME/../skills/ci-status/SKILL.md"
  [ -f "$SK" ]
  run awk '/^name: ci-status$/{n=1} /^description:/{d=1} END{exit (n&&d)?0:1}' "$SK"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Task 5: B2 deterministic advisory-vs-license pre-gate (runs BEFORE any LLM)
# ---------------------------------------------------------------------------

@test "B2 pre-gate: log with RUSTSEC → ESCALATE-security, exit 10 (LLM not asked)" {
  log="$(STUB_LOG=deny-advisory bash "$STUB" run view 1 --log-failed)"
  run bash "$CS" deny-classify "$log"
  [ "$status" -eq 10 ]; echo "$output" | grep -q "ESCALATE-security"
}
@test "B2 pre-gate: license-only log → A3-eligible exit 0" {
  log="$(STUB_LOG=deny-license bash "$STUB" run view 1 --log-failed)"
  run bash "$CS" deny-classify "$log"
  [ "$status" -eq 0 ]; echo "$output" | grep -q "A3-eligible"
}
@test "B2 pre-gate: license + advisory both → advisory wins ESCALATE-security" {
  log="$(STUB_LOG=deny-both bash "$STUB" run view 1 --log-failed)"
  run bash "$CS" deny-classify "$log"
  [ "$status" -eq 10 ]; echo "$output" | grep -q "ESCALATE-security"
}
@test "B2 pre-gate: unrecognized → DEFER-LLM exit 0" {
  run bash "$CS" deny-classify "some random failure"
  [ "$status" -eq 0 ]; echo "$output" | grep -q "DEFER-LLM"
}

# ---------------------------------------------------------------------------
# W4: deny-classify is case-insensitive (uppercase ADVISORIES/RUSTSEC still wins)
# and an empty/missing log fails SAFE to ESCALATE, never DEFER-LLM.
# ---------------------------------------------------------------------------

@test "W4: uppercase ADVISORIES → ESCALATE-security (case-insensitive firewall)" {
  run bash "$CS" deny-classify "error[ADVISORIES]: RUSTSEC-2024-0001"
  [ "$status" -eq 10 ]; echo "$output" | grep -q "ESCALATE-security"
}
@test "W4: mixed-case Advisories → ESCALATE-security" {
  run bash "$CS" deny-classify "Advisories check failed"
  [ "$status" -eq 10 ]
}
@test "W4: uppercase LICENSES → A3-eligible (case-insensitive license match)" {
  run bash "$CS" deny-classify "error[LICENSES]: MIT not in allow"
  [ "$status" -eq 0 ]; echo "$output" | grep -q "A3-eligible"
}
@test "W4: empty log → ESCALATE (fail-safe, NOT DEFER-LLM)" {
  run bash "$CS" deny-classify ""
  [ "$status" -eq 10 ]; echo "$output" | grep -q "ESCALATE"
  echo "$output" | grep -q "DEFER-LLM" && { echo "empty log must not DEFER"; false; } || true
}
@test "W4: missing log arg → ESCALATE (fail-safe)" {
  run bash "$CS" deny-classify
  [ "$status" -eq 10 ]
}

@test "E2 coupling: releaser.md rule 12 references ci-status.sh --require-known" {
  RL="$BATS_TEST_DIRNAME/../agents/releaser.md"
  run awk '/ci-status\.sh --require-known/{f=1} END{exit f?0:1}' "$RL"
  [ "$status" -eq 0 ]
}

@test "E2 coupling: pr-reviewer.md references ci-status.sh (reversible WARN path)" {
  PR="$BATS_TEST_DIRNAME/../agents/pr-reviewer.md"
  run awk '/ci-status\.sh/{f=1} END{exit f?0:1}' "$PR"
  [ "$status" -eq 0 ]
}

@test "ci-remediator.md has model_tier frontmatter (Hard constraint #6)" {
  AG="$BATS_TEST_DIRNAME/../agents/ci-remediator.md"
  [ -f "$AG" ]
  run awk '/^model_tier: (opus|sonnet|haiku)/{f=1} END{exit f?0:1}' "$AG"
  [ "$status" -eq 0 ]
}
@test "ci-remediator wires diff-guard before commit + B2 pre-gate + bounded loop" {
  AG="$BATS_TEST_DIRNAME/../agents/ci-remediator.md"
  run awk '/diff-guard\.sh/{f=1} END{exit f?0:1}' "$AG"; [ "$status" -eq 0 ]
  run awk '/deny-classify|advisory pre-gate/{f=1} END{exit f?0:1}' "$AG"; [ "$status" -eq 0 ]
  run awk '/MAX_REMEDIATION/{f=1} END{exit f?0:1}' "$AG"; [ "$status" -eq 0 ]
}
@test "ci-remediator names the escalate-always classes (test/logic/security)" {
  AG="$BATS_TEST_DIRNAME/../agents/ci-remediator.md"
  run awk '/ESCALATE-always|MUST-ESCALATE|MUST ESCALATE/{f=1} END{exit f?0:1}' "$AG"; [ "$status" -eq 0 ]
}
@test "C3: ci-remediator declares THREE auto-fix classes (A2 dropped, lint escalates)" {
  AG="$BATS_TEST_DIRNAME/../agents/ci-remediator.md"
  # must say "three" auto-fix classes and explicitly that A2/lint is no longer auto-fixed.
  run awk '/[Tt]hree (auto-fix|narrowly)|3 auto-fix/{f=1} END{exit f?0:1}' "$AG"; [ "$status" -eq 0 ]
  # diff-guard --class invocations must be A1|A3|A4 only — never A2.
  run awk '/diff-guard\.sh --class A2|--class <A1\|A2/{bad=1} END{exit bad?1:0}' "$AG"; [ "$status" -eq 0 ]
}
@test "C3: spec declares THREE auto-fix classes + A1 whitespace-only invariant" {
  SP="$BATS_TEST_DIRNAME/../docs/superpowers/specs/2026-06-05-ci-green-gate.md"
  run awk '/[Tt]hree auto-fix|3 auto-fix/{f=1} END{exit f?0:1}' "$SP"; [ "$status" -eq 0 ]
  run awk '/whitespace-only/{f=1} END{exit f?0:1}' "$SP"; [ "$status" -eq 0 ]
}
@test "C3: diff-guard.sh rejects --class A2 as usage (A2 not in allowlist)" {
  DG2="$BATS_TEST_DIRNAME/../skills/ci-status/diff-guard.sh"
  run bash "$DG2" --class A2; [ "$status" -eq 2 ]
  run bash "$DG2" --class A1 --help 2>/dev/null || true
}
@test "ci-remediator agent body >= 250 lines (rubric E.2 depth)" {
  AG="$BATS_TEST_DIRNAME/../agents/ci-remediator.md"
  run awk 'END{exit (NR>=250)?0:1}' "$AG"; [ "$status" -eq 0 ]
}
@test "ci-remediator has no hardcoded cargo/npm fix literal (stack-config SSOT)" {
  AG="$BATS_TEST_DIRNAME/../agents/ci-remediator.md"
  # the FIX command must come from config/stack-*.yaml, not a baked-in 'cargo fmt'/'npm run'.
  run awk '/`cargo fmt`|`cargo clippy --fix`|`npm run lint -- --fix`/{f=1} END{exit f?1:0}' "$AG"
  [ "$status" -eq 0 ]
}

@test "promote.md exists and calls ci-status.sh --require-known + tagged assertion" {
  PM="$BATS_TEST_DIRNAME/../commands/promote.md"
  [ -f "$PM" ]
  run awk '/ci-status\.sh --require-known/{f=1} END{exit f?0:1}' "$PM"; [ "$status" -eq 0 ]
  run awk '/git (tag|describe)|tagged/{f=1} END{exit f?0:1}' "$PM"; [ "$status" -eq 0 ]
}
@test "promote.md has a description frontmatter line" {
  PM="$BATS_TEST_DIRNAME/../commands/promote.md"
  fm=$(awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$PM")
  echo "$fm" | grep -qE "^description: .+"
}

@test "dogfood: plugin.json + README declare 18 agents / 28 skills / 30 commands / 3 hooks" {
  PJ="$BATS_TEST_DIRNAME/../.claude-plugin/plugin.json"
  RM="$BATS_TEST_DIRNAME/../README.md"
  run awk '/18 agents, 28 skills, 30 slash commands, 3 hooks/{f=1} END{exit f?0:1}' "$PJ"; [ "$status" -eq 0 ]
  run awk '/18 agents, 28 skills, 30 slash/{f=1} END{exit f?0:1}' "$RM"; [ "$status" -eq 0 ]
}
@test "dogfood: declared counts match the real FS counts (no drift)" {
  D="$BATS_TEST_DIRNAME/.."
  a=$(find "$D/agents" -maxdepth 1 -name '*.md' -type f | awk 'END{print NR}')
  s=$(find "$D/skills" -mindepth 2 -maxdepth 2 -name 'SKILL.md' -type f | awk 'END{print NR}')
  c=$(find "$D/commands" -maxdepth 1 -name '*.md' -type f | awk 'END{print NR}')
  [ "$a" -eq 18 ]; [ "$s" -eq 28 ]; [ "$c" -eq 30 ]
}

@test "META coupling: releaser + pr-reviewer + promote reference ci-status.sh; remediator references diff-guard.sh" {
  D="$BATS_TEST_DIRNAME/.."
  for f in agents/releaser.md agents/pr-reviewer.md commands/promote.md; do
    run awk '/ci-status\.sh/{f=1} END{exit f?0:1}' "$D/$f"; [ "$status" -eq 0 ]
  done
  run awk '/diff-guard\.sh/{f=1} END{exit f?0:1}' "$D/agents/ci-remediator.md"; [ "$status" -eq 0 ]
}
@test "META coupling: doc-audit.sh --strict is CLEAN on the tracked tree (dogfood)" {
  D="$BATS_TEST_DIRNAME/.."
  TREE=$(mktemp -d)
  ( cd "$D" && git archive HEAD | tar -x -C "$TREE" )
  run env SDLC_DOC_ROOT="$TREE" bash "$D/scripts/doc-audit.sh" --strict
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CLEAN"
  rm -rf "$TREE"
}

# ---------------------------------------------------------------------------
# v0.25.1: ci-remediator is WIRED into the /sdlc:run drive (not an orphan).
# Coupling guards — fail if a future edit decouples the auto-remediation from run.
# ---------------------------------------------------------------------------
@test "v0.25.1 wiring: task-orchestrator drive dispatches ci-remediator on a red ci-status" {
  TO="$BATS_TEST_DIRNAME/../agents/task-orchestrator.md"
  run awk '/ci-remediator/{a=1} /ci-status/{b=1} END{exit (a&&b)?0:1}' "$TO"
  [ "$status" -eq 0 ]
}
@test "v0.25.1 wiring: run.md documents CI gate + bounded auto-remediation (diff-guard) as auto-triggered" {
  RM="$BATS_TEST_DIRNAME/../commands/run.md"
  run awk '/ci-remediator/{a=1} /ci-status/{b=1} /diff-guard/{c=1} END{exit (a&&b&&c)?0:1}' "$RM"
  [ "$status" -eq 0 ]
}
