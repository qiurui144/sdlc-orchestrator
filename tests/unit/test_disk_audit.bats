#!/usr/bin/env bats

AUDIT="$BATS_TEST_DIRNAME/../../skills/disk-self-audit/audit.sh"

@test "audit emits 3 mount points" {
  run "$AUDIT" --dry-run
  [[ "$output" == *"root_avail_gb"* ]]
  [[ "$output" == *"data_avail_gb"* ]]
  [[ "$output" == *"tmp_avail_gb"* ]]
}

@test "redline simulated via env var triggers exit 2" {
  run env SDLC_DISK_FAKE_ROOT_GB=10 SDLC_DISK_FAKE_DATA_GB=100 SDLC_DISK_FAKE_TMP_GB=10 "$AUDIT" --strict
  [ "$status" -eq 2 ]
  [[ "$output" == *"disk-redline-hit"* ]]
}

@test "redline simulated above threshold is OK" {
  run env SDLC_DISK_FAKE_ROOT_GB=100 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=20 "$AUDIT" --strict
  [ "$status" -eq 0 ]
}

@test "config override for redline" {
  run env SDLC_DISK_REDLINE_ROOT_GB=5 SDLC_DISK_FAKE_ROOT_GB=10 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=20 "$AUDIT" --strict
  [ "$status" -eq 0 ]
}

@test "redline read from project .sdlc/disk.conf (file visible to hook subprocess, no restart)" {
  # Real fix from dogfood: env doesn't reach the CC-spawned hook process, but a config
  # file does. A box with small / + dedicated /data calibrates the redline via a file.
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  mkdir -p "$tmp/.sdlc"
  printf 'redline_root_gb=20\n' > "$tmp/.sdlc/disk.conf"
  # fake / at 32G: default 50 would FAIL, but file says 20 → PASS
  run env SDLC_DISK_FAKE_ROOT_GB=32 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=20 bash -c "cd '$tmp' && '$AUDIT' --strict"
  [ "$status" -eq 0 ]
}

@test "env var overrides project disk.conf (precedence env > file)" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  mkdir -p "$tmp/.sdlc"
  printf 'redline_root_gb=20\n' > "$tmp/.sdlc/disk.conf"
  # file says 20 (would pass at 32), but env forces 50 → 32 < 50 → FAIL (env wins)
  run env SDLC_DISK_REDLINE_ROOT_GB=50 SDLC_DISK_FAKE_ROOT_GB=32 SDLC_DISK_FAKE_DATA_GB=200 SDLC_DISK_FAKE_TMP_GB=20 bash -c "cd '$tmp' && '$AUDIT' --strict"
  [ "$status" -eq 2 ]
}

# --- snapshot: data_used_pct is INFORMATIONAL only (no threshold gate; reclamation is value-based) ---
@test "snapshot includes data_used_pct (informational), and NO redline_data_pct threshold" {
  run "$AUDIT" --dry-run
  [[ "$output" == *"data_used_pct"* ]]
  [[ "$output" != *"redline_data_pct"* ]]
}
@test "avail-floor hit STILL hard-blocks in --strict (ENOSPC build-safety — NOT a fullness gate)" {
  run env SDLC_DISK_FAKE_ROOT_GB=100 SDLC_DISK_FAKE_DATA_GB=10 SDLC_DISK_FAKE_TMP_GB=20 "$AUDIT" --strict
  [ "$status" -eq 2 ]; [[ "$output" == *"disk-redline-hit"* ]]
}

