#!/usr/bin/env bash
# Go coverage adapter: coverprofile converted to Cobertura (line-only; Go
# records statements, so branches stay unmeasured - KTD6).
# Prints the report path on success; exits 4 when the toolchain is missing.
set -u
REPO="." COV_OUT=""
while [ $# -gt 0 ]; do case "$1" in --repo) REPO="$2"; shift 2 ;; --out) COV_OUT="$2"; shift 2 ;; *) shift ;; esac; done

GO_BIN="${HARMONIA_GO:-go}"
CONV_BIN="${HARMONIA_GOCOVER:-gocover-cobertura}"
command -v "$GO_BIN" >/dev/null 2>&1 || { echo "go adapter: go not installed - cannot measure" >&2; exit 4; }
command -v "$CONV_BIN" >/dev/null 2>&1 || { echo "go adapter: gocover-cobertura not installed - cannot measure" >&2; exit 4; }

# Same contract as the other two adapters: the printed report sits inside this
# directory, so the caller owns the lifetime - --out is the gate's, and a bare
# invocation mints its own.
OUTDIR="${COV_OUT:-$(mktemp -d -t harmonia-gocov-XXXXXX)}"
( cd "$REPO" && "$GO_BIN" test ./... -coverprofile="$OUTDIR/go.out" >/dev/null 2>&1 \
    && "$CONV_BIN" < "$OUTDIR/go.out" > "$OUTDIR/go-cobertura.xml" )
[ -s "$OUTDIR/go-cobertura.xml" ] || { echo "go adapter: no report produced" >&2; exit 4; }

# Adapters emit repo-relative reports (gate contract): gocover-cobertura
# names files by Go import path, so strip the module prefix.
MOD="$(cd "$REPO" && "$GO_BIN" list -m 2>/dev/null)"
[ -n "$MOD" ] && sed -i "s|filename=\"$MOD/|filename=\"|g" "$OUTDIR/go-cobertura.xml"
echo "$OUTDIR/go-cobertura.xml"
