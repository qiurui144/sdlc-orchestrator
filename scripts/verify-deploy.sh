#!/usr/bin/env bash
# verify-deploy.sh — §7.3 本机部署验证 (local deployment verification).
# Packages the plugin, INSTALLS it to a clean dir (extracted tarball — NOT the dev tree),
# and exercises every executable component FROM THE INSTALLED LOCATION. This catches
# dev≠packaged gaps that the dev-tree test suite cannot (e.g. a skill sourcing a file that
# package.sh forgot to ship — the v0.16 eval/ blocker). Read-only w.r.t. the repo; all work
# in a mktemp dir cleaned on exit (§1.1.6 / §4.3 trap).
#
# Scope boundary (honest, §1.2): this verifies the DETERMINISTIC installed surface (manifest
# load, component presence, every bash skill/hook script running from the install). The
# LLM-driven north-star (/sdlc:spec→…→/sdlc:release via the live harness dispatching real
# model agents) is a HARNESS action requiring the harness to load the installed plugin + real
# model budget — that is the user's final §7.2 acceptance run, NOT covered here.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$HERE/.." && pwd -P)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fails=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }
ck()   { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }

ver=$(yq -r '.version' "$ROOT/.claude-plugin/plugin.json")
echo "== §7.3 本机部署验证: sdlc-orchestrator v$ver =="

echo "[1] package"
if DIST_DIR="$WORK/dist" bash "$ROOT/scripts/package.sh" "v$ver" >/dev/null 2>&1; then
  pass "package.sh → tarball"
else
  fail "package.sh"; echo "ABORT (cannot package)"; exit 1
fi
tarball="$WORK/dist/sdlc-orchestrator-v$ver.tar.gz"

echo "[2] install (extract to clean dir — simulates ~/.claude/plugins/<name>/)"
I="$WORK/install"; mkdir -p "$I"
ck "extract tarball" "tar -xzf '$tarball' -C '$I'"

echo "[3] manifest loads from install"
ck "manifest valid json + name" "jq -e '.name==\"sdlc-orchestrator\"' '$I/.claude-plugin/plugin.json'"
ck "manifest version matches" "[ \"\$(jq -r .version '$I/.claude-plugin/plugin.json')\" = '$ver' ]"

echo "[4] component presence (installed)"
ck "agents present"   "ls '$I'/agents/*.md"
ck "commands present" "ls '$I'/commands/*.md"
ck "skills present"   "ls -d '$I'/skills/*/"
ck "hooks present"    "[ -f '$I/hooks/hooks.json' ]"
ck "config present"   "ls '$I'/config/stack-*.yaml"
ck "eval/judge.sh shipped (panel dep)" "[ -f '$I/eval/judge.sh' ]"
ck "no dev artifacts (tests/docs/reports)" "! ls -d '$I'/tests '$I'/docs '$I'/reports 2>/dev/null | grep -q ."

echo "[5] every agent/command/skill frontmatter parses (installed)"
fm=0
for f in "$I"/agents/*.md "$I"/commands/*.md "$I"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  # valid frontmatter = line 1 is '---' AND at least 2 fence lines (open + close)
  if [ "$(head -1 "$f")" = "---" ] && [ "$(grep -c '^---$' "$f")" -ge 2 ]; then
    :
  else
    fm=1; echo "    bad frontmatter: ${f#"$I"/}"
  fi
done
if [ "$fm" -eq 0 ]; then pass "all frontmatter has --- fences"; else fail "frontmatter fences"; fi

echo "[6] hooks.json scripts exist (installed)"
hk=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ -f "$I/$rel" ] || { hk=1; echo "    missing: $rel"; }
done < <(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/[^"]+' "$I/hooks/hooks.json" | sed 's|.*}/||')
if [ "$hk" -eq 0 ]; then pass "hook scripts present"; else fail "hook scripts"; fi

echo "[7] exercise executable surface FROM INSTALL"
# pipeline-emit
ck "emit.sh rust → valid yaml" "SDLC_CONFIG_DIR='$I/config' bash '$I/skills/pipeline-emit/emit.sh' --stack rust | yq ."
# async-dispatch
ck "jobs.sh register+inflight" "SDLC_JOBS_DIR='$WORK/jobs' bash '$I/skills/async-dispatch/jobs.sh' register --id d --label x && [ \"\$(SDLC_JOBS_DIR='$WORK/jobs' bash '$I/skills/async-dispatch/jobs.sh' inflight)\" = 1 ]"
# challenger-panel (sources eval/judge.sh — the v0.16 blocker)
mkdir -p "$WORK/votes"; printf 'VERDICT: PASS\nSCORE: 5\nLENS: x\nREASON: y\n' > "$WORK/votes/a.json"
ck "panel.sh consensus (eval/judge.sh wired)" "bash '$I/skills/challenger-panel/panel.sh' --consensus --votes-dir '$WORK/votes' --high-risk no | grep -q AUTO_ADVANCE"
# i18n
ck "lang.sh zh msg" "[ -n \"\$(SDLC_LANG=zh bash '$I/skills/i18n/lang.sh' msg gate.advance)\" ]"
# disk-self-audit (fake redline → exit 2 under strict)
ck "audit.sh redline → exit 2" "! SDLC_DISK_FAKE_ROOT_GB=1 bash '$I/skills/disk-self-audit/audit.sh' --strict"
# worktree-merge + merge-queue on a temp git repo
G="$WORK/repo"; mkdir -p "$G"
( cd "$G" && git init -q -b main && git config user.email t@t && git config user.name t \
  && echo base > base.txt && git add . && git commit -qm base && git tag v0.1.0 \
  && git checkout -q -b f1 && echo a > a.txt && git add . && git commit -qm a && git checkout -q main ) >/dev/null 2>&1
ck "merge.sh clean merge"  "( cd '$G' && bash '$I/skills/worktree-merge/merge.sh' --base main --branches f1 ) | grep -q merged=f1"
ck "queue.sh merge+tag"    "( cd '$G' && git checkout -q -b f2 main && echo b > b.txt && git add . && git commit -qm b && git checkout -q main && bash '$I/skills/merge-queue/queue.sh' --base main --features f2 ) | grep -qE 'merged=f2 tag=v0.1.'"
# handoff-schema validate (v2) on a temp git repo with a real artifact
( cd "$G" && sha=$(git hash-object base.txt) && cat > h.yaml <<EOF
schema_version: 2
sprint_id: verify
phase_from: spec
phase_to: plan
artifact_path: base.txt
artifact_sha: $sha
timestamp_utc8: 2026-06-02T12:00:00+08:00
producer: spec-analyst
model_tier: opus
self_score: {rubric_ref: "x#e", overall: 4.5}
EOF
) >/dev/null 2>&1
ck "validate.sh v2 handoff" "( cd '$G' && bash '$I/skills/handoff-schema/validate.sh' h.yaml )"

if [ "$fails" -eq 0 ]; then
  echo "== result: ALL PASS — installed artifact functional =="
  echo "NOTE: LLM-driven north-star (/sdlc:spec→release via the live harness dispatching model"
  echo "      agents) = user's §7.2 acceptance run; NOT covered by this deterministic verify."
  exit 0
else
  echo "== result: $fails FAIL — installed artifact NOT GA-ready =="
  exit 1
fi
