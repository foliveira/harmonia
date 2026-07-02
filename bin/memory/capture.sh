#!/usr/bin/env bash
# Capture a learning into a memory tier (KTD5, R11, R21). Body on stdin.
#   capture.sh --title <t> --tier global|project --tags a,b [--repo <path>] [--client]
# Exit: 0 written (or already present); 2 refused (client content, global tier).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/store-lib.sh"

TITLE="" TIER="" TAGS="" REPO="." CLIENT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --title)  TITLE="$2"; shift 2 ;;
    --tier)   TIER="$2"; shift 2 ;;
    --tags)   TAGS="$2"; shift 2 ;;
    --repo)   REPO="$2"; shift 2 ;;
    --client) CLIENT=1; shift ;;
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

DATE="$(date +%Y-%m-%d)"
SLUG="$(slugify "$TITLE")"
FILE="$DATE-$SLUG.md"
BODY="$(cat)"
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
