#!/usr/bin/env bash
# TS/JS coverage adapter: produce a Cobertura report via vitest's v8 provider.
# Prints the report path on success; exits 4 when the toolchain is missing.
set -u
REPO="."
while [ $# -gt 0 ]; do case "$1" in --repo) REPO="$2"; shift 2 ;; *) shift ;; esac; done

if ! (cd "$REPO" && npx --no-install vitest --version >/dev/null 2>&1); then
  echo "ts adapter: vitest not available in this repo - cannot measure" >&2
  exit 4
fi
OUTDIR="$(mktemp -d -t harmonia-tscov-XXXXXX)"
( cd "$REPO" && npx --no-install vitest run --coverage \
    --coverage.reporter=cobertura --coverage.reportsDirectory="$OUTDIR" >/dev/null 2>&1 )
OUT="$OUTDIR/cobertura-coverage.xml"
[ -f "$OUT" ] || { echo "ts adapter: no report produced" >&2; exit 4; }
echo "$OUT"
