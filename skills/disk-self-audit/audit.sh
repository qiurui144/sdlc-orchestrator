#!/usr/bin/env bash
set -euo pipefail

mode="warn"; reclaim=0; apply=0
for arg in "$@"; do
  case "$arg" in
    --strict)  mode=strict ;;
    --reclaim) reclaim=1 ;;
    --apply)   apply=1 ;;
    --dry-run) : ;;   # accepted no-op: the audit is read-only (never mutates)
  esac
done

# Redline precedence: env var > project .sdlc/disk.conf > machine config > built-in.
# A config FILE (unlike a shell env var) is visible to the CC-spawned hook subprocess and needs no
# session restart — the fix for a box whose / is small but whose work disk (/data) is large.
conf_get() {  # numeric value or non-zero
  [ -f "$1" ] || return 1
  local v
  v=$(grep -E "^[[:space:]]*$2[[:space:]]*=" "$1" 2>/dev/null | head -1 | sed 's/^[^=]*=//' | tr -d '[:space:]')
  case "$v" in ''|*[!0-9]*) return 1 ;; esac
  echo "$v"
}
conf_get_str() {  # string value or non-zero (for path lists)
  [ -f "$1" ] || return 1
  local v
  v=$(grep -E "^[[:space:]]*$2[[:space:]]*=" "$1" 2>/dev/null | head -1 | sed 's/^[^=]*=//' | tr -d '[:space:]')
  [ -n "$v" ] && { echo "$v"; return 0; }
  return 1
}

# Build/worktree scratch roots that accumulate cargo target*/ + mktemp worktrees + .tmp* and are the #1
# cause of silent /data bloat (the 253G dogfood incident). env > conf > default.
SCRATCH_ROOTS_DEFAULT="/data/tmp-sdlc:/data/tmp-cargo"
scratch_roots="$SCRATCH_ROOTS_DEFAULT"
for cf in "${HOME:-/root}/.config/sdlc-orchestrator/disk.conf" "$PWD/.sdlc/disk.conf"; do
  v=$(conf_get_str "$cf" scratch_roots) && scratch_roots="$v"
