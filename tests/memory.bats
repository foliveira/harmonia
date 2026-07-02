#!/usr/bin/env bats
# U4 memory tests - capture/recall over two tiers, written before the implementation.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HARMONIA_HOME="$BATS_TEST_TMPDIR/home"   # isolated global tier
  CAPTURE="$REPO_ROOT/bin/memory/capture.sh"
  RECALL="$REPO_ROOT/bin/memory/recall.sh"

  # A fixture Go project repo.
  GOREPO="$BATS_TEST_TMPDIR/gorepo"
  mkdir -p "$GOREPO"
  git -C "$GOREPO" init -q
  echo 'package main' > "$GOREPO/main.go"
  git -C "$GOREPO" add -A && git -C "$GOREPO" -c user.email=t@t -c user.name=t commit -qm x
}

cap() { # cap <title> <tier> <tags> [--client] <<< body
  bash "$CAPTURE" --title "$1" --tier "$2" --tags "$3" --repo "$GOREPO" "${@:4}"
}

@test "capturing a global learning creates the file and exactly one index line, idempotently" {
  echo "prefer table tests" | cap "Go table tests" global "go,testing"
  [ "$(ls "$HARMONIA_HOME/learnings" | wc -l)" -eq 1 ]
  [ "$(grep -c "Go table tests" "$HARMONIA_HOME/index.md")" -eq 1 ]
  echo "prefer table tests" | cap "Go table tests" global "go,testing"
  [ "$(grep -c "Go table tests" "$HARMONIA_HOME/index.md")" -eq 1 ]
}

@test "client-flagged content is refused for the global tier and accepted project-tier" {
  run bash -c "echo x | bash '$CAPTURE' --title 'Client secret sauce' --tier global --tags go --repo '$GOREPO' --client"
  [ "$status" -ne 0 ]
  [[ "$output" == *"client"* ]]
  run bash -c "echo x | bash '$CAPTURE' --title 'Client secret sauce' --tier project --tags go --repo '$GOREPO' --client"
  [ "$status" -eq 0 ]
  ls "$GOREPO/docs/learnings/" | grep -q "client-secret-sauce"
}

@test "recall in a Go repo returns the Go-tagged summary and omits the TypeScript one" {
  echo x | cap "Go pitfall" global "go,testing"
  echo x | cap "TS quirk" global "typescript"
  run bash "$RECALL" --repo "$GOREPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Go pitfall"* ]]
  [[ "$output" != *"TS quirk"* ]]
}

@test "recall respects the output budget and prefers recent entries" {
  for i in $(seq 1 40); do echo x | cap "Go learning $i" global "go"; done
  run bash "$RECALL" --repo "$GOREPO" --budget-lines 10
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -le 10 ]
  [[ "$output" == *"Go learning 40"* ]]
}

@test "recall surfaces a legacy docs/solutions entry read-only" {
  mkdir -p "$GOREPO/docs/solutions/testing"
  printf -- "---\ntitle: Legacy CE learning\ndate: 2026-01-01\nmodule: app\nproblem_type: bug\ncomponent: testing_framework\nseverity: low\n---\nbody\n" \
    > "$GOREPO/docs/solutions/testing/legacy-ce-learning.md"
  before="$(find "$GOREPO/docs/solutions" -type f | sort)"
  run bash "$RECALL" --repo "$GOREPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Legacy CE learning"* ]]
  after="$(find "$GOREPO/docs/solutions" -type f | sort)"
  [ "$before" = "$after" ]
}

@test "two concurrent captures leave a valid index with both entries" {
  (echo a | cap "Concurrent one" global "go") &
  (echo b | cap "Concurrent two" global "go") &
  wait
  grep -q "Concurrent one" "$HARMONIA_HOME/index.md"
  grep -q "Concurrent two" "$HARMONIA_HOME/index.md"
}

@test "recall tolerates a duplicated or torn index line, warning and continuing" {
  echo x | cap "Good entry" global "go"
  echo "half a torn lin" >> "$HARMONIA_HOME/index.md"
  dup="$(grep "Good entry" "$HARMONIA_HOME/index.md")"
  echo "$dup" >> "$HARMONIA_HOME/index.md"
  run bash "$RECALL" --repo "$GOREPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Good entry"* ]]
}

@test "a worktree of the same project yields the same repo identity" {
  git -C "$GOREPO" worktree add -q "$BATS_TEST_TMPDIR/wt" -b wt-branch
  id1="$(bash "$REPO_ROOT/bin/memory/store-lib.sh" repo-id "$GOREPO")"
  id2="$(bash "$REPO_ROOT/bin/memory/store-lib.sh" repo-id "$BATS_TEST_TMPDIR/wt")"
  [ -n "$id1" ]
  [ "$id1" = "$id2" ]
}

@test "a corrupted index fails open: recall returns empty with a warning, exit zero" {
  mkdir -p "$HARMONIA_HOME"
  head -c 64 /dev/urandom > "$HARMONIA_HOME/index.md"
  run bash "$RECALL" --repo "$GOREPO"
  [ "$status" -eq 0 ]
}
