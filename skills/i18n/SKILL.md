---
name: i18n
description: Use when emitting human-facing interaction output (sprint status, gate decisions, scorecards, handoff prose) and the user has set SDLC_LANG to choose the language. Resolves SDLC_LANG (zh|en|bilingual; unset/invalid → en) and looks up structured messages from a TSV catalog via lang.sh. Localizes human-facing prose ONLY — technical tokens (identifiers, error codes, JSON keys, commit messages, paths) always stay English.
---

# i18n

The interaction-language layer. Lets a Chinese (or bilingual) user read the orchestrator's
human-facing output in their language, without translating agent/command prompts or drifting
(§3.2). Mechanism over mass-translation: one catalog + one helper.

## SDLC_LANG

| Value | Effect |
|-------|--------|
| `en` (default — also when unset/invalid) | English output (existing behavior, byte-for-byte) |
| `zh` | Chinese human-facing output (opt-in) |
| `bilingual` | `en / zh` inline, for mixed-language teams |

Default is **en** (§1.1.3 docs-default-English); Chinese is **opt-in** via `SDLC_LANG=zh`.

## Contract — lang.sh

```
lang.sh lang          # → resolved language (zh|en|bilingual)
lang.sh msg <key>     # → message for key in resolved language
                      #   bilingual → "en / zh"; unknown key → the key itself; empty zh → en
```

`SDLC_I18N_CATALOG` (default `skills/i18n/messages.tsv`) — TSV: `key<TAB>en<TAB>zh`, `#` comments.

## What is localized — and what is NOT

- **Localized**: human-facing prose — section headers, gate decisions, status labels, scorecard
  headings, handoff/scorecard prose a person reads.
- **NEVER localized** (stays English): identifiers, sprint ids, phase names, kebab error codes,
  JSON/YAML keys + enum values, commit messages, file paths, log keys. These are machine-parseable
  contracts; translating them breaks tooling (spec §2.3 / §10).

## Usage pattern (agents/commands)

```
resolved=$(skills/i18n/lang.sh lang)
header=$(skills/i18n/lang.sh msg status.next)     # structured label from catalog
# free-form summary prose: write it in $resolved (Chinese when zh; en + zh when bilingual)
# technical tokens (ids/codes/paths/keys): always English
```

## Graceful fallbacks (never crash, never blank)

- `SDLC_LANG` unset / invalid → `en`.
- unknown key → echo the key (a visible key signals "add it to the catalog").
- empty zh column → fall back to en (zh and bilingual both); bilingual never emits a trailing `/`.
- missing catalog file → every `msg` echoes its key (mechanism degrades, does not error).

## Extending

Add a human-facing string: append one `key<TAB>en<TAB>zh` row to `messages.tsv` (real TABs).
No code change. Forget the zh column → it falls back to en. Per-agent full translation is
intentionally out of scope (drift, §3.2) — the catalog grows on demand.

## Linked

- agent [[task-orchestrator]] (emits status / gate decisions via SDLC_LANG)
