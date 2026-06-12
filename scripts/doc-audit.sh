#!/usr/bin/env bash
# doc-audit.sh — deterministic doc-structure auditor (CLAUDE.md §3.2 "周期审计").
#
# The repo ships a docs-curator AGENT (/sdlc:audit-docs, haiku-LLM), but §3.2 also calls for a
# zero-LLM script — which was missing until v0.19.1 (a doc-discipline plugin that itself accreted
# off-whitelist files; this is the mechanical guard so that can't recur silently).
#
# Checks (per §3.2): (1) root .md off-whitelist · (2) stray .zh.md outside root README · (3) one-shot
# residue (*-tasks/-report/-analysis/-readiness/v*-release-notes) anywhere under docs/ · (4) plans
# lingering in docs/superpowers/plans/ (deleted on archival, §3.2) · (5) tracked reports/*.md accrual
# (raw → reports/runs/ gitignored; conclusions → RELEASE.md) · (6) inventory-count consistency ·
# (7) command-ref integrity · (8) canonical-version anchor · (9) command-list completeness (every
# commands/<cmd>.md referenced in README; .sdlc/doc-audit-allow exempts) · (10) bilingual count-tuple
# parity (README.zh.md tuple == README.md tuple, plugin-self).
#
# Exit: 0 = clean · 1 = findings (advisory). --strict → exit 1 on findings (for CI/gates).
# Root override for tests: SDLC_DOC_ROOT. bash-3.2-safe; SE16-safe (grep -c / case, no early-close pipe).
set -uo pipefail

strict=0; [ "${1:-}" = "--strict" ] && strict=1
ROOT="${SDLC_DOC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
findings=0
note() { echo "  - $1"; findings=$((findings + 1)); }

# extract_count_tuple <readme-file>: print the inventory count integers in document order, taken
# from the FIRST bold `**...**` run that mentions "agent" — the canonical count tuple
# "**N agents, M skills, K commands, J hooks**" (en) / "**N ... agent ... skill ... commands ...
# hook ...**" (zh). The program is PURE ASCII (no multibyte literal anywhere) so BSD sed/awk on
# macOS under a C locale cannot raise "illegal byte sequence" (the v0.26.1 cross-platform fix —
# the previous Chinese-in-the-sed-program aborted the macOS test job). Chinese unit/kind words are
# simply ignored by ASCII digit extraction; position carries the kind (1=agents 2=skills
# 3=commands 4=hooks), and both READMEs use that fixed order. awk reads to EOF — SE16-safe.
extract_count_tuple() {
  awk 'BEGIN{p=1} /^## Status/{p=0} p{printf "%s ", $0}' "$1" 2>/dev/null \
    | awk '{
        s=$0
        while (match(s, /\*\*[^*]+\*\*/)) {
          seg=substr(s, RSTART+2, RLENGTH-4)
          if (seg ~ /agent/) { print seg; exit }
          s=substr(s, RSTART+RLENGTH)
        }
      }' \
    | grep -oE '[0-9]+'
}

# resolve_version_source: deterministic first-hit version source for generic anchor mode.
# Prints "<label> <version>" (e.g. "Cargo.toml 1.3.0") or nothing if unresolvable.
resolve_version_source() {
  if [ -f "$ROOT/.claude-plugin/plugin.json" ] && command -v jq >/dev/null 2>&1; then
    v=$(jq -r '.version // ""' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)
    [ -n "$v" ] && { echo ".claude-plugin/plugin.json $v"; return; }
  fi
  if [ -f "$ROOT/Cargo.toml" ]; then
    v=$(awk -F'"' '/^version[[:space:]]*=/{print $2; exit}' "$ROOT/Cargo.toml" 2>/dev/null)
    [ -n "$v" ] && { echo "Cargo.toml $v"; return; }
  fi
  if [ -f "$ROOT/package.json" ] && command -v jq >/dev/null 2>&1; then
    v=$(jq -r '.version // ""' "$ROOT/package.json" 2>/dev/null)
    [ -n "$v" ] && { echo "package.json $v"; return; }
  fi
  if [ -f "$ROOT/pyproject.toml" ]; then
    v=$(awk -F'"' '/^version[[:space:]]*=/{print $2; exit}' "$ROOT/pyproject.toml" 2>/dev/null)
    [ -n "$v" ] && { echo "pyproject.toml $v"; return; }
  fi
}

