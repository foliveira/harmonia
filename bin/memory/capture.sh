#!/usr/bin/env bash
# Capture a learning into a memory tier (KTD5, R11, R21). Body on stdin.
#   capture.sh --title <t> --tier global|project --tags a,b [--repo <path>]
#              [--client] [--unreachable-ok]
# Exit: 0 written (or already present); 2 refused (client content to the global
# tier, or a global entry with no recognized language tag).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/store-lib.sh"

TITLE="" TIER="" TAGS="" REPO="." CLIENT=0 UNREACHABLE_OK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --title)  TITLE="$2"; shift 2 ;;
    --tier)   TIER="$2"; shift 2 ;;
    --tags)   TAGS="$2"; shift 2 ;;
    --repo)   REPO="$2"; shift 2 ;;
    --client) CLIENT=1; shift ;;
    --unreachable-ok) UNREACHABLE_OK=1; shift ;;
    *) echo "capture: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
[ -n "$TITLE" ] || { echo "capture: --title is required" >&2; exit 1; }
case "$TIER" in global|project) ;; *) echo "capture: --tier must be global or project" >&2; exit 1 ;; esac

# R21: client-work knowledge never reaches the global store.
if [ "$CLIENT" -eq 1 ] && [ "$TIER" = "global" ]; then
  echo "capture: refused - client-flagged content cannot be written to the global tier (R21); use --tier project" >&2
  exit 2
fi

# Recall keeps a global entry only when a tag overlaps the recognized-language
# list (store-lib.sh); with topic-only tags it would be silently unreachable in
# every repo. Refuse that unless the writer acknowledges the trade-off.
UNREACHABLE=0
if [ "$TIER" = "global" ]; then
  LANG_HIT=0
  KNOWN=" $(known_langs | tr '\n' ' ') "
  IFS=',' read -r -a tag_tokens <<< "$TAGS"
  for t in "${tag_tokens[@]}"; do
    t="${t//[[:space:]]/}"
    [ -n "$t" ] && [[ "$KNOWN" == *" $t "* ]] && LANG_HIT=1
  done
  if [ "$LANG_HIT" -eq 0 ]; then
    UNREACHABLE=1
  fi
  if [ "$UNREACHABLE" -eq 1 ] && [ "$UNREACHABLE_OK" -eq 0 ]; then
    echo "capture: refused - a global-tier entry with no recognized language tag can never surface in recall; add a language tag ($(known_langs | tr '\n' ' ' | sed 's/ $//')), capture with --tier project instead, or pass --unreachable-ok to record it anyway" >&2
    exit 2
  fi
fi

DATE="$(date +%Y-%m-%d)"
SLUG="$(slugify "$TITLE")"
FILE="$DATE-$SLUG.md"
BODY="$(cat)"
if [ "$UNREACHABLE" -eq 1 ]; then
  BODY="$BODY"$'\n\n'"note: unreachable-ok - no recognized language tag; recall's language filter cannot surface this entry"
fi
SOURCE="$(repo_id "$REPO")"

write_entry() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  {
    printf -- '---\ntitle: %s\ndate: %s\ntags: [%s]\ntier: %s\nsource_repo: %s\n---\n\n%s\n' \
      "$TITLE" "$DATE" "$TAGS" "$TIER" "$SOURCE" "$BODY"
  } > "$path.tmp.$$"
  mv "$path.tmp.$$" "$path"   # atomic within the same filesystem
}

if [ "$TIER" = "global" ]; then
  H="$(harmonia_home)"
  write_entry "$H/learnings/$FILE"
  atomic_index_append "$H/index.md" "- $DATE [$TITLE](learnings/$FILE) tags: $TAGS"
else
  write_entry "$REPO/docs/learnings/$FILE"
fi
echo "captured: $TIER/$FILE"
