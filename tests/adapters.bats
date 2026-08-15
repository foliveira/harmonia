#!/usr/bin/env bats
# U7 adapter tests - tool-missing paths and full happy paths via fake toolchains,
# so adapter code is exercised (and kcov-traceable) without vitest/go installed.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # An adapter's output directory is its product: it prints a path inside it and
  # its caller reads the report, so it cannot delete it on the way out and the
  # CALLER owns the lifetime. Here the caller is this file, and these six
  # standalone invocations are the whole of what `bats tests/` leaves on /tmp -
  # measured at 5fe85ad: 4 directories per run (1 kcov, 2 tscov, 1 gocov) from
  # this file and 0 from tests/coverage.bats, whose gate invocations all supply
  # a report or hide the toolchain and so never reach an adapter's mktemp. /tmp
  # is tmpfs on the machine this was found on, so those are memory. Pointing
  # TMPDIR at the per-test directory bats already removes owns them without
  # constraining the adapter, which must keep working invoked bare.
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
  R="$BATS_TEST_TMPDIR/target"
  mkdir -p "$R"
  git -C "$R" init -q
  FAKE="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE"
}

@test "bash adapter exits cannot-measure when kcov is hidden" {
  run env HARMONIA_KCOV=/nonexistent-kcov bash "$REPO_ROOT/bin/coverage/bash.sh" --repo "$R"
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot measure"* ]]
}

@test "bash adapter produces a repo-relative report from a fake kcov run" {
  cat > "$FAKE/kcov" <<FAKEEOF
#!/usr/bin/env bash
# args: --include-path=<p> <outdir> <bats> <tests>
out="\$2"
mkdir -p "\$out/kcov-merged"
cat > "\$out/kcov-merged/cobertura.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="1.0" version="1.9" timestamp="1">
  <sources><source>REPOPATH/bin/</source></sources>
  <packages><package name="p" line-rate="1.0"><classes>
    <class name="x" filename="tool.sh" line-rate="1.0">
      <lines><line number="1" hits="1"/></lines>
    </class>
  </classes></package></packages>
</coverage>
XML
FAKEEOF
  sed -i "s|REPOPATH|$R|" "$FAKE/kcov"
  chmod +x "$FAKE/kcov"
  run env PATH="$FAKE:$PATH" bash "$REPO_ROOT/bin/coverage/bash.sh" --repo "$R"
  [ "$status" -eq 0 ]
  grep -q 'filename="bin/tool.sh"' "$output"
}

@test "ts adapter exits cannot-measure without vitest" {
  run bash "$REPO_ROOT/bin/coverage/ts.sh" --repo "$R"
  [ "$status" -eq 4 ]
}

@test "ts adapter returns the report a fake vitest produces" {
  cat > "$FAKE/npx" <<'FAKEEOF'
#!/usr/bin/env bash
outdir=""
for a in "$@"; do case "$a" in --coverage.reportsDirectory=*) outdir="${a#*=}" ;; esac; done
if [ -n "$outdir" ]; then
  mkdir -p "$outdir"
  echo '<coverage/>' > "$outdir/cobertura-coverage.xml"
fi
exit 0
FAKEEOF
  chmod +x "$FAKE/npx"
  run env PATH="$FAKE:$PATH" bash "$REPO_ROOT/bin/coverage/ts.sh" --repo "$R"
  [ "$status" -eq 0 ]
  [ -f "$output" ]
}

@test "ts adapter exits cannot-measure when vitest produces no report" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE/npx"
  chmod +x "$FAKE/npx"
  run env PATH="$FAKE:$PATH" bash "$REPO_ROOT/bin/coverage/ts.sh" --repo "$R"
  [ "$status" -eq 4 ]
  [[ "$output" == *"no report produced"* ]]
}

@test "go adapter exits cannot-measure without go" {
  run env HARMONIA_GO=/nonexistent-go bash "$REPO_ROOT/bin/coverage/go.sh" --repo "$R"
  [ "$status" -eq 4 ]
}

@test "go adapter strips the module prefix from a fake toolchain's report" {
  cat > "$FAKE/go" <<'FAKEEOF'
#!/usr/bin/env bash
case "$1" in
  list) echo "example.com/mod" ;;
  test) # emit a trivial coverprofile at the -coverprofile= path
    for a in "$@"; do case "$a" in -coverprofile=*) echo "mode: set" > "${a#-coverprofile=}" ;; esac; done ;;
esac
exit 0
FAKEEOF
  cat > "$FAKE/gocover-cobertura" <<'FAKEEOF'
#!/usr/bin/env bash
cat <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="1.0" version="1.9" timestamp="1">
  <packages><package name="p" line-rate="1.0"><classes>
    <class name="x" filename="example.com/mod/pkg/file.go" line-rate="1.0">
      <lines><line number="1" hits="1"/></lines>
    </class>
  </classes></package></packages>
</coverage>
XML
FAKEEOF
  chmod +x "$FAKE/go" "$FAKE/gocover-cobertura"
  run env PATH="$FAKE:$PATH" bash "$REPO_ROOT/bin/coverage/go.sh" --repo "$R"
  [ "$status" -eq 0 ]
  grep -q 'filename="pkg/file.go"' "$output"
  ! grep -q 'example.com/mod/pkg' "$output"
}
