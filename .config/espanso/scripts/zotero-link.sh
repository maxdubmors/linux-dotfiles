#!/usr/bin/env bash
export LC_ALL=en_US.UTF-8

# Requirements:
# 1. jq (https://jqlang.github.io/jq/)
# 2. Export Zotero library as BetterBibTeX JSON
# 3*. Espanso for quick link insertion (https://espanso.org/)
#
# Usage: zotero-link.sh [link|citekey|quote]

mode="${1:-link}"
library="$HOME/Documents/mors-database/.library.json"

fail() {
  printf 'zotero-link: %s\n' "$*" >&2
  exit 1
}

#─────────────────────────────────────────────────────────────────────────────
# Read clipboard

if command -v wl-paste >/dev/null 2>&1; then
  text=$(wl-paste --no-newline)
elif command -v pbpaste >/dev/null 2>&1; then
  text=$(pbpaste)
elif command -v xsel >/dev/null 2>&1; then
  text=$(xsel --clipboard --output)
else
  fail "could not find wl-paste, pbpaste or xsel"
fi

command -v jq >/dev/null 2>&1 || fail "jq is not installed"
[[ -r "$library" ]] || fail "library file is not readable: $library"

#─────────────────────────────────────────────────────────────────────────────
# Extract item ID

id=$(printf '%s\n' "$text" |
  grep -Eo 'zotero://select/library/items/[a-zA-Z0-9]+' |
  sed 's|zotero://select/library/items/||' |
  head -n 1)

if [[ -z "$id" ]]; then
  id=$(printf '%s\n' "$text" |
    grep -Eo 'zotero://open-pdf/library/items/[a-zA-Z0-9]+' |
    sed 's|zotero://open-pdf/library/items/||' |
    head -n 1)
fi

if [[ -z "$id" ]]; then
  fail "could not find Zotero item ID in the clipboard text"
fi

#─────────────────────────────────────────────────────────────────────────────
# Get item data from library

item=$(jq --arg key "$id" '
  .items[]
  | select(
      .key == $key
      or any(.attachments[]?; (.select == ("zotero://select/library/items/" + $key)) or (.uri | endswith("/items/" + $key)))
    )
' "$library")
title=$(jq -r 'if .shortTitle then .shortTitle else .title end' <<<"$item")

if [[ -z "$title" ]]; then
  fail "could not find exported Zotero item or parent attachment for ID: $id"
fi

#─────────────────────────────────────────────────────────────────────────────
# Citekey mode

if [[ "$mode" == "citekey" ]]; then
  citekey=$(jq -r '.citationKey' <<<"$item")
  echo "[@${citekey#@}]"
  exit 0
fi

#─────────────────────────────────────────────────────────────────────────────
# Link patterns

link_patterns=(
  "pdf:zotero:\/\/open-pdf\/library\/items\/([a-zA-Z0-9]+)\?page=([0-9]+)&annotation=([a-zA-Z0-9])+"
  "snap:zotero:\/\/open-pdf\/library\/items\/([a-zA-Z0-9]+)\?sel=([^&]+)&annotation=([a-zA-Z0-9]+)"
  "epub:zotero:\/\/open-pdf\/library\/items\/([a-zA-Z0-9]+)\?cfi=([^&]+)&annotation=([a-zA-Z0-9]+)"
)

#─────────────────────────────────────────────────────────────────────────────
# Match link and produce output

for pattern in "${link_patterns[@]}"; do
  IFS=':' read -r link_type regex <<<"$pattern"

  if [[ "$text" =~ $regex ]]; then
    link="${BASH_REMATCH[0]}"
    page_number="${BASH_REMATCH[2]}"

    case "$mode" in
    quote)
      quote_text=$(printf '%s' "$text" | sed 's/ *(\[.*//')
      author_full=$(jq -r 'if .creators[0] then "\(.creators[0].firstName) \(.creators[0].lastName)" else empty end' <<<"$item")
      echo "> [!quote]"
      echo "> ${quote_text//$'\n'/$'\n> '}"
      echo ">"
      case "$link_type" in
      pdf) echo "> - ${title}, [p. ${page_number}](${link})" ;;
      *) echo "> - [${title}](${link})" ;;
      esac
      [[ -n "$author_full" ]] && echo "> - ${author_full}"
      ;;
    *)
      author=$(jq -r '.creators[0].lastName // empty' <<<"$item")
      year=$(jq -r '.date // empty' <<<"$item" | grep -Eo '[0-9]{4}')
      result=""
      [[ -n "$author" ]] && result="${author}, "
      case "$link_type" in
      pdf)
        result="${result}${title}"
        [[ -n "$year" ]] && result="${result} (${year})"
        result="${result}, [p. ${page_number}](${link})"
        ;;
      *)
        result="${result}[${title}](${link})"
        [[ -n "$year" ]] && result="${result} (${year})"
        ;;
      esac
      echo "$result"
      ;;
    esac
    exit 0
  fi
done

fail "no suitable Zotero PDF/snapshot/EPUB link found in the clipboard text"
