#!/usr/bin/env bash
# Shared memory-store helpers (KTD5). Sourceable; also a small CLI:
#   store-lib.sh repo-id <path>   -> stable repo identity (worktree-safe)
#   store-lib.sh repo-langs <path>-> language tags detected in the repo
set -u

harmonia_home() { echo "${HARMONIA_HOME:-$HOME/.harmonia}"; }

# Stable repo identity: remote URL when present, else the git common dir —
# so every worktree of one project resolves to the same identity.
repo_id() {
  local repo="${1:-.}"
  local url common
  url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  if [ -n "$url" ]; then echo "$url"; return 0; fi
  common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$common" ]; then echo "$common"; return 0; fi
  ( cd "$repo" 2>/dev/null && pwd )
}

# Language tags from tracked (or present) file extensions.
repo_langs() {
  local repo="${1:-.}"
  local files
  files="$(git -C "$repo" ls-files 2>/dev/null || find "$repo" -maxdepth 3 -type f 2>/dev/null)"
  echo "$files" | awk -F. 'NF>1 {print tolower($NF)}' | sort -u | awk '
    /^go$/        {print "go"}
    /^ts$|^tsx$/  {print "typescript"}
    /^js$|^jsx$/  {print "javascript"}
    /^sh$|^bats$/ {print "bash"}
    /^py$/        {print "python"}
    /^rb$/        {print "ruby"}
    /^ya?ml$/     {print "yaml"}
  ' | sort -u
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]+*/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

# Atomic, de-duplicated index append (flock-guarded write).
atomic_index_append() {
  local index="$1" line="$2"
  local lock="${index}.lock"
  mkdir -p "$(dirname "$index")"
  (
    flock 9
    touch "$index"
    if ! grep -qxF -- "$line" "$index" 2>/dev/null; then
      printf '%s\n' "$line" >> "$index"
    fi
  ) 9>"$lock"
}

# CLI dispatch when executed directly.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cmd="${1:-}"
  case "$cmd" in
    repo-id)    repo_id "${2:-.}" ;;
    repo-langs) repo_langs "${2:-.}" ;;
    *) echo "usage: store-lib.sh {repo-id|repo-langs} <path>" >&2; exit 1 ;;
  esac
fi
