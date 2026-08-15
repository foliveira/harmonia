#!/usr/bin/env bash
# Bash coverage adapter: kcov over the bats suite (line-only; kcov carries no
# branch records - KTD6). Prints the merged Cobertura path; exits 4 when kcov
# is missing, produced nothing, or was killed mid-run.
set -u
REPO="." COV_OUT=""
while [ $# -gt 0 ]; do case "$1" in --repo) REPO="$2"; shift 2 ;; --out) COV_OUT="$2"; shift 2 ;; *) shift ;; esac; done

# Tool resolution is overridable so tests can simulate absence deterministically.
KCOV_BIN="${HARMONIA_KCOV:-kcov}"
BATS_BIN_NAME="${HARMONIA_BATS:-bats}"
command -v "$KCOV_BIN" >/dev/null 2>&1 || { echo "bash adapter: kcov not installed - cannot measure" >&2; exit 4; }
command -v "$BATS_BIN_NAME" >/dev/null 2>&1 || { echo "bash adapter: bats not installed - cannot measure" >&2; exit 4; }

# The path this prints lives INSIDE the output directory, so the adapter cannot
# delete it on the way out: whoever reads the report owns the lifetime. --out is
# the gate handing over a directory it removes itself; invoked bare (the
# standalone calls in tests/adapters.bats) the adapter still mints its own.
OUTDIR="${COV_OUT:-$(mktemp -d -t harmonia-kcov-XXXXXX)}"
BATS_PATH="$(command -v "$BATS_BIN_NAME")"
# kcov exits with the status of the program it ran, so a red bats suite arrives
# as a plain non-zero and must still be measured - that is the case the tolerated
# status exists for. A SIGNAL is never a red suite: it is kcov being killed
# mid-run, and a kcov that got as far as the changed file leaves a report that
# reads downstream as a clean pass, because the gate's fail-closed rule for
# missing data is per FILE. Discarding the status made those two indistinguishable.
rc=0
"$KCOV_BIN" --include-path="$REPO/bin" "$OUTDIR" "$BATS_PATH" "$REPO/tests" >"$OUTDIR/kcov.log" 2>&1 || rc=$?
[ "$rc" -lt 128 ] || { echo "bash adapter: kcov was killed (signal $((rc - 128))) - cannot measure" >&2; exit 4; }
MERGED="$(find "$OUTDIR" -name cobertura.xml -path '*kcov-merged*' | head -1)"
[ -z "$MERGED" ] && MERGED="$(find "$OUTDIR" -name cobertura.xml | head -1)"
[ -n "$MERGED" ] && [ -s "$MERGED" ] || { echo "bash adapter: no report produced" >&2; exit 4; }

# Adapters emit repo-relative reports (gate contract): kcov roots filenames at
# its --include-path, so rewrite them to be relative to the repo.
SRC="$(grep -o '<source>[^<]*</source>' "$MERGED" | head -1 | sed -e 's/<source>//' -e 's|</source>||')"
case "$SRC" in
  "$REPO"/*)
    REL="${SRC#"$REPO"/}"; REL="${REL%/}"
    [ -n "$REL" ] && sed -i -e "s|filename=\"|filename=\"$REL/|g" "$MERGED"
    ;;
esac
echo "$MERGED"
