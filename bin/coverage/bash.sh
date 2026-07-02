#!/usr/bin/env bash
# Bash coverage adapter: kcov over the bats suite (line-only; kcov carries no
# branch records - KTD6). Prints the merged Cobertura path; exits 4 when kcov
# is missing.
set -u
REPO="."
while [ $# -gt 0 ]; do case "$1" in --repo) REPO="$2"; shift 2 ;; *) shift ;; esac; done

# Tool resolution is overridable so tests can simulate absence deterministically.
KCOV_BIN="${HARMONIA_KCOV:-kcov}"
BATS_BIN_NAME="${HARMONIA_BATS:-bats}"
command -v "$KCOV_BIN" >/dev/null 2>&1 || { echo "bash adapter: kcov not installed - cannot measure" >&2; exit 4; }
command -v "$BATS_BIN_NAME" >/dev/null 2>&1 || { echo "bash adapter: bats not installed - cannot measure" >&2; exit 4; }

OUTDIR="$(mktemp -d -t harmonia-kcov-XXXXXX)"
BATS_PATH="$(command -v "$BATS_BIN_NAME")"
"$KCOV_BIN" --include-path="$REPO/bin" "$OUTDIR" "$BATS_PATH" "$REPO/tests" >"$OUTDIR/kcov.log" 2>&1 || true
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
