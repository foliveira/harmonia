#!/usr/bin/env bats
# Unit tests for bin/coverage/config-lib.sh - the one reader of a repo's
# .harmonia/project.yaml. It is sourced, never executed, and exposes
# project_config <repo> <key> <default>. These cover every branch of the reader
# (absent file, absent key, unquoted/quoted/empty values, internal colons, and
# the colon-anchor that keeps a later key out of an earlier key's value) so the
# coverage gate does not flag the new lib's lines as uncovered.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO_ROOT/bin/coverage/config-lib.sh"
  R="$BATS_TEST_TMPDIR/target"
  mkdir -p "$R/.harmonia"
}

# Source the lib in a fresh subshell (proving sourced-not-executed) and echo
# project_config's result, so each test asserts the reader's contract in isolation.
pc() {  # pc <repo> <key> <default>
  bash -c '. "$1"; project_config "$2" "$3" "$4"' _ "$LIB" "$1" "$2" "$3"
}

@test "project_config returns the default when the project.yaml is absent" {
  [ ! -f "$R/.harmonia/project.yaml" ]
  [ "$(pc "$R" coverage FALLBACK)" = "FALLBACK" ]
}

@test "project_config returns the default when the key is absent from the file" {
  printf 'test: bats tests/\n' > "$R/.harmonia/project.yaml"
  [ "$(pc "$R" coverage FALLBACK)" = "FALLBACK" ]
}

@test "project_config returns an unquoted value verbatim over the default" {
  printf 'coverage: pytest --cov\n' > "$R/.harmonia/project.yaml"
  [ "$(pc "$R" coverage SHOULD-NOT-SEE)" = "pytest --cov" ]
}

@test "project_config strips one layer of surrounding double quotes" {
  printf 'coverage: "pytest --cov"\n' > "$R/.harmonia/project.yaml"
  [ "$(pc "$R" coverage SHOULD-NOT-SEE)" = "pytest --cov" ]
}

@test "project_config strips one layer of surrounding single quotes" {
  printf "coverage: 'pytest --cov'\n" > "$R/.harmonia/project.yaml"
  [ "$(pc "$R" coverage SHOULD-NOT-SEE)" = "pytest --cov" ]
}

@test "project_config returns the default when the key's value is empty" {
  printf 'coverage:\n' > "$R/.harmonia/project.yaml"
  [ "$(pc "$R" coverage EMPTYDEF)" = "EMPTYDEF" ]
}

@test "project_config preserves an internal colon in the value" {
  printf 'coverage: run --report=a:b\n' > "$R/.harmonia/project.yaml"
  [ "$(pc "$R" coverage SHOULD-NOT-SEE)" = "run --report=a:b" ]
}

@test "project_config anchors on the key so a later key is not read as an earlier key's value" {
  printf 'test: bats tests/\ncoverage: run cov\n' > "$R/.harmonia/project.yaml"
  # reading `test` returns exactly its own value, never the following coverage line
  [ "$(pc "$R" test SHOULD-NOT-SEE)" = "bats tests/" ]
  # and a non-first key is still read from its own anchored line
  [ "$(pc "$R" coverage SHOULD-NOT-SEE)" = "run cov" ]
}
