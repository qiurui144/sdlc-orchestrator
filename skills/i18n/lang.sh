#!/usr/bin/env bash
# lang.sh — i18n: resolve SDLC_LANG + look up human-facing messages from a TSV catalog.
# Localizes human-facing PROSE only; technical tokens (ids / error-codes / JSON keys /
# commit messages / paths) stay English (spec §2.3). Zero LLM, file-only. bash-3.2-safe.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CATALOG="${SDLC_I18N_CATALOG:-$HERE/messages.tsv}"

resolve_lang() {
  case "${SDLC_LANG:-}" in
    zh|en|bilingual) echo "${SDLC_LANG}";;
    *) echo "en";;                       # unset / invalid → en (spec §2.3 graceful default)
  esac
}

# lookup KEY → echoes "en<TAB>zh" and returns 0, or returns 1 if absent / no catalog.
# Reads the TSV line-by-line for an EXACT first-column match (no regex — keys contain '.',
# and a substring/regex match would mis-hit, spec §11 TSV-parse).
lookup() {
  local key="$1" k en zh
  [ -f "$CATALOG" ] || return 1
  while IFS=$'\t' read -r k en zh || [ -n "$k" ]; do
    case "$k" in '#'*) continue;; esac    # skip comment lines
    if [ "$k" = "$key" ]; then printf '%s\t%s' "$en" "$zh"; return 0; fi
  done < "$CATALOG"
  return 1
}

msg() {
  local key="$1" resolved pair en zh
  [ -n "$key" ] || { echo "usage: lang.sh msg <key>" >&2; return 2; }
  resolved=$(resolve_lang)
  if pair=$(lookup "$key"); then
    en=${pair%%$'\t'*}; zh=${pair#*$'\t'}
    case "$resolved" in
      en) echo "$en";;
      zh) if [ -n "$zh" ]; then echo "$zh"; else echo "$en"; fi;;        # empty zh → en fallback
      bilingual) if [ -n "$zh" ]; then echo "$en / $zh"; else echo "$en"; fi;; # empty zh → en only (no trailing ' / ')
    esac
  else
    echo "$key"                           # unknown key / no catalog → echo key (graceful)
  fi
}

case "${1:-}" in
  lang) resolve_lang;;
  msg)  shift; msg "${1:-}";;
  *) echo "usage: lang.sh lang | msg <key>" >&2; exit 2;;
esac
