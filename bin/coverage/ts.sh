#!/usr/bin/env bash
# TS/JS coverage adapter: produce a Cobertura report via vitest's v8 provider.
# Prints the report path on success; exits 4 when the toolchain is missing.
set -u
REPO="." COV_OUT=""
while [ $# -gt 0 ]; do case "$1" in --repo) REPO="$2"; shift 2 ;; --out) COV_OUT="$2"; shift 2 ;; *) shift ;; esac; done

if ! (cd "$REPO" && npx --no-install vitest --version >/dev/null 2>&1); then
  echo "ts adapter: vitest not available in this repo - cannot measure" >&2
  exit 4
fi
# The report path this prints is inside the output directory, so its READER owns
# the lifetime (bash.sh carries the same note): --out is the gate's directory,
# and a bare invocation still gets one of its own.
OUTDIR="${COV_OUT:-$(mktemp -d -t harmonia-tscov-XXXXXX)}"
# Judging the run by `[ -f "$OUT" ]` alone cannot tell a finished vitest from one
# killed after it wrote the report - the same fail-open as bash.sh's discarded
# status. A non-zero vitest is a red suite and still measurable; >= 128 is a
# signal, which no suite result produces.
rc=0
( cd "$REPO" && npx --no-install vitest run --coverage \
    --coverage.reporter=cobertura --coverage.reportsDirectory="$OUTDIR" >/dev/null 2>&1 ) || rc=$?
[ "$rc" -lt 128 ] || { echo "ts adapter: vitest was killed (signal $((rc - 128))) - cannot measure" >&2; exit 4; }
OUT="$OUTDIR/cobertura-coverage.xml"
[ -f "$OUT" ] || { echo "ts adapter: no report produced" >&2; exit 4; }
echo "$OUT"