# (1) root .md whitelist
echo "[1] root .md whitelist (§3.2)"
for f in "$ROOT"/*.md; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  case "$b" in
    README.md|README.zh.md|DEVELOP.md|RELEASE.md|CLAUDE.md|ACKNOWLEDGMENTS.md|CONTRIBUTING.md|SECURITY.md|CODE_OF_CONDUCT.md) ;;
    *) note "off-whitelist root doc: $b (allowed: README[.zh]/DEVELOP/RELEASE/CLAUDE/ACKNOWLEDGMENTS/CONTRIBUTING/SECURITY/CODE_OF_CONDUCT)";;
  esac
done

# (2) stray .zh.md outside the root README (only README.zh.md may be bilingual, §1.1.3)
echo "[2] stray .zh.md (only root README.zh.md allowed)"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ "$f" = "$ROOT/README.zh.md" ] && continue
  note "stray bilingual file: ${f#"$ROOT"/}"
done < <(find "$ROOT" -name '*.zh.md' -not -path '*/node_modules/*' 2>/dev/null)

# (3) one-shot residue anywhere under docs/
echo "[3] one-shot residue under docs/ (belongs in PR/RELEASE)"
if [ -d "$ROOT/docs" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && note "one-shot residue: ${f#"$ROOT"/}"
  done < <(find "$ROOT/docs" -type f \( -name '*-tasks.md' -o -name '*-todo.md' -o -name '*-report.md' \
            -o -name '*-analysis.md' -o -name '*-readiness.md' -o -name 'v*-release-notes.md' \) 2>/dev/null)
fi

# (4) plans lingering after archival (§3.2: plans deleted when the sprint ships)
echo "[4] lingering plans (deleted on archival, §3.2)"
if [ -d "$ROOT/docs/superpowers/plans" ]; then
  n=$(find "$ROOT/docs/superpowers/plans" -name '*.md' -type f 2>/dev/null | grep -c . || true)
  if [ "${n:-0}" -gt 0 ]; then
    note "$n plan file(s) present — verify each is an ACTIVE sprint; archived sprints' plans must be deleted:"
    while IFS= read -r f; do [ -n "$f" ] && echo "      ${f#"$ROOT"/}"; done \
      < <(find "$ROOT/docs/superpowers/plans" -name '*.md' -type f 2>/dev/null)
  fi
fi

# (5) tracked reports/*.md accumulation (should be gitignored; raw→runs/, conclusions→RELEASE.md)
echo "[5] tracked reports/*.md accumulation"
if [ -d "$ROOT/.git" ] || git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  n=$(git -C "$ROOT" ls-files 'reports/*.md' 2>/dev/null | grep -c . || true)
  [ "${n:-0}" -gt 0 ] && note "$n tracked reports/*.md — gitignore them (keep reports/runs/); conclusions live in RELEASE.md"
fi

# (6) inventory-count consistency — plugin-self only (needs plugin.json + commands/)
# Real FS counts vs the declared tuple in BOTH plugin.json .description AND the README prose line.
# Zero prose scan: reads exactly two declared strings; NEVER the README `## Status` table.
if [ -f "$ROOT/.claude-plugin/plugin.json" ] && [ -d "$ROOT/commands" ]; then
  echo "[6] inventory counts (plugin-self)"
  if command -v jq >/dev/null 2>&1; then
    # real_* are consumed dynamically via eval "real=\${real_${kind}}" below (shellcheck can't trace).
    # shellcheck disable=SC2034
    real_agents=$(find "$ROOT/agents" -maxdepth 1 -name '*.md' -type f 2>/dev/null | awk 'END{print NR}')
    # shellcheck disable=SC2034
    real_skills=$(find "$ROOT/skills" -mindepth 2 -maxdepth 2 -name 'SKILL.md' -type f 2>/dev/null | awk 'END{print NR}')
    # shellcheck disable=SC2034
    real_commands=$(find "$ROOT/commands" -maxdepth 1 -name '*.md' -type f 2>/dev/null | awk 'END{print NR}')
    # shellcheck disable=SC2034
    real_hooks=$(jq -r '.hooks | keys | length' "$ROOT/hooks/hooks.json" 2>/dev/null || echo 0)
    # parse_counts <text>: emit "agents=N skills=M commands=K hooks=J" for the int bound to each kind.
    # When a kind word (agents/skills/commands/hooks) is found, scan BACKWARDS to the nearest field
    # that is a PURE integer, stopping at another kind word (don't cross boundaries). This handles the
    # "26 slash commands" phrasing where "commands" is preceded by "slash", not the number.
    # awk reads its whole input (to EOF) — SE16-safe, no pipe early-close.
    parse_counts() {
      printf '%s' "$1" | awk '
        function is_kind(w) { return (w=="agents"||w=="skills"||w=="commands"||w=="hooks") }
        { for (i=1; i<=NF; i++) {
            w=$i; gsub(/[^a-z]/,"",w)
            # Bind each kind to its FIRST co-occurrence (the canonical count line lives at the top
            # of the README/description). Later stray prose mentions ("Guard skills", "the phase
            # commands") must NOT overwrite the bound count.
            if (is_kind(w) && !(w in c)) {
              for (j=i-1; j>=1; j--) {
                p=$j; gsub(/[^a-z]/,"",p)
                if (is_kind(p)) break            # boundary: do not cross into prior kind
                q=$j; gsub(/^[^0-9]+/,"",q); gsub(/[^0-9]+$/,"",q)  # strip wrapping punct (** , .)
                if (q ~ /^[0-9]+$/) { c[w]=q; break }
              }
            }
          }
        }
        END { printf "agents=%s skills=%s commands=%s hooks=%s", c["agents"], c["skills"], c["commands"], c["hooks"] }'
    }
    json_desc=$(jq -r '.description // ""' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)
    # README prose line may WRAP across lines; join the file into one space-separated stream,
    # then parse the same tuple. Cut the file at the first `## Status` heading to be defensive
    # so the stale history table is never read.
    readme_prose=$(awk 'BEGIN{p=1} /^## Status/{p=0} p{printf "%s ", $0}' "$ROOT/README.md" 2>/dev/null)
    j_counts=$(parse_counts "$json_desc")
    r_counts=$(parse_counts "$readme_prose")
    # shellcheck disable=SC2086
    set -- $j_counts; for kv in "$@"; do eval "j_${kv}"; done
    # shellcheck disable=SC2086
    set -- $r_counts; for kv in "$@"; do eval "r_${kv}"; done
    # 'real' / 'decl_*' are assigned by the eval lines below (shellcheck can't trace dynamic eval).
    # shellcheck disable=SC2154
    for kind in agents skills commands hooks; do
      eval "decl_j=\${j_${kind}:-}"; eval "decl_r=\${r_${kind}:-}"; eval "real=\${real_${kind}}"
      [ -n "$decl_j" ] && [ "$decl_j" != "$real" ] && \
        note "inventory drift (plugin.json): $kind says $decl_j, fs has $real"
      [ -n "$decl_r" ] && [ "$decl_r" != "$real" ] && \
        note "inventory drift (README): $kind says $decl_r, fs has $real"
    done
  else
    note "[6] jq unavailable — inventory-count check skipped"
  fi
fi

# (7) command-reference integrity — plugin-self. Every /sdlc:<cmd> in README must have commands/<cmd>.md.
# Extract regex restricted to `/sdlc:[a-z][a-z-]*` → a placeholder `/sdlc:<cmd>` (angle brackets) never matches.
# awk reads to EOF (SE16-safe); uniq the refs to avoid duplicate notes.
if [ -f "$ROOT/.claude-plugin/plugin.json" ] && [ -d "$ROOT/commands" ]; then
  echo "[7] command-ref integrity (plugin-self)"
  refs=$(awk '{
      s=$0
      while (match(s, /\/sdlc:[a-z][a-z-]*/)) {
        print substr(s, RSTART+6, RLENGTH-6)
        s=substr(s, RSTART+RLENGTH)
      }
    }' "$ROOT/README.md" 2>/dev/null | sort -u)
  for cmd in $refs; do
    [ -n "$cmd" ] || continue
    [ -f "$ROOT/commands/$cmd.md" ] || note "dangling command ref: /sdlc:$cmd (commands/$cmd.md missing)"
  done
