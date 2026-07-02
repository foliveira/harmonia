#!/usr/bin/env bash
# Validate the portable core: YAML syntax, schema conformance, lens resolution.
# Exit codes: 0 valid; 1 validation failed; 3 cannot-validate (tool missing).
set -u

usage() { echo "usage: validate-core.sh [--repo <path>]" >&2; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

LIFECYCLE="$REPO/core/lifecycle.yaml"
SCHEMA="$REPO/core/lifecycle.schema.json"
LENS_DIR="$REPO/core/lenses"
FAIL=0

if [ ! -f "$LIFECYCLE" ]; then echo "validate-core: missing $LIFECYCLE" >&2; exit 1; fi
if [ ! -f "$SCHEMA" ]; then echo "validate-core: missing $SCHEMA" >&2; exit 1; fi

# 1. YAML syntax (yamllint, syntax-level only).
if command -v yamllint >/dev/null 2>&1; then
  if ! yamllint -d '{extends: relaxed, rules: {line-length: disable}}' "$LIFECYCLE" >&2; then
    echo "validate-core: yamllint failed" >&2
    FAIL=1
  fi
else
  echo "validate-core: yamllint missing - cannot validate" >&2
  exit 3
fi

# 2. Schema conformance (check-jsonschema validates YAML natively).
if command -v check-jsonschema >/dev/null 2>&1; then
  if ! check-jsonschema --schemafile "$SCHEMA" "$LIFECYCLE" >&2; then
    echo "validate-core: schema validation failed" >&2
    FAIL=1
  fi
else
  echo "validate-core: check-jsonschema missing - cannot validate" >&2
  exit 3
fi

# 3. Every lens named by a stage resolves to a core/lenses/<name>.md file (KTD11).
lenses=$(grep -A3 'lenses:' "$LIFECYCLE" | grep -oE '\[[^]]*\]' | tr -d '[] ' | tr ',' '\n' | sort -u)
for lens in $lenses; do
  [ -z "$lens" ] && continue
  if [ ! -f "$LENS_DIR/$lens.md" ]; then
    echo "validate-core: lens '$lens' has no file at core/lenses/$lens.md" >&2
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then exit 1; fi
echo "validate-core: OK"
exit 0
