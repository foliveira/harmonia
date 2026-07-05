#!/usr/bin/env bash
# Emit relevant learning summaries for a repo, newest first, within a budget.
#   recall.sh [--repo <path>] [--budget-lines N]
# Sources: project tier (docs/learnings) and legacy docs/solutions (read-only)
# are always relevant to their own repo; global-tier entries are filtered by
# language-tag overlap. Fails open: warnings to stderr, exit 0 (KTD5).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/store-lib.sh"

REPO="." BUDGET=30
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)         REPO="$2"; shift 2 ;;
    --budget-lines) BUDGET="$2"; shift 2 ;;
    *) echo "recall: unknown argument '$1'" >&2; exit 0 ;;
  esac
done

LANGS=" $(repo_langs "$REPO" | tr '\n' ' ') "
H="$(harmonia_home)"
CANDIDATES=""   # lines: <date>\t<summary>

add() { CANDIDATES="${CANDIDATES}$1
"; }

fm_val() { # fm_val <file> <key>
  awk -v k="$2" 'BEGIN{inf=0} /^---$/{inf++; next} inf==1 && index($0,k": ")==1 {sub("^"k": *",""); print; exit}' "$1" 2>/dev/null
}

# --- Global tier: parse the index defensively; filter by language overlap ---
if [ -f "$H/index.md" ]; then
  torn=0
  while IFS= read -r line; do
    case "$line" in
      -\ [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ \[*\]\(*\)\ tags:*) ;;
      "") continue ;;
      *) torn=$((torn+1)); continue ;;
    esac
    d="${line:2:10}"
    title="${line#*\[}"; title="${title%%\]*}"
    tags="${line#*tags: }"
    keep=0
    IFS=',' read -r -a tag_tokens <<< "$tags"
    for t in "${tag_tokens[@]}"; do
      t="${t//[[:space:]]/}"
      [ -n "$t" ] && [[ "$LANGS" == *" $t "* ]] && keep=1
    done
    [ "$keep" -eq 1 ] && add "$d	[global] $d $title (tags: $tags)"
  done < "$H/index.md"
  [ "$torn" -gt 0 ] && echo "recall: warning - skipped $torn unparseable index line(s)" >&2
fi

# --- Project tier: always relevant to its own repo ---
if [ -d "$REPO/docs/learnings" ]; then
  for f in "$REPO"/docs/learnings/*.md; do
    [ -f "$f" ] || continue
    t="$(fm_val "$f" title)"; d="$(fm_val "$f" date)"
    [ -n "$t" ] && add "${d:-0000-00-00}	[project] ${d:-} $t"
  done
fi

# --- Legacy compound-engineering entries: read-only continuity ---
if [ -d "$REPO/docs/solutions" ]; then
  while IFS= read -r f; do
    t="$(fm_val "$f" title)"; d="$(fm_val "$f" date)"
    [ -n "$t" ] && add "${d:-0000-00-00}	[legacy] ${d:-} $t"
  done < <(find "$REPO/docs/solutions" -name '*.md' -type f 2>/dev/null)
fi

# Newest first (stable for same-date by later-seen-first), deduped, budgeted.
printf '%s' "$CANDIDATES" | grep -v '^$' | nl -ba -nrz | sort -t'	' -k2,2r -k1,1r \
  | cut -f3- | awk '!seen[$0]++' | head -n "$BUDGET"
exit 0