fi

# (8) canonical-version anchor — the ONLY version check: a designated LINE, not a prose scan.
echo "[8] canonical-version anchor"
if [ -f "$ROOT/.claude-plugin/plugin.json" ]; then
  # PLUGIN MODE: CLAUDE.md `> Shipped through **vX.Y.Z**` line vs plugin.json .version.
  src_ver=""
  command -v jq >/dev/null 2>&1 && src_ver=$(jq -r '.version // ""' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)
  # extract the bold version token on the Shipped-through line; strip leading `v`. awk-to-EOF.
  anchor_ver=$(awk '/Shipped through/ {
      if (match($0, /v[0-9]+\.[0-9]+\.[0-9]+/)) { print substr($0, RSTART+1, RLENGTH-1); exit }
    }' "$ROOT/CLAUDE.md" 2>/dev/null)
  if [ -z "$anchor_ver" ]; then
    note "canonical anchor line absent in CLAUDE.md (expected '> Shipped through **vX.Y.Z**') — anchor check skipped"
  elif [ -n "$src_ver" ] && [ "$anchor_ver" != "$src_ver" ]; then
    note "stale version anchor: CLAUDE.md says $anchor_ver, source .claude-plugin/plugin.json = $src_ver"
  fi
else
  # GENERIC MODE: only lines bearing `<!-- sdlc:version -->`. No marker → silent skip (zero false-positive).
  src_pair=$(resolve_version_source)
  src_label=${src_pair%% *}; src_ver=${src_pair#* }
  found_marker=0
  while IFS= read -r line; do
    found_marker=1
    fpath=${line%%:*}; rest=${line#*:}; lno=${rest%%:*}; content=${rest#*:}
    mver=$(printf '%s' "$content" | awk '{ if (match($0, /[0-9]+\.[0-9]+\.[0-9]+/)) print substr($0, RSTART, RLENGTH) }')
    if [ -z "$src_pair" ]; then
      note "version marker present (${fpath#"$ROOT"/}:$lno) but no version source resolvable"
    elif [ -n "$mver" ] && [ "$mver" != "$src_ver" ]; then
      note "stale version anchor: ${fpath#"$ROOT"/}:$lno says $mver, source $src_label = $src_ver"
    fi
  done < <(grep -rn -- '<!-- sdlc:version -->' "$ROOT" 2>/dev/null)
  [ "$found_marker" -eq 0 ] && true   # silent skip: no marker, no finding
fi

# (9) command-list completeness — plugin-self. Reverse of [7]: every commands/<cmd>.md MUST be
# referenced as /sdlc:<cmd> somewhere in README.md, unless listed in .sdlc/doc-audit-allow.
# awk reads to EOF (SE16-safe); refs uniq'd; allowlist mirrors .sdlc/secret-allow.
if [ -f "$ROOT/.claude-plugin/plugin.json" ] && [ -d "$ROOT/commands" ]; then
  echo "[9] command-list completeness (plugin-self)"
  refs9=$(awk '{
      s=$0
      while (match(s, /\/sdlc:[a-z][a-z-]*/)) {
        print substr(s, RSTART+6, RLENGTH-6)
        s=substr(s, RSTART+RLENGTH)
      }
    }' "$ROOT/README.md" 2>/dev/null | sort -u)
  exempt9=""
  if [ -f "$ROOT/.sdlc/doc-audit-allow" ]; then
    # one token per line; '/sdlc:<cmd>' or bare '<cmd>'; strip the prefix; drop '#' lines + blanks.
    exempt9=$(awk 'NF && $0 !~ /^[[:space:]]*#/ { sub(/^\/sdlc:/,"",$1); print $1 }' \
      "$ROOT/.sdlc/doc-audit-allow" 2>/dev/null | sort -u)
  fi
  for f in "$ROOT"/commands/*.md; do
    [ -e "$f" ] || continue
    cmd=$(basename "$f" .md)
    # listed? — newline-delimited membership test without a pipe early-close (SE16-safe).
    case $'\n'"$refs9"$'\n' in *$'\n'"$cmd"$'\n'*) continue;; esac
    [ -n "$exempt9" ] && case $'\n'"$exempt9"$'\n' in *$'\n'"$cmd"$'\n'*) continue;; esac
    note "command not in README: /sdlc:$cmd"
  done
fi

# (10) bilingual count-tuple parity — plugin-self, only when README.zh.md exists. The zh inventory
# count tuple MUST equal README.md's. Since [6] binds README.md ↔ FS, this transitively binds zh ↔ FS.
# Empty/unparseable kind → skip (zero false-positive). awk-to-EOF; no early-close pipe (SE16-safe).
if [ -f "$ROOT/.claude-plugin/plugin.json" ] && [ -d "$ROOT/commands" ] && [ -f "$ROOT/README.zh.md" ]; then
  echo "[10] bilingual count parity (plugin-self)"
  # Positional compare of the two count tuples (ASCII digit extraction — extract_count_tuple).
  # Position carries the kind (1=agents 2=skills 3=commands 4=hooks); both READMEs use that fixed
  # order. Only compare positions present in BOTH (a shorter tuple => its trailing kind is skipped,
  # not flagged — matches the "kind missing entirely" edge).
  en_nums=$(extract_count_tuple "$ROOT/README.md")
  zh_nums=$(extract_count_tuple "$ROOT/README.zh.md")
  # Positional compare via a single awk over both integer streams (separated by '---'); it emits
  # one tab line "<kind>\t<zh>\t<en>" per differing position. Only positions present in BOTH are
  # compared (a shorter tuple => its trailing kind is skipped). No named per-index vars (so there
  # is no SC2034 unused-var false positive); awk reads to EOF (SE16-safe).
  drift10=$(printf '%s\n---\n%s\n' "$en_nums" "$zh_nums" | awk '
      /^---$/ { sep=1; next }
      !sep    { en[++en_n]=$1; next }
              { zh[++zh_n]=$1 }
      END {
        split("agents skills commands hooks", K, " ")
        n = (en_n < zh_n ? en_n : zh_n)
        for (i=1; i<=n; i++) if (en[i] != zh[i]) printf "%s\t%s\t%s\n", K[i], zh[i], en[i]
      }')
  # feed via here-doc (not a pipe) so note()'s findings increment persists in this shell.
  while IFS="$(printf '\t')" read -r kind zc ec; do
    [ -n "$kind" ] && note "bilingual count drift (README.zh): $kind says $zc, README.md says $ec"
  done <<EOF
$drift10
EOF
fi

# (11) dangling internal-doc refs — agents/skills/commands/hooks must NOT link to a docs/ path that
# does not exist. The public-snapshot cleanup removed specs but left "## Linked" pointers → dead links
# that [7] (command→commands/ only) never caught. Placeholder/example tokens ('<...>', feature-slug,
# vector-search) are skipped. Effectively plugin-self (agents/skills/commands only exist in the plugin).
# Scope narrowly to DATED design-spec refs (docs/superpowers/specs/YYYY-MM-DD-<name>.md) — the exact
# class that regressed (a committed spec removed while a "## Linked: spec …" pointer survived). Generic
# docs/<name>.md (e.g. docs/cicd-strategy.md, docs/tech-debt.md) are agent OUTPUT paths produced at
# runtime, not committed cross-refs, so they're out of scope (zero false positives). Placeholder/example
# slugs (feature-slug, vector-search, '<…>') are skipped.
echo "[11] dangling dated-spec refs (agents/skills/commands → docs/superpowers/specs/<dated>.md)"
dangling11=""
for src in "$ROOT"/agents/*.md "$ROOT"/skills/*/SKILL.md "$ROOT"/commands/*.md; do
  [ -e "$src" ] || continue
  refs=$(grep -oE 'docs/superpowers/specs/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[a-z0-9-]+\.md' "$src" 2>/dev/null | sort -u)
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    case "$ref" in *feature-slug*|*vector-search*|*'<'*) continue;; esac
    [ -f "$ROOT/$ref" ] || dangling11="${dangling11}${ref}	${src#"$ROOT"/}
"
  done <<EOF
$refs
EOF
done
while IFS="$(printf '\t')" read -r ref src; do
  [ -n "$ref" ] && note "dangling doc ref: $ref (in $src) — file does not exist"
done <<EOF
$dangling11
EOF

echo
if [ "$findings" -eq 0 ]; then
  echo "doc-audit: CLEAN"
  exit 0
fi
echo "doc-audit: $findings finding(s)"
[ "$strict" -eq 1 ] && exit 1
exit 0