# --- value-based reclaim: stale (no-value) ⇒ reclaim, regardless of disk fullness ---
@test "--reclaim (dry-run): stale entry ⇒ RECLAIM, recent entry ⇒ kept, nothing deleted" {
  t=$(mktemp -d); trap "rm -rf $t" EXIT
  mkdir -p "$t/old-target" "$t/recent-target"
  touch -t 202401010000 "$t/old-target"    # ancient ⇒ stale (no value)
  run env SDLC_SCRATCH_ROOTS="$t" SDLC_SCRATCH_RETENTION_DAYS=7 "$AUDIT" --reclaim
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
  [[ "$output" == *"old-target"* ]]        # stale listed
  [[ "$output" != *"recent-target"* ]]     # recent has value ⇒ silently kept
  [ -d "$t/old-target" ]                    # dry-run: NEVER deletes
}
@test "--reclaim --apply: reclaims stale, keeps recent (regardless of disk %)" {
  t=$(mktemp -d); trap "rm -rf $t" EXIT
  mkdir -p "$t/old" "$t/recent"; touch -t 202401010000 "$t/old"
  run env SDLC_SCRATCH_ROOTS="$t" SDLC_SCRATCH_RETENTION_DAYS=7 "$AUDIT" --reclaim --apply
  [ "$status" -eq 0 ]; [[ "$output" == *"RECLAIMED"* ]]
  [ ! -e "$t/old" ]    # stale gone
  [ -d "$t/recent" ]   # recent survives
}
@test "--reclaim NEVER removes an active (dirty) worktree even if stale" {
  t=$(mktemp -d); trap "rm -rf $t" EXIT
  repo="$t/repo"; mkdir -p "$repo"
  ( cd "$repo" && git init -q && git -c user.email=a@b -c user.name=a commit -q --allow-empty -m init )
  mkdir -p "$t/scratch"; wt="$t/scratch/wt1"
  ( cd "$repo" && git worktree add -q "$wt" -b wt1 )
  echo dirty > "$wt/uncommitted.txt"        # untracked ⇒ dirty
  touch -t 202401010000 "$wt"               # stale
  run env SDLC_SCRATCH_ROOTS="$t/scratch" SDLC_SCRATCH_RETENTION_DAYS=7 "$AUDIT" --reclaim --apply
  [ "$status" -eq 0 ]; [[ "$output" == *"KEEP"* ]]
  [ -d "$wt" ]   # uncommitted work preserved
}
@test "--reclaim retention window configurable (no fullness threshold involved)" {
  t=$(mktemp -d); trap "rm -rf $t" EXIT
  mkdir -p "$t/d"; touch -t 202401010000 "$t/d"   # ancient
  run env SDLC_SCRATCH_ROOTS="$t" SDLC_SCRATCH_RETENTION_DAYS=99999 "$AUDIT" --reclaim
  [[ "$output" != *"$t/d"* ]]    # within a huge window ⇒ not stale ⇒ kept
  run env SDLC_SCRATCH_ROOTS="$t" SDLC_SCRATCH_RETENTION_DAYS=1 "$AUDIT" --reclaim
  [[ "$output" == *"$t/d"* ]]    # 1-day window ⇒ ancient is stale ⇒ listed
}
@test "--reclaim on an absent root is graceful" {
  # ≥2 segments so it reaches the absent-skip (the depth guard short-circuits 1-segment paths first).
  run env SDLC_SCRATCH_ROOTS="/data/nonexistent-scratch-xyz" "$AUDIT" --reclaim
  [ "$status" -eq 0 ]; [[ "$output" == *"absent"* ]]
}
@test "--reclaim REFUSES a shallow/system root before any glob (never rm top-level dirs)" {
  # 1-segment path → refused regardless of existence; even with --apply it never reaches the rm.
  run env SDLC_SCRATCH_ROOTS="/zzz-shallow-xyz" "$AUDIT" --reclaim --apply
  [ "$status" -eq 0 ]; [[ "$output" == *"REFUSED"* ]]
  # '/' and '/data' (0 and 1 segment) are likewise refused.
  run env SDLC_SCRATCH_ROOTS="/" "$AUDIT" --reclaim --apply
  [[ "$output" == *"REFUSED"* ]]
}
@test "--reclaim REFUSES a root that RESOLVES to a system dir via . or .. (F2 bypass closed)" {
  # dry-run (never deletes): '/data/.' '/./data' '/tmp/.' '/usr/..' all canonicalize to a system dir.
  for root in "/data/." "/./data" "/tmp/." "/usr/.."; do
    run env SDLC_SCRATCH_ROOTS="$root" "$AUDIT" --reclaim
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFUSED"* ]] || { echo "NOT REFUSED for $root => $output"; false; }
  done
}
@test "--reclaim --apply KEEPS a broken worktree (.git unreadable) — N2 fail-safe" {
  t=$(mktemp -d); trap "rm -rf $t" EXIT
  mkdir -p "$t/scratch/wt"
  echo "gitdir: /nonexistent/broken-link" > "$t/scratch/wt/.git"   # broken → git status errors
  echo data > "$t/scratch/wt/uncommitted.txt"
  touch -t 202401010000 "$t/scratch/wt"                            # stale
  run env SDLC_SCRATCH_ROOTS="$t/scratch" SDLC_SCRATCH_RETENTION_DAYS=7 "$AUDIT" --reclaim --apply
  [ "$status" -eq 0 ]; [[ "$output" == *"KEEP"* ]]
  [ -d "$t/scratch/wt" ]   # unsure → preserved, not rm'd
}