done
scratch_roots="${SDLC_SCRATCH_ROOTS:-$scratch_roots}"

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# --reclaim: VALUE-BASED reclamation. No-value = stale beyond the retention window AND not an active
# (uncommitted) worktree. NOT gated on disk fullness — valueless scratch is reclaimed regardless of how
# full /data is (a tmp dir untouched for weeks is reclaimable whether the disk is 10% or 90% full).
#   dry-run (default): list each entry as KEEP / RECLAIM with age + size + reason.
#   --apply:           rm -rf the RECLAIM entries (then suggest `git worktree prune`).
# Safety: NEVER a recent (< retention) entry; NEVER a worktree with uncommitted changes.
# ─────────────────────────────────────────────────────────────────────────────────────────────────
if [ "$reclaim" -eq 1 ]; then
  retention="${SDLC_SCRATCH_RETENTION_DAYS:-7}"
  case "$retention" in ''|*[!0-9]*) retention=7 ;; esac
  now=$(date +%s)
  [ "$apply" -eq 1 ] && echo "# sdlc scratch reclaim — MODE: APPLY (will rm -rf no-value entries)" \
                     || echo "# sdlc scratch reclaim — MODE: DRY-RUN (add --apply to reclaim)"
  echo "# value rule: reclaim entries older than ${retention}d that are NOT an active (dirty) worktree."
  echo "# roots: $scratch_roots   (SDLC_SCRATCH_ROOTS / disk.conf scratch_roots=; retention: SDLC_SCRATCH_RETENTION_DAYS)"
  oldifs=$IFS; IFS=':'
  # shellcheck disable=SC2086  # intentional split of the colon-list into roots
  set -- $scratch_roots
  IFS=$oldifs
  for r in "$@"; do
    # SAFETY (checked BEFORE any glob/rm): refuse a shallow/system root so a misconfigured
    # scratch_roots can never rm -rf top-level dirs. Canonicalize FIRST (cd+pwd -P) to collapse
    # './', '../' and symlinks — '/data/.' and '/./data' both resolve to /data, which the raw
    # segment count (2) wrongly accepted (F2, the dual-acceptance bypass). Then refuse known system
    # dirs outright, and require ≥2 real (non-'.'/'..') path segments.
    canon=$(cd "$r" 2>/dev/null && pwd -P) || canon=""
    [ -n "$canon" ] || canon="$r"   # absent dir → fall back to raw (still segment-checked below)
    case "$canon" in
      /|/data|/home|/usr|/etc|/var|/tmp|/root|/bin|/sbin|/lib|/lib64|/opt|/boot|/dev|/proc|/sys|/mnt|/media \
      |/private|/private/tmp|/private/var|/private/etc|/System|/Library|/Users|/Applications|/Volumes)
        # macOS canonicalizes /tmp→/private/tmp, /var→/private/var, /etc→/private/etc (symlinks), so the
        # /private/* forms must be blacklisted too — else pwd -P slips a system dir past the guard (CI macOS).
        echo "## $r  (REFUSED — resolves to system dir '$canon'; refusing to reclaim under it)"; continue ;;
    esac
    seg=$(printf '%s\n' "$canon" | awk -F/ '{c=0; for(i=1;i<=NF;i++) if($i!="" && $i!="." && $i!="..") c++; print c}')
    if [ "${seg:-0}" -lt 2 ]; then echo "## $r  (REFUSED — root too shallow; need ≥2 path segments for safety)"; continue; fi
    if [ ! -d "$r" ]; then echo "## $r  (absent — skip)"; continue; fi
    echo "## $r"
    for entry in "$r"/* "$r"/.[!.]*; do
      [ -e "$entry" ] || continue   # nullglob-off: skip the literal pattern when no match
      mt=$(stat -c %Y "$entry" 2>/dev/null || stat -f %m "$entry" 2>/dev/null || echo "$now")
      case "$mt" in ''|*[!0-9]*) mt="$now" ;; esac
      age_days=$(( (now - mt) / 86400 ))
      if [ "$age_days" -le "$retention" ]; then
        continue   # recent ⇒ has value (may be in use); silently keep
      fi
      # active-worktree guard: a git worktree is NEVER reclaimed if it has uncommitted changes OR if
      # its status can't be read (broken .git link) — when unsure, KEEP (N2 fail-safe; the old code
      # read an unreadable worktree as clean and would rm it). Command-sub (not | grep) so
      # set -e/pipefail stay safe on an early-closed pipe (SE16).
      if [ -e "$entry/.git" ]; then
        if ! git -C "$entry" status --porcelain >/dev/null 2>&1; then
          echo "  KEEP     $entry  (${age_days}d — has .git but status unreadable; kept to be safe)"
          continue
        fi
        if [ -n "$(git -C "$entry" status --porcelain 2>/dev/null || true)" ]; then
          echo "  KEEP     $entry  (${age_days}d — worktree with uncommitted changes)"
          continue
        fi
      fi
      sz=$(du -shx "$entry" 2>/dev/null | awk '{print $1}' || true)
      if [ "$apply" -eq 1 ]; then
        if rm -rf "$entry" 2>/dev/null; then echo "  RECLAIMED $entry  (${age_days}d, ${sz:-?})"
        else echo "  FAILED    $entry  (rm error)"; fi
      else
        echo "  RECLAIM  $entry  (${age_days}d, ${sz:-?})"
      fi
    done
  done
  if [ "$apply" -eq 1 ]; then
    echo "# done. Also run 'git -C <repo> worktree prune' to drop stale worktree admin entries."
  else
    echo "# DRY-RUN — add --apply to reclaim. Tune the window with SDLC_SCRATCH_RETENTION_DAYS (default 7)."
  fi
  exit 0
fi

RL_ROOT=50; RL_DATA=50; RL_TMP=5
for cf in "${HOME:-/root}/.config/sdlc-orchestrator/disk.conf" "$PWD/.sdlc/disk.conf"; do
  v=$(conf_get "$cf" redline_root_gb) && RL_ROOT="$v"
  v=$(conf_get "$cf" redline_data_gb) && RL_DATA="$v"
  v=$(conf_get "$cf" redline_tmp_gb)  && RL_TMP="$v"
done
RL_ROOT="${SDLC_DISK_REDLINE_ROOT_GB:-$RL_ROOT}"
RL_DATA="${SDLC_DISK_REDLINE_DATA_GB:-$RL_DATA}"
RL_TMP="${SDLC_DISK_REDLINE_TMP_GB:-$RL_TMP}"

# Available GB for a mount, POSIX-portable across GNU and BSD/macOS (df -P -k → col 4 = available KB).
avail_gb() {
  local kb
  kb=$(df -P -k "$1" 2>/dev/null | awk 'NR==2 {print $4}')
  case "$kb" in ''|*[!0-9]*) return 1 ;; esac   # no row / non-numeric → mount absent
  echo $(( kb / 1024 / 1024 ))
}
# Used % (df -P col 5, % stripped) — INFORMATIONAL only (no threshold gate; reclamation is value-based).
used_pct() {
  local p
  p=$(df -P -k "$1" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  case "$p" in ''|*[!0-9]*) echo "n/a"; return ;; esac
  echo "$p"
}

if [ -n "${SDLC_DISK_FAKE_ROOT_GB:-}" ]; then
  root_avail="$SDLC_DISK_FAKE_ROOT_GB"
  data_avail="${SDLC_DISK_FAKE_DATA_GB:-100}"
  tmp_avail="${SDLC_DISK_FAKE_TMP_GB:-10}"
  data_used_pct="${SDLC_DISK_FAKE_DATA_PCT:-n/a}"
else
  root_avail=$(avail_gb /) || root_avail=""
  data_avail=$(avail_gb /data) || data_avail=""   # /data is optional; absent → skip, NOT treated as 0
  tmp_avail=$(avail_gb /tmp) || tmp_avail=""
  data_used_pct=$(used_pct /data)
fi

ts_utc8=$(TZ='Asia/Shanghai' date '+%Y-%m-%dT%H:%M:%S+08:00')

cat <<EOF
disk_snapshot:
  root_avail_gb: ${root_avail:-n/a}
  data_avail_gb: ${data_avail:-n/a}
  tmp_avail_gb: ${tmp_avail:-n/a}
  data_used_pct: ${data_used_pct}   # informational only — NOT a reclamation trigger (reclaim is value-based)
  redline_root_gb: $RL_ROOT
  redline_data_gb: $RL_DATA
  redline_tmp_gb: $RL_TMP
  mode: $mode
  timestamp_utc8: $ts_utc8
EOF

# Hard redline = a mount's AVAILABLE space below the floor (ENOSPC build-safety, §1.1.6 — a build needs
# absolute headroom regardless of disk size). This is NOT a "how full" gate; routine fullness is handled
# by value-based --reclaim, not by blocking here.
hits=()
[ -n "$root_avail" ] && [ "$root_avail" -lt "$RL_ROOT" ] && hits+=("/ ($root_avail G < $RL_ROOT)")
[ -n "$data_avail" ] && [ "$data_avail" -lt "$RL_DATA" ] && hits+=("/data ($data_avail G < $RL_DATA)")
[ -n "$tmp_avail" ] && [ "$tmp_avail" -lt "$RL_TMP" ] && hits+=("/tmp ($tmp_avail G < $RL_TMP)")

if [ "${#hits[@]}" -gt 0 ]; then
  echo "disk-redline-hit: ${hits[*]}" >&2
  echo "" >&2
  echo "Suggested cleanup:" >&2
  echo "  - bash $0 --reclaim          # value-based: list stale (no-value) build/worktree scratch (dry-run)" >&2
  echo "  - bash $0 --reclaim --apply  # reclaim it (stale beyond retention, not an active worktree)" >&2
  echo "  - cargo clean ; git worktree list && git worktree remove <stale> ; docker system prune -af" >&2
  if [ "$mode" = "strict" ]; then exit 2; else exit 1; fi
fi

exit 0
