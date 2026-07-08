#!/usr/bin/env bash
# The one reader of a repo's .harmonia/project.yaml. Sourced by the coverage
# gate; never executed directly. Flat, known-key, one-scalar-per-line only:
# no nesting, no block scalars, no arrays.
set -u

# project_config <repo> <key> <default>
# Echo the scalar value of <key> from <repo>/.harmonia/project.yaml, or <default>
# when the file or the key is absent (or the value is empty).
project_config() {
  local repo="$1" key="$2" default="$3"
  local file="$repo/.harmonia/project.yaml" val
  [ -f "$file" ] || { printf '%s' "$default"; return 0; }
  # Column-0 key anchor + trailing colon; FIRST match only; strip the anchored
  # key and surrounding blanks. Reads exactly one physical line, so a value
  # cannot span lines or forge another key's line (newline-guard learning).
  val="$(grep -m1 -E "^${key}:[[:space:]]*" "$file" 2>/dev/null | sed -e "s/^${key}:[[:space:]]*//" -e 's/[[:space:]]*$//')"
  # Strip one layer of matching quotes if present. The gate later eval's this
  # returned value (the coverage: key), so the strip means a value wrapped in
  # single OR double quotes runs identically to bare - the quotes are not literal,
  # and a quoted value must be read as executable, not as data.
  case "$val" in
    \"*\") val="${val#\"}"; val="${val%\"}" ;;
    \'*\') val="${val#\'}"; val="${val%\'}" ;;
  esac
  [ -n "$val" ] || val="$default"
  printf '%s' "$val"
}
